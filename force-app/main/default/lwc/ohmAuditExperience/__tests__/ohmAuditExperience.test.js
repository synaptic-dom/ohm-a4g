import { createElement } from 'lwc';
import OhmAuditExperience from 'c/ohmAuditExperience';
import startAudit from '@salesforce/apex/OhmAuditController.startAudit';
import getAuditStatus from '@salesforce/apex/OhmAuditController.getAuditStatus';
import getCalmModePreference from '@salesforce/apex/OhmAuditController.getCalmModePreference';
import setCalmModePreference from '@salesforce/apex/OhmAuditController.setCalmModePreference';
import {
    mockAuditReadoutComplete,
    mockAuditReadoutRunning
} from 'c/ohmTestData';
import { POLL_INTERVAL_MS } from 'c/ohmConstants';
import { pendingGuidedAudit, pendingAudits } from 'c/ohmAuditRun';
import { reviewFixture } from '../../../../../../test-fixtures/review/reviewFixture';

jest.mock(
    '@salesforce/apex/OhmAuditController.startAudit',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.getAuditStatus',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.getCalmModePreference',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.setCalmModePreference',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

async function flush(times = 6) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

function create() {
    const el = createElement('c-ohm-audit-experience', {
        is: OhmAuditExperience
    });
    document.body.appendChild(el);
    return el;
}

function child(el, id) {
    return el.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function startTo(el) {
    child(el, 'welcome').dispatchEvent(new CustomEvent('startaudit'));
    await flush();
}

describe('c-ohm-audit-experience', () => {
    beforeEach(() => {
        sessionStorage.clear();
        startAudit.mockReset();
        getAuditStatus.mockReset();
        getAuditStatus.mockResolvedValue(mockAuditReadoutRunning({ runStatus: 'Discovering' }));
        getCalmModePreference.mockReset();
        setCalmModePreference.mockReset();
        getCalmModePreference.mockResolvedValue(false);
        setCalmModePreference.mockResolvedValue(undefined);
        startAudit.mockResolvedValue('AUDIT-1');
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllTimers();
        jest.useRealTimers();
    });

    it('renders one dark palette immediately without loading or saving a display preference', async () => {
        getCalmModePreference.mockReturnValue(new Promise(() => {}));
        const el = create();
        await flush();
        expect(child(el, 'welcome')).not.toBeNull();
        expect(child(el, 'calm-toggle')).toBeNull();
        expect(el.shadowRoot.querySelector('.ohm-experience--calm')).toBeNull();
        expect(getCalmModePreference).not.toHaveBeenCalled();
        expect(setCalmModePreference).not.toHaveBeenCalled();
    });

    it('focus lands on the welcome heading after first paint', async () => {
        const el = create();
        await flush();
        const welcome = child(el, 'welcome');
        const h1 = welcome.shadowRoot.querySelector('[data-focus-heading]');
        expect(welcome.shadowRoot.activeElement).toBe(h1);
    });

    it('startaudit calls startAudit and transitions to DISCOVERING', async () => {
        jest.useFakeTimers();
        const el = create();
        await flush();
        await startTo(el);
        expect(startAudit).toHaveBeenCalledTimes(1);
        expect(child(el, 'discover')).not.toBeNull();
        expect(child(el, 'welcome')).toBeNull();
    });

    it('polls with setTimeout (one in-flight) and advances Analyzing -> ANALYZING', async () => {
        jest.useFakeTimers();
        const setIntervalSpy = jest.spyOn(global, 'setInterval');
        getAuditStatus.mockResolvedValue(
            mockAuditReadoutRunning({ runStatus: 'Analyzing', percentComplete: 60 })
        );
        const el = create();
        await flush();
        await startTo(el);

        // exactly one timer scheduled
        expect(jest.getTimerCount()).toBe(1);
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();

        const discover = child(el, 'discover');
        expect(discover.runStatus).toBe('Analyzing');
        // one in-flight -> rescheduled to exactly one timer
        expect(jest.getTimerCount()).toBe(1);
        expect(setIntervalSpy).not.toHaveBeenCalled();
    });

    it('Complete -> IMPACT, stores readout, and STOPS polling (no timer after terminal)', async () => {
        jest.useFakeTimers();
        const reviewJson = JSON.stringify(reviewFixture());
        getAuditStatus.mockResolvedValue(mockAuditReadoutComplete({ reviewJson }));
        const el = create();
        await flush();
        await startTo(el);
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();

        expect(child(el, 'impact')).not.toBeNull();
        expect(child(el, 'impact').readout.runStatus).toBe('Complete');
        expect(child(el, 'review-panel').reviewJson).toBe(reviewJson);
        expect(child(el, 'supporting-evidence').open).toBe(false);
        expect(jest.getTimerCount()).toBe(0);
    });

    it('focus moves to the review heading on the Complete transition', async () => {
        jest.useFakeTimers();
        getAuditStatus.mockResolvedValue(mockAuditReadoutComplete());
        const el = create();
        await flush();
        await startTo(el);
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();

        const review = child(el, 'review-panel');
        const h2 = review.shadowRoot.querySelector('[data-focus-heading]');
        expect(review.shadowRoot.activeElement).toBe(h2);
    });

    it('Failed status -> ERROR screen', async () => {
        jest.useFakeTimers();
        getAuditStatus.mockResolvedValue(
            mockAuditReadoutRunning({ runStatus: 'Failed', stageMessage: 'boom' })
        );
        const el = create();
        await flush();
        await startTo(el);
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();

        expect(child(el, 'error-message')).not.toBeNull();
        expect(child(el, 'error-message').textContent).toContain('boom');
        expect(jest.getTimerCount()).toBe(0);
        expect(pendingGuidedAudit()).toBeNull();
        expect(child(el, 'retry-button').label).toBe('Try again');
    });

    it('rejected startAudit -> ERROR', async () => {
        startAudit.mockRejectedValue({ body: { message: 'no auth' } });
        const el = create();
        await flush();
        await startTo(el);
        expect(child(el, 'error-message').textContent).toContain('no auth');
    });

    it('view recommendations -> RECOMMENDATIONS, back -> IMPACT', async () => {
        jest.useFakeTimers();
        getAuditStatus.mockResolvedValue(mockAuditReadoutComplete());
        const el = create();
        await flush();
        await startTo(el);
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();

        child(el, 'impact').dispatchEvent(new CustomEvent('viewrecommendations'));
        await flush();
        expect(child(el, 'recommendations')).not.toBeNull();
        expect(child(el, 'recommendations').findings.length).toBe(4);

        child(el, 'back-button').click();
        await flush();
        expect(child(el, 'impact')).not.toBeNull();
    });

    it('retry from ERROR returns to WELCOME', async () => {
        startAudit.mockRejectedValue({ message: 'x' });
        const el = create();
        await flush();
        await startTo(el);
        expect(child(el, 'retry-button')).not.toBeNull();
        child(el, 'retry-button').click();
        await flush();
        expect(child(el, 'welcome')).not.toBeNull();
    });

    it('disconnectedCallback clears the poll handle', async () => {
        jest.useFakeTimers();
        getAuditStatus.mockResolvedValue(
            mockAuditReadoutRunning({ runStatus: 'Discovering' })
        );
        const el = create();
        await flush();
        await startTo(el);
        expect(jest.getTimerCount()).toBe(1);
        document.body.removeChild(el);
        expect(jest.getTimerCount()).toBe(0);
    });

    it('continues checking a genuine retrieval run beyond the previous 60-second cutoff', async () => {
        jest.useFakeTimers();
        getAuditStatus.mockResolvedValue(mockAuditReadoutRunning({ runStatus: 'Discovering', stageMessage: 'Waiting for Salesforce source retrieval' }));
        const el = create();
        await flush();
        await startTo(el);
        for (let i = 0; i < 45; i += 1) {
            jest.advanceTimersByTime(POLL_INTERVAL_MS);
            // eslint-disable-next-line no-await-in-loop
            await flush();
        }
        expect(getAuditStatus).toHaveBeenCalledTimes(46);
        expect(child(el, 'error-message')).toBeNull();
        expect(child(el, 'discover').stageMessage).toBe('Waiting for Salesforce source retrieval');
        getAuditStatus.mockResolvedValue(mockAuditReadoutComplete());
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();
        expect(child(el, 'impact')).not.toBeNull();
        expect(pendingGuidedAudit()).toBeNull();
    });

    it('persists and resumes an org-wide run across refresh without treating it as a planner audit', async () => {
        jest.useFakeTimers();
        const el = create();
        await flush();
        await startTo(el);
        expect(pendingGuidedAudit()).toBe('AUDIT-1');
        expect(pendingAudits()).toEqual([]);
        document.body.removeChild(el);
        jest.advanceTimersByTime(9000);
        await flush();
        expect(getAuditStatus).toHaveBeenCalledTimes(1);
        const resumed = create();
        await flush();
        expect(child(resumed, 'discover').reportId).toBe('AUDIT-1');
        expect(getAuditStatus).toHaveBeenCalledTimes(2);
        expect(startAudit).toHaveBeenCalledTimes(1);
    });

    it('resumes the same report after a connection error instead of starting another audit', async () => {
        jest.useFakeTimers();
        getAuditStatus.mockRejectedValueOnce(new Error('Connection interrupted'));
        const el = create();
        await flush();
        await startTo(el);
        expect(child(el, 'error-message').textContent).toBe('Connection interrupted');
        expect(child(el, 'retry-button').label).toBe('Resume checking');
        expect(pendingGuidedAudit()).toBe('AUDIT-1');
        getAuditStatus.mockResolvedValue(mockAuditReadoutComplete());
        child(el, 'retry-button').click();
        await flush();
        expect(child(el, 'impact')).not.toBeNull();
        expect(startAudit).toHaveBeenCalledTimes(1);
        expect(getAuditStatus).toHaveBeenLastCalledWith({ reportId: 'AUDIT-1' });
        expect(pendingGuidedAudit()).toBeNull();
    });

    it('never overlaps status calls and ignores an in-flight response after disconnect', async () => {
        jest.useFakeTimers();
        let resolveStatus;
        getAuditStatus.mockReturnValue(new Promise((resolve) => { resolveStatus = resolve; }));
        const el = create();
        await flush();
        await startTo(el);
        jest.advanceTimersByTime(9000);
        await flush();
        expect(getAuditStatus).toHaveBeenCalledTimes(1);
        document.body.removeChild(el);
        resolveStatus(mockAuditReadoutComplete());
        await flush();
        expect(pendingGuidedAudit()).toBe('AUDIT-1');
        expect(jest.getTimerCount()).toBe(0);
    });

    it('keeps the guided welcome accessible in the single visual mode', async () => {
        const el = create();
        await flush();
        await expect(el).toBeAccessible();
    });
});
