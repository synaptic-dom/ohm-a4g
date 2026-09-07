/**
 * Signal (a) LLM_WHERE_DETERMINISTIC — metadata-based review candidate.
 * Whole-word intent matches suggest a place to investigate a rule-based alternative.
 * They do not establish equivalence, removable calls, or savings. Confidence = Low.
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
            if (!OhmActionTypes.isPrompt(a.invocationTargetType)) {
                continue; // flow/apex/standardInvocableAction/etc. never flagged
            }
            Integer hits = countHits(a);
            if (hits < 1) {
                continue;
            }
            Decimal score = min1(0.4 + 0.15 * hits);
            OhmDTO.Finding f = new OhmDTO.Finding();
            f.signalType = SIGNAL;
            f.reviewRequired = true;
            f.boundModel = a.boundModel;
            f.severityScore = score;
            f.severity = OhmSeverity.band(score);
            f.confidence = 'Low';
            f.artifactType = 'Action';
            f.artifactApiName = a.developerName;
            f.artifactLabel = a.masterLabel;
            f.artifactToolingId = a.id;
            f.parentTopicApiName = null;
            f.metricValue = hits;
            f.metricUnit = 'lexicon-hits';
            f.evidence = 'Prompt action metadata contains ' + hits +
                ' whole-word intent match' + (hits == 1 ? '' : 'es') +
                '. Review whether explicit rules can cover the inputs and edge cases. ' +
                'Metadata alone does not establish an equivalent replacement or removable inference.';
            out.add(f);
        }
        return out;
    }

    private Integer countHits(OhmDTO.ActionNode a) {
        String text = OhmIntentEvidence.actionText(a);
        Integer hits = 0;
        for (String term : LEXICON) {
            if (OhmIntentEvidence.containsTerm(text, term)) {
                hits++;
            }
        }
        return hits;
    }

    private Decimal min1(Decimal v) {
        return (v > 1) ? 1 : v;
    }
}
