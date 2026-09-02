/**
 * Signal (b) MODEL_RIGHTSIZING — best-effort (SPEC §S.6b, canon C7b).
 * Uses action.boundModel (never fetches — closes S1/S2 circularity).
 *  - boundModel null => informational finding, zero savings, evidence='model unknown', Confidence=Low.
 *  - else overshoot = rank(bound) - rank(taskComplexity); fire when overshoot >= 1;
 *    score = min(1, overshoot/2); Confidence = Medium (Low when modelAssumed).
 * Metric_Value = bound rate-card multiplier, Metric_Unit = 'model-multiplier',
 * Recommended_Target = recommended tier name. Never performs a callout.
 */
public with sharing class ModelRightSizingDetector implements SignalDetector {

    public static final String SIGNAL = 'MODEL_RIGHTSIZING';

    // triviality lexicon (a trivial task should ride a SMALL model)
    private static final List<String> TRIVIAL_LEXICON = new List<String>{
        'classify', 'categorize', 'categorise', 'route', 'lookup', 'look up',
        'format', 'validate', 'boolean', 'yes-no', 'yes/no', 'yes or no', 'flag', 'tag'
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
                continue; // only prompt-typed actions burn model tokens
            }

            if (String.isBlank(a.boundModel)) {
                // degrade — informational, no savings
                OhmDTO.Finding f = baseFinding(a);
                f.severityScore = 0;
                f.severity = OhmSeverity.band(0);
                f.confidence = 'Low';
                f.metricValue = null;
                f.metricUnit = 'model-multiplier';
                f.evidence = 'model unknown';
                out.add(f);
                continue;
            }

            ModelRegistry.ModelInfo bound = ModelRegistry.lookup(a.boundModel);
            ModelRegistry.TaskComplexity complexity = classifyComplexity(a);
            Integer complexityRank = rankFor(complexity);
            Integer overshoot = bound.rank - complexityRank;
            if (overshoot < 1) {
                continue; // right-sized (or under-sized)
            }
            ModelRegistry.ModelInfo recommended = ModelRegistry.recommendedFor(complexity);
            Decimal score = min1(((Decimal) overshoot) / 2.0);
            OhmDTO.Finding f = baseFinding(a);
            f.severityScore = score;
            f.severity = OhmSeverity.band(score);
            f.confidence = (a.modelAssumed == true) ? 'Low' : 'Medium';
            f.metricValue = bound.rateCardMultiplier;   // bound multiplier (drives savingsFor)
            f.metricUnit = 'model-multiplier';
            f.recommendedTarget = recommended.tier;
            f.evidence = 'Bound model tier ' + bound.tier + ' (×' + bound.rateCardMultiplier +
                ') overshoots task by ' + overshoot + ' tier(s); ' + recommended.tier +
                ' (×' + recommended.rateCardMultiplier + ') covers the work.';
            out.add(f);
        }
        return out;
    }

    private OhmDTO.Finding baseFinding(OhmDTO.ActionNode a) {
        OhmDTO.Finding f = new OhmDTO.Finding();
        f.signalType = SIGNAL;
        f.artifactType = 'Action';
        f.artifactApiName = a.developerName;
        f.artifactLabel = a.masterLabel;
        f.artifactToolingId = a.id;
        return f;
    }

    private ModelRegistry.TaskComplexity classifyComplexity(OhmDTO.ActionNode a) {
        String text = ((a.masterLabel == null ? '' : a.masterLabel) + ' ' +
                       (a.developerName == null ? '' : a.developerName) + ' ' +
                       (a.description == null ? '' : a.description)).toLowerCase();
        for (String term : TRIVIAL_LEXICON) {
            if (text.contains(term)) {
                return ModelRegistry.TaskComplexity.TRIVIAL;
            }
        }
        return ModelRegistry.TaskComplexity.MODERATE;
    }

    private Integer rankFor(ModelRegistry.TaskComplexity c) {
        if (c == ModelRegistry.TaskComplexity.TRIVIAL || c == ModelRegistry.TaskComplexity.SIMPLE) {
            return 1;
        }
        if (c == ModelRegistry.TaskComplexity.MODERATE) {
            return 2;
        }
        return 3;
    }

    private Decimal min1(Decimal v) {
        return (v > 1) ? 1 : v;
    }
}
