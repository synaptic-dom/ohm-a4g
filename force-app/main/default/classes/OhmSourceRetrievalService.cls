/**
 * Callout-only retrieval for one published Agent Script bundle and its linked prompts.
 * The caller persists RetrievalState between jobs and performs all DML after callouts.
 * No metadata is deployed, activated, generated or executed by this service.
 */
public with sharing class OhmSourceRetrievalService {
    private static final String API_VERSION = '67.0';
    private static final String SOAP_NS = 'http://schemas.xmlsoap.org/soap/envelope/';
    private static final Integer MAX_CANDIDATES = 20;
    private static final Integer MAX_POLLS = 40;
    private static final Integer MAX_ARTIFACTS = 100;
    public class RetrievalException extends Exception {}

    public class RetrievalState {
        public String plannerId;
        public String plannerApiName;
        public String metadataFingerprint;
        public String botApiName;
        public String expectedTarget;
        public Boolean modern;
        public List<String> bundleCandidates = new List<String>();
        public Integer candidateIndex = 0;
        public Map<String, String> promptApiByAction = new Map<String, String>();
        public Map<String, String> sourceModifiedByKey = new Map<String, String>();
        public List<String> warnings = new List<String>();
        public String requestId;
        public Integer pollCount = 0;
        public Datetime startedAt;
        public Datetime deadlineAt;
    }
    public class RetrievalResult {
        public Boolean pending;
        public RetrievalState state;
        public OhmSourceImportService.SourceBundle bundle;
        public List<String> warnings;
    }
    private class MetadataRecord {
        String apiName;
        String id;
        String modified;
    }

    public static RetrievalState start(OhmDTO.AgentModel graph) {
        OhmDTO.AgentNode planner = singlePlanner(graph);
        RetrievalState state = new RetrievalState();
        state.plannerId = planner.id; state.plannerApiName = planner.developerName;
        state.metadataFingerprint = graph.metadataFingerprint;
        state.startedAt = System.now(); state.deadlineAt = state.startedAt.addMinutes(10);
        Matcher version = Pattern.compile('^([A-Za-z_][A-Za-z0-9_]*)_v([1-9][0-9]*)$').matcher(planner.developerName);
        if (!version.matches()) { throw new RetrievalException(OhmDiscoveryService.AGENT_SCRIPT_SCOPE_MESSAGE); }
        state.modern = true;
        state.botApiName = version.group(1);
        state.expectedTarget = state.botApiName + '.v' + version.group(2);
        prepareAuthoringCandidates(state);
        preparePromptSources(state, graph);
        state.requestId = submit(state);
        return state;
    }

    public static RetrievalResult poll(RetrievalState state, OhmDTO.AgentModel currentGraph) {
        validateState(state, currentGraph);
        state.pollCount++;
        if (state.pollCount > MAX_POLLS || System.now() > state.deadlineAt) {
            throw new RetrievalException('Source retrieval timed out. Start a new source refresh.');
        }
        Dom.Document response = OhmSalesforceApi.metadata('checkRetrieveStatus',
            '<asyncProcessId>' + xml(state.requestId) + '</asyncProcessId><includeZip>true</includeZip>');
        Dom.XmlNode result = oneResult(response, 'checkRetrieveStatus');
        String status = text(result, 'status');
        if (status == 'Failed' || status == 'Canceled') {
            throw new RetrievalException('Salesforce source retrieval failed: ' + safeError(text(result, 'errorMessage')));
        }
        if (text(result, 'done') != 'true') { return pending(state); }
        if (status != 'Succeeded') { throw new RetrievalException('Salesforce returned an unexpected source retrieval status.'); }
        String encoded = text(result, 'zipFile');
        if (String.isBlank(encoded) || encoded.length() > 1398112) {
            throw new RetrievalException('Metadata response has no ZIP or exceeds the 1 MiB archive limit.');
        }
        Map<String, String> files = OhmSourceParser.readArchive(EncodingUtil.base64Decode(encoded));
        OhmSourceParser.PublishedScript published;
        if (state.modern) {
            published = OhmSourceParser.publishedScript(files, state.expectedTarget);
            if (published == null) {
                state.candidateIndex++;
                if (state.candidateIndex >= state.bundleCandidates.size()) {
                    throw new RetrievalException('No retrieved authoring bundle is bound to ' + state.expectedTarget + '. Source coverage is unavailable.');
                }
                state.requestId = submit(state);
                return pending(state);
            }
        }
        OhmSourceImportService.SourceBundle bundle = buildBundle(state, currentGraph, files, published);
        validateFreshness(state);
        for (OhmSourceImportService.SourceArtifact artifact : bundle.artifacts) {
            artifact.sourceBindingVerified = true;
        }
        if (JSON.serialize(bundle).length() > 131072) {
            throw new RetrievalException('Retrieved source exceeds the 131072-character manifest storage limit. Source was not truncated.');
        }
        RetrievalResult done = new RetrievalResult(); done.pending = false; done.state = state;
        done.bundle = bundle; done.warnings = bundle.warnings;
        return done;
    }

    /** Reusable if a caller persists the completed bundle in a later transaction. */
    public static void validateFreshness(RetrievalState state) {
        if (state == null || state.modern != true) {
            throw new RetrievalException(OhmDiscoveryService.AGENT_SCRIPT_SCOPE_MESSAGE);
        }
        Set<String> types = new Set<String>();
        for (String key : state.sourceModifiedByKey.keySet()) {
            String type = key.substringBefore(':');
            if (type == 'AiAuthoringBundle' && key != 'AiAuthoringBundle:' + state.bundleCandidates[state.candidateIndex]) { continue; }
            types.add(type);
        }
        for (String type : types) {
            Map<String, MetadataRecord> fresh = metadataByName(type);
            for (String key : state.sourceModifiedByKey.keySet()) {
                if (!key.startsWith(type + ':')) { continue; }
                String apiName = key.substringAfter(':');
                if (type == 'AiAuthoringBundle' && apiName != state.bundleCandidates[state.candidateIndex]) { continue; }
                MetadataRecord current = fresh.get(apiName);
                if (current == null || current.modified != state.sourceModifiedByKey.get(key)) {
                    throw new RetrievalException('Source metadata changed during retrieval: ' + apiName + '. Refresh again.');
                }
            }
        }
    }

    private static void prepareAuthoringCandidates(RetrievalState state) {
        Map<String, MetadataRecord> available = metadataByName('AiAuthoringBundle');
        Map<Integer, String> versions = new Map<Integer, String>();
        String prefix = state.botApiName + '_';
        for (String name : available.keySet()) {
            if (!name.startsWith(prefix)) { continue; }
            String suffix = name.substring(prefix.length());
            if (!Pattern.matches('[1-9][0-9]{0,8}', suffix)) { continue; }
            MetadataRecord record = available.get(name);
            if (String.isBlank(record.modified)) { continue; }
            versions.put(Integer.valueOf(suffix), name);
            state.sourceModifiedByKey.put('AiAuthoringBundle:' + name, record.modified);
        }
        if (versions.isEmpty()) {
            throw new RetrievalException('No versioned authoring bundles map to ' + state.botApiName + '. Draft source is not accepted as published source.');
        }
        if (versions.size() > MAX_CANDIDATES) {
            throw new RetrievalException('More than 20 authoring versions require a narrower publication mapping.');
        }
        List<Integer> ordered = new List<Integer>(versions.keySet()); ordered.sort();
        for (Integer i = ordered.size() - 1; i >= 0; i--) { state.bundleCandidates.add(versions.get(ordered[i])); }
    }

    private static void preparePromptSources(RetrievalState state, OhmDTO.AgentModel graph) {
        Boolean needed = false;
        for (OhmDTO.ActionNode action : graph.actions) { if (OhmActionTypes.isPrompt(action.invocationTargetType)) { needed = true; break; } }
        if (!needed) { return; }
        Map<String, MetadataRecord> available = metadataByName('GenAiPromptTemplate');
        Map<String, String> nameById = new Map<String, String>();
        for (MetadataRecord record : available.values()) {
            if (String.isNotBlank(record.id)) {
                nameById.put(record.id, record.apiName);
                if (record.id.length() >= 15) { nameById.put(record.id.substring(0, 15), record.apiName); }
            }
        }
        for (OhmDTO.ActionNode action : graph.actions) {
            if (!OhmActionTypes.isPrompt(action.invocationTargetType)) { continue; }
            String target = action.invocationTarget;
            if (String.isNotBlank(target) && target.contains('://')) { target = target.substringAfter('://'); }
            String name = nameById.containsKey(target) ? nameById.get(target) : target;
            MetadataRecord record = available.get(name);
            if (record == null || String.isBlank(record.modified)) {
                state.warnings.add('Active prompt source cannot be mapped for ' + action.developerName); continue;
            }
            state.promptApiByAction.put(action.id, name);
            state.sourceModifiedByKey.put('GenAiPromptTemplate:' + name, record.modified);
        }
    }

    private static String submit(RetrievalState state) {
        String types = manifestType('AiAuthoringBundle', new List<String>{state.bundleCandidates[state.candidateIndex]});
        Set<String> promptNames = new Set<String>(state.promptApiByAction.values());
        if (!promptNames.isEmpty()) { types += manifestType('GenAiPromptTemplate', new List<String>(promptNames)); }
        String args = '<request><apiVersion>' + API_VERSION + '</apiVersion><singlePackage>true</singlePackage>'
            + '<unpackaged>' + types + '<version>' + API_VERSION + '</version></unpackaged></request>';
        Dom.XmlNode result = oneResult(OhmSalesforceApi.metadata('retrieve', args), 'retrieve');
        String id = text(result, 'id');
        if (String.isBlank(id)) { throw new RetrievalException('Salesforce did not return a metadata retrieval job ID.'); }
        return id;
    }

    private static String manifestType(String type, List<String> names) {
        names.sort();
        String result = '<types>';
        for (String name : names) { result += '<members>' + xml(name) + '</members>'; }
        return result + '<name>' + type + '</name></types>';
    }

    private static OhmSourceImportService.SourceBundle buildBundle(RetrievalState state, OhmDTO.AgentModel graph,
        Map<String, String> files, OhmSourceParser.PublishedScript published) {
        OhmSourceImportService.SourceBundle bundle = new OhmSourceImportService.SourceBundle();
        bundle.schemaVersion = 1; bundle.plannerId = state.plannerId; bundle.plannerApiName = state.plannerApiName;
        bundle.metadataFingerprint = state.metadataFingerprint; bundle.provenance = 'Retrieved'; bundle.retrievedAt = System.now();
        bundle.sourceRevision = 'MetadataApi:' + API_VERSION + ':' + state.requestId;
        bundle.artifacts = new List<OhmSourceImportService.SourceArtifact>(); bundle.warnings = new List<String>();
        bundle.warnings.addAll(state.warnings);
        if (state.modern) {
            // Preserve the full authored setup for the semantic reviewer. It is context,
            // not an additional prompt block or an assertion of runtime token usage.
            bundle.configurationSource = published.script;
            bundle.configurationSourcePath = 'metadata://' + published.path;
            bundle.configurationSourceHash = OhmSourceImportService.sha256(published.script);
            OhmSourceParser.AgentScript script = OhmSourceParser.agentScript(published.script, state.botApiName);
            Set<String> expectedTopics = new Set<String>();
            for (OhmDTO.TopicNode topic : graph.topics) { expectedTopics.add(sourceTopicName(topic.developerName, state.plannerId)); }
            if (expectedTopics != script.topics.keySet()) {
                throw new RetrievalException('Published Agent Script topic names do not exactly match the selected planner inventory.');
            }
            String apiName = state.bundleCandidates[state.candidateIndex];
            String dependency = state.sourceModifiedByKey.get('AiAuthoringBundle:' + apiName);
            bundle.artifacts.add(artifact(state.plannerId, script.systemInstructions, published.script, 'RetrievedAgentScript',
                apiName, published.target, published.path + '#system', dependency, bundle.retrievedAt, null));
            for (OhmDTO.TopicNode topic : graph.topics) {
                String name = sourceTopicName(topic.developerName, state.plannerId);
                bundle.artifacts.add(artifact(topic.id, script.topics.get(name), published.script, 'RetrievedAgentScript',
                    apiName, published.target, published.path + '#' + name, dependency, bundle.retrievedAt, null));
            }
            bundle.warnings.add('Retrieved Agent Script retains conditional branches. Static instruction size is not measured rendered prompt usage.');
        }
        Map<String, OhmSourceParser.PromptTemplate> templates = new Map<String, OhmSourceParser.PromptTemplate>();
        Map<String, String> paths = new Map<String, String>();
        for (String apiName : new Set<String>(state.promptApiByAction.values())) {
            String path = exactFile(files, 'genAiPromptTemplates', apiName, '.genAiPromptTemplate');
            if (path == null) { bundle.warnings.add('Retrieved ZIP has no active prompt source for ' + apiName); continue; }
            try {
                templates.put(apiName, OhmSourceParser.promptTemplate(files.get(path), apiName)); paths.put(apiName, path);
            } catch (OhmSourceParser.SourceParseException ex) {
                bundle.warnings.add('Active prompt source unavailable for ' + apiName + ': ' + ex.getMessage());
            }
        }
        for (String actionId : state.promptApiByAction.keySet()) {
            String name = state.promptApiByAction.get(actionId);
            OhmSourceParser.PromptTemplate prompt = templates.get(name);
            if (prompt == null) { continue; }
            String path = paths.get(name);
            String modified = state.sourceModifiedByKey.get('GenAiPromptTemplate:' + name);
            bundle.artifacts.add(artifact(actionId, prompt.instructions, files.get(path), 'RetrievedPromptTemplate',
                name, prompt.versionIdentifier, path + '#templateVersions/' + prompt.versionIdentifier,
                modified, bundle.retrievedAt, prompt.boundModel));
        }
        if (bundle.artifacts.isEmpty()) { throw new RetrievalException('No complete instruction source was returned for this planner.'); }
        return bundle;
    }

    private static OhmSourceImportService.SourceArtifact artifact(String id, String instructions, String source,
        String kind, String apiName, String version, String path, String modified, Datetime retrievedAt, String model) {
        OhmSourceImportService.SourceArtifact result = new OhmSourceImportService.SourceArtifact();
        result.id = id; result.instructions = instructions; result.sourceKind = kind; result.sourceApiName = apiName;
        result.sourceVersionIdentifier = version; result.sourceRetrievedAt = retrievedAt; result.boundModel = model;
        result.sourceVersion = 'MetadataApi:' + API_VERSION + ':' + version + ':' + OhmSourceImportService.sha256(source);
        result.sourceHash = OhmSourceImportService.sha256(instructions); result.sourcePath = 'metadata://' + path;
        result.dependencyFingerprint = OhmSourceImportService.sha256(apiName + '\n' + modified + '\n' + version + '\n' + OhmSourceImportService.sha256(source));
        result.sourceBindingVerified = false;
        return result;
    }

    private static String exactFile(Map<String, String> files, String directory, String apiName, String suffix) {
        String found;
        for (String path : files.keySet()) {
            String p = '/' + path;
            if (!p.endsWith('/' + directory + '/' + apiName + suffix) && !p.endsWith('/' + directory + '/' + apiName + suffix + '-meta.xml')) { continue; }
            if (found != null) { throw new RetrievalException('Ambiguous duplicate source files for ' + apiName); }
            found = path;
        }
        return found;
    }
    private static String sourceTopicName(String name, String plannerId) {
        String suffix = '_' + plannerId.substring(0, 15);
        return name.endsWith(suffix) ? name.substring(0, name.length() - suffix.length()) : name;
    }

    private static Map<String, MetadataRecord> metadataByName(String type) {
        Dom.Document response = OhmSalesforceApi.metadata('listMetadata', '<queries><type>' + type
            + '</type></queries><asOfVersion>' + API_VERSION + '</asOfVersion>');
        Map<String, MetadataRecord> result = new Map<String, MetadataRecord>();
        for (Dom.XmlNode node : results(response, 'listMetadata')) {
            String name = text(node, 'fullName');
            if (String.isBlank(name)) { continue; }
            if (result.containsKey(name)) { throw new RetrievalException('Metadata listing returned a duplicated component name.'); }
            MetadataRecord record = new MetadataRecord(); record.apiName = name; record.id = text(node, 'id');
            record.modified = text(node, 'lastModifiedDate'); result.put(name, record);
        }
        return result;
    }
    private static OhmDTO.AgentNode singlePlanner(OhmDTO.AgentModel graph) {
        if (graph == null || graph.agentsById == null || graph.agentsById.size() != 1 || String.isBlank(graph.metadataFingerprint)) {
            throw new RetrievalException('Source retrieval requires one exact planner and a current metadata fingerprint.');
        }
        OhmDTO.AgentNode planner = graph.agentsById.values()[0];
        if (String.isBlank(planner.id) || planner.id.length() < 15 || String.isBlank(planner.developerName)
            || !Pattern.matches('[A-Za-z_][A-Za-z0-9_]*', planner.developerName) || !graph.agentsById.containsKey(planner.id)) {
            throw new RetrievalException('Planner identity is invalid.');
        }
        if (!OhmDiscoveryService.isAgentScriptCandidate(planner.developerName)) {
            throw new RetrievalException(OhmDiscoveryService.AGENT_SCRIPT_SCOPE_MESSAGE);
        }
        if (graph.topics.size() + graph.actions.size() + 1 > MAX_ARTIFACTS) { throw new RetrievalException('Source retrieval supports at most 100 scoped artifacts per request.'); }
        Set<String> ids = new Set<String>{planner.id};
        for (OhmDTO.TopicNode topic : graph.topics) {
            if (topic.plannerId != planner.id || String.isBlank(topic.developerName) || String.isBlank(topic.id) || ids.contains(topic.id)) {
                throw new RetrievalException('Topic inventory does not belong to the selected planner.');
            }
            ids.add(topic.id);
        }
        for (OhmDTO.ActionNode action : graph.actions) {
            if (action.plannerId != planner.id || String.isBlank(action.id) || ids.contains(action.id)) { throw new RetrievalException('Action inventory does not belong to the selected planner.'); }
            ids.add(action.id);
        }
        return planner;
    }
    private static void validateState(RetrievalState state, OhmDTO.AgentModel graph) {
        OhmDTO.AgentNode planner = singlePlanner(graph);
        if (state == null || state.plannerId != planner.id || state.plannerApiName != planner.developerName
            || state.metadataFingerprint != graph.metadataFingerprint || String.isBlank(state.requestId)
            || state.deadlineAt == null || state.pollCount == null || state.candidateIndex == null
            || state.modern != true || state.sourceModifiedByKey == null || state.promptApiByAction == null
            || (state.modern && (state.candidateIndex < 0 || state.candidateIndex >= state.bundleCandidates.size()))) {
            throw new RetrievalException('Planner metadata changed or retrieval state is invalid. Refresh again.');
        }
    }
    private static RetrievalResult pending(RetrievalState state) {
        RetrievalResult result = new RetrievalResult(); result.pending = true; result.state = state; result.warnings = state.warnings; return result;
    }
    private static List<Dom.XmlNode> results(Dom.Document document, String operation) {
        Dom.XmlNode body = document.getRootElement().getChildElement('Body', SOAP_NS);
        Dom.XmlNode response = body == null ? null : body.getChildElement(operation + 'Response', OhmSourceParser.METADATA_NS);
        if (response == null) { throw new RetrievalException('Salesforce returned an invalid ' + operation + ' SOAP response.'); }
        return OhmSourceParser.children(response, 'result');
    }
    private static Dom.XmlNode oneResult(Dom.Document document, String operation) {
        List<Dom.XmlNode> found = results(document, operation);
        if (found.size() != 1) { throw new RetrievalException('Salesforce returned an invalid metadata result count.'); }
        return found[0];
    }
    private static String text(Dom.XmlNode node, String name) { return OhmSourceParser.childText(node, name); }
    private static String xml(String value) { return value == null ? '' : value.escapeXml(); }
    private static String safeError(String value) { return String.isBlank(value) ? 'No error detail returned.' : value.left(500); }
}
