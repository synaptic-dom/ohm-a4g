@IsTest
private class OhmAuditImpactServiceTest {
    private static OhmDTO.AgentModel graph(Integer characters) {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.AgentNode agent = new OhmDTO.AgentNode();
        agent.id = '16j000000000001'; agent.developerName = 'Weather_v1';
        g.agentsById.put(agent.id, agent);
        OhmDTO.TopicNode topic = new OhmDTO.TopicNode();
        topic.id = '179000000000001'; topic.developerName = 'weather'; topic.plannerId = agent.id;
        topic.instructions = 'x'.repeat(characters); topic.scope = topic.instructions;
        g.topics.add(topic);
        return g;
    }
    private static OhmDTO.Finding bloat() {
        OhmDTO.Finding f = new OhmDTO.Finding();
        f.signalType = InstructionBloatDetector.SIGNAL; f.artifactToolingId = '179000000000001';
        return f;
    }
    @IsTest static void cleanInstructionsRetainResidualFootprint() {
        OhmAuditImpactService.Snapshot clean = OhmAuditImpactService.compute(graph(1000), new List<OhmDTO.Finding>(), null);
        System.assertEquals(1, clean.artifactCount);
        System.assert(clean.baseline.energyWhCentral > 0, 'No findings does not mean no model work');
        System.assertEquals(clean.baseline.energyWhCentral, clean.afterScenario.energyWhCentral);
        System.assertEquals(0, clean.savings.energyWhCentral);
    }
    @IsTest static void duplicateFlagsDoNotDuplicateCostOrSavings() {
        OhmAuditImpactService.Snapshot single = OhmAuditImpactService.compute(graph(5400), new List<OhmDTO.Finding>{bloat()}, null);
        OhmAuditImpactService.Snapshot duplicate = OhmAuditImpactService.compute(graph(5400), new List<OhmDTO.Finding>{bloat(), bloat()}, null);
        System.assertEquals(single.baseline.energyWhCentral, duplicate.baseline.energyWhCentral);
        System.assertEquals(single.savings.energyWhCentral, duplicate.savings.energyWhCentral);
        System.assert(single.afterScenario.energyWhCentral > 0, 'Trim preserves remaining instruction input');
        System.assert(single.savings.energyWhCentral < single.baseline.energyWhCentral);
    }
    @IsTest static void changedVolumeOrScopeBlocksComparison() {
        OhmAuditImpactService.Snapshot before = OhmAuditImpactService.compute(graph(5400), null, null);
        OhmAuditImpactService.Snapshot after = OhmAuditImpactService.compute(graph(1000), null, null);
        System.assert(OhmAuditImpactService.comparable(JSON.serialize(before), JSON.serialize(after)), 'Source size may change under identical assumptions');
        OhmDTO.VolumeInput changed = new AssumptionVolumeProvider().defaultVolume();
        changed.sessionsPerPeriod *= 2;
        OhmAuditImpactService.Snapshot other = OhmAuditImpactService.compute(graph(1000), null, changed);
        System.assertEquals(false, OhmAuditImpactService.comparable(JSON.serialize(before), JSON.serialize(other)));
        System.assertEquals(false, OhmAuditImpactService.comparable(null, JSON.serialize(other)), 'Historical finding rollups are not modeled baselines');
    }
    @IsTest static void unavailableSourceHasNoDisplayedZeroEstimate() {
        Id reportId = new OhmPersistenceService().createReport();
        OhmAuditImpactService.save(reportId, new OhmDTO.AgentModel(), null, null);
        Agent_Audit_Report__c report = [SELECT Modeled_Energy_Wh__c, Coverage_Status__c FROM Agent_Audit_Report__c WHERE Id = :reportId];
        System.assertEquals(null, report.Modeled_Energy_Wh__c);
        System.assertEquals('Incomplete', report.Coverage_Status__c);
    }
    @IsTest static void factorsDiscloseEveryConstantBehindTheModel() {
        Map<String, Object> f = OhmAuditImpactService.factors();
        for (String key : new List<String>{'energyPerPromptWh', 'gridIntensityGco2ePerWh', 'waterMlPerWh', 'referencePromptTokens', 'charsPerToken', 'methodologyVersion', 'telemetryBacked', 'confidence'}) {
            System.assert(f.containsKey(key), 'Disclosed factor missing: ' + key);
        }
        Map<String, Object> energy = (Map<String, Object>) f.get('energyPerPromptWh');
        System.assertEquals(OhmConstants.load().energyPerPromptWh().central, energy.get('central'));
        System.assert((Decimal) energy.get('low') < (Decimal) energy.get('high'), 'band must be ordered');
        System.assertEquals(false, f.get('telemetryBacked'), 'No figure is telemetry-backed');
        System.assertEquals('Low', f.get('confidence'));
    }
    @IsTest static void savedSnapshotBandsReachFleetRowsAndDetailWithRequestsPerYear() {
        OhmAuditImpactService.Snapshot data = OhmAuditImpactService.compute(graph(5400), null, null);
        String json = JSON.serialize(data);
        Decimal perArtifact = Decimal.valueOf(String.valueOf(data.baseline.assumptions.get('annualCallsPerArtifact')));
        System.assert(perArtifact > 0, 'the snapshot records the requests/year it modeled');

        OhmDTO.ProcessSummaryDTO row = new OhmDTO.ProcessSummaryDTO();
        OhmAuditImpactService.applyBands(row, json);
        System.assertEquals(perArtifact, row.annualCalls, 'fleet rows carry the modeled requests/year so the UI can rescale');
        System.assertEquals(data.baseline.co2eGCentral, row.co2eGCentral);
        System.assertEquals(data.baseline.waterMlHigh, row.waterMlHigh);
        System.assertEquals(data.savings.energyWhCentral, row.savingsWhCentral);
        System.assertEquals(data.assumptionSummary, row.impactAssumptions);
        System.assertNotEquals(null, row.impactFactors);

        OhmDTO.ProcessDetailDTO detail = new OhmDTO.ProcessDetailDTO();
        OhmAuditImpactService.applyBands(detail, json);
        System.assertEquals(perArtifact, detail.annualCalls);
        System.assertEquals(data.savings.energyWhLow, detail.savingsWhLow);
        System.assertEquals(data.baseline.co2eGLow, detail.co2eGLow);

        OhmDTO.ProcessSummaryDTO blank = new OhmDTO.ProcessSummaryDTO();
        OhmAuditImpactService.applyBands(blank, null);
        System.assertEquals(null, blank.annualCalls, 'no snapshot means no invented footprint');
        System.assertNotEquals(null, blank.impactFactors, 'the constants are still disclosed');
        OhmAuditImpactService.applyBands(blank, 'not json');
        System.assertEquals(null, blank.co2eGCentral);
    }
}
