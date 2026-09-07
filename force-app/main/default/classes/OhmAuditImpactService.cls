/** Modeled instruction-input scope, independent of whether any waste was found.
 * Each distinct instruction artifact is counted once at the disclosed usage scenario.
 * Output tokens, runtime branching, tool compute and real usage are not measured.
 */
public with sharing class OhmAuditImpactService {
    public static final String SCOPE = 'Modeled instruction-source scenario';
    public class Snapshot {
        public String scope = OhmAuditImpactService.SCOPE;
        public String assumptionSummary;
        public String comparisonKey;
        public Integer artifactCount = 0;
        public Map<String, Object> artifactAssumptions = new Map<String, Object>();
        public OhmDTO.FootprintResponse baseline;
        public OhmDTO.FootprintResponse afterScenario;
        public OhmDTO.FootprintResponse savings;
    }
    private class InputBlock {
        String id; String key; String type; String instructions; String model; Boolean assumed;
        InputBlock(String id, String key, String type, String instructions, String model, Boolean assumed) {
            this.id = id; this.key = key; this.type = type;
            this.instructions = instructions; this.model = model;
            this.assumed = assumed;
        }
    }
    public static Snapshot compute(OhmDTO.AgentModel graph, List<OhmDTO.Finding> findings, OhmDTO.VolumeInput volume) {
        AssumptionVolumeProvider provider = new AssumptionVolumeProvider();
        if (volume == null) { volume = provider.defaultVolume(); }
        Decimal calls = provider.annualCalls(volume);
        OhmFootprintService engine = new OhmFootprintService();
        List<OhmDTO.FootprintResponse> beforeParts = new List<OhmDTO.FootprintResponse>();
        List<OhmDTO.FootprintResponse> afterParts = new List<OhmDTO.FootprintResponse>();
        Map<String, Object> artifactAssumptions = new Map<String, Object>();
        Map<String, InputBlock> blocks = new Map<String, InputBlock>();
        if (graph != null) {
            for (OhmDTO.AgentNode a : graph.agentsById.values()) {
                add(blocks, new InputBlock(a.id, key(a.developerName, a.id, 'Agent', a.developerName, null), 'Agent', a.instructions, null, true));
            }
            for (OhmDTO.TopicNode t : graph.topics) {
                OhmDTO.AgentNode a = graph.agentsById.get(t.plannerId);
                add(blocks, new InputBlock(t.id, key(a == null ? null : a.developerName, t.plannerId, 'Topic', t.developerName, null),
                    'Topic', String.isNotBlank(t.instructions) ? t.instructions : t.scope, null, true));
            }
            for (OhmDTO.ActionNode action : graph.actions) {
                OhmDTO.AgentNode a = graph.agentsById.get(action.plannerId);
                add(blocks, new InputBlock(action.id, key(a == null ? null : a.developerName, action.plannerId, 'Action', action.developerName, null),
                    'Action', action.instructions, action.boundModel, action.modelAssumed));
            }
        }
        Set<String> trimIds = new Set<String>();
        if (findings != null) {
            for (OhmDTO.Finding f : findings) {
                if (f.signalType == InstructionBloatDetector.SIGNAL && f.reviewRequired != true) {
                    trimIds.add(f.artifactToolingId);
                }
            }
        }
        List<String> signatures = new List<String>();
        for (InputBlock block : blocks.values()) {
            OhmDTO.FootprintRequest request = new OhmDTO.FootprintRequest();
            request.artifactId = block.id; request.artifactType = block.type;
            request.tokensPerInference = TokenEstimator.approxTokens(block.instructions);
            request.annualCalls = calls; request.boundModel = block.model;
            request.modelAssumed = block.assumed == true || ModelRegistry.lookup(block.model).assumed;
            OhmDTO.FootprintResponse before = engine.estimate(request);
            beforeParts.add(before);
            artifactAssumptions.put(block.key, before.assumptions);
            if (trimIds.contains(block.id)) {
                request.tokensPerInference = Math.min(request.tokensPerInference, OhmConstants.load().softThresholdFor(block.type));
            }
            afterParts.add(engine.estimate(request));
            signatures.add(block.key + ':' + ModelRegistry.lookup(block.model).tier + ':' + String.valueOf(request.modelAssumed));
        }
        Snapshot result = new Snapshot();
        result.artifactCount = blocks.size();
        result.artifactAssumptions = artifactAssumptions;
        result.baseline = engine.sumAll(beforeParts);
        result.afterScenario = engine.sumAll(afterParts);
        result.savings = difference(result.baseline, result.afterScenario);
        signatures.sort();
        result.comparisonKey = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(
            SCOPE + '|' + OhmConstants.load().methodologyVersion() + '|' + calls + '|' + String.join(signatures, '|'))));
        result.assumptionSummary = String.valueOf(calls) + ' modeled calls/year per source block; '
            + 'source characters / 4 approximate tokens. Conditional branches and dynamic outputs are not executed. '
            + 'Unknown models use standard multiplier 1.0; reference cost is '
            + OhmConstants.load().energyPerPromptWh().central + ' Wh per '
            + OhmConstants.load().referencePromptTokens() + ' tokens. Low confidence. '
            + 'Excludes output tokens, tool compute and actual runtime frequency. Potential savings cover instruction trimming only.';
        result.baseline.assumptions.put('scope', SCOPE);
        result.baseline.assumptions.put('summary', result.assumptionSummary);
        result.baseline.assumptions.put('annualCallsPerArtifact', calls);
        result.baseline.assumptions.put('artifactCount', result.artifactCount);
        result.baseline.assumptions.put('methodologyVersion', OhmConstants.load().methodologyVersion());
        return result;
    }
    public static void save(Id reportId, OhmDTO.AgentModel graph, List<OhmDTO.Finding> findings, OhmDTO.VolumeInput volume) {
        Snapshot data = compute(graph, findings, volume);
        Boolean available = data.artifactCount > 0;
        update new Agent_Audit_Report__c(Id = reportId,
            Modeled_Energy_Wh__c = available ? data.baseline.energyWhCentral : null,
            Modeled_Energy_Wh_Low__c = available ? data.baseline.energyWhLow : null,
            Modeled_Energy_Wh_High__c = available ? data.baseline.energyWhHigh : null,
            Modeled_Savings_Wh__c = available ? data.savings.energyWhCentral : null,
            Modeled_Savings_Wh_Low__c = available ? data.savings.energyWhLow : null,
            Modeled_Savings_Wh_High__c = available ? data.savings.energyWhHigh : null,
            Impact_Snapshot__c = JSON.serialize(data),
            Coverage_Status__c = graph != null && graph.coverageComplete == true
                && graph.discoveryErrors.isEmpty() ? 'Complete' : 'Incomplete');
    }
    public static Boolean comparable(String beforeJson, String afterJson) {
        if (String.isBlank(beforeJson) || String.isBlank(afterJson)) { return false; }
        try {
            Snapshot before = readSnapshot(beforeJson);
            Snapshot after = readSnapshot(afterJson);
            return before.artifactCount > 0 && after.artifactCount > 0
                && String.isNotBlank(before.comparisonKey) && before.comparisonKey == after.comparisonKey;
        } catch (Exception e) { return false; }
    }
    /** Constants behind every modeled figure, disclosed next to the numbers in the UI. */
    public static Map<String, Object> factors() {
        OhmConstants c = OhmConstants.load();
        return new Map<String, Object>{
            'energyPerPromptWh' => band(c.energyPerPromptWh()),
            'gridIntensityGco2ePerWh' => band(c.gridIntensityGco2ePerWh()),
            'waterMlPerWh' => band(c.waterMlPerWh()),
            'referencePromptTokens' => c.referencePromptTokens(),
            'charsPerToken' => c.charsPerToken(),
            'methodologyVersion' => c.methodologyVersion(),
            'telemetryBacked' => false,
            'confidence' => 'Low'
        };
    }
    private static Map<String, Object> band(OhmConstants.Band b) {
        return new Map<String, Object>{ 'low' => b.low, 'central' => b.central, 'high' => b.high };
    }

    /** Modeled bands plus the requests/year they assume, read from a saved Impact snapshot. */
    public class Bands {
        public Decimal annualCalls;
        public OhmDTO.FootprintResponse baseline;
        public OhmDTO.FootprintResponse savings;
    }
    public static Bands readBands(String snapshotJson) {
        if (String.isBlank(snapshotJson)) { return null; }
        Snapshot data;
        try { data = readSnapshot(snapshotJson); } catch (Exception e) { return null; }
        if (data == null || data.baseline == null || data.artifactCount == null || data.artifactCount == 0) { return null; }
        Bands result = new Bands();
        result.baseline = data.baseline;
        result.savings = data.savings;
        Object perArtifact = data.baseline.assumptions == null ? null : data.baseline.assumptions.get('annualCallsPerArtifact');
        if (perArtifact != null) {
            result.annualCalls = Decimal.valueOf(String.valueOf(perArtifact));
        } else if (data.baseline.annualCalls != null) {
            result.annualCalls = data.baseline.annualCalls / data.artifactCount;
        }
        return result;
    }
    /** Fleet rows carry the same disclosed bands as the bundle page. */
    public static void applyBands(OhmDTO.ProcessSummaryDTO row, String snapshotJson) {
        Bands b = readBands(snapshotJson);
        row.impactFactors = factors();
        if (b == null) { return; }
        row.annualCalls = b.annualCalls;
        if (b.baseline != null) {
            row.co2eGLow = b.baseline.co2eGLow; row.co2eGCentral = b.baseline.co2eGCentral; row.co2eGHigh = b.baseline.co2eGHigh;
            row.waterMlLow = b.baseline.waterMlLow; row.waterMlCentral = b.baseline.waterMlCentral; row.waterMlHigh = b.baseline.waterMlHigh;
            if (b.baseline.assumptions != null && b.baseline.assumptions.get('summary') != null) {
                row.impactAssumptions = String.valueOf(b.baseline.assumptions.get('summary'));
            }
        }
        if (b.savings != null) {
            row.savingsWhLow = b.savings.energyWhLow; row.savingsWhCentral = b.savings.energyWhCentral; row.savingsWhHigh = b.savings.energyWhHigh;
        }
    }
    public static void applyBands(OhmDTO.ProcessDetailDTO detail, String snapshotJson) {
        Bands b = readBands(snapshotJson);
        detail.impactFactors = factors();
        if (b == null) { return; }
        detail.annualCalls = b.annualCalls;
        if (b.baseline != null) {
            detail.co2eGLow = b.baseline.co2eGLow; detail.co2eGCentral = b.baseline.co2eGCentral; detail.co2eGHigh = b.baseline.co2eGHigh;
            detail.waterMlLow = b.baseline.waterMlLow; detail.waterMlCentral = b.baseline.waterMlCentral; detail.waterMlHigh = b.baseline.waterMlHigh;
        }
        if (b.savings != null) {
            detail.savingsWhLow = b.savings.energyWhLow; detail.savingsWhCentral = b.savings.energyWhCentral; detail.savingsWhHigh = b.savings.energyWhHigh;
        }
    }
    /** Apex cannot deserialize Object-valued assumption maps into a typed DTO. */
    public static Snapshot readSnapshot(String encoded) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(encoded);
        Snapshot result = new Snapshot();
        result.scope = (String) data.get('scope');
        result.assumptionSummary = (String) data.get('assumptionSummary');
        result.comparisonKey = (String) data.get('comparisonKey');
        result.artifactCount = Integer.valueOf(String.valueOf(data.get('artifactCount')));
        result.artifactAssumptions = (Map<String, Object>) data.get('artifactAssumptions');
        result.baseline = readFootprint(data.get('baseline'));
        result.afterScenario = readFootprint(data.get('afterScenario'));
        result.savings = readFootprint(data.get('savings'));
        return result;
    }
    private static OhmDTO.FootprintResponse readFootprint(Object raw) {
        if (raw == null) return null;
        Map<String, Object> data = (Map<String, Object>) raw;
        Map<String, Object> assumptions = (Map<String, Object>) data.remove('assumptions');
        OhmDTO.FootprintResponse response = (OhmDTO.FootprintResponse)
            JSON.deserialize(JSON.serialize(data), OhmDTO.FootprintResponse.class);
        response.assumptions = assumptions;
        return response;
    }
    private static void add(Map<String, InputBlock> blocks, InputBlock block) {
        if (String.isNotBlank(block.instructions)) { blocks.put(block.key, block); }
    }
    private static String key(String planner, String plannerId, String type, String name, String parent) {
        return OhmPersistenceService.artifactKey(OhmPersistenceService.logicalProcessKey(planner, plannerId), type, name, parent);
    }
    private static OhmDTO.FootprintResponse difference(OhmDTO.FootprintResponse before, OhmDTO.FootprintResponse after) {
        OhmDTO.FootprintResponse out = new OhmDTO.FootprintResponse();
        out.energyWhLow = before.energyWhLow - after.energyWhLow;
        out.energyWhCentral = before.energyWhCentral - after.energyWhCentral;
        out.energyWhHigh = before.energyWhHigh - after.energyWhHigh;
        out.waterMlLow = before.waterMlLow - after.waterMlLow;
        out.waterMlCentral = before.waterMlCentral - after.waterMlCentral;
        out.waterMlHigh = before.waterMlHigh - after.waterMlHigh;
        out.co2eGLow = before.co2eGLow - after.co2eGLow;
        out.co2eGCentral = before.co2eGCentral - after.co2eGCentral;
        out.co2eGHigh = before.co2eGHigh - after.co2eGHigh;
        out.telemetryBacked = false; out.confidence = 'Low';
        return out;
    }
}
