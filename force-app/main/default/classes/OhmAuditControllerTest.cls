/** Readout/Task/controller regressions use completed report fixtures from the shared engine.
 * The asynchronous acquisition/queued endpoint contract is verified by OhmAuditCoordinatorTest.
 */
@IsTest
private class OhmAuditControllerTest {

    // ---------- startAudit: full pipeline against live discovery data ----------

    @IsTest(SeeAllData=true) // GenAiPlannerDefinition/GenAiPluginDefinition/GenAiFunctionDefinition are org metadata rows
    static void testStartAuditReturnsCompleteReportWithReadout() {
        Test.startTest();
        Id reportId = OhmAuditTestSupport.startAudit();
        Test.stopTest();

        System.assertNotEquals(null, reportId, 'startAudit must return the reportId (== runId)');

        OhmDTO.AuditReadoutDTO dto = OhmAuditController.getAuditStatus(reportId);
        System.assertNotEquals(null, dto, 'readout must load');
        System.assertEquals(reportId, dto.reportId);
        System.assertEquals('Complete', dto.runStatus, 'shared deterministic pipeline must finish Complete');
        System.assertEquals(100, dto.percentComplete);
        System.assert(dto.agentsDiscovered >= 1,
            'live spike agent (Ohm_Spike_Agent) must be discovered; got ' + dto.agentsDiscovered);
        System.assert(dto.actionsDiscovered >= 1,
            'live spike apex action must be discovered; got ' + dto.actionsDiscovered);
        System.assertEquals('IN', dto.efficiencyGrade, 'Unknown runtime/model coverage is explicitly incomplete.');
        System.assertEquals(null, dto.efficiencyScore, 'Incomplete coverage withholds the numeric score.');
        System.assertEquals(false, dto.telemetryBacked, 'modeled figures are disclosed as non-telemetry');
        System.assertNotEquals(null, dto.findings, 'findings list always present (possibly empty)');
        System.assertNotEquals(null, dto.assumptions, 'assumptions disclosed (F10)');
        System.assertNotEquals(null, dto.volumeAssumption, 'volume scenario disclosed');

        // the graph was persisted for agent re-entrancy (C11)
        Agent_Audit_Report__c rep = [
            SELECT Discovery_Graph_Json__c, Run_Status__c FROM Agent_Audit_Report__c WHERE Id = :reportId
        ];
        System.assertEquals('Complete', rep.Run_Status__c);
        System.assertNotEquals(null, rep.Discovery_Graph_Json__c, 'Discovery_Graph_Json__c saved');
    }

    // ---------- getAuditStatus during a run ----------

    @IsTest
    static void testGetAuditStatusReflectsInProgressReport() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        svc.updateProgress(reportId, 'Analyzing', 'Running efficiency signals', 40);

        Test.startTest();
        OhmDTO.AuditReadoutDTO dto = OhmAuditController.getAuditStatus(reportId);
        Test.stopTest();

