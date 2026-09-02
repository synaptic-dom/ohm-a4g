/**
 * OhmConstants — loads the Ohm_Constants StaticResource JSON (SPEC §A.3) with
 * memoization (one SOQL per transaction) and source-cited static-final fallbacks
 * for EVERY leaf, so the deterministic core works even if the resource is not yet
 * deployed. No CMDT. Canon C6/C7/C8.
 */
public with sharing class OhmConstants {

    public class Band {
        public Decimal low;
        public Decimal central;
        public Decimal high;
        public Band(Decimal l, Decimal c, Decimal h) { low = l; central = c; high = h; }
    }

    // ---- Source-cited static-final fallbacks (identical numbers to §A.3.1) ----
    @TestVisible private static final Decimal ENERGY_LOW_WH = 0.24;
    @TestVisible private static final Decimal ENERGY_CENTRAL_WH = 0.27; // Epoch AI GPT-4o / Gemini 2025 median
    @TestVisible private static final Decimal ENERGY_HIGH_WH = 0.30;
    @TestVisible private static final Decimal GRID_LOW = 0.125;
    @TestVisible private static final Decimal GRID_CENTRAL = 0.30;
    @TestVisible private static final Decimal GRID_HIGH = 0.475;
    @TestVisible private static final Decimal WATER_LOW_ML = 0.8;
    @TestVisible private static final Decimal WATER_CENTRAL_ML = 1.08;
    @TestVisible private static final Decimal WATER_HIGH_ML = 1.4;
    @TestVisible private static final Integer REFERENCE_PROMPT_TOKENS = 500;
    @TestVisible private static final Integer TYPICAL_OUTPUT_TOKENS = 250;
    @TestVisible private static final Decimal OUTPUT_WEIGHT = 1.0;
    @TestVisible private static final Decimal CHARS_PER_TOKEN = 4.0;
    @TestVisible private static final Integer TOPIC_SCOPE_SOFT = 500;
    @TestVisible private static final Integer TOPIC_SCOPE_HARD = 1000;
    @TestVisible private static final Integer AGENT_SOFT = 400;
    @TestVisible private static final Integer AGENT_HARD = 800;
    @TestVisible private static final Integer ACTION_SOFT = 150;
    @TestVisible private static final Integer ACTION_HARD = 300;
    @TestVisible private static final String METHODOLOGY_VERSION = '1.0';

    // ---- memoized singleton ----
    private static OhmConstants INSTANCE;

    private Map<String, Object> root;               // parsed JSON (may be empty)
    public List<String> fallbackNotes { get; private set; }

    private OhmConstants(Map<String, Object> parsed, List<String> notes) {
        this.root = (parsed == null) ? new Map<String, Object>() : parsed;
        this.fallbackNotes = (notes == null) ? new List<String>() : notes;
    }

    /** Memoized loader — one SOQL per transaction (NFR-1). */
    public static OhmConstants load() {
        if (INSTANCE != null) {
            return INSTANCE;
        }
        String raw;
        try {
            List<StaticResource> rs = [SELECT Body FROM StaticResource WHERE Name = 'Ohm_Constants' LIMIT 1];
            if (!rs.isEmpty() && rs[0].Body != null) {
                raw = rs[0].Body.toString();
            }
        } catch (Exception e) {
            raw = null;
        }
        INSTANCE = parseOrDefault(raw);
        return INSTANCE;
    }

    @TestVisible
    private static OhmConstants parseOrDefault(String rawJson) {
        List<String> notes = new List<String>();
        Map<String, Object> parsed;
        if (String.isBlank(rawJson)) {
            notes.add('Ohm_Constants resource missing/blank — using cited static-final defaults.');
            parsed = new Map<String, Object>();
        } else {
            try {
                parsed = (Map<String, Object>) JSON.deserializeUntyped(rawJson);
            } catch (Exception e) {
                notes.add('Ohm_Constants JSON unparseable — using cited static-final defaults.');
                parsed = new Map<String, Object>();
            }
        }
        return new OhmConstants(parsed, notes);
    }

    // ---------- typed accessors ----------

    public String methodologyVersion() {
        return strAt(new List<String>{ 'methodologyVersion' }, METHODOLOGY_VERSION);
    }

    public Decimal energyPerPromptWh(String band) {
        String b = (band == null) ? 'central' : band.toLowerCase();
        Decimal fb = (b == 'low') ? ENERGY_LOW_WH : (b == 'high' ? ENERGY_HIGH_WH : ENERGY_CENTRAL_WH);
        return decAt(new List<String>{ 'footprint', 'energyPerPromptWh', b }, fb);
    }

    public Band energyPerPromptWh() {
        return new Band(energyPerPromptWh('low'), energyPerPromptWh('central'), energyPerPromptWh('high'));
    }

    public Band gridIntensityGco2ePerWh() {
        return new Band(
            decAt(new List<String>{ 'footprint', 'gridIntensityGco2ePerWh', 'low' }, GRID_LOW),
            decAt(new List<String>{ 'footprint', 'gridIntensityGco2ePerWh', 'central' }, GRID_CENTRAL),
            decAt(new List<String>{ 'footprint', 'gridIntensityGco2ePerWh', 'high' }, GRID_HIGH)
        );
    }

    public Band waterMlPerWh() {
        return new Band(
            decAt(new List<String>{ 'footprint', 'waterMlPerWh', 'low' }, WATER_LOW_ML),
            decAt(new List<String>{ 'footprint', 'waterMlPerWh', 'central' }, WATER_CENTRAL_ML),
            decAt(new List<String>{ 'footprint', 'waterMlPerWh', 'high' }, WATER_HIGH_ML)
        );
    }

    public Integer referencePromptTokens() {
        return intAt(new List<String>{ 'footprint', 'referencePromptTokens' }, REFERENCE_PROMPT_TOKENS);
    }

    public Integer typicalOutputTokens() {
        return intAt(new List<String>{ 'footprint', 'typicalOutputTokens' }, TYPICAL_OUTPUT_TOKENS);
    }

    public Decimal outputWeight() {
        return decAt(new List<String>{ 'footprint', 'outputWeight' }, OUTPUT_WEIGHT);
    }

    public Decimal charsPerToken() {
        return decAt(new List<String>{ 'footprint', 'charsPerToken' }, CHARS_PER_TOKEN);
    }

    public Integer topicScopeSoftTokens() { return intAt(new List<String>{ 'thresholds', 'topicScopeSoftTokens' }, TOPIC_SCOPE_SOFT); }
    public Integer topicScopeHardTokens() { return intAt(new List<String>{ 'thresholds', 'topicScopeHardTokens' }, TOPIC_SCOPE_HARD); }
    public Integer agentSoftTokens() { return intAt(new List<String>{ 'thresholds', 'agentSoftTokens' }, AGENT_SOFT); }
    public Integer agentHardTokens() { return intAt(new List<String>{ 'thresholds', 'agentHardTokens' }, AGENT_HARD); }
    public Integer actionSoftTokens() { return intAt(new List<String>{ 'thresholds', 'actionSoftTokens' }, ACTION_SOFT); }
    public Integer actionHardTokens() { return intAt(new List<String>{ 'thresholds', 'actionHardTokens' }, ACTION_HARD); }

    /** Soft threshold for an artifact type ('Topic'|'Agent'|'Action'). */
    public Integer softThresholdFor(String artifactType) {
        String t = (artifactType == null) ? '' : artifactType.toLowerCase();
        if (t == 'agent') { return agentSoftTokens(); }
        if (t == 'action') { return actionSoftTokens(); }
        return topicScopeSoftTokens();
    }

    public Integer hardThresholdFor(String artifactType) {
        String t = (artifactType == null) ? '' : artifactType.toLowerCase();
        if (t == 'agent') { return agentHardTokens(); }
        if (t == 'action') { return actionHardTokens(); }
        return topicScopeHardTokens();
    }

    /** rateCardMultiplier by tier name or model API name — unknown => _baseline (MEDIUM=1.0). */
    public Decimal rateCardMultiplier(String modelTierOrName) {
        String tier = (modelTierOrName == null) ? '' : modelTierOrName.toUpperCase();
        Decimal m = multiplierForTier(tier);
        if (m != null) {
            return m;
        }
        // unknown => baseline tier
        String baseline = strAt(new List<String>{ 'modelMultipliers', '_baseline' }, 'MEDIUM');
        Decimal bm = multiplierForTier(baseline.toUpperCase());
        return (bm == null) ? 1.0 : bm;
    }

    private Decimal multiplierForTier(String tier) {
        if (tier != 'SMALL' && tier != 'MEDIUM' && tier != 'LARGE') {
            return null;
        }
        Decimal fb = (tier == 'SMALL') ? 0.5 : (tier == 'LARGE' ? 2.0 : 1.0);
        return decAt(new List<String>{ 'modelMultipliers', tier, 'rateCardMultiplier' }, fb);
    }

    public Integer rankForTier(String tier) {
        String t = (tier == null) ? 'MEDIUM' : tier.toUpperCase();
        Integer fb = (t == 'SMALL') ? 1 : (t == 'LARGE' ? 3 : 2);
        if (t != 'SMALL' && t != 'MEDIUM' && t != 'LARGE') {
            return 2;
        }
        return intAt(new List<String>{ 'modelMultipliers', t, 'rank' }, fb);
    }

    public String baselineTier() {
        return strAt(new List<String>{ 'modelMultipliers', '_baseline' }, 'MEDIUM');
    }

    /** default volume from volumeScenario (C6). */
    public OhmDTO.VolumeInput defaultVolume() {
        OhmDTO.VolumeInput v = new OhmDTO.VolumeInput();
        v.sessionsPerPeriod = decAt(new List<String>{ 'volumeScenario', 'sessionsPerDay' }, 50);
        v.turnsPerSession = decAt(new List<String>{ 'volumeScenario', 'turnsPerSession' }, 6);
        v.callsPerTurn = decAt(new List<String>{ 'volumeScenario', 'callsPerTurn' }, 1);
        v.periodsPerYear = decAt(new List<String>{ 'volumeScenario', 'daysPerYear' }, 365);
        v.scenarioLabel = '50 sessions/day × 6 turns';
        return v;
    }

    public Decimal signalWeight(String signalType) {
        Map<String, Decimal> fb = new Map<String, Decimal>{
            'LLM_WHERE_DETERMINISTIC' => 1.0,
            'MODEL_RIGHTSIZING' => 0.7,
            'INSTRUCTION_BLOAT' => 0.5,
            'REDUNDANT_CALLS' => 0.8
        };
        Decimal fbv = fb.containsKey(signalType) ? fb.get(signalType) : 0.5;
        return decAt(new List<String>{ 'signalWeights', signalType }, fbv);
    }

    public Map<String, Integer> gradeCutoffs() {
        return new Map<String, Integer>{
            'A' => intAt(new List<String>{ 'gradeCutoffs', 'A' }, 90),
            'B' => intAt(new List<String>{ 'gradeCutoffs', 'B' }, 80),
            'C' => intAt(new List<String>{ 'gradeCutoffs', 'C' }, 70),
            'D' => intAt(new List<String>{ 'gradeCutoffs', 'D' }, 60)
        };
    }

    // ---------- path helpers (null/type tolerant) ----------

    private Object valueAt(List<String> path) {
        Object cur = root;
        for (String key : path) {
            if (!(cur instanceof Map<String, Object>)) {
                return null;
            }
            cur = ((Map<String, Object>) cur).get(key);
            if (cur == null) {
                return null;
            }
        }
        return cur;
    }

    private Decimal decAt(List<String> path, Decimal fb) {
        Object o = valueAt(path);
        if (o == null) { return fb; }
        try {
            if (o instanceof Decimal) { return (Decimal) o; }
            if (o instanceof Integer) { return (Decimal) ((Integer) o); }
            if (o instanceof Double) { return Decimal.valueOf((Double) o); }
            return Decimal.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return fb;
        }
    }

    private Integer intAt(List<String> path, Integer fb) {
        Decimal d = decAt(path, null);
        return (d == null) ? fb : d.intValue();
    }

    private String strAt(List<String> path, String fb) {
        Object o = valueAt(path);
        return (o == null) ? fb : String.valueOf(o);
    }
}
