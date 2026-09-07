/** Shared lexical evidence for review candidates, never proof of behavioral equivalence. */
public with sharing class OhmIntentEvidence {
    private static Map<String, Pattern> patterns = new Map<String, Pattern>();

    public static String actionText(OhmDTO.ActionNode action) {
        if (action == null) { return ''; }
        String text = value(action.masterLabel) + ' ' + value(action.developerName) + ' ' +
            value(action.description);
        // API names often use CamelCase or underscores. Preserve real word boundaries
        // while allowing ClassifyLead and classify_lead to carry the same evidence.
        return text.replaceAll('([A-Z])([A-Z][a-z])', '$1 $2')
            .replaceAll('([a-z0-9])([A-Z])', '$1 $2').replace('_', ' ').toLowerCase();
    }

    public static Boolean containsTerm(String text, String term) {
        if (String.isBlank(text) || String.isBlank(term)) { return false; }
        if (!patterns.containsKey(term)) {
            // All terms are controlled lexicon constants, not user-provided patterns.
            patterns.put(term, Pattern.compile('(^|[^a-z0-9])' + term + '([^a-z0-9]|$)'));
        }
        return patterns.get(term).matcher(text).find();
    }

    private static String value(String text) { return text == null ? '' : text; }
}
