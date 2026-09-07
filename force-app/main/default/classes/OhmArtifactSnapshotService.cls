/** Immutable report-scoped source evidence, including artifacts with no findings. */
public with sharing class OhmArtifactSnapshotService {
    private static final Integer SOURCE_LIMIT = 131072;

    public static void capture(Id reportId, OhmDTO.AgentModel graph, String reportProcessKey) {
        if (graph == null) { return; }
        List<Audit_Artifact_Snapshot__c> snapshots = new List<Audit_Artifact_Snapshot__c>();
        Map<String, String> processById = new Map<String, String>();
        Map<String, String> topicById = new Map<String, String>();
        Map<String, String> processByTopicId = new Map<String, String>();
        if (graph.agentsById != null) {
            for (OhmDTO.AgentNode node : graph.agentsById.values()) {
                if (node == null) { continue; }
                String processKey = OhmPersistenceService.logicalProcessKey(node.developerName, node.id);
                processById.put(node.id, processKey);
                snapshots.add(snapshot(reportId, processKey, 'Agent', node.developerName, node.masterLabel,
                    null, node.instructions, node.sourceKind, node.sourceVersion, node.sourcePath, node.sourceApiName, node.sourceVersionIdentifier, node.sourceRetrievedAt, node.sourceBindingVerified, graph));
            }
        }
        if (graph.topics != null) {
            for (OhmDTO.TopicNode node : graph.topics) {
                if (node == null) { continue; }
                topicById.put(node.id, node.developerName);
                String processKey = processById.get(node.plannerId);
                if (String.isBlank(processKey)) { processKey = reportProcessKey; }
                processByTopicId.put(node.id, processKey);
                snapshots.add(snapshot(reportId, processKey, 'Topic', node.developerName, node.masterLabel,
                    null, node.instructions, node.sourceKind, node.sourceVersion, node.sourcePath, node.sourceApiName, node.sourceVersionIdentifier, node.sourceRetrievedAt, node.sourceBindingVerified, graph));
            }
        }
        if (graph.actions != null) {
            for (OhmDTO.ActionNode node : graph.actions) {
                if (node == null) { continue; }
                String processKey = processById.get(node.plannerId);
                if (String.isBlank(processKey)) { processKey = reportProcessKey; }
                if (String.isBlank(processKey)) { processKey = processByTopicId.get(node.pluginId); }
                snapshots.add(snapshot(reportId, processKey, 'Action', node.developerName, node.masterLabel,
                    topicById.get(node.pluginId), node.instructions, node.sourceKind, node.sourceVersion, node.sourcePath, node.sourceApiName, node.sourceVersionIdentifier, node.sourceRetrievedAt, node.sourceBindingVerified, graph));
            }
        }
        // capture is deliberately idempotent for retries before report completion.
        List<Audit_Artifact_Snapshot__c> existing = [
            SELECT Id FROM Audit_Artifact_Snapshot__c WHERE Agent_Audit_Report__c = :reportId
        ];
        if (!existing.isEmpty()) { return; } // report evidence is immutable; retry needs no delete permission
        if (!snapshots.isEmpty()) { insert snapshots; }
    }

    private static Audit_Artifact_Snapshot__c snapshot(Id reportId, String processKey,
            String artifactType, String apiName, String label, String parentTopic,
            String instructions, String sourceKind, String sourceVersion, String sourcePath, String sourceApiName, String sourceVersionIdentifier, Datetime sourceRetrievedAt, Boolean sourceBindingVerified, OhmDTO.AgentModel graph) {
        String encodedSource = instructions == null ? null : JSON.serialize(instructions);
        Boolean oversized = encodedSource != null && encodedSource.length() > SOURCE_LIMIT;
        if (oversized) {
            graph.coverageComplete = false;
            if (graph.detectorCoverage != null) { graph.detectorCoverage.put('INSTRUCTION_BLOAT', 'Unknown'); }
            String warning = 'Source exceeds snapshot capacity: ' + apiName + '. No partial rewrite or comparison is available.';
            if (graph.discoveryErrors == null) { graph.discoveryErrors = new List<String>(); }
            graph.discoveryErrors.add(warning);
            if (graph.coverageWarnings == null) { graph.coverageWarnings = new List<String>(); }
            graph.coverageWarnings.add(warning);
        }
        return new Audit_Artifact_Snapshot__c(
            Agent_Audit_Report__c = reportId,
            Process_Key__c = processKey,
            Artifact_Key__c = OhmPersistenceService.artifactKey(processKey, artifactType, apiName, parentTopic),
            Artifact_Type__c = artifactType,
            Artifact_Api_Name__c = shorten(apiName, 255),
            Artifact_Label__c = shorten(label, 255),
            Instructions__c = oversized ? null : instructions,
            Source_Json__c = oversized ? null : encodedSource,
            Character_Count__c = instructions == null ? null : instructions.length(),
            Source_Hash__c = instructions == null ? null : OhmPersistenceService.sha256(instructions),
            Source_Kind__c = shorten(sourceKind, 100),
            Source_Version__c = shorten(sourceVersion, 255),
            Source_Path__c = shorten(sourcePath, 255),
            Source_Api_Name__c = shorten(sourceApiName, 255),
            Source_Version_Identifier__c = shorten(sourceVersionIdentifier, 255),
            Source_Retrieved_At__c = sourceRetrievedAt,
            Source_Binding_Verified__c = sourceBindingVerified == true,
            Coverage_Status__c = oversized ? 'Unsupported size' : instructions == null ? 'Unavailable' : 'Complete'
        );
    }

    public static Map<Id, Map<String, Audit_Artifact_Snapshot__c>> load(Set<Id> reportIds) {
        Map<Id, Map<String, Audit_Artifact_Snapshot__c>> result = new Map<Id, Map<String, Audit_Artifact_Snapshot__c>>();
        if (reportIds == null || reportIds.isEmpty()) { return result; }
        for (Audit_Artifact_Snapshot__c row : [
            SELECT Id, Agent_Audit_Report__c, Process_Key__c, Artifact_Key__c, Artifact_Type__c,
                   Artifact_Api_Name__c, Artifact_Label__c, Instructions__c, Source_Json__c, Character_Count__c,
                   Source_Hash__c, Source_Kind__c, Source_Version__c, Source_Path__c, Coverage_Status__c,
                   Source_Api_Name__c, Source_Version_Identifier__c, Source_Retrieved_At__c, Source_Binding_Verified__c
            FROM Audit_Artifact_Snapshot__c WHERE Agent_Audit_Report__c IN :reportIds
            ORDER BY Artifact_Key__c, CreatedDate DESC, Id DESC
        ]) {
            // Long text storage may trim source-edge whitespace. The JSON string ends in
            // quotes, so it preserves the exact audited bytes for display and hash checking.
            try {
                if (String.isNotBlank(row.Source_Json__c)) {
                    row.Instructions__c = (String) JSON.deserialize(row.Source_Json__c, String.class);
                }
                if (row.Coverage_Status__c == 'Complete' &&
                    (row.Instructions__c == null || String.isBlank(row.Source_Hash__c)
                     || OhmPersistenceService.sha256(row.Instructions__c) != row.Source_Hash__c)) {
                    row.Coverage_Status__c = 'Source hash mismatch';
                    row.Instructions__c = null;
                }
            } catch (Exception invalidSource) {
                row.Coverage_Status__c = 'Invalid stored source';
                row.Instructions__c = null;
            }
            if (!result.containsKey(row.Agent_Audit_Report__c)) {
                result.put(row.Agent_Audit_Report__c, new Map<String, Audit_Artifact_Snapshot__c>());
            }
            if (!result.get(row.Agent_Audit_Report__c).containsKey(row.Artifact_Key__c)) {
                result.get(row.Agent_Audit_Report__c).put(row.Artifact_Key__c, row);
            }
        }
        return result;
    }

    private static String shorten(String value, Integer maximum) {
        return value == null ? null : value.abbreviate(maximum);
    }
}
