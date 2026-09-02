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

    // ===================== v2 Workbench (SPEC-ohm-v2-workbench §4) =====================

    /**
     * Friendly domain derived from a planner's DeveloperName / MasterLabel via a simple
     * keyword map (there is no domain field on the metadata). First match wins, in listed
     * priority order; Ohm/Spike is the "internal tooling" bucket checked last before default.
     * The single source of truth — the controller REUSES this (never duplicate the map).
     */
    public String deriveDomain(String developerName, String masterLabel) {
        String hay = (
            (developerName == null ? '' : developerName) + ' ' +
            (masterLabel == null ? '' : masterLabel)
        ).toLowerCase();
        if (hay.contains('lead')) { return 'Sales'; }
        if (hay.contains('order')) { return 'Commerce'; }
        if (hay.contains('service') || hay.contains('case')) { return 'Customer Service'; }
        if (hay.contains('bill')) { return 'Finance'; }
        if (hay.contains('ohm') || hay.contains('spike')) { return 'Internal'; }
        return 'General';
    }

    /**
     * ORG-DATA REALITY (verified on the live org, both inline Apex SOQL and Tooling API):
     * on GenAiPluginDefinition / GenAiFunctionDefinition the PlannerId, PluginId, ParentId
     * fields and GenAiPlannerDefinition.AgentGraph are ALL null for the deployed agents — there
     * is NO structural planner→topic→action linkage to query. The only join that exists is the
     * DeveloperName naming convention (planner Ohm_Waste_Demo ↔ topic Ohm_Waste_LeadTriage ↔
     * action Ohm_Waste_ClassifyLeadTier). So fleet counts and per-process scoping join by a
     * distinctive DeveloperName key. The PUBLIC signatures (listFleet / discoverProcess) match
     * the shared contract exactly; only the internal join differs and is invisible to callers.
     */

    // Generic DeveloperName segments that never distinguish one planner from another.
    private static final Set<String> GENERIC_PLANNER_TOKENS = new Set<String>{
        'ohm', 'agent', 'demo', 'sample', 'bot', 'assistant', 'concierge', 'support'
    };

    /**
     * Distinctive lowercase key for a planner DeveloperName: the first '_'-delimited segment
     * that is not a generic token (Ohm_Waste_Demo→"waste", Ohm_Sample_Order→"order",
     * Ohm_Sample_Service→"service", Ohm_Spike_Agent→"spike"). Falls back to the full lowercased
     * DeveloperName when every segment is generic. Used to join topics/actions to their planner.
     */
    private String plannerMatchKey(String plannerDeveloperName) {
        if (String.isBlank(plannerDeveloperName)) { return ''; }
        for (String seg : plannerDeveloperName.split('_')) {
            String s = seg.trim().toLowerCase();
            if (String.isNotBlank(s) && !GENERIC_PLANNER_TOKENS.contains(s)) {
                return s;
            }
        }
        return plannerDeveloperName.toLowerCase();
    }

    /**
     * Assign a node (by its DeveloperName) to the planner whose match key it contains; when a
     * node contains more than one planner's key, the LONGEST key wins (most specific). Returns
     * null when no key matches. keyByPlanner is precomputed once (no SOQL here) — bulk-safe.
     */
    private Id bestPlannerFor(String nodeDeveloperName, Map<Id, String> keyByPlanner) {
        if (String.isBlank(nodeDeveloperName)) { return null; }
        String hay = nodeDeveloperName.toLowerCase();
        Id best = null;
        Integer bestLen = -1;
        for (Id pid : keyByPlanner.keySet()) {
            String key = keyByPlanner.get(pid);
            if (String.isNotBlank(key) && hay.contains(key) && key.length() > bestLen) {
                best = pid;
                bestLen = key.length();
            }
        }
        return best;
    }

    /**
     * CHEAP fleet listing (SPEC §4). Bulk-safe: exactly THREE inline SOQL total regardless of
     * planner count (planners, all topics, all actions), then counts are tallied in memory —
     * NO SOQL inside any loop. Counts join topics/actions to planners by the DeveloperName key
     * (see ORG-DATA REALITY above; PlannerId is null on this org).
     * Populates plannerId/apiName/label/domain/topicCount/actionCount only; audited/grade/score/
     * energy/latestReportId/lastAudited are left null for the CONTROLLER to join in from reports.
     */
    public List<OhmDTO.ProcessSummaryDTO> listFleet() {
        List<GenAiPlannerDefinition> planners = new List<GenAiPlannerDefinition>();
        try {
            planners = [
                SELECT Id, DeveloperName, MasterLabel, Description
                FROM GenAiPlannerDefinition
                ORDER BY MasterLabel NULLS LAST
            ];
        } catch (Exception e) {
            return new List<OhmDTO.ProcessSummaryDTO>();
        }

        Map<Id, String> keyByPlanner = new Map<Id, String>();
        for (GenAiPlannerDefinition p : planners) {
            keyByPlanner.put(p.Id, plannerMatchKey(p.DeveloperName));
        }

        Map<Id, Integer> topicCountByPlanner = new Map<Id, Integer>();
        Map<Id, Integer> actionCountByPlanner = new Map<Id, Integer>();

        try {
            for (GenAiPluginDefinition t : [SELECT DeveloperName FROM GenAiPluginDefinition]) {
                Id pid = bestPlannerFor(t.DeveloperName, keyByPlanner);
                if (pid == null) { continue; }
                Integer c = topicCountByPlanner.get(pid);
                topicCountByPlanner.put(pid, (c == null ? 0 : c) + 1);
            }
        } catch (Exception e) {
            // partial-failure tolerant: topic counts stay 0
        }

        try {
            for (GenAiFunctionDefinition fn : [SELECT DeveloperName FROM GenAiFunctionDefinition]) {
                Id pid = bestPlannerFor(fn.DeveloperName, keyByPlanner);
                if (pid == null) { continue; }
                Integer c = actionCountByPlanner.get(pid);
                actionCountByPlanner.put(pid, (c == null ? 0 : c) + 1);
            }
        } catch (Exception e) {
            // partial-failure tolerant: action counts stay 0
        }

        List<OhmDTO.ProcessSummaryDTO> fleet = new List<OhmDTO.ProcessSummaryDTO>();
        for (GenAiPlannerDefinition p : planners) {
            OhmDTO.ProcessSummaryDTO row = new OhmDTO.ProcessSummaryDTO();
            row.plannerId = p.Id;
            row.plannerApiName = p.DeveloperName;
            row.label = String.isNotBlank(p.MasterLabel) ? p.MasterLabel : p.DeveloperName;
            row.domain = deriveDomain(p.DeveloperName, p.MasterLabel);
            Integer tc = topicCountByPlanner.get(p.Id);
            Integer ac = actionCountByPlanner.get(p.Id);
            row.topicCount = (tc == null) ? 0 : tc;
            row.actionCount = (ac == null) ? 0 : ac;
            // audited/grade/score/energy/latestReportId/lastAudited intentionally left null (controller joins)
            fleet.add(row);
        }
        return fleet;
    }

    /**
     * DEEP discovery scoped to ONE planner subtree (SPEC §4) — the same AgentModel shape the
     * detectors consume (flat g.topics / g.actions / g.agentsById). Reuses the existing per-node
     * mapping shape, but the tree contains only the given planner plus the topics and actions that
     * join to it by DeveloperName key (see ORG-DATA REALITY above; PlannerId is null on this org).
     * Bulk-safe: three inline SOQL total, no SOQL in loops. Kept nodes get plannerId stamped so
     * buildTree() groups them under this planner (topicsByPlanner / actionsByPlanner).
     */
    public OhmDTO.AgentModel discoverProcess(Id plannerId) {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        if (plannerId == null) {
            g.discoveryErrors.add('discoverProcess called with a null plannerId');
            return g;
        }

        // All planners are needed so bestPlannerFor never mis-assigns a node whose name also
        // contains another planner's key (longest-key-wins disambiguation).
        Map<Id, String> keyByPlanner = new Map<Id, String>();
        try {
            for (GenAiPlannerDefinition p : [
                SELECT Id, DeveloperName, MasterLabel, Description, PlannerType, Capabilities, AgentGraph
                FROM GenAiPlannerDefinition
            ]) {
                keyByPlanner.put(p.Id, plannerMatchKey(p.DeveloperName));
                if (p.Id == plannerId) {
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
            }
        } catch (Exception e) {
            g.discoveryErrors.add('Process agent discovery failed: ' + e.getMessage());
        }
        if (g.agentsById.isEmpty()) {
            g.discoveryErrors.add('No GenAiPlannerDefinition found for Id ' + plannerId);
        }

        try {
            for (GenAiPluginDefinition t : [
                SELECT Id, DeveloperName, MasterLabel, Description, PluginType, Scope, IsLocal,
                       ParentId, CanEscalate, PlannerId
                FROM GenAiPluginDefinition
            ]) {
                if (bestPlannerFor(t.DeveloperName, keyByPlanner) != plannerId) { continue; }
                OhmDTO.TopicNode n = new OhmDTO.TopicNode();
                n.id = t.Id;
                n.developerName = t.DeveloperName;
                n.masterLabel = t.MasterLabel;
                n.description = t.Description;
                n.pluginType = t.PluginType;
                n.scope = t.Scope;
                n.isLocal = t.IsLocal;
                n.parentId = t.ParentId;
                n.plannerId = plannerId;   // stamp scoped linkage (org PlannerId is null)
                g.topics.add(n);
            }
        } catch (Exception e) {
            g.discoveryErrors.add('Process topic discovery failed: ' + e.getMessage());
        }

        try {
            for (GenAiFunctionDefinition fn : [
                SELECT Id, DeveloperName, MasterLabel, Description, InvocationTargetType,
                       InvocationTarget, IsConfirmationRequired, IsLocal, PluginId, PlannerId
                FROM GenAiFunctionDefinition
            ]) {
                if (bestPlannerFor(fn.DeveloperName, keyByPlanner) != plannerId) { continue; }
                OhmDTO.ActionNode a = new OhmDTO.ActionNode();
                a.id = fn.Id;
                a.developerName = fn.DeveloperName;
                a.masterLabel = fn.MasterLabel;
                a.description = fn.Description;
                a.invocationTargetType = fn.InvocationTargetType;
                a.invocationTarget = fn.InvocationTarget;
                a.isLocal = fn.IsLocal;
                a.pluginId = fn.PluginId;
                a.plannerId = plannerId;   // stamp scoped linkage (org PlannerId is null)
                g.actions.add(a);
            }
        } catch (Exception e) {
            g.discoveryErrors.add('Process action discovery failed: ' + e.getMessage());
        }

        buildTree(g);
        bindModels(g);
        g.promptTemplateCount = countPromptTemplates(g);
        return g;
    }
}
