import { createElement } from 'lwc';
import OhmApp from 'c/ohmApp';
import getCalmModePreference from '@salesforce/apex/OhmAuditController.getCalmModePreference';
jest.mock('@salesforce/apex/OhmAuditController.getCalmModePreference', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.getFleet', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.auditProcess', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.getProcessDetail', () => ({ default: jest.fn(() => Promise.resolve({ plannerId: 'P1', label: 'Bundle', nodes: [], findings: [] })) }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.getFindings', () => ({ default: jest.fn(() => Promise.resolve([])) }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.createRemediationTask', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.updateFindingStatus', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.assignFinding', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmReviewRecommendationService.getReviewRecommendations', () => ({ default: jest.fn(() => Promise.resolve({ items: [] })) }), { virtual: true });
async function flush() { for (let i=0; i<12; i+=1) await Promise.resolve(); }
function create() { const el = createElement('c-ohm-app', { is: OhmApp }); document.body.appendChild(el); return el; }
const tabs = (el) => [...el.shadowRoot.querySelectorAll('[data-id="tab"]')];
afterEach(() => { document.body.replaceChildren(); jest.clearAllMocks(); });
it('opens immediately on Overview with four destinations and no legacy controls', async () => {
    const el=create();
    expect(el.shadowRoot.querySelector('[data-id="overview"]')).not.toBeNull();
    await flush();
    expect(tabs(el).map((tab) => tab.textContent.trim())).toEqual(['Overview', 'Bundles', 'Recommendations', 'How it works']);
    expect(tabs(el)[0].getAttribute('aria-selected')).toBe('true');
    expect(el.shadowRoot.querySelector('c-ohm-calm-mode-toggle')).toBeNull();
    expect(el.shadowRoot.querySelector('c-ohm-trends')).toBeNull();
    expect(getCalmModePreference).not.toHaveBeenCalled();
});
it('takes the overview action to bundles and returns through the wordmark', async () => {
    const el=create(); await flush();
    el.shadowRoot.querySelector('c-ohm-overview').dispatchEvent(new CustomEvent('navigate', { detail: { tab: 'FLEET' } })); await flush();
    expect(el.shadowRoot.querySelector('c-ohm-fleet-table')).not.toBeNull();
    el.shadowRoot.querySelector('[aria-label="Ohm overview"]').click(); await flush();
    expect(el.shadowRoot.querySelector('c-ohm-overview')).not.toBeNull();
});
it('routes recommendation identity to the exact source and clears it on back', async () => {
    const el=create(); await flush(); tabs(el)[2].click(); await flush();
    const recs=el.shadowRoot.querySelector('c-ohm-recommendations');
    expect(recs.standalone).toBe(true);
    recs.dispatchEvent(new CustomEvent('openprocess', { detail: { plannerId:'P1', label:'Bundle', nodeId:'N1', artifactKey:'K1', intent:'source', question:'Review this change' } })); await flush();
    const page=el.shadowRoot.querySelector('c-ohm-process-page');
    expect(page.plannerId).toBe('P1'); expect(page.initialNodeId).toBe('N1'); expect(page.initialArtifactKey).toBe('K1'); expect(page.initialIntent).toBe('source'); expect(page.initialQuestion).toBe('Review this change');
    page.dispatchEvent(new CustomEvent('backtofleet')); await flush();
    const fleet=el.shadowRoot.querySelector('c-ohm-fleet-table'); expect(fleet).not.toBeNull();
    fleet.dispatchEvent(new CustomEvent('openprocess', { detail: { plannerId:'P2' } })); await flush();
    const next=el.shadowRoot.querySelector('c-ohm-process-page'); expect(next.initialNodeId).toBeUndefined(); expect(next.initialIntent).toBeUndefined();
});
it('supports Arrow, Home and End navigation and clears a prior open bundle', async () => {
    const el=create(); await flush();
    el.shadowRoot.querySelector('c-ohm-overview').dispatchEvent(new CustomEvent('openprocess', { detail: { plannerId:'P1' } })); await flush();
    tabs(el)[1].dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true})); await flush();
    expect(tabs(el)[2].getAttribute('aria-selected')).toBe('true');
    tabs(el)[2].dispatchEvent(new KeyboardEvent('keydown',{key:'Home',bubbles:true})); await flush(); expect(tabs(el)[0].getAttribute('aria-selected')).toBe('true');
    tabs(el)[0].dispatchEvent(new KeyboardEvent('keydown',{key:'End',bubbles:true})); await flush(); expect(tabs(el)[3].getAttribute('aria-selected')).toBe('true'); expect(el.shadowRoot.querySelector('c-ohm-how-it-works')).not.toBeNull();
    tabs(el)[1].click(); await flush(); expect(el.shadowRoot.querySelector('c-ohm-process-page')).toBeNull();
});
