// Can Apex read the Agentforce definition objects via INLINE SOQL (no Tooling callout)?
// If yes, the whole auth chain is unnecessary.
try {
    Integer p = [SELECT COUNT() FROM GenAiPlannerDefinition];
    System.debug('OHM_PROBE GenAiPlannerDefinition inline SOQL OK count=' + p);
} catch (Exception e) { System.debug('OHM_PROBE GenAiPlannerDefinition FAIL: ' + e.getMessage()); }

try {
    Integer p = [SELECT COUNT() FROM GenAiPluginDefinition];
    System.debug('OHM_PROBE GenAiPluginDefinition inline SOQL OK count=' + p);
} catch (Exception e) { System.debug('OHM_PROBE GenAiPluginDefinition FAIL: ' + e.getMessage()); }

try {
    Integer p = [SELECT COUNT() FROM GenAiFunctionDefinition];
    System.debug('OHM_PROBE GenAiFunctionDefinition inline SOQL OK count=' + p);
} catch (Exception e) { System.debug('OHM_PROBE GenAiFunctionDefinition FAIL: ' + e.getMessage()); }

// Also probe reading the actual fields we need for the signals
try {
    for (GenAiPlannerDefinition d : [SELECT Id, DeveloperName, MasterLabel, PlannerType, AgentGraph FROM GenAiPlannerDefinition LIMIT 5]) {
        System.debug('OHM_PROBE planner=' + d.DeveloperName + ' type=' + d.PlannerType + ' graphLen=' + (d.AgentGraph == null ? 0 : d.AgentGraph.length()));
    }
    System.debug('OHM_PROBE planner field read OK');
} catch (Exception e) { System.debug('OHM_PROBE planner field read FAIL: ' + e.getMessage()); }

try {
    for (GenAiFunctionDefinition f : [SELECT Id, DeveloperName, InvocationTargetType, InvocationTarget, PluginId, PlannerId FROM GenAiFunctionDefinition LIMIT 5]) {
        System.debug('OHM_PROBE action=' + f.DeveloperName + ' targetType=' + f.InvocationTargetType);
    }
    System.debug('OHM_PROBE action field read OK');
} catch (Exception e) { System.debug('OHM_PROBE action field read FAIL: ' + e.getMessage()); }
