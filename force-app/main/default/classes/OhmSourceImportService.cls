/**
 * Explicit versioned source import for instruction text not exposed by inline metadata SOQL.
 * A manifest is an operator-provided source snapshot, never a claim of live runtime telemetry.
 * Imported text applies only to the exact planner and observed metadata fingerprint. Republishing
 * invalidates it. History remains append-only; audit reports retain their own source snapshots.
 */
public with sharing class OhmSourceImportService {
    public class SourceArtifact {
        public String id;
        public String instructions;
        public String sourceKind;
        public String sourceVersion;
        public String sourceHash;
        public String sourcePath;
        public String boundModel;
        public String sourceApiName;
        public String sourceVersionId;
        public String sourceVersionIdentifier;
        public Datetime sourceRetrievedAt;
        public Boolean sourceBindingVerified;
        public String dependencyFingerprint;
    }
    public class SourceBundle {
        public String configurationSource;
        public String configurationSourcePath;
        public String configurationSourceHash;
        public Integer schemaVersion;
        public String plannerId;
        public String plannerApiName;
        public String metadataFingerprint;
        public String sourceRevision;
        public List<SourceArtifact> artifacts;
        public List<String> warnings;
        public String provenance;
        public Datetime retrievedAt;
    }
    public class SourceImportException extends Exception {}

    /** Used by the CLI importer; explicit import authorization comes from the invoking user. */
    public static Id importBundle(String manifest) {
        if (String.isBlank(manifest) || manifest.length() > 131072) {
            throw new SourceImportException('Source manifest must contain 1–131072 characters. Split unsupported large sources before import.');
        }
        SourceBundle bundle = (SourceBundle)JSON.deserializeStrict(manifest, SourceBundle.class);
        if (bundle.schemaVersion != 1 || String.isBlank(bundle.plannerId)
            || String.isBlank(bundle.sourceRevision) || bundle.artifacts == null || bundle.artifacts.isEmpty()) {
            throw new SourceImportException('Schema version, planner identity, source revision and artifacts are required.');
        }
        bundle.provenance = 'Imported';
        for (SourceArtifact artifact : bundle.artifacts) artifact.sourceBindingVerified = false;
        return storeBundle(bundle, new OhmDiscoveryService().discoverForRetrieval((Id)bundle.plannerId));
    }

    /** Trusted server retrieval adapter only: never exposed as an Aura/Flow import endpoint. */
    public static Id importRetrievedBundle(SourceBundle bundle, OhmDTO.AgentModel currentGraph) {
        if (bundle == null || bundle.provenance != 'Retrieved' || bundle.retrievedAt == null) {
            throw new SourceImportException('Retrieved source requires platform acquisition provenance.');
        }
        return storeBundle(bundle, currentGraph);
    }

    private static Id storeBundle(SourceBundle bundle, OhmDTO.AgentModel graph) {
        if (bundle.schemaVersion != 1 || graph == null || !graph.agentsById.containsKey(bundle.plannerId)
            || graph.metadataFingerprint != bundle.metadataFingerprint
            || graph.agentsById.get(bundle.plannerId).developerName != bundle.plannerApiName
            || String.isBlank(bundle.sourceRevision) || bundle.artifacts == null) {
            throw new SourceImportException('Source manifest does not match the current planner metadata. Refresh the source and retry.');
        }
        if (!validConfiguration(bundle)) {
            throw new SourceImportException('Bundle configuration failed its source integrity check.');
        }
        Set<String> validIds = new Set<String>(graph.agentsById.keySet());
        for (OhmDTO.TopicNode t : graph.topics) validIds.add(t.id);
        for (OhmDTO.ActionNode a : graph.actions) validIds.add(a.id);
        Set<String> seen = new Set<String>();
        for (SourceArtifact a : bundle.artifacts) {
            if (a == null || !validIds.contains(a.id) || seen.contains(a.id) || a.instructions == null
                || String.isBlank(a.sourcePath) || String.isBlank(a.sourceVersion)
                || String.isBlank(a.sourceKind) || sha256(a.instructions) != a.sourceHash) {
                throw new SourceImportException('Source contains an invalid, duplicated, foreign or hash-mismatched artifact.');
            }
            seen.add(a.id);
        }
        String manifest = JSON.serialize(bundle);
        if (manifest.length() > 131072) throw new SourceImportException('Retrieved source exceeds the 131072-character manifest capacity. No truncated source was stored.');
        Ohm_Instruction_Source__c record = new Ohm_Instruction_Source__c(
            Planner_Id__c = bundle.plannerId, Metadata_Fingerprint__c = bundle.metadataFingerprint,
            Source_Revision__c = bundle.sourceRevision, Manifest__c = manifest,
            Provenance__c = bundle.provenance, Retrieved_At__c = bundle.retrievedAt
        );
        insert record;
        return record.Id;
    }

    public static void applySources(OhmDTO.AgentModel graph, Map<String, String> metadataVersions) {
        Set<String> ids = graph.agentsById.keySet();
        if (ids.isEmpty()) return;
        try {
            applyRows(graph, metadataVersions, [
                SELECT Planner_Id__c, Metadata_Fingerprint__c, Manifest__c
                FROM Ohm_Instruction_Source__c WHERE Planner_Id__c IN :ids
                ORDER BY CreatedDate DESC, Id DESC LIMIT 1000
            ], false);
        } catch (Exception ex) {
            graph.coverageWarnings.add('Instruction source snapshots unavailable: ' + ex.getMessage());
        }
    }

    public static void applyPinnedSources(OhmDTO.AgentModel graph, Map<String, String> metadataVersions, Set<Id> sourceIds) {
        if (sourceIds == null || sourceIds.isEmpty()) return;
        List<Ohm_Instruction_Source__c> rows = [
            SELECT Planner_Id__c, Metadata_Fingerprint__c, Manifest__c
            FROM Ohm_Instruction_Source__c WHERE Id IN :sourceIds
        ];
        if (rows.size() != sourceIds.size()) throw new SourceImportException('Audit source evidence is missing. Start a new audit.');
        applyRows(graph, metadataVersions, rows, true);
    }

    private static void applyRows(OhmDTO.AgentModel graph, Map<String, String> metadataVersions,
                                  List<Ohm_Instruction_Source__c> rows, Boolean strict) {
        Map<String, SourceBundle> byPlanner = new Map<String, SourceBundle>();
        for (Ohm_Instruction_Source__c row : rows) {
            if (byPlanner.containsKey(row.Planner_Id__c)) continue;
            SourceBundle bundle = (SourceBundle)JSON.deserialize(row.Manifest__c, SourceBundle.class);
            if (bundle == null || bundle.schemaVersion != 1 || bundle.plannerId != row.Planner_Id__c
                || bundle.metadataFingerprint != row.Metadata_Fingerprint__c || bundle.artifacts == null
                || !graph.agentsById.containsKey(bundle.plannerId)) {
                if (strict) throw new SourceImportException('Pinned audit source manifest is invalid. Start a new audit.');
                byPlanner.put(row.Planner_Id__c, null);
                graph.coverageWarnings.add('Invalid source manifest for ' + row.Planner_Id__c);
                continue;
            }
            byPlanner.put(row.Planner_Id__c, bundle);
        }
        for (String plannerId : byPlanner.keySet()) {
            OhmDTO.AgentModel scoped = new OhmDTO.AgentModel();
            scoped.agentsById.put(plannerId, graph.agentsById.get(plannerId));
            for (OhmDTO.TopicNode t : graph.topics) { if (t.plannerId == plannerId) { scoped.topics.add(t); } }
            for (OhmDTO.ActionNode a : graph.actions) { if (a.plannerId == plannerId) { scoped.actions.add(a); } }
            SourceBundle bundle = byPlanner.get(plannerId);
            if (bundle == null) { continue; }
            if (bundle.metadataFingerprint != OhmDiscoveryService.fingerprint(scoped, metadataVersions)) {
                if (strict) throw new SourceImportException('Pinned audit source no longer matches this publication. Start a new audit.');
                graph.coverageWarnings.add('Source snapshot is stale for ' + graph.agentsById.get(plannerId).developerName + '; refresh after metadata publication.');
                continue;
            }
            Map<String, SourceArtifact> sources = new Map<String, SourceArtifact>();
            Boolean validContent = validConfiguration(bundle);
            for (SourceArtifact a : bundle.artifacts) {
                if (a == null || a.instructions == null || sha256(a.instructions) != a.sourceHash || sources.containsKey(a.id)) {
                    validContent = false; break;
                }
                sources.put(a.id, a);
            }
            if (!validContent) {
                if (strict) throw new SourceImportException('Pinned audit source failed its integrity check. Start a new audit.');
                graph.coverageWarnings.add('Source snapshot content failed integrity checks for ' + plannerId);
                continue;
            }
            if (bundle.warnings != null) { graph.coverageWarnings.addAll(bundle.warnings); }
            for (OhmDTO.AgentNode node : scoped.agentsById.values()) {
                SourceArtifact s = sources.get(node.id);
                if (s == null) { continue; }
                node.instructions = s.instructions; node.sourceKind = s.sourceKind;
                node.sourceVersion = s.sourceVersion; node.sourceHash = s.sourceHash; node.sourcePath = s.sourcePath;
                node.sourceApiName = s.sourceApiName; node.sourceVersionIdentifier = s.sourceVersionIdentifier;
                node.sourceRetrievedAt = s.sourceRetrievedAt; node.sourceBindingVerified = bundle.provenance == 'Retrieved' && s.sourceBindingVerified == true;
                if (node.sourceBindingVerified == true) {
                    node.configurationSource = bundle.configurationSource;
                    node.configurationSourcePath = bundle.configurationSourcePath;
                    node.configurationSourceHash = bundle.configurationSourceHash;
                }
            }
            for (OhmDTO.TopicNode node : scoped.topics) {
                SourceArtifact s = sources.get(node.id);
                if (s == null) { continue; }
                node.instructions = s.instructions; node.scope = s.instructions; node.sourceKind = s.sourceKind;
                node.sourceVersion = s.sourceVersion; node.sourceHash = s.sourceHash; node.sourcePath = s.sourcePath;
                node.sourceApiName = s.sourceApiName; node.sourceVersionIdentifier = s.sourceVersionIdentifier;
                node.sourceRetrievedAt = s.sourceRetrievedAt; node.sourceBindingVerified = bundle.provenance == 'Retrieved' && s.sourceBindingVerified == true;
            }
            for (OhmDTO.ActionNode node : scoped.actions) {
                SourceArtifact s = sources.get(node.id);
                if (s == null) { continue; }
                node.instructions = s.instructions; node.sourceKind = s.sourceKind;
                node.sourceVersion = s.sourceVersion; node.sourceHash = s.sourceHash; node.sourcePath = s.sourcePath;
                node.sourceApiName = s.sourceApiName; node.sourceVersionIdentifier = s.sourceVersionIdentifier;
                node.sourceRetrievedAt = s.sourceRetrievedAt; node.sourceBindingVerified = bundle.provenance == 'Retrieved' && s.sourceBindingVerified == true;
                node.boundModel = s.boundModel;
                // A platform retrieval verifies the binding at snapshot time, never continuously.
                node.modelAssumed = !(bundle.provenance == 'Retrieved' && s.sourceBindingVerified == true);
            }
        }
    }

    public static String sha256(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value)));
    }
    private static Boolean validConfiguration(SourceBundle bundle) {
        if (bundle.configurationSource == null) {
            return bundle.configurationSourcePath == null && bundle.configurationSourceHash == null;
        }
        return bundle.configurationSource.length() <= OhmSourceParser.MAX_SOURCE_CHARS
            && String.isNotBlank(bundle.configurationSourcePath)
            && sha256(bundle.configurationSource) == bundle.configurationSourceHash;
    }
}
