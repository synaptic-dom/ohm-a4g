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
            f.recommendationText = 'This action performs deterministic work an LLM does not need to do. ' +
                'Replace the prompt call with a Flow (or Apex) that returns the exact result — removing the ' +
                'per-turn inference entirely.';

        } else if (f.signalType == ModelRightSizingDetector.SIGNAL) {
            f.fixType = 'Downsize_Model';
            if (String.isBlank(f.recommendedTarget)) {
                f.recommendedTarget = ModelRegistry.recommendedFor(ModelRegistry.TaskComplexity.TRIVIAL).tier;
            }
            f.effort = 'Low';
            f.recommendationText = 'The bound model is larger than this task requires. Re-point the action to a ' +
                f.recommendedTarget + '-tier model, which covers the work at a lower per-inference cost.';

        } else if (f.signalType == InstructionBloatDetector.SIGNAL) {
            f.fixType = 'Trim_Instructions';
            Integer soft = c.softThresholdFor(f.artifactType);
            f.recommendedTarget = soft + ' tokens';
            f.effort = 'Low';
            f.recommendationText = 'The instruction block exceeds its token budget. Trim it to ≈ ' + soft +
                ' tokens; the removed tokens are re-sent every turn, so the saving recurs across the run.';

        } else if (f.signalType == RedundantCallDetector.SIGNAL) {
            f.fixType = 'Consolidate_Calls';
            if (String.isBlank(f.recommendedTarget)) {
                f.recommendedTarget = 'Single consolidated call per turn';
            }
            f.effort = 'Medium';
            f.recommendationText = 'The agent makes more prompt calls per turn than the task requires. ' +
                'Consolidate the redundant calls into one, eliminating the extra inferences each turn.';
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
