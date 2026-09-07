/** Isolated synthetic lifecycle checks for the demo contract; not external-workflow telemetry. */
@IsTest
private class OhmAuditLifecycleAcceptanceTest {
    private static Agent_Audit_Report__c report(String plannerId, String name, Integer secondsAgo) {
        Agent_Audit_Report__c r = new Agent_Audit_Report__c(
            Target_Type__c = 'Process', Target_Planner_Id__c = plannerId,
            Target_Planner_Api_Name__c = name, Run_Status__c = 'Complete',
            Run_Timestamp__c = System.now().addSeconds(-secondsAgo)
        );
        insert r;
        Test.setCreatedDate(r.Id, System.now().addSeconds(-secondsAgo));
        return r;
    }

    private static Finding__c finding(Id reportId, String label, Decimal energy) {
        Finding__c f = new Finding__c(
            Agent_Audit_Report__c = reportId, Artifact_Label__c = label,
            Signal_Type__c = 'INSTRUCTION_BLOAT', Severity__c = 'High',
            Annual_Energy_Wh_Central__c = energy, Generated_By__c = 'Deterministic',
            Finding_Status__c = 'Open'
        );
        insert f;
        return f;
    }

    @IsTest static void cleanReauditRemovesStaleRecommendations() {
        Agent_Audit_Report__c before = report('16j000000000001', 'Lab_Alpha', 20);
        finding(before.Id, 'Resolved instruction block', 80000);
        report('16j000000000001', 'Lab_Alpha', 10); // successful clean re-audit, no findings
        System.assertEquals(0, OhmAuditController.getRecommendations().size(),
            'A newer clean report must displace findings from the previous report');
    }

    @IsTest static void unchangedIssueKeepsItsTaskAndStatus() {
        Agent_Audit_Report__c before = report('16j000000000001', 'Lab_Alpha', 20);
        Finding__c original = finding(before.Id, 'Persistent instruction block', 80000);
        Id taskId = OhmAuditController.assignFinding(original.Id, UserInfo.getUserId(), Date.today().addDays(2));
        OhmAuditController.updateFindingStatus(original.Id, 'Accepted');
        Agent_Audit_Report__c after = report('16j000000000001', 'Lab_Alpha', 10);
        finding(after.Id, 'Persistent instruction block', 80000);
        List<OhmDTO.WorklistItemDTO> items = OhmAuditController.getFindings(null, null);
        System.assertEquals(1, items.size());
        System.assertEquals(taskId, items[0].taskId, 'Re-audit must retain the existing remediation Task');
        System.assertEquals('Accepted', items[0].findingStatus, 'Re-audit must retain the accepted state');
    }

    @IsTest static void differentAgentsDoNotCreateRealizedSavings() {
        Agent_Audit_Report__c alpha = report('16j000000000001', 'Lab_Alpha', 20);
        finding(alpha.Id, 'Alpha work', 80000);
        Agent_Audit_Report__c beta = report('16j000000000002', 'Lab_Beta', 10);
        finding(beta.Id, 'Beta work', 10000);
        OhmDTO.TrendDTO trends = OhmAuditController.getTrends(null);
        System.assertEquals(0, trends.realizedSavingsWh,
            'Two different agents, each audited once and never changed, cannot establish realized savings');
    }

    @IsTest static void missingCoverageMustNotReceiveAnA() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        g.discoveryErrors.add('Required instructions/model evidence unavailable');
        OhmDTO.EfficiencyResult rating = new OhmSignalService().rate(g, new List<OhmDTO.Finding>());
        System.assertNotEquals('A', rating.grade, 'Unavailable evidence must be distinct from a passed audit');
    }

    @IsTest static void unknownModelDoesNotPromiseSavings() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.ActionNode action = new OhmDTO.ActionNode();
        action.invocationTargetType = 'prompt'; // legacy supported type; missing model evidence
        action.developerName = 'Unknown_Model_Action';
        g.actions.add(action);
        List<OhmDTO.Finding> findings = new ModelRightSizingDetector().detect(g);
        System.assertEquals(1, findings.size(), 'Informational unknown-model result remains visible');
        new OhmRecommendationService().attachRecommendations(findings);
        System.assert(findings[0].savings == null || findings[0].savings.energyWhCentral == 0,
            'Unknown current model does not justify positive downsizing savings');
    }
}
