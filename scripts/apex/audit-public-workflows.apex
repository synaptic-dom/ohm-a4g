// Scratch-lab audit submission probe. Queued audits invoke the OHM Salesforce
// Prompt Builder reviewer; the audited agents and their business actions are not executed.
// Run with: sf apex run -o ohm-audit-lab -f scripts/apex/audit-public-workflows.apex --json
// The returned IDs are queued reports. Collect their status in a later transaction
// with collect-demo-results.py; reviews are valid only after Run_Status__c = Complete.
Set<String> names = new Set<String>{
    'ActionDefinitions_v1', 'ActionChaining_v1',
    'PromptTemplateActions_v1', 'Ohm_Weather_Demo_v4'
};
List<GenAiPlannerDefinition> planners = [
    SELECT Id, DeveloperName, AgentGraph FROM GenAiPlannerDefinition
    WHERE DeveloperName IN :names ORDER BY DeveloperName
];
OhmDiscoveryService discovery = new OhmDiscoveryService();
for (GenAiPlannerDefinition planner : planners) {
    List<GenAiPluginDefinition> topics = [
        SELECT Id, DeveloperName, Scope FROM GenAiPluginDefinition WHERE PlannerId = :planner.Id
    ];
    Set<Id> topicIds = new Set<Id>();
    Integer scopeChars = 0;
    for (GenAiPluginDefinition topic : topics) {
        topicIds.add(topic.Id);
        scopeChars += topic.Scope == null ? 0 : topic.Scope.length();
    }
    List<GenAiFunctionDefinition> actions = [
        SELECT Id, DeveloperName, InvocationTargetType FROM GenAiFunctionDefinition
        WHERE PluginId IN :topicIds OR PlannerId = :planner.Id
    ];
    Map<String, Integer> actionTypes = new Map<String, Integer>();
    for (GenAiFunctionDefinition action : actions) {
        String kind = action.InvocationTargetType;
        actionTypes.put(kind, (actionTypes.containsKey(kind) ? actionTypes.get(kind) : 0) + 1);
    }
    OhmDTO.AgentModel graph = discovery.discoverForRetrieval(planner.Id);
    Id reportId = OhmAuditController.auditProcess(planner.Id);
    Agent_Audit_Report__c report = [
        SELECT Run_Status__c, Async_Job_Id__c
        FROM Agent_Audit_Report__c WHERE Id = :reportId
    ];
    System.debug('OHM_PUBLIC_QUEUED ' + JSON.serialize(new Map<String, Object>{
        'planner' => planner.DeveloperName, 'plannerId' => planner.Id,
        'structuralTopics' => topics.size(), 'structuralActions' => actions.size(),
        'actionTypes' => actionTypes, 'persistedScopeChars' => scopeChars,
        'agentGraphPresent' => String.isNotBlank(planner.AgentGraph),
        'ohmTopics' => graph.topics.size(), 'ohmActions' => graph.actions.size(),
        'queuedReportId' => reportId, 'status' => report.Run_Status__c,
        'asyncJobId' => report.Async_Job_Id__c,
        'inventoryErrors' => graph.discoveryErrors
    }));
}

// Distinguish raw full-org discovery from Ohm's per-process name matching.
OhmDTO.AgentModel full = discovery.discoverForRetrieval(null);
System.debug('OHM_PUBLIC_FULL ' + JSON.serialize(new Map<String, Object>{
    'agents' => full.agentsById.size(), 'topics' => full.topics.size(),
    'actions' => full.actions.size(), 'promptTemplates' => full.promptTemplateCount
}));
