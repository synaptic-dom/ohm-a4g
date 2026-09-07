/** Completed-report fixtures for readout/assistant tests; async acquisition is tested separately. */
@IsTest
public class OhmAuditTestSupport {
    /** Both supported demo projects publish an Apex-backed Agent Script control.
     * Select its current publication; never reopen legacy audit scope or skip missing fixtures.
     */
    public static Id scriptPlannerId() {
        List<OhmDTO.ProcessSummaryDTO> fleet = new OhmDiscoveryService().listFleet();
        for (String family : new List<String>{'Ohm_Schedule_Desk_v', 'Ohm_Weather_Demo_v'}) {
            for (OhmDTO.ProcessSummaryDTO row : fleet) {
                if (row.plannerApiName.startsWith(family)) return row.plannerId;
            }
        }
        return null;
    }

    /** Stable, explicitly synthetic instruction evidence keeps readout tests independent of
     * the demo's current optimized source. The real acquisition path has separate tests.
     */
    public static void seedInstructionFixture(Id plannerId) {
        OhmDTO.AgentModel graph = new OhmDiscoveryService().discoverForRetrieval(plannerId);
        System.assert(graph.agentsById.containsKey(String.valueOf(plannerId)), 'Fixture requires an Agent Script publication.');
        System.assert(!graph.topics.isEmpty(), 'Fixture requires at least one published topic.');
        OhmSourceImportService.SourceBundle bundle = new OhmSourceImportService.SourceBundle();
        bundle.schemaVersion = 1;
        bundle.plannerId = String.valueOf(plannerId);
        bundle.plannerApiName = graph.agentsById.get(bundle.plannerId).developerName;
        bundle.metadataFingerprint = graph.metadataFingerprint;
        bundle.sourceRevision = 'synthetic-readout-fixture';
        bundle.provenance = 'Imported';
        bundle.artifacts = new List<OhmSourceImportService.SourceArtifact>();
        bundle.artifacts.add(source(graph.agentsById.get(bundle.plannerId).id,
            'Help users obtain forecasts and weather alerts.', 'agent'));
        Boolean addedBloat = false;
        for (OhmDTO.TopicNode topic : graph.topics) {
            bundle.artifacts.add(source(topic.id, addedBloat ? 'Preserve this topic routing and actions.' :
                'Ask for location. Retrieve forecast. Preserve the alert branch. '.repeat(90), topic.developerName));
            addedBloat = true;
        }
        insert new Ohm_Instruction_Source__c(Planner_Id__c = bundle.plannerId,
            Metadata_Fingerprint__c = bundle.metadataFingerprint, Source_Revision__c = bundle.sourceRevision,
            Provenance__c = 'Imported', Manifest__c = JSON.serialize(bundle));
    }

    private static OhmSourceImportService.SourceArtifact source(String id, String instructions, String fragment) {
        OhmSourceImportService.SourceArtifact artifact = new OhmSourceImportService.SourceArtifact();
        artifact.id = id; artifact.instructions = instructions;
        artifact.sourceKind = 'ImportedAgentScript'; artifact.sourceVersion = 'synthetic-readout-fixture';
        artifact.sourcePath = 'test-fixture.agent#' + fragment;
        artifact.sourceHash = OhmSourceImportService.sha256(instructions);
        artifact.sourceBindingVerified = false;
        return artifact;
    }

    public static Id auditProcess(Id plannerId) {
        seedInstructionFixture(plannerId);
        OhmDTO.AgentModel graph = new OhmDiscoveryService().discoverProcess(plannerId);
        String apiName = graph.agentsById.get(String.valueOf(plannerId)).developerName;
        Id reportId = new OhmPersistenceService().createProcessReport(plannerId, apiName);
        OhmAuditRunService.finish(reportId, graph);
        return reportId;
    }
    public static Id startAudit() {
        seedInstructionFixture(scriptPlannerId());
        Id reportId = new OhmPersistenceService().createReport();
        OhmAuditRunService.finish(reportId, new OhmDiscoveryService().discover());
        return reportId;
    }
}
