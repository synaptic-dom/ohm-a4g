import { createElement } from 'lwc';
import OhmRecommendations from 'c/ohmRecommendations';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import getReviewRecommendations from '@salesforce/apex/OhmReviewRecommendationService.getReviewRecommendations';
import createReviewTask from '@salesforce/apex/OhmReviewRecommendationService.createReviewTask';
import getFindings from '@salesforce/apex/OhmAuditController.getFindings';

jest.mock('@salesforce/apex/OhmAuditController.getFleet', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmReviewRecommendationService.getReviewRecommendations', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmReviewRecommendationService.createReviewTask', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.getFindings', () => ({ default: jest.fn() }), { virtual: true });

const ITEM = {
    key: 'review-key', reportId: 'R1', plannerId: 'P1', bundleLabel: 'Schedule Assistant',
    artifactId: 'N1', nodeId: 'N1', artifactKey: 'Action:Schedule', artifactLabel: 'Generate Schedule',
    categoryId: 'CALLS', categoryLabel: 'Call efficiency', rating: 'B',
    recommendation: 'Evaluate moving overlap checks into validated code.',
    explanation: 'The instruction assigns a bounded calculation to the model.',
    preserve: 'Keep the schedule and all required checks.',
    validation: 'Compare boundary cases and the final output.',
    evidence: [{ artifactId: 'N1', nodeId: 'N1', artifactKey: 'Action:Schedule', artifactLabel: 'Generate Schedule', quote: 'Calculate all overlaps.' }]
};
function page(overrides = {}) { return { plannerId: 'P1', bundleLabel: 'Schedule Assistant', sourceCurrent: true, reviewAvailable: true, items: [{ ...ITEM }], ...overrides }; }
async function flush(times = 12) { for (let i = 0; i < times; i += 1) { await Promise.resolve(); } }
function create() { const element = createElement('c-ohm-recommendations', { is: OhmRecommendations }); element.standalone = true; document.body.appendChild(element); return element; }
function card(element) { return element.shadowRoot.querySelector('c-ohm-recommendation-card'); }

describe('saved review recommendations', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        getFleet.mockResolvedValue([{ plannerId: 'P1', label: 'Schedule Assistant' }]);
        getReviewRecommendations.mockResolvedValue(page());
        createReviewTask.mockResolvedValue('00T000000000009');
        getFindings.mockResolvedValue([]);
    });
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); });

    it('loads recommendations from each bundle’s current saved review without modeled savings', async () => {
        const element = create(); await flush();
        expect(getFleet).toHaveBeenCalledTimes(1);
        expect(getReviewRecommendations).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(card(element).recommendation).toMatchObject(ITEM);
        expect(element.shadowRoot.querySelector('[data-id="coverage"]').textContent).toContain('1 recommendation · 1 of 1');
        expect(element.shadowRoot.textContent).not.toMatch(/\bWh\b/);
        expect(getFindings).not.toHaveBeenCalled();
    });
    it('creates a task using only saved server identities and shows its returned link', async () => {
        const element = create(); await flush();
        card(element).dispatchEvent(new CustomEvent('createtask', { detail: { plannerId: 'P1', reportId: 'R1', key: 'review-key' } }));
        await flush();
        expect(createReviewTask).toHaveBeenCalledWith({ plannerId: 'P1', reportId: 'R1', key: 'review-key' });
        expect(card(element).recommendation.taskId).toBe('00T000000000009');
        expect(card(element).recommendation.taskStatus).toBeUndefined();
        expect(card(element).shadowRoot.querySelector('[data-id="rec-task-link"]').getAttribute('href')).toBe('/lightning/r/Task/00T000000000009/view');
        expect(card(element).shadowRoot.textContent).not.toContain('Applied');
        card(element).dispatchEvent(new CustomEvent('createtask', { detail: { plannerId: 'P1', reportId: 'R1', key: 'review-key' } }));
        await flush(); expect(createReviewTask).toHaveBeenCalledTimes(1);
    });
    it('ignores unknown recommendation identities and displays server rejection on the correct card', async () => {
        createReviewTask.mockRejectedValue({ body: { message: 'Source changed. Run a new audit.' } });
        const element = create(); await flush();
        card(element).dispatchEvent(new CustomEvent('createtask', { detail: { plannerId: 'P1', reportId: 'R1', key: 'unknown' } }));
        expect(createReviewTask).not.toHaveBeenCalled();
        card(element).dispatchEvent(new CustomEvent('createtask', { detail: { plannerId: 'P1', reportId: 'R1', key: 'review-key' } }));
        await flush();
        expect(card(element).errorMessage).toContain('Source changed');
        expect(card(element).recommendation.taskId).toBeUndefined();
    });
    it('keeps available bundle recommendations when another source check fails', async () => {
        getFleet.mockResolvedValue([{ plannerId: 'P1', label: 'Schedule Assistant' }, { plannerId: 'P2', label: 'Weather Assistant' }]);
        getReviewRecommendations.mockImplementation(({ plannerId }) => plannerId === 'P1' ? Promise.resolve(page()) : Promise.reject(new Error('Metadata unavailable')));
        const element = create(); await flush();
        expect(card(element)).not.toBeNull();
        const unavailable = element.shadowRoot.querySelector('[data-id="unavailable-bundle"]');
        expect(unavailable.textContent).toContain('Weather Assistant');
        expect(unavailable.textContent).toContain('Metadata unavailable');
        const open = jest.fn(); element.addEventListener('openprocess', open);
        unavailable.querySelector('button').click();
        expect(open.mock.calls[0][0].detail).toMatchObject({ plannerId: 'P2', label: 'Weather Assistant' });
    });
    it('hides stale recommendations even if an unavailable response includes items', async () => {
        getReviewRecommendations.mockResolvedValue(page({ sourceCurrent: false, reason: 'Source changed.' }));
        const element = create(); await flush();
        expect(card(element)).toBeNull();
        expect(element.shadowRoot.textContent).toContain('Source changed.');
        expect(element.shadowRoot.textContent).toContain('Your next step is a fresh review');
    });
    it('keeps a no-recommendation review distinct from a clean pass', async () => {
        getReviewRecommendations.mockResolvedValue(page({ items: [] }));
        const element = create(); await flush();
        expect(element.shadowRoot.querySelector('[data-id="empty"]').textContent).toContain('insufficient evidence');
        expect(element.shadowRoot.textContent).not.toContain('already running lean');
    });
    it('filters categories and omits Model Fit from the interface', async () => {
        getReviewRecommendations.mockResolvedValue(page({ items: [ITEM, { ...ITEM, key: 'model', categoryId: 'MODEL', categoryLabel: 'Model fit' }] }));
        const element = create(); await flush();
        expect(element.shadowRoot.querySelectorAll('[data-id="card"]')).toHaveLength(1);
        expect(element.shadowRoot.textContent).not.toContain('Model fit');
        const filter = element.shadowRoot.querySelector('[data-id="filter-category"]');
        filter.value = 'INPUT'; filter.dispatchEvent(new CustomEvent('change')); await flush();
        expect(card(element)).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="empty"]').textContent).toContain('match these filters');
    });
    it('loads existing detector work only when its disclosure is opened', async () => {
        const element = create(); await flush();
        expect(getFindings).not.toHaveBeenCalled();
        element.shadowRoot.querySelector('[data-id="tracked-toggle"]').click(); await flush();
        expect(getFindings).toHaveBeenCalledWith({ statusFilter: 'All', severityFilter: 'All' });
        expect(element.shadowRoot.querySelector('c-ohm-findings-worklist')).not.toBeNull();
    });
    it('can retry a fleet failure without inventing recommendation coverage', async () => {
        getFleet.mockRejectedValueOnce(new Error('Fleet unavailable'));
        const element = create(); await flush();
        expect(element.shadowRoot.querySelector('[data-id="load-error"]').textContent).toContain('Fleet unavailable');
        expect(element.shadowRoot.querySelector('[data-id="coverage"]')).toBeNull();
        element.shadowRoot.querySelector('[data-id="refresh"]').click(); await flush();
        expect(card(element)).not.toBeNull();
    });
    it('is accessible with review cards and missing source coverage', async () => {
        const element = create(); await flush(); await expect(element).toBeAccessible();
        getReviewRecommendations.mockResolvedValue(page({ sourceCurrent: false }));
        await element.refresh(); await flush(); await expect(element).toBeAccessible();
    });
});
