/**
 * Signal (c) INSTRUCTION_BLOAT — CONFIRMED, protected (SPEC §S.6c, canon C9).
 * totalTokens = approxTokens(authoritative instructions). Fire strictly > soft.
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
                    String.isNotBlank(t.instructions) ? t.instructions : t.scope);
                addIfBloated(out, total, c.topicScopeSoftTokens(), 'Topic', t.developerName, t.masterLabel, t.id);
            }
        }
        // Agents
        if (g.agentsById != null) {
            for (OhmDTO.AgentNode a : g.agentsById.values()) {
                if (a == null) { continue; }
                Integer total = TokenEstimator.approxTokens(a.instructions);
                addIfBloated(out, total, c.agentSoftTokens(), 'Agent', a.developerName, a.masterLabel, a.id);
            }
        }
        // Actions
        if (g.actions != null) {
            for (OhmDTO.ActionNode a : g.actions) {
                if (a == null) { continue; }
                Integer total = TokenEstimator.approxTokens(a.instructions);
                Integer beforeCount = out.size();
                addIfBloated(out, total, c.actionSoftTokens(), 'Action', a.developerName, a.masterLabel, a.id);
                if (out.size() > beforeCount) { out[out.size() - 1].boundModel = a.boundModel; }
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
            ' (excess ' + excess + '). Review a shorter version that preserves required behavior. ' +
            'Any modeled reduction assumes this instruction input is sent at the stated usage volume.';
        out.add(f);
    }

    private Decimal min1(Decimal v) {
        return (v > 1) ? 1 : v;
    }
}
