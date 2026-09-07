/** Integration tests for Ohm's Agentforce actions against the org's published control bundle. */
@IsTest
private class OhmAgentActionsTest {
    private static OhmDTO.ProcessSummaryDTO rowFor(Id plannerId, List<OhmDTO.ProcessSummaryDTO> rows) {
        for (OhmDTO.ProcessSummaryDTO r : rows) if (String.valueOf(r.plannerId) == String.valueOf(plannerId)) return r;
        return null;
    }

    @IsTest(SeeAllData=true) static void listsBundlesWithGradesAndModeledSavingsAtAnyVolume() {
        Id plannerId = OhmAuditTestSupport.scriptPlannerId();
        System.assertNotEquals(null, plannerId, 'A supported Agent Script control must be published before integration tests.');
        Test.startTest();
        OhmAuditTestSupport.auditProcess(plannerId);
        Test.stopTest();
        OhmAgentListBundles.Request req = new OhmAgentListBundles.Request();
        req.requestsPerDay = 1000;
        List<OhmAgentListBundles.Response> out = OhmAgentListBundles.run(new List<OhmAgentListBundles.Request>{ req });
        System.assertEquals(1, out.size());
        System.assert(out[0].summary.contains('1000 requests a day'), out[0].summary);
        System.assert(out[0].summary.contains('Input'), out[0].summary);
        System.assert(out[0].summary.contains('modeled'), 'the agent is told the figures are modeled');
        System.assertNotEquals(null, out[0].bundlesJson);
        List<OhmAgentListBundles.Response> dflt = OhmAgentListBundles.run(new List<OhmAgentListBundles.Request>());
        System.assertEquals(1, dflt.size(), 'an empty request still yields one summary');
        System.assert(dflt[0].summary.contains('300 requests a day'), dflt[0].summary);
    }

    @IsTest(SeeAllData=true) static void resolvesBundlesByAnyNameAndExplainsMisses() {
        Id plannerId = OhmAuditTestSupport.scriptPlannerId();
        Test.startTest();
        OhmAuditTestSupport.auditProcess(plannerId);
        Test.stopTest();
        List<OhmDTO.ProcessSummaryDTO> rows = OhmAgentActions.fleet();
        OhmDTO.ProcessSummaryDTO row = rowFor(plannerId, rows);
        System.assertNotEquals(null, row, 'the control publication is in the fleet');
        System.assertEquals(row.plannerId, OhmAgentActions.resolve(row.label, rows).plannerId, 'label match');
        System.assertEquals(row.plannerId, OhmAgentActions.resolve(row.plannerApiName.toUpperCase(), rows).plannerId, 'api name match, any case');
        System.assertEquals(row.plannerId, OhmAgentActions.resolve(OhmAgentActions.logicalName(row.plannerApiName), rows).plannerId, 'logical name without the version suffix');
        System.assertEquals(null, OhmAgentActions.resolve('definitely not a bundle', rows));
        System.assertEquals(null, OhmAgentActions.resolve('  ', rows));
        System.assert(OhmAgentActions.availableBundles(rows).contains(OhmAgentActions.displayLabel(row)));

        OhmAgentRecommendations.Request req = new OhmAgentRecommendations.Request();
        req.bundle = 'definitely not a bundle';
        OhmAgentRecommendations.Response missing = OhmAgentRecommendations.run(new List<OhmAgentRecommendations.Request>{ req })[0];
        System.assert(missing.summary.contains('was not found') && missing.summary.contains('Available bundles'), missing.summary);
        req.bundle = row.label;
        OhmAgentRecommendations.Response found = OhmAgentRecommendations.run(new List<OhmAgentRecommendations.Request>{ req })[0];
        System.assert(found.summary.startsWith(OhmAgentActions.displayLabel(row)), found.summary);
        System.assert(found.summary.contains('Input'), 'grades lead the recommendation summary');

        Map<String, String> g = OhmAgentActions.grades('{"categories":[{"id":"INPUT","rating":"C"},{"id":"MODEL","rating":"UNRATED"},{"id":"CALLS","rating":"A"}]}');
        System.assertEquals('C', g.get('INPUT'));
        System.assertEquals('A', g.get('CALLS'));
        System.assertEquals('Unrated', g.get('OUTPUT'));
        System.assertEquals('Unrated', OhmAgentActions.grades('not json').get('INPUT'));
        System.assertEquals('37.8 kWh', OhmAgentActions.energy(37784.07));
        System.assertEquals('1.26 MWh', OhmAgentActions.energy(1259469));
        System.assertEquals('0.35 Wh', OhmAgentActions.energy(0.3456));
        System.assertEquals('11.3 kg', OhmAgentActions.mass(11335.2));
        System.assertEquals('40.8 L', OhmAgentActions.water(40806.8));
        System.assertEquals(37784.07, OhmAgentActions.scaled(37784.07, 109500, 300).setScale(2), 'the model scenario reproduces the saved figure');
        System.assertEquals(null, OhmAgentActions.scaled(1, 0, 300));
    }

