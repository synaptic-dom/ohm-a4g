@IsTest
private class OhmDiscoveryContractTest {
    private static final String PID = '16j000000000001AAA';
    private static final String OTHER_PID = '16j000000000002AAA';
    private static final String TOPIC_ID = '0Qx000000000001AAA';
    private static final String ACTION_ID = '0Qy000000000001AAA';

    private static OhmDTO.AgentModel graph() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.AgentNode planner = new OhmDTO.AgentNode();
        planner.id = PID; planner.developerName = 'Weather_v1';
        g.agentsById.put(PID, planner);
        OhmDTO.AgentNode other = new OhmDTO.AgentNode();
        other.id = OTHER_PID; other.developerName = 'Payments_v1';
        g.agentsById.put(OTHER_PID, other);
        OhmDTO.TopicNode topic = new OhmDTO.TopicNode();
        topic.id = TOPIC_ID; topic.developerName = 'Payments_looks_misleading'; topic.plannerId = PID;
        g.topics.add(topic);
        OhmDTO.ActionNode action = new OhmDTO.ActionNode();
        action.id = ACTION_ID; action.developerName = 'Payments_misleading_action'; action.pluginId = TOPIC_ID;
        g.actions.add(action);
        return g;
    }
    @IsTest static void realRelationshipsOverrideMisleadingNames() {
        OhmDTO.AgentModel g = graph();
        new OhmDiscoveryService().resolveRelationships(g);
        System.assertEquals(PID, g.topics[0].plannerId);
        System.assertEquals(PID, g.actions[0].plannerId, 'Action ownership follows PluginId when PlannerId is null');
        System.assertEquals(0, g.coverageWarnings.size());
    }
    @IsTest static void unresolvedExplicitParentNeverFallsBackToName() {
        OhmDTO.AgentModel g = graph();
        g.actions[0].pluginId = '0Qx000000000002AAA';
        new OhmDiscoveryService().resolveRelationships(g);
        System.assertEquals(null, g.actions[0].plannerId);
        System.assertEquals(1, g.coverageWarnings.size());
    }
    @IsTest static void conflictingRelationshipsDoNotInventOwnership() {
        OhmDTO.AgentModel g = graph();
        g.actions[0].plannerId = OTHER_PID;
        new OhmDiscoveryService().resolveRelationships(g);
        System.assertEquals(null, g.actions[0].plannerId);
        System.assert(g.coverageWarnings[0].startsWith('Conflicting'));
    }
    @IsTest static void legacyNameInferenceIsExplicitlyIncomplete() {
        OhmDTO.AgentModel g = graph();
        g.topics[0].plannerId = null;
        new OhmDiscoveryService().resolveRelationships(g);
        System.assertEquals(OTHER_PID, g.topics[0].plannerId);
        System.assert(g.coverageWarnings[0].startsWith('Inferred'));
    }
    @IsTest static void promptActionAliasesNormalize() {
        System.assert(OhmActionTypes.isPrompt(' GENERATEPROMPTRESPONSE '));
        System.assert(OhmActionTypes.isPrompt('Prompt'));
        System.assert(!OhmActionTypes.isPrompt('flow'));
        System.assert(!OhmActionTypes.isPrompt(null));
        System.assert(OhmActionTypes.isDeterministic(' Apex '));
    }
    @IsTest static void sourceFingerprintIsStableAndDetectsMetadataChange() {
        OhmDTO.AgentModel g = graph();
        Map<String,String> v = new Map<String,String>{PID=>'1',OTHER_PID=>'2',TOPIC_ID=>'3',ACTION_ID=>'4'};
        String before = OhmDiscoveryService.fingerprint(g,v);
        System.assertEquals(before, OhmDiscoveryService.fingerprint(g,v));
        v.put(ACTION_ID,'5');
        System.assertNotEquals(before, OhmDiscoveryService.fingerprint(g,v));
    }
    @IsTest static void currentImportedSourceCarriesProvenanceAndStaleSourceIsIgnored() {
        OhmDTO.AgentModel g = graph();
        g.agentsById.remove(OTHER_PID);
        g.actions[0].plannerId = PID;
        Map<String,String> versions = new Map<String,String>{PID=>'1',TOPIC_ID=>'3',ACTION_ID=>'4'};
        OhmSourceImportService.SourceBundle bundle = new OhmSourceImportService.SourceBundle();
        bundle.schemaVersion = 1; bundle.plannerId = PID; bundle.plannerApiName = 'Weather_v1';
        bundle.metadataFingerprint = OhmDiscoveryService.fingerprint(g,versions);
        bundle.sourceRevision = 'commit-123';
        OhmSourceImportService.SourceArtifact artifact = new OhmSourceImportService.SourceArtifact();
        artifact.id = TOPIC_ID; artifact.instructions = 'Preserve weather actions and routing.';
        artifact.sourceHash = OhmSourceImportService.sha256(artifact.instructions);
        artifact.sourceKind = 'ImportedAgentScript'; artifact.sourcePath = 'weather.agent#weather';
        artifact.sourceVersion = 'commit-123:sha';
        bundle.artifacts = new List<OhmSourceImportService.SourceArtifact>{artifact};
        insert new Ohm_Instruction_Source__c(Planner_Id__c=PID,Metadata_Fingerprint__c=bundle.metadataFingerprint,
            Source_Revision__c=bundle.sourceRevision,Manifest__c=JSON.serialize(bundle));
        OhmSourceImportService.applySources(g,versions);
        System.assertEquals(artifact.instructions,g.topics[0].scope);
        System.assertEquals(artifact.sourceVersion,g.topics[0].sourceVersion);
        System.assertEquals(artifact.sourceHash,g.topics[0].sourceHash);
        g.topics[0].scope = null; g.topics[0].instructions = null;
        versions.put(TOPIC_ID,'5');
        OhmSourceImportService.applySources(g,versions);
        System.assertEquals(null,g.topics[0].instructions,'Stale source must not be audited as current');
        System.assert(g.coverageWarnings[0].contains('stale'));
    }
}
