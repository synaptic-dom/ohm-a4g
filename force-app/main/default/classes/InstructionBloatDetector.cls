/**
 * Signal (c) INSTRUCTION_BLOAT — CONFIRMED, protected (SPEC §S.6c, canon C9).
 * totalTokens = approxTokens(scope|description|capabilities). Fire strictly > soft.
 * excess = total - soft. score = min(1, excess/soft). Metric_Value = EXCESS tokens (C9),
 * Metric_Unit = 'tokens', Evidence records total. Confidence = High.
 * Thresholds: Topic 500/1000, Agent 400/800, Action 150/300.
 */
public with sharing class InstructionBloatDetector implements SignalDetector {

    public static final String SIGNAL = 'INSTRUCTION_BLOAT';

    public List<OhmDTO.Finding> detect(OhmDTO.AgentModel g) {
        List<OhmDTO.Finding> out = new List<OhmDTO.Finding>();
        if (g == null) {
            return out;
        }
        OhmConstants c = OhmConstants.load();

        // Topics
        if (g.topics != null) {
            for (OhmDTO.TopicNode t : g.topics) {
                if (t == null) { continue; }
                Integer total = TokenEstimator.approxTokens(
                    concat(t.scope, t.description, null)
                );
                addIfBloated(out, total, c.topicScopeSoftTokens(), 'Topic', t.developerName, t.masterLabel, t.id);
            }
        }
        // Agents
        if (g.agentsById != null) {
            for (OhmDTO.AgentNode a : g.agentsById.values()) {
                if (a == null) { continue; }
                Integer total = TokenEstimator.approxTokens(
                    concat(a.description, a.capabilities, null)
                );
                addIfBloated(out, total, c.agentSoftTokens(), 'Agent', a.developerName, a.masterLabel, a.id);
            }
        }
        // Actions
        if (g.actions != null) {
            for (OhmDTO.ActionNode a : g.actions) {
                if (a == null) { continue; }
                Integer total = TokenEstimator.approxTokens(
                    concat(a.description, null, null)
                );
                addIfBloated(out, total, c.actionSoftTokens(), 'Action', a.developerName, a.masterLabel, a.id);
            }
        }
        return out;
    }

    private void addIfBloated(
        List<OhmDTO.Finding> out, Integer total, Integer soft,
        String artifactType, String apiName, String label, String toolingId
    ) {
        if (total == null || total <= soft) {
            return; // strict '> soft'
        }
        Integer excess = total - soft;
        Decimal score = min1(((Decimal) excess) / ((Decimal) soft));
        OhmDTO.Finding f = new OhmDTO.Finding();
        f.signalType = SIGNAL;
        f.severityScore = score;
        f.severity = OhmSeverity.band(score);
        f.confidence = 'High';
        f.artifactType = artifactType;
        f.artifactApiName = apiName;
        f.artifactLabel = label;
        f.artifactToolingId = toolingId;
        f.metricValue = excess;                 // C9 — EXCESS over soft, not total
        f.metricUnit = 'tokens';
        f.evidence = 'Instruction block ≈ ' + total + ' tokens vs soft budget ' + soft +
            ' (excess ' + excess + '). Trimming to budget removes recurring per-turn token cost.';
        out.add(f);
    }

    private String concat(String a, String b, String cc) {
        String s = '';
        if (String.isNotBlank(a)) { s += a; }
        if (String.isNotBlank(b)) { s += ' ' + b; }
        if (String.isNotBlank(cc)) { s += ' ' + cc; }
        return s;
    }

    private Decimal min1(Decimal v) {
        return (v > 1) ? 1 : v;
    }
}
