/**
 * Signal (a) LLM_WHERE_DETERMINISTIC — CONFIRMED, protected (SPEC §S.6a, canon C7a).
 * For each prompt-typed action, classify intent against the deterministic lexicon.
 * Fire when hitCount >= 1. score = min(1, 0.4 + 0.15 × hitCount). Confidence = Medium.
 * flow/apex actions are never flagged. Savings = full per-inference footprint (call removed).
 */
public with sharing class LlmWhereDeterministicDetector implements SignalDetector {

    public static final String SIGNAL = 'LLM_WHERE_DETERMINISTIC';

    // deterministic-work lexicon
    private static final List<String> LEXICON = new List<String>{
        'classify', 'categorize', 'categorise', 'route', 'lookup', 'look up',
        'format', 'validate', 'extract', 'parse', 'calculate', 'boolean',
        'yes-no', 'yes/no', 'yes or no'
    };

    public List<OhmDTO.Finding> detect(OhmDTO.AgentModel g) {
        List<OhmDTO.Finding> out = new List<OhmDTO.Finding>();
        if (g == null || g.actions == null) {
            return out;
        }
        for (OhmDTO.ActionNode a : g.actions) {
            if (a == null) {
                continue;
            }
            String targetType = (a.invocationTargetType == null) ? '' : a.invocationTargetType.toLowerCase();
            if (targetType != 'prompt') {
                continue; // flow/apex never flagged
            }
            Integer hits = countHits(a);
            if (hits < 1) {
                continue;
            }
            Decimal score = min1(0.4 + 0.15 * hits);
            OhmDTO.Finding f = new OhmDTO.Finding();
            f.signalType = SIGNAL;
            f.severityScore = score;
            f.severity = OhmSeverity.band(score);
            f.confidence = 'Medium';
            f.artifactType = 'Action';
            f.artifactApiName = a.developerName;
            f.artifactLabel = a.masterLabel;
            f.artifactToolingId = a.id;
            f.parentTopicApiName = null;
            f.metricValue = hits;
            f.metricUnit = 'lexicon-hits';
            f.evidence = 'Prompt-typed action performs deterministic work (' + hits +
                ' lexicon hit' + (hits == 1 ? '' : 's') + '): a rule/flow/apex path would be exact and token-free.';
            out.add(f);
        }
        return out;
    }

    private Integer countHits(OhmDTO.ActionNode a) {
        String text = ((a.masterLabel == null ? '' : a.masterLabel) + ' ' +
                       (a.developerName == null ? '' : a.developerName) + ' ' +
                       (a.description == null ? '' : a.description)).toLowerCase();
        Integer hits = 0;
        for (String term : LEXICON) {
            if (text.contains(term)) {
                hits++;
            }
        }
        return hits;
    }

    private Decimal min1(Decimal v) {
        return (v > 1) ? 1 : v;
    }
}
