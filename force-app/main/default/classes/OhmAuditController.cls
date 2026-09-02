/**
 * OhmAuditController — the unified @AuraEnabled door (SPEC §S.10, canon C5).
 * Sync pipeline: createReport → discover → saveDiscoveryGraph → analyze → footprint →
 * recommendations → rate → persistFindings → Complete. reportId == runId.
 * "One service, two doors": every method delegates to the same services the agent
 * actions call — the doors can never diverge.
 */
public with sharing class OhmAuditController {

    /** The full synchronous audit pipeline. Returns the reportId (== runId). */
    @AuraEnabled
    public static Id startAudit() {
        OhmPersistenceService persistence = new OhmPersistenceService();
        Id reportId = persistence.createReport();
        try {
            persistence.updateProgress(reportId, 'Discovering', 'Discovering agentic work', 10);
            OhmDTO.AgentModel graph = new OhmDiscoveryService().discover();
            persistence.saveDiscoveryGraph(reportId, graph);

            persistence.updateProgress(reportId, 'Analyzing', 'Running efficiency signals', 40);
            OhmSignalService signals = new OhmSignalService();
            List<OhmDTO.Finding> findings = signals.analyze(graph);

            persistence.updateProgress(reportId, 'Analyzing', 'Estimating footprint and savings', 70);
            OhmFootprintService footprint = new OhmFootprintService();
            OhmDTO.VolumeInput volume = new AssumptionVolumeProvider().defaultVolume();
            for (OhmDTO.Finding f : findings) {
                f.footprint = footprint.estimateForArtifact(f, volume);
            }
            // attachRecommendations fills fixType/recommendationText and savings (savingsFor)
            new OhmRecommendationService().attachRecommendations(findings);

            OhmDTO.EfficiencyResult rating = signals.rate(graph, findings);
            persistence.persistFindings(reportId, graph, findings, rating);
            persistence.updateProgress(reportId, 'Complete', 'Audit complete', 100);
            return reportId;
        } catch (Exception e) {
            try {
                persistence.updateProgress(reportId, 'Failed',
                    ('Audit failed: ' + e.getMessage()), 100);
            } catch (Exception ignored) {
                // best-effort failure stamp; surface the original error below
            }
            throw new AuraHandledException('Audit failed: ' + e.getMessage());
        }
    }

    /** Poll target: status during the run, the full readout once Complete. */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.AuditReadoutDTO getAuditStatus(Id reportId) {
        try {
            return new OhmPersistenceService().loadReadout(reportId);
        } catch (Exception e) {
            throw new AuraHandledException('Could not load audit status: ' + e.getMessage());
        }
    }

    /** F9 Calm Mode — read from the Ohm_Preferences__c hierarchy custom setting. */
    @AuraEnabled(cacheable=true)
    public static Boolean getCalmModePreference() {
        Ohm_Preferences__c prefs = Ohm_Preferences__c.getInstance(UserInfo.getUserId());
        return prefs != null && prefs.Calm_Mode__c == true;
    }

    /** F9 Calm Mode — persist at the current-user level of the hierarchy. */
    @AuraEnabled
    public static void setCalmModePreference(Boolean enabled) {
        try {
            Ohm_Preferences__c prefs = Ohm_Preferences__c.getValues(UserInfo.getUserId());
            if (prefs == null) {
                prefs = new Ohm_Preferences__c(SetupOwnerId = UserInfo.getUserId());
            }
            prefs.Calm_Mode__c = (enabled == true);
            upsert prefs;
        } catch (Exception e) {
            throw new AuraHandledException('Could not save Calm Mode preference: ' + e.getMessage());
        }
    }

    /** F8 — LWC door for remediation; same single service method as the agent door (C12). */
    @AuraEnabled
    public static Id createRemediationTask(OhmDTO.RemediationInputDTO input) {
        try {
            return new OhmPersistenceService().createRemediationTask(input);
        } catch (Exception e) {
            throw new AuraHandledException('Could not create remediation task: ' + e.getMessage());
        }
    }

    /** Aura twin of the EstimateFootprint action — per element, the ONE singular engine (C5). */
    @AuraEnabled
    public static List<OhmDTO.FootprintResponse> estimateFootprint(List<OhmDTO.FootprintRequest> reqs) {
        List<OhmDTO.FootprintResponse> responses = new List<OhmDTO.FootprintResponse>();
        if (reqs == null) {
            return responses;
        }
        OhmFootprintService footprint = new OhmFootprintService();
        for (OhmDTO.FootprintRequest req : reqs) {
            responses.add(footprint.estimate(req));
        }
        return responses;
    }

    // ===================== v2 Fleet Workbench (SPEC-ohm-v2 §4) =====================

    /**
     * v2 — the Fleet table. Cheap discovery (OhmDiscoveryService.listFleet, metadata only),
     * then ONE bulk SOQL over process-scoped reports to join the LATEST audit result per
     * planner (grade/score/energy/latestReportId/lastAudited) — mapped in memory, no SOQL in loop.
     * Processes never audited come back audited=false with null grade/energy.
     */
    @AuraEnabled(cacheable=false)
    public static List<OhmDTO.ProcessSummaryDTO> getFleet() {
        try {
            List<OhmDTO.ProcessSummaryDTO> fleet = new OhmDiscoveryService().listFleet();
            if (fleet == null) {
                return new List<OhmDTO.ProcessSummaryDTO>();
            }
            Set<String> plannerIds = new Set<String>();
            for (OhmDTO.ProcessSummaryDTO p : fleet) {
                if (p != null && p.plannerId != null) {
                    plannerIds.add(String.valueOf(p.plannerId));
                }
            }
            // one bulk SOQL, newest first; first row seen per planner == latest
            Map<String, Agent_Audit_Report__c> latestByPlanner = new Map<String, Agent_Audit_Report__c>();
            if (!plannerIds.isEmpty()) {
                for (Agent_Audit_Report__c r : [
                    SELECT Id, Target_Planner_Id__c, Efficiency_Grade__c, Efficiency_Score__c,
                           Total_Annual_Energy_Wh__c, Run_Timestamp__c, CreatedDate
                    FROM Agent_Audit_Report__c
                    WHERE Target_Type__c = 'Process'
                      AND Target_Planner_Id__c IN :plannerIds
                    ORDER BY CreatedDate DESC
                ]) {
                    if (!latestByPlanner.containsKey(r.Target_Planner_Id__c)) {
                        latestByPlanner.put(r.Target_Planner_Id__c, r);
                    }
                }
            }
            for (OhmDTO.ProcessSummaryDTO p : fleet) {
                if (p == null || p.plannerId == null) { continue; }
                Agent_Audit_Report__c r = latestByPlanner.get(String.valueOf(p.plannerId));
                if (r == null) {
                    p.audited = false;
                    continue;
                }
                p.audited = true;
                p.grade = r.Efficiency_Grade__c;
                p.score = (r.Efficiency_Score__c == null) ? null : Integer.valueOf(r.Efficiency_Score__c);
                p.energyWhCentral = r.Total_Annual_Energy_Wh__c;
                p.latestReportId = r.Id;
                p.lastAudited = r.Run_Timestamp__c;
            }
            return fleet;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load fleet: ' + e.getMessage());
        }
    }

    /**
     * v2 — deep audit of ONE process. Same engine the org-wide pipeline uses (C5: one service,
     * two doors): discoverProcess → analyze → per-finding footprint → recommendations → rate →
     * persist a PROCESS-scoped report tagged with the planner. Returns the report Id (== runId).
     */
    @AuraEnabled
    public static Id auditProcess(Id plannerId) {
        if (plannerId == null) {
            throw new AuraHandledException('auditProcess requires a plannerId.');
        }
        OhmPersistenceService persistence = new OhmPersistenceService();
        Id reportId;
        try {
            OhmDiscoveryService discovery = new OhmDiscoveryService();
            OhmDTO.AgentModel graph = discovery.discoverProcess(plannerId);

            String devName = null;
            if (graph != null && graph.agentsById != null) {
                OhmDTO.AgentNode agent = graph.agentsById.get(String.valueOf(plannerId));
                if (agent != null) {
                    devName = agent.developerName;
                }
            }

            reportId = persistence.createProcessReport(plannerId, devName);
            persistence.saveDiscoveryGraph(reportId, graph);

            OhmSignalService signals = new OhmSignalService();
            List<OhmDTO.Finding> findings = signals.analyze(graph);

            OhmFootprintService footprint = new OhmFootprintService();
            OhmDTO.VolumeInput volume = new AssumptionVolumeProvider().defaultVolume();
            for (OhmDTO.Finding f : findings) {
                f.footprint = footprint.estimateForArtifact(f, volume);
            }
            // attachRecommendations fills fixType/recommendationText and savings (savingsFor)
            new OhmRecommendationService().attachRecommendations(findings);

            OhmDTO.EfficiencyResult rating = signals.rate(graph, findings);
            persistence.persistFindings(reportId, graph, findings, rating);
            return reportId;
        } catch (Exception e) {
            if (reportId != null) {
                try {
                    persistence.updateProgress(reportId, 'Failed',
                        ('Audit failed: ' + e.getMessage()), 100);
                } catch (Exception ignored) {
                    // best-effort failure stamp
                }
            }
            throw new AuraHandledException('Process audit failed: ' + e.getMessage());
        }
    }

    /**
     * v2 — the process page payload: identity + domain (from the cheap fleet listing, which
     * owns the domain helper), latest process report's findings, and the node list
     * (agent/topic/action) with each node marked wasteful + signalType/severity by matching
     * findings to the artifact, instructions = topic Scope / agent instructions, tokenCount
     * via TokenEstimator. Never audited → nodes present, findings empty, grade/energy null.
     */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.ProcessDetailDTO getProcessDetail(Id plannerId) {
        if (plannerId == null) {
            throw new AuraHandledException('getProcessDetail requires a plannerId.');
        }
        try {
            OhmDiscoveryService discovery = new OhmDiscoveryService();
            OhmDTO.AgentModel graph = discovery.discoverProcess(plannerId);

            OhmDTO.ProcessDetailDTO detail = new OhmDTO.ProcessDetailDTO();
            detail.plannerId = plannerId;
            detail.findings = new List<OhmDTO.FindingDTO>();
            detail.nodes = new List<OhmDTO.NodeDTO>();

            // identity + domain from the cheap fleet listing (reuses the OhmDiscoveryService domain helper)
            String key = String.valueOf(plannerId);
            for (OhmDTO.ProcessSummaryDTO p : discovery.listFleet()) {
                if (p != null && p.plannerId != null && String.valueOf(p.plannerId) == key) {
                    detail.plannerApiName = p.plannerApiName;
                    detail.label = p.label;
                    detail.domain = p.domain;
                    break;
                }
            }

            // latest process report → grade/score/energy + findings
            Agent_Audit_Report__c rep;
            for (Agent_Audit_Report__c r : [
                SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Total_Annual_Energy_Wh__c
                FROM Agent_Audit_Report__c
                WHERE Target_Type__c = 'Process' AND Target_Planner_Id__c = :key
                ORDER BY CreatedDate DESC
                LIMIT 1
            ]) {
                rep = r;
            }

            Map<String, OhmDTO.FindingDTO> findingByToolingId = new Map<String, OhmDTO.FindingDTO>();
            Map<String, OhmDTO.FindingDTO> findingByTypeApi = new Map<String, OhmDTO.FindingDTO>();
            if (rep != null) {
                detail.reportId = rep.Id;
                detail.grade = rep.Efficiency_Grade__c;
                detail.score = (rep.Efficiency_Score__c == null) ? null : Integer.valueOf(rep.Efficiency_Score__c);
                detail.energyWhCentral = rep.Total_Annual_Energy_Wh__c;
                OhmDTO.AuditReadoutDTO readout = new OhmPersistenceService().loadReadout(rep.Id);
                if (readout != null && readout.findings != null) {
                    detail.findings = readout.findings;
                    for (OhmDTO.FindingDTO fd : readout.findings) {
                        if (fd == null) { continue; }
                        if (fd.targetArtifact != null && String.isNotBlank(fd.targetArtifact.toolingId)) {
                            findingByToolingId.put(fd.targetArtifact.toolingId, fd);
                        }
                        if (fd.artifactType != null && fd.targetArtifact != null
                                && String.isNotBlank(fd.targetArtifact.apiName)) {
                            findingByTypeApi.put(typeApiKey(fd.artifactType, fd.targetArtifact.apiName), fd);
                        }
                    }
                }
            }

            // nodes: agent → topics → actions (same AgentModel the detectors consume)
            if (graph != null) {
                if (graph.agentsById != null) {
                    for (OhmDTO.AgentNode a : graph.agentsById.values()) {
                        if (a == null) { continue; }
                        OhmDTO.NodeDTO n = new OhmDTO.NodeDTO();
                        n.id = a.id;
                        n.nodeType = 'Agent';
                        n.apiName = a.developerName;
                        n.label = a.masterLabel;
                        n.parentId = null;
                        n.instructions = joinInstructions(a.description, a.capabilities);
                        n.tokenCount = TokenEstimator.approxTokens(n.instructions);
                        applyFindingToNode(n, findingByToolingId, findingByTypeApi);
                        detail.nodes.add(n);
                    }
                }
                if (graph.topics != null) {
                    for (OhmDTO.TopicNode t : graph.topics) {
                        if (t == null) { continue; }
                        OhmDTO.NodeDTO n = new OhmDTO.NodeDTO();
                        n.id = t.id;
                        n.nodeType = 'Topic';
                        n.apiName = t.developerName;
                        n.label = t.masterLabel;
                        n.parentId = t.plannerId;
                        n.instructions = t.scope;
                        n.tokenCount = TokenEstimator.approxTokens(t.scope);
                        applyFindingToNode(n, findingByToolingId, findingByTypeApi);
                        detail.nodes.add(n);
                    }
                }
                if (graph.actions != null) {
                    for (OhmDTO.ActionNode a : graph.actions) {
                        if (a == null) { continue; }
                        OhmDTO.NodeDTO n = new OhmDTO.NodeDTO();
                        n.id = a.id;
                        n.nodeType = 'Action';
                        n.apiName = a.developerName;
                        n.label = a.masterLabel;
                        n.parentId = (a.pluginId != null) ? a.pluginId : a.plannerId;
                        n.invocationTargetType = a.invocationTargetType;
                        n.instructions = a.description;
                        n.tokenCount = TokenEstimator.approxTokens(a.description);
                        applyFindingToNode(n, findingByToolingId, findingByTypeApi);
                        detail.nodes.add(n);
                    }
                }
            }
            return detail;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load process detail: ' + e.getMessage());
        }
    }

    // ---------- v2 private helpers ----------

    /** Mark a node wasteful (+ signalType/severity) by matching a finding on tooling id, then type|apiName. */
    private static void applyFindingToNode(OhmDTO.NodeDTO n,
            Map<String, OhmDTO.FindingDTO> byToolingId, Map<String, OhmDTO.FindingDTO> byTypeApi) {
        OhmDTO.FindingDTO match = null;
        if (n.id != null && byToolingId.containsKey(n.id)) {
            match = byToolingId.get(n.id);
        } else if (n.nodeType != null && n.apiName != null) {
            match = byTypeApi.get(typeApiKey(n.nodeType, n.apiName));
        }
        if (match != null) {
            n.wasteful = true;
            n.signalType = match.signal;
            n.severity = match.severity;
        } else {
            n.wasteful = false;
        }
    }

    private static String typeApiKey(String artifactType, String apiName) {
        return (artifactType == null ? '' : artifactType.toLowerCase())
            + '|' + (apiName == null ? '' : apiName.toLowerCase());
    }

    private static String joinInstructions(String a, String b) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(a)) { parts.add(a); }
        if (String.isNotBlank(b)) { parts.add(b); }
        return parts.isEmpty() ? null : String.join(parts, '\n\n');
    }
}
