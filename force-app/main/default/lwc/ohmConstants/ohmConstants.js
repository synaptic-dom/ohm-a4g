/**
 * Shared constants + label maps for the Ohm audit experience.
 * Canon: SPEC §L.1, §0.2 C2 (canonical Signal_Type values), C3 (low/central/high).
 */

// FSM states for the root ohmAuditExperience (SPEC §L.4).
export const STATES = {
    WELCOME: 'WELCOME',
    DISCOVERING: 'DISCOVERING',
    ANALYZING: 'ANALYZING',
    IMPACT: 'IMPACT',
    RECOMMENDATIONS: 'RECOMMENDATIONS',
    ERROR: 'ERROR'
};

// Canonical Signal_Type__c values (C2) -> human labels. Keys MUST be exactly these four.
export const SIGNAL_LABELS = {
    LLM_WHERE_DETERMINISTIC: 'LLM used where deterministic code would do',
    MODEL_RIGHTSIZING: 'Model larger than the task needs',
    INSTRUCTION_BLOAT: 'Bloated instructions / scope',
    REDUNDANT_CALLS: 'Redundant LLM calls'
};

// Severity picklist (C7) -> human labels.
export const SEVERITY_LABELS = {
    High: 'High',
    Medium: 'Medium',
    Low: 'Low'
};

// Fix_Type__c -> human labels (deterministic recommendation targets).
export const FIX_TYPE_LABELS = {
    Replace_With_Flow: 'Replace with Flow',
    Replace_With_Apex: 'Replace with Apex',
    Downsize_Model: 'Downsize the model',
    Trim_Instructions: 'Trim instructions',
    Consolidate_Calls: 'Consolidate calls'
};

// Polling cadence for getAuditStatus (SPEC §L.4).
export const POLL_INTERVAL_MS = 1500;

// Hard stop after this many polls -> ERROR (avoids an infinite loop).
export const MAX_POLLS = 40;

// Run_Status__c values that terminate polling.
export const TERMINAL_STATUSES = ['Complete', 'Failed'];

// Efficiency grade letter -> plain word (color-independent per AC-F4).
export const GRADE_WORDS = {
    A: 'Excellent',
    B: 'Good',
    C: 'Fair',
    D: 'Poor',
    F: 'Wasteful'
};

/**
 * Round to at most `dp` decimals and group thousands. null/undefined -> '—'.
 */
export function formatNumber(value, dp = 0) {
    if (value === null || value === undefined || Number.isNaN(Number(value))) {
        return '—';
    }
    const n = Number(value);
    const rounded = Number(n.toFixed(dp));
    return rounded.toLocaleString('en-US', {
        minimumFractionDigits: 0,
        maximumFractionDigits: dp
    });
}

/**
 * "range low–high" text for a metric band. Uses an en dash.
 */
export function formatRange(low, high, dp = 0) {
    return `range ${formatNumber(low, dp)}–${formatNumber(high, dp)}`;
}

/**
 * W7 point-of-display provenance: "at 50 sessions/day × 6 turns, modeled — Confidence: Low".
 * telemetryBacked=true swaps "modeled" for "telemetry-backed".
 */
export function provenanceLabel(volumeAssumption, confidence, telemetryBacked) {
    const scenario =
        (volumeAssumption && volumeAssumption.scenarioLabel) || 'the modeled scenario';
    const basis = telemetryBacked ? 'telemetry-backed' : 'modeled';
    const conf = confidence || 'Low';
    return `at ${scenario}, ${basis} — Confidence: ${conf}`;
}
