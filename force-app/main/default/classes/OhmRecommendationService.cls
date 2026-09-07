/**
 * OhmRecommendationService — deterministic fix candidates (SPEC §S.8, canon C2 fix types).
 * Maps signalType → {fixType, recommendedTarget, recommendationText, effort}, fills savings
 * via OhmFootprintService.savingsFor, sets generatedBy='Deterministic'.
 */
public with sharing class OhmRecommendationService {

    private final OhmFootprintService footprint = new OhmFootprintService();
    private final VolumeProvider volume = new AssumptionVolumeProvider();

    public OhmDTO.Finding attachRecommendation(OhmDTO.Finding f) {
        if (f == null) {
            return f;
        }
        OhmConstants c = OhmConstants.load();
        f.generatedBy = 'Deterministic';

        if (f.signalType == LlmWhereDeterministicDetector.SIGNAL) {
            f.fixType = 'Replace_With_Flow';
            if (String.isBlank(f.recommendedTarget)) {
                f.recommendedTarget = 'Flow or Apex rule';
            }
            f.effort = 'Medium';
            f.recommendationText = 'Review a Flow or Apex alternative for this prompt action. Specify the ' +
                'rules, allowed inputs and edge cases, then compare outputs before replacing it. ' +
                'The metadata does not prove equivalent behavior; savings are withheld until validated.';

        } else if (f.signalType == ModelRightSizingDetector.SIGNAL) {
            if (f.reviewRequired == true || f.metricValue == null || String.isBlank(f.boundModel) ||
                ModelRegistry.lookup(f.boundModel).assumed || String.isBlank(f.recommendedTarget) ||
                ModelRegistry.lookup(f.recommendedTarget).assumed) {
                f.fixType = null;
                f.recommendedTarget = null;
                f.effort = 'Low';
                f.recommendationText = 'Retrieve the current prompt model and evaluate task requirements ' +
                    'before recommending a different tier. Model reduction and savings are unavailable.';
                f.savings = null;
                return f;
            }
            f.fixType = 'Downsize_Model';
            f.effort = 'Low';
            f.recommendationText = 'Evaluate a ' + f.recommendedTarget +
                '-tier model with representative inputs, quality checks and edge cases. Any displayed ' +
                'reduction is a modeled scenario, conditional on that model meeting the task requirements.';

        } else if (f.signalType == InstructionBloatDetector.SIGNAL) {
            f.fixType = 'Trim_Instructions';
            Integer soft = c.softThresholdFor(f.artifactType);
            f.recommendedTarget = soft + ' tokens';
            f.effort = 'Low';
            f.recommendationText = 'The instruction block exceeds the review budget of approximately ' +
                soft + ' tokens. Propose a shorter version, preserve required rules and action branches, ' +
                'then validate behavior. The displayed reduction models a trim to that budget at the stated usage volume.';

        } else if (f.signalType == RedundantCallDetector.SIGNAL) {
            f.fixType = 'Consolidate_Calls';
            if (String.isBlank(f.recommendedTarget)) {
                f.recommendedTarget = 'Review repeated prompt paths';
            }
            f.effort = 'Medium';
            f.recommendationText = 'Inspect the repeated prompt target or loop with representative ' +
                'execution traces. Preserve calls that use changed inputs or serve distinct steps. ' +
                'Metadata does not establish removable calls, so savings are withheld.';
        }

        if (f.signalType == LlmWhereDeterministicDetector.SIGNAL ||
            f.signalType == RedundantCallDetector.SIGNAL) {
            f.savings = null;
            return f;
        }

        // fill savings via the single savings path
        try {
            f.savings = footprint.savingsFor(f, volume.defaultVolume());
        } catch (Exception e) {
            f.savings = null;
        }
        return f;
    }

    public List<OhmDTO.Finding> attachRecommendations(List<OhmDTO.Finding> findings) {
        if (findings == null) {
            return findings;
        }
        for (OhmDTO.Finding f : findings) {
            attachRecommendation(f);
        }
        return findings;
    }
}
