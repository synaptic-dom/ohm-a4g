/** External, published workflow acceptance tests. Intentionally exposes current gaps.
 * Requires the three pinned Agent Script Recipes to be published in a scratch org.
 * Test-only package; never included in the Ohm application package.
 */
@IsTest(SeeAllData=true)
private class OhmPublicWorkflowAcceptanceTest {
    private static GenAiPlannerDefinition planner(String name) {
        return [SELECT Id, DeveloperName FROM GenAiPlannerDefinition WHERE DeveloperName = :name LIMIT 1];
    }

    @IsTest static void weatherDiscoveryUsesRealRelationships() {
        GenAiPlannerDefinition p = planner('ActionDefinitions_v1');
        List<GenAiPluginDefinition> topics = [SELECT Id FROM GenAiPluginDefinition WHERE PlannerId = :p.Id];
        Set<Id> topicIds = new Map<Id, GenAiPluginDefinition>(topics).keySet();
        Integer actions = [SELECT COUNT() FROM GenAiFunctionDefinition WHERE PluginId IN :topicIds];
        System.assertEquals(2, topics.size(), 'Published upstream recipe should expose router + weather subagent');
        System.assertEquals(3, actions, 'Published upstream recipe should expose 2 Flows + 1 Apex action');
        OhmDTO.AgentModel g = new OhmDiscoveryService().discoverProcess(p.Id);
        System.assertEquals(topics.size(), g.topics.size(), 'Ohm must follow the real PlannerId relationships');
        System.assertEquals(actions, g.actions.size(), 'Ohm must follow PluginId to the owning planner');
    }

    @IsTest static void paymentFlowChainIsNotRedundantLlmWork() {
        GenAiPlannerDefinition p = planner('ActionChaining_v1');
        Set<Id> topicIds = new Map<Id, GenAiPluginDefinition>([
            SELECT Id FROM GenAiPluginDefinition WHERE PlannerId = :p.Id
        ]).keySet();
        Set<Id> actionIds = new Map<Id, GenAiFunctionDefinition>([
            SELECT Id FROM GenAiFunctionDefinition WHERE PluginId IN :topicIds
        ]).keySet();
        System.assertEquals(4, actionIds.size(), 'Four distinct required payment/receipt/loyalty/log steps');
        OhmDTO.AgentModel full = new OhmDiscoveryService().discover();
        OhmDTO.AgentModel payment = new OhmDTO.AgentModel();
        for (OhmDTO.ActionNode a : full.actions) {
            if (actionIds.contains((Id) a.id)) {
                System.assertEquals('flow', a.invocationTargetType.toLowerCase());
                payment.actions.add(a);
            }
        }
        System.assertEquals(4, payment.actions.size());
        System.assertEquals(0, new LlmWhereDeterministicDetector().detect(payment).size(),
            'Existing deterministic Flow actions must not be counted as removable LLM calls');
    }

    @IsTest static void promptInventoryRecognizesPublishedTargetType() {
        Integer expected = [SELECT COUNT() FROM GenAiFunctionDefinition WHERE InvocationTargetType = 'generatePromptResponse'];
        System.assert(expected > 0, 'Published scheduling recipe must expose a prompt action');
        OhmDTO.AgentModel full = new OhmDiscoveryService().discover();
        System.assertEquals(expected, full.promptTemplateCount,
            'Actual generatePromptResponse actions must appear in the prompt inventory');
    }

    @IsTest static void informationIsNotEvidenceOfFormattingWork() {
        OhmDTO.AgentModel full = new OhmDiscoveryService().discover();
        OhmDTO.AgentModel schedule = new OhmDTO.AgentModel();
        for (OhmDTO.ActionNode a : full.actions) {
            if (a.developerName.startsWith('generate_personalized_schedule_')) {
                schedule.actions.add(a);
            }
        }
        System.assertEquals(1, schedule.actions.size(), 'Use the real published scheduling action description');
        System.assert(schedule.actions[0].description.contains('information'));
        System.assertEquals(0, new LlmWhereDeterministicDetector().detect(schedule).size(),
            'The substring format inside information does not establish deterministic replacement');
    }

    @IsTest static void publishedScheduleMiniModelIsSmall() {
        // This is primaryModel in the pinned upstream scheduling prompt template.
        ModelRegistry.ModelInfo model = ModelRegistry.lookup('sfdc_ai__DefaultOpenAIGPT4OmniMini');
        System.assertEquals('SMALL', model.tier, 'Mini model suffix must take precedence over GPT4/Omni family');
    }
}
