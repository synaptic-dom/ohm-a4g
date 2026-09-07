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
    static void test_specificSmallVariantsWinOverFamily() {
        for (String apiName : new List<String>{
            'sfdc_ai__DefaultOpenAIGPT4OmniMini', 'sfdc_ai__DefaultGPT4OmniMini',
            'SFDC_AI__DEFAULTOPENAIGPT4OMNIMINI', 'sfdc_ai__defaultgpt4omnimini',
            'gpt-4o-mini', 'gpt-4.1-nano', ' small '
        }) {
            ModelRegistry.ModelInfo model = ModelRegistry.lookup(apiName);
            System.assertEquals('SMALL', model.tier, apiName);
            System.assertEquals(false, model.assumed, apiName);
            System.assertEquals(0.5, model.rateCardMultiplier, apiName);
        }
    }

    @IsTest
    static void test_unknownModelBaseline() {
        ModelRegistry.ModelInfo m = ModelRegistry.lookup('totally-unknown-model');
        System.assertEquals('MEDIUM', m.tier, 'unknown -> baseline MEDIUM');
        System.assertEquals(1.0, m.rateCardMultiplier, 'baseline multiplier 1.0');
        System.assertEquals(true, m.assumed, 'unknown -> assumed true');
    }

    @IsTest
    static void test_embeddedSizeWordsAreNotModelEvidence() {
        for (String name : new List<String>{ 'unmapped-provider-model', 'administer-v2', 'ultrasonic-engine' }) {
            System.assertEquals(true, ModelRegistry.lookup(name).assumed,
                'embedded PRO/MINI/ULTRA substrings do not establish a model family: ' + name);
        }
        System.assertEquals('MEDIUM', ModelRegistry.lookup('GeminiPro').tier, 'CamelCase model variant remains supported');
        System.assertEquals('MEDIUM', ModelRegistry.lookup('GEMINIPRO').tier, 'known family suffix remains supported');
    }

    @IsTest
    static void test_recommendedFor() {
        System.assertEquals('SMALL', ModelRegistry.recommendedFor(ModelRegistry.TaskComplexity.TRIVIAL).tier);
        System.assertEquals('MEDIUM', ModelRegistry.recommendedFor(ModelRegistry.TaskComplexity.MODERATE).tier);
        System.assertEquals('LARGE', ModelRegistry.recommendedFor(ModelRegistry.TaskComplexity.COMPLEX).tier);
    }
}
