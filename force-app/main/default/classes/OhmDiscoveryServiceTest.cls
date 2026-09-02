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

    // ===================== v2 Workbench — listFleet / discoverProcess / deriveDomain =====================

    /**
     * listFleet() returns one ProcessSummaryDTO per live planner (org has 4), each with a
     * derived domain and topic/action counts, and NO grade/score/energy (the controller joins
     * those from reports). Fleet listing must never carry audit results.
     */
    @IsTest(SeeAllData=true)
    static void test_listFleetReturnsProcessesWithCountsAndDomainsNoGrade() {
        Test.startTest();
        List<OhmDTO.ProcessSummaryDTO> fleet = new OhmDiscoveryService().listFleet();
        Test.stopTest();

        System.assertNotEquals(null, fleet, 'listFleet() must return a list');
        System.assert(fleet.size() >= 4,
            'Org has 4 live planners — expected >= 4 fleet rows, got ' + fleet.size());

        Boolean sawWasteDemo = false;
        Set<String> domainsSeen = new Set<String>();
        for (OhmDTO.ProcessSummaryDTO row : fleet) {
            System.assertNotEquals(null, row.plannerId, 'each row must carry a plannerId');
            System.assertNotEquals(null, row.plannerApiName, 'each row must carry a plannerApiName');
            System.assert(String.isNotBlank(row.label), 'each row must carry a label');
            System.assert(String.isNotBlank(row.domain), 'each row must carry a derived domain');
            System.assertNotEquals(null, row.topicCount, 'topicCount must be non-null');
            System.assertNotEquals(null, row.actionCount, 'actionCount must be non-null');
            System.assert(row.topicCount >= 0 && row.actionCount >= 0, 'counts must be >= 0');

            // Fleet listing carries NO audit result — the controller joins those in.
            System.assertEquals(null, row.grade, 'listFleet() must not set grade');
            System.assertEquals(null, row.score, 'listFleet() must not set score');
            System.assertEquals(null, row.energyWhCentral, 'listFleet() must not set energy');

            domainsSeen.add(row.domain);
            if (row.plannerApiName == 'Ohm_Waste_Demo') {
                sawWasteDemo = true;
                System.assertEquals('Sales', row.domain,
                    'Ohm_Waste_Demo (Lead Concierge) must derive domain Sales');
                System.assert(row.topicCount >= 1,
                    'Ohm_Waste_Demo must count its Lead Triage topic, got ' + row.topicCount);
                System.assert(row.actionCount >= 1,
                    'Ohm_Waste_Demo must count its lead-tier action, got ' + row.actionCount);
            }
        }
        System.assert(sawWasteDemo, 'Ohm_Waste_Demo must appear in the fleet');
        System.assert(domainsSeen.size() >= 2,
            'The four live agents span multiple derived domains, got ' + domainsSeen);
    }

    /**
     * discoverProcess(Ohm_Waste_Demo) returns an AgentModel scoped to that one planner and
     * containing its bloated "Lead Triage" topic (Scope ~5400 chars). Other planners' nodes
     * (Order/Service/Spike) must NOT leak into the subtree.
     */
    @IsTest(SeeAllData=true)
    static void test_discoverProcessScopedToWasteDemoHasBloatedLeadTriage() {
        GenAiPlannerDefinition waste = [
            SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName = 'Ohm_Waste_Demo' LIMIT 1
        ];

        Test.startTest();
        OhmDTO.AgentModel g = new OhmDiscoveryService().discoverProcess(waste.Id);
        Test.stopTest();

        System.assertNotEquals(null, g, 'discoverProcess() must return an AgentModel');
        System.assertEquals(1, g.agentsById.size(),
            'scoped model must contain exactly the target planner');
        System.assert(g.agentsById.containsKey(String.valueOf(waste.Id)),
            'scoped model must contain the Waste Demo planner');

        // the bloated Lead Triage topic is present, with its oversized Scope
        OhmDTO.TopicNode leadTriage = null;
        for (OhmDTO.TopicNode t : g.topics) {
            if (t.developerName != null && t.developerName.contains('LeadTriage')) {
                leadTriage = t;
            }
            // no foreign topics leaked in
            System.assert(
                t.developerName == null ||
                (!t.developerName.contains('Sample') && !t.developerName.contains('Spike')),
                'scoped topics must not include other planners: ' + t.developerName);
        }
        System.assertNotEquals(null, leadTriage,
            'Ohm_Waste_Demo subtree must contain the Lead Triage topic');
        System.assert(leadTriage.scope != null && leadTriage.scope.length() >= 5000,
            'Lead Triage Scope must be the bloated ~5400-char instruction, got '
            + (leadTriage.scope == null ? 0 : leadTriage.scope.length()));

        // scoped actions belong to the Waste Demo family only
        for (OhmDTO.ActionNode a : g.actions) {
            System.assert(
                a.developerName == null ||
                (!a.developerName.contains('Sample') && !a.developerName.contains('Spike')),
                'scoped actions must not include other planners: ' + a.developerName);
        }

        // consumable by the detectors (Wave-A handoff) without throwing
        List<OhmDTO.Finding> findings = new OhmSignalService().analyze(g);
        System.assertNotEquals(null, findings, 'analyze(discoverProcess()) must return a list');
    }

    /** deriveDomain keyword map: first match wins in the documented priority order. */
    @IsTest
    static void test_deriveDomainKeywordMap() {
        OhmDiscoveryService svc = new OhmDiscoveryService();
        System.assertEquals('Sales', svc.deriveDomain('Ohm_Waste_Demo', 'Lead Concierge'),
            'Lead -> Sales');
        System.assertEquals('Commerce', svc.deriveDomain('Ohm_Sample_Order', 'Order Support'),
            'Order -> Commerce');
        System.assertEquals('Customer Service', svc.deriveDomain('Ohm_Sample_Service', 'Service Concierge'),
            'Service -> Customer Service');
        System.assertEquals('Customer Service', svc.deriveDomain('Case_Router', 'Case Router'),
            'Case -> Customer Service');
        System.assertEquals('Finance', svc.deriveDomain('Billing_Bot', 'Bill Pay'),
            'Bill -> Finance');
        System.assertEquals('Internal', svc.deriveDomain('Ohm_Spike_Agent', 'Ohm Spike Agent'),
            'Ohm/Spike -> Internal');
        System.assertEquals('General', svc.deriveDomain('Widget_Helper', 'Widget Helper'),
            'no keyword -> General');
        System.assertEquals('General', svc.deriveDomain(null, null),
            'null-safe -> General');
    }
}
