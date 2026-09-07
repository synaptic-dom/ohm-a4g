@IsTest
private class OhmAuditCoordinatorTest {
    private static final String PID = '16j000000000001AAA';
    private static final String TID = '16k000000000001AAA';
    private class Inventory extends OhmAuditCoordinator.InventoryGateway {
        public String revision = '1';
        public override OhmDTO.AgentModel read(Id plannerId) {
            OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
            OhmDTO.AgentNode agent = new OhmDTO.AgentNode();
            agent.id = PID; agent.developerName = 'Retrieved_Weather_v1'; agent.masterLabel = 'Retrieved Weather';
            graph.agentsById.put(PID, agent);
            OhmDTO.TopicNode topic = new OhmDTO.TopicNode();
            topic.id = TID; topic.plannerId = PID; topic.developerName = 'weather_16j000000000001'; topic.masterLabel = 'Weather';
            graph.topics.add(topic);
            graph.topicsByPlanner.put(PID, new List<OhmDTO.TopicNode>{topic});
            graph.metadataFingerprint = OhmDiscoveryService.fingerprint(graph, versions());
            return graph;
        }
        public Map<String, String> versions() { return new Map<String, String>{PID => revision, TID => revision}; }
        public override String plannerFingerprint(OhmDTO.AgentModel graph, String plannerId) { return graph.metadataFingerprint; }
        public override void attach(OhmDTO.AgentModel graph, Set<Id> sourceIds) {
            OhmSourceImportService.applyPinnedSources(graph, versions(), sourceIds);
            graph.detectorCoverage.put('INSTRUCTION_BLOAT', graph.topics[0].instructions == null ? 'Unknown' : 'Covered');
            graph.detectorCoverage.put('REDUNDANT_CALLS', 'Unknown');
            graph.detectorCoverage.put('MODEL_RIGHTSIZING', 'Covered');
            graph.detectorCoverage.put('LLM_WHERE_DETERMINISTIC', 'Covered');
            graph.coverageWarnings.add('Execution graph unavailable; this is static source evidence.');
        }
    }
    private class Retrieval extends OhmAuditCoordinator.RetrievalGateway {
        public Integer pending = 0;
        public Integer starts = 0;
        public Boolean rejectHash = false;
        public Boolean transientFailure = false;
        public Boolean permissionFailure = false;
        public Integer sourceLength = 18000;
        public Boolean dependencyChanged = false;
        public Boolean duplicateWarnings = false;
        public override void validate(String stateJson) {
            if (dependencyChanged) throw new OhmAuditCoordinator.AuditRunException('Prompt version changed after retrieval. Re-audit.');
        }
        public override String start(OhmDTO.AgentModel graph) {
            starts++;
            if (transientFailure || permissionFailure) {
                OhmSalesforceApi.SourceApiException ex = new OhmSalesforceApi.SourceApiException('Source connection unavailable.');
                ex.retryable = transientFailure; ex.httpStatus = transientFailure ? 503 : 403;
                throw ex;
            }
            return '{}';
        }
        public override OhmAuditCoordinator.RetrievalOutcome poll(String state, OhmDTO.AgentModel graph) {
            OhmAuditCoordinator.RetrievalOutcome result = new OhmAuditCoordinator.RetrievalOutcome();
            result.stateJson = '{}'; result.pending = pending > 0;
            if (pending > 0) { pending--; return result; }
            OhmSourceImportService.SourceBundle bundle = new OhmSourceImportService.SourceBundle();
            bundle.schemaVersion = 1; bundle.plannerId = PID; bundle.plannerApiName = 'Retrieved_Weather_v1';
            bundle.configurationSource = 'config:\n   developer_name: "Retrieved_Weather"\n';
            bundle.configurationSourcePath = 'metadata://aiAuthoringBundles/Retrieved_Weather/Retrieved_Weather.agent';
            bundle.configurationSourceHash = OhmSourceImportService.sha256(bundle.configurationSource);
            bundle.metadataFingerprint = graph.metadataFingerprint; bundle.sourceRevision = 'published-version-1';
            bundle.provenance = 'Retrieved'; bundle.retrievedAt = System.now();
            bundle.artifacts = new List<OhmSourceImportService.SourceArtifact>();
            bundle.warnings = new List<String>();
            if (duplicateWarnings) {
                bundle.warnings.add('Conditional branches retained; execution order unavailable.');
                result.warnings = bundle.warnings;
            }
            for (String id : new List<String>{PID, TID}) {
                OhmSourceImportService.SourceArtifact source = new OhmSourceImportService.SourceArtifact();
                source.id = id; source.instructions = id == PID ? '' : 'w'.repeat(sourceLength);
                source.sourceHash = rejectHash ? 'incorrect' : OhmSourceImportService.sha256(source.instructions);
                source.sourceKind = 'RetrievedAgentScript'; source.sourceVersion = 'published-version-1';
                source.sourceVersionIdentifier = '1'; source.sourceApiName = 'Retrieved_Weather';
                source.sourcePath = 'AiAuthoringBundle/Retrieved_Weather#' + (id == PID ? 'system' : 'weather');
                source.sourceRetrievedAt = bundle.retrievedAt; source.sourceBindingVerified = true;
                bundle.artifacts.add(source);
            }
            result.bundle = bundle;
            return result;
        }
    }
    private class Review extends OhmAuditCoordinator.ReviewGateway {
        public Integer calls = 0;
        public Boolean unavailable = false;
        public Boolean empty = false;
        public Inventory changeInventory;
        public Retrieval changePrompt;
        public String result = '{"schemaVersion":1,"rubricVersion":"integration-fixture","categories":[],"artifacts":[]}';
        public override String review(OhmDTO.AgentModel graph) {
            calls++;
            System.assertNotEquals(null, graph.topics[0].instructions, 'Reviewer receives this run\'s acquired instructions.');
            System.assertEquals(true, graph.topics[0].sourceBindingVerified, 'Source binding is verified before reviewer invocation.');
            System.assertNotEquals(null, graph.agentsById.get(PID).configurationSource, 'Full configuration is supplied as separate review context.');
            if (unavailable) throw new OhmAuditCoordinator.AuditRunException('The Salesforce review template is unavailable.');
            if (changeInventory != null) changeInventory.revision = 'changed-during-review';
            if (changePrompt != null) changePrompt.dependencyChanged = true;
            return empty ? null : result;
        }
    }
    private static Id setup(Inventory sourceInventory, Retrieval sourceRetrieval) {
        OhmAuditCoordinator.inventory = sourceInventory;
        OhmAuditCoordinator.retrieval = sourceRetrieval;
        OhmAuditCoordinator.reviewer = new Review();
        return new OhmPersistenceService().createProcessReport((Id)PID, 'Retrieved_Weather_v1');
    }
    private static Agent_Audit_Report__c read(Id reportId) {
        return [SELECT Run_Status__c, Run_Stage_Message__c, Source_Retrieval_Context__c, Coverage_Status__c,
                       Modeled_Energy_Wh__c, Review_Result__c, Review_Summary__c FROM Agent_Audit_Report__c WHERE Id = :reportId];
    }
    private static void step(Id reportId) { OhmAuditCoordinator.advance(reportId, false); }

