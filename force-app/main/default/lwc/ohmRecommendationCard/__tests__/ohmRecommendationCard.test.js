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

    it('does not present modeled savings as the outcome of a recommendation', () => {
        const el = create({ finding: mockFinding({ estimatedSavingsLow: 10, estimatedSavingsCentral: 20, estimatedSavingsHigh: 30 }) });
        expect(text(el, 'rec-savings')).toBeNull();
        expect(el.shadowRoot.textContent).not.toContain('Wh/yr');
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

    it('opens the saved recommendation and its exact quoted source without applying changes', async () => {
        const recommendation = {
            key: 'K1', plannerId: 'P1', reportId: 'R1', bundleLabel: 'Schedule Assistant',
            nodeId: 'N1', artifactKey: 'Action:Schedule', artifactLabel: 'Generate Schedule',
            categoryLabel: 'Call efficiency', rating: 'B', recommendation: 'Evaluate moving overlap checks into code.',
            explanation: 'The prompt asks for a bounded calculation.', preserve: 'Keep all scheduling rules.',
            validation: 'Compare overlapping and non-overlapping cases.',
            evidence: [{ nodeId: 'N2', artifactKey: 'Topic:Schedule', artifactLabel: 'Schedule topic', quote: 'Calculate all overlaps.\nKeep every rule.' }]
        };
        const el = create({ recommendation });
        const open = jest.fn(); el.addEventListener('openprocess', open);
        expect(el.shadowRoot.querySelector('[data-id="rec-reasoning"]')).toBeNull();
        el.shadowRoot.querySelector('[data-id="rec-open"]').click();
        expect(open.mock.calls[0][0].detail).toEqual({ plannerId: 'P1', label: 'Schedule Assistant', nodeId: 'N1', artifactKey: 'Action:Schedule', intent: 'recommendation' });
        el.shadowRoot.querySelector('[data-id="rec-details"]').click(); await Promise.resolve();
        const detail = el.shadowRoot.querySelector('[data-id="rec-reasoning"]');
        expect(detail.textContent).toContain('Keep all scheduling rules.');
        expect(detail.textContent).toContain('Compare overlapping and non-overlapping cases.');
        expect(detail.querySelector('blockquote').textContent).toBe('Calculate all overlaps.\nKeep every rule.');
        el.shadowRoot.querySelector('[data-id="rec-evidence-open"]').click();
        expect(open.mock.calls[1][0].detail).toMatchObject({ nodeId: 'N2', artifactKey: 'Topic:Schedule', intent: 'source' });
        expect(el.shadowRoot.textContent).not.toMatch(/\bWh\b/);
        await expect(el).toBeAccessible();
    });

    it('uses saved task status without implying that the source was fixed', () => {
        const el = create({ recommendation: { key: 'K1', plannerId: 'P1', recommendation: 'Review the source.', taskId: '00T000000000001', taskStatus: 'Completed', taskClosed: true } });
        expect(text(el, 'rec-done')).toBe('Task · Completed');
        expect(el.shadowRoot.querySelector('[data-id="rec-create-task"]')).toBeNull();
        expect(el.shadowRoot.textContent).not.toContain('Applied');
    });

    it('keeps the single dark interface accessible for existing callers', async () => {
        await expect(create({ calmMode: false })).toBeAccessible();
        await expect(create({ calmMode: true })).toBeAccessible();
    });
});
