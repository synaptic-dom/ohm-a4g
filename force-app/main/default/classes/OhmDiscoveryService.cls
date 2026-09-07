/**
 * OhmDiscoveryService — discovers published Agent Script audit candidates.
 * C13: discovery is INLINE APEX SOQL — no callout, no Named Credential, no Tooling client.
 * Three inventory queries (GenAiPlannerDefinition, GenAiPluginDefinition, GenAiFunctionDefinition),
 * each wrapped in try/catch appending to discoveryErrors — a partial failure never sinks discovery.
 * One additional query loads explicitly imported instruction sources; no SOQL/DML in loops.
 */
public with sharing class OhmDiscoveryService {
    public static final String AGENT_SCRIPT_SCOPE_MESSAGE =
        'OHM audits published Agent Script bundles only. Select a versioned Agent Script agent from the fleet.';
    public class AuditScopeException extends Exception {}

    /** Candidate naming is an inventory filter, not source proof. Retrieval must verify the
     * exact published target in an AiAuthoringBundle before any audit can complete.
     */
    public static Boolean isAgentScriptCandidate(String apiName) {
        if (String.isBlank(apiName)) return false;
        return Pattern.matches('^([A-Za-z_][A-Za-z0-9_]*)_v([1-9][0-9]*)$', apiName);
    }

    /**
     * C5 canonical signature. Runs Q1→Q2→Q3, builds the AgentModel tree
     * (agentsById, topics, actions, topicsByPlanner, actionsByPlugin, actionsByPlanner),
     * binds models best-effort (C13: no metadata fetch — boundModel stays null, modelAssumed=true
     * for prompt-typed actions so signal (b) degrades to its informational branch),
     * and computes promptTemplateCount (C10 reference-count path).
     */
    private Map<String, String> metadataVersions = new Map<String, String>();

    public OhmDTO.AgentModel discover() {
        OhmDTO.AgentModel g = inventory();
        retainLatestPlannerVersions(g);
        completeDiscovery(g);
        return g;
    }

    /** Audit acquisition deliberately ignores cached/imported text. Every new run fetches source. */
    public OhmDTO.AgentModel discoverForRetrieval(Id plannerId) {
        OhmDTO.AgentModel graph = inventory();
        if (plannerId == null) {
            retainLatestPlannerVersions(graph);
        } else {
            graph = scopeInventory(graph, String.valueOf(plannerId));
        }
        buildTree(graph);
        graph.metadataFingerprint = fingerprint(graph, metadataVersions);
        graph.promptTemplateCount = countPromptTemplates(graph);
        return graph;
    }

    public String plannerFingerprint(OhmDTO.AgentModel graph, String plannerId) {
        return fingerprint(scopeInventory(graph, plannerId), metadataVersions);
    }

    /** Attach only immutable source records selected by this audit, then assess coverage. */
    public void finishRetrievedDiscovery(OhmDTO.AgentModel graph, Set<Id> sourceIds) {
        OhmSourceImportService.applyPinnedSources(graph, metadataVersions, sourceIds);
        bindModels(graph);
        assessCoverage(graph);
    }

    private OhmDTO.AgentModel scopeInventory(OhmDTO.AgentModel all, String plannerId) {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
        graph.discoveryErrors.addAll(all.discoveryErrors);
        if (!all.agentsById.containsKey(plannerId)) {
            graph.discoveryErrors.add(AGENT_SCRIPT_SCOPE_MESSAGE + ' The selected publication is unavailable or outside this scope.');
            return graph;
        }
        graph.agentsById.put(plannerId, all.agentsById.get(plannerId));
        for (OhmDTO.TopicNode node : all.topics) if (node.plannerId == plannerId) graph.topics.add(node);
        for (OhmDTO.ActionNode node : all.actions) if (node.plannerId == plannerId) graph.actions.add(node);
        for (String warning : all.coverageWarnings) {
            if (warning.contains(plannerId) || warning.startsWith('Unlinked')) graph.coverageWarnings.add(warning);
        }
        return graph;
    }

    private OhmDTO.AgentModel inventory() {
        metadataVersions.clear();
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        queryAgents(g);
        queryTopics(g);
        queryActions(g);
        retainAgentScriptCandidates(g);
        resolveRelationships(g);
        return g;
    }

    /** Remove unrelated legacy/shared metadata before resolving ownership. Unowned global
     * actions cannot be attributed to an Agent Script bundle and do not lower its coverage.
     * Explicit relationships into the selected scope are retained, including conflicts.
     */
    @TestVisible
    private static void retainAgentScriptCandidates(OhmDTO.AgentModel graph) {
        Set<String> keepIds = new Set<String>();
        for (OhmDTO.AgentNode node : graph.agentsById.values()) {
            if (isAgentScriptCandidate(node.developerName)) keepIds.add(node.id);
        }
        for (String plannerId : new List<String>(graph.agentsById.keySet())) {
            if (!keepIds.contains(plannerId)) graph.agentsById.remove(plannerId);
        }
        Set<String> keepTopicIds = new Set<String>();
        List<OhmDTO.TopicNode> topics = new List<OhmDTO.TopicNode>();
        for (OhmDTO.TopicNode topic : graph.topics) {
            if (keepIds.contains(topic.plannerId)) {
                topics.add(topic);
                keepTopicIds.add(topic.id);
            }
        }
        graph.topics = topics;
        List<OhmDTO.ActionNode> actions = new List<OhmDTO.ActionNode>();
        for (OhmDTO.ActionNode action : graph.actions) {
            if (keepIds.contains(action.plannerId) || keepTopicIds.contains(action.pluginId)) actions.add(action);
        }
        graph.actions = actions;
    }

    private void completeDiscovery(OhmDTO.AgentModel g) {
        buildTree(g);
        g.metadataFingerprint = fingerprint(g, metadataVersions);
        OhmSourceImportService.applySources(g, metadataVersions);
        bindModels(g);
        g.promptTemplateCount = countPromptTemplates(g);
        assessCoverage(g);
    }

    /** Q1 — GenAiPlannerDefinition → AgentNode. */
    private void queryAgents(OhmDTO.AgentModel g) {
        try {
            for (GenAiPlannerDefinition p : [
                SELECT Id, DeveloperName, MasterLabel, Description, PlannerType, Capabilities, AgentGraph, LastModifiedDate
                FROM GenAiPlannerDefinition ORDER BY MasterLabel NULLS LAST
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
                metadataVersions.put(a.id, String.valueOf(p.LastModifiedDate.getTime()));
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
                       ParentId, CanEscalate, PlannerId, LastModifiedDate
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
                metadataVersions.put(n.id, String.valueOf(t.LastModifiedDate.getTime()));
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
                       InvocationTarget, IsConfirmationRequired, IsLocal, PluginId, PlannerId, LastModifiedDate
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
                metadataVersions.put(a.id, String.valueOf(fn.LastModifiedDate.getTime()));
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
        return a != null && OhmActionTypes.isPrompt(a.invocationTargetType);
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

    // Older metadata can lack relationship IDs. Name inference is a compatibility fallback
    // only, never an override for an authoritative relationship, and always lowers coverage.

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
     * Build the planner→match-key map with COLLISION RESOLUTION (G9): if two planners reduce to
     * the same key (e.g. Ohm_Lead_Triage and Ohm_Lead_Scoring both → "lead"), BOTH fall back to
     * their full (unique) DeveloperName as the key — otherwise one planner would absorb every
     * shared-key node and the other would render empty. Bulk-safe: no SOQL.
     */
    private Map<Id, String> buildKeyByPlanner(List<OhmDTO.AgentNode> planners) {
        Map<Id, String> keys = new Map<Id, String>();
        Map<String, Integer> counts = new Map<String, Integer>();
        for (OhmDTO.AgentNode p : planners) {
            String k = plannerMatchKey(p.developerName);
            keys.put((Id)p.id, k);
            counts.put(k, (counts.containsKey(k) ? counts.get(k) : 0) + 1);
        }
        for (OhmDTO.AgentNode p : planners) {
            if (counts.get(keys.get((Id)p.id)) > 1) {
                keys.put((Id)p.id, p.developerName.toLowerCase());
            }
        }
        return keys;
    }

    /**
     * Assign a node (by its DeveloperName) to the planner whose match key it best matches.
     * G9: a WHOLE '_'-segment match (score 2) always beats a mere substring match (score 1), so
     * a node like Ohm_Reorder_Helper goes to the "reorder" planner, not the "order" planner whose
     * key is a substring of "reorder". Ties break on longer key, then lower Id — fully
     * deterministic (never nondeterministic keyset order). Returns null when no key matches.
     * keyByPlanner is precomputed once (no SOQL here) — bulk-safe.
     */
    private Id bestPlannerFor(String nodeDeveloperName, Map<Id, String> keyByPlanner) {
        if (String.isBlank(nodeDeveloperName)) { return null; }
        String hay = nodeDeveloperName.toLowerCase();
        Set<String> segs = new Set<String>(hay.split('_'));
        Id best = null;
        Integer bestScore = 0;
        Integer bestLen = -1;
        for (Id pid : keyByPlanner.keySet()) {
            String key = keyByPlanner.get(pid);
            if (String.isBlank(key)) { continue; }
            Integer score = segs.contains(key) ? 2 : (hay.contains(key) ? 1 : 0);
            if (score == 0) { continue; }
            Boolean better = score > bestScore
                || (score == bestScore && key.length() > bestLen)
                || (score == bestScore && key.length() == bestLen && (best == null || pid < best));
            if (better) {
                best = pid;
                bestScore = score;
                bestLen = key.length();
            }
        }
        return best;
    }

    /** Cheap fleet counts share the same authoritative inventory relationships as audits.
     * No source import query, detectors, report data or model calls run during fleet listing.
     */
    public List<OhmDTO.ProcessSummaryDTO> listFleet() {
        OhmDTO.AgentModel g = inventory();
        retainLatestPlannerVersions(g);
        buildTree(g);
        List<OhmDTO.ProcessSummaryDTO> fleet = new List<OhmDTO.ProcessSummaryDTO>();
        for (OhmDTO.AgentNode p : g.agentsById.values()) {
            OhmDTO.ProcessSummaryDTO row = new OhmDTO.ProcessSummaryDTO();
            row.plannerId = (Id)p.id;
            row.plannerApiName = p.developerName;
            row.label = String.isNotBlank(p.masterLabel) ? p.masterLabel : p.developerName;
            row.domain = deriveDomain(p.developerName, p.masterLabel);
            row.topicCount = g.topicsByPlanner.containsKey(p.id) ? g.topicsByPlanner.get(p.id).size() : 0;
            row.actionCount = g.actionsByPlanner.containsKey(p.id) ? g.actionsByPlanner.get(p.id).size() : 0;
            fleet.add(row);
        }
        return fleet;
    }

    /** Fleet inventory represents one current published version per exact logical name.
     * Process discovery deliberately keeps its exact-ID path for older Agent Script publications.
     */
    @TestVisible
    private static void retainLatestPlannerVersions(OhmDTO.AgentModel graph) {
        Map<String, OhmDTO.AgentNode> latest = new Map<String, OhmDTO.AgentNode>();
        for (OhmDTO.AgentNode node : graph.agentsById.values()) {
            String key = OhmPersistenceService.logicalProcessKey(node.developerName, node.id);
            OhmDTO.AgentNode current = latest.get(key);
            if (current == null || laterPlannerVersion(node, current)) { latest.put(key, node); }
        }
        Set<String> keepIds = new Set<String>();
        for (OhmDTO.AgentNode node : latest.values()) { keepIds.add(node.id); }
        Set<String> removedIds = new Set<String>();
        for (String id : graph.agentsById.keySet()) {
            if (!keepIds.contains(id)) { removedIds.add(id); }
        }
        if (removedIds.isEmpty()) { return; }
        for (String id : removedIds) { graph.agentsById.remove(id); }
        Set<String> removedTopics = new Set<String>();
        List<OhmDTO.TopicNode> topics = new List<OhmDTO.TopicNode>();
        for (OhmDTO.TopicNode topic : graph.topics) {
            if (removedIds.contains(topic.plannerId)) { removedTopics.add(topic.id); }
            else { topics.add(topic); }
        }
        graph.topics = topics;
        List<OhmDTO.ActionNode> actions = new List<OhmDTO.ActionNode>();
        for (OhmDTO.ActionNode action : graph.actions) {
            if (!removedIds.contains(action.plannerId) && !removedTopics.contains(action.pluginId)) { actions.add(action); }
        }
        graph.actions = actions;
        List<String> warnings = new List<String>();
        for (String warning : graph.coverageWarnings) {
            Boolean removedOnly = false;
            Boolean affectsCurrent = false;
            for (String id : removedIds) if (warning.contains(id)) removedOnly = true;
            for (String id : keepIds) if (warning.contains(id)) affectsCurrent = true;
            if (!removedOnly || affectsCurrent) warnings.add(warning);
        }
        graph.coverageWarnings = warnings;
    }

    private static Boolean laterPlannerVersion(OhmDTO.AgentNode candidate, OhmDTO.AgentNode current) {
        String candidateVersion = plannerVersionDigits(candidate.developerName);
        String currentVersion = plannerVersionDigits(current.developerName);
        if (candidateVersion != null && currentVersion == null) { return true; }
        if (candidateVersion == null && currentVersion != null) { return false; }
        if (candidateVersion != null && candidateVersion != currentVersion) {
            if (candidateVersion.length() != currentVersion.length()) { return candidateVersion.length() > currentVersion.length(); }
            return candidateVersion.compareTo(currentVersion) > 0;
        }
        // Deterministic tie-break for numerically equal suffixes such as _v01 and _v1.
        return candidate.id.compareTo(current.id) > 0;
    }

    private static String plannerVersionDigits(String apiName) {
        if (String.isBlank(apiName)) { return null; }
        Matcher versionMatcher = Pattern.compile('(?i)_v([0-9]+)$').matcher(apiName);
        if (!versionMatcher.find()) { return null; }
        String digits = versionMatcher.group(1);
        while (digits.length() > 1 && digits.startsWith('0')) { digits = digits.substring(1); }
        return digits;
    }

    /**
     * G12: cheap single-planner identity (id/apiName/label/domain) — ONE SOQL. Replaces the
     * former full listFleet() scan in getProcessDetail, which re-tallied every planner's counts
     * just to read one label; that scan ran on every assistant question. Returns null if absent.
     */
    public OhmDTO.ProcessSummaryDTO resolveIdentity(Id plannerId) {
        if (plannerId == null) { return null; }
        for (GenAiPlannerDefinition p : [
            SELECT Id, DeveloperName, MasterLabel
            FROM GenAiPlannerDefinition
            WHERE Id = :plannerId
            LIMIT 1
        ]) {
            OhmDTO.ProcessSummaryDTO row = new OhmDTO.ProcessSummaryDTO();
            row.plannerId = p.Id;
            row.plannerApiName = p.DeveloperName;
            row.label = String.isNotBlank(p.MasterLabel) ? p.MasterLabel : p.DeveloperName;
            row.domain = deriveDomain(p.DeveloperName, p.MasterLabel);
            return row;
        }
        return null;
    }

    /** Discover one planner subtree using real IDs, then attach matching versioned source.
     * Only Agent Script candidates are eligible; older published versions remain addressable.
     */
    public OhmDTO.AgentModel discoverProcess(Id plannerId) {
        OhmDTO.AgentModel all = inventory();
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        g.discoveryErrors.addAll(all.discoveryErrors);
        if (plannerId == null || !all.agentsById.containsKey(String.valueOf(plannerId))) {
            g.discoveryErrors.add(AGENT_SCRIPT_SCOPE_MESSAGE + ' No eligible publication found for Id ' + plannerId + '.');
            assessCoverage(g);
            return g;
        }
        String pid = String.valueOf(plannerId);
        g.agentsById.put(pid, all.agentsById.get(pid));
        for (OhmDTO.TopicNode t : all.topics) {
            if (t.plannerId == pid) { g.topics.add(t); }
        }
        for (OhmDTO.ActionNode a : all.actions) {
            if (a.plannerId == pid) { g.actions.add(a); }
        }
        // Preserve warnings affecting this process; source/coverage checks run on the scoped graph.
        for (String warning : all.coverageWarnings) {
            if (warning.contains(pid) || warning.startsWith('Unlinked')) { g.coverageWarnings.add(warning); }
        }
        completeDiscovery(g);
        return g;
    }

    @TestVisible
    private void resolveRelationships(OhmDTO.AgentModel g) {
        Map<Id, String> keys = buildKeyByPlanner(g.agentsById.values());
        Map<String, OhmDTO.TopicNode> topicsById = new Map<String, OhmDTO.TopicNode>();
        for (OhmDTO.TopicNode t : g.topics) {
            if (String.isBlank(t.plannerId)) {
                Id inferred = bestPlannerFor(t.developerName, keys);
                if (inferred != null) {
                    t.plannerId = String.valueOf(inferred);
                    g.coverageWarnings.add('Inferred topic ownership for ' + t.developerName + ' in ' + inferred);
                } else {
                    g.coverageWarnings.add('Unlinked topic: ' + t.developerName);
                }
            }
            topicsById.put(t.id, t);
        }
        for (OhmDTO.ActionNode a : g.actions) {
            if (String.isNotBlank(a.pluginId)) {
                OhmDTO.TopicNode parent = topicsById.get(a.pluginId);
                if (parent == null || String.isBlank(parent.plannerId)) {
                    // An unresolved explicit relationship must never fall through to a name guess.
                    g.coverageWarnings.add('Unlinked action parent: ' + a.developerName
                        + (String.isBlank(a.plannerId) ? '' : ' in ' + a.plannerId));
                    continue;
                }
                if (String.isNotBlank(a.plannerId) && a.plannerId != parent.plannerId) {
                    g.coverageWarnings.add('Conflicting action ownership for ' + a.developerName + ' in '
                        + a.plannerId + ' and ' + parent.plannerId);
                    a.plannerId = null;
                    continue;
                }
                a.plannerId = parent.plannerId;
            } else if (String.isBlank(a.plannerId)) {
                Id inferred = bestPlannerFor(a.developerName, keys);
                if (inferred != null) {
                    a.plannerId = String.valueOf(inferred);
                    g.coverageWarnings.add('Inferred action ownership for ' + a.developerName + ' in ' + inferred);
                } else { g.coverageWarnings.add('Unlinked action: ' + a.developerName); }
            }
        }
    }

    public static String fingerprint(OhmDTO.AgentModel g, Map<String, String> versions) {
        List<String> parts = new List<String>();
        for (String id : g.agentsById.keySet()) { parts.add(id + ':' + versions.get(id)); }
        for (OhmDTO.TopicNode t : g.topics) { parts.add(t.id + ':' + versions.get(t.id)); }
        for (OhmDTO.ActionNode a : g.actions) { parts.add(a.id + ':' + versions.get(a.id)); }
        parts.sort();
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(parts, '\n'))));
    }

    private void assessCoverage(OhmDTO.AgentModel g) {
        Boolean instructionsCovered = !g.agentsById.isEmpty();
        Boolean graphCovered = !g.agentsById.isEmpty();
        Boolean modelsCovered = true;
        g.instructionSourceCount = 0;
        for (OhmDTO.AgentNode a : g.agentsById.values()) {
            if (a.instructions == null) { instructionsCovered = false; }
            else { g.instructionSourceCount++; }
            if (String.isBlank(a.agentGraphJson)) { graphCovered = false; }
        }
        for (OhmDTO.TopicNode t : g.topics) {
            if (t.instructions == null && String.isNotBlank(t.scope)) {
                t.instructions = t.scope;
                t.sourceKind = 'PlatformScope';
                t.sourceVersion = metadataVersions.get(t.id);
                t.sourceHash = OhmSourceImportService.sha256(t.scope);
                t.sourcePath = 'GenAiPluginDefinition/' + t.developerName + '/Scope';
            }
            if (t.instructions == null) { instructionsCovered = false; }
            else { g.instructionSourceCount++; }
        }
        for (OhmDTO.ActionNode a : g.actions) {
            if (OhmActionTypes.isPrompt(a.invocationTargetType)) {
                if (a.instructions == null) { instructionsCovered = false; }
                else { g.instructionSourceCount++; }
                if (String.isBlank(a.boundModel) || a.modelAssumed == true) { modelsCovered = false; }
            }
        }
        if (!instructionsCovered) { g.coverageWarnings.add('Instruction source unavailable for one or more artifacts. Import current versioned source before interpreting instruction efficiency.'); }
        if (!graphCovered) { g.coverageWarnings.add('Execution graph unavailable; redundant-call coverage is unknown.'); }
        if (!modelsCovered) { g.coverageWarnings.add('Published model binding unavailable for one or more prompt actions.'); }
        g.detectorCoverage.put('INSTRUCTION_BLOAT', instructionsCovered ? 'Covered' : 'Unknown');
        g.detectorCoverage.put('REDUNDANT_CALLS', graphCovered ? 'Covered' : 'Unknown');
        g.detectorCoverage.put('MODEL_RIGHTSIZING', modelsCovered ? 'Covered' : 'Unknown');
        g.detectorCoverage.put('LLM_WHERE_DETERMINISTIC', g.discoveryErrors.isEmpty() ? 'Covered' : 'Unknown');
        g.coverageComplete = instructionsCovered && graphCovered && modelsCovered
            && g.discoveryErrors.isEmpty() && g.coverageWarnings.isEmpty();
    }
}