        System.assertEquals('Analyzing', dto.runStatus);
        System.assertEquals('Running efficiency signals', dto.stageMessage);
        System.assertEquals(40, dto.percentComplete);
        System.assertEquals(0, dto.findings.size(), 'no findings persisted yet');
    }

    @IsTest
    static void testGetAuditStatusBadIdThrowsAuraHandled() {
        Boolean threw = false;
        Id bogus = Id.valueOf(
            Agent_Audit_Report__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA');
        try {
            OhmAuditController.getAuditStatus(bogus);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'a non-existent reportId surfaces as AuraHandledException');
    }

    // ---------- Calm Mode round-trip (F9) ----------

    @IsTest
    static void testCalmModePreferenceRoundTrip() {
        System.assertEquals(false, OhmAuditController.getCalmModePreference(),
            'default is calm-mode OFF');

        Test.startTest();
        OhmAuditController.setCalmModePreference(true);
        System.assertEquals(true, OhmAuditController.getCalmModePreference(),
            'set(true) then get must return true');
        OhmAuditController.setCalmModePreference(false);
        System.assertEquals(false, OhmAuditController.getCalmModePreference(),
            'set(false) then get must return false');
        Test.stopTest();

        Ohm_Preferences__c stored = Ohm_Preferences__c.getValues(UserInfo.getUserId());
        System.assertNotEquals(null, stored, 'a user-level hierarchy record was written');
        System.assertEquals(false, stored.Calm_Mode__c);
    }

    // ---------- createRemediationTask door (C12) ----------

    @IsTest
    static void testCreateRemediationTaskDoorDelegatesToPersistence() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        Finding__c row = new Finding__c(
            Agent_Audit_Report__c = reportId,
            Signal_Type__c = 'INSTRUCTION_BLOAT',
            Severity__c = 'High',
            Confidence__c = 'High',
            Artifact_Type__c = 'Topic',
            Artifact_Api_Name__c = 'Ohm_Fixture_LeadTriage',
            Fix_Type__c = 'Trim_Instructions',
            Recommendation_Text__c = 'Trim the topic scope to about 500 tokens.',
            Generated_By__c = 'Deterministic'
        );
        insert row;

        OhmDTO.RemediationInputDTO input = new OhmDTO.RemediationInputDTO();
        input.findingId = row.Id;
        input.reportId = reportId;
        input.fixType = 'Trim_Instructions';
        input.recommendedTarget = '500 tokens';
        input.recommendationText = 'Trim the topic scope to about 500 tokens.';
        input.estimatedSavingsCentralWh = 1234.5;

        Test.startTest();
        Id taskId = OhmAuditController.createRemediationTask(input);
        Test.stopTest();

        System.assertNotEquals(null, taskId);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Id = :taskId]);
        System.assertEquals((String) taskId,
            [SELECT Remediation_Task_Id__c FROM Finding__c WHERE Id = :row.Id].Remediation_Task_Id__c);
    }

    @IsTest
    static void testPrimitiveTaskDoorUsesSavedEvidenceAndPreservesAssignment() {
        Id reportId = new OhmPersistenceService().createReport();
        Finding__c finding = new Finding__c(
            Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
            Fix_Type__c = 'Trim_Instructions', Recommended_Target__c = '500 tokens',
            Recommendation_Text__c = 'Keep the weather conditions and remove repeated prose.',
            Annual_Energy_Savings_Wh__c = 321, Generated_By__c = 'Deterministic'
        );
        insert finding;
        Id taskId = OhmAuditController.createFindingRemediationTask(finding.Id, 'Review against the published source.');
        Task task = [SELECT WhatId, Description, OwnerId FROM Task WHERE Id = :taskId];
        System.assertEquals(reportId, task.WhatId);
        System.assert(task.Description.contains(finding.Recommendation_Text__c));
        System.assert(task.Description.contains('Estimated annual energy savings (central): 321'));
        System.assert(task.Description.contains('Review against the published source.'));
        Date due = Date.today().addDays(10);
        update new Task(Id = taskId, ActivityDate = due, Status = 'In Progress');
        System.assertEquals(taskId, OhmAuditController.createFindingRemediationTask(finding.Id, null));
        task = [SELECT OwnerId, ActivityDate, Status FROM Task WHERE Id = :taskId];
        System.assertEquals(UserInfo.getUserId(), task.OwnerId);
        System.assertEquals(due, task.ActivityDate);
        System.assertEquals('In Progress', task.Status);
    }

    // ---------- estimateFootprint aura twin (C5: per-element singular engine) ----------

    @IsTest
    static void testEstimateFootprintPerElement() {
        OhmDTO.FootprintRequest req = new OhmDTO.FootprintRequest();
        req.tokensPerInference = 750;
        req.annualCalls = 109500;

        Test.startTest();
        List<OhmDTO.FootprintResponse> out =
            OhmAuditController.estimateFootprint(new List<OhmDTO.FootprintRequest>{ req, req });
        Test.stopTest();

        System.assertEquals(2, out.size(), 'one response per request');
        System.assert(out[0].energyWhCentral > 0, 'central energy computed');
        System.assert(out[0].energyWhLow <= out[0].energyWhCentral
            && out[0].energyWhCentral <= out[0].energyWhHigh, 'band ordering Low<=Central<=High');
        System.assertEquals(false, out[0].telemetryBacked);
        System.assertEquals('Low', out[0].confidence);
        System.assertNotEquals(null, out[0].assumptions, 'assumptions disclosed (F10)');
        System.assertEquals(out[0].energyWhCentral, out[1].energyWhCentral,
            'identical requests give identical (deterministic) responses');

        System.assertEquals(0, OhmAuditController.estimateFootprint(null).size(),
            'null input degrades to an empty list');
    }

    // ========================= v2 Fleet Workbench (SPEC-ohm-v2 §4) =========================

    /** Current Agent Script publication; completed-report helper supplies synthetic bloat. */
    private static Id wastePlannerId() {
        return OhmAuditTestSupport.scriptPlannerId();
    }

    @IsTest(SeeAllData=true)
    static void testLegacyPlannerCannotQueueAnAuditOrAppearInAcquisition() {
        GenAiPlannerDefinition legacy = [SELECT Id FROM GenAiPlannerDefinition
            WHERE DeveloperName = 'Ohm_Waste_Demo' LIMIT 1];
        Integer reportCount = [SELECT COUNT() FROM Agent_Audit_Report__c];
        Boolean rejected = false;
        try {
            OhmAuditController.auditProcess(legacy.Id);
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Direct entry must reject legacy planners before enqueueing work.');
        System.assertEquals(reportCount, [SELECT COUNT() FROM Agent_Audit_Report__c], 'Rejected targets create no report.');
        OhmDTO.AgentModel scoped = new OhmDiscoveryService().discoverForRetrieval(legacy.Id);
        System.assertEquals(0, scoped.agentsById.size());
        System.assert(scoped.discoveryErrors[0].contains('Agent Script bundles only'));
        OhmDTO.AgentModel orgWide = new OhmDiscoveryService().discoverForRetrieval(null);
        System.assert(!orgWide.agentsById.containsKey(String.valueOf(legacy.Id)));
        System.assertEquals(null, rowFor(OhmAuditController.getFleet(), legacy.Id));
    }

    private static OhmDTO.ProcessSummaryDTO rowFor(List<OhmDTO.ProcessSummaryDTO> fleet, Id plannerId) {
        String key = String.valueOf(plannerId);
        for (OhmDTO.ProcessSummaryDTO p : fleet) {
            if (p != null && p.plannerId != null && String.valueOf(p.plannerId) == key) {
                return p;
            }
        }
        return null;
    }

    // ---------- getFleet: cheap discovery, unaudited before any process audit ----------

    @IsTest(SeeAllData=true)
    static void testGetFleetReturnsUnauditedFleet() {
        Test.startTest();
        List<OhmDTO.ProcessSummaryDTO> fleet = OhmAuditController.getFleet();
        Test.stopTest();

        System.assertNotEquals(null, fleet, 'getFleet must never return null');
        System.assert(!fleet.isEmpty(), 'live org has agents; fleet must be non-empty');

        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');
        OhmDTO.ProcessSummaryDTO waste = rowFor(fleet, wasteId);
        System.assertNotEquals(null, waste, 'the Weather fixture process must appear in the fleet');
        System.assertNotEquals(null, waste.plannerApiName, 'apiName populated by listFleet');
        System.assertNotEquals(null, waste.label, 'label populated by listFleet');
        System.assertNotEquals(null, waste.domain, 'domain derived by listFleet');
        System.assert(waste.topicCount != null && waste.topicCount >= 1,
            'Weather fixture has at least one topic; got ' + waste.topicCount);

        // audited=false when no PROCESS-scoped report has been committed for this planner
        Integer committed = [
            SELECT COUNT() FROM Agent_Audit_Report__c
            WHERE Target_Type__c = 'Process' AND Target_Planner_Id__c = :String.valueOf(wasteId)
        ];
        if (committed == 0) {
            System.assertEquals(false, waste.audited, 'unaudited process reports audited=false');
            System.assertEquals(null, waste.grade, 'no grade before a process audit');
            System.assertEquals(null, waste.latestReportId, 'no report id before a process audit');
        }
    }

    // ---------- auditProcess: process-scoped report, fleet then shows grade F ----------

    @IsTest(SeeAllData=true)
    static void testAuditProcessPersistsScopedReportAndFleetReflectsGrade() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        Test.startTest();
        Id reportId = OhmAuditTestSupport.auditProcess(wasteId);
        Test.stopTest();

        System.assertNotEquals(null, reportId, 'auditProcess returns the report Id (== runId)');

        Agent_Audit_Report__c rep = [
            SELECT Id, Target_Type__c, Target_Planner_Id__c, Target_Planner_Api_Name__c,
                   Run_Status__c, Efficiency_Grade__c, Coverage_Status__c, Efficiency_Score__c
            FROM Agent_Audit_Report__c WHERE Id = :reportId
        ];
        System.assertEquals('Process', rep.Target_Type__c, 'report is process-scoped');
        System.assertEquals(String.valueOf(wasteId), rep.Target_Planner_Id__c, 'report tagged with planner id');
        System.assertNotEquals(null, rep.Target_Planner_Api_Name__c, 'report tagged with planner api name');
        System.assertEquals('Complete', rep.Run_Status__c, 'completed report fixture finishes Complete');
        System.assertEquals('IN', rep.Efficiency_Grade__c, 'Known bloat does not fill missing runtime/model coverage.');
        System.assertEquals('Incomplete', rep.Coverage_Status__c);
        System.assertEquals(null, rep.Efficiency_Score__c);

        // re-called getFleet joins the latest process report → audited, grade F
        List<OhmDTO.ProcessSummaryDTO> fleet = OhmAuditController.getFleet();
        OhmDTO.ProcessSummaryDTO waste = rowFor(fleet, wasteId);
        System.assertNotEquals(null, waste, 'waste process still in fleet');
        System.assertEquals(true, waste.audited, 'process now shows audited');
        System.assertEquals('IN', waste.grade, 'fleet row reflects incomplete coverage.');
        System.assertEquals(reportId, waste.latestReportId, 'fleet row points at the latest report');
        System.assertNotEquals(null, waste.lastAudited, 'lastAudited stamped');
        // The footprint strip needs the requests/year behind the modeled figures, never a bare number.
        System.assertNotEquals(null, waste.impactFactors, 'fleet rows disclose the modeling constants');
        if (waste.energyWhCentral != null) {
            System.assert(waste.annualCalls > 0, 'a modeled footprint carries the requests/year it assumed');
            System.assertNotEquals(null, waste.co2eGCentral, 'CO2e travels with energy');
            System.assertNotEquals(null, waste.waterMlCentral, 'water travels with energy');
            System.assertNotEquals(null, waste.energyWhHigh, 'the band travels with the central figure');
        }
        OhmDTO.ProcessDetailDTO detail = OhmAuditController.getProcessDetail(wasteId);
        System.assertNotEquals(null, detail.impactFactors, 'detail discloses the modeling constants');
        if (detail.energyWhCentral != null) {
            System.assert(detail.annualCalls > 0, 'detail carries the requests/year it assumed');
            System.assertNotEquals(null, detail.co2eGCentral);
        }
    }

    // ---------- getProcessDetail: nodes with the bloated topic marked wasteful ----------

    @IsTest(SeeAllData=true)
    static void testGetProcessDetailMarksBloatedTopicWasteful() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        Test.startTest();
        OhmAuditTestSupport.auditProcess(wasteId);           // findings must exist to mark nodes
        OhmDTO.ProcessDetailDTO detail = OhmAuditController.getProcessDetail(wasteId);
        Test.stopTest();

        System.assertNotEquals(null, detail, 'detail must load');
        System.assertEquals(String.valueOf(wasteId), String.valueOf(detail.plannerId));
        System.assertNotEquals(null, detail.domain, 'domain populated');
        System.assertNotEquals(null, detail.reportId, 'latest process report joined in');
        System.assertEquals('IN', detail.grade, 'process detail carries incomplete coverage.');
        System.assertEquals('Incomplete', detail.coverageStatus);
        System.assert(!detail.coverageWarnings.isEmpty(), 'The missing evidence is disclosed.');
        System.assert(detail.nodes != null && !detail.nodes.isEmpty(), 'node list built from discoverProcess');

        // find the synthetic bloat topic node (by name, else the first wasteful topic)
        OhmDTO.NodeDTO triage;
        for (OhmDTO.NodeDTO n : detail.nodes) {
            if (n == null || n.nodeType != 'Topic') { continue; }
            String hay = ((n.label == null ? '' : n.label) + ' ' + (n.apiName == null ? '' : n.apiName)).toLowerCase();
            if (hay.contains('triage')) { triage = n; break; }
        }
        if (triage == null) {
            for (OhmDTO.NodeDTO n : detail.nodes) {
                if (n != null && n.nodeType == 'Topic' && n.wasteful == true) { triage = n; break; }
            }
        }
        System.assertNotEquals(null, triage, 'the synthetic bloat topic node must be present');
        System.assertEquals(true, triage.wasteful, 'the bloated topic node is marked wasteful');
        System.assert(String.isNotBlank(triage.instructions), 'topic instructions (Scope) populated');
        System.assertEquals(InstructionBloatDetector.SIGNAL, triage.signalType,
            'the wasteful topic carries the instruction-bloat signal');
        System.assert(triage.tokenCount != null && triage.tokenCount > 0, 'token count computed for the scope');
    }

    // ========================= Wave 4 Worklist (Findings + Recommendations) =========================

    private static OhmDTO.WorklistItemDTO worklistItemFor(List<OhmDTO.WorklistItemDTO> items, Id findingId) {
        for (OhmDTO.WorklistItemDTO i : items) {
            if (i != null && i.findingId == findingId) { return i; }
        }
        return null;
    }

    // ---------- getFindings: live re-audit twice, still one item per (planner+artifact+signal) ----------

    @IsTest(SeeAllData=true)
    static void testGetFindingsDedupsAcrossReAudits() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        Test.startTest();
        OhmAuditTestSupport.auditProcess(wasteId);   // first audit
        OhmAuditTestSupport.auditProcess(wasteId);   // re-audit the SAME process
        List<OhmDTO.WorklistItemDTO> items = OhmAuditController.getFindings(null, null);
        Test.stopTest();

        System.assertNotEquals(null, items, 'getFindings must never return null');
        System.assert(!items.isEmpty(), 'at least one waste finding after auditing the Weather fixture process');

        // dedup: no two items share (plannerApiName|artifactLabel|signal)
        Set<String> keys = new Set<String>();
        Decimal prevSavings = null;
        for (OhmDTO.WorklistItemDTO i : items) {
            String k = (i.plannerApiName == null ? '' : i.plannerApiName.toLowerCase())
                + '|' + (i.artifactLabel == null ? '' : i.artifactLabel.toLowerCase())
                + '|' + (i.signal == null ? '' : i.signal);
            System.assert(!keys.contains(k), 'no duplicate (planner|artifact|signal) survives re-audit dedup: ' + k);
            keys.add(k);
            // ordered by savings desc
            Decimal s = (i.savingsCentralWh == null) ? 0 : i.savingsCentralWh;
            if (prevSavings != null) {
                System.assert(prevSavings >= s, 'items ordered by savingsCentralWh desc');
            }
            prevSavings = s;
        }

        // at least one item carries savings and defaults to status Open
        Boolean sawSavingsOpen = false;
        for (OhmDTO.WorklistItemDTO i : items) {
            if (i.savingsCentralWh != null && i.savingsCentralWh > 0 && i.findingStatus == 'Open') {
                sawSavingsOpen = true;
                System.assertNotEquals(null, i.severity, 'severity mapped');
                System.assertNotEquals(null, i.processLabel, 'processLabel derived');
                break;
            }
        }
        System.assert(sawSavingsOpen, 'at least one finding with savings and status Open');
    }

    // ---------- getFindings: status/severity filters ----------

    @IsTest
    static void testGetFindingsAppliesStatusAndSeverityFilters() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        svc.updateProgress(reportId, 'Complete', 'Audit complete', 100);
        insert new List<Finding__c>{
            new Finding__c(Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
                Severity__c = 'High', Artifact_Label__c = 'Alpha', Annual_Energy_Savings_Wh__c = 5000,
                Finding_Status__c = 'Open', Generated_By__c = 'Deterministic'),
            new Finding__c(Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
                Severity__c = 'Medium', Artifact_Label__c = 'Beta', Annual_Energy_Savings_Wh__c = 1000,
                Finding_Status__c = 'Dismissed', Generated_By__c = 'Deterministic')
        };

        Test.startTest();
        List<OhmDTO.WorklistItemDTO> open = OhmAuditController.getFindings('Open', 'All');
        List<OhmDTO.WorklistItemDTO> high = OhmAuditController.getFindings(null, 'High');
        List<OhmDTO.WorklistItemDTO> all = OhmAuditController.getFindings('All', null);
        Test.stopTest();

        for (OhmDTO.WorklistItemDTO i : open) {
            System.assertEquals('Open', i.findingStatus, 'status filter keeps only Open');
        }
        for (OhmDTO.WorklistItemDTO i : high) {
            System.assertEquals('High', i.severity, 'severity filter keeps only High');
        }
        System.assert(all.size() >= 2, 'no filter (All/null) returns both fixtures; got ' + all.size());
    }

    // ---------- updateFindingStatus: persists + mirrors the linked Task ----------

    @IsTest
    static void testUpdateFindingStatusPersistsAndMirrorsTask() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        Finding__c f = new Finding__c(
            Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
            Severity__c = 'High', Artifact_Label__c = 'Gamma', Fix_Type__c = 'Trim_Instructions',
            Recommendation_Text__c = 'Trim it.', Generated_By__c = 'Deterministic'
        );
        insert f;

        // a linked task to verify mirroring
        OhmDTO.RemediationInputDTO input = new OhmDTO.RemediationInputDTO();
        input.findingId = f.Id;
        input.reportId = reportId;
        input.fixType = 'Trim_Instructions';
        Id taskId = svc.createRemediationTask(input);

        Test.startTest();
        OhmAuditController.updateFindingStatus(f.Id, 'Accepted');
        System.assertEquals('Accepted',
            [SELECT Finding_Status__c FROM Finding__c WHERE Id = :f.Id].Finding_Status__c,
            'status persisted to Accepted');
        System.assertEquals('In Progress',
            [SELECT Status FROM Task WHERE Id = :taskId].Status, 'Accepted mirrors Task open');

        OhmAuditController.updateFindingStatus(f.Id, 'Applied');
        Test.stopTest();

        System.assertEquals('Applied',
            [SELECT Finding_Status__c FROM Finding__c WHERE Id = :f.Id].Finding_Status__c);
        System.assertEquals('Completed',
            [SELECT Status FROM Task WHERE Id = :taskId].Status, 'Applied mirrors Task Completed');
    }

    // ---------- assignFinding: creates a Task, sets owner + due, writes Remediation_Task_Id__c ----------

    @IsTest
    static void testAssignFindingCreatesTaskWithOwnerAndDue() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        Finding__c f = new Finding__c(
            Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
            Severity__c = 'High', Artifact_Label__c = 'Delta', Fix_Type__c = 'Trim_Instructions',
            Recommendation_Text__c = 'Trim the scope.', Annual_Energy_Savings_Wh__c = 4200,
            Generated_By__c = 'Deterministic'
        );
        insert f;

        Date due = Date.today().addDays(3);

        Test.startTest();
        Id taskId = OhmAuditController.assignFinding(f.Id, UserInfo.getUserId(), due);
        Test.stopTest();

        System.assertNotEquals(null, taskId, 'assignFinding returns a Task Id');
        Task t = [SELECT Id, OwnerId, ActivityDate FROM Task WHERE Id = :taskId];
        System.assertEquals(UserInfo.getUserId(), t.OwnerId, 'Task owner set');
        System.assertEquals(due, t.ActivityDate, 'Task due date set');
        System.assertEquals((String) taskId,
            [SELECT Remediation_Task_Id__c FROM Finding__c WHERE Id = :f.Id].Remediation_Task_Id__c,
            'Remediation_Task_Id__c written back onto the finding');

        // re-assign reuses the SAME task (no duplicate)
        Id again = OhmAuditController.assignFinding(f.Id, UserInfo.getUserId(), due.addDays(1));
        System.assertEquals(taskId, again, 'existing Task reused, not duplicated');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :reportId]);
    }

    // ---------- getRecommendations: quick-wins ranked by savings / effort ----------

    @IsTest
    static void testGetRecommendationsRanksQuickWinsBySavingsPerEffort() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        svc.updateProgress(reportId, 'Complete', 'Audit complete', 100);
        // A: 6000 Wh / High(3) = 2000 ; B: 5000 Wh / Low(1) = 5000 ; C: 9000 Wh Dismissed (excluded)
        insert new List<Finding__c>{
            new Finding__c(Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
                Severity__c = 'High', Artifact_Label__c = 'HeavyEffort', Effort__c = 'High',
                Annual_Energy_Savings_Wh__c = 6000, Finding_Status__c = 'Open', Generated_By__c = 'Deterministic'),
            new Finding__c(Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
                Severity__c = 'Medium', Artifact_Label__c = 'QuickWin', Effort__c = 'Low',
                Annual_Energy_Savings_Wh__c = 5000, Finding_Status__c = 'Open', Generated_By__c = 'Deterministic'),
            new Finding__c(Agent_Audit_Report__c = reportId, Signal_Type__c = 'INSTRUCTION_BLOAT',
                Severity__c = 'High', Artifact_Label__c = 'AlreadyDone', Effort__c = 'Low',
                Annual_Energy_Savings_Wh__c = 9000, Finding_Status__c = 'Applied', Generated_By__c = 'Deterministic')
        };

        Test.startTest();
        List<OhmDTO.WorklistItemDTO> recs = OhmAuditController.getRecommendations();
        Test.stopTest();

        // Applied item excluded
        for (OhmDTO.WorklistItemDTO i : recs) {
            System.assertNotEquals('AlreadyDone', i.artifactLabel, 'Applied findings are excluded from quick-wins');
            System.assert(i.findingStatus != 'Applied' && i.findingStatus != 'Dismissed');
        }

        // QuickWin (5000/1) must rank ahead of HeavyEffort (6000/3=2000) despite lower absolute savings
        Integer quickWinPos = -1, heavyPos = -1;
        for (Integer idx = 0; idx < recs.size(); idx++) {
            if (recs[idx].artifactLabel == 'QuickWin') { quickWinPos = idx; }
            if (recs[idx].artifactLabel == 'HeavyEffort') { heavyPos = idx; }
        }
        System.assert(quickWinPos >= 0 && heavyPos >= 0, 'both actionable items present');
        System.assert(quickWinPos < heavyPos,
            'low-effort win ranks ahead of high-effort item by savings/effort');
    }

    // ========================= Wave 5 Trends + before/after diff (SPEC §2.5 / §2.6) =========================

    private static OhmDTO.AgentGradeHistoryDTO perAgentFor(List<OhmDTO.AgentGradeHistoryDTO> hist, Id plannerId) {
        String key = String.valueOf(plannerId);
        for (OhmDTO.AgentGradeHistoryDTO h : hist) {
            if (h != null && h.plannerId != null && String.valueOf(h.plannerId) == key) { return h; }
        }
        return null;
    }

    // ---------- getTrends(plannerId): that planner's process reports, chronological ----------

    @IsTest(SeeAllData=true)
    static void testGetTrendsPerProcessReturnsChronologicalPoints() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        Test.startTest();
        Id firstReport = OhmAuditTestSupport.auditProcess(wasteId);
        Id secondReport = OhmAuditTestSupport.auditProcess(wasteId);
        OhmDTO.TrendDTO trend = OhmAuditController.getTrends(wasteId);
        Test.stopTest();

        System.assertNotEquals(null, trend, 'getTrends must never return null');
        System.assertEquals(String.valueOf(wasteId), String.valueOf(trend.plannerId), 'scoped to the planner');
        System.assertNotEquals(null, trend.points, 'points list always present');
        System.assert(trend.points.size() >= 2,
            'two process audits produce at least two trend points; got ' + trend.points.size());
        for (OhmDTO.TrendPointDTO p : trend.points) {
            System.assertNotEquals(null, p.reportId, 'each point carries its report id');
            System.assertNotEquals(null, p.auditedAt, 'each point carries a timestamp');
            if (p.reportId == firstReport || p.reportId == secondReport) {
                System.assertEquals('IN', p.grade, 'Incomplete coverage is retained in history.');
                System.assertEquals(null, p.score);
                System.assert(p.energyWhCentral > 0, 'Known instruction scope still has modeled cost.');
            }
        }
        System.assertNotEquals(null, trend.lastEnergyWhCentral, 'last energy stamped');
        System.assertNotEquals(null, trend.realizedSavingsWh, 'realizedSavings stamped');
        System.assert(trend.realizedSavingsWh >= 0, 'realizedSavings is clamped at 0');
    }

    // ---------- getTrends(null): org points + per-agent grade history ----------

    @IsTest(SeeAllData=true)
    static void testGetTrendsOrgReturnsPointsAndPerAgentHistory() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        Integer fleetPointsBefore = OhmAuditController.getTrends(null).points.size();
        Test.startTest();
        OhmAuditTestSupport.auditProcess(wasteId);
        OhmDTO.TrendDTO trend = OhmAuditController.getTrends(null);
        Test.stopTest();

        System.assertNotEquals(null, trend, 'getTrends(null) must never return null');
        System.assertEquals('Org', trend.scope, 'null planner → org scope');
        System.assertEquals(null, trend.plannerId, 'org scope has no plannerId');
        System.assertNotEquals(null, trend.points, 'org points list present');
        System.assertEquals(fleetPointsBefore, trend.points.size(), 'A process audit must not create a fleet trend point.');

        System.assertNotEquals(null, trend.perAgent, 'perAgent history present for org scope');
        OhmDTO.AgentGradeHistoryDTO waste = perAgentFor(trend.perAgent, wasteId);
        System.assertNotEquals(null, waste, 'the audited waste planner appears in perAgent history');
        System.assertNotEquals(null, waste.label, 'perAgent label derived');
        System.assert(waste.gradeHistory != null && !waste.gradeHistory.isEmpty(),
            'grade history populated for the audited planner');
        System.assertEquals('IN', waste.currentGrade, 'Latest process history retains incomplete coverage.');
    }

    // ---------- getDiff: two process audits → before/after with deltas + improved flag ----------

    @IsTest(SeeAllData=true)
    static void testGetDiffAfterTwoAuditsReturnsBeforeAfterWithDeltas() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        Test.startTest();
        OhmAuditTestSupport.auditProcess(wasteId);   // before
        Id afterReport = OhmAuditTestSupport.auditProcess(wasteId);
        Audit_Artifact_Snapshot__c source = [
            SELECT Artifact_Key__c FROM Audit_Artifact_Snapshot__c
            WHERE Agent_Audit_Report__c = :afterReport AND Artifact_Type__c = 'Topic' AND Coverage_Status__c = 'Complete'
            ORDER BY Character_Count__c DESC LIMIT 1
        ];
        OhmDTO.DiffDTO diff = OhmAuditController.getArtifactDiff(wasteId, source.Artifact_Key__c);
        Test.stopTest();

        System.assertNotEquals(null, diff, 'getDiff must never return null');
        System.assertEquals(String.valueOf(wasteId), String.valueOf(diff.plannerId), 'diff scoped to planner');
        System.assertNotEquals(null, diff.beforeReportId, 'before report set (2nd-newest)');
        System.assertNotEquals(null, diff.afterReportId, 'after report set (newest)');
        System.assertNotEquals(diff.beforeReportId, diff.afterReportId, 'before and after are distinct reports');
        System.assertEquals('IN', diff.afterGrade);
        System.assertEquals('IN', diff.beforeGrade);
        System.assertEquals(true, diff.comparable, 'The selected known instruction scope has unchanged modeled assumptions.');

        // deltas present; two identical audits of an unchanged process → zero deltas, not improved
        System.assertEquals(null, diff.scoreDelta, 'Incomplete coverage does not create a numeric grade improvement.');
        System.assertEquals(false, diff.improved, 'unchanged process is not "improved"');
        System.assertNotEquals(null, diff.energyDeltaWh, 'energyDelta computed');
        System.assertEquals(0, diff.energyDeltaWh, 'unchanged process → zero energy delta');
        System.assertNotEquals(null, diff.findingsDelta, 'findingsDelta computed');

        // Exact same artifact snapshots survive independently of findings.
        System.assert(String.isNotBlank(diff.afterInstructions),
            'after instructions snapshot present (bloat finding scope)');
        System.assert(String.isNotBlank(diff.beforeInstructions),
            'before instructions snapshot present (bloat finding scope)');
    }

    // ---------- getDiff: single audit → after only, before null ("re-audit to compare") ----------

    @IsTest(SeeAllData=true)
    static void testGetDiffSingleAuditReturnsAfterOnly() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        // guard: this test relies on exactly one report existing; skip if prior process reports linger
        Integer existing = [
            SELECT COUNT() FROM Agent_Audit_Report__c
            WHERE Target_Type__c = 'Process' AND Target_Planner_Id__c = :String.valueOf(wasteId)
        ];

        Test.startTest();
        Id reportId = OhmAuditTestSupport.auditProcess(wasteId);
        OhmDTO.DiffDTO diff = OhmAuditController.getDiff(wasteId);
        Test.stopTest();

        System.assertNotEquals(null, diff, 'getDiff must never return null');
        System.assertNotEquals(null, diff.afterReportId, 'after (newest) report always set when any report exists');
        if (existing == 0) {
            System.assertEquals(reportId, diff.afterReportId, 'after points at the only report');
            System.assertEquals(null, diff.beforeReportId, 'fewer than two reports → before is null');
            System.assertEquals(null, diff.scoreDelta, 'no delta without a before report');
        }
    }

    // ---------- snapshot: INSTRUCTION_BLOAT finding captures the topic Scope at audit time ----------

    @IsTest(SeeAllData=true)
    static void testAuditProcessCapturesInstructionSnapshotForBloatFinding() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Published Weather Agent Script fixture must exist in the org');

        Test.startTest();
        Id reportId = OhmAuditTestSupport.auditProcess(wasteId);
        Test.stopTest();

        // Read through the source-evidence service: Source_Json__c preserves the exact source
        // whitespace that Salesforce can trim from the convenience long-text field.
        List<Audit_Artifact_Snapshot__c> sources = new List<Audit_Artifact_Snapshot__c>();
        for (Audit_Artifact_Snapshot__c source : OhmArtifactSnapshotService.load(new Set<Id>{reportId}).get(reportId).values()) {
            if (source.Artifact_Type__c == 'Topic') sources.add(source);
        }
        System.assert(!sources.isEmpty(), 'Every discovered topic has independent source evidence.');
        Boolean sawSnapshot = false;
        for (Audit_Artifact_Snapshot__c source : sources) {
            if (String.isNotBlank(source.Instructions__c) && source.Instructions__c.length() > 100) {
                sawSnapshot = true;
                System.assertEquals('Complete', source.Coverage_Status__c);
                System.assertEquals(OhmPersistenceService.sha256(source.Instructions__c), source.Source_Hash__c);
                System.assertEquals(source.Character_Count__c, source.Instructions__c.length(),
                    'The exact audited source, including its trailing whitespace, survives the snapshot.');
                System.assertNotEquals(null, source.Artifact_Key__c);
            }
        }
        System.assert(sawSnapshot, 'The audited raw topic instructions survive independently of findings.');
    }
}
