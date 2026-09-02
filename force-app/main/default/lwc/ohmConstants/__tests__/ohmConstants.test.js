import {
    STATES,
    SIGNAL_LABELS,
    SEVERITY_LABELS,
    POLL_INTERVAL_MS,
    MAX_POLLS,
    GRADE_WORDS,
    formatNumber,
    formatRange,
    provenanceLabel
} from 'c/ohmConstants';

describe('ohmConstants', () => {
    it('exposes the six FSM states', () => {
        expect(Object.keys(STATES).sort()).toEqual(
            [
                'ANALYZING',
                'DISCOVERING',
                'ERROR',
                'IMPACT',
                'RECOMMENDATIONS',
                'WELCOME'
            ].sort()
        );
    });

    it('SIGNAL_LABELS keys are exactly the four canonical C2 values', () => {
        expect(Object.keys(SIGNAL_LABELS).sort()).toEqual(
            [
                'INSTRUCTION_BLOAT',
                'LLM_WHERE_DETERMINISTIC',
                'MODEL_RIGHTSIZING',
                'REDUNDANT_CALLS'
            ].sort()
        );
    });

    it('does not contain any non-canonical signal variants', () => {
        const keys = Object.keys(SIGNAL_LABELS);
        expect(keys).not.toContain('Model_Right_Sizing');
        expect(keys).not.toContain('Redundant_Call_Pattern');
    });

    it('POLL_INTERVAL_MS is 1500 and MAX_POLLS is a positive integer', () => {
        expect(POLL_INTERVAL_MS).toBe(1500);
        expect(MAX_POLLS).toBeGreaterThan(0);
    });

    it('SEVERITY_LABELS and GRADE_WORDS cover the bands', () => {
        expect(Object.keys(SEVERITY_LABELS).sort()).toEqual([
            'High',
            'Low',
            'Medium'
        ]);
        expect(GRADE_WORDS.A).toBeDefined();
        expect(GRADE_WORDS.F).toBeDefined();
    });

    it('formatNumber groups thousands and handles null', () => {
        expect(formatNumber(88695)).toBe('88,695');
        expect(formatNumber(null)).toBe('—');
        expect(formatNumber(0.27, 2)).toBe('0.27');
    });

    it('formatRange emits an en-dash range', () => {
        expect(formatRange(10, 30)).toBe('range 10–30');
    });

    it('provenanceLabel builds the W7 scenario + confidence string', () => {
        const label = provenanceLabel(
            { scenarioLabel: '50 sessions/day × 6 turns' },
            'Low',
            false
        );
        expect(label).toBe(
            'at 50 sessions/day × 6 turns, modeled — Confidence: Low'
        );
    });
});

describe('sa11y matcher wiring', () => {
    it('registers the toBeAccessible() matcher', () => {
        expect(typeof expect({}).toBeAccessible).toBe('function');
    });
});
