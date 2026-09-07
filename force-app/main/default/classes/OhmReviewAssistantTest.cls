@IsTest
private class OhmReviewAssistantTest {
    private static final Id PID = '16j000000000001AAA';
    private static OhmDTO.ProcessDetailDTO detail(Boolean current) {
        OhmDTO.ProcessDetailDTO d = new OhmDTO.ProcessDetailDTO();
        d.plannerId = PID; d.label = 'Reviewed bundle'; d.sourceCurrent = current;
        d.coverageStatus = 'Incomplete'; d.findings = new List<OhmDTO.FindingDTO>();
        d.nodes = new List<OhmDTO.NodeDTO>();
        OhmDTO.NodeDTO n = new OhmDTO.NodeDTO();
        n.id = 'prompt-source'; n.artifactKey = 'bundle|Action|prompt'; n.nodeType = 'Action';
        n.label = 'Selected prompt'; n.instructions = 'Return the required answer.';
        d.nodes.add(n);
        OhmReviewService.Result review = new OhmReviewService.Result();
        review.categories = categories('Bundle assessment only.');
        OhmReviewService.ArtifactResult artifact = new OhmReviewService.ArtifactResult();
        artifact.artifactId = n.id; artifact.artifactKey = n.artifactKey;
        artifact.sourceHash = OhmPersistenceService.sha256(n.instructions);
        artifact.categories = categories('Selected prompt assessment only.');
        review.artifacts.add(artifact);
        d.reviewJson = JSON.serialize(review);
        return d;
    }
    private static List<OhmReviewService.Category> categories(String assessment) {
        List<OhmReviewService.Category> result = new List<OhmReviewService.Category>();
        for (String key : new List<String>{'INPUT','OUTPUT','MODEL','CALLS'}) {
            OhmReviewService.Category c = new OhmReviewService.Category();
            c.id = key; c.label = key; c.rating = key == 'MODEL' ? 'UNRATED' : 'A';
            c.assessment = assessment; c.coverageStatus = key == 'MODEL' ? 'Unknown' : 'Complete';
            result.add(c);
        }
        return result;
    }
    @IsTest static void reviewQuestionsUseSavedRatingsWithoutAnotherModelCall() {
        OhmAssistantService.mockDetail = detail(true);
        OhmAssistantService.mockModelReply = 'This must not replace the saved ratings.';
        OhmDTO.AssistantReplyDTO reply = OhmAssistantService.ask(PID, 'Explain the category ratings.');
        System.assert(reply.answer.startsWith('Saved review for Reviewed bundle.'));
        System.assert(reply.answer.contains('Bundle assessment only.'));
        System.assert(reply.answer.contains('INPUT: A'));
        System.assert(reply.answer.contains('OUTPUT: A'));
        System.assert(reply.answer.contains('CALLS: A'));
        System.assert(!reply.answer.contains('MODEL:'));
        System.assert(!reply.answer.contains('Unrated'), 'The hidden MODEL category is the only unrated category in this fixture.');
        OhmReviewService.Result stored = (OhmReviewService.Result)JSON.deserialize(OhmAssistantService.mockDetail.reviewJson, OhmReviewService.Result.class);
        System.assertEquals(4, stored.categories.size(), 'Presentation scope must not alter the saved review schema.');
        System.assert(!reply.answer.contains('Selected prompt assessment only.'));
        System.assertEquals('Saved Salesforce review · ratings computed by Apex', reply.modelLabel);
        System.assertEquals(0, OhmAssistantService.modelCallCount);
    }
    @IsTest static void selectedPromptExplainsOnlyItsHashMatchedReview() {
        OhmDTO.ProcessDetailDTO d = detail(true);
        OhmReviewService.Result stored = (OhmReviewService.Result)JSON.deserialize(d.reviewJson, OhmReviewService.Result.class);
        stored.artifacts[0].categories[3].rating = 'UNRATED';
        stored.artifacts[0].categories[3].coverageStatus = 'Unknown';
        d.reviewJson = JSON.serialize(stored);
        OhmAssistantService.mockDetail = d;
        OhmDTO.AssistantReplyDTO reply = OhmAssistantService.askArtifact(PID, d.nodes[0].artifactKey,
            OhmPersistenceService.sha256(d.nodes[0].instructions), 'Explain the evidence.', false);
        System.assert(reply.answer.contains('Selected prompt assessment only.'));
        System.assert(reply.answer.startsWith('Saved review for Selected prompt.'));
        System.assert(reply.answer.contains('CALLS: Unrated'), 'Unknown coverage in a visible category must remain visible.');
        System.assert(!reply.answer.contains('MODEL:'));
        System.assert(!reply.answer.contains('Bundle assessment only.'));
        System.assertEquals(0, OhmAssistantService.modelCallCount);
    }
    @IsTest static void staleReviewCannotBePresentedAsCurrent() {
        OhmAssistantService.mockDetail = detail(false);
        OhmDTO.AssistantReplyDTO reply = OhmAssistantService.ask(PID, 'What are the ratings?');
        System.assert(reply.answer.contains('source changed'));
        System.assert(!reply.answer.contains('Bundle assessment only.'));
        System.assertEquals(0, OhmAssistantService.modelCallCount);
    }
}
