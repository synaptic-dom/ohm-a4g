@IsTest
private class OhmSourceRetrievalServiceTest {
    private static final String PID = '16j000000000001AAA';
    private static final String ROUTER = '0Qx000000000001AAA';
    private static final String WEATHER = '0Qx000000000002AAA';
    private static final String ACTION_ID = '0Qy000000000001AAA';
    private static final String TEMPLATE_ID = '0hf000000000001AAA';
    private static final String NS = 'http://soap.sforce.com/2006/04/metadata';
    private static final String SOAP = 'http://schemas.xmlsoap.org/soap/envelope/';

    private static OhmDTO.AgentModel graph() {
        OhmDTO.AgentModel graph = new OhmDTO.AgentModel(); graph.metadataFingerprint = 'current-fingerprint';
        OhmDTO.AgentNode agent = new OhmDTO.AgentNode(); agent.id = PID; agent.developerName = 'Weather_v1'; graph.agentsById.put(PID, agent);
        for (Integer i = 0; i < 2; i++) {
            OhmDTO.TopicNode topic = new OhmDTO.TopicNode(); topic.id = i == 0 ? ROUTER : WEATHER;
            topic.developerName = (i == 0 ? 'router' : 'weather') + '_' + PID.substring(0, 15); topic.plannerId = PID; graph.topics.add(topic);
        }
        OhmDTO.ActionNode action = new OhmDTO.ActionNode(); action.id = ACTION_ID; action.developerName = 'generate_schedule';
        action.plannerId = PID; action.pluginId = WEATHER; action.invocationTargetType = 'generatePromptResponse'; action.invocationTarget = TEMPLATE_ID;
        graph.actions.add(action); return graph;
    }
    private static String script() {
        return 'config:\n   developer_name: "Weather"\nsystem:\n   instructions: "Help with weather."\n'
            + 'start_agent router:\n   reasoning:\n      instructions: "Choose weather."\n'
            + 'subagent weather:\n   reasoning:\n      instructions:->\n'
            + '         | Help with the current weather.\n         if @variables.location:\n'
            + '            | Fetch {!@actions.lookup}.\n         else:\n            | Ask for a location.\n';
    }
    private static String prompt(Boolean inactive) {
        return '<GenAiPromptTemplate xmlns="' + NS + '"><developerName>Schedule</developerName>'
            + (inactive ? '' : '<activeVersionIdentifier>hash_9</activeVersionIdentifier>')
            + '<templateVersions><content>Old source</content><status>Published</status><versionIdentifier>hash_1</versionIdentifier></templateVersions>'
            + '<templateVersions><content>  Keep  spaces.\nDon&apos;t collapse\u00a0space.\n</content><status>Published</status>'
            + '<primaryModel>small-model</primaryModel><versionIdentifier>hash_9</versionIdentifier></templateVersions></GenAiPromptTemplate>';
    }
    private class ApiMock implements HttpCalloutMock {
        public Boolean oneCandidate = false;
        public Boolean allWrongTargets = false;
        public Boolean wrongDeveloper = false;
        public Boolean wrongTopics = false;
        public Boolean missingPrompt = false;
        public Boolean inactivePrompt = false;
        public Boolean pendingOnce = false;
        public Boolean sourceChanges = false;
        public Boolean failRetrieve = false;
        public Boolean missingScript = false;
        public Boolean legacy = false;
        public Boolean oversizedManifest = false;
        public String currentCandidate;
        public Integer promptListings = 0;
        public Integer polls = 0;
        public Integer requests = 0;
        public List<String> requestedCandidates = new List<String>();

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse(); response.setStatusCode(200);
            if (request.getEndpoint().endsWith('/services/oauth2/token')) {
                response.setHeader('Content-Type', 'application/json'); response.setBody('{"access_token":"test-session","instance_url":"https://example.my.salesforce.com"}'); return response;
            }
            System.assert(request.getEndpoint().endsWith('/services/Soap/m/67.0'));
            System.assertEquals('POST', request.getMethod());
            Dom.Document document = new Dom.Document(); document.load(request.getBody());
            Dom.XmlNode operation = document.getRootElement().getChildElement('Body', SOAP).getChildElements()[0];
            String op = operation.getName();
            String result;
            if (op == 'listMetadata') {
                String type = OhmSourceParser.childText(OhmSourceParser.child(operation, 'queries'), 'type');
                if (type == 'AiAuthoringBundle') {
                    result = listed('Weather_4', null, false) + (oneCandidate ? '' : listed('Weather_7', null, false));
                    // An unversioned draft and unrelated similarly named agent must never be selected.
                    result += listed('Weather', null, false) + listed('Weather_Clone_9', null, false);
                } else if (type == 'GenAiPromptTemplate') {
                    promptListings++;
                    result = listed('Schedule', TEMPLATE_ID, sourceChanges && promptListings > 1);
                } else if (type == 'GenAiPlugin') { result = listed('LegacyWeather', null, false); }
                else { System.assert(false, 'Unexpected metadata type ' + type); }
            } else if (op == 'retrieve') {
                requests++;
                Dom.XmlNode manifest = OhmSourceParser.child(OhmSourceParser.child(operation, 'request'), 'unpackaged');
                for (Dom.XmlNode type : OhmSourceParser.children(manifest, 'types')) {
                    if (OhmSourceParser.childText(type, 'name') == 'AiAuthoringBundle') {
                        List<Dom.XmlNode> members = OhmSourceParser.children(type, 'members');
                        System.assertEquals(1, members.size(), 'Each request pins one authoring component');
                        currentCandidate = members[0].getText(); requestedCandidates.add(currentCandidate);
                    }
                }
                result = '<result><id>09S000000000001AAA</id><done>false</done><state>Queued</state></result>';
            } else if (op == 'checkRetrieveStatus') {
                polls++;
                if (failRetrieve) { result = '<result><done>true</done><status>Failed</status><errorMessage>Component failed</errorMessage></result>'; }
                else if (pendingOnce && polls == 1) { result = '<result><done>false</done><status>InProgress</status></result>'; }
                else { result = '<result><done>true</done><status>Succeeded</status><zipFile>' + EncodingUtil.base64Encode(archive()) + '</zipFile></result>'; }
            } else { System.assert(false, 'Unexpected operation ' + op); }
            response.setHeader('Content-Type', 'text/xml');
            response.setBody('<env:Envelope xmlns:env="' + SOAP + '"><env:Body><' + op + 'Response xmlns="' + NS + '">'
                + result + '</' + op + 'Response></env:Body></env:Envelope>');
            return response;
        }
        private String listed(String name, String id, Boolean changed) {
            return '<result><fullName>' + name + '</fullName>' + (id == null ? '' : '<id>' + id + '</id>')
                + '<lastModifiedDate>2026-09-07T01:00:' + (changed ? '01' : '00') + '.000Z</lastModifiedDate></result>';
        }
        private Blob archive() {
            Compression.ZipWriter writer = new Compression.ZipWriter();
            if (legacy) {
                writer.addEntry('unpackaged/genAiPlugins/LegacyWeather.genAiPlugin', Blob.valueOf('<GenAiPlugin xmlns="' + NS + '">'
                    + '<developerName>LegacyWeather</developerName><description>Summary only</description>'
                    + '<genAiPluginInstructions><description>Ask for location.</description></genAiPluginInstructions></GenAiPlugin>'));
            } else {
                String target = allWrongTargets || currentCandidate == 'Weather_7' ? 'Weather.v2' : 'Weather.v1';
                writer.addEntry('unpackaged/aiAuthoringBundles/Weather/Weather.bundle-meta.xml', Blob.valueOf('<AiAuthoringBundle xmlns="' + NS
                    + '"><bundleType>AGENT</bundleType><target>' + target + '</target></AiAuthoringBundle>'));
                String source = script();
                if (wrongDeveloper) { source = source.replace('developer_name: "Weather"', 'developer_name: "Wrong"'); }
                if (wrongTopics) { source = source.replace('subagent weather:', 'subagent renamed:'); }
                if (oversizedManifest) {
                    String huge = 'x'.repeat(70000);
                    source = source.replace('Help with weather.', huge).replace('Choose weather.', huge);
                }
                if (!missingScript) { writer.addEntry('unpackaged/aiAuthoringBundles/Weather/Weather.agent', Blob.valueOf(source)); }
            }
            if (!missingPrompt) { writer.addEntry('unpackaged/genAiPromptTemplates/Schedule.genAiPromptTemplate', Blob.valueOf(prompt(inactivePrompt))); }
            return writer.getArchive();
        }
    }

    private static OhmSourceImportService.SourceArtifact findArtifact(OhmSourceImportService.SourceBundle bundle, String id) {
        for (OhmSourceImportService.SourceArtifact artifact : bundle.artifacts) { if (artifact.id == id) { return artifact; } }
        return null;
    }
    @IsTest static void retrievesPublicationByTargetAndActivePromptWithProvenance() {
        ApiMock mock = new ApiMock(); Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph();
        Test.startTest();
        OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        System.assertEquals('Weather.v1', state.expectedTarget);
        OhmSourceRetrievalService.RetrievalResult first = OhmSourceRetrievalService.poll(state, inventory);
        System.assertEquals(true, first.pending, 'Newer authoring bundle targets a different published version');
        state = (OhmSourceRetrievalService.RetrievalState)JSON.deserialize(JSON.serialize(first.state), OhmSourceRetrievalService.RetrievalState.class);
        OhmSourceRetrievalService.RetrievalResult done = OhmSourceRetrievalService.poll(state, inventory);
        Test.stopTest();
        System.assertEquals(false, done.pending);
        System.assertEquals(new List<String>{'Weather_7', 'Weather_4'}, mock.requestedCandidates);
        System.assertEquals(4, done.bundle.artifacts.size());
        System.assertEquals('Retrieved', done.bundle.provenance);
        System.assertEquals(script(), done.bundle.configurationSource, 'Full setup source survives retrieval separately from prompt blocks.');
        System.assertEquals(OhmSourceImportService.sha256(script()), done.bundle.configurationSourceHash);
        System.assert(done.bundle.configurationSourcePath.startsWith('metadata://'));
        System.assertEquals('current-fingerprint', done.bundle.metadataFingerprint);
        OhmSourceImportService.SourceArtifact source = findArtifact(done.bundle, WEATHER);
        System.assert(source.instructions.contains('if @variables.location:\n   | Fetch {!@actions.lookup}.'));
        System.assertEquals('Weather_4', source.sourceApiName);
        System.assertEquals('Weather.v1', source.sourceVersionIdentifier);
        System.assertEquals(true, source.sourceBindingVerified);
        System.assertEquals(OhmSourceImportService.sha256(source.instructions), source.sourceHash);
        OhmSourceImportService.SourceArtifact prompt = findArtifact(done.bundle, ACTION_ID);
        System.assertEquals('  Keep  spaces.\nDon\'t collapse\u00a0space.\n', prompt.instructions);
        System.assertEquals('hash_9', prompt.sourceVersionIdentifier);
        System.assertEquals('Schedule', prompt.sourceApiName);
        System.assertEquals('small-model', prompt.boundModel);
        System.assertEquals(true, prompt.sourceBindingVerified);
        System.assertNotEquals(null, prompt.dependencyFingerprint);
        System.assertEquals(0, [SELECT COUNT() FROM Ohm_Instruction_Source__c], 'Retrieval does not persist or deploy anything');
    }
    @IsTest static void pendingResponseDoesNotInventSourcesOrResubmit() {
        ApiMock mock = new ApiMock(); mock.pendingOnce = true; mock.oneCandidate = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph();
        OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        OhmSourceRetrievalService.RetrievalResult waiting = OhmSourceRetrievalService.poll(state, inventory);
        System.assertEquals(true, waiting.pending); System.assertEquals(null, waiting.bundle); System.assertEquals(1, mock.requests);
        System.assertEquals(false, OhmSourceRetrievalService.poll(waiting.state, inventory).pending);
    }
    @IsTest static void rejectsInventoryChangesBeforeAcceptingSource() {
        ApiMock mock = new ApiMock(); Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        inventory.metadataFingerprint = 'new-publication';
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('changed')); }
        System.assertEquals(0, mock.polls);
    }
    @IsTest static void rejectsPromptEditsThatDoNotChangePlannerFingerprint() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; mock.sourceChanges = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('changed during retrieval: Schedule')); }
    }
    @IsTest static void missingPromptIsExplicitPartialCoverage() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; mock.missingPrompt = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        OhmSourceRetrievalService.RetrievalResult done = OhmSourceRetrievalService.poll(state, inventory);
        System.assertEquals(3, done.bundle.artifacts.size()); System.assertEquals(null, findArtifact(done.bundle, ACTION_ID));
        System.assert(String.join(done.warnings, '\n').contains('no active prompt source for Schedule'));
    }
    @IsTest static void inactivePromptNeverFallsBackToLatestVersion() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; mock.inactivePrompt = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        OhmSourceRetrievalService.RetrievalResult done = OhmSourceRetrievalService.poll(state, inventory);
        System.assertEquals(null, findArtifact(done.bundle, ACTION_ID));
        System.assert(String.join(done.warnings, '\n').contains('no active version identifier'));
    }
    @IsTest static void wrongPublicationFailsClosed() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; mock.allWrongTargets = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('No retrieved authoring bundle')); }
    }
    @IsTest static void mismatchedConfigAndTopicSetCannotBecomeCurrentEvidence() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; mock.wrongDeveloper = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('developer_name')); }
        mock.wrongDeveloper = false; mock.wrongTopics = true;
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('topic names')); }
    }
    @IsTest static void missingScriptAndFailedRetrieveAreVisible() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; mock.missingScript = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('no matching Agent Script')); }
        mock.missingScript = false; mock.failRetrieve = true;
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('failed')); }
    }
    @IsTest static void boundedStateAndManifestNeverSilentlyTruncate() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; mock.oversizedManifest = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('not truncated')); }
        state.deadlineAt = System.now().addMinutes(-1);
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('timed out')); }
    }
    @IsTest static void legacyPlannerWithLinkedPromptIsRejectedBeforeCallouts() {
        ApiMock mock = new ApiMock(); mock.legacy = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph(); inventory.agentsById.get(PID).developerName = 'LegacyPlanner'; inventory.topics.remove(0);
        inventory.topics[0].developerName = 'LegacyWeather';
        try { OhmSourceRetrievalService.start(inventory); System.assert(false, 'A prompt dependency cannot make a legacy planner eligible'); }
        catch (OhmSourceRetrievalService.RetrievalException ex) {
            System.assertEquals(OhmDiscoveryService.AGENT_SCRIPT_SCOPE_MESSAGE, ex.getMessage());
        }
        System.assertEquals(0, Limits.getCallouts());
        System.assertEquals(0, mock.requests);
    }
    @IsTest static void standalonePromptCannotStartBundleRetrieval() {
        OhmDTO.AgentModel inventory = graph(); inventory.agentsById.clear(); inventory.topics.clear();
        try { OhmSourceRetrievalService.start(inventory); System.assert(false, 'Standalone prompt targets are outside bundle scope'); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('one exact planner')); }
        System.assertEquals(0, Limits.getCallouts());
    }
    @IsTest static void previousLegacyRetrievalStateCannotResume() {
        ApiMock mock = new ApiMock(); mock.oneCandidate = true; Test.setMock(HttpCalloutMock.class, mock);
        OhmDTO.AgentModel inventory = graph();
        OhmSourceRetrievalService.RetrievalState state = OhmSourceRetrievalService.start(inventory);
        state.modern = false;
        Integer priorCallouts = Limits.getCallouts();
        try { OhmSourceRetrievalService.poll(state, inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('invalid')); }
        try { OhmSourceRetrievalService.validateFreshness(state); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) {
            System.assertEquals(OhmDiscoveryService.AGENT_SCRIPT_SCOPE_MESSAGE, ex.getMessage());
        }
        System.assertEquals(priorCallouts, Limits.getCallouts());
    }
    @IsTest static void refusesUnscopedInventoryWithoutCallouts() {
        OhmDTO.AgentModel inventory = graph(); inventory.topics[0].plannerId = 'another-planner';
        try { OhmSourceRetrievalService.start(inventory); System.assert(false); }
        catch (OhmSourceRetrievalService.RetrievalException ex) { System.assert(ex.getMessage().contains('does not belong')); }
        System.assertEquals(0, Limits.getCallouts());
    }
}
