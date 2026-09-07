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
        String n = name.trim().toUpperCase();
        String words = name.trim().replaceAll('([A-Z])([A-Z][a-z])', '$1 $2')
            .replaceAll('([a-z0-9])([A-Z])', '$1 $2').replace('_', ' ').toLowerCase();
        // direct tier keywords
        if (n == 'SMALL' || n == 'MEDIUM' || n == 'LARGE') {
            return n;
        }
        // Specific size variants take precedence over their parent family:
        // DefaultOpenAIGPT4OmniMini is SMALL, even though it also contains GPT4/OMNI.
        if (variant(n, words, 'mini') || variant(n, words, 'small') || variant(n, words, 'haiku') ||
            variant(n, words, 'flash') || variant(n, words, 'nano') || variant(n, words, 'lite')) {
            return 'SMALL';
        }
        // large-class model families
        if (n.contains('GPT4') || n.contains('GPT-4') || variant(n, words, 'omni') ||
            variant(n, words, 'opus') || variant(n, words, 'ultra') || OhmIntentEvidence.containsTerm(words, '4o')) {
            return 'LARGE';
        }
        // medium-class model families
        if (n.contains('GPT35') || n.contains('GPT-3.5') || variant(n, words, 'turbo') ||
            variant(n, words, 'sonnet') || variant(n, words, 'medium') || variant(n, words, 'pro')) {
            return 'MEDIUM';
        }
        return null; // unknown
    }

    private static Boolean variant(String upperName, String words, String term) {
        if (OhmIntentEvidence.containsTerm(words, term)) { return true; }
        // Fully upper/lower-cased API names lose CamelCase boundaries. Preserve suffixes
        // only for recognized model families; PROVIDER must not match PRO, nor ADMINISTER MINI.
        Boolean knownFamily = upperName.contains('GPT') || upperName.contains('CLAUDE') ||
            upperName.contains('GEMINI');
        return knownFamily && upperName.endsWith(term.toUpperCase());
    }
}
