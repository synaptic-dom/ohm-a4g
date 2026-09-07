/** Executes the published OHM review rubric through Salesforce Prompt Builder. */
public with sharing class OhmReviewTemplate {
    public static final String TEMPLATE_API_NAME = 'Ohm_Bundle_Environmental_Review';
    public static final String REVIEWER_MODEL = 'sfdc_ai__DefaultGPT55';
    public static final String RUBRIC_VERSION = 'OHM_ENVIRONMENTAL_REVIEW_V1';
    // Declared deployment identity; generation does not attest the org's active version.
    public static final String TEMPLATE_VERSION_IDENTIFIER = 'WCyeBTg2NZWRDVRViggPve0yyaQfI6t9+0AlEdZ1LCQ=_1';
    public static final String REVIEWER_VERSION = TEMPLATE_VERSION_IDENTIFIER;
    public static final Integer MAX_EVIDENCE_CHARS = 100000;
    public static final Integer MAX_RESPONSE_CHARS = 100000;

    public class ReviewTemplateException extends Exception {}

    /** The test seam substitutes transport only; production always invokes Prompt Builder. */
    public virtual class Gateway {
        public virtual ConnectApi.EinsteinPromptTemplateGenerationsRepresentation invoke(
            String templateName, ConnectApi.EinsteinPromptTemplateGenerationsInput input
        ) {
            return ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, input);
        }
    }
    @TestVisible private static Gateway gateway = new Gateway();

    /** Returns the original generation. The review service owns strict rubric validation. */
    public static String generate(String evidenceJson) {
        if (String.isBlank(evidenceJson) || evidenceJson.length() > MAX_EVIDENCE_CHARS) {
            throw new ReviewTemplateException('Review evidence is empty or exceeds the supported input size.');
        }
        try {
            if (!(JSON.deserializeUntyped(evidenceJson) instanceof Map<String, Object>)) {
                throw new ReviewTemplateException('Review evidence must be a JSON object.');
            }
        } catch (Exception ex) {
            throw new ReviewTemplateException('Review evidence must be a valid JSON object.');
        }

        ConnectApi.WrappedValue evidence = new ConnectApi.WrappedValue();
        evidence.value = evidenceJson;
        ConnectApi.EinsteinPromptTemplateGenerationsInput input =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{'Input:evidenceJson' => evidence};
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        // Salesforce requires a registered AI application name, not an arbitrary client label.
        input.additionalConfig.applicationName = 'PromptBuilderPreview';
        input.additionalConfig.numGenerations = 1;

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output;
        try {
            output = gateway.invoke(TEMPLATE_API_NAME, input);
        } catch (Exception ex) {
            // Provider exceptions may contain resolved source. Do not persist or expose their text.
            throw new ReviewTemplateException('Salesforce prompt review could not run. Check the active OHM review template and Execute Prompt Templates access, then retry.');
        }
        if (output == null || output.generations == null || output.generations.size() != 1
            || output.generations[0] == null || String.isBlank(output.generations[0].text)) {
            throw new ReviewTemplateException('Salesforce prompt review did not return exactly one nonempty response.');
        }
        String response = output.generations[0].text;
        if (response.length() > MAX_RESPONSE_CHARS) {
            throw new ReviewTemplateException('Salesforce prompt review exceeded the supported response size.');
        }
        return response;
    }
}
