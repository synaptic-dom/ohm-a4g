import { createElement } from 'lwc';
import OhmRecommendationCard from 'c/ohmRecommendationCard';
import { mockFinding, mockVolumeAssumption } from 'c/ohmTestData';

function create(props = {}) {
    const el = createElement('c-ohm-recommendation-card', {
        is: OhmRecommendationCard
    });
    Object.assign(
        el,
        { finding: mockFinding(), volumeAssumption: mockVolumeAssumption() },
        props
    );
    document.body.appendChild(el);
    return el;
}

function text(el, id) {
    const n = el.shadowRoot.querySelector(`[data-id="${id}"]`);
    return n ? n.textContent.trim() : null;
}

describe('c-ohm-recommendation-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('prefers agentNarrative over recommendationText when non-null', () => {
        const el = create({
            finding: mockFinding({
                agentNarrative: 'Agent-phrased advice.',
                recommendationText: 'Deterministic advice.'
            })
        });
        expect(text(el, 'rec-text')).toBe('Agent-phrased advice.');
    });

    it('falls back to recommendationText when narrative is null', () => {
        const el = create({
            finding: mockFinding({
                agentNarrative: null,
                recommendationText: 'Deterministic advice.'
            })
        });
        expect(text(el, 'rec-text')).toBe('Deterministic advice.');
    });

    it('renders severity and the signal label as TEXT', () => {
        const el = create({
            finding: mockFinding({ signal: 'REDUNDANT_CALLS', severity: 'High' })
        });
        expect(text(el, 'rec-severity')).toBe('Severity: High');
        expect(text(el, 'rec-signal')).toContain('Redundant');
    });

    it('shows the savings band and a W7 provenance line', () => {
        const el = create({
            finding: mockFinding({
                estimatedSavingsLow: 10,
                estimatedSavingsCentral: 20,
                estimatedSavingsHigh: 30,
                confidence: 'Low'
            })
        });
        expect(text(el, 'rec-savings')).toBe('saves 10–20–30 Wh/yr');
        expect(text(el, 'rec-provenance')).toContain('Confidence: Low');
        expect(text(el, 'rec-provenance')).toContain('50 sessions/day');
    });

    it('badges the provenance of the phrasing as text', () => {
        const agent = create({ finding: mockFinding({ generatedBy: 'Agentforce' }) });
        expect(text(agent, 'rec-generated-by')).toBe('Agent-phrased');
        const det = create({ finding: mockFinding({ generatedBy: 'Deterministic' }) });
        expect(text(det, 'rec-generated-by')).toBe('Deterministic');
    });

    it('emits createtask with the findingId, then shows "Task created" once done', () => {
        const finding = mockFinding({ id: 'FIND-1', remediationTaskId: null });
        const el = create({ finding });
        const handler = jest.fn();
        el.addEventListener('createtask', handler);
        el.shadowRoot.querySelector('[data-id="rec-create-task"]').click();
        expect(handler.mock.calls[0][0].detail).toEqual({ findingId: 'FIND-1' });

        // Simulate the container flipping the finding to created.
        el.finding = mockFinding({ id: 'FIND-1', remediationTaskId: '00T000000000001' });
        return Promise.resolve().then(() => {
            expect(text(el, 'rec-done')).toBe('Task created');
            expect(
                el.shadowRoot.querySelector('[data-id="rec-create-task"]')
            ).toBeNull();
        });
    });

    it('shows an error message when the container feeds one', () => {
        const el = create({ errorMessage: 'Could not create the task.' });
        expect(text(el, 'rec-error')).toContain('Could not create the task');
    });

    it('is accessible in both Calm variants', async () => {
        await expect(create({ calmMode: false })).toBeAccessible();
        await expect(create({ calmMode: true })).toBeAccessible();
    });
});
