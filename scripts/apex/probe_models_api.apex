// Probe: can Apex invoke an LLM through the Einstein Trust Layer with NO connected app?
// (Agent API / connected-app creation is disabled on this org, so the assistant must
//  use the callout-free Apex Models API — aiplatform.ModelsAPI, GA Winter '25.)
try {
    aiplatform.ModelsAPI.createChatGenerations_Request req =
        new aiplatform.ModelsAPI.createChatGenerations_Request();
    req.modelName = 'sfdc_ai__DefaultGPT4OmniMini';

    aiplatform.ModelsAPI_ChatMessageRequest msg = new aiplatform.ModelsAPI_ChatMessageRequest();
    msg.content = 'Reply with exactly the five words: OHM MODELS API IS LIVE';
    msg.role = 'user';

    aiplatform.ModelsAPI_ChatGenerationsRequest body = new aiplatform.ModelsAPI_ChatGenerationsRequest();
    body.messages = new List<aiplatform.ModelsAPI_ChatMessageRequest>{ msg };

    req.body = body;

    aiplatform.ModelsAPI api = new aiplatform.ModelsAPI();
    aiplatform.ModelsAPI.createChatGenerations_Response res = api.createChatGenerations(req);

    String out = res.Code200.generationDetails.generations[0].content;
    System.debug('OHM_PROBE_OK model=sfdc_ai__DefaultGPT4OmniMini reply=' + out);
} catch (Exception e) {
    System.debug('OHM_PROBE_ERR ' + e.getTypeName() + ': ' + e.getMessage());
}
