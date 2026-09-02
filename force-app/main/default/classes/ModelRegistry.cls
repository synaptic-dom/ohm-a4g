/**
 * ModelRegistry — resolves a model API name to tier + rank + rate-card multiplier
 * from Ohm_Constants (SPEC §S.4). Unknown model => baseline MEDIUM, multiplier 1.0,
 * assumed=true (caller sets modelAssumed). Never throws.
 */
public with sharing class ModelRegistry {

    public enum TaskComplexity { TRIVIAL, SIMPLE, MODERATE, COMPLEX }

    public class ModelInfo {
        public String tier;
        public Integer rank;
        public Decimal rateCardMultiplier;
        public Boolean assumed;
        public ModelInfo(String tier, Integer rank, Decimal mult, Boolean assumed) {
            this.tier = tier;
            this.rank = rank;
            this.rateCardMultiplier = mult;
            this.assumed = assumed;
        }
    }

    /**
     * Look up a model by tier keyword or model API name.
     * Unknown => baseline MEDIUM (1.0), assumed=true.
     */
    public static ModelInfo lookup(String modelApiName) {
        OhmConstants c = OhmConstants.load();
        String tier = classifyTier(modelApiName);
        if (tier == null) {
            String baseline = c.baselineTier();
            return new ModelInfo(baseline, c.rankForTier(baseline), c.rateCardMultiplier(baseline), true);
        }
        return new ModelInfo(tier, c.rankForTier(tier), c.rateCardMultiplier(tier), false);
    }

    /** Smallest tier that covers the task (signal-b recommendation target). */
    public static ModelInfo recommendedFor(TaskComplexity complexity) {
        OhmConstants c = OhmConstants.load();
        String tier;
        if (complexity == TaskComplexity.TRIVIAL || complexity == TaskComplexity.SIMPLE) {
            tier = 'SMALL';
        } else if (complexity == TaskComplexity.MODERATE) {
            tier = 'MEDIUM';
        } else {
            tier = 'LARGE';
        }
        return new ModelInfo(tier, c.rankForTier(tier), c.rateCardMultiplier(tier), false);
    }

    /** Map a tier keyword or model API name to a canonical tier, or null if unknown. */
    private static String classifyTier(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        String n = name.toUpperCase();
        // direct tier keywords
        if (n == 'SMALL' || n == 'MEDIUM' || n == 'LARGE') {
            return n;
        }
        // large-class model families
        if (n.contains('GPT4') || n.contains('GPT-4') || n.contains('OMNI') ||
            n.contains('OPUS') || n.contains('ULTRA') || n.contains('4O')) {
            return 'LARGE';
        }
        // small-class model families
        if (n.contains('MINI') || n.contains('SMALL') || n.contains('HAIKU') ||
            n.contains('FLASH') || n.contains('NANO') || n.contains('LITE')) {
            return 'SMALL';
        }
        // medium-class model families
        if (n.contains('GPT35') || n.contains('GPT-3.5') || n.contains('TURBO') ||
            n.contains('SONNET') || n.contains('MEDIUM') || n.contains('PRO')) {
            return 'MEDIUM';
        }
        return null; // unknown
    }
}
