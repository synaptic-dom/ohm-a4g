/**
 * OhmRecommendationServiceTest — signal → fix mapping (T.3.9, canon C2 fix types).
 */
@IsTest
private class OhmRecommendationServiceTest {

    static OhmDTO.Finding finding(String signal, String artifactType, Decimal metric, String recTarget) {
        OhmDTO.Finding f = new OhmDTO.Finding();
        f.signalType = signal; f.artifactType = artifactType;
        f.metricValue = metric; f.recommendedTarget = recTarget;
        if (signal == 'MODEL_RIGHTSIZING' && metric == 2.0) { f.boundModel = 'LARGE'; }
        return f;
    }

    @IsTest
    static void test_llmWhereDeterministic() {
        OhmDTO.Finding f = new OhmRecommendationService().attachRecommendation(
            finding('LLM_WHERE_DETERMINISTIC', 'Action', 1, null));
        System.assertEquals('Replace_With_Flow', f.fixType);
        System.assertEquals('Medium', f.effort);
        System.assertEquals('Deterministic', f.generatedBy);
        System.assert(String.isNotBlank(f.recommendationText), 'text present');
        System.assertEquals(null, f.savings, 'lexical metadata does not establish removable work');
        System.assert(f.recommendationText.contains('compare outputs'), 'requires behavioral validation');
        System.assert(!f.recommendationText.contains('exact result'), 'no equivalence claim');
    }

    @IsTest
    static void test_modelRightsizing() {
        OhmDTO.Finding f = new OhmRecommendationService().attachRecommendation(
            finding('MODEL_RIGHTSIZING', 'Action', 2.0, 'SMALL'));
        System.assertEquals('Downsize_Model', f.fixType);
        System.assertEquals('SMALL', f.recommendedTarget, 'preserves detector target');
        System.assertEquals('Low', f.effort);
        System.assertEquals('Deterministic', f.generatedBy);
        System.assert(f.savings.energyWhCentral > 0, 'conditional modeled scenario with known tiers');
        System.assert(f.recommendationText.contains('conditional'), 'not a guaranteed reduction');
    }

    @IsTest
    static void test_instructionBloat() {
        OhmDTO.Finding f = new OhmRecommendationService().attachRecommendation(
            finding('INSTRUCTION_BLOAT', 'Topic', 800, null));
        System.assertEquals('Trim_Instructions', f.fixType);
        System.assertEquals('500 tokens', f.recommendedTarget, 'token budget target');
        System.assertEquals('Low', f.effort);
        System.assert(f.savings.energyWhCentral > 0, 'positive savings');
    }

    @IsTest
    static void test_redundantCalls() {
        OhmDTO.Finding f = new OhmRecommendationService().attachRecommendation(
            finding('REDUNDANT_CALLS', 'Agent', 2, null));
        System.assertEquals('Consolidate_Calls', f.fixType);
        System.assertEquals('Medium', f.effort);
        System.assertEquals(null, f.savings, 'static repetition is not proof calls can be removed');
    }

    @IsTest
    static void test_nullFinding_safe() {
        System.assertEquals(null, new OhmRecommendationService().attachRecommendation(null), 'null returns null');
        System.assertEquals(null, new OhmRecommendationService().attachRecommendations(null), 'null list returns null');
    }

    @IsTest
    static void test_modelRightsizing_blankTarget_doesNotInventTarget() {
        OhmDTO.Finding f = new OhmRecommendationService().attachRecommendation(
            finding('MODEL_RIGHTSIZING', 'Action', 2.0, null));
        System.assertEquals(null, f.fixType);
        System.assertEquals(null, f.recommendedTarget, 'missing recommendation evidence stays unknown');
        System.assertEquals(null, f.savings);
    }

    @IsTest
    static void test_unknownModelCannotBeDownsizedFromAMultiplier() {
        OhmDTO.Finding candidate = finding('MODEL_RIGHTSIZING', 'Action', 2.0, 'SMALL');
        candidate.boundModel = 'unmapped-provider-model';
        OhmDTO.Finding f = new OhmRecommendationService().attachRecommendation(candidate);
        System.assertEquals(null, f.fixType);
        System.assertEquals(null, f.recommendedTarget);
        System.assertEquals(null, f.savings);
    }

    @IsTest
    static void test_redundant_blankTarget_derivesDefault() {
        OhmDTO.Finding f = new OhmRecommendationService().attachRecommendation(
            finding('REDUNDANT_CALLS', 'Agent', 1, null));
        System.assertEquals('Consolidate_Calls', f.fixType);
        System.assert(String.isNotBlank(f.recommendedTarget), 'derives a default consolidation target');
    }

    @IsTest
    static void test_bulk() {
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>{
            finding('LLM_WHERE_DETERMINISTIC', 'Action', 1, null),
            finding('INSTRUCTION_BLOAT', 'Topic', 800, null)
        };
        List<OhmDTO.Finding> out = new OhmRecommendationService().attachRecommendations(findings);
        System.assertEquals(2, out.size());
        System.assertEquals('Replace_With_Flow', out[0].fixType);
        System.assertEquals('Trim_Instructions', out[1].fixType);
    }
}
