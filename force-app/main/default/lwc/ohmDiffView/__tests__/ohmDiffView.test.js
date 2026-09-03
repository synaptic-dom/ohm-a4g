import { createElement } from 'lwc';
import OhmDiffView from 'c/ohmDiffView';
import getDiff from '@salesforce/apex/OhmAuditController.getDiff';

jest.mock(
    '@salesforce/apex/OhmAuditController.getDiff',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const IMPROVED = {
    plannerId: 'P1',
    label: 'Lead Triage',
    beforeReportId: 'R1',
    beforeAt: '2026-08-01T10:00:00Z',
    beforeGrade: 'F',
    beforeScore: 20,
    beforeEnergyWhCentral: 82486,
    beforeFindings: 1,
    afterReportId: 'R2',
    afterAt: '2026-09-01T10:00:00Z',
    afterGrade: 'A',
    afterScore: 96,
    afterEnergyWhCentral: 0,
    afterFindings: 0,
    energyDeltaWh: 82486,
    scoreDelta: 76,
    findingsDelta: 1,
    beforeInstructions: 'x'.repeat(5400),
    afterInstructions: 'y'.repeat(380),
    improved: true
};

const SINGLE = {
    plannerId: 'P2',
    label: 'Order Help',
    beforeReportId: null,
    afterReportId: 'R9',
    afterGrade: 'C',
    afterScore: 60,
    afterEnergyWhCentral: 45648,
    afterFindings: 1,
    improved: false
};

function create(plannerId = 'P1', calmMode = false) {
    const el = createElement('c-ohm-diff-view', { is: OhmDiffView });
    el.calmMode = calmMode;
    el.plannerId = plannerId;
    document.body.appendChild(el);
    return el;
}

async function flush(times = 8) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

describe('c-ohm-diff-view', () => {
    beforeEach(() => {
        getDiff.mockReset();
        getDiff.mockResolvedValue(JSON.parse(JSON.stringify(IMPROVED)));
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('loads the diff and renders both before/after columns', async () => {
        const el = create('P1');
        await flush();

        expect(getDiff).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(
            el.shadowRoot.querySelector('[data-id="before-grade"]').textContent
        ).toContain('F');
        expect(
            el.shadowRoot.querySelector('[data-id="after-grade"]').textContent
        ).toContain('A');
        expect(
            el.shadowRoot.querySelector('[data-id="before-energy"]').textContent
        ).toContain('82,486 Wh/yr');
        expect(
            el.shadowRoot.querySelector('[data-id="after-energy"]').textContent
        ).toContain('0 Wh/yr');
    });

    it('renders the delta row with grade, energy and findings transitions', async () => {
        const el = create('P1');
        await flush();

        const delta = el.shadowRoot.querySelector('[data-id="delta"]');
        expect(delta).not.toBeNull();
        expect(delta.className).toContain('ohm-diff__delta--improved');
        expect(
            el.shadowRoot.querySelector('[data-id="delta-grade"]').textContent
        ).toContain('F → A');
        // energyDeltaWh positive -> shown as saved energy (minus sign)
        expect(
            el.shadowRoot.querySelector('[data-id="delta-energy"]').textContent
        ).toContain('−82,486 Wh/yr');
        expect(
            el.shadowRoot.querySelector('[data-id="delta-findings"]').textContent
        ).toContain('1 → 0 findings');
    });

    it('renders the instructions comparison with char counts', async () => {
        const el = create('P1');
        await flush();

        const instr = el.shadowRoot.querySelector('[data-id="instructions"]');
        expect(instr).not.toBeNull();
        expect(instr.textContent).toContain('5,400 chars');
        expect(instr.textContent).toContain('380 chars');
        expect(
            el.shadowRoot.querySelector('[data-id="before-instr"]').textContent
                .length
        ).toBe(5400);
        expect(
            el.shadowRoot.querySelector('[data-id="after-instr"]').textContent
                .length
        ).toBe(380);
    });

    it('shows the single-audit prompt when only one report exists', async () => {
        getDiff.mockReset();
        getDiff.mockResolvedValue(JSON.parse(JSON.stringify(SINGLE)));
        const el = create('P2');
        await flush();

        const note = el.shadowRoot.querySelector('[data-id="single-note"]');
        expect(note).not.toBeNull();
        expect(note.textContent).toContain('Re-audit this process after a change');
        // no comparison columns / delta
        expect(el.shadowRoot.querySelector('[data-id="compare"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="delta"]')).toBeNull();
    });

    it('refresh() re-fetches the diff', async () => {
        const el = create('P1');
        await flush();
        expect(getDiff).toHaveBeenCalledTimes(1);

        el.refresh();
        await flush();
        expect(getDiff).toHaveBeenCalledTimes(2);
    });

    it('shows a load error with retry when getDiff rejects', async () => {
        getDiff.mockReset();
        getDiff.mockRejectedValue({ body: { message: 'kaboom' } });
        const el = create('P1');
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="load-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('kaboom');
    });
});