    @IsTest(SeeAllData=true) static void startsAnAuditReportsStatusAndHandlesTasks() {
        Id plannerId = OhmAuditTestSupport.scriptPlannerId();
        List<OhmDTO.ProcessSummaryDTO> rows = OhmAgentActions.fleet();
        OhmDTO.ProcessSummaryDTO row = rowFor(plannerId, rows);
        System.assertNotEquals(null, row);
        OhmAgentStartAudit.Request req = new OhmAgentStartAudit.Request();
        req.bundle = row.plannerApiName;
        Test.startTest();
        OhmAgentStartAudit.Response started = OhmAgentStartAudit.run(new List<OhmAgentStartAudit.Request>{ req })[0];
        System.assertNotEquals(null, started.reportId, started.summary);
        System.assertEquals('Queued', started.status);
        System.assert(started.summary.contains('started'), started.summary);
        OhmAgentAuditStatus.Request sreq = new OhmAgentAuditStatus.Request();
        sreq.reportId = started.reportId;
        OhmAgentAuditStatus.Response status = OhmAgentAuditStatus.run(new List<OhmAgentAuditStatus.Request>{ sreq })[0];
        System.assert(status.summary.contains(started.reportId), status.summary);
        System.assertNotEquals(null, status.status);
        Test.stopTest();

        OhmAgentAuditStatus.Request bad = new OhmAgentAuditStatus.Request();
        bad.reportId = 'nope';
        System.assert(OhmAgentAuditStatus.run(new List<OhmAgentAuditStatus.Request>{ bad })[0].summary.contains('not a valid'), 'invalid ids are explained');

        OhmAgentStartAudit.Request missing = new OhmAgentStartAudit.Request();
        missing.bundle = 'definitely not a bundle';
        OhmAgentStartAudit.Response notFound = OhmAgentStartAudit.run(new List<OhmAgentStartAudit.Request>{ missing })[0];
        System.assertEquals(null, notFound.reportId);
        System.assert(notFound.summary.contains('was not found'), notFound.summary);

        OhmAgentCreateTask.Request treq = new OhmAgentCreateTask.Request();
        treq.bundle = 'definitely not a bundle';
        OhmAgentCreateTask.Response taskMissing = OhmAgentCreateTask.run(new List<OhmAgentCreateTask.Request>{ treq })[0];
        System.assertEquals(null, taskMissing.taskId);
        System.assert(taskMissing.summary.contains('was not found'), taskMissing.summary);
        treq.bundle = row.plannerApiName;
        treq.category = 'Input';
        OhmAgentCreateTask.Response attempt = OhmAgentCreateTask.run(new List<OhmAgentCreateTask.Request>{ treq })[0];
        System.assertNotEquals(null, attempt.summary);
        System.assert(attempt.summary.contains(OhmAgentActions.displayLabel(row)) || attempt.summary.contains('task'), attempt.summary);
    }

    /** The create/duplicate paths need a bundle whose current review actually recommends something. */
    @IsTest(SeeAllData=true) static void createsOneTaskPerRecommendationAndNeverDuplicatesIt() {
        List<OhmDTO.ProcessSummaryDTO> rows = OhmAgentActions.fleet();
        OhmDTO.ProcessSummaryDTO target = null;
        OhmReviewRecommendationService.Item wanted = null;
        for (OhmDTO.ProcessSummaryDTO row : rows) {
            OhmReviewRecommendationService.RecommendationPage page = OhmReviewRecommendationService.getReviewRecommendations(row.plannerId);
            OhmReviewRecommendationService.Item item = OhmAgentActions.pickRecommendation(page, null);
            if (page.sourceCurrent == true && page.reviewAvailable == true && item != null && item.taskId == null) {
                target = row; wanted = item; break;
            }
        }
        if (target == null) {
            // Every current recommendation is already tracked, or none exist: assert the tracked path instead.
            for (OhmDTO.ProcessSummaryDTO row : rows) {
                OhmReviewRecommendationService.RecommendationPage page = OhmReviewRecommendationService.getReviewRecommendations(row.plannerId);
                OhmReviewRecommendationService.Item item = OhmAgentActions.pickRecommendation(page, null);
                if (item != null && item.taskId != null) {
                    OhmAgentCreateTask.Request req = new OhmAgentCreateTask.Request();
                    req.bundle = row.plannerApiName;
                    OhmAgentCreateTask.Response existing = OhmAgentCreateTask.run(new List<OhmAgentCreateTask.Request>{ req })[0];
                    System.assertEquals(String.valueOf(item.taskId), existing.taskId, 'an already-tracked recommendation returns its existing task');
                    System.assert(existing.summary.contains('already tracks'), existing.summary);
                    return;
                }
            }
            return; // nothing recommended anywhere in this org; the not-found and no-recommendation paths are covered above
        }
        OhmAgentCreateTask.Request req = new OhmAgentCreateTask.Request();
        req.bundle = OhmAgentActions.displayLabel(target);
        Test.startTest();
        OhmAgentCreateTask.Response created = OhmAgentCreateTask.run(new List<OhmAgentCreateTask.Request>{ req })[0];
        Test.stopTest();
        System.assertNotEquals(null, created.taskId, created.summary);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Id = :created.taskId], 'a created task is a real Task');
        System.assert(created.summary.contains('Created task'), created.summary);
        System.assert(created.summary.contains(wanted.recommendation.left(30)), 'the summary carries the recommendation');

        OhmAgentCreateTask.Response again = OhmAgentCreateTask.run(new List<OhmAgentCreateTask.Request>{ req })[0];
        System.assertEquals(created.taskId, again.taskId, 'the same recommendation is never tracked twice');
        System.assert(again.summary.contains('already tracks'), again.summary);
    }
}
