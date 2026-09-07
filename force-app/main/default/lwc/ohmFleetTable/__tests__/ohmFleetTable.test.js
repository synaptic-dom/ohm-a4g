import { createElement } from 'lwc';
import OhmFleetTable from 'c/ohmFleetTable';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';
import getAuditStatus from '@salesforce/apex/OhmAuditController.getAuditStatus';
import { pendingAudits, rememberAudit } from 'c/ohmAuditRun';
import { reviewSummaryFixture } from '../../../../../../test-fixtures/review/reviewFixture';
jest.mock('@salesforce/apex/OhmAuditController.getAuditStatus', () => ({ default: jest.fn() }), { virtual: true });

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

const PRIORITY_REVIEW = reviewSummaryFixture();
PRIORITY_REVIEW.categories[0].rating = 'C';
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
        reviewJson: JSON.stringify(PRIORITY_REVIEW),
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
        reviewJson: JSON.stringify(reviewSummaryFixture()),
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
        jest.useFakeTimers();
        sessionStorage.clear();
        getAuditStatus.mockReset();
        getAuditStatus.mockImplementation(({ reportId }) => Promise.resolve({ reportId, runStatus: 'Complete', stageMessage: 'Audit complete.', percentComplete: 100 }));
        getFleet.mockReset();
        auditProcess.mockReset();
        getFleet.mockResolvedValue(JSON.parse(JSON.stringify(FLEET)));
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllTimers();
        jest.useRealTimers();
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

        // reviewed row shows category chips; the modeled scenario stays secondary
        const openBtns = el.shadowRoot.querySelectorAll('[data-id="open"]');
        expect(openBtns).toHaveLength(2);
        expect(el.shadowRoot.querySelector('[data-id="energy"]')).toBeNull();

        // un-audited row shows an Audit button
        const auditBtns = el.shadowRoot.querySelectorAll('[data-id="audit"]');
        expect(auditBtns).toHaveLength(1);
        expect(el.shadowRoot.textContent).toContain('Review not run');
        expect(el.shadowRoot.querySelectorAll('[data-id="review-chips"]')).toHaveLength(2);
        expect(el.shadowRoot.querySelectorAll('.ohm-fleet__review-chip')).toHaveLength(6);
    });

    it('shows the reviewed count without modeled energy totals', async () => {
        const el = create(); await flush();
        expect(el.shadowRoot.querySelector('[data-id="stat-audited"]').textContent).toContain('2/3');
        expect(el.shadowRoot.textContent).not.toContain('Wh/yr');
        expect(el.shadowRoot.textContent).not.toContain('Model fit');
    });

    it('does not count old detector reports as reviewed and filters on category ratings', async () => {
        getFleet.mockResolvedValue(FLEET.map((row) => ({ ...row, reviewJson: null, grade: 'A' })));
        const baseline = create();
        await flush();
        expect(baseline.shadowRoot.querySelector('[data-id="stat-audited"]').textContent.trim()).toBe('0/3');
        expect(baseline.shadowRoot.querySelector('[data-id="review-chips"]')).toBeNull();
        expect(baseline.shadowRoot.textContent).toContain('Review not run');
        document.body.removeChild(baseline);
        getFleet.mockResolvedValue(FLEET);
        const reviewed = create();
        await flush();
        const select = reviewed.shadowRoot.querySelector('[data-id="filter-grade"]');
        select.value = 'B';
        select.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(rows(reviewed)).toHaveLength(1);
        expect(rows(reviewed)[0].textContent).toContain('Order Support');
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
            latestReportId: 'NEWREPORT'
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

    it('clears a search that has no matches', async () => {
        const el = create(); await flush();
        const search=el.shadowRoot.querySelector('[data-id="search"]');
        search.value='missing'; search.dispatchEvent(new CustomEvent('input')); await flush();
        expect(rows(el)).toHaveLength(0);
        el.shadowRoot.querySelector('[data-id="empty-filtered"] button').click(); await flush();
        expect(rows(el)).toHaveLength(3);
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

    it('puts priority fixes and improvement opportunities first', async () => {
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

    it('shows authentic retrieval progress without refreshing results prematurely', async () => {
        auditProcess.mockResolvedValue('R3');
        getAuditStatus.mockResolvedValueOnce({ runStatus: 'Discovering', stageMessage: 'Retrieving published source (1 of 2)', percentComplete: 20 });
        const el = create();
        await flush();
        el.shadowRoot.querySelector('[data-id="audit"]').click();
        await flush();
        expect(getFleet).toHaveBeenCalledTimes(1);
        expect(el.shadowRoot.querySelector('[data-id="audit"]').disabled).toBe(true);
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress').run.stageMessage).toBe('Retrieving published source (1 of 2)');
        const refreshed = FLEET.map((row) => row.plannerId === 'P3' ? { ...row, audited: true, latestReportId: 'R3', grade: 'IN' } : row);
        getFleet.mockResolvedValue(refreshed);
        jest.advanceTimersByTime(1500);
        await flush(16);
        expect(getFleet).toHaveBeenCalledTimes(2);
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress').run.runStatus).toBe('Complete');
        expect(pendingAudits()).toHaveLength(0);
    });

    it('resumes saved jobs and labels existing fleet estimates as previous completed results', async () => {
        rememberAudit({ plannerId: 'P1', reportId: 'R4', label: 'Lead Concierge', hadPriorAudit: true });
        getAuditStatus.mockResolvedValue({ runStatus: 'Analyzing', stageMessage: 'Running efficiency signals', percentComplete: 75 });
        const el = create();
        await flush();
        expect(auditProcess).not.toHaveBeenCalled();
        expect(getAuditStatus).toHaveBeenCalledWith({ reportId: 'R4' });
        expect(el.shadowRoot.textContent).toContain('Previous completed audit shown below');
        document.body.removeChild(el);
        jest.advanceTimersByTime(4500);
        await flush();
        expect(getAuditStatus).toHaveBeenCalledTimes(1);
        const returned = create();
        await flush();
        expect(returned.shadowRoot.querySelector('c-ohm-audit-progress').run.reportId).toBe('R4');
        expect(getAuditStatus).toHaveBeenCalledTimes(2);
    });

    it('does not mark an unmatched completed report as refreshed and resumes its result check', async () => {
        rememberAudit({ plannerId: 'P3', reportId: 'R3' });
        const el = create();
        await flush(16);
        const progress = el.shadowRoot.querySelector('c-ohm-audit-progress');
        expect(progress.run.error).toContain('results are not available yet');
        expect(pendingAudits()[0].reportId).toBe('R3');
        getFleet.mockResolvedValue(FLEET.map((row) => row.plannerId === 'P3' ? { ...row, audited: true, latestReportId: 'R3' } : row));
        progress.dispatchEvent(new CustomEvent('retry', { detail: { plannerId: 'P3' } }));
        await flush(16);
        expect(progress.run.error).toBeNull();
        expect(progress.run.runStatus).toBe('Complete');
        expect(auditProcess).not.toHaveBeenCalled();
        expect(pendingAudits()).toHaveLength(0);
    });

    it('clears a failed saved run and starts a new report only on explicit retry', async () => {
        rememberAudit({ plannerId: 'P3', reportId: 'R3' });
        getAuditStatus.mockResolvedValueOnce({ runStatus: 'Failed', stageMessage: 'Salesforce source retrieval failed.', percentComplete: 20 });
        const el = create();
        await flush();
        const progress = el.shadowRoot.querySelector('c-ohm-audit-progress');
        expect(progress.run.terminal).toBe(true);
        expect(pendingAudits()).toHaveLength(0);
        expect(getFleet).toHaveBeenCalledTimes(1);
        auditProcess.mockResolvedValue('R4');
        getAuditStatus.mockResolvedValue({ runStatus: 'Discovering', stageMessage: 'Retrieving published source', percentComplete: 20 });
        progress.dispatchEvent(new CustomEvent('retry', { detail: { plannerId: 'P3' } }));
        await flush();
        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P3' });
        expect(progress.run.reportId).toBe('R4');
        expect(progress.run.error).toBeNull();
    });

    it('ignores a delayed initial fleet response after fresh completion results arrive', async () => {
        let initialLoad;
        rememberAudit({ plannerId: 'P3', reportId: 'R3' });
        getFleet.mockReturnValueOnce(new Promise((resolve) => { initialLoad = resolve; }))
            .mockResolvedValue(FLEET.map((row) => row.plannerId === 'P3' ? { ...row, audited: true, latestReportId: 'R3', grade: 'B' } : row));
        const el = create();
        await flush(16);
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress').run.runStatus).toBe('Complete');
        initialLoad(FLEET);
        await flush();
        expect(el.shadowRoot.querySelectorAll('[data-id="open"]')).toHaveLength(3);
        expect(el.shadowRoot.querySelector('[data-id="audit"]')).toBeNull();
    });
});
