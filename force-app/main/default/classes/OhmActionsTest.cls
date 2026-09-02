/**
 * OhmActionsTest — TDD coverage for the six agent-door invocable actions (SPEC §S.11,
 * canon C4). One test per action asserting real delegation behavior: DTO shapes come
 * from OhmDTO, picklist fixtures use canonical restricted values only (C2), and no
 * test depends on org agent data being present (empty-org safe).
 */
@IsTest
private class OhmActionsTest {

    // ---------- fixtures ----------

    private static OhmDTO.AgentModel wastefulGraph() {
        // One prompt-typed action whose text trips the LLM_WHERE_DETERMINISTIC lexicon
        // (classify + route + extract) — deterministic detector input, no org data needed.
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.ActionNode a = new OhmDTO.ActionNode();
        a.id = 'act-fixture-1';
        a.developerName = 'Classify_Lead';
        a.masterLabel = 'Classify Lead';
        a.description = 'Classify the lead, route it to the right queue, and extract the region code.';
        a.invocationTargetType = 'prompt';
        a.invocationTarget = 'Lead_Classifier_Template';
        a.isLocal = false;
        g.actions.add(a);
        return g;
    }

    private static Agent_Audit_Report__c makeReport(String graphJson) {
        Agent_Audit_Report__c rep = new Agent_Audit_Report__c(
            Run_Status__c = 'Queued',
            Discovery_Graph_Json__c = graphJson
        );
        insert rep;
        return rep;
    }

    private static Finding__c makeFinding(Id reportId) {
        Finding__c f = new Finding__c(
            Agent_Audit_Report__c = reportId,
            Signal_Type__c = 'LLM_WHERE_DETERMINISTIC',
            Severity__c = 'Medium',
            Confidence__c = 'Medium',
            Artifact_Type__c = 'Action',
            Artifact_Api_Name__c = 'Classify_Lead',
            Artifact_Label__c = 'Classify Lead',
            Fix_Type__c = 'Replace_With_Flow',
            Recommended_Target__c = 'Flow or Apex rule',
            Recommendation_Text__c = 'Replace the prompt call with a Flow that returns the exact result.',
            Annual_Energy_Savings_Wh__c = 1234.5,
            Generated_By__c = 'Deterministic',
            Effort__c = 'Medium'
        );
        insert f;
        return f;
    }

    // ---------- 1. DiscoverAgenticWork ----------

    @IsTest
    static void discoverAgenticWorkCreatesReportAndSavesGraph() {
        DiscoverAgenticWork.Request req = new DiscoverAgenticWork.Request(); // blank => new report

        Test.startTest();
        List<DiscoverAgenticWork.Response> out =
            DiscoverAgenticWork.run(new List<DiscoverAgenticWork.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, out.size(), 'one response per request');
        DiscoverAgenticWork.Response resp = out[0];
        System.assertNotEquals(null, resp.reportId,
            'blank reportId must create a report; summary: ' + resp.summary);
        System.assert(resp.agentCount >= 0 && resp.topicCount >= 0 && resp.actionCount >= 0,
            'inventory counts populated (empty-org safe)');
        System.assert(String.isNotBlank(resp.graphJson), 'graphJson returned for the next action');
        System.assert(String.isNotBlank(resp.summary), 'summary is the agent-readable channel');

        // C11: the graph must be persisted on the report for re-entrancy
        Agent_Audit_Report__c rep = [
            SELECT Id, Discovery_Graph_Json__c
            FROM Agent_Audit_Report__c
            WHERE Id = :resp.reportId
        ];
        System.assert(String.isNotBlank(rep.Discovery_Graph_Json__c),
            'Discovery_Graph_Json__c persisted (C11)');
    }

    @IsTest
    static void discoverAgenticWorkReusesExistingReport() {
        Agent_Audit_Report__c rep = makeReport(null);
        DiscoverAgenticWork.Request req = new DiscoverAgenticWork.Request();
        req.reportId = rep.Id;

        Test.startTest();
        List<DiscoverAgenticWork.Response> out =
            DiscoverAgenticWork.run(new List<DiscoverAgenticWork.Request>{ req });
        Test.stopTest();

        System.assertEquals(String.valueOf(rep.Id), out[0].reportId,
            'existing reportId is reused, not replaced; summary: ' + out[0].summary);
        System.assertEquals(1, [SELECT COUNT() FROM Agent_Audit_Report__c],
            'no second report created');
    }