    @IsTest static void queueBudgetOverridesScratchDefaultAndFailsDurablyAtLimit() {
        AsyncOptions options = OhmAuditCoordinator.initialQueueOptions();
        System.assertEquals(200, options.MaximumQueueableStackDepth,
            'The initial job must override the scratch org default of five and allow bounded retrieval retries.');
        Retrieval retrieval = new Retrieval();
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId);
        OhmAuditCoordinator.RunState state = (OhmAuditCoordinator.RunState)JSON.deserialize(
            read(reportId).Source_Retrieval_Context__c, OhmAuditCoordinator.RunState.class);
        state.jobExecutions = 199;
        update new Agent_Audit_Report__c(Id = reportId, Source_Retrieval_Context__c = JSON.serialize(state));
        step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assert(read(reportId).Run_Stage_Message__c.contains('job budget'));
        System.assertEquals(0, retrieval.starts, 'An exhausted chain cannot submit more retrieval work.');
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :reportId]);
    }

    @IsTest static void sourceAcquisitionFinishesOnceAndPreservesExactProvenance() {
        Retrieval retrieval = new Retrieval();
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId);
        System.assertEquals('Analyzing', read(reportId).Run_Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :reportId]);
        step(reportId);
        System.assertEquals('Complete', read(reportId).Run_Status__c);
        System.assertNotEquals(null, read(reportId).Review_Result__c, 'Review is committed with the completed source audit.');
        System.assertEquals(1, ((Review)OhmAuditCoordinator.reviewer).calls);
        Map<String, Object> compactReview = (Map<String, Object>)JSON.deserializeUntyped(read(reportId).Review_Summary__c);
        System.assertEquals(true, compactReview.get('summaryOnly'));
        System.assertEquals('Incomplete', read(reportId).Coverage_Status__c, 'Source retrieval does not invent execution coverage.');
        System.assert(read(reportId).Modeled_Energy_Wh__c > 0, 'Completion includes independent modeled impact.');
        Integer findings = [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :reportId];
        System.assertEquals(1, findings);
        Audit_Artifact_Snapshot__c snapshot = [SELECT Source_Retrieved_At__c, Source_Hash__c, Source_Binding_Verified__c,
            Source_Version_Identifier__c FROM Audit_Artifact_Snapshot__c WHERE Agent_Audit_Report__c = :reportId AND Artifact_Type__c = 'Topic'];
        System.assertNotEquals(null, snapshot.Source_Retrieved_At__c);
        System.assertEquals(true, snapshot.Source_Binding_Verified__c);
        System.assertEquals('1', snapshot.Source_Version_Identifier__c);
        System.assertEquals(OhmSourceImportService.sha256('w'.repeat(18000)), snapshot.Source_Hash__c);
        step(reportId); OhmAuditRunService.finish(reportId, null);
        System.assertEquals(findings, [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :reportId], 'Duplicate terminal work must be a no-op.');
    }

    @IsTest static void pendingAcquisitionHasNoPartialFindingsAndResumesFromContext() {
        Retrieval retrieval = new Retrieval(); retrieval.pending = 1;
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId);
        System.assertEquals('Discovering', read(reportId).Run_Status__c);
        System.assert(read(reportId).Run_Stage_Message__c.contains('Waiting'));
        System.assertEquals(0, [SELECT COUNT() FROM Ohm_Instruction_Source__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c]);
        step(reportId); step(reportId);
        System.assertEquals('Complete', read(reportId).Run_Status__c);
        System.assertEquals(1, retrieval.starts, 'Resume polls the existing retrieval instead of submitting it twice.');
    }

    @IsTest static void sharedBundleWarningsAreStoredOnce() {
        Retrieval retrieval = new Retrieval(); retrieval.duplicateWarnings = true;
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId);
        Ohm_Instruction_Source__c source = [SELECT Manifest__c FROM Ohm_Instruction_Source__c LIMIT 1];
        OhmSourceImportService.SourceBundle bundle = (OhmSourceImportService.SourceBundle)JSON.deserialize(
            source.Manifest__c, OhmSourceImportService.SourceBundle.class);
        System.assertEquals(new List<String>{'Conditional branches retained; execution order unavailable.'}, bundle.warnings,
            'The retrieval result and bundle can share the same warning list; merging must not duplicate it.');
    }

    @IsTest static void publicationChangeRejectsEvidenceWithoutFindings() {
        Inventory inventory = new Inventory();
        Id reportId = setup(inventory, new Retrieval());
        step(reportId); step(reportId); inventory.revision = '2'; step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assert(read(reportId).Run_Stage_Message__c.contains('changed'));
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Audit_Artifact_Snapshot__c]);
    }

    @IsTest static void invalidSourceHashFailsDurablyAndDoesNotPersistPartialEvidence() {
        Retrieval retrieval = new Retrieval(); retrieval.rejectHash = true;
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Ohm_Instruction_Source__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c]);
    }

    @IsTest static void cleanRetrievedRunUsesItsPinnedSourceAndClosesExistingTask() {
        Inventory inventory = new Inventory();
        Retrieval retrieval = new Retrieval();
        Id first = setup(inventory, retrieval);
        step(first); step(first); step(first); step(first);
        Finding__c issue = [SELECT Id FROM Finding__c WHERE Agent_Audit_Report__c = :first LIMIT 1];
        Id taskId = OhmAuditController.createFindingRemediationTask(issue.Id, null);
        Date due = Date.today().addDays(2);
        update new Task(Id = taskId, ActivityDate = due, Status = 'In Progress');
        retrieval.sourceLength = 20;
        Id second = setup(inventory, retrieval);
        step(second); step(second); step(second); step(second);
        System.assertEquals('Complete', read(second).Run_Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :second]);
        Task original = [SELECT Status, ActivityDate FROM Task WHERE Id = :taskId];
        System.assertEquals('Completed', original.Status);
        System.assertEquals(due, original.ActivityDate);
        Audit_Artifact_Snapshot__c afterSource = [SELECT Character_Count__c FROM Audit_Artifact_Snapshot__c
            WHERE Agent_Audit_Report__c = :second AND Artifact_Type__c = 'Topic'];
        System.assertEquals(20, afterSource.Character_Count__c, 'The previous imported/retrieved source cannot silently fill this run.');
        System.assertEquals(2, [SELECT COUNT() FROM Ohm_Instruction_Source__c], 'Both immutable acquisitions are retained.');
    }

    @IsTest static void transientRetriesAreBoundedAndPermissionErrorsAreNotRetried() {
        Retrieval retrieval = new Retrieval(); retrieval.transientFailure = true;
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(3, retrieval.starts, 'Initial attempt plus two bounded retries.');
        retrieval = new Retrieval(); retrieval.permissionFailure = true;
        reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(1, retrieval.starts, 'Permission failure requires connection repair.');
    }

    @IsTest static void independentPromptChangeBeforeFinalizationPreventsFindings() {
        Retrieval retrieval = new Retrieval();
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId);
        retrieval.dependencyChanged = true; step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Audit_Artifact_Snapshot__c]);
    }

    @IsTest static void reviewerFailureNeverCompletesWithDeterministicResultsAlone() {
        Id reportId = setup(new Inventory(), new Retrieval());
        Review review = new Review(); review.unavailable = true;
        OhmAuditCoordinator.reviewer = review;
        step(reportId); step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(null, read(reportId).Review_Result__c);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :reportId]);
        System.assertEquals(0, [SELECT COUNT() FROM Audit_Artifact_Snapshot__c WHERE Agent_Audit_Report__c = :reportId]);
        System.assertEquals(1, review.calls);
    }

    @IsTest static void publicationChangesDuringReviewDiscardTheReviewAndFindings() {
        Inventory inv = new Inventory();
        Id reportId = setup(inv, new Retrieval());
        Review review = new Review(); review.changeInventory = inv;
        OhmAuditCoordinator.reviewer = review;
        step(reportId); step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assert(read(reportId).Run_Stage_Message__c.contains('changed during'));
        System.assertEquals(null, read(reportId).Review_Result__c);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :reportId]);
    }

    @IsTest static void promptChangesDuringReviewAreRevalidatedBeforePersistence() {
        Retrieval retrieval = new Retrieval();
        Id reportId = setup(new Inventory(), retrieval);
        Review review = new Review(); review.changePrompt = retrieval;
        OhmAuditCoordinator.reviewer = review;
        step(reportId); step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(null, read(reportId).Review_Result__c);
        System.assertEquals(0, [SELECT COUNT() FROM Audit_Artifact_Snapshot__c WHERE Agent_Audit_Report__c = :reportId]);
    }

    @IsTest static void emptyReviewerResponseCannotProduceACompletedAudit() {
        Id reportId = setup(new Inventory(), new Retrieval());
        Review review = new Review(); review.empty = true;
        OhmAuditCoordinator.reviewer = review;
        step(reportId); step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(null, read(reportId).Review_Result__c);
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c WHERE Agent_Audit_Report__c = :reportId]);
    }

    @IsTest static void tamperedConfigurationIsRejectedBeforeReview() {
        Id reportId = setup(new Inventory(), new Retrieval());
        step(reportId); step(reportId); step(reportId);
        Ohm_Instruction_Source__c source = [SELECT Id, Manifest__c FROM Ohm_Instruction_Source__c LIMIT 1];
        OhmSourceImportService.SourceBundle bundle = (OhmSourceImportService.SourceBundle)JSON.deserialize(source.Manifest__c, OhmSourceImportService.SourceBundle.class);
        bundle.configurationSource += 'UNVERIFIED';
        source.Manifest__c = JSON.serialize(bundle); update source;
        step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assertEquals(0, ((Review)OhmAuditCoordinator.reviewer).calls);
        System.assertEquals(null, read(reportId).Review_Result__c);
    }

    @IsTest static void excessiveSourceIsRejectedWithoutTruncation() {
        Retrieval retrieval = new Retrieval(); retrieval.sourceLength = 132000;
        Id reportId = setup(new Inventory(), retrieval);
        step(reportId); step(reportId); step(reportId);
        System.assertEquals('Failed', read(reportId).Run_Status__c);
        System.assert(read(reportId).Run_Stage_Message__c.contains('capacity'));
        System.assertEquals(0, [SELECT COUNT() FROM Ohm_Instruction_Source__c]);
    }

    @IsTest static void startAuditReturnsQueuedRunAndRecordsJobHandle() {
        Test.startTest();
        Id reportId = OhmAuditController.startAudit();
        Agent_Audit_Report__c report = [SELECT Run_Status__c, Async_Job_Id__c FROM Agent_Audit_Report__c WHERE Id = :reportId];
        System.assertEquals('Queued', report.Run_Status__c, 'The UI receives a handle before retrieval begins.');
        System.assertNotEquals(null, report.Async_Job_Id__c);
        Test.stopTest();
        System.assertNotEquals('Complete', read(reportId).Run_Status__c, 'No stale local-source audit is completed in the enqueue request.');
    }

    @IsTest(SeeAllData=true) static void processEndpointReturnsQueuedExactPublication() {
        Id plannerId = OhmAuditTestSupport.scriptPlannerId();
        System.assertNotEquals(null, plannerId, 'A supported Agent Script control must be published before integration tests.');
        GenAiPlannerDefinition planner = [SELECT Id, DeveloperName FROM GenAiPlannerDefinition
            WHERE Id = :plannerId LIMIT 1];
        Test.startTest();
        Id reportId = OhmAuditController.auditProcess(planner.Id);
        Agent_Audit_Report__c report = [SELECT Run_Status__c, Target_Planner_Id__c, Target_Planner_Api_Name__c,
            Async_Job_Id__c FROM Agent_Audit_Report__c WHERE Id = :reportId];
        System.assertEquals('Queued', report.Run_Status__c);
        System.assertEquals(String.valueOf(planner.Id), report.Target_Planner_Id__c);
        System.assertEquals(planner.DeveloperName, report.Target_Planner_Api_Name__c);
        System.assertNotEquals(null, report.Async_Job_Id__c);
        Test.stopTest();
    }
}
