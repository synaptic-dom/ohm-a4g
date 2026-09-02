/**
 * OhmSeverity — the SINGLE severity-band mapping (canon C7).
 * High if score >= 0.67; Medium if 0.34 <= score < 0.67; Low otherwise.
 * Every detector and its tests use ONLY this function — no detector defines its own banding.
 */
public with sharing class OhmSeverity {
    public static final String HIGH = 'High';
    public static final String MEDIUM = 'Medium';
    public static final String LOW = 'Low';

    public static String band(Decimal score) {
        if (score == null) {
            return LOW;
        }
        if (score >= 0.67) {
            return HIGH;
        }
        if (score >= 0.34) {
            return MEDIUM;
        }
        return LOW;
    }
}
