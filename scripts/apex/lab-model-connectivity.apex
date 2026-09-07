// One real Models API request using the same model and message roles as Ask Ohm.
// Connectivity check only: does not establish grounded app behavior or execute actions.
try {
    aiplatform.ModelsAPI.createChatGenerations_Request request =
        new aiplatform.ModelsAPI.createChatGenerations_Request();
    request.modelName = 'sfdc_ai__DefaultGPT4OmniMini';
    aiplatform.ModelsAPI_ChatMessageRequest systemMessage = new aiplatform.ModelsAPI_ChatMessageRequest();
    systemMessage.role = 'system';
    systemMessage.content = 'Answer the user in one short sentence using only the provided workflow description.';
    aiplatform.ModelsAPI_ChatMessageRequest userMessage = new aiplatform.ModelsAPI_ChatMessageRequest();
    userMessage.role = 'user';
    userMessage.content = 'A public sample retrieves current weather and a forecast using Flow, and sends weather alerts using Apex. What kinds of actions does it use?';
    aiplatform.ModelsAPI_ChatGenerationsRequest body = new aiplatform.ModelsAPI_ChatGenerationsRequest();
    body.messages = new List<aiplatform.ModelsAPI_ChatMessageRequest>{systemMessage, userMessage};
    request.body = body;
    aiplatform.ModelsAPI api = new aiplatform.ModelsAPI();
    aiplatform.ModelsAPI.createChatGenerations_Response response = api.createChatGenerations(request);
    String content;
    if (response != null && response.Code200 != null && response.Code200.generationDetails != null
            && response.Code200.generationDetails.generations != null
            && !response.Code200.generationDetails.generations.isEmpty()) {
        content = response.Code200.generationDetails.generations[0].content;
    }
    System.debug('OHM_LAB_MODEL ' + JSON.serialize(new Map<String, Object>{
        'model' => request.modelName, 'nonEmptyResponse' => String.isNotBlank(content), 'response' => content
    }));
} catch (Exception error) {
    System.debug('OHM_LAB_MODEL ' + JSON.serialize(new Map<String, Object>{
        'model' => 'sfdc_ai__DefaultGPT4OmniMini', 'nonEmptyResponse' => false,
        'errorType' => error.getTypeName(), 'error' => error.getMessage()
    }));
}
