/**
 * OhmPersistenceServiceTest — SPEC §T (Task 7 gate: findings persisted, rollups compute,
 * loadReadout maps exactly, restricted picklists accept canonical values, F8 task created).
 */
@IsTest
private class OhmPersistenceServiceTest {

    // ---------- fixture builders ----------

    private static OhmDTO.AgentModel buildGraph() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.AgentNode a = new OhmDTO.AgentNode();
        a.id = '0AgentToolingId001';
        a.developerName = 'Ohm_Spike_Agent';
        a.masterLabel = 'Ohm Spike Agent';
        g.agentsById.put(a.id, a);

        OhmDTO.TopicNode t = new OhmDTO.TopicNode();
        t.id = '0TopicToolingId001';
        t.developerName = 'Ohm_Spike_Topic';
        g.topics.add(t);

        OhmDTO.ActionNode n = new OhmDTO.ActionNode();
        n.id = '0ActionToolingId01';
        n.developerName = 'Ohm_Spike_Ping';
        n.invocationTargetType = 'apex';
        g.actions.add(n);

        g.promptTemplateCount = 1;
        return g;
    }

    private static OhmDTO.FootprintResponse band(Decimal lowV, Decimal centralV, Decimal highV) {
        OhmDTO.FootprintResponse r = new OhmDTO.FootprintResponse();
        r.energyWhLow = lowV;       r.energyWhCentral = centralV;       r.energyWhHigh = highV;
        r.waterMlLow = lowV * 2;    r.waterMlCentral = centralV * 2;    r.waterMlHigh = highV * 2;
        r.co2eGLow = lowV / 2;      r.co2eGCentral = centralV / 2;      r.co2eGHigh = highV / 2;
        r.annualCalls = 109500;
        r.perInferenceWh = 0.27;
        r.telemetryBacked = false;
        r.confidence = 'Low';
        return r;
    }

    /** A canonical-picklist finding (LLM_WHERE_DETERMINISTIC / High / Medium / Action ...). */
    private static OhmDTO.Finding buildFinding(String signalType, String fixType, Decimal centralWh) {
        OhmDTO.Finding f = new OhmDTO.Finding();
        f.signalType = signalType;
        f.severity = 'High';
        f.confidence = 'Medium';
        f.artifactType = 'Action';
        f.artifactApiName = 'Ohm_Fixture_ClassifyPriority';
        f.artifactLabel = 'Classify Priority';
        f.artifactToolingId = '0ActionToolingId01';
        f.parentAgentApiName = 'Ohm_Spike_Agent';
        f.parentTopicApiName = 'Ohm_Spike_Topic';
        f.evidence = 'Deterministic lexicon hits: classify, route, categorize.';
        f.metricValue = 2;
        f.metricUnit = 'hits';
        f.severityScore = 0.70;
        f.footprint = band(centralWh - 5000, centralWh, centralWh + 5000);
        f.savings = band(1000, 2000, 3000);
        f.fixType = fixType;
        f.recommendedTarget = 'Flow or Apex rule';
        f.recommendationText = 'Replace the prompt call with a Flow that returns the exact result.';
        f.generatedBy = 'Deterministic';
        f.effort = 'Medium';
        return f;
    }

    private static OhmDTO.EfficiencyResult buildRating() {
        OhmDTO.EfficiencyResult r = new OhmDTO.EfficiencyResult();
        r.score = 72;
        r.grade = 'C';
        r.weightedSeveritySum = 0.7;
        r.maxPossible = 2.5;
        return r;
    }

    // ---------- createReport / updateProgress ----------

    @IsTest
    static void testCreateReportInsertsQueuedAndUpdateProgressAdvances() {
        OhmPersistenceService svc = new OhmPersistenceService();

        Test.startTest();
        Id reportId = svc.createReport();
        svc.updateProgress(reportId, 'Analyzing', 'Running efficiency signals', 40);
        Test.stopTest();

        System.assertNotEquals(null, reportId, 'createReport must return the new report Id');
        Agent_Audit_Report__c rep = [
            SELECT Run_Status__c, Run_Stage_Message__c, Percent_Complete__c, Org_Id__c, Run_Timestamp__c
            FROM Agent_Audit_Report__c WHERE Id = :reportId
        ];
        System.assertEquals('Analyzing', rep.Run_Status__c, 'updateProgress must set status');
        System.assertEquals('Running efficiency signals', rep.Run_Stage_Message__c);
        System.assertEquals(40, rep.Percent_Complete__c);
        System.assertEquals(UserInfo.getOrganizationId(), rep.Org_Id__c);
        System.assertNotEquals(null, rep.Run_Timestamp__c);
    }

    // ---------- saveDiscoveryGraph ----------

    @IsTest
    static void testSaveDiscoveryGraphSerializesModel() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();

        Test.startTest();
        svc.saveDiscoveryGraph(reportId, buildGraph());
        Test.stopTest();

        Agent_Audit_Report__c rep = [
            SELECT Discovery_Graph_Json__c FROM Agent_Audit_Report__c WHERE Id = :reportId
        ];
        System.assertNotEquals(null, rep.Discovery_Graph_Json__c, 'graph JSON must be stored');
        System.assert(rep.Discovery_Graph_Json__c.contains('Ohm_Spike_Agent'),
            'serialized graph must carry the agent developerName');
        // must round-trip back into the DTO
        OhmDTO.AgentModel back = (OhmDTO.AgentModel) JSON.deserialize(
            rep.Discovery_Graph_Json__c, OhmDTO.AgentModel.class);
        System.assertEquals(1, back.actions.size());
        System.assertEquals('Ohm_Spike_Ping', back.actions[0].developerName);
    }

    // ---------- persistFindings: restricted picklists, bulk insert, rollups ----------

    @IsTest
    static void testPersistFindingsInsertsChildrenAndComputesRollups() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>{
            buildFinding('LLM_WHERE_DETERMINISTIC', 'Replace_With_Flow', 30000),
            buildFinding('INSTRUCTION_BLOAT', 'Trim_Instructions', 10000)
        };

        Test.startTest();
        svc.persistFindings(reportId, buildGraph(), findings, buildRating());
        Test.stopTest();

        // children inserted with canonical restricted-picklist values (happy path = no DmlException)
        List<Finding__c> rows = [
            SELECT Signal_Type__c, Severity__c, Confidence__c, Artifact_Type__c, Fix_Type__c,
                   Generated_By__c, Effort__c, Rec_Status__c,
                   Annual_Energy_Wh_Central__c, Annual_Energy_Savings_Wh__c,
                   Estimated_Annual_Calls__c, Per_Inference_Wh__c
            FROM Finding__c WHERE Agent_Audit_Report__c = :reportId
            ORDER BY Annual_Energy_Wh_Central__c DESC
        ];
        System.assertEquals(2, rows.size(), 'both findings must be inserted in ONE bulk insert');
        System.assertEquals('LLM_WHERE_DETERMINISTIC', rows[0].Signal_Type__c);
        System.assertEquals('INSTRUCTION_BLOAT', rows[1].Signal_Type__c);
        System.assertEquals('Deterministic', rows[0].Generated_By__c);
        System.assertEquals('Proposed', rows[0].Rec_Status__c);
        System.assertEquals(30000, rows[0].Annual_Energy_Wh_Central__c);
        System.assertEquals(2000, rows[0].Annual_Energy_Savings_Wh__c);
        System.assertEquals(109500, rows[0].Estimated_Annual_Calls__c);

        // findingRecordId written back onto the DTOs
        System.assertNotEquals(null, findings[0].findingRecordId);
        System.assertNotEquals(null, findings[1].findingRecordId);

        // report stamped + rollup summaries computed
        Agent_Audit_Report__c rep = [
            SELECT Run_Status__c, Percent_Complete__c, Efficiency_Grade__c, Efficiency_Score__c,
                   Agents_Discovered__c, Topics_Discovered__c, Actions_Discovered__c,
                   Prompt_Templates_Discovered__c, Methodology_Version__c,
                   Findings_Count__c, Total_Annual_Energy_Wh__c, Total_Annual_Energy_Savings_Wh__c,
                   Total_Annual_Water_mL__c, Total_Annual_CO2e_g__c
            FROM Agent_Audit_Report__c WHERE Id = :reportId
        ];
        System.assertEquals('Complete', rep.Run_Status__c);
        System.assertEquals(100, rep.Percent_Complete__c);
        System.assertEquals('C', rep.Efficiency_Grade__c);
        System.assertEquals(72, rep.Efficiency_Score__c);
        System.assertEquals(1, rep.Agents_Discovered__c);
        System.assertEquals(1, rep.Topics_Discovered__c);
        System.assertEquals(1, rep.Actions_Discovered__c);
        System.assertEquals(1, rep.Prompt_Templates_Discovered__c);
        System.assertNotEquals(null, rep.Methodology_Version__c);
        System.assertEquals(2, rep.Findings_Count__c, 'Findings_Count__c rollup');
        System.assertEquals(40000, rep.Total_Annual_Energy_Wh__c, 'sum of central Wh (30000+10000)');
        System.assertEquals(4000, rep.Total_Annual_Energy_Savings_Wh__c, 'sum of central savings (2000+2000)');
        System.assertEquals(80000, rep.Total_Annual_Water_mL__c, 'sum of central water (2x Wh)');
        System.assertEquals(20000, rep.Total_Annual_CO2e_g__c, 'sum of central CO2e (0.5x Wh)');
    }

    // ---------- loadReadout mapping ----------

    @IsTest
    static void testLoadReadoutMapsEveryField() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>{
            buildFinding('MODEL_RIGHTSIZING', 'Downsize_Model', 20000)
        };

        OhmDTO.AgentModel audited = buildGraph();
        audited.topics[0].instructions = 'Audited instructions with an independent workload baseline.';
        OhmAuditImpactService.Snapshot modeled = OhmAuditImpactService.compute(audited, findings, null);
        Test.startTest();
        OhmAuditImpactService.save(reportId, audited, findings, null);
        svc.persistFindings(reportId, audited, findings, buildRating());
        OhmDTO.AuditReadoutDTO dto = svc.loadReadout(reportId);
        Test.stopTest();

        System.assertEquals(reportId, dto.reportId);
        System.assertEquals('Complete', dto.runStatus);
        System.assertEquals(100, dto.percentComplete);
        System.assertEquals(1, dto.agentsDiscovered);
        System.assertEquals(1, dto.topicsDiscovered);
        System.assertEquals(1, dto.actionsDiscovered);
        System.assertEquals(1, dto.promptTemplatesDiscovered);
        System.assertEquals('C', dto.efficiencyGrade);
        System.assertEquals(72, dto.efficiencyScore);
        System.assertEquals(false, dto.telemetryBacked);
        System.assertNotEquals(null, dto.volumeAssumption, 'volume scenario disclosed');
        System.assertNotEquals(null, dto.assumptions, 'assumptions disclosed (F10)');

        // Totals come from the persisted modeled workload, not the finding's overlapping cost.
        System.assertEquals(modeled.baseline.energyWhLow, dto.orgEnergyWhLow);
        System.assertEquals(modeled.baseline.energyWhCentral, dto.orgEnergyWhCentral);
        System.assertEquals(modeled.baseline.energyWhHigh, dto.orgEnergyWhHigh);
        System.assertEquals(modeled.baseline.waterMlCentral, dto.orgWaterMlCentral);
        System.assertEquals(modeled.baseline.co2eGCentral, dto.orgCo2eGCentral);
        System.assertEquals(modeled.savings.energyWhLow, dto.orgEnergySavingsWhLow);
        System.assertEquals(modeled.savings.energyWhCentral, dto.orgEnergySavingsWhCentral);
        System.assertEquals(modeled.savings.energyWhHigh, dto.orgEnergySavingsWhHigh);
        System.assertNotEquals(20000, dto.orgEnergyWhCentral);

        System.assertEquals(1, dto.findings.size());
        OhmDTO.FindingDTO f = dto.findings[0];
        System.assertEquals('MODEL_RIGHTSIZING', f.signal);
        System.assertEquals('High', f.severity);
        System.assertEquals('Medium', f.confidence);
        System.assertEquals('Action', f.artifactType);
        System.assertEquals('Ohm_Fixture_ClassifyPriority', f.targetArtifact.apiName);
        System.assertEquals('Classify Priority', f.targetArtifact.label);
        System.assertEquals('0ActionToolingId01', f.targetArtifact.toolingId);
        System.assertEquals('Ohm_Spike_Agent', f.targetArtifact.parentAgentApiName);
        System.assertEquals('Ohm_Spike_Topic', f.targetArtifact.parentTopicApiName);
        System.assertEquals(2, f.metricValue);
        System.assertEquals('hits', f.metricUnit);
        System.assertEquals(20000, f.energyWhCentral);
        System.assertEquals(40000, f.waterMlCentral);
        System.assertEquals(10000, f.co2eGCentral);
        System.assertEquals(109500, f.estimatedAnnualCalls);
        System.assertEquals(0.27, f.perInferenceWh);
        System.assertEquals(2000, f.estimatedSavingsCentral);
        System.assertEquals('Downsize_Model', f.fixType);
        System.assertEquals('Deterministic', f.generatedBy);
        System.assertEquals('Proposed', f.recStatus);
        System.assertEquals('Medium', f.effort);
    }

    // ---------- writeAgentNarratives ----------

    @IsTest
    static void testWriteAgentNarrativesUpdatesMatchingFindings() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>{
            buildFinding('REDUNDANT_CALLS', 'Consolidate_Calls', 5000),
            buildFinding('INSTRUCTION_BLOAT', 'Trim_Instructions', 6000)
        };
        svc.persistFindings(reportId, buildGraph(), findings, buildRating());

        OhmDTO.AgentNarrativeInput n = new OhmDTO.AgentNarrativeInput();
        n.findingId = findings[0].findingRecordId;
        n.narrative = 'This agent repeats a call each turn; consolidating saves the most energy first.';
        n.rank = 1;

        Test.startTest();
        Integer updated = svc.writeAgentNarratives(reportId, new List<OhmDTO.AgentNarrativeInput>{ n });
        Test.stopTest();

        System.assertEquals(1, updated, 'exactly one narrative row updated');
        Finding__c row = [
            SELECT Agent_Narrative__c, Generated_By__c FROM Finding__c
            WHERE Id = :findings[0].findingRecordId
        ];
        System.assertEquals(n.narrative, row.Agent_Narrative__c);
        System.assertEquals('Agentforce', row.Generated_By__c, 'narrative provenance flips to Agentforce');

        Finding__c untouched = [
            SELECT Agent_Narrative__c, Generated_By__c FROM Finding__c
            WHERE Id = :findings[1].findingRecordId
        ];
        System.assertEquals(null, untouched.Agent_Narrative__c);
        System.assertEquals('Deterministic', untouched.Generated_By__c);
    }

    @IsTest
    static void testWriteAgentNarrativesEmptyOrForeignIdsReturnsZero() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        System.assertEquals(0, svc.writeAgentNarratives(reportId, null));
        System.assertEquals(0, svc.writeAgentNarratives(reportId, new List<OhmDTO.AgentNarrativeInput>()));

        // a findingId that does not belong to this report must not be updated
        Id otherReport = svc.createReport();
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>{
            buildFinding('REDUNDANT_CALLS', 'Consolidate_Calls', 5000)
        };
        svc.persistFindings(otherReport, buildGraph(), findings, buildRating());
        OhmDTO.AgentNarrativeInput n = new OhmDTO.AgentNarrativeInput();
        n.findingId = findings[0].findingRecordId;
        n.narrative = 'wrong report';
        System.assertEquals(0, svc.writeAgentNarratives(reportId, new List<OhmDTO.AgentNarrativeInput>{ n }),
            'narratives are scoped to the given report');
    }

    // ---------- createRemediationTask (C12, F8) ----------

    @IsTest
    static void testCreateRemediationTaskInsertsTaskAndWritesBackId() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>{
            buildFinding('LLM_WHERE_DETERMINISTIC', 'Replace_With_Flow', 30000)
        };
        svc.persistFindings(reportId, buildGraph(), findings, buildRating());

        OhmDTO.RemediationInputDTO input = new OhmDTO.RemediationInputDTO();
        input.findingId = findings[0].findingRecordId;
        input.reportId = reportId;
        input.fixType = 'Replace_With_Flow';
        input.recommendedTarget = 'Flow or Apex rule';
        input.recommendationText = 'Replace the prompt call with a Flow that returns the exact result.';
        input.estimatedSavingsCentralWh = 2000;
        input.note = 'Approved during demo.';

        Test.startTest();
        Id taskId = svc.createRemediationTask(input);
        Test.stopTest();

        System.assertNotEquals(null, taskId);
        Task t = [SELECT Subject, Description, Status FROM Task WHERE Id = :taskId];
        System.assert(t.Subject.startsWith('Ohm:'), 'subject carries the Ohm prefix');
        System.assert(t.Subject.contains('Replace With Flow'), 'subject carries the fix type');
        System.assert(t.Description.contains('2000'), 'description carries the savings figure');
        System.assert(t.Description.contains('Approved during demo.'), 'description carries the note');
        System.assert(t.Description.contains(reportId), 'description references the audit report');

        Finding__c row = [SELECT Remediation_Task_Id__c FROM Finding__c WHERE Id = :input.findingId];
        System.assertEquals(taskId, (Id) row.Remediation_Task_Id__c, 'task Id written back on the finding');
    }

    @IsTest
    static void testCreateRemediationTaskRequiresFindingId() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Boolean threw = false;
        try {
            svc.createRemediationTask(new OhmDTO.RemediationInputDTO());
        } catch (OhmPersistenceService.OhmPersistenceException e) {
            threw = true;
        }
        System.assert(threw, 'missing findingId must raise OhmPersistenceException');
    }

    // ---------- empty-findings persist (clean org path) ----------

    @IsTest
    static void testPersistFindingsWithNoFindingsStillCompletesReport() {
        OhmPersistenceService svc = new OhmPersistenceService();
        Id reportId = svc.createReport();
        OhmDTO.EfficiencyResult clean = new OhmDTO.EfficiencyResult();
        clean.score = 100;
        clean.grade = 'A';

        Test.startTest();
        svc.persistFindings(reportId, buildGraph(), new List<OhmDTO.Finding>(), clean);
        Test.stopTest();

        Agent_Audit_Report__c rep = [
            SELECT Run_Status__c, Efficiency_Grade__c, Efficiency_Score__c, Findings_Count__c
            FROM Agent_Audit_Report__c WHERE Id = :reportId
        ];
        System.assertEquals('Complete', rep.Run_Status__c);
        System.assertEquals('A', rep.Efficiency_Grade__c, 'clean org grades A (NFR-4)');
        System.assertEquals(100, rep.Efficiency_Score__c);
        System.assertEquals(0, rep.Findings_Count__c);
    }
    @IsTest static void legacyReadoutDoesNotPretendFindingCostIsTotalWorkload() {
        OhmPersistenceService service = new OhmPersistenceService();
        Id reportId = service.createReport();
        service.persistFindings(reportId, buildGraph(), new List<OhmDTO.Finding>{
            buildFinding('INSTRUCTION_BLOAT', 'Trim_Instructions', 10000)
        }, buildRating());
        OhmDTO.AuditReadoutDTO readout = service.loadReadout(reportId);
        System.assertEquals(null, readout.orgEnergyWhCentral);
        System.assertEquals(null, readout.orgEnergySavingsWhCentral);
        System.assertEquals(1, readout.findings.size(), 'Historical findings remain available as evidence.');
    }

}
