/**
 * OhmSignalService — orchestrates the four detectors and grades efficiency (SPEC §S.6, canon C8).
 * analyze(AgentModel) : List<Finding> — runs all four detectors, concatenates, severity via OhmSeverity.
 * rate(AgentModel, List<Finding>) : EfficiencyResult — weighted-severity score → letter grade.
 */
public with sharing class OhmSignalService {

    /** Run the four signal detectors and concatenate their findings. */
    public List<OhmDTO.Finding> analyze(OhmDTO.AgentModel g) {
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>();
        if (g == null) {
            return findings;
        }
        List<SignalDetector> detectors = new List<SignalDetector>{
            new LlmWhereDeterministicDetector(),
            new ModelRightSizingDetector(),
            new InstructionBloatDetector(),
            new RedundantCallDetector()
        };
        for (SignalDetector d : detectors) {
            try {
                List<OhmDTO.Finding> part = d.detect(g);
                if (part != null) {
                    findings.addAll(part);
                }
            } catch (Exception e) {
                // best-effort: a detector failure must not sink the run
                if (g.discoveryErrors == null) {
                    g.discoveryErrors = new List<String>();
                }
                g.discoveryErrors.add('Detector error: ' + e.getMessage());
            }
        }
        // ensure severity band is set (single C7 mapping)
        for (OhmDTO.Finding f : findings) {
            if (f.severity == null && f.severityScore != null) {
                f.severity = OhmSeverity.band(f.severityScore);
            }
        }
        return findings;
    }

    /**
     * Grade org efficiency (C8).
     * score = round(100 × (1 − Σ(signalWeight × severityScore) / maxPossible)).
     * No findings => 100 / A. Letter cutoffs A≥90 B≥80 C≥70 D≥60 F<60.
     */
    public OhmDTO.EfficiencyResult rate(OhmDTO.AgentModel g, List<OhmDTO.Finding> findings) {
        OhmConstants c = OhmConstants.load();
        OhmDTO.EfficiencyResult r = new OhmDTO.EfficiencyResult();
        r.weightedSeveritySum = 0;
        r.maxPossible = 0;
        r.deterministicActionCount = countDeterministicActions(g);
        r.withinBudgetInstructionCount = 0;

        if (findings != null) {
            for (OhmDTO.Finding f : findings) {
                if (f.reviewRequired == true) { continue; }
                Decimal w = c.signalWeight(f.signalType);
                Decimal s = (f.severityScore == null) ? 0 : f.severityScore;
                r.weightedSeveritySum += w * s;
                r.maxPossible += w; // max severity = 1.0
            }
        }

        Integer score;
        if (r.maxPossible == null || r.maxPossible == 0) {
            score = 100; // clean org
        } else {
            Decimal ratio = r.weightedSeveritySum / r.maxPossible;
            score = (Integer) Math.round(100 * (1 - ratio));
        }
        if (score < 0) { score = 0; }
        if (score > 100) { score = 100; }
        Boolean complete = g != null && g.coverageComplete == true
            && (g.discoveryErrors == null || g.discoveryErrors.isEmpty());
        r.coverageStatus = complete ? 'Complete' : 'Incomplete';
        r.score = complete ? score : null;
        r.grade = complete ? letterFor(score, c.gradeCutoffs()) : 'IN';
        return r;
    }

    private String letterFor(Integer score, Map<String, Integer> cutoffs) {
        if (score >= cutoffs.get('A')) { return 'A'; }
        if (score >= cutoffs.get('B')) { return 'B'; }
        if (score >= cutoffs.get('C')) { return 'C'; }
        if (score >= cutoffs.get('D')) { return 'D'; }
        return 'F';
    }

    private Integer countDeterministicActions(OhmDTO.AgentModel g) {
        Integer n = 0;
        if (g != null && g.actions != null) {
            for (OhmDTO.ActionNode a : g.actions) {
                if (a == null) { continue; }
                String t = (a.invocationTargetType == null) ? '' : a.invocationTargetType.toLowerCase();
                if (t == 'apex' || t == 'flow') { n++; }
            }
        }
        return n;
    }
}
