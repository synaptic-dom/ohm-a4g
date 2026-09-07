@IsTest
private class OhmReviewTemplateTest {
    private class FakeGateway extends OhmReviewTemplate.Gateway {
        Integer calls = 0;
        String templateName;
        ConnectApi.EinsteinPromptTemplateGenerationsInput capturedInput;
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response;
        Boolean shouldFail = false;

        public override ConnectApi.EinsteinPromptTemplateGenerationsRepresentation invoke(
            String name, ConnectApi.EinsteinPromptTemplateGenerationsInput input
        ) {
            calls++;
            templateName = name;
            capturedInput = input;
            if (shouldFail) { throw new OhmReviewTemplate.ReviewTemplateException('PRIVATE_SOURCE_IN_PROVIDER_ERROR'); }
            return response;
        }
    }

    private static FakeGateway install(List<String> responses) {
        FakeGateway fake = new FakeGateway();
        if (responses != null) {
            fake.response = new ConnectApi.EinsteinPromptTemplateGenerationsRepresentation();
            fake.response.generations = new List<ConnectApi.EinsteinLLMGenerationItemOutput>();
            for (String text : responses) {
                ConnectApi.EinsteinLLMGenerationItemOutput item = new ConnectApi.EinsteinLLMGenerationItemOutput();
                item.text = text;
                fake.response.generations.add(item);
            }
        }
        OhmReviewTemplate.gateway = fake;
        return fake;
    }

    @IsTest static void invokesPublishedFlexTemplateWithExactEvidence() {
        String evidence = '{"schemaVersion":1,"artifacts":[{"instructions":"Preserve whitespace.\\n"}]}';
        String raw = '  {"schemaVersion":1,"artifacts":[],"categories":[]}\n';
        FakeGateway fake = install(new List<String>{raw});
        System.assertEquals(raw, OhmReviewTemplate.generate(evidence), 'The adapter must not repair or truncate model output.');
        System.assertEquals(1, fake.calls);
        System.assertEquals('Ohm_Bundle_Environmental_Review', fake.templateName);
        System.assertEquals(false, fake.capturedInput.isPreview, 'A review must generate a response, not just resolve the template.');
        System.assertEquals(new Set<String>{'Input:evidenceJson'}, fake.capturedInput.inputParams.keySet());
        System.assertEquals(evidence, fake.capturedInput.inputParams.get('Input:evidenceJson').value);
        System.assertEquals('PromptBuilderPreview', fake.capturedInput.additionalConfig.applicationName);
        System.assertEquals(1, fake.capturedInput.additionalConfig.numGenerations);
        System.assertEquals(null, fake.capturedInput.additionalConfig.temperature,
            'Use the configured model default; reasoning models need not support temperature overrides.');
    }

    @IsTest static void rejectsEmptyMalformedAndOversizedEvidenceBeforeGeneration() {
        FakeGateway fake = install(new List<String>{'{}'});
        for (String evidence : new List<String>{null, ' ', '[]', '{PRIVATE_EVIDENCE',
            '{"source":"' + 'x'.repeat(OhmReviewTemplate.MAX_EVIDENCE_CHARS) + '"}'}) {
            try {
                OhmReviewTemplate.generate(evidence);
                System.assert(false, 'Invalid evidence must not be submitted.');
            } catch (OhmReviewTemplate.ReviewTemplateException ex) {
                System.assert(!ex.getMessage().contains('PRIVATE_EVIDENCE'));
            }
        }
        System.assertEquals(0, fake.calls);
    }

    @IsTest static void failsClosedOnMissingOrAmbiguousGenerations() {
        for (List<String> responses : new List<List<String>>{null, new List<String>(),
            new List<String>{' '}, new List<String>{'{}', '{}'}}) {
            FakeGateway fake = install(responses);
            try {
                OhmReviewTemplate.generate('{}');
                System.assert(false, 'Absent or multiple responses must fail.');
            } catch (OhmReviewTemplate.ReviewTemplateException ex) {
                System.assert(ex.getMessage().contains('exactly one nonempty response'));
            }
            System.assertEquals(1, fake.calls);
        }
    }

    @IsTest static void rejectsOversizedResponseWithoutTruncation() {
        install(new List<String>{'x'.repeat(OhmReviewTemplate.MAX_RESPONSE_CHARS + 1)});
        try {
            OhmReviewTemplate.generate('{}');
            System.assert(false, 'An oversized review cannot be truncated into a partial review.');
        } catch (OhmReviewTemplate.ReviewTemplateException ex) {
            System.assert(ex.getMessage().contains('response size'));
        }
    }

    @IsTest static void sanitizesProviderFailureWithoutFallback() {
        FakeGateway fake = install(null);
        fake.shouldFail = true;
        try {
            OhmReviewTemplate.generate('{}');
            System.assert(false, 'Provider failures must remain failures.');
        } catch (OhmReviewTemplate.ReviewTemplateException ex) {
            System.assert(ex.getMessage().contains('Salesforce prompt review could not run'));
            System.assert(!ex.getMessage().contains('PRIVATE_SOURCE'));
        }
        System.assertEquals(1, fake.calls, 'No automatic second model call or alternate provider is allowed.');
    }
}
