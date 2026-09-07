/** Regression contracts exercise production persistence, not only hand-inserted worklist rows. */
@IsTest
private class OhmRemediationLifecycleTest {
    private static final String PLANNER1 = '16j000000000001';
    private static final String PLANNER2 = '16j000000000002';

    private static OhmDTO.AgentModel graph(String plannerId, String version, String source) {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        graph.coverageComplete = true;
        graph.detectorCoverage.put('INSTRUCTION_BLOAT', 'Covered');
        OhmDTO.AgentNode agent = new OhmDTO.AgentNode();
        agent.id = plannerId;
        agent.developerName = 'Lab_Weather_' + version;
        agent.masterLabel = 'Weather';
        graph.agentsById.put(agent.id, agent);
        OhmDTO.TopicNode topic = new OhmDTO.TopicNode();
        topic.id = 'topic-' + version;
        topic.plannerId = plannerId;
        topic.developerName = 'weather_lookup_' + plannerId;
        topic.masterLabel = 'Weather Lookup';
        topic.instructions = source;
        topic.scope = source;
        topic.sourceKind = 'Versioned source import';
        topic.sourcePath = 'Weather.agent#weather_lookup';
        topic.sourceVersion = version;
        graph.topics.add(topic);
        return graph;
    }
    private static OhmDTO.Finding finding(OhmDTO.AgentModel graph) {
        OhmDTO.Finding finding = new OhmDTO.Finding();
        finding.signalType = 'INSTRUCTION_BLOAT';
        finding.artifactType = 'Topic';
        finding.artifactApiName = graph.topics[0].developerName;
        finding.artifactToolingId = graph.topics[0].id;
        finding.artifactLabel = 'Weather Lookup';
        finding.parentAgentApiName = graph.agentsById.values()[0].developerName;
        finding.severity = 'High';
        finding.confidence = 'High';
        finding.fixType = 'Trim_Instructions';
        finding.effort = 'Low';
        return finding;
    }
    private static Id persist(OhmDTO.AgentModel graph, List<OhmDTO.Finding> findings, Integer secondsAgo) {
        OhmPersistenceService persistence = new OhmPersistenceService();
        OhmDTO.AgentNode agent = graph.agentsById.values()[0];
        Id reportId = persistence.createProcessReport((Id)agent.id, agent.developerName);
        OhmDTO.EfficiencyResult rating = new OhmDTO.EfficiencyResult();
        rating.grade = findings.isEmpty() ? 'A' : 'C';
        rating.score = findings.isEmpty() ? 100 : 75;
        OhmAuditImpactService.save(reportId, graph, findings, null);
        persistence.persistFindings(reportId, graph, findings, rating);
        update new Agent_Audit_Report__c(Id = reportId, Run_Timestamp__c = System.now().addSeconds(-secondsAgo));
        Test.setCreatedDate(reportId, System.now().addSeconds(-secondsAgo));
        return reportId;
    }
    private static Id assign(OhmDTO.Finding finding) {
        Id taskId = OhmAuditController.assignFinding(finding.findingRecordId, UserInfo.getUserId(), Date.today().addDays(4));
        OhmAuditController.updateFindingStatus(finding.findingRecordId, 'Accepted');
        return taskId;
    }

    @IsTest static void republishedIssueRetainsTaskOwnerDateAndAcceptedState() {
        OhmDTO.AgentModel before = graph(PLANNER1, 'v1', 'Original weather instructions.');
        OhmDTO.Finding first = finding(before);
        persist(before, new List<OhmDTO.Finding>{ first }, 30);
        Id taskId = assign(first);
        OhmDTO.AgentModel after = graph(PLANNER2, 'v2', 'Original weather instructions.');
        OhmDTO.Finding next = finding(after);
        persist(after, new List<OhmDTO.Finding>{ next }, 10);
        Finding__c stored = [SELECT Issue_Key__c, Remediation_Task_Id__c, Finding_Status__c FROM Finding__c WHERE Id = :next.findingRecordId];
        System.assertEquals(taskId, stored.Remediation_Task_Id__c);
        System.assertEquals('Accepted', stored.Finding_Status__c);
        System.assertEquals([SELECT Issue_Key__c FROM Finding__c WHERE Id = :first.findingRecordId].Issue_Key__c, stored.Issue_Key__c);
        Task task = [SELECT OwnerId, ActivityDate, Status FROM Task WHERE Id = :taskId];
        System.assertEquals(UserInfo.getUserId(), task.OwnerId);
        System.assertEquals(Date.today().addDays(4), task.ActivityDate);
        System.assertEquals('In Progress', task.Status);
        System.assertEquals(1, OhmAuditController.getFindings(null, null).size());
        System.assertEquals(taskId, OhmAuditController.getFindings(null, null)[0].taskId);
    }

