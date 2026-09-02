@IsTest
private class OhmConstantsTest {
    @IsTest
    static void test_happyOrFallback_values() {
        // With or without the deployed resource, cited defaults guarantee these canon values.
        OhmConstants c = OhmConstants.load();
        System.assertEquals(0.27, c.energyPerPromptWh('central'), 'central energy 0.27');
        System.assertEquals(0.24, c.energyPerPromptWh('low'), 'low energy 0.24');
        System.assertEquals(0.30, c.energyPerPromptWh('high'), 'high energy 0.30');
        System.assertEquals(500, c.topicScopeSoftTokens(), 'topic soft 500');
        System.assertEquals(1000, c.topicScopeHardTokens(), 'topic hard 1000');
        System.assertEquals(2.0, c.rateCardMultiplier('LARGE'), 'LARGE 2.0');
        System.assertEquals(1.0, c.rateCardMultiplier('MEDIUM'), 'MEDIUM 1.0');
        System.assertEquals(0.5, c.rateCardMultiplier('SMALL'), 'SMALL 0.5');
        System.assertEquals(500, c.referencePromptTokens(), 'reference tokens 500');
    }

    @IsTest
    static void test_bands() {
        OhmConstants c = OhmConstants.load();
        OhmConstants.Band grid = c.gridIntensityGco2ePerWh();
        System.assertEquals(0.30, grid.central, 'grid central 0.30');
        OhmConstants.Band water = c.waterMlPerWh();
        System.assertEquals(1.08, water.central, 'water central 1.08');
    }

    @IsTest
    static void test_unknownModelBaseline() {
        OhmConstants c = OhmConstants.load();
        System.assertEquals(1.0, c.rateCardMultiplier('no-such-model'), 'unknown -> baseline 1.0');
    }

    @IsTest
    static void test_parseOrDefault_fallbacks() {
        OhmConstants nullC = OhmConstants.parseOrDefault(null);
        System.assertEquals(0.27, nullC.energyPerPromptWh('central'), 'null json -> default');
        System.assert(!nullC.fallbackNotes.isEmpty(), 'null json records a fallback note');

        OhmConstants badC = OhmConstants.parseOrDefault('{ not json');
        System.assertEquals(500, badC.topicScopeSoftTokens(), 'bad json -> default');
        System.assert(!badC.fallbackNotes.isEmpty(), 'bad json records a fallback note');
    }

    @IsTest
    static void test_partialJson_perKeyFallback() {
        String partial = '{ "footprint": { "energyPerPromptWh": { "central": 0.99 } } }';
        OhmConstants c = OhmConstants.parseOrDefault(partial);
        System.assertEquals(0.99, c.energyPerPromptWh('central'), 'overridden key wins');
        System.assertEquals(0.24, c.energyPerPromptWh('low'), 'missing key falls back');
        System.assertEquals(500, c.topicScopeSoftTokens(), 'missing section falls back, no NPE');
    }

    @IsTest
    static void test_defaultVolume() {
        OhmDTO.VolumeInput v = OhmConstants.load().defaultVolume();
        System.assertEquals(50, v.sessionsPerPeriod);
        System.assertEquals(6, v.turnsPerSession);
        System.assertEquals(1, v.callsPerTurn);
        System.assertEquals(365, v.periodsPerYear);
    }

    @IsTest
    static void test_signalWeightsAndGrades() {
        OhmConstants c = OhmConstants.load();
        System.assertEquals(1.0, c.signalWeight('LLM_WHERE_DETERMINISTIC'));
        System.assertEquals(0.7, c.signalWeight('MODEL_RIGHTSIZING'));
        System.assertEquals(0.5, c.signalWeight('INSTRUCTION_BLOAT'));
        System.assertEquals(0.8, c.signalWeight('REDUNDANT_CALLS'));
        Map<String, Integer> cut = c.gradeCutoffs();
        System.assertEquals(90, cut.get('A'));
        System.assertEquals(60, cut.get('D'));
    }
}
