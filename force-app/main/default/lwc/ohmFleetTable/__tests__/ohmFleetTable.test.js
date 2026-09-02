import { createElement } from 'lwc';
import OhmFleetTable from 'c/ohmFleetTable';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';

jest.mock(
    '@salesforce/apex/OhmAuditController.getFleet',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.auditProcess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const FLEET = [
    {
        plannerId: 'P1',
        plannerApiName: 'Lead_Concierge',
        label: 'Lead Concierge',
        domain: 'Sales',
        topicCount: 1,
        actionCount: 1,
        audited: true,
        grade: 'F',
        score: 22,
        energyWhCentral: 82486,
        latestReportId: 'R1',
        lastAudited: '2026-09-02T00:00:00Z'
    },
    {
        plannerId: 'P2',
        plannerApiName: 'Order_Support',
        label: 'Order Support',
        domain: 'Commerce',
        topicCount: 1,
        actionCount: 1,
        audited: true,
        grade: 'C',
        score: 60,
        energyWhCentral: 45648,
        latestReportId: 'R2',
        lastAudited: '2026-09-02T00:00:00Z'
    },
    {
        plannerId: 'P3',
        plannerApiName: 'Billing_Assistant',
        label: 'Billing Assistant',
        domain: 'Finance',
        topicCount: 2,
        actionCount: 3,
        audited: false,
        grade: null,
        score: null,
        energyWhCentral: null,
        latestReportId: null,
        lastAudited: null
    }
];

async function flush(times = 8) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

function create() {
    const el = createElement('c-ohm-fleet-table', { is: OhmFleetTable });
    document.body.appendChild(el);
    return el;
}

function rows(el) {
    return Array.from(el.shadowRoot.querySelectorAll('[data-id="row"]'));
}

describe('c-ohm-fleet-table', () => {
    beforeEach(() => {
        getFleet.mockReset();
        auditProcess.mockReset();
        getFleet.mockResolvedValue(JSON.parse(JSON.stringify(FLEET)));
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows a loading state, then renders rows from getFleet', async () => {
        const el = create();
        // before resolution
        expect(el.shadowRoot.querySelector('[data-id="loading"]')).not.toBeNull();

        await flush();
        expect(el.shadowRoot.querySelector('[data-id="loading"]')).toBeNull();
        expect(rows(el)).toHaveLength(3);
        expect(getFleet).toHaveBeenCalledTimes(1);
    });

    it('null-guards un-audited rows (Audit button) and decorates audited rows', async () => {
        const el = create();
        await flush();

        // audited row shows grade chip + energy + Open
        const openBtns = el.shadowRoot.querySelectorAll('[data-id="open"]');
        expect(openBtns).toHaveLength(2);
        const energy = el.shadowRoot.querySelector('[data-id="energy"]');
        expect(energy.textContent).toContain('82,486 Wh/yr');

        // un-audited row shows an Audit button
        const auditBtns = el.shadowRoot.querySelectorAll('[data-id="audit"]');
        expect(auditBtns).toHaveLength(1);
        expect(el.shadowRoot.textContent).toContain('Not audited yet');
    });

    it('renders the summary strip with null-guarded aggregates', async () => {
        const el = create();
        await flush();

        expect(
            el.shadowRoot.querySelector('[data-id="stat-audited"]').textContent
        ).toContain('2');
        expect(
            el.shadowRoot.querySelector('[data-id="stat-energy"]').textContent
        ).toContain('128,134 Wh/yr'); // 82486 + 45648
        expect(
            el.shadowRoot.querySelector('[data-id="stat-worst"]').textContent
        ).toContain('F');
    });

    it('audits a row: calls auditProcess then refreshes via getFleet', async () => {
        auditProcess.mockResolvedValue('NEWREPORT');
        // second getFleet call returns P3 now audited
        const refreshed = JSON.parse(JSON.stringify(FLEET));
        refreshed[2] = {
            ...refreshed[2],
            audited: true,
            grade: 'B',
            score: 80,
            energyWhCentral: 12000,
            latestReportId: 'R3'
        };
        getFleet
            .mockResolvedValueOnce(JSON.parse(JSON.stringify(FLEET)))
            .mockResolvedValueOnce(refreshed);

        const el = create();
        await flush();

        el.shadowRoot.querySelector('[data-id="audit"]').click();
        await flush();

        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P3' });
        expect(getFleet).toHaveBeenCalledTimes(2);
        // P3 now audited -> no Audit button remains
        expect(el.shadowRoot.querySelectorAll('[data-id="audit"]')).toHaveLength(
            0
        );
        expect(el.shadowRoot.querySelectorAll('[data-id="open"]')).toHaveLength(
            3
        );
    });

    it('surfaces an inline error when auditProcess fails', async () => {
        auditProcess.mockRejectedValue({ body: { message: 'boom' } });
        const el = create();
        await flush();

        el.shadowRoot.querySelector('[data-id="audit"]').click();
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="row-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('boom');
        // still shows Audit button to retry
        expect(el.shadowRoot.querySelector('[data-id="audit"]')).not.toBeNull();
    });

    it('fires openprocess with the planner id when Open is clicked', async () => {
        const el = create();
        await flush();
        const handler = jest.fn();
        el.addEventListener('openprocess', handler);

        el.shadowRoot.querySelector('[data-id="open"]').click();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.plannerId).toBe('P1');
        expect(handler.mock.calls[0][0].detail.label).toBe('Lead Concierge');
    });

    it('filters by domain', async () => {
        const el = create();
        await flush();

        const sel = el.shadowRoot.querySelector('[data-id="filter-domain"]');
        sel.value = 'Finance';
        sel.dispatchEvent(new CustomEvent('change'));
        await flush();

        const r = rows(el);
        expect(r).toHaveLength(1);
        expect(r[0].textContent).toContain('Billing Assistant');
    });

    it('searches over the label', async () => {
        const el = create();
        await flush();

        const search = el.shadowRoot.querySelector('[data-id="search"]');
        search.value = 'order';
        search.dispatchEvent(new CustomEvent('input'));
        await flush();

        const r = rows(el);
        expect(r).toHaveLength(1);
        expect(r[0].textContent).toContain('Order Support');
    });

    it('sorts by energy (audited descending first, un-audited last)', async () => {
        const el = create();
        await flush();
        // default sort is desc already; toggle to asc then check order
        const r = rows(el);
        // desc: Lead Concierge (82k), Order Support (45k), then un-audited
        expect(r[0].textContent).toContain('Lead Concierge');
        expect(r[1].textContent).toContain('Order Support');
        expect(r[2].textContent).toContain('Billing Assistant');
    });

    it('shows a load error with retry when getFleet rejects', async () => {
        getFleet.mockReset();
        getFleet.mockRejectedValue({ body: { message: 'no fleet' } });
        const el = create();
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="load-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('no fleet');
    });
});
