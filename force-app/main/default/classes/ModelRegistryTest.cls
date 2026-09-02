@IsTest
private class ModelRegistryTest {
    @IsTest
    static void test_knownTiers() {
        ModelRegistry.ModelInfo large = ModelRegistry.lookup('LARGE');
        System.assertEquals('LARGE', large.tier);
        System.assertEquals(3, large.rank);
        System.assertEquals(2.0, large.rateCardMultiplier, 'LARGE multiplier 2.0');
        System.assertEquals(false, large.assumed, 'known tier not assumed');

        ModelRegistry.ModelInfo small = ModelRegistry.lookup('SMALL');
        System.assertEquals(0.5, small.rateCardMultiplier, 'SMALL multiplier 0.5');
        System.assertEquals(1, small.rank);
    }

    @IsTest
    static void test_knownModelName() {
        ModelRegistry.ModelInfo m = ModelRegistry.lookup('sfdc_ai__DefaultGPT4Omni');
        System.assertEquals('LARGE', m.tier, 'GPT4 Omni maps to LARGE');
        System.assertEquals(2.0, m.rateCardMultiplier);
    }

    @IsTest
    static void test_unknownModelBaseline() {
        ModelRegistry.ModelInfo m = ModelRegistry.lookup('totally-unknown-model');
        System.assertEquals('MEDIUM', m.tier, 'unknown -> baseline MEDIUM');
        System.assertEquals(1.0, m.rateCardMultiplier, 'baseline multiplier 1.0');
        System.assertEquals(true, m.assumed, 'unknown -> assumed true');
    }

    @IsTest
    static void test_recommendedFor() {
        System.assertEquals('SMALL', ModelRegistry.recommendedFor(ModelRegistry.TaskComplexity.TRIVIAL).tier);
        System.assertEquals('MEDIUM', ModelRegistry.recommendedFor(ModelRegistry.TaskComplexity.MODERATE).tier);
        System.assertEquals('LARGE', ModelRegistry.recommendedFor(ModelRegistry.TaskComplexity.COMPLEX).tier);
    }
}
