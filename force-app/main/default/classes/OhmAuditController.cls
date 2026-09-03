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
                      AND Run_Status__c = 'Complete'
                    ORDER BY CreatedDate DESC, Id DESC
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

            // Wave 5 — capture the raw instructions (topic Scope / agent+action instructions)
            // behind each INSTRUCTION_BLOAT finding so the before/after diff can show pre-trim
            // text. Bulk-safe: build the map in memory, one DML update, no SOQL/DML in loop.
            captureInstructionSnapshots(graph, findings);
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

            // identity + domain via the cheap single-planner resolver (G12: no full-fleet scan)
            String key = String.valueOf(plannerId);
            OhmDTO.ProcessSummaryDTO ident = discovery.resolveIdentity(plannerId);
            if (ident != null) {
                detail.plannerApiName = ident.plannerApiName;
                detail.label = ident.label;
                detail.domain = ident.domain;
            }

            // latest process report → grade/score/energy + findings
            Agent_Audit_Report__c rep;
            for (Agent_Audit_Report__c r : [
                SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Total_Annual_Energy_Wh__c
                FROM Agent_Audit_Report__c
                WHERE Target_Type__c = 'Process' AND Target_Planner_Id__c = :key
                  AND Run_Status__c = 'Complete'
                ORDER BY CreatedDate DESC, Id DESC
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

    // ===================== Wave 4 Worklist (Findings + Recommendations) =====================

    /**
     * Wave 4 — the cross-fleet Findings worklist. Returns every waste finding de-duplicated
     * across re-audits: from PROCESS-scoped reports only the LATEST report per planner counts,
     * plus every Fleet-scoped report's findings; the surviving rows are de-duped by
     * (plannerApiName|artifactLabel|signal), keeping the newest. If a finding is linked to a
     * remediation Task, the Task is joined for assignee/due. Bulk-safe: one Finding query, one
     * Task query, mapped in memory. Ordered by savingsCentralWh desc.
     * statusFilter/severityFilter may be null or 'All' (no filter).
     */
    @AuraEnabled(cacheable=false)
    public static List<OhmDTO.WorklistItemDTO> getFindings(String statusFilter, String severityFilter) {
        try {
            // one bulk query. Process-scoped reports FIRST (so a process row wins over the fleet-scoped
            // copy of the same finding — better process label), then newest report first within each.
            List<Finding__c> rows = [
                SELECT Id, Signal_Type__c, Severity__c, Confidence__c, Artifact_Label__c,
                       Annual_Energy_Savings_Wh_Low__c, Annual_Energy_Savings_Wh__c, Annual_Energy_Savings_Wh_High__c,
                       Fix_Type__c, Recommended_Target__c, Recommendation_Text__c, Effort__c,
                       Finding_Status__c, Remediation_Task_Id__c, Parent_Agent_Api_Name__c,
                       Agent_Audit_Report__c, Agent_Audit_Report__r.Target_Type__c,
                       Agent_Audit_Report__r.Target_Planner_Id__c, Agent_Audit_Report__r.Target_Planner_Api_Name__c,
                       Agent_Audit_Report__r.CreatedDate
                FROM Finding__c
                ORDER BY Agent_Audit_Report__r.Target_Type__c DESC NULLS LAST, Agent_Audit_Report__r.CreatedDate DESC, CreatedDate DESC
            ];

            // pass 1: latest process report id per planner (rows are newest-first, so first wins)
            Map<String, Id> latestReportByPlanner = new Map<String, Id>();
            for (Finding__c f : rows) {
                Agent_Audit_Report__c rep = f.Agent_Audit_Report__r;
                if (rep == null || rep.Target_Type__c != 'Process') { continue; }
                String pk = rep.Target_Planner_Id__c;
                if (String.isBlank(pk)) { continue; }
                if (!latestReportByPlanner.containsKey(pk)) {
                    latestReportByPlanner.put(pk, f.Agent_Audit_Report__c);
                }
            }

            // pass 2: keep only latest-per-planner (Process) + all Fleet, then dedup newest-wins
            List<OhmDTO.WorklistItemDTO> items = new List<OhmDTO.WorklistItemDTO>();
            Set<String> seenKeys = new Set<String>();
            Set<String> taskIds = new Set<String>();
            for (Finding__c f : rows) {
                Agent_Audit_Report__c rep = f.Agent_Audit_Report__r;
                String plannerApiName = null;
                if (rep != null) {
                    if (rep.Target_Type__c == 'Process') {
                        String pk = rep.Target_Planner_Id__c;
                        if (String.isNotBlank(pk) && latestReportByPlanner.get(pk) != f.Agent_Audit_Report__c) {
                            continue; // stale re-audit
                        }
                        plannerApiName = rep.Target_Planner_Api_Name__c;
                    }
                }
                if (String.isBlank(plannerApiName)) { plannerApiName = f.Parent_Agent_Api_Name__c; }

                // Dedup on (planner + artifact label + signal), independent of which report scope
                // surfaced it — the same finding appears under both a Process report and the Fleet report
                // (same plannerApiName, so it still collapses). G6: the planner is IN the key so two
                // DIFFERENT planners that happen to share an artifact label + signal are NOT collapsed
                // (previously the second planner's finding vanished). Process-scoped rows are ordered first
                // (Target_Type DESC), so a process row wins and keeps its richer process label.
                String dedupKey = (String.isBlank(plannerApiName) ? '' : plannerApiName.toLowerCase())
                    + '|' + (f.Artifact_Label__c == null ? '' : f.Artifact_Label__c.toLowerCase())
                    + '|' + (f.Signal_Type__c == null ? '' : f.Signal_Type__c);
                if (seenKeys.contains(dedupKey)) { continue; }
                seenKeys.add(dedupKey);

                OhmDTO.WorklistItemDTO item = new OhmDTO.WorklistItemDTO();
                item.findingId = f.Id;
                item.signal = f.Signal_Type__c;
                item.severity = f.Severity__c;
                item.confidence = f.Confidence__c;
                item.plannerApiName = plannerApiName;
                item.processLabel = prettyProcessLabel(plannerApiName);
                item.artifactLabel = f.Artifact_Label__c;
                item.savingsCentralWh = f.Annual_Energy_Savings_Wh__c;
                item.savingsLowWh = f.Annual_Energy_Savings_Wh_Low__c;
                item.savingsHighWh = f.Annual_Energy_Savings_Wh_High__c;
                item.fixType = f.Fix_Type__c;
                item.recommendedTarget = f.Recommended_Target__c;
                item.recommendationText = f.Recommendation_Text__c;
                item.findingStatus = String.isBlank(f.Finding_Status__c) ? 'Open' : f.Finding_Status__c;
                item.effort = f.Effort__c;
                if (String.isNotBlank(f.Remediation_Task_Id__c)) {
                    item.taskId = (Id) f.Remediation_Task_Id__c;
                    taskIds.add(f.Remediation_Task_Id__c);
                }
                items.add(item);
            }

            // one Task query, joined in memory
            if (!taskIds.isEmpty()) {
                Map<Id, Task> taskById = new Map<Id, Task>([
                    SELECT Id, OwnerId, Owner.Name, ActivityDate FROM Task WHERE Id IN :taskIds
                ]);
                for (OhmDTO.WorklistItemDTO item : items) {
                    if (item.taskId == null) { continue; }
                    Task t = taskById.get(item.taskId);
                    if (t == null) { continue; }
                    item.assigneeId = t.OwnerId;
                    item.assigneeName = (t.Owner == null) ? null : t.Owner.Name;
                    item.dueDate = t.ActivityDate;
                }
            }

            // in-memory filters (applied post-dedup so the newest surviving row is judged)
            Boolean filterStatus = String.isNotBlank(statusFilter) && statusFilter != 'All';
            Boolean filterSeverity = String.isNotBlank(severityFilter) && severityFilter != 'All';
            List<OhmDTO.WorklistItemDTO> filtered = new List<OhmDTO.WorklistItemDTO>();
            for (OhmDTO.WorklistItemDTO item : items) {
                if (filterStatus && item.findingStatus != statusFilter) { continue; }
                if (filterSeverity && item.severity != severityFilter) { continue; }
                filtered.add(item);
            }

            sortBySavingsDesc(filtered);
            return filtered;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load findings: ' + e.getMessage());
        }
    }

    /**
     * Wave 4 — set Finding_Status__c (restricted: Open/Accepted/Dismissed/Applied). If a
     * remediation Task is linked, mirror its state: Accepted -> Task open (In Progress),
     * Dismissed/Applied -> Task Completed. Bulk-safe: one SOQL, one DML per object.
     */
    @AuraEnabled
    public static void updateFindingStatus(Id findingId, String status) {
        if (findingId == null || String.isBlank(status)) {
            throw new AuraHandledException('updateFindingStatus requires a findingId and status.');
        }
        try {
            Finding__c f = [
                SELECT Id, Remediation_Task_Id__c FROM Finding__c WHERE Id = :findingId LIMIT 1
            ];
            update new Finding__c(Id = findingId, Finding_Status__c = status);

            if (String.isNotBlank(f.Remediation_Task_Id__c)) {
                String taskStatus = null;
                if (status == 'Accepted') {
                    taskStatus = 'In Progress';
                } else if (status == 'Dismissed' || status == 'Applied') {
                    taskStatus = 'Completed';
                }
                if (taskStatus != null) {
                    update new Task(Id = (Id) f.Remediation_Task_Id__c, Status = taskStatus);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Could not update finding status: ' + e.getMessage());
        }
    }

    /**
     * Wave 4 — assign a finding: ensure a remediation Task exists (creating one via the SAME
     * OhmPersistenceService.createRemediationTask path the F8 door uses, which also writes
     * Remediation_Task_Id__c back), then set the Task owner + due date. Returns the Task Id.
     */
    @AuraEnabled
    public static Id assignFinding(Id findingId, Id userId, Date dueDate) {
        if (findingId == null) {
            throw new AuraHandledException('assignFinding requires a findingId.');
        }
        try {
            Finding__c f = [
                SELECT Id, Remediation_Task_Id__c, Fix_Type__c, Recommended_Target__c,
                       Recommendation_Text__c, Annual_Energy_Savings_Wh__c, Agent_Audit_Report__c
                FROM Finding__c WHERE Id = :findingId LIMIT 1
            ];

            Id taskId;
            if (String.isBlank(f.Remediation_Task_Id__c)) {
                OhmDTO.RemediationInputDTO input = new OhmDTO.RemediationInputDTO();
                input.findingId = f.Id;
                input.reportId = f.Agent_Audit_Report__c;
                input.fixType = f.Fix_Type__c;
                input.recommendedTarget = f.Recommended_Target__c;
                input.recommendationText = f.Recommendation_Text__c;
                input.estimatedSavingsCentralWh = f.Annual_Energy_Savings_Wh__c;
                taskId = new OhmPersistenceService().createRemediationTask(input);
            } else {
                taskId = (Id) f.Remediation_Task_Id__c;
            }

            Task t = new Task(Id = taskId);
            if (userId != null) { t.OwnerId = userId; }
            if (dueDate != null) { t.ActivityDate = dueDate; }
            update t;
            return taskId;
        } catch (Exception e) {
            throw new AuraHandledException('Could not assign finding: ' + e.getMessage());
        }
    }

    /**
     * Wave 4 — the Recommendations quick-wins view: the same de-duplicated worklist as
     * getFindings(null,null), limited to actionable items (status Open/Accepted), ranked by
     * savingsCentralWh / effortWeight desc (Low=1, Medium=2, High=3; default Low).
     */
    @AuraEnabled(cacheable=false)
    public static List<OhmDTO.WorklistItemDTO> getRecommendations() {
        try {
            List<OhmDTO.WorklistItemDTO> all = getFindings(null, null);
            List<OhmDTO.WorklistItemDTO> quickWins = new List<OhmDTO.WorklistItemDTO>();
            for (OhmDTO.WorklistItemDTO item : all) {
                if (item.findingStatus == 'Dismissed' || item.findingStatus == 'Applied') { continue; }
                quickWins.add(item);
            }
            sortByQuickWinDesc(quickWins);
            return quickWins;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load recommendations: ' + e.getMessage());
        }
    }

    // ===================== Wave 5 Trends + before/after diff (SPEC §2.5 / §2.6) =====================

    /**
     * Wave 5 — the Trends time series.
     * plannerId null  → ORG scope: every Fleet-scoped report as a point if any exist, else the
     *   latest-per-planner PROCESS reports as points; plus perAgent grade history (every process
     *   report per planner, chronological).
     * plannerId set   → that planner's PROCESS reports, chronological (oldest→newest).
     * realizedSavingsWh = max(0, firstEnergy - lastEnergy). Bulk-safe: at most two SOQL, mapped
     * in memory. Never returns null; points is always present (possibly empty).
     */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.TrendDTO getTrends(Id plannerId) {
        try {
            OhmDTO.TrendDTO dto = new OhmDTO.TrendDTO();
            dto.plannerId = plannerId;
            dto.points = new List<OhmDTO.TrendPointDTO>();
            dto.perAgent = new List<OhmDTO.AgentGradeHistoryDTO>();

            if (plannerId != null) {
                // per-process scope: this planner's process reports oldest→newest
                dto.scope = prettyProcessLabel(processApiNameFor(plannerId));
                for (Agent_Audit_Report__c r : [
                    SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Total_Annual_Energy_Wh__c,
                           Findings_Count__c, Run_Timestamp__c, CreatedDate, Target_Planner_Api_Name__c
                    FROM Agent_Audit_Report__c
                    WHERE Target_Type__c = 'Process'
                      AND Target_Planner_Id__c = :String.valueOf(plannerId)
                      AND Run_Status__c = 'Complete'
                    ORDER BY CreatedDate ASC, Id ASC
                ]) {
                    if (dto.scope == null && String.isNotBlank(r.Target_Planner_Api_Name__c)) {
                        dto.scope = prettyProcessLabel(r.Target_Planner_Api_Name__c);
                    }
                    dto.points.add(toTrendPoint(r));
                }
                stampEnergyBounds(dto);
                return dto;
            }

            // ---- ORG scope ----
            dto.scope = 'Org';
            // Fleet-scoped reports (org-wide runs) as points, if any exist
            for (Agent_Audit_Report__c r : [
                SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Total_Annual_Energy_Wh__c,
                       Findings_Count__c, Run_Timestamp__c, CreatedDate
                FROM Agent_Audit_Report__c
                WHERE Target_Type__c != 'Process' AND Run_Status__c = 'Complete'
                ORDER BY CreatedDate ASC, Id ASC
            ]) {
                dto.points.add(toTrendPoint(r));
            }

            // Process reports (oldest→newest) power the per-agent grade history, and — when there
            // are no Fleet reports — the org points fall back to the latest report per planner.
            List<Agent_Audit_Report__c> proc = [
                SELECT Id, Target_Planner_Id__c, Target_Planner_Api_Name__c, Efficiency_Grade__c,
                       Efficiency_Score__c, Total_Annual_Energy_Wh__c, Findings_Count__c,
                       Run_Timestamp__c, CreatedDate
                FROM Agent_Audit_Report__c
                WHERE Target_Type__c = 'Process' AND Run_Status__c = 'Complete'
                ORDER BY CreatedDate ASC, Id ASC
            ];

            // per-agent grade history, insertion-ordered by planner first-seen
            Map<String, OhmDTO.AgentGradeHistoryDTO> perAgentByPlanner =
                new Map<String, OhmDTO.AgentGradeHistoryDTO>();
            // latest process report per planner (rows ascending → last write wins)
            Map<String, Agent_Audit_Report__c> latestByPlanner =
                new Map<String, Agent_Audit_Report__c>();
            for (Agent_Audit_Report__c r : proc) {
                String pk = r.Target_Planner_Id__c;
                if (String.isBlank(pk)) { continue; }
                latestByPlanner.put(pk, r);
                OhmDTO.AgentGradeHistoryDTO h = perAgentByPlanner.get(pk);
                if (h == null) {
                    h = new OhmDTO.AgentGradeHistoryDTO();
                    h.plannerId = (Id) pk;
                    h.label = prettyProcessLabel(r.Target_Planner_Api_Name__c);
                    h.gradeHistory = new List<String>();
                    perAgentByPlanner.put(pk, h);
                }
                if (r.Efficiency_Grade__c != null) {
                    h.gradeHistory.add(r.Efficiency_Grade__c);
                    h.currentGrade = r.Efficiency_Grade__c;
                }
            }
            dto.perAgent = perAgentByPlanner.values();

            // fallback org points: no Fleet reports → latest-per-planner process reports, chronological
            if (dto.points.isEmpty() && !latestByPlanner.isEmpty()) {
                List<Agent_Audit_Report__c> latest = latestByPlanner.values();
                latest.sort(new ReportByCreatedAsc());
                for (Agent_Audit_Report__c r : latest) {
                    dto.points.add(toTrendPoint(r));
                }
            }

            stampEnergyBounds(dto);
            return dto;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load trends: ' + e.getMessage());
        }
    }

    /**
     * Wave 5 — before/after diff of the TWO most recent PROCESS reports for a planner
     * (before = 2nd-newest, after = newest). Fewer than two reports → afterReportId set,
     * beforeReportId null (LWC shows "Re-audit after a change to compare"). Instructions come
     * from Instructions_Snapshot__c on the newest INSTRUCTION_BLOAT finding of each report.
     * Bulk-safe: one report query, one findings query, mapped in memory.
     */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.DiffDTO getDiff(Id plannerId) {
        if (plannerId == null) {
            throw new AuraHandledException('getDiff requires a plannerId.');
        }
        try {
            List<Agent_Audit_Report__c> reps = [
                SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Total_Annual_Energy_Wh__c,
                       Findings_Count__c, Run_Timestamp__c, CreatedDate, Target_Planner_Api_Name__c
                FROM Agent_Audit_Report__c
                WHERE Target_Type__c = 'Process'
                  AND Target_Planner_Id__c = :String.valueOf(plannerId)
                  AND Run_Status__c = 'Complete'
                ORDER BY CreatedDate DESC, Id DESC
                LIMIT 2
            ];

            OhmDTO.DiffDTO dto = new OhmDTO.DiffDTO();
            dto.plannerId = plannerId;
            dto.label = prettyProcessLabel(processApiNameFor(plannerId));

            if (reps.isEmpty()) {
                return dto; // nothing audited yet
            }

            Agent_Audit_Report__c after = reps[0];
            dto.afterReportId = after.Id;
            dto.afterAt = whenOf(after);
            dto.afterGrade = after.Efficiency_Grade__c;
            dto.afterScore = intOrNull(after.Efficiency_Score__c);
            dto.afterEnergyWhCentral = after.Total_Annual_Energy_Wh__c;
            dto.afterFindings = intOrNull(after.Findings_Count__c);
            if (String.isBlank(dto.label) && String.isNotBlank(after.Target_Planner_Api_Name__c)) {
                dto.label = prettyProcessLabel(after.Target_Planner_Api_Name__c);
            }

            Set<Id> reportIds = new Set<Id>{ after.Id };
            if (reps.size() >= 2) {
                Agent_Audit_Report__c before = reps[1];
                dto.beforeReportId = before.Id;
                dto.beforeAt = whenOf(before);
                dto.beforeGrade = before.Efficiency_Grade__c;
                dto.beforeScore = intOrNull(before.Efficiency_Score__c);
                dto.beforeEnergyWhCentral = before.Total_Annual_Energy_Wh__c;
                dto.beforeFindings = intOrNull(before.Findings_Count__c);
                reportIds.add(before.Id);

                dto.energyDeltaWh = nz(dto.beforeEnergyWhCentral) - nz(dto.afterEnergyWhCentral);
                if (dto.beforeScore != null && dto.afterScore != null) {
                    dto.scoreDelta = dto.afterScore - dto.beforeScore;
                    dto.improved = dto.afterScore > dto.beforeScore;
                }
                if (dto.beforeFindings != null && dto.afterFindings != null) {
                    dto.findingsDelta = dto.afterFindings - dto.beforeFindings;
                }
            }

            // instructions snapshot from the newest bloat finding of each report (one SOQL)
            Map<Id, String> snapshotByReport = new Map<Id, String>();
            // NB: Instructions_Snapshot__c is a Long Text Area (not filterable in WHERE) — take the
            // newest non-blank snapshot per report in memory instead.
            for (Finding__c f : [
                SELECT Agent_Audit_Report__c, Instructions_Snapshot__c
                FROM Finding__c
                WHERE Agent_Audit_Report__c IN :reportIds
                  AND Signal_Type__c = :InstructionBloatDetector.SIGNAL
                ORDER BY CreatedDate DESC
            ]) {
                if (String.isBlank(f.Instructions_Snapshot__c)) { continue; }
                if (!snapshotByReport.containsKey(f.Agent_Audit_Report__c)) {
                    snapshotByReport.put(f.Agent_Audit_Report__c, f.Instructions_Snapshot__c);
                }
            }
            dto.afterInstructions = snapshotByReport.get(dto.afterReportId);
            if (dto.beforeReportId != null) {
                dto.beforeInstructions = snapshotByReport.get(dto.beforeReportId);
            }
            return dto;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load diff: ' + e.getMessage());
        }
    }

    // ===================== Wave 6 — "Ask Ohm" per-process assistant =====================

    /**
     * Opening context for the per-process assistant: grounding summary, chips, and
     * process-specific quick prompts. Cheap — never calls the model.
     */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.AssistantContextDTO getAssistantContext(Id plannerId) {
        return OhmAssistantService.getContext(plannerId);
    }

    /**
     * Answer one grounded question about a process through the Einstein Trust Layer.
     * A rewrite/trim request returns the drafted instructions plus a before→after readout.
     */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.AssistantReplyDTO askAssistant(Id plannerId, String question) {
        return OhmAssistantService.ask(plannerId, question);
    }

    // ---------- Wave 5 private helpers ----------

    /** Bulk-safe: write each INSTRUCTION_BLOAT finding's audited raw instructions to the snapshot. */
    private static void captureInstructionSnapshots(OhmDTO.AgentModel graph, List<OhmDTO.Finding> findings) {
        if (graph == null || findings == null || findings.isEmpty()) { return; }
        // instructions by tooling id, across every node type the bloat detector inspects
        Map<String, String> instructionsByToolingId = new Map<String, String>();
        if (graph.topics != null) {
            for (OhmDTO.TopicNode t : graph.topics) {
                if (t != null && t.id != null) { instructionsByToolingId.put(t.id, t.scope); }
            }
        }
        if (graph.agentsById != null) {
            for (OhmDTO.AgentNode a : graph.agentsById.values()) {
                if (a != null && a.id != null) {
                    instructionsByToolingId.put(a.id, joinInstructions(a.description, a.capabilities));
                }
            }
        }
        if (graph.actions != null) {
            for (OhmDTO.ActionNode a : graph.actions) {
                if (a != null && a.id != null) { instructionsByToolingId.put(a.id, a.description); }
            }
        }

        List<Finding__c> updates = new List<Finding__c>();
        for (OhmDTO.Finding f : findings) {
            if (f == null || f.findingRecordId == null) { continue; }
            if (f.signalType != InstructionBloatDetector.SIGNAL) { continue; }
            if (!instructionsByToolingId.containsKey(f.artifactToolingId)) { continue; }
            String raw = instructionsByToolingId.get(f.artifactToolingId);
            if (String.isBlank(raw)) { continue; }
            updates.add(new Finding__c(
                Id = f.findingRecordId,
                Instructions_Snapshot__c = raw.abbreviate(131072)
            ));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static OhmDTO.TrendPointDTO toTrendPoint(Agent_Audit_Report__c r) {
        OhmDTO.TrendPointDTO p = new OhmDTO.TrendPointDTO();
        p.reportId = r.Id;
        p.auditedAt = whenOf(r);
        p.grade = r.Efficiency_Grade__c;
        p.score = intOrNull(r.Efficiency_Score__c);
        p.energyWhCentral = r.Total_Annual_Energy_Wh__c;
        p.findingsCount = intOrNull(r.Findings_Count__c);
        return p;
    }

    /** first/last central energy + realizedSavings (max(0, first - last)) from the ordered points. */
    private static void stampEnergyBounds(OhmDTO.TrendDTO dto) {
        if (dto.points == null || dto.points.isEmpty()) { return; }
        dto.firstEnergyWhCentral = dto.points[0].energyWhCentral;
        dto.lastEnergyWhCentral = dto.points[dto.points.size() - 1].energyWhCentral;
        Decimal delta = nz(dto.firstEnergyWhCentral) - nz(dto.lastEnergyWhCentral);
        dto.realizedSavingsWh = (delta > 0) ? delta : 0;
    }

    /** Resolve a planner's process api name from its most recent process report (null if none). */
    private static String processApiNameFor(Id plannerId) {
        for (Agent_Audit_Report__c r : [
            SELECT Target_Planner_Api_Name__c
            FROM Agent_Audit_Report__c
            WHERE Target_Type__c = 'Process' AND Target_Planner_Id__c = :String.valueOf(plannerId)
              AND Run_Status__c = 'Complete'
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ]) {
            return r.Target_Planner_Api_Name__c;
        }
        return null;
    }

    private static Datetime whenOf(Agent_Audit_Report__c r) {
        return (r.Run_Timestamp__c != null) ? r.Run_Timestamp__c : r.CreatedDate;
    }

    private static Integer intOrNull(Decimal d) {
        return (d == null) ? null : Integer.valueOf(d);
    }

    private static Decimal nz(Decimal d) {
        return (d == null) ? 0 : d;
    }

    /** Chronological (CreatedDate asc) report comparator for in-memory ordering. */
    private class ReportByCreatedAsc implements System.Comparator<Agent_Audit_Report__c> {
        public Integer compare(Agent_Audit_Report__c a, Agent_Audit_Report__c b) {
            if (a == null || a.CreatedDate == null) { return -1; }
            if (b == null || b.CreatedDate == null) { return 1; }
            if (a.CreatedDate != b.CreatedDate) {
                return (a.CreatedDate < b.CreatedDate) ? -1 : 1;
            }
            // deterministic tie-break on Id so tied timestamps order identically everywhere
            if (a.Id == b.Id) { return 0; }
            return (a.Id < b.Id) ? -1 : 1;
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

    // ---------- Wave 4 private helpers ----------

    /** Prettify a planner api name into a human label ("Ohm_Waste_Demo" -> "Ohm Waste Demo"). */
    private static String prettyProcessLabel(String apiName) {
        if (String.isBlank(apiName)) { return 'Fleet'; }
        return apiName.replace('__c', '').replace('_', ' ').trim();
    }

    /** Effort -> quick-win divisor weight (Low=1, Medium=2, High=3; default Low). */
    private static Decimal effortWeight(String effort) {
        if (effort == 'High') { return 3; }
        if (effort == 'Medium') { return 2; }
        return 1;
    }

    private static void sortBySavingsDesc(List<OhmDTO.WorklistItemDTO> items) {
        if (items != null && items.size() > 1) {
            items.sort(new SavingsDescComparator());
        }
    }

    private static void sortByQuickWinDesc(List<OhmDTO.WorklistItemDTO> items) {
        if (items != null && items.size() > 1) {
            items.sort(new QuickWinComparator());
        }
    }

    /** Rank by savingsCentralWh desc (null == 0). */
    private class SavingsDescComparator implements System.Comparator<OhmDTO.WorklistItemDTO> {
        public Integer compare(OhmDTO.WorklistItemDTO a, OhmDTO.WorklistItemDTO b) {
            Decimal av = (a == null || a.savingsCentralWh == null) ? 0 : a.savingsCentralWh;
            Decimal bv = (b == null || b.savingsCentralWh == null) ? 0 : b.savingsCentralWh;
            if (av == bv) { return 0; }
            return (av > bv) ? -1 : 1;
        }
    }

    /** Rank by savingsCentralWh / effortWeight desc (quick wins first). */
    private class QuickWinComparator implements System.Comparator<OhmDTO.WorklistItemDTO> {
        public Integer compare(OhmDTO.WorklistItemDTO a, OhmDTO.WorklistItemDTO b) {
            Decimal av = ((a == null || a.savingsCentralWh == null) ? 0 : a.savingsCentralWh)
                / effortWeight(a == null ? null : a.effort);
            Decimal bv = ((b == null || b.savingsCentralWh == null) ? 0 : b.savingsCentralWh)
                / effortWeight(b == null ? null : b.effort);
            if (av == bv) { return 0; }
            return (av > bv) ? -1 : 1;
        }
    }
}
