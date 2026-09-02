/**
 * Signal (d) REDUNDANT_CALLS — best-effort (SPEC §S.6d, canon C7d).
 * Tolerant JSON.deserializeUntyped walker over agent.agentGraphJson — NEVER throws on
 * unknown shapes; degrades to no-finding + a discoveryError note.
 * Heuristics: fan-out extraCalls = max(0, promptNodeCount - 1); prompt-bearing cycle;
 * duplicate target. Fire on extraCalls >= 1 OR prompt cycle.
 * score = min(1, 0.34 + 0.165 × extraCalls); a cycle forces score = 1.0.
 * Metric_Value = extraCalls, Metric_Unit = 'calls-per-turn', Confidence = Low.
 */
public with sharing class RedundantCallDetector implements SignalDetector {

    public static final String SIGNAL = 'REDUNDANT_CALLS';

    public List<OhmDTO.Finding> detect(OhmDTO.AgentModel g) {
        List<OhmDTO.Finding> out = new List<OhmDTO.Finding>();
        if (g == null || g.agentsById == null) {
            return out;
        }
        if (g.discoveryErrors == null) {
            g.discoveryErrors = new List<String>();
        }
        for (OhmDTO.AgentNode a : g.agentsById.values()) {
            if (a == null || String.isBlank(a.agentGraphJson)) {
                continue;
            }
            OhmDTO.Finding f = analyzeGraph(a, g.discoveryErrors);
            if (f != null) {
                out.add(f);
            }
        }
        return out;
    }

    private OhmDTO.Finding analyzeGraph(OhmDTO.AgentNode a, List<String> errors) {
        try {
            Object parsed = JSON.deserializeUntyped(a.agentGraphJson);
            if (!(parsed instanceof Map<String, Object>)) {
                return null; // unknown shape — degrade silently
            }
            Map<String, Object> graph = (Map<String, Object>) parsed;

            // node id -> isPrompt, node id -> ref
            Map<String, Boolean> isPrompt = new Map<String, Boolean>();
            Map<String, String> refById = new Map<String, String>();
            List<Object> nodes = asList(graph.get('nodes'));
            for (Object no : nodes) {
                if (!(no instanceof Map<String, Object>)) { continue; }
                Map<String, Object> n = (Map<String, Object>) no;
                String id = str(n.get('id'));
                if (id == null) { continue; }
                String itt = str(n.get('invocationTargetType'));
                isPrompt.put(id, itt != null && itt.equalsIgnoreCase('prompt'));
                refById.put(id, str(n.get('ref')));
            }

            // promptNodeCount: busiest turn's prompt calls, else total prompt nodes
            Integer promptNodeCount = 0;
            List<Object> turns = asList(graph.get('turns'));
            if (!turns.isEmpty()) {
                for (Object to : turns) {
                    if (!(to instanceof Map<String, Object>)) { continue; }
                    Map<String, Object> turn = (Map<String, Object>) to;
                    List<Object> calls = asList(turn.get('calls'));
                    Integer c = 0;
                    for (Object callId : calls) {
                        String cid = str(callId);
                        if (cid != null && isPrompt.get(cid) == true) { c++; }
                    }
                    if (c > promptNodeCount) { promptNodeCount = c; }
                }
            } else {
                for (String id : isPrompt.keySet()) {
                    if (isPrompt.get(id) == true) { promptNodeCount++; }
                }
            }

            Integer extraCalls = Math.max(0, promptNodeCount - 1);

            // duplicate target among prompt nodes
            Boolean duplicateTarget = hasDuplicatePromptRef(isPrompt, refById);

            // prompt-bearing cycle via edges
            Boolean cycle = hasCycle(asList(graph.get('edges')));

            if (extraCalls < 1 && !cycle) {
                return null; // no redundancy
            }

            Decimal score = cycle ? 1.0 : min1(0.34 + 0.165 * extraCalls);
            OhmDTO.Finding f = new OhmDTO.Finding();
            f.signalType = SIGNAL;
            f.severityScore = score;
            f.severity = OhmSeverity.band(score);
            f.confidence = 'Low';
            f.artifactType = 'Agent';
            f.artifactApiName = a.developerName;
            f.artifactLabel = a.masterLabel;
            f.artifactToolingId = a.id;
            f.metricValue = extraCalls;
            f.metricUnit = 'calls-per-turn';
            String ev = 'Turn runs ' + promptNodeCount + ' prompt call(s) → ' + extraCalls +
                ' redundant call(s)/turn.';
            if (duplicateTarget) {
                ev += ' Duplicate action target invoked more than once in the same turn.';
            }
            if (cycle) {
                ev += ' Prompt-bearing cycle detected — cost recurs ×N per loop iteration.';
            }
            f.evidence = ev;
            return f;
        } catch (Exception e) {
            errors.add('RedundantCallDetector: unparseable AgentGraph for ' +
                (a.developerName == null ? a.id : a.developerName) + ' — ' + e.getMessage());
            return null; // never a false positive
        }
    }

    private Boolean hasDuplicatePromptRef(Map<String, Boolean> isPrompt, Map<String, String> refById) {
        Set<String> seen = new Set<String>();
        for (String id : isPrompt.keySet()) {
            if (isPrompt.get(id) != true) { continue; }
            String ref = refById.get(id);
            if (ref == null) { continue; }
            if (seen.contains(ref)) { return true; }
            seen.add(ref);
        }
        return false;
    }

    /** Directed-cycle detection via DFS back-edge over 'edges' [{from,to}]. */
    private Boolean hasCycle(List<Object> edges) {
        Map<String, List<String>> adj = new Map<String, List<String>>();
        for (Object eo : edges) {
            if (!(eo instanceof Map<String, Object>)) { continue; }
            Map<String, Object> e = (Map<String, Object>) eo;
            String fromId = str(e.get('from'));
            String toId = str(e.get('to'));
            if (fromId == null || toId == null) { continue; }
            if (!adj.containsKey(fromId)) { adj.put(fromId, new List<String>()); }
            adj.get(fromId).add(toId);
        }
        Set<String> visited = new Set<String>();
        Set<String> stack = new Set<String>();
        for (String node : adj.keySet()) {
            if (dfsCycle(node, adj, visited, stack)) {
                return true;
            }
        }
        return false;
    }

    private Boolean dfsCycle(String node, Map<String, List<String>> adj, Set<String> visited, Set<String> stack) {
        if (stack.contains(node)) { return true; }
        if (visited.contains(node)) { return false; }
        visited.add(node);
        stack.add(node);
        if (adj.containsKey(node)) {
            for (String nxt : adj.get(node)) {
                if (dfsCycle(nxt, adj, visited, stack)) { return true; }
            }
        }
        stack.remove(node);
        return false;
    }

    private List<Object> asList(Object o) {
        if (o instanceof List<Object>) {
            return (List<Object>) o;
        }
        return new List<Object>();
    }

    private String str(Object o) {
        return (o == null) ? null : String.valueOf(o);
    }

    private Decimal min1(Decimal v) {
        return (v > 1) ? 1 : v;
    }
}
