import { createElement } from 'lwc';
import OhmApp from 'c/ohmApp';
import getCalmModePreference from '@salesforce/apex/OhmAuditController.getCalmModePreference';
import setCalmModePreference from '@salesforce/apex/OhmAuditController.setCalmModePreference';

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

// ohmFleetTable pulls in its own Apex; stub those imports so the child mounts.
jest.mock(
    '@salesforce/apex/OhmAuditController.getFleet',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.auditProcess',
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
    const el = createElement('c-ohm-app', { is: OhmApp });
    document.body.appendChild(el);
    return el;
}

function tabs(el) {
    return Array.from(el.shadowRoot.querySelectorAll('[data-id="tab"]'));
}

describe('c-ohm-app', () => {
    beforeEach(() => {
        getCalmModePreference.mockReset();
        setCalmModePreference.mockReset();
        getCalmModePreference.mockResolvedValue(false);
        setCalmModePreference.mockResolvedValue(undefined);
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the shell with four tabs and Fleet active by default', async () => {
        const el = create();
        await flush();

        const strip = tabs(el);
        expect(strip).toHaveLength(4);
        expect(strip.map((t) => t.textContent.trim())).toEqual([
            'Fleet',
            'Findings',
            'Recommendations',
            'Trends'
        ]);
        // Fleet is active + fleet table is mounted
        expect(strip[0].getAttribute('aria-selected')).toBe('true');
        expect(el.shadowRoot.querySelector('[data-id="fleet"]')).not.toBeNull();
        expect(
            el.shadowRoot.querySelector('[data-id="placeholder"]')
        ).toBeNull();
    });

    it('switches tabs on click and shows the on-brand placeholder', async () => {
        const el = create();
        await flush();

        const findingsTab = tabs(el)[1];
        findingsTab.click();
        await flush();

        expect(findingsTab.getAttribute('aria-selected')).toBe('true');
        const placeholder = el.shadowRoot.querySelector(
            '[data-id="placeholder"]'
        );
        expect(placeholder).not.toBeNull();
        expect(placeholder.textContent).toContain('Coming in this build');
        expect(placeholder.textContent).toContain('Findings');
        // Fleet table unmounted while on another tab
        expect(el.shadowRoot.querySelector('[data-id="fleet"]')).toBeNull();
    });

    it('reflects the loaded calm preference and passes it to children', async () => {
        getCalmModePreference.mockResolvedValue(true);
        const el = create();
        await flush();

        const shell = el.shadowRoot.querySelector('[data-id="shell"]');
        expect(shell.className).toContain('ohm-app--calm');

        const toggle = el.shadowRoot.querySelector('c-ohm-calm-mode-toggle');
        expect(toggle.calmMode).toBe(true);
        const fleet = el.shadowRoot.querySelector('[data-id="fleet"]');
        expect(fleet.calmMode).toBe(true);
    });

    it('toggles calm mode from the child event and persists it', async () => {
        const el = create();
        await flush();

        const toggle = el.shadowRoot.querySelector('c-ohm-calm-mode-toggle');
        toggle.dispatchEvent(
            new CustomEvent('calmtoggle', { detail: { enabled: true } })
        );
        await flush();

        expect(setCalmModePreference).toHaveBeenCalledWith({ enabled: true });
        const shell = el.shadowRoot.querySelector('[data-id="shell"]');
        expect(shell.className).toContain('ohm-app--calm');
        expect(
            el.shadowRoot.querySelector('c-ohm-calm-mode-toggle').calmMode
        ).toBe(true);
    });

    it('records openprocess into the breadcrumb (Wave-3 seam)', async () => {
        const el = create();
        await flush();

        const fleet = el.shadowRoot.querySelector('[data-id="fleet"]');
        fleet.dispatchEvent(
            new CustomEvent('openprocess', {
                detail: { plannerId: '0Ai000000000001', label: 'Lead Concierge' },
                bubbles: true,
                composed: true
            })
        );
        await flush();

        const crumb = el.shadowRoot.querySelector('[data-id="breadcrumb"]');
        expect(crumb.textContent).toContain('Fleet');
        expect(crumb.textContent).toContain('Lead Concierge');
    });

    it('moves between tabs with arrow keys', async () => {
        const el = create();
        await flush();

        const strip = tabs(el);
        strip[0].dispatchEvent(
            new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true })
        );
        await flush();

        expect(tabs(el)[1].getAttribute('aria-selected')).toBe('true');
    });
});
