/**
 * OhmDiscoveryService — discovers the org's agentic surface (SPEC §S.2, canon C5/C13).
 * C13: discovery is INLINE APEX SOQL — no callout, no Named Credential, no Tooling client.
 * Three queries total (GenAiPlannerDefinition, GenAiPluginDefinition, GenAiFunctionDefinition),
 * each wrapped in try/catch appending to discoveryErrors — a partial failure never sinks discovery.
 * Bulk-safe: no SOQL/DML in loops.
 */
public with sharing class OhmDiscoveryService {

    /**
     * C5 canonical signature. Runs Q1→Q2→Q3, builds the AgentModel tree
     * (agentsById, topics, actions, topicsByPlanner, actionsByPlugin, actionsByPlanner),
     * binds models best-effort (C13: no metadata fetch — boundModel stays null, modelAssumed=true
     * for prompt-typed actions so signal (b) degrades to its informational branch),
     * and computes promptTemplateCount (C10 reference-count path).
     */
    public OhmDTO.AgentModel discover() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        queryAgents(g);
        queryTopics(g);
        queryActions(g);
        buildTree(g);
        bindModels(g);
        g.promptTemplateCount = countPromptTemplates(g);
        return g;
    }

    /** Q1 — GenAiPlannerDefinition → AgentNode. */
    private void queryAgents(OhmDTO.AgentModel g) {
        try {
            for (GenAiPlannerDefinition p : [
                SELECT Id, DeveloperName, MasterLabel, Description, PlannerType, Capabilities, AgentGraph
                FROM GenAiPlannerDefinition
            ]) {
                OhmDTO.AgentNode a = new OhmDTO.AgentNode();
                a.id = p.Id;
                a.developerName = p.DeveloperName;
                a.masterLabel = p.MasterLabel;
                a.description = p.Description;
                a.plannerType = p.PlannerType;
                a.capabilities = p.Capabilities;
                a.agentGraphJson = p.AgentGraph;
                g.agentsById.put(a.id, a);
            }
        } catch (Exception e) {
            g.discoveryErrors.add('Agent discovery (GenAiPlannerDefinition) failed: ' + e.getMessage());
        }
    }

    /** Q2 — GenAiPluginDefinition → TopicNode. */
    private void queryTopics(OhmDTO.AgentModel g) {
        try {
            for (GenAiPluginDefinition t : [
                SELECT Id, DeveloperName, MasterLabel, Description, PluginType, Scope, IsLocal,
                       ParentId, CanEscalate, PlannerId
                FROM GenAiPluginDefinition
            ]) {
                OhmDTO.TopicNode n = new OhmDTO.TopicNode();
                n.id = t.Id;
                n.developerName = t.DeveloperName;
                n.masterLabel = t.MasterLabel;
                n.description = t.Description;
                n.pluginType = t.PluginType;
                n.scope = t.Scope;
                n.isLocal = t.IsLocal;
                n.parentId = t.ParentId;
                n.plannerId = t.PlannerId;
                g.topics.add(n);
            }
        } catch (Exception e) {
            g.discoveryErrors.add('Topic discovery (GenAiPluginDefinition) failed: ' + e.getMessage());
        }
    }

    /** Q3 — GenAiFunctionDefinition → ActionNode. */
    private void queryActions(OhmDTO.AgentModel g) {
        try {
            for (GenAiFunctionDefinition fn : [
                SELECT Id, DeveloperName, MasterLabel, Description, InvocationTargetType,
                       InvocationTarget, IsConfirmationRequired, IsLocal, PluginId, PlannerId
                FROM GenAiFunctionDefinition
            ]) {
                OhmDTO.ActionNode a = new OhmDTO.ActionNode();
                a.id = fn.Id;
                a.developerName = fn.DeveloperName;
                a.masterLabel = fn.MasterLabel;
                a.description = fn.Description;
                a.invocationTargetType = fn.InvocationTargetType;
                a.invocationTarget = fn.InvocationTarget;
                a.isLocal = fn.IsLocal;
                a.pluginId = fn.PluginId;
                a.plannerId = fn.PlannerId;
                g.actions.add(a);
            }
        } catch (Exception e) {
            g.discoveryErrors.add('Action discovery (GenAiFunctionDefinition) failed: ' + e.getMessage());
        }
    }

    /** Populate topicsByPlanner / actionsByPlugin / actionsByPlanner (null keys skipped). */
    private void buildTree(OhmDTO.AgentModel g) {
        for (OhmDTO.TopicNode t : g.topics) {
            if (String.isBlank(t.plannerId)) { continue; }
            if (!g.topicsByPlanner.containsKey(t.plannerId)) {
                g.topicsByPlanner.put(t.plannerId, new List<OhmDTO.TopicNode>());
            }
            g.topicsByPlanner.get(t.plannerId).add(t);
        }
        for (OhmDTO.ActionNode a : g.actions) {
            if (String.isNotBlank(a.pluginId)) {
                if (!g.actionsByPlugin.containsKey(a.pluginId)) {
                    g.actionsByPlugin.put(a.pluginId, new List<OhmDTO.ActionNode>());
                }
                g.actionsByPlugin.get(a.pluginId).add(a);
            }
            if (String.isNotBlank(a.plannerId)) {
                if (!g.actionsByPlanner.containsKey(a.plannerId)) {
                    g.actionsByPlanner.put(a.plannerId, new List<OhmDTO.ActionNode>());
                }
                g.actionsByPlanner.get(a.plannerId).add(a);
            }
        }
    }

    /**
     * C13 model binding: no metadata fetch path exists, so prompt-typed actions carry
     * boundModel=null + modelAssumed=true (ModelRightSizingDetector degrades to its
     * informational "model unknown" branch). Non-prompt actions burn no model tokens.
     */
    private void bindModels(OhmDTO.AgentModel g) {
        for (OhmDTO.ActionNode a : g.actions) {
            if (isPrompt(a) && String.isBlank(a.boundModel)) {
                a.modelAssumed = true;
            } else if (a.modelAssumed == null) {
                a.modelAssumed = false;
            }
        }
    }

    /** C10 / canon §0.7 — count DISTINCT InvocationTarget among prompt-typed actions. Never throws. */
    private Integer countPromptTemplates(OhmDTO.AgentModel g) {
        Set<String> distinctTargets = new Set<String>();
        for (OhmDTO.ActionNode a : g.actions) {
            if (isPrompt(a) && String.isNotBlank(a.invocationTarget)) {
                distinctTargets.add(a.invocationTarget);
            }
        }
        return distinctTargets.size();
    }

    private Boolean isPrompt(OhmDTO.ActionNode a) {
        return a != null
            && a.invocationTargetType != null
            && a.invocationTargetType.equalsIgnoreCase('prompt');
    }
}
