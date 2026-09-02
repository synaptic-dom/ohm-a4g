/**
 * OhmAuditControllerTest — SPEC §S.10 gate.
 * startAudit runs the full sync pipeline against the LIVE org agent surface
 * (GenAi*Definition rows, e.g. the deployed Ohm_Spike_Agent) — no mocks: discovery
 * is inline Apex SOQL (canon C13), so the pipeline is testable end-to-end.
 */
@IsTest
private class OhmAuditControllerTest {

    // ---------- startAudit: full pipeline against live discovery data ----------

    @IsTest(SeeAllData=true) // GenAiPlannerDefinition/GenAiPluginDefinition/GenAiFunctionDefinition are org metadata rows
    static void testStartAuditReturnsCompleteReportWithReadout() {
        Test.startTest();
        Id reportId = OhmAuditController.startAudit();
        Test.stopTest();

        System.assertNotEquals(null, reportId, 'startAudit must return the reportId (== runId)');

        OhmDTO.AuditReadoutDTO dto = OhmAuditController.getAuditStatus(reportId);
        System.assertNotEquals(null, dto, 'readout must load');
        System.assertEquals(reportId, dto.reportId);
        System.assertEquals('Complete', dto.runStatus, 'sync pipeline must finish Complete');
        System.assertEquals(100, dto.percentComplete);
        System.assert(dto.agentsDiscovered >= 1,
            'live spike agent (Ohm_Spike_Agent) must be discovered; got ' + dto.agentsDiscovered);
        System.assert(dto.actionsDiscovered >= 1,
            'live spike apex action must be discovered; got ' + dto.actionsDiscovered);
        System.assertNotEquals(null, dto.efficiencyGrade, 'grade stamped');
        System.assertNotEquals(null, dto.efficiencyScore, 'score stamped');
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
}
