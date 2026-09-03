import { createElement } from 'lwc';
import OhmTrends from 'c/ohmTrends';
import getTrends from '@salesforce/apex/OhmAuditController.getTrends';

jest.mock(
    '@salesforce/apex/OhmAuditController.getTrends',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const ORG_TREND = {
    scope: 'Org',
    plannerId: null,
    points: [
        { auditedAt: '2026-08-01T10:00:00Z', grade: 'F', score: 20, energyWhCentral: 82486, findingsCount: 1, reportId: 'R1' },
        { auditedAt: '2026-08-15T10:00:00Z', grade: 'D', score: 55, energyWhCentral: 40000, findingsCount: 1, reportId: 'R2' },
        { auditedAt: '2026-09-01T10:00:00Z', grade: 'A', score: 96, energyWhCentral: 0, findingsCount: 0, reportId: 'R3' }
    ],
    firstEnergyWhCentral: 82486,
    lastEnergyWhCentral: 0,
    realizedSavingsWh: 82486,
    perAgent: [
        { plannerId: 'P1', label: 'Lead Concierge', gradeHistory: ['F', 'D', 'A'], currentGrade: 'A' },
        { plannerId: 'P2', label: 'Order Support', gradeHistory: ['C'], currentGrade: 'C' }
    ]
};

const PROCESS_TREND = {
    scope: 'Lead Concierge',
    plannerId: 'P1',
    points: [
        { auditedAt: '2026-09-01T10:00:00Z', grade: 'F', score: 20, energyWhCentral: 82486, findingsCount: 1, reportId: 'R9' }
    ],
    firstEnergyWhCentral: 82486,
    lastEnergyWhCentral: 82486,
    realizedSavingsWh: 0,
    perAgent: []
};

function create(calmMode = false) {
    const el = createElement('c-ohm-trends', { is: OhmTrends });
    el.calmMode = calmMode;
    document.body.appendChild(el);
    return el;
}

async function flush(times = 8) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

describe('c-ohm-trends', () => {
    beforeEach(() => {
        getTrends.mockReset();
        getTrends.mockResolvedValue(JSON.parse(JSON.stringify(ORG_TREND)));
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('loads the org trend on connect and draws the trendline + dots', async () => {
        const el = create();
        await flush();

        expect(getTrends).toHaveBeenCalledWith({ plannerId: null });
        const chart = el.shadowRoot.querySelector('[data-id="chart"]');
        expect(chart).not.toBeNull();
        // role=img + an aria-label summarizing the trend
        expect(chart.getAttribute('role')).toBe('img');
        expect(chart.getAttribute('aria-label')).toContain('energy trend');
        // one dot per point, a line for 3 points
        expect(chart.querySelectorAll('circle')).toHaveLength(3);
        expect(chart.querySelector('polyline')).not.toBeNull();
    });

    it('renders the realized-savings callout from realizedSavingsWh', async () => {
        const el = create();
        await flush();

        const savings = el.shadowRoot.querySelector(
            '[data-id="realized-savings"]'
        );
        expect(savings).not.toBeNull();
        expect(savings.textContent).toContain('82,486 Wh/yr');
    });

    it('renders the per-agent grade-history strip with letter chips', async () => {
        const el = create();
        await flush();

        const history = el.shadowRoot.querySelector(
            '[data-id="grade-history"]'
        );
        expect(history).not.toBeNull();
        const rows = el.shadowRoot.querySelectorAll('[data-id="agent-row"]');
        expect(rows).toHaveLength(2);
        // Lead Concierge shows its F,D,A history as letter chips
        const firstRow = rows[0];
        expect(firstRow.textContent).toContain('Lead Concierge');
        const chips = firstRow.querySelectorAll('.ohm-trends__gchip');
        expect(chips).toHaveLength(3);
        expect(Array.from(chips).map((c) => c.textContent.trim())).toEqual([
            'F',
            'D',
            'A'
        ]);
        // the current grade chip is emphasized
        expect(
            firstRow.querySelector('.ohm-trends__gchip--current').textContent.trim()
        ).toBe('A');
    });

    it('toggles scope to a process and re-calls getTrends with the plannerId', async () => {
        const el = create();
        await flush();

        // the dropdown was seeded from perAgent
        const select = el.shadowRoot.querySelector('[data-id="scope-select"]');
        expect(select).not.toBeNull();

        getTrends.mockResolvedValue(JSON.parse(JSON.stringify(PROCESS_TREND)));
        select.value = 'P1';
        select.dispatchEvent(new CustomEvent('change'));
        await flush();

        expect(getTrends).toHaveBeenLastCalledWith({ plannerId: 'P1' });
        // grade history is org-only -> gone on a process scope
        expect(
            el.shadowRoot.querySelector('[data-id="grade-history"]')
        ).toBeNull();
    });

    it('renders sparse single-point data as a dot with a caption', async () => {
        getTrends.mockReset();
        getTrends.mockResolvedValue(JSON.parse(JSON.stringify(PROCESS_TREND)));
        const el = create();
        await flush();

        const chart = el.shadowRoot.querySelector('[data-id="chart"]');
        expect(chart.querySelectorAll('circle')).toHaveLength(1);
        // no line for a single point
        expect(chart.querySelector('polyline')).toBeNull();
        expect(
            el.shadowRoot.querySelector('[data-id="sparse-caption"]')
        ).not.toBeNull();
    });

    it('shows the empty state when there are no points', async () => {
        getTrends.mockReset();
        getTrends.mockResolvedValue({
            scope: 'Org',
            plannerId: null,
            points: [],
            realizedSavingsWh: 0,
            perAgent: []
        });
        const el = create();
        await flush();

        expect(el.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="chart"]')).toBeNull();
    });

    it('shows a load error with retry when getTrends rejects', async () => {
        getTrends.mockReset();
        getTrends.mockRejectedValue({ body: { message: 'boom' } });
        const el = create();
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="load-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('boom');
    });
});
