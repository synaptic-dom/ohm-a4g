/**
 * Signal (d) REDUNDANT_CALLS — best-effort (SPEC §S.6d, canon C7d).
 * Tolerant JSON.deserializeUntyped walker over agent.agentGraphJson — NEVER throws on
 * unknown shapes; degrades to no-finding + a discoveryError note.
 * Review candidates require a repeated prompt target within one declared turn, or a
 * cycle containing a prompt node. Distinct calls and deterministic cycles are valid.
 * The static graph cannot establish removable calls or runtime volume; savings are withheld.
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
                errors.add('RedundantCallDetector: unsupported AgentGraph shape for ' + a.developerName);
                return null;
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
                isPrompt.put(id, OhmActionTypes.isPrompt(itt));
                refById.put(id, str(n.get('ref')));
            }

            // Only repeated targets in the same declared turn supply duplication evidence.
            // Different calls, or the same target in separate turns, may be necessary work.
            Integer extraCalls = 0;
            for (Object to : asList(graph.get('turns'))) {
                if (!(to instanceof Map<String, Object>)) { continue; }
                Map<String, Object> turn = (Map<String, Object>) to;
                Set<String> seen = new Set<String>();
                Integer repeats = 0;
                for (Object callId : asList(turn.get('calls'))) {
                    String cid = str(callId);
                    if (isPrompt.get(cid) != true) { continue; }
                    String ref = refById.get(cid);
                    String identity = String.isBlank(ref) ? cid : ref;
                    if (seen.contains(identity)) { repeats++; }
                    seen.add(identity);
                }
                extraCalls = Math.max(extraCalls, repeats);
            }
            Boolean cycle = hasPromptCycle(asList(graph.get('edges')), isPrompt);
            if (extraCalls < 1 && !cycle) { return null; }

            Decimal score = cycle ? 1.0 : min1(0.34 + 0.165 * extraCalls);
            OhmDTO.Finding f = new OhmDTO.Finding();
            f.signalType = SIGNAL;
            f.reviewRequired = true;
            f.severityScore = score;
            f.severity = OhmSeverity.band(score);
            f.confidence = 'Low';
            f.artifactType = 'Agent';
            f.artifactApiName = a.developerName;
            f.artifactLabel = a.masterLabel;
            f.artifactToolingId = a.id;
            f.metricValue = extraCalls;
            f.metricUnit = 'calls-per-turn';
            String ev = 'Static graph review candidate.';
            if (extraCalls > 0) {
                ev += ' Duplicate prompt target appears ' + extraCalls +
                    ' additional time(s) within a declared turn.';
            }
            if (cycle) {
                ev += ' A cycle contains a prompt node; execution frequency and exit conditions are unknown.';
            }
            ev += ' Changed inputs or required steps may justify these calls. No removable-call savings are established.';
            f.evidence = ev;
            return f;
        } catch (Exception e) {
            errors.add('RedundantCallDetector: unparseable AgentGraph for ' +
                (a.developerName == null ? a.id : a.developerName) + ' — ' + e.getMessage());
            return null; // never a false positive
        }
    }

    /** A cycle is relevant only when a prompt node can reach itself. */
    private Boolean hasPromptCycle(List<Object> edges, Map<String, Boolean> isPrompt) {
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
        for (String origin : isPrompt.keySet()) {
            if (isPrompt.get(origin) != true || !adj.containsKey(origin)) { continue; }
            List<String> pending = new List<String>();
            pending.addAll(adj.get(origin));
            Set<String> visited = new Set<String>();
            while (!pending.isEmpty()) {
                String node = pending.remove(pending.size() - 1);
                if (node == origin) { return true; }
                if (visited.contains(node)) { continue; }
                visited.add(node);
                if (adj.containsKey(node)) { pending.addAll(adj.get(node)); }
            }
        }
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
