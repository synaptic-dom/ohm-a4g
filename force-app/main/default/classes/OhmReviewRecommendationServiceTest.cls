@IsTest
private class OhmReviewRecommendationServiceTest {
    private static final Id PID = '16j000000000001AAA';
    private static final Id REPORT = 'a00000000000001AAA';
    private class Stub extends OhmReviewRecommendationService.Gateway {
        OhmDTO.ProcessDetailDTO value;
        Integer calls = 0;
        Stub(OhmDTO.ProcessDetailDTO value) { this.value = value; }
        public override OhmDTO.ProcessDetailDTO detail(Id plannerId) {
            System.assertEquals(PID, plannerId); calls++; return value;
        }
    }
    private static OhmReviewService.Category category(String id, OhmReviewService.Issue issue) {
        OhmReviewService.Category result = new OhmReviewService.Category();
        result.id = id; result.label = 'Input efficiency'; result.rating = 'B'; result.status = 'reviewed';
        result.issues.add(issue); return result;
    }
    private static OhmReviewService.QuoteEvidence quote(String id, String text) {
        OhmReviewService.QuoteEvidence result = new OhmReviewService.QuoteEvidence();
        result.artifactId = id; result.quote = text; return result;
    }
    private static OhmReviewService.Result review() {
        OhmReviewService.Result result = new OhmReviewService.Result();
        result.reviewedAt = System.now();
        OhmReviewService.Issue issue = new OhmReviewService.Issue();
        issue.code = 'INPUT_UNNECESSARY_CONTEXT'; issue.origin = 'Reviewer';
        issue.explanation = 'Unrelated context distracts from the task.';
        issue.recommendation = 'Remove the unrelated biography.';
        issue.preserve = 'Keep all workshop and scheduling constraints.';
        issue.validation = 'Compare representative workshop recommendations.';
        issue.evidence = new List<OhmReviewService.QuoteEvidence>{quote('prompt-source', 'Repeat the complete biography.'),
            quote('configuration:' + PID, 'run @actions.workshop_recommendation')};
        OhmReviewService.ArtifactResult artifact = new OhmReviewService.ArtifactResult();
        artifact.artifactId = 'prompt-source'; artifact.artifactKey = 'bundle|Action|prompt';
        artifact.artifactType = 'Action'; artifact.label = 'Workshop prompt'; artifact.sourcePath = 'prompt/source.xml';
        artifact.categories.add(category('INPUT', issue)); result.artifacts.add(artifact);
        result.categories.add(category('INPUT', issue));
        OhmReviewService.ContextSource context = new OhmReviewService.ContextSource();
        context.artifactId = 'configuration:' + PID; context.plannerId = String.valueOf(PID);
        context.label = 'Workshop configuration'; context.sourcePath = 'bundle.agent';
        result.contextSources.add(context); return result;
    }
    private static OhmDTO.ProcessDetailDTO detail(OhmReviewService.Result review) {
        OhmDTO.ProcessDetailDTO result = new OhmDTO.ProcessDetailDTO();
        result.plannerId = PID; result.reportId = REPORT; result.label = 'Workshop bundle';
        result.plannerApiName = 'Workshop_v1'; result.sourceCurrent = true;
        result.reviewJson = JSON.serialize(review); result.nodes = new List<OhmDTO.NodeDTO>();
        for (String id : new List<String>{String.valueOf(PID), 'prompt-source'}) {
            OhmDTO.NodeDTO node = new OhmDTO.NodeDTO(); node.id = id; result.nodes.add(node);
        }
        return result;
    }
    private static OhmReviewRecommendationService.RecommendationPage load(OhmDTO.ProcessDetailDTO detail) {
        OhmReviewRecommendationService.gateway = new Stub(detail);
        return OhmReviewRecommendationService.getReviewRecommendations(PID);
    }
    @IsTest static void exposesOriginalSavedIssueAndActionableSourceLinksWithoutSavings() {
        OhmReviewService.Result review = review(); Stub stub = new Stub(detail(review));
        OhmReviewRecommendationService.gateway = stub;
        OhmReviewRecommendationService.RecommendationPage page = OhmReviewRecommendationService.getReviewRecommendations(PID);
        System.assert(page.reviewAvailable && page.sourceCurrent); System.assertEquals(1, stub.calls);
        System.assertEquals(2, page.items.size(), 'Bundle and artifact judgments retain their distinct scopes.');
        OhmReviewRecommendationService.Item bundle = page.items[0]; OhmReviewRecommendationService.Item item = page.items[1];
        System.assertEquals('Bundle', bundle.artifactType); System.assertEquals(null, bundle.nodeId);
        System.assertEquals('prompt-source', item.nodeId); System.assertEquals('bundle|Action|prompt', item.artifactKey);
        System.assertEquals(PID, item.plannerId); System.assertEquals(REPORT, item.reportId);
        System.assertEquals(review.artifacts[0].categories[0].issues[0].recommendation, item.recommendation);
        System.assertEquals(review.artifacts[0].categories[0].issues[0].explanation, item.explanation);
        System.assertEquals(review.artifacts[0].categories[0].issues[0].preserve, item.preserve);
        System.assertEquals(review.artifacts[0].categories[0].issues[0].validation, item.validation);
        System.assertEquals('Repeat the complete biography.', item.evidence[0].quote);
        System.assertEquals('prompt/source.xml', item.evidence[0].sourcePath);
        System.assertEquals(String.valueOf(PID), item.evidence[1].nodeId, 'Configuration quote opens the bundle source.');
        System.assert(!JSON.serialize(page).toLowerCase().contains('savings'), 'Semantic review has no quantified savings.');
        System.assertEquals(0, Limits.getCallouts(), 'The adapter fixture exposes stored reviews without model calls.');
    }
    @IsTest static void identityIgnoresQuoteOrderButSeparatesReportAndScope() {
        OhmReviewService.Result review = review(); OhmDTO.ProcessDetailDTO detail = detail(review);
        OhmReviewRecommendationService.RecommendationPage before = load(detail);
        List<OhmReviewService.QuoteEvidence> quotes = review.artifacts[0].categories[0].issues[0].evidence;
        review.artifacts[0].categories[0].issues[0].evidence = new List<OhmReviewService.QuoteEvidence>{quotes[1], quotes[0]};
        detail.reviewJson = JSON.serialize(review); OhmReviewRecommendationService.RecommendationPage reordered = load(detail);
        System.assertEquals(before.items[1].key, reordered.items[1].key);
        System.assertNotEquals(before.items[0].key, before.items[1].key, 'Bundle and artifact scope must not collide.');
        detail.reportId = 'a00000000000002AAA';
        System.assertNotEquals(before.items[1].key, load(detail).items[1].key, 'Another audit requires a different acceptance identity.');
    }
    @IsTest static void staleUnknownAndSupersededReviewsNeverOfferActions() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); detail.sourceCurrent = false;
        OhmReviewRecommendationService.RecommendationPage page = load(detail);
        System.assert(!page.reviewAvailable); System.assertEquals(0, page.items.size()); System.assert(page.reason.contains('Source changed'));
        detail.sourceCurrent = null; System.assertEquals(0, load(detail).items.size());
        detail.sourceCurrent = true; OhmReviewService.Result old = review(); old.reviewerVersion = 'superseded';
        detail.reviewJson = JSON.serialize(old); page = load(detail);
        System.assert(!page.reviewAvailable); System.assertEquals(0, page.items.size()); System.assert(page.reason.contains('earlier reviewer'));
        old.reviewerVersion = OhmReviewTemplate.REVIEWER_VERSION; old.status = 'Unvalidated'; detail.reviewJson = JSON.serialize(old);
        System.assert(!load(detail).reviewAvailable);
    }
    @IsTest static void absentUnreadableAndCleanReviewsHaveHonestEmptyStates() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); detail.reportId = null;
        System.assert(load(detail).reason.contains('Audit this bundle'));
        detail.reportId = REPORT; detail.reviewJson = null;
        System.assert(!load(detail).reviewAvailable);
        detail.reviewJson = '{not json'; System.assert(load(detail).reason.contains('could not be read'));
        OhmReviewService.Result clean = review(); clean.categories.clear(); clean.artifacts[0].categories.clear();
        detail.reviewJson = JSON.serialize(clean); OhmReviewRecommendationService.RecommendationPage page = load(detail);
        System.assert(page.reviewAvailable); System.assertEquals(0, page.items.size());
        System.assert(page.reason.contains('Unknown coverage'), 'No issues is not a complete-coverage claim.');
    }
    @IsTest static void rejectsMissingPlannerAndNeverLinksMissingSources() {
        try { OhmReviewRecommendationService.getReviewRecommendations(null); System.assert(false, 'Expected missing bundle rejection.'); }
        catch (AuraHandledException expected) { System.assertNotEquals(null, expected); }
        OhmDTO.ProcessDetailDTO detail = detail(review()); detail.nodes.clear();
        OhmReviewRecommendationService.RecommendationPage page = load(detail);
        System.assertEquals(null, page.items[1].nodeId);
        System.assertEquals(null, page.items[1].evidence[0].nodeId, 'Never invent a source node link.');
    }
    private static void persist(OhmDTO.ProcessDetailDTO detail) {
        detail.reportId = new OhmPersistenceService().createProcessReport(PID, 'Workshop_v1');
        update new Agent_Audit_Report__c(Id = detail.reportId, Run_Status__c = 'Complete', Review_Result__c = detail.reviewJson);
    }
    @IsTest static void semanticTaskIsIdempotentAndRetainsOriginalEvidenceAndStandardStatus() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); persist(detail);
        OhmReviewRecommendationService.RecommendationPage page = load(detail); OhmReviewRecommendationService.Item item = page.items[1];
        Id first = OhmReviewRecommendationService.createReviewTask(PID, detail.reportId, item.key);
        Id again = OhmReviewRecommendationService.createReviewTask(PID, detail.reportId, item.key);
        System.assertEquals(first, again); System.assertEquals(1, [SELECT COUNT() FROM Task]);
        Task task = [SELECT WhatId, OwnerId, Subject, Status, Description, Ohm_Review_Key__c FROM Task WHERE Id = :first];
        System.assertEquals(detail.reportId, task.WhatId); System.assertEquals(UserInfo.getUserId(), task.OwnerId);
        System.assertEquals(item.key, task.Ohm_Review_Key__c);
        System.assertEquals('Remove unrelated context — Workshop prompt', task.Subject);
        System.assert(task.Description.contains(item.recommendation)); System.assert(task.Description.contains(item.preserve));
        System.assert(task.Description.contains(item.validation)); System.assert(task.Description.contains(item.evidence[0].quote));
        System.assert(!task.Description.contains('savings'), 'No unsupported environmental estimate is attached.');
        System.assert(!task.Description.contains(item.key)); System.assert(!task.Description.contains(item.reviewerVersion));
        System.assert(!task.Description.contains('prompt/source.xml'));
        System.assert(task.Description.startsWith('Change\n'));
        update new Task(Id = first, Status = 'Completed');
        OhmReviewRecommendationService.Item refreshed = load(detail).items[1];
        System.assertEquals(first, refreshed.taskId); System.assertEquals('Completed', refreshed.taskStatus);
        System.assertEquals(true, refreshed.taskClosed);
        System.assertEquals(first, OhmReviewRecommendationService.createReviewTask(PID, detail.reportId, item.key),
            'Completing a Task does not cause a second Task or claim the source was changed.');
        System.assertEquals(0, [SELECT COUNT() FROM Finding__c], 'Semantic issues are not fabricated detector findings.');
    }
    @IsTest static void renamedTaskKeepsIdentityAndUserNotes() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); persist(detail);
        OhmReviewRecommendationService.Item item = load(detail).items[1];
        Id taskId = OhmReviewRecommendationService.createReviewTask(PID, detail.reportId, item.key);
        update new Task(Id = taskId, Subject = 'Workshop cleanup with engineering', Description = 'Owner notes and acceptance criteria.');
        System.assertEquals(taskId, load(detail).items[1].taskId, 'Subject changes do not break the review link.');
        System.assertEquals(taskId, OhmReviewRecommendationService.createReviewTask(PID, detail.reportId, item.key));
        Task task = [SELECT Subject, Description FROM Task WHERE Id = :taskId];
        System.assertEquals('Workshop cleanup with engineering', task.Subject);
        System.assertEquals('Owner notes and acceptance criteria.', task.Description);
        System.assertEquals(1, [SELECT COUNT() FROM Task]);
    }
    @IsTest static void adoptsLegacyTaskAndRemovesGeneratedTechnicalClutter() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); persist(detail);
        OhmReviewRecommendationService.RecommendationPage page = load(detail);
        OhmReviewRecommendationService.Item item = page.items[1];
        Task prior = new Task(Subject = OhmReviewRecommendationService.legacyTaskSubject(item),
            Description = OhmReviewRecommendationService.legacyTaskBody(item, page),
            WhatId = detail.reportId, OwnerId = UserInfo.getUserId(), Status = 'Not Started', Priority = 'Normal');
        insert prior;
        System.assertEquals(prior.Id, load(detail).items[1].taskId, 'Older generated tasks remain discoverable before adoption.');
        System.assertEquals(prior.Id, OhmReviewRecommendationService.createReviewTask(PID, detail.reportId, item.key));
        Task migrated = [SELECT Subject, Description, Ohm_Review_Key__c FROM Task WHERE Id = :prior.Id];
        System.assertEquals(item.key, migrated.Ohm_Review_Key__c);
        System.assertEquals('Remove unrelated context — Workshop prompt', migrated.Subject);
        System.assert(migrated.Description.startsWith('Change\n'));
        System.assert(!migrated.Description.contains('Recommendation identity:'));
        System.assert(!migrated.Description.contains('prompt/source.xml'));
        System.assertEquals(1, [SELECT COUNT() FROM Task]);
    }
    @IsTest static void adoptingLegacyTaskPreservesUserEditedDescription() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); persist(detail);
        OhmReviewRecommendationService.Item item = load(detail).items[1];
        Task prior = new Task(Subject = OhmReviewRecommendationService.legacyTaskSubject(item), Description = 'Keep my team notes.',
            WhatId = detail.reportId, OwnerId = UserInfo.getUserId(), Status = 'In Progress', Priority = 'Normal');
        insert prior;
        System.assertEquals(prior.Id, OhmReviewRecommendationService.createReviewTask(PID, detail.reportId, item.key));
        Task migrated = [SELECT Description, Status, Ohm_Review_Key__c FROM Task WHERE Id = :prior.Id];
        System.assertEquals('Keep my team notes.', migrated.Description); System.assertEquals('In Progress', migrated.Status);
        System.assertEquals(item.key, migrated.Ohm_Review_Key__c);
    }
    @IsTest static void taskRequiresCurrentSavedIssueAndMatchingLockedReport() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); persist(detail);
        String key = load(detail).items[1].key;
        assertTaskRejected(detail, detail.reportId, 'review:forged');
        assertTaskRejected(detail, REPORT, key);
        detail.sourceCurrent = false; assertTaskRejected(detail, detail.reportId, key); detail.sourceCurrent = true;
        update new Agent_Audit_Report__c(Id = detail.reportId, Review_Result__c = '{}');
        assertTaskRejected(detail, detail.reportId, key);
        System.assertEquals(0, [SELECT COUNT() FROM Task]);
    }
    @IsTest static void taskRejectsAnAuditSupersededAfterSourceRead() {
        OhmDTO.ProcessDetailDTO detail = detail(review()); persist(detail);
        Test.setCreatedDate(detail.reportId, System.now().addDays(-1));
        String key = load(detail).items[1].key;
        Id newer = new OhmPersistenceService().createProcessReport(PID, 'Workshop_v1');
        update new Agent_Audit_Report__c(Id = newer, Run_Status__c = 'Complete', Review_Result__c = detail.reviewJson);
        assertTaskRejected(detail, detail.reportId, key);
        System.assertEquals(0, [SELECT COUNT() FROM Task]);
    }
    private static void assertTaskRejected(OhmDTO.ProcessDetailDTO detail, Id reportId, String key) {
        OhmReviewRecommendationService.gateway = new Stub(detail);
        try { OhmReviewRecommendationService.createReviewTask(PID, reportId, key); System.assert(false, 'Expected stale or forged task request rejection.'); }
        catch (AuraHandledException expected) { System.assertNotEquals(null, expected); }
    }
}
