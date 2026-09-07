/** Latest fleet versions do not merge exact historical process discovery or old audit claims. */
@IsTest
private class OhmFleetVersionTest {
    @IsTest static void candidateNamesMatchPublishedRetrievalContract() {
        for (String apiName : new List<String>{'Weather_v1', 'Weather_Alerts_v10', 'Ohm_Weather_Demo_v4'}) {
            System.assert(OhmDiscoveryService.isAgentScriptCandidate(apiName), apiName);
        }
        for (String apiName : new List<String>{null, '', 'Legacy_Weather', 'Weather_v1_Helper', '_v1',
                'Weather_v0', 'Weather_v01', 'Weather_V1', '9Weather_v1'}) {
            System.assert(!OhmDiscoveryService.isAgentScriptCandidate(apiName), apiName);
        }
    }

    @IsTest static void bundleScopeRemovesLegacyAndUnownedArtifactsBeforeRelationshipWarnings() {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        add(graph, '16j000000000001AAA', 'Weather_v1');
        add(graph, '16j000000000002AAA', 'Legacy_Weather');
        graph.topics[0].id = '0Qx000000000001AAA';
        graph.actions[0].pluginId = graph.topics[0].id;
        OhmDTO.TopicNode unrelated = new OhmDTO.TopicNode();
        unrelated.id = '0Qx000000000002AAA'; unrelated.developerName = 'Legacy_Unowned';
        graph.topics.add(unrelated);
        OhmDTO.ActionNode globalAction = new OhmDTO.ActionNode();
        globalAction.id = 'global'; globalAction.developerName = 'Legacy_Unowned';
        graph.actions.add(globalAction);
        OhmDiscoveryService.retainAgentScriptCandidates(graph);
        new OhmDiscoveryService().resolveRelationships(graph);
        System.assertEquals(new Set<String>{'16j000000000001AAA'}, graph.agentsById.keySet());
        System.assertEquals(1, graph.topics.size());
        System.assertEquals(1, graph.actions.size());
        System.assertEquals(0, graph.coverageWarnings.size(), 'Unrelated legacy inventory must not poison this bundle coverage.');
    }

    @IsTest static void supportedPlannerWithMissingActionParentStillLowersCoverage() {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        add(graph, '16j000000000001AAA', 'Weather_v1');
        graph.actions[0].pluginId = 'missing';
        OhmDiscoveryService.retainAgentScriptCandidates(graph);
        new OhmDiscoveryService().resolveRelationships(graph);
        System.assertEquals(1, graph.actions.size(), 'Known planner ownership keeps unresolved dependencies visible.');
        System.assertEquals(1, graph.coverageWarnings.size());
        System.assert(graph.coverageWarnings[0].contains('16j000000000001AAA'));
    }

    @IsTest static void previousPublicationWarningsDoNotLowerLatestPublicationCoverage() {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        add(graph, 'old-planner', 'Weather_v1');
        add(graph, 'current-planner', 'Weather_v2');
        graph.coverageWarnings.add('Inferred topic ownership in old-planner');
        graph.coverageWarnings.add('Conflicting ownership in old-planner and current-planner');
        graph.coverageWarnings.add('Unlinked action parent in current-planner');
        OhmDiscoveryService.retainLatestPlannerVersions(graph);
        System.assertEquals(2, graph.coverageWarnings.size());
        for (String warning : graph.coverageWarnings) System.assert(warning.contains('current-planner'));
    }

    private static void add(OhmDTO.AgentModel graph, String id, String apiName) {
        OhmDTO.AgentNode node = new OhmDTO.AgentNode();
        node.id = id; node.developerName = apiName; node.masterLabel = 'Same display label';
        graph.agentsById.put(id, node);
        OhmDTO.TopicNode topic = new OhmDTO.TopicNode();
        topic.id = 'topic-' + id; topic.plannerId = id;
        graph.topics.add(topic);
        OhmDTO.ActionNode action = new OhmDTO.ActionNode();
        action.id = 'action-' + id; action.plannerId = id; action.pluginId = topic.id;
        graph.actions.add(action);
    }

    @IsTest static void highestNumericVersionWinsAndOldArtifactsLeaveFleetScope() {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        add(graph, 'p1', 'Weather_v1');
        add(graph, 'p2', 'Weather_v2');
        add(graph, 'p10', 'Weather_v10');
        add(graph, 'legacy', 'Weather');
        OhmDiscoveryService.retainLatestPlannerVersions(graph);
        System.assertEquals(new Set<String>{ 'p10' }, graph.agentsById.keySet());
        System.assertEquals(1, graph.topics.size());
        System.assertEquals('p10', graph.topics[0].plannerId);
        System.assertEquals(1, graph.actions.size());
        System.assertEquals('p10', graph.actions[0].plannerId);
    }

    @IsTest static void sameLabelsAndSimilarNamesDoNotMergeDifferentProcesses() {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        add(graph, 'weather', 'Weather_v2');
        add(graph, 'alerts', 'Weather_Alerts_v1');
        add(graph, 'legacy', 'Legacy_Weather');
        add(graph, 'helper', 'Weather_v1_Helper');
        OhmDiscoveryService.retainLatestPlannerVersions(graph);
        System.assertEquals(4, graph.agentsById.size());
        System.assertEquals(4, graph.topics.size());
        System.assertEquals(4, graph.actions.size());
    }

    @IsTest static void missingRelationshipsRemainUnknownWhileOldOwnedActionsAreRemoved() {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        add(graph, 'old', 'Weather_v1');
        add(graph, 'new', 'Weather_v2');
        graph.actions[0].plannerId = null; // Its explicit topic still identifies the old version.
        OhmDTO.ActionNode unlinked = new OhmDTO.ActionNode();
        unlinked.id = 'unlinked';
        graph.actions.add(unlinked);
        graph.coverageWarnings.add('Unlinked action: unavailable parent');
        OhmDiscoveryService.retainLatestPlannerVersions(graph);
        System.assertEquals(2, graph.actions.size());
        System.assertEquals('action-new', graph.actions[0].id);
        System.assertEquals('unlinked', graph.actions[1].id);
        System.assertEquals(1, graph.coverageWarnings.size());
    }
}
