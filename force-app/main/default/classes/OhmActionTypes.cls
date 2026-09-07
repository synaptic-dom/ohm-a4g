/** Salesforce invocation types normalized once for inventory and detector consistency. */
public with sharing class OhmActionTypes {
    public static Boolean isPrompt(String value) {
        String kind = normalize(value);
        return kind == 'prompt' || kind == 'generatepromptresponse';
    }
    public static Boolean isDeterministic(String value) {
        String kind = normalize(value);
        return kind == 'flow' || kind == 'apex';
    }
    private static String normalize(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }
}
