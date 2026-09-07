import { createElement } from 'lwc';
import OhmFindingsWorklist from 'c/ohmFindingsWorklist';
import getFindings from '@salesforce/apex/OhmAuditController.getFindings';
import updateFindingStatus from '@salesforce/apex/OhmAuditController.updateFindingStatus';
import assignFinding from '@salesforce/apex/OhmAuditController.assignFinding';

jest.mock(
    '@salesforce/apex/OhmAuditController.getFindings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.updateFindingStatus',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.assignFinding',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/user/Id', () => ({ default: '005000000000USER' }), {
    virtual: true
});

function mockItems() {
    return [
        {
            findingId: 'FIND-1',
            signal: 'INSTRUCTION_BLOAT',
            severity: 'High',
            confidence: 'Low',
            processLabel: 'Lead Concierge',
            plannerApiName: 'Lead_Concierge',
            artifactLabel: 'Lead Triage',
            savingsCentralWh: 52921,
            savingsLowWh: 47041,
            savingsHighWh: 58802,
            fixType: 'Trim_Instructions',
            recommendedTarget: 'Trim the scope',
            recommendationText: 'Cut 800 excess tokens from the topic scope.',
            findingStatus: 'Open',
            taskId: null,
            assigneeName: null,
            assigneeId: null,
            dueDate: null,
            effort: 'Low'
        },
        {
            findingId: 'FIND-2',
            signal: 'INSTRUCTION_BLOAT',
            severity: 'Medium',
            confidence: 'Low',
            processLabel: 'Order Support',
            plannerApiName: 'Order_Support',
            artifactLabel: 'Order Help',
            savingsCentralWh: 16083,
            savingsLowWh: 14000,
            savingsHighWh: 18000,
            fixType: 'Trim_Instructions',
            recommendedTarget: 'Trim the scope',
            recommendationText: 'Trim redundant guidance.',
            findingStatus: 'Accepted',
            taskId: '00T000000000001',
            assigneeName: 'Dom',
            assigneeId: '005000000000DOM',
            dueDate: '2026-09-05',
            effort: 'Medium'
        }
    ];
}

async function flush(times = 6) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

function create() {
    const el = createElement('c-ohm-findings-worklist', {
        is: OhmFindingsWorklist
    });
    document.body.appendChild(el);
    return el;
}

function rows(el) {
    return Array.from(el.shadowRoot.querySelectorAll('[data-id="row"]'));
}

describe('c-ohm-findings-worklist', () => {
    beforeEach(() => {
        getFindings.mockReset();
        updateFindingStatus.mockReset();
        assignFinding.mockReset();
        getFindings.mockResolvedValue(mockItems());
        updateFindingStatus.mockResolvedValue(undefined);
        assignFinding.mockResolvedValue('00T000000000009');
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('fetches on connect and renders a row per finding', async () => {
        const el = create();
        await flush();

        expect(getFindings).toHaveBeenCalledTimes(1);
        expect(getFindings.mock.calls[0][0]).toEqual({
            statusFilter: 'All',
            severityFilter: 'All'
        });
        expect(rows(el)).toHaveLength(2);
        // Severity and the source are readable without a modeled savings claim.
        expect(el.shadowRoot.textContent).toContain('High');
        expect(el.shadowRoot.textContent).not.toContain('Wh/yr');
        expect(el.shadowRoot.textContent).toContain('Lead Concierge');

        // Each row's status control reflects that finding's real status.
        const selects = el.shadowRoot.querySelectorAll('[data-id="row-status"]');
        expect(selects[0].value).toBe('Open'); // FIND-1
        expect(selects[1].value).toBe('Accepted'); // FIND-2
    });

    it('orders supporting checks by severity, with a reversible priority control', async () => {
        const el = create();
        await flush();
        expect(rows(el)[0].textContent).toContain('Lead Concierge');
        expect(rows(el)[1].textContent).toContain('Order Support');
        el.shadowRoot.querySelector('[data-id="sort-priority"]').click();
        await flush();
        expect(rows(el)[0].textContent).toContain('Order Support');
        expect(rows(el)[1].textContent).toContain('Lead Concierge');
    });

    it('changing a row status calls updateFindingStatus and refreshes', async () => {
        const el = create();
        await flush();

        const select = el.shadowRoot.querySelector('[data-id="row-status"]');
        select.value = 'Accepted';
        select.dispatchEvent(new CustomEvent('change'));
        await flush();

        expect(updateFindingStatus).toHaveBeenCalledTimes(1);
        expect(updateFindingStatus.mock.calls[0][0]).toEqual({
            findingId: 'FIND-1',
            status: 'Accepted'
        });
        // refresh -> getFindings called again (1 initial + 1 refresh)
        expect(getFindings).toHaveBeenCalledTimes(2);
    });

    it('assigning an open finding to me calls assignFinding with the user + due date', async () => {
        const el = create();
        await flush();

        // FIND-1 is unassigned -> it exposes the Assign toggle
        const toggle = el.shadowRoot.querySelector('[data-id="assign-toggle"]');
        expect(toggle).not.toBeNull();
        toggle.click();
        await flush();

        const date = el.shadowRoot.querySelector('[data-id="assign-date"]');
        date.value = '2026-09-10';
        date.dispatchEvent(new CustomEvent('change'));
        await flush();

        el.shadowRoot.querySelector('[data-id="assign-me"]').click();
        await flush();

        expect(assignFinding).toHaveBeenCalledTimes(1);
        expect(assignFinding.mock.calls[0][0]).toEqual({
            findingId: 'FIND-1',
            userId: '005000000000USER',
            dueDate: '2026-09-10'
        });
        expect(getFindings).toHaveBeenCalledTimes(2); // refresh
    });

    it('re-queries the server when the status filter changes', async () => {
        const el = create();
        await flush();

        const filter = el.shadowRoot.querySelector('[data-id="filter-status"]');
        filter.value = 'Applied';
        filter.dispatchEvent(new CustomEvent('change'));
        await flush();

        expect(getFindings).toHaveBeenCalledTimes(2);
        expect(getFindings.mock.calls[1][0]).toEqual({
            statusFilter: 'Applied',
            severityFilter: 'All'
        });
    });

    it('expands the recommendation detail for a row', async () => {
        const el = create();
        await flush();

        el.shadowRoot.querySelector('[data-id="expand"]').click();
        await flush();

        const reco = el.shadowRoot.querySelector('[data-id="reco"]');
        expect(reco).not.toBeNull();
        expect(reco.textContent).toContain('excess tokens');
    });

    it('shows an on-brand empty state when there are no findings', async () => {
        getFindings.mockResolvedValue([]);
        const el = create();
        await flush();

        const empty = el.shadowRoot.querySelector('[data-id="empty"]');
        expect(empty).not.toBeNull();
        expect(empty.textContent).toContain('No supporting check findings are waiting here');
    });

    it('surfaces a row error when a status update rejects', async () => {
        updateFindingStatus.mockRejectedValue({ body: { message: 'DML failed' } });
        const el = create();
        await flush();

        const select = el.shadowRoot.querySelector('[data-id="row-status"]');
        select.value = 'Dismissed';
        select.dispatchEvent(new CustomEvent('change'));
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="row-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('DML failed');
    });

    it('keeps the single dark interface accessible for existing callers', async () => {
        const dark = create();
        await flush();
        await expect(dark).toBeAccessible();

        const calm = createElement('c-ohm-findings-worklist', {
            is: OhmFindingsWorklist
        });
        calm.calmMode = true;
        document.body.appendChild(calm);
        await flush();
        await expect(calm).toBeAccessible();
    });
});