    @IsTest static void coveredCleanAuditResolvesTaskAndKeepsAfterSource() {
        OhmDTO.AgentModel before = graph(PLANNER1, 'v1', 'Weather instructions with redundant prose.');
        OhmDTO.Finding original = finding(before);
        Id first = persist(before, new List<OhmDTO.Finding>{ original }, 30);
        Id taskId = assign(original);
        OhmDTO.AgentModel after = graph(PLANNER2, 'v2', 'Get the weather.');
        // Other detectors may remain unknown, but this artifact's instruction audit is covered.
        after.coverageComplete = false;
        after.detectorCoverage.put('MODEL_RIGHTSIZING', 'Unknown');
        Id second = persist(after, new List<OhmDTO.Finding>(), 10);
        System.assertEquals('Applied', [SELECT Finding_Status__c FROM Finding__c WHERE Id = :original.findingRecordId].Finding_Status__c);
        System.assertEquals(true, [SELECT IsClosed FROM Task WHERE Id = :taskId].IsClosed);
        System.assertEquals(0, OhmAuditController.getRecommendations().size());
        String artifactKey = OhmPersistenceService.artifactKey('lab_weather', 'Topic', after.topics[0].developerName, null);
        Audit_Artifact_Snapshot__c saved = OhmPersistenceService.loadSnapshots(new Set<Id>{ second }).get(second).get(artifactKey);
        System.assertEquals('Get the weather.', saved.Instructions__c);
        System.assertEquals('v2', saved.Source_Version__c);
        System.assertEquals(OhmPersistenceService.sha256(saved.Instructions__c), saved.Source_Hash__c);
        Set<Id> reports = new Set<Id>{ first, second };
        System.assertEquals(2, [SELECT COUNT() FROM Agent_Audit_Report__c WHERE Id IN :reports]);
    }

    @IsTest static void unknownCoverageDoesNotResolveExistingWork() {
        OhmDTO.AgentModel before = graph(PLANNER1, 'v1', 'Weather instructions.');
        OhmDTO.Finding original = finding(before);
        persist(before, new List<OhmDTO.Finding>{ original }, 30);
        Id taskId = assign(original);
        OhmDTO.AgentModel after = graph(PLANNER2, 'v2', null);
        after.coverageComplete = false;
        after.detectorCoverage.put('INSTRUCTION_BLOAT', 'Unknown');
        persist(after, new List<OhmDTO.Finding>(), 10);
        System.assertEquals('Accepted', [SELECT Finding_Status__c FROM Finding__c WHERE Id = :original.findingRecordId].Finding_Status__c);
        System.assertEquals(false, [SELECT IsClosed FROM Task WHERE Id = :taskId].IsClosed);
    }

    @IsTest static void reappearingIssueReopensSameTaskWithoutLosingAssignment() {
        OhmDTO.AgentModel firstGraph = graph(PLANNER1, 'v1', 'Repeated instructions.');
        OhmDTO.Finding first = finding(firstGraph);
        persist(firstGraph, new List<OhmDTO.Finding>{ first }, 30);
        Id taskId = assign(first);
        OhmAuditController.updateFindingStatus(first.findingRecordId, 'Applied');
        OhmDTO.AgentModel again = graph(PLANNER2, 'v2', 'Repeated instructions again.');
        OhmDTO.Finding next = finding(again);
        persist(again, new List<OhmDTO.Finding>{ next }, 10);
        Finding__c stored = [SELECT Finding_Status__c, Remediation_Task_Id__c FROM Finding__c WHERE Id = :next.findingRecordId];
        System.assertEquals('Open', stored.Finding_Status__c);
        System.assertEquals(taskId, stored.Remediation_Task_Id__c);
        Task task = [SELECT Status, OwnerId, ActivityDate FROM Task WHERE Id = :taskId];
        System.assertEquals('Not Started', task.Status);
        System.assertEquals(UserInfo.getUserId(), task.OwnerId);
        System.assertEquals(Date.today().addDays(4), task.ActivityDate);
    }