    // ---------- 2. RunSignals ----------

    @IsTest
    static void runSignalsDetectsWasteFromGraphJson() {
        RunSignals.Request req = new RunSignals.Request();
        req.graphJson = JSON.serialize(wastefulGraph());

        Test.startTest();
        List<RunSignals.Response> out = RunSignals.run(new List<RunSignals.Request>{ req });
        Test.stopTest();

        RunSignals.Response resp = out[0];
        System.assert(resp.findingsCount >= 1,
            'the wasteful prompt action must fire at least one signal; summary: ' + resp.summary);
        System.assert(resp.signalBreakdownJson.contains('LLM_WHERE_DETERMINISTIC'),
            'breakdown names the canonical signal (C2): ' + resp.signalBreakdownJson);
        List<OhmDTO.Finding> findings =
            (List<OhmDTO.Finding>) JSON.deserialize(resp.findingsJson, List<OhmDTO.Finding>.class);
        System.assertEquals(resp.findingsCount, findings.size(),
            'findingsJson round-trips to the same count');
    }

    @IsTest
    static void runSignalsReloadsGraphFromReportWhenJsonBlank() {
        Agent_Audit_Report__c rep = makeReport(JSON.serialize(wastefulGraph()));
        RunSignals.Request req = new RunSignals.Request();
        req.reportId = rep.Id; // no graphJson => reload from Discovery_Graph_Json__c

        Test.startTest();
        List<RunSignals.Response> out = RunSignals.run(new List<RunSignals.Request>{ req });
        Test.stopTest();

        System.assert(out[0].findingsCount >= 1,
            're-entrant path (C11) analyzes the saved graph; summary: ' + out[0].summary);
    }

    // ---------- 3. EstimateFootprint ----------

    @IsTest
    static void estimateFootprintReturnsOrderedBandsPerElement() {
        OhmDTO.FootprintRequest fpReq = new OhmDTO.FootprintRequest();
        fpReq.tokensPerInference = 1000;
        fpReq.annualCalls = 1000;
        EstimateFootprint.Request withJson = new EstimateFootprint.Request();
        withJson.requestJson = JSON.serialize(fpReq);
        EstimateFootprint.Request blankDefault = new EstimateFootprint.Request(); // org-default baseline

        Test.startTest();
        List<EstimateFootprint.Response> out = EstimateFootprint.run(
            new List<EstimateFootprint.Request>{ withJson, blankDefault });
        Test.stopTest();

        System.assertEquals(2, out.size(), 'one response per element (C5 singular engine per element)');
        for (EstimateFootprint.Response resp : out) {
            System.assert(resp.energyWhCentral > 0, 'central energy positive; summary: ' + resp.summary);
            System.assert(resp.energyWhLow <= resp.energyWhCentral
                && resp.energyWhCentral <= resp.energyWhHigh,
                'bands ordered Low <= Central <= High (C3)');
            System.assert(resp.waterMlCentral > 0 && resp.co2eGCentral > 0, 'water and CO2e populated');
            System.assert(String.isNotBlank(resp.assumptionsJson)
                && resp.assumptionsJson.contains('energyPerPromptWh'),
                'assumptions disclosed (F10)');
            System.assert(resp.summary.contains('not telemetry'), 'provenance caveat in summary (W7)');
        }
        // the default path uses the C6 baseline volume: 50 × 6 × 1 × 365 = 109,500 calls/yr
        System.assertEquals(109500, out[1].annualCalls.intValue(), 'org-default baseline uses the C6 scenario');
    }

    // ---------- 4. RecommendImprovements ----------

