/**
 * OhmDiscoveryServiceTest — integration-style tests against LIVE org metadata (intentional).
 * The org carries the deployed spike agent Ohm_Spike_Agent (1 planner, 1 topic, 1 apex action),
 * so discovery has real GenAi* rows to read. SeeAllData=true is required because the
 * GenAi*Definition setup entities are org data, not test-created data.
 */
@IsTest
private class OhmDiscoveryServiceTest {

    @IsTest(SeeAllData=true)
    static void test_discoverFindsLiveSpikeAgent() {
        Test.startTest();
        OhmDTO.AgentModel g = new OhmDiscoveryService().discover();
        Test.stopTest();

        System.assertNotEquals(null, g, 'discover() must return an AgentModel');
        System.assertNotEquals(null, g.agentsById, 'agentsById must be initialized');
        System.assert(g.agentsById.size() >= 1,
            'Org has the live Ohm_Spike_Agent — expected >= 1 agent, got ' + g.agentsById.size());
        System.assertEquals(0, g.discoveryErrors.size(),
            'All three inline SOQL queries are verified on this org — expected no discovery errors: '
            + String.join(g.discoveryErrors, '; '));

        // the spike planner is present
        OhmDTO.AgentNode spike = null;
        for (OhmDTO.AgentNode a : g.agentsById.values()) {
            if (a.developerName != null && a.developerName.startsWith('Ohm_Spike_Agent')) {
                spike = a;
                break;
            }
        }
        System.assertNotEquals(null, spike,
            'Expected planner Ohm_Spike_Agent among discovered agents');

        // ...with its apex action reachable (by planner linkage or by spike naming)
        Boolean spikeApexActionFound = false;
        for (OhmDTO.ActionNode act : g.actions) {
            Boolean isApex = act.invocationTargetType != null
                && act.invocationTargetType.equalsIgnoreCase('apex');
            Boolean linkedToSpike = act.plannerId == spike.id
                || (act.developerName != null && act.developerName.contains('Spike'));
            if (isApex && linkedToSpike) {
                spikeApexActionFound = true;
                break;
            }
        }
        System.assert(spikeApexActionFound,
            'Expected the spike apex action (Ohm_Spike_Ping) among discovered actions');
    }

    @IsTest(SeeAllData=true)
    static void test_promptTemplateCountIsDistinctPromptTargets() {
        OhmDTO.AgentModel g = new OhmDiscoveryService().discover();

        System.assertNotEquals(null, g.promptTemplateCount,
            'promptTemplateCount must be a non-null Integer');
        System.assert(g.promptTemplateCount >= 0,
            'promptTemplateCount must be >= 0');

        // recompute independently: distinct InvocationTarget among prompt-typed actions (C10/§0.7)
        Set<String> expected = new Set<String>();
        Integer promptActionCount = 0;
        for (OhmDTO.ActionNode a : g.actions) {
            if (a.invocationTargetType != null && a.invocationTargetType.equalsIgnoreCase('prompt')) {
                promptActionCount++;
                if (String.isNotBlank(a.invocationTarget)) {
                    expected.add(a.invocationTarget);
                }
            }
        }
        System.assertEquals(expected.size(), g.promptTemplateCount,
            'promptTemplateCount must equal DISTINCT prompt InvocationTargets');
        System.assert(g.promptTemplateCount <= promptActionCount,
            'Distinct template count can never exceed the prompt-action count');
    }

    @IsTest(SeeAllData=true)
    static void test_treeMapsAreConsistentWithFlatLists() {
        OhmDTO.AgentModel g = new OhmDiscoveryService().discover();

        System.assertNotEquals(null, g.topics, 'topics list must be initialized');
        System.assertNotEquals(null, g.actions, 'actions list must be initialized');
        System.assertNotEquals(null, g.topicsByPlanner, 'topicsByPlanner must be initialized');
        System.assertNotEquals(null, g.actionsByPlugin, 'actionsByPlugin must be initialized');
        System.assertNotEquals(null, g.actionsByPlanner, 'actionsByPlanner must be initialized');

        // every grouped topic/action exists in the flat list; group keys match member fields
        Integer groupedTopics = 0;
        for (String plannerId : g.topicsByPlanner.keySet()) {
            for (OhmDTO.TopicNode t : g.topicsByPlanner.get(plannerId)) {
                groupedTopics++;
                System.assertEquals(plannerId, t.plannerId, 'topicsByPlanner key must match member plannerId');
            }
        }
        System.assert(groupedTopics <= g.topics.size(),
            'Grouped topics cannot exceed the flat topic list');

        Integer groupedByPlanner = 0;
        for (String plannerId : g.actionsByPlanner.keySet()) {
            for (OhmDTO.ActionNode a : g.actionsByPlanner.get(plannerId)) {
                groupedByPlanner++;
                System.assertEquals(plannerId, a.plannerId, 'actionsByPlanner key must match member plannerId');
            }
        }
        System.assert(groupedByPlanner <= g.actions.size(),
            'Grouped actions cannot exceed the flat action list');

        for (String pluginId : g.actionsByPlugin.keySet()) {
            for (OhmDTO.ActionNode a : g.actionsByPlugin.get(pluginId)) {
                System.assertEquals(pluginId, a.pluginId, 'actionsByPlugin key must match member pluginId');
            }
        }

        // C13 model-binding degrade: every prompt action without a bound model is flagged assumed,
        // and every action carries a non-null modelAssumed so signal (b) never NPEs
        for (OhmDTO.ActionNode a : g.actions) {
            System.assertNotEquals(null, a.modelAssumed,
                'modelAssumed must be set on every action: ' + a.developerName);
            Boolean isPrompt = a.invocationTargetType != null
                && a.invocationTargetType.equalsIgnoreCase('prompt');
            if (isPrompt && String.isBlank(a.boundModel)) {
                System.assertEquals(true, a.modelAssumed,
                    'Prompt action without bound model must be modelAssumed=true: ' + a.developerName);
            }
        }
    }

    @IsTest(SeeAllData=true)
    static void test_discoverNeverThrowsOnRealOrgData() {
        // defensive: whatever the live metadata contains, discover() must complete
        OhmDTO.AgentModel g;
        try {
            g = new OhmDiscoveryService().discover();
        } catch (Exception e) {
            System.assert(false, 'discover() must never throw; got ' + e.getTypeName() + ': ' + e.getMessage());
        }
        System.assertNotEquals(null, g, 'discover() must return a model even on partial failure');
        System.assertNotEquals(null, g.discoveryErrors, 'discoveryErrors must always be a list');
        System.assertNotEquals(null, g.promptTemplateCount, 'promptTemplateCount must always be set');

        // the model must be directly consumable by OhmSignalService.analyze (Wave-A handoff)
        List<OhmDTO.Finding> findings = new OhmSignalService().analyze(g);
        System.assertNotEquals(null, findings, 'analyze(discover()) must return a list, not throw');
    }
}