    @IsTest static void sameLabelsDifferentArtifactsRemainSeparateIssues() {
        OhmDTO.AgentModel model = graph(PLANNER1, 'v1', 'Some instructions.');
        OhmDTO.Finding first = finding(model);
        OhmDTO.Finding second = finding(model);
        second.artifactApiName = 'another_weather_lookup_' + PLANNER1;
        persist(model, new List<OhmDTO.Finding>{ first, second }, 10);
        System.assertEquals(2, OhmAuditController.getFindings(null, null).size());
    }

    @IsTest static void assignmentIsIdempotentAndOpenClearsTaskCompletion() {
        OhmDTO.AgentModel model = graph(PLANNER1, 'v1', 'Some instructions.');
        OhmDTO.Finding finding = finding(model);
        persist(model, new List<OhmDTO.Finding>{ finding }, 10);
        Id taskId = assign(finding);
        System.assertEquals(taskId, OhmAuditController.assignFinding(finding.findingRecordId, null, null));
        System.assertEquals(null, [SELECT ActivityDate FROM Task WHERE Id = :taskId].ActivityDate, 'Clearing a due date is an explicit assignment edit.');
        OhmAuditController.updateFindingStatus(finding.findingRecordId, 'Applied');
        OhmAuditController.updateFindingStatus(finding.findingRecordId, 'Open');
        System.assertEquals('Not Started', [SELECT Status FROM Task WHERE Id = :taskId].Status);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Id = :taskId]);
    }

    @IsTest static void exactArtifactDiffSurvivesCleanAuditAndPublicationIds() {
        OhmDTO.AgentModel before = graph(PLANNER1, 'v1', 'Weather instructions. '.repeat(50));
        OhmDTO.Finding original = finding(before);
        persist(before, new List<OhmDTO.Finding>{ original }, 30);
        OhmDTO.AgentModel after = graph(PLANNER2, 'v2', 'Get the weather.');
        persist(after, new List<OhmDTO.Finding>(), 10);
        String key = OhmPersistenceService.artifactKey('lab_weather', 'Topic', after.topics[0].developerName, null);
        OhmDTO.DiffDTO diff = OhmAuditController.getArtifactDiff((Id)PLANNER2, key);
        System.assertEquals(true, diff.comparable);
        System.assertEquals(before.topics[0].instructions, diff.beforeInstructions);
        System.assertEquals(after.topics[0].instructions, diff.afterInstructions);
        System.assert(diff.energyDeltaWh > 0);
        System.assert(diff.afterEnergyWhCentral > 0, 'A clean audit retains residual modeled instruction cost.');
        System.assertEquals(false, OhmAuditController.getArtifactDiff((Id)PLANNER2, 'different-artifact').comparable);
    }

    @IsTest static void changedScenarioWithholdsDeltaButRetainsExactSourceDiff() {
        OhmDTO.AgentModel before = graph(PLANNER1, 'v1', 'Original weather instructions.');
        persist(before, new List<OhmDTO.Finding>(), 30);
        OhmDTO.AgentModel after = graph(PLANNER2, 'v2', 'Short weather instructions.');
        Id reportId = persist(after, new List<OhmDTO.Finding>(), 10);
        OhmDTO.VolumeInput increasedUsage = new AssumptionVolumeProvider().defaultVolume();
        increasedUsage.sessionsPerPeriod *= 2;
        OhmAuditImpactService.save(reportId, after, new List<OhmDTO.Finding>(), increasedUsage);
        String key = OhmPersistenceService.artifactKey('lab_weather', 'Topic', after.topics[0].developerName, null);
        OhmDTO.DiffDTO diff = OhmAuditController.getArtifactDiff((Id)PLANNER2, key);
        System.assertEquals(false, diff.comparable);
        System.assertEquals(null, diff.energyDeltaWh);
        System.assertEquals(before.topics[0].instructions, diff.beforeInstructions);
        System.assertEquals(after.topics[0].instructions, diff.afterInstructions);
    }

    @IsTest static void logicalProcessTrendsRetainPriorPublicationAndSeparateSimilarNames() {
        OhmDTO.AgentModel first = graph(PLANNER1, 'v1', 'Weather instructions. '.repeat(50));
        Id firstReport = persist(first, new List<OhmDTO.Finding>(), 30);
        OhmDTO.AgentModel latest = graph(PLANNER2, 'v2', 'Get the weather.');
        Id latestReport = persist(latest, new List<OhmDTO.Finding>(), 10);
        OhmDTO.AgentModel other = graph('16j000000000003', 'v1', 'Different process.');
        other.agentsById.values()[0].developerName = 'Lab_Weather_Alerts_v1';
        persist(other, new List<OhmDTO.Finding>(), 20);
        OhmDTO.TrendDTO trend = OhmAuditController.getTrends((Id)PLANNER2);
        System.assertEquals(2, trend.points.size());
        System.assertEquals(firstReport, trend.points[0].reportId);
        System.assertEquals(latestReport, trend.points[1].reportId);
        System.assert(trend.realizedSavingsWh > 0, 'Comparable scenario history survives the publication ID change.');
        System.assertEquals(2, OhmAuditController.getTrends((Id)PLANNER1).points.size(), 'Opening a historical version reaches the same process history.');
        OhmDTO.TrendDTO org = OhmAuditController.getTrends(null);
        System.assertEquals(2, org.perAgent.size(), 'Two logical processes produce two histories, not three planner-version rows.');
        System.assertEquals(0, org.points.size(), 'Process histories do not become fleet points.');
        System.assertEquals(0, org.realizedSavingsWh);
    }

    @IsTest static void snapshotRoundTripPreservesWhitespaceQuotesAndHash() {
        String original = '  \n"Get the weather."\t\n  ';
        OhmDTO.AgentModel model = graph(PLANNER1, 'v1', original);
        Id reportId = new OhmPersistenceService().createProcessReport((Id)PLANNER1, 'Lab_Weather_v1');
        OhmArtifactSnapshotService.capture(reportId, model, 'lab_weather');
        String key = OhmPersistenceService.artifactKey('lab_weather', 'Topic', model.topics[0].developerName, null);
        Audit_Artifact_Snapshot__c source = OhmPersistenceService.loadSnapshots(new Set<Id>{ reportId }).get(reportId).get(key);
        System.assertEquals(original, source.Instructions__c);
        System.assertEquals(OhmPersistenceService.sha256(original), source.Source_Hash__c);
        System.assertEquals('Complete', source.Coverage_Status__c);
        // Corrupt or lossy historical storage must not be presented as exact source evidence.
        update new Audit_Artifact_Snapshot__c(Id = source.Id, Source_Json__c = JSON.serialize(original.trim()));
        source = OhmPersistenceService.loadSnapshots(new Set<Id>{ reportId }).get(reportId).get(key);
        System.assertEquals('Source hash mismatch', source.Coverage_Status__c);
        System.assertEquals(null, source.Instructions__c);
    }

    @IsTest static void oversizedSourceIsNeverSavedAsACompleteTruncatedSnapshot() {
        OhmDTO.AgentModel model = graph(PLANNER1, 'v1', 'x'.repeat(131073));
        Id reportId = new OhmPersistenceService().createProcessReport((Id)PLANNER1, 'Lab_Weather_v1');
        OhmArtifactSnapshotService.capture(reportId, model, 'lab_weather');
        Audit_Artifact_Snapshot__c source = [SELECT Instructions__c, Source_Hash__c, Character_Count__c, Coverage_Status__c
            FROM Audit_Artifact_Snapshot__c WHERE Agent_Audit_Report__c = :reportId AND Artifact_Type__c = 'Topic'];
        System.assertEquals(null, source.Instructions__c);
        System.assertEquals(131073, source.Character_Count__c);
        System.assertEquals('Unsupported size', source.Coverage_Status__c);
        System.assertEquals(OhmPersistenceService.sha256(model.topics[0].instructions), source.Source_Hash__c);
        System.assertEquals(false, model.coverageComplete);
    }
}