    @IsTest
    static void recommendImprovementsAttachesDeterministicFixes() {
        OhmSignalService signals = new OhmSignalService();
        List<OhmDTO.Finding> raw = signals.analyze(wastefulGraph());
        System.assert(!raw.isEmpty(), 'fixture graph must yield findings to recommend against');

        RecommendImprovements.Request req = new RecommendImprovements.Request();
        req.findingsJson = JSON.serialize(raw);

        Test.startTest();
        List<RecommendImprovements.Response> out =
            RecommendImprovements.run(new List<RecommendImprovements.Request>{ req });
        Test.stopTest();

        RecommendImprovements.Response resp = out[0];
        System.assertEquals(raw.size(), resp.recommendationCount,
            'every finding carries a recommendation; summary: ' + resp.summary);
        System.assert(resp.candidatesJson.contains('Replace_With_Flow'),
            'LLM_WHERE_DETERMINISTIC maps to Replace_With_Flow (C2 fix types)');
        System.assert(resp.candidatesJson.contains('Deterministic'),
            'generatedBy stays Deterministic — the agent only narrates');
    }

    // ---------- 5. PersistAuditReport ----------

    @IsTest
    static void persistAuditReportWritesAgentNarratives() {
        Agent_Audit_Report__c rep = makeReport(null);
        Finding__c finding = makeFinding(rep.Id);

        OhmDTO.AgentNarrativeInput n = new OhmDTO.AgentNarrativeInput();
        n.findingId = finding.Id;
        n.narrative = 'This action re-does deterministic work with a language model; a flow would be exact and token-free.';
        n.rank = 1;

        PersistAuditReport.Request req = new PersistAuditReport.Request();
        req.reportId = rep.Id;
        req.narrativesJson = JSON.serialize(new List<OhmDTO.AgentNarrativeInput>{ n });

        Test.startTest();
        List<PersistAuditReport.Response> out =
            PersistAuditReport.run(new List<PersistAuditReport.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, out[0].recordsUpdated,
            'one narrative written; summary: ' + out[0].summary);
        Finding__c reloaded = [
            SELECT Agent_Narrative__c, Generated_By__c FROM Finding__c WHERE Id = :finding.Id
        ];
        System.assertEquals(n.narrative, reloaded.Agent_Narrative__c, 'narrative persisted verbatim');
        System.assertEquals('Agentforce', reloaded.Generated_By__c,
            'narrative provenance stamped Agentforce (canonical value)');
    }

    // ---------- 6. CreateRemediationTask ----------

    @IsTest
    static void createRemediationTaskBuildsTaskFromPersistedFinding() {
        Agent_Audit_Report__c rep = makeReport(null);
        Finding__c finding = makeFinding(rep.Id);

        CreateRemediationTask.Request req = new CreateRemediationTask.Request();
        req.findingId = finding.Id;
        req.note = 'Approved in the audit review.';

        Test.startTest();
        List<CreateRemediationTask.Response> out =
            CreateRemediationTask.run(new List<CreateRemediationTask.Request>{ req });
        Test.stopTest();

        CreateRemediationTask.Response resp = out[0];
        System.assertNotEquals(null, resp.taskId,
            'a Task Id is returned; summary: ' + resp.summary);
        Task t = [SELECT Id, WhatId, Subject, Description FROM Task WHERE Id = :resp.taskId];
        System.assertEquals(rep.Id, t.WhatId, 'task is tied to the audit report (C12)');
        System.assert(t.Description.contains('Approved in the audit review.'),
            'optional note lands in the task description');
        Finding__c reloaded = [SELECT Remediation_Task_Id__c FROM Finding__c WHERE Id = :finding.Id];
        System.assertEquals(String.valueOf(resp.taskId), reloaded.Remediation_Task_Id__c,
            'Remediation_Task_Id__c written back on the finding (S.9)');
    }

    @IsTest
    static void createRemediationTaskReportsMissingFindingGracefully() {
        CreateRemediationTask.Request req = new CreateRemediationTask.Request();
        req.findingId = Finding__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000'; // valid shape, no record

        Test.startTest();
        List<CreateRemediationTask.Response> out =
            CreateRemediationTask.run(new List<CreateRemediationTask.Request>{ req });
        Test.stopTest();

        System.assertEquals(null, out[0].taskId, 'no task for a missing finding');
        System.assert(out[0].summary.startsWith('Error:'),
            'agent gets a readable error, not an exception: ' + out[0].summary);
    }
}
