/**
 * OhmAuditController — the unified @AuraEnabled door (SPEC §S.10, canon C5).
 * Async pipeline: createReport → retrieve published source → validate → analyze → footprint →
 * recommendations → rate → persistFindings → Complete. reportId == runId.
 * "One service, two doors": every method delegates to the same services the agent
 * actions call — the doors can never diverge.
 */
public with sharing class OhmAuditController {

    /** Queue an org-wide audit. Returns the durable reportId (== runId) before acquisition starts. */
    @AuraEnabled
    public static Id startAudit() {
        try {
            Id reportId = new OhmPersistenceService().createReport();
            OhmAuditCoordinator.enqueue(reportId);
            return reportId;
        } catch (Exception ex) {
            throw new AuraHandledException('Could not start audit: ' + ex.getMessage());
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

    /** Primitive LWC parameters avoid inner-class Aura input deserialization limitations.
     * Recommendation content and report ownership are always read from the persisted finding.
     */
    @AuraEnabled
    public static Id createFindingRemediationTask(Id findingId, String note) {
        if (findingId == null) { throw new AuraHandledException('A saved finding is required to create a remediation Task.'); }
        try {
            Finding__c finding = [
                SELECT Id, Agent_Audit_Report__c, Fix_Type__c, Recommended_Target__c,
                       Recommendation_Text__c, Annual_Energy_Savings_Wh__c
                FROM Finding__c WHERE Id = :findingId LIMIT 1
            ];
            OhmDTO.RemediationInputDTO input = new OhmDTO.RemediationInputDTO();
            input.findingId = finding.Id;
            input.reportId = finding.Agent_Audit_Report__c;
            input.fixType = finding.Fix_Type__c;
            input.recommendedTarget = finding.Recommended_Target__c;
            input.recommendationText = finding.Recommendation_Text__c;
            input.estimatedSavingsCentralWh = finding.Annual_Energy_Savings_Wh__c;
            input.note = note;
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
                           Modeled_Energy_Wh__c, Modeled_Energy_Wh_Low__c, Modeled_Energy_Wh_High__c, Impact_Snapshot__c,
                           Coverage_Status__c, Run_Timestamp__c, CreatedDate, Review_Summary__c
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
                p.grade = r.Coverage_Status__c == 'Complete' ? r.Efficiency_Grade__c : 'IN';
                p.score = (r.Coverage_Status__c != 'Complete' || r.Efficiency_Score__c == null) ? null : Integer.valueOf(r.Efficiency_Score__c);
                p.energyWhCentral = r.Modeled_Energy_Wh__c;
                p.latestReportId = r.Id;
                p.reviewJson = r.Review_Summary__c;
                p.energyWhLow = r.Modeled_Energy_Wh_Low__c;
                p.energyWhHigh = r.Modeled_Energy_Wh_High__c;
                OhmAuditImpactService.applyBands(p, r.Impact_Snapshot__c);
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
        if (plannerId == null) throw new AuraHandledException('auditProcess requires a plannerId.');
        try {
            OhmDTO.ProcessSummaryDTO identity = new OhmDiscoveryService().resolveIdentity(plannerId);
            if (identity == null) throw new AuraHandledException('Published planner is unavailable. Refresh the fleet.');
            if (!OhmDiscoveryService.isAgentScriptCandidate(identity.plannerApiName)) {
                throw new OhmDiscoveryService.AuditScopeException(OhmDiscoveryService.AGENT_SCRIPT_SCOPE_MESSAGE);
            }
            Id reportId = new OhmPersistenceService().createProcessReport(plannerId, identity.plannerApiName);
            OhmAuditCoordinator.enqueue(reportId);
            return reportId;
        } catch (Exception ex) {
            throw new AuraHandledException('Could not start process audit: ' + ex.getMessage());
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
            detail.coverageStatus = graph.coverageComplete == true ? 'Complete' : 'Incomplete';
            detail.coverageWarnings = new List<String>();
            detail.coverageWarnings.addAll(graph.coverageWarnings);
            detail.coverageWarnings.addAll(graph.discoveryErrors);
            detail.detectorCoverage = graph.detectorCoverage;
            detail.sourceCurrent = true;

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
                SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Modeled_Energy_Wh__c,
                       Modeled_Energy_Wh_Low__c, Modeled_Energy_Wh_High__c, Impact_Snapshot__c, Coverage_Status__c,
                       Discovery_Graph_Json__c, Review_Result__c
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
                detail.reviewJson = rep.Review_Result__c;
                detail.grade = rep.Efficiency_Grade__c;
                detail.score = (rep.Efficiency_Score__c == null) ? null : Integer.valueOf(rep.Efficiency_Score__c);
                detail.energyWhCentral = rep.Modeled_Energy_Wh__c;
                detail.energyWhLow = rep.Modeled_Energy_Wh_Low__c;
                detail.energyWhHigh = rep.Modeled_Energy_Wh_High__c;
                detail.impactScope = OhmAuditImpactService.SCOPE;
                if (String.isNotBlank(rep.Impact_Snapshot__c)) {
                    OhmAuditImpactService.Snapshot impact = OhmAuditImpactService.readSnapshot(rep.Impact_Snapshot__c);
                    detail.impactAssumptions = impact.assumptionSummary;
                    OhmAuditImpactService.applyBands(detail, rep.Impact_Snapshot__c);
                }
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
                        n.instructions = a.instructions;
                        n.artifactKey = OhmPersistenceService.artifactKey(OhmPersistenceService.logicalProcessKey(a.developerName, a.id), 'Agent', a.developerName, null);
                        n.sourceKind = a.sourceKind; n.sourceVersion = a.sourceVersion;
                        n.sourceHash = a.sourceHash; n.sourcePath = a.sourcePath;
                        n.sourceApiName = a.sourceApiName; n.sourceVersionIdentifier = a.sourceVersionIdentifier;
                        n.sourceRetrievedAt = a.sourceRetrievedAt; n.sourceBindingVerified = a.sourceBindingVerified;
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
                        n.artifactKey = OhmPersistenceService.artifactKey(OhmPersistenceService.logicalProcessKey(detail.plannerApiName, key), 'Topic', t.developerName, null);
                        n.sourceKind = t.sourceKind; n.sourceVersion = t.sourceVersion;
                        n.sourceHash = t.sourceHash; n.sourcePath = t.sourcePath;
                        n.sourceApiName = t.sourceApiName; n.sourceVersionIdentifier = t.sourceVersionIdentifier;
                        n.sourceRetrievedAt = t.sourceRetrievedAt; n.sourceBindingVerified = t.sourceBindingVerified;
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
                        n.instructions = a.instructions;
                        n.artifactKey = OhmPersistenceService.artifactKey(OhmPersistenceService.logicalProcessKey(detail.plannerApiName, key), 'Action', a.developerName, null);
                        n.sourceKind = a.sourceKind; n.sourceVersion = a.sourceVersion;
                        n.sourceHash = a.sourceHash; n.sourcePath = a.sourcePath;
                        n.sourceApiName = a.sourceApiName; n.sourceVersionIdentifier = a.sourceVersionIdentifier;
                        n.sourceRetrievedAt = a.sourceRetrievedAt; n.sourceBindingVerified = a.sourceBindingVerified;
                        n.tokenCount = TokenEstimator.approxTokens(n.instructions);
                        applyFindingToNode(n, findingByToolingId, findingByTypeApi);
                        detail.nodes.add(n);
                    }
                }
            }
            if (rep != null) {
                Map<String, Audit_Artifact_Snapshot__c> snapshots = OhmPersistenceService.loadSnapshots(new Set<Id>{rep.Id}).get(rep.Id);
                for (OhmDTO.NodeDTO node : detail.nodes) {
                    if (node.instructions == null) continue;
                    Audit_Artifact_Snapshot__c prior = snapshots == null ? null : snapshots.get(node.artifactKey);
                    String currentHash = OhmPersistenceService.sha256(node.instructions);
                    if (prior == null || prior.Source_Hash__c != currentHash) detail.sourceCurrent = false;
                }
                if (String.isNotBlank(rep.Discovery_Graph_Json__c)) {
                    OhmDTO.AgentModel priorGraph = (OhmDTO.AgentModel) JSON.deserialize(rep.Discovery_Graph_Json__c, OhmDTO.AgentModel.class);
                    if (priorGraph.metadataFingerprint != graph.metadataFingerprint) detail.sourceCurrent = false;
                }
                if (!detail.sourceCurrent) {
                    detail.reviewJson = null;
                    detail.coverageWarnings.add('Source changed since this audit. Re-audit before using its findings, estimates or a rewrite.');
                    detail.coverageStatus = 'Incomplete';
                    detail.grade = 'IN'; detail.score = null; detail.energyWhCentral = null;
                    detail.energyWhLow = null; detail.energyWhHigh = null;
                    detail.findings.clear();
                    for (OhmDTO.NodeDTO node : detail.nodes) { node.wasteful = false; node.signalType = null; node.severity = null; }
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
            // Select reports first: a clean report has no child rows but still supersedes old work.
            Map<String, Id> latestReportByProcess = new Map<String, Id>();
            Id latestFleetReport;
            for (Agent_Audit_Report__c report : [
                SELECT Id, Target_Type__c, Target_Planner_Id__c, Target_Planner_Api_Name__c
                FROM Agent_Audit_Report__c WHERE Run_Status__c = 'Complete'
                ORDER BY Run_Timestamp__c DESC NULLS LAST, CreatedDate DESC, Id DESC
            ]) {
                if (report.Target_Type__c == 'Process') {
                    String key = OhmPersistenceService.logicalProcessKey(report.Target_Planner_Api_Name__c, report.Target_Planner_Id__c);
                    if (String.isNotBlank(key) && !latestReportByProcess.containsKey(key)) {
                        latestReportByProcess.put(key, report.Id);
                    }
                } else if (latestFleetReport == null) { latestFleetReport = report.Id; }
            }
            List<Finding__c> rows = [
                SELECT Id, Signal_Type__c, Severity__c, Confidence__c, Artifact_Label__c, Artifact_Api_Name__c,
                       Artifact_Type__c, Parent_Topic_Api_Name__c, Process_Key__c, Artifact_Key__c, Issue_Key__c,
                       Annual_Energy_Savings_Wh_Low__c, Annual_Energy_Savings_Wh__c, Annual_Energy_Savings_Wh_High__c,
                       Fix_Type__c, Recommended_Target__c, Recommendation_Text__c, Effort__c,
                       Finding_Status__c, Remediation_Task_Id__c, Parent_Agent_Api_Name__c,
                       Agent_Audit_Report__c, Agent_Audit_Report__r.Target_Type__c,
                       Agent_Audit_Report__r.Target_Planner_Id__c, Agent_Audit_Report__r.Target_Planner_Api_Name__c
                FROM Finding__c WHERE Agent_Audit_Report__r.Run_Status__c = 'Complete'
                ORDER BY Agent_Audit_Report__r.Target_Type__c DESC NULLS LAST,
                         Agent_Audit_Report__r.Run_Timestamp__c DESC NULLS LAST,
                         Agent_Audit_Report__r.CreatedDate DESC, CreatedDate DESC, Id DESC
            ];
            // Compatibility for historic reports without stable keys: retain the last linked
            // Task while the latest report governs whether the issue still exists.
            Map<String, Finding__c> legacyState = new Map<String, Finding__c>();
            for (Finding__c row : rows) {
                String key = OhmRemediationLifecycle.keyOf(row);
                if (String.isBlank(row.Issue_Key__c) && String.isNotBlank(row.Remediation_Task_Id__c)
                    && !legacyState.containsKey(key)) { legacyState.put(key, row); }
            }
            List<OhmDTO.WorklistItemDTO> items = new List<OhmDTO.WorklistItemDTO>();
            Set<String> seenKeys = new Set<String>();
            Set<Id> taskIds = new Set<Id>();
            for (Finding__c row : rows) {
                String processKey = OhmRemediationLifecycle.processOf(row);
                Id authoritativeReport = latestReportByProcess.get(processKey);
                if (authoritativeReport != null && authoritativeReport != row.Agent_Audit_Report__c) { continue; }
                if (authoritativeReport == null && row.Agent_Audit_Report__r.Target_Type__c != 'Process'
                    && row.Agent_Audit_Report__c != latestFleetReport) { continue; }
                String key = OhmRemediationLifecycle.keyOf(row);
                if (seenKeys.contains(key)) { continue; }
                seenKeys.add(key);
                Finding__c state = row;
                if (String.isBlank(row.Issue_Key__c) && String.isBlank(row.Remediation_Task_Id__c)
                    && legacyState.containsKey(key)) { state = legacyState.get(key); }
                String plannerName = row.Agent_Audit_Report__r.Target_Type__c == 'Process'
                    ? row.Agent_Audit_Report__r.Target_Planner_Api_Name__c : row.Parent_Agent_Api_Name__c;
                OhmDTO.WorklistItemDTO item = new OhmDTO.WorklistItemDTO();
                item.findingId = row.Id;
                item.signal = row.Signal_Type__c;
                item.severity = row.Severity__c;
                item.confidence = row.Confidence__c;
                item.plannerApiName = plannerName;
                item.processLabel = prettyProcessLabel(plannerName);
                item.artifactLabel = row.Artifact_Label__c;
                item.savingsCentralWh = row.Annual_Energy_Savings_Wh__c;
                item.savingsLowWh = row.Annual_Energy_Savings_Wh_Low__c;
                item.savingsHighWh = row.Annual_Energy_Savings_Wh_High__c;
                item.fixType = row.Fix_Type__c;
                item.recommendedTarget = row.Recommended_Target__c;
                item.recommendationText = row.Recommendation_Text__c;
                item.findingStatus = String.isBlank(state.Finding_Status__c) ? 'Open' : state.Finding_Status__c;
                item.effort = row.Effort__c;
                item.taskId = OhmRemediationLifecycle.taskIdOf(state.Remediation_Task_Id__c);
                if (item.taskId != null) { taskIds.add(item.taskId); }
                items.add(item);
            }
            Map<Id, Task> tasks = new Map<Id, Task>();
            if (!taskIds.isEmpty()) {
                tasks = new Map<Id, Task>([SELECT Id, OwnerId, Owner.Name, ActivityDate, IsClosed, Status FROM Task WHERE Id IN :taskIds]);
            }
            List<OhmDTO.WorklistItemDTO> filtered = new List<OhmDTO.WorklistItemDTO>();
            for (OhmDTO.WorklistItemDTO item : items) {
                Task task = tasks.get(item.taskId);
                if (task != null) {
                    item.assigneeId = task.OwnerId;
                    item.assigneeName = task.Owner == null ? null : task.Owner.Name;
                    item.dueDate = task.ActivityDate;
                    if (task.IsClosed && item.findingStatus != 'Dismissed') { item.findingStatus = 'Applied'; }
                    else if (task.Status == 'In Progress' && item.findingStatus == 'Open') { item.findingStatus = 'Accepted'; }
                }
                if (String.isNotBlank(statusFilter) && statusFilter != 'All' && item.findingStatus != statusFilter) { continue; }
                if (String.isNotBlank(severityFilter) && severityFilter != 'All' && item.severity != severityFilter) { continue; }
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
        if (findingId == null || !new Set<String>{ 'Open', 'Accepted', 'Dismissed', 'Applied' }.contains(status)) {
            throw new AuraHandledException('A finding and valid status are required.');
        }
        try {
            Finding__c finding = [SELECT Id, Issue_Key__c, Remediation_Task_Id__c FROM Finding__c WHERE Id = :findingId LIMIT 1 FOR UPDATE];
            List<Finding__c> linked = new List<Finding__c>{ finding };
            if (String.isNotBlank(finding.Issue_Key__c)) {
                linked = [SELECT Id, Remediation_Task_Id__c FROM Finding__c WHERE Issue_Key__c = :finding.Issue_Key__c FOR UPDATE];
            }
            Map<Id, Task> updates = new Map<Id, Task>();
            List<Finding__c> statusUpdates = new List<Finding__c>();
            for (Finding__c row : linked) {
                statusUpdates.add(new Finding__c(Id = row.Id, Finding_Status__c = status,
                    Rec_Status__c = status == 'Open' ? 'Proposed' : status));
                Id taskId = OhmRemediationLifecycle.taskIdOf(row.Remediation_Task_Id__c);
                if (taskId != null) {
                    updates.put(taskId, new Task(Id = taskId,
                        Status = status == 'Open' ? 'Not Started' : status == 'Accepted' ? 'In Progress' : 'Completed'));
                }
            }
            update statusUpdates;
            if (!updates.isEmpty()) { update updates.values(); }
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
        if (findingId == null) { throw new AuraHandledException('assignFinding requires a findingId.'); }
        try {
            Finding__c finding = [
                SELECT Id, Fix_Type__c, Recommended_Target__c, Recommendation_Text__c,
                       Annual_Energy_Savings_Wh__c, Agent_Audit_Report__c
                FROM Finding__c WHERE Id = :findingId LIMIT 1
            ];
            OhmDTO.RemediationInputDTO input = new OhmDTO.RemediationInputDTO();
            input.findingId = finding.Id;
            input.reportId = finding.Agent_Audit_Report__c;
            input.fixType = finding.Fix_Type__c;
            input.recommendedTarget = finding.Recommended_Target__c;
            input.recommendationText = finding.Recommendation_Text__c;
            input.estimatedSavingsCentralWh = finding.Annual_Energy_Savings_Wh__c;
            Id taskId = new OhmPersistenceService().createRemediationTask(input);
            Task task = new Task(Id = taskId, ActivityDate = dueDate);
            if (userId != null) { task.OwnerId = userId; }
            update task;
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

    /** Historical modeled scenarios, grouped by exact logical process across publication IDs.
     * Org points contain only fleet audits. Versioned process history never fabricates a fleet
     * time series or applies an old grade to a new unaudited version. Reductions require matching
     * workload assumptions; the displayed values are modeled, not measured runtime usage.
     */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.TrendDTO getTrends(Id plannerId) {
        try {
            OhmDTO.TrendDTO dto = new OhmDTO.TrendDTO();
            dto.plannerId = plannerId;
            dto.points = new List<OhmDTO.TrendPointDTO>();
            dto.perAgent = new List<OhmDTO.AgentGradeHistoryDTO>();
            dto.realizedSavingsWh = 0;
            String firstImpact;
            String lastImpact;

            if (plannerId != null) {
                // Publication creates new planner IDs; history belongs to the logical process.
                // This does not apply old report grades to the newly published Fleet row.
                String plannerKey = String.valueOf(plannerId);
                String processName = processApiNameFor(plannerId);
                if (String.isBlank(processName)) {
                    OhmDTO.ProcessSummaryDTO identity = new OhmDiscoveryService().resolveIdentity(plannerId);
                    processName = identity == null ? null : identity.plannerApiName;
                }
                String logicalKey = OhmPersistenceService.logicalProcessKey(processName, plannerKey);
                String candidatePrefix = logicalKey + '_v%';
                dto.scope = prettyProcessLabel(processName);
                for (Agent_Audit_Report__c r : [
                    SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Modeled_Energy_Wh__c, Impact_Snapshot__c,
                           Findings_Count__c, Run_Timestamp__c, CreatedDate, Target_Planner_Api_Name__c,
                           Target_Planner_Id__c
                    FROM Agent_Audit_Report__c
                    WHERE Target_Type__c = 'Process'
                      AND (Target_Planner_Id__c = :plannerKey OR Target_Planner_Api_Name__c = :logicalKey
                           OR Target_Planner_Api_Name__c LIKE :candidatePrefix)
                      AND Run_Status__c = 'Complete'
                    ORDER BY CreatedDate ASC, Id ASC
                ]) {
                    if (OhmPersistenceService.logicalProcessKey(r.Target_Planner_Api_Name__c, r.Target_Planner_Id__c) != logicalKey) { continue; }
                    if (dto.scope == null && String.isNotBlank(r.Target_Planner_Api_Name__c)) {
                        dto.scope = prettyProcessLabel(r.Target_Planner_Api_Name__c);
                    }
                    if (r.Modeled_Energy_Wh__c != null) {
                        dto.points.add(toTrendPoint(r));
                        if (firstImpact == null) firstImpact = r.Impact_Snapshot__c;
                        lastImpact = r.Impact_Snapshot__c;
                    }
                }
                stampEnergyBounds(dto);
                if (!OhmAuditImpactService.comparable(firstImpact, lastImpact)) dto.realizedSavingsWh = 0;
                return dto;
            }

            // ---- ORG scope ----
            dto.scope = 'Org';
            // Fleet-scoped reports (org-wide runs) as points, if any exist
            for (Agent_Audit_Report__c r : [
                SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Modeled_Energy_Wh__c, Impact_Snapshot__c,
                       Findings_Count__c, Run_Timestamp__c, CreatedDate
                FROM Agent_Audit_Report__c
                WHERE Target_Type__c != 'Process' AND Run_Status__c = 'Complete'
                ORDER BY CreatedDate ASC, Id ASC
            ]) {
                if (r.Modeled_Energy_Wh__c != null) {
                        dto.points.add(toTrendPoint(r));
                        if (firstImpact == null) firstImpact = r.Impact_Snapshot__c;
                        lastImpact = r.Impact_Snapshot__c;
                    }
            }

            // Process reports power logical-process history only; they never become fleet points.
            List<Agent_Audit_Report__c> proc = [
                SELECT Id, Target_Planner_Id__c, Target_Planner_Api_Name__c, Efficiency_Grade__c,
                       Efficiency_Score__c, Modeled_Energy_Wh__c, Impact_Snapshot__c, Findings_Count__c,
                       Run_Timestamp__c, CreatedDate
                FROM Agent_Audit_Report__c
                WHERE Target_Type__c = 'Process' AND Run_Status__c = 'Complete'
                ORDER BY CreatedDate ASC, Id ASC
            ];

            // per-agent grade history, insertion-ordered by planner first-seen
            Map<String, OhmDTO.AgentGradeHistoryDTO> perAgentByPlanner =
                new Map<String, OhmDTO.AgentGradeHistoryDTO>();
            for (Agent_Audit_Report__c r : proc) {
                String pk = OhmPersistenceService.logicalProcessKey(r.Target_Planner_Api_Name__c, r.Target_Planner_Id__c);
                if (String.isBlank(pk)) { continue; }
                OhmDTO.AgentGradeHistoryDTO h = perAgentByPlanner.get(pk);
                if (h == null) {
                    h = new OhmDTO.AgentGradeHistoryDTO();
                    h.label = prettyProcessLabel(r.Target_Planner_Api_Name__c);
                    h.gradeHistory = new List<String>();
                    perAgentByPlanner.put(pk, h);
                }
                if (String.isNotBlank(r.Target_Planner_Id__c)) { h.plannerId = (Id) r.Target_Planner_Id__c; }
                h.label = prettyProcessLabel(r.Target_Planner_Api_Name__c);
                if (r.Efficiency_Grade__c != null) {
                    h.gradeHistory.add(r.Efficiency_Grade__c);
                    h.currentGrade = r.Efficiency_Grade__c;
                }
            }
            dto.perAgent = perAgentByPlanner.values();

            // Different processes are not successive measurements of the org.

            stampEnergyBounds(dto);
                if (!OhmAuditImpactService.comparable(firstImpact, lastImpact)) dto.realizedSavingsWh = 0;
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
        return lifecycleDiff(plannerId, null);
    }

    /** Compare the explicitly selected artifact across the same process's published versions. */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.DiffDTO getArtifactDiff(Id plannerId, String artifactKey) {
        return lifecycleDiff(plannerId, artifactKey);
    }

    private static OhmDTO.DiffDTO lifecycleDiff(Id plannerId, String requestedArtifactKey) {
        if (plannerId == null) { throw new AuraHandledException('getDiff requires a plannerId.'); }
        try {
            List<Agent_Audit_Report__c> reports = [
                SELECT Id, Efficiency_Grade__c, Efficiency_Score__c, Modeled_Energy_Wh__c,
                       Impact_Snapshot__c, Findings_Count__c, Run_Timestamp__c, CreatedDate,
                       Target_Planner_Id__c, Target_Planner_Api_Name__c
                FROM Agent_Audit_Report__c WHERE Target_Type__c = 'Process' AND Run_Status__c = 'Complete'
                ORDER BY Run_Timestamp__c DESC NULLS LAST, CreatedDate DESC, Id DESC
            ];
            String processKey;
            for (Agent_Audit_Report__c report : reports) {
                if (report.Target_Planner_Id__c == String.valueOf(plannerId)) {
                    processKey = OhmPersistenceService.logicalProcessKey(report.Target_Planner_Api_Name__c, report.Target_Planner_Id__c);
                    break;
                }
            }
            List<Agent_Audit_Report__c> selected = new List<Agent_Audit_Report__c>();
            if (String.isNotBlank(processKey)) {
                for (Agent_Audit_Report__c report : reports) {
                    if (OhmPersistenceService.logicalProcessKey(report.Target_Planner_Api_Name__c, report.Target_Planner_Id__c) == processKey) {
                        selected.add(report);
                        if (selected.size() == 2) { break; }
                    }
                }
            }
            OhmDTO.DiffDTO dto = new OhmDTO.DiffDTO();
            dto.plannerId = plannerId;
            dto.comparable = false;
            dto.improved = false;
            dto.comparisonReason = 'Re-audit the same process after a change to compare.';
            if (selected.isEmpty()) { return dto; }
            Agent_Audit_Report__c after = selected[0];
            dto.label = prettyProcessLabel(after.Target_Planner_Api_Name__c);
            dto.afterReportId = after.Id;
            dto.afterAt = whenOf(after);
            dto.afterGrade = after.Efficiency_Grade__c;
            dto.afterScore = intOrNull(after.Efficiency_Score__c);
            dto.afterEnergyWhCentral = after.Modeled_Energy_Wh__c;
            dto.afterFindings = intOrNull(after.Findings_Count__c);
            Set<Id> ids = new Set<Id>{ after.Id };
            if (selected.size() > 1) {
                Agent_Audit_Report__c before = selected[1];
                dto.beforeReportId = before.Id;
                dto.beforeAt = whenOf(before);
                dto.beforeGrade = before.Efficiency_Grade__c;
                dto.beforeScore = intOrNull(before.Efficiency_Score__c);
                dto.beforeEnergyWhCentral = before.Modeled_Energy_Wh__c;
                dto.beforeFindings = intOrNull(before.Findings_Count__c);
                ids.add(before.Id);
            }
            Map<Id, Map<String, Audit_Artifact_Snapshot__c>> snapshots = OhmPersistenceService.loadSnapshots(ids);
            Map<String, Audit_Artifact_Snapshot__c> afterByKey = snapshots.get(dto.afterReportId);
            Map<String, Audit_Artifact_Snapshot__c> beforeByKey = snapshots.get(dto.beforeReportId);
            if (afterByKey == null) { afterByKey = new Map<String, Audit_Artifact_Snapshot__c>(); }
            if (beforeByKey == null) { beforeByKey = new Map<String, Audit_Artifact_Snapshot__c>(); }
            String artifactKey = requestedArtifactKey;
            if (String.isBlank(artifactKey)) {
                List<String> common = new List<String>();
                List<String> changed = new List<String>();
                for (String key : afterByKey.keySet()) {
                    if (afterByKey.get(key).Coverage_Status__c != 'Complete' || !beforeByKey.containsKey(key)
                        || beforeByKey.get(key).Coverage_Status__c != 'Complete') { continue; }
                    common.add(key);
                    if (afterByKey.get(key).Source_Hash__c != beforeByKey.get(key).Source_Hash__c) { changed.add(key); }
                }
                if (changed.size() == 1) { artifactKey = changed[0]; }
                else if (common.size() == 1) { artifactKey = common[0]; }
                else { dto.comparisonReason = 'Select one artifact with source evidence in both reports.'; }
            }
            dto.artifactKey = artifactKey;
            Audit_Artifact_Snapshot__c beforeSource = beforeByKey.get(artifactKey);
            Audit_Artifact_Snapshot__c afterSource = afterByKey.get(artifactKey);
            if (beforeSource != null) { dto.beforeInstructions = beforeSource.Instructions__c; dto.beforeHash = beforeSource.Source_Hash__c; }
            if (afterSource != null) {
                dto.afterInstructions = afterSource.Instructions__c;
                dto.afterHash = afterSource.Source_Hash__c;
                dto.artifactLabel = afterSource.Artifact_Label__c;
            }
            if (dto.beforeReportId == null) { return dto; }
            if (beforeSource == null || afterSource == null || beforeSource.Coverage_Status__c != 'Complete'
                || afterSource.Coverage_Status__c != 'Complete') {
                dto.comparisonReason = 'The same artifact needs complete source snapshots in both reports.';
                return dto;
            }
            if (!OhmAuditImpactService.comparable(selected[1].Impact_Snapshot__c, after.Impact_Snapshot__c)) {
                dto.comparisonReason = 'Modeled workload, volume, model or methodology differs, or modeled evidence is unavailable.';
                return dto;
            }
            dto.comparable = true;
            dto.comparisonReason = 'Same artifact and modeled workload assumptions; values are estimates, not measured usage.';
            if (dto.beforeEnergyWhCentral != null && dto.afterEnergyWhCentral != null) {
                dto.energyDeltaWh = dto.beforeEnergyWhCentral - dto.afterEnergyWhCentral;
                dto.improved = dto.energyDeltaWh > 0;
            }
            if (dto.beforeScore != null && dto.afterScore != null) { dto.scoreDelta = dto.afterScore - dto.beforeScore; }
            if (dto.beforeFindings != null && dto.afterFindings != null) { dto.findingsDelta = dto.afterFindings - dto.beforeFindings; }
            return dto;
        } catch (Exception e) { throw new AuraHandledException('Could not load diff: ' + e.getMessage()); }
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

    @AuraEnabled(cacheable=false)
    public static OhmDTO.AssistantContextDTO getArtifactAssistantContext(Id plannerId, String artifactKey) {
        return OhmAssistantService.getArtifactContext(plannerId, artifactKey);
    }

    @AuraEnabled
    public static OhmDTO.AssistantReplyDTO askArtifactAssistant(Id plannerId, String artifactKey,
            String expectedSourceHash, String question, Boolean calmMode) {
        return OhmAssistantService.askArtifact(plannerId, artifactKey, expectedSourceHash, question, calmMode);
    }

    // ---------- Wave 5 private helpers ----------

    private static OhmDTO.TrendPointDTO toTrendPoint(Agent_Audit_Report__c r) {
        OhmDTO.TrendPointDTO p = new OhmDTO.TrendPointDTO();
        p.reportId = r.Id;
        p.auditedAt = whenOf(r);
        p.grade = r.Efficiency_Grade__c;
        p.score = intOrNull(r.Efficiency_Score__c);
        p.energyWhCentral = r.Modeled_Energy_Wh__c;
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
