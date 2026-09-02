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
        startAudit.mockReset();
        getAuditStatus.mockReset();
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
        jest.useRealTimers();
    });

    it('gates first render until getCalmModePreference resolves, then shows WELCOME', async () => {
        let resolveCalm;
        getCalmModePreference.mockReturnValue(
            new Promise((r) => {
                resolveCalm = r;
            })
        );
        const el = create();
        // Not ready yet -> nothing rendered.
        expect(child(el, 'welcome')).toBeNull();
        resolveCalm(false);
        await flush();
        expect(child(el, 'welcome')).not.toBeNull();
    });

    it('loads Calm Mode before first paint and threads it to children', async () => {
        getCalmModePreference.mockResolvedValue(true);
        const el = create();
        await flush();
        expect(child(el, 'welcome').calmMode).toBe(true);
        expect(child(el, 'calm-toggle').calmMode).toBe(true);
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
        getAuditStatus.mockResolvedValue(mockAuditReadoutComplete());
        const el = create();
        await flush();
        await startTo(el);
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();

        expect(child(el, 'impact')).not.toBeNull();
        expect(child(el, 'impact').readout.runStatus).toBe('Complete');
        expect(jest.getTimerCount()).toBe(0);
    });

    it('focus moves to the impact heading on the Complete transition', async () => {
        jest.useFakeTimers();
        getAuditStatus.mockResolvedValue(mockAuditReadoutComplete());
        const el = create();
        await flush();
        await startTo(el);
        jest.advanceTimersByTime(POLL_INTERVAL_MS);
        await flush();

        const impact = child(el, 'impact');
        const h2 = impact.shadowRoot.querySelector('[data-focus-heading]');
        expect(impact.shadowRoot.activeElement).toBe(h2);
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

    it('calm toggle is optimistic and persists via setCalmModePreference', async () => {
        const el = create();
        await flush();
        child(el, 'calm-toggle').dispatchEvent(
            new CustomEvent('calmtoggle', { detail: { enabled: true } })
        );
        await flush();
        expect(setCalmModePreference).toHaveBeenCalledTimes(1);
        expect(setCalmModePreference.mock.calls[0][0]).toEqual({ enabled: true });
        expect(child(el, 'calm-toggle').calmMode).toBe(true);
    });

    it('calm toggle reverts when the persist call rejects', async () => {
        setCalmModePreference.mockRejectedValue(new Error('nope'));
        const el = create();
        await flush();
        child(el, 'calm-toggle').dispatchEvent(
            new CustomEvent('calmtoggle', { detail: { enabled: true } })
        );
        await flush();
        expect(child(el, 'calm-toggle').calmMode).toBe(false);
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

    it('is accessible in both Calm variants', async () => {
        const loud = create();
        await flush();
        await expect(loud).toBeAccessible();

        getCalmModePreference.mockResolvedValue(true);
        const calm = create();
        await flush();
        await expect(calm).toBeAccessible();
    });
});
