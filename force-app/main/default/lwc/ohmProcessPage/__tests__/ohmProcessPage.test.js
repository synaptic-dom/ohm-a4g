import { createElement } from 'lwc';
import OhmProcessPage from 'c/ohmProcessPage';
import getProcessDetail from '@salesforce/apex/OhmAuditController.getProcessDetail';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';
import getAuditStatus from '@salesforce/apex/OhmAuditController.getAuditStatus';
import { pendingAudits, rememberAudit } from 'c/ohmAuditRun';
import { reviewFixture } from '../../../../../../test-fixtures/review/reviewFixture';
import getAssistantContext from '@salesforce/apex/OhmAuditController.getArtifactAssistantContext';
import askAssistant from '@salesforce/apex/OhmAuditController.askArtifactAssistant';
jest.mock('@salesforce/apex/OhmAuditController.getArtifactAssistantContext', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.askArtifactAssistant', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/OhmAuditController.getAuditStatus', () => ({ default: jest.fn() }), { virtual: true });

jest.mock(
    '@salesforce/apex/OhmAuditController.getProcessDetail',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.auditProcess',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
// child inspector imports this
jest.mock(
    '@salesforce/apex/OhmAuditController.createRemediationTask',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
// child diff-view (revealed via "Compare last two audits") imports this
jest.mock(
    '@salesforce/apex/OhmAuditController.getDiff',
    () =>
        ({
            default: jest.fn(() =>
                Promise.resolve({ plannerId: 'P1', beforeReportId: null, afterReportId: 'R1' })
            )
        }),
    { virtual: true }
);

const NODES = [
    { id: 'AGENT1', nodeType: 'Agent', apiName: 'Lead_Concierge', label: 'Lead Concierge', parentId: null, wasteful: false },
    {
        id: 'TOPIC1',
        artifactKey: 'bundle|Topic|triage',
        sourceHash: 'source-hash',
        nodeType: 'Topic',
        apiName: 'Lead_Triage',
        label: 'Lead Triage',
        parentId: 'AGENT1',
        wasteful: true,
        signalType: 'INSTRUCTION_BLOAT',
        severity: 'High',
        tokenCount: 1300,
        instructions: 'x'.repeat(2500)
    },
    { id: 'ACTION1', nodeType: 'Action', apiName: 'Classify_Lead_Tier', label: 'Classify Lead Tier', parentId: 'TOPIC1', wasteful: false, instructions: 'ok' }
];

const AUDITED = {
    plannerId: 'P1',
    plannerApiName: 'Lead_Concierge',
    label: 'Lead Concierge',
    domain: 'Sales',
    grade: 'F',
    score: 22,
    energyWhCentral: 82486,
    reportId: 'R1',
    reviewJson: JSON.stringify(reviewFixture()),
    findings: [
        {
            id: 'F1',
            signal: 'INSTRUCTION_BLOAT',
            severity: 'High',
            artifactType: 'Topic',
            targetArtifact: { apiName: 'Lead_Triage', toolingId: 'TOPIC1' },
            evidence: '1,300 tokens',
            estimatedSavingsCentral: 52921,
            fixType: 'Trim_Instructions',
            recommendationText: 'Trim it.'
        }
    ],
    nodes: NODES
};

const UNAUDITED = {
    plannerId: 'P2',
    plannerApiName: 'Billing_Assistant',
    label: 'Billing Assistant',
    domain: 'Finance',
    grade: null,
    score: null,
    energyWhCentral: null,
    reportId: null,
    findings: [],
    nodes: NODES
};

function create(plannerId = 'P1') {
    const el = createElement('c-ohm-process-page', { is: OhmProcessPage });
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

describe('c-ohm-process-page', () => {
    beforeEach(() => {
        jest.useFakeTimers();
        sessionStorage.clear();
        getAuditStatus.mockReset();
        getAuditStatus.mockImplementation(({ reportId }) => Promise.resolve({ reportId, runStatus: 'Complete', stageMessage: 'Audit complete.', percentComplete: 100 }));
        getProcessDetail.mockReset();
        auditProcess.mockReset();
        getProcessDetail.mockResolvedValue(JSON.parse(JSON.stringify(AUDITED)));
        getAssistantContext.mockReset();
        getAssistantContext.mockResolvedValue({ available: true, quickPrompts: [], groundedOn: [] });
        askAssistant.mockReset();
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllTimers();
        jest.useRealTimers();
    });

    it('loads the detail then renders the header, graph and inspector', async () => {
        const el = create('P1');
        await flush();

        expect(getProcessDetail).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(
            el.shadowRoot.querySelector('[data-id="process-label"]').textContent
        ).toContain('Lead Concierge');
        expect(
            el.shadowRoot.querySelector('[data-id="legacy-grade"]').textContent
        ).toContain('Legacy detector grade: F');
        expect(
            el.shadowRoot.querySelector('[data-id="process-energy"]').textContent
        ).toContain('82,486 Wh/yr');
        expect(el.shadowRoot.querySelector('[data-id="supporting-evidence"]').open).toBe(false);
        expect(el.shadowRoot.querySelector('[data-id="grade-chip"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="review-panel"]').reviewJson).toBe(AUDITED.reviewJson);
        expect(el.shadowRoot.querySelector('[aria-label="Bundle structure"]')).not.toBeNull();

        const graph = el.shadowRoot.querySelector('[data-id="call-graph"]');
        expect(graph).not.toBeNull();
        expect(graph.nodes).toHaveLength(3);
        expect(
            el.shadowRoot.querySelector('[data-id="node-inspector"]')
        ).toBeNull();
        // The assistant is mounted only after a source is opened.
        const assistant = el.shadowRoot.querySelector('[data-id="ask-assistant"]');
        expect(assistant).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="source-workspace"]').open).toBe(false);
        expect(getAssistantContext).not.toHaveBeenCalled();
    });

    it('renders Review not run for a baseline detector report without inventing a new review', async () => {
        getProcessDetail.mockResolvedValue({ ...AUDITED, reviewJson: null, grade: 'A' });
        const el = create();
        await flush();
        const panel = el.shadowRoot.querySelector('[data-id="review-panel"]');
        expect(panel.shadowRoot.querySelector('h2').textContent).toBe('Review not run');
        expect(panel.shadowRoot.querySelector('[data-id="category-card"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="supporting-evidence"]').open).toBe(false);
    });

    it('passes the selected node + matching finding to the inspector on selectnode', async () => {
        const el = create('P1');
        await flush();

        const graph = el.shadowRoot.querySelector('[data-id="call-graph"]');
        graph.dispatchEvent(
            new CustomEvent('selectnode', {
                detail: { nodeId: 'TOPIC1' },
                bubbles: true,
                composed: true
            })
        );
        await flush();

        const inspector = el.shadowRoot.querySelector(
            '[data-id="node-inspector"]'
        );
        expect(inspector.node.id).toBe('TOPIC1');
        expect(inspector.finding.id).toBe('F1');
        expect(inspector.reportId).toBe('R1');
        expect(graph.selectedNodeId).toBe('TOPIC1');
    });

    it('re-audits: calls auditProcess then reloads getProcessDetail', async () => {
        auditProcess.mockResolvedValue('R2');
        getProcessDetail.mockResolvedValueOnce(AUDITED).mockResolvedValue({ ...AUDITED, reportId: 'R2' });
        const el = create('P1');
        await flush();

        el.shadowRoot.querySelector('[data-id="reaudit"]').click();
        await flush();

        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P1' });
        // once on load, once after re-audit
        expect(getProcessDetail).toHaveBeenCalledTimes(2);
    });

    it('shows the "Audit this bundle" CTA for an unaudited bundle', async () => {
        getProcessDetail.mockReset();
        getProcessDetail.mockResolvedValue(JSON.parse(JSON.stringify(UNAUDITED)));
        auditProcess.mockResolvedValue('R9');
        const el = create('P2');
        await flush();

        // no grade chip, a prominent audit CTA + unaudited note instead
        expect(el.shadowRoot.querySelector('[data-id="grade-chip"]')).toBeNull();
        const cta = el.shadowRoot.querySelector('[data-id="audit-cta"]');
        expect(cta).not.toBeNull();
        expect(cta.textContent).toContain('Audit this bundle');
        expect(
            el.shadowRoot.querySelector('[data-id="review-panel"]').shadowRoot.querySelector('h2').textContent
        ).toBe('Review not run');

        cta.click();
        await flush();
        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P2' });
    });

    it('reveals the before/after diff view from the compare toggle', async () => {
        const el = create('P1');
        await flush();

        // toggle present for an audited process; diff hidden until clicked
        const toggle = el.shadowRoot.querySelector('[data-id="compare-toggle"]');
        expect(toggle).not.toBeNull();
        expect(toggle.textContent).toContain('Compare last two audits');
        expect(el.shadowRoot.querySelector('[data-id="diff-view"]')).toBeNull();

        toggle.click();
        await flush();

        const diff = el.shadowRoot.querySelector('[data-id="diff-view"]');
        expect(diff).not.toBeNull();
        expect(diff.plannerId).toBe('P1');
    });

    it('keeps comparison secondary after a completed re-audit', async () => {
        auditProcess.mockResolvedValue('R2');
        getProcessDetail.mockResolvedValueOnce(AUDITED).mockResolvedValue({ ...AUDITED, reportId: 'R2' });
        const el = create('P1');
        await flush();

        expect(el.shadowRoot.querySelector('[data-id="diff-view"]')).toBeNull();
        el.shadowRoot.querySelector('[data-id="reaudit"]').click();
        await flush();

        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(
            el.shadowRoot.querySelector('[data-id="diff-view"]')
        ).toBeNull();
    });

    it('opens a recommendation source and prefills Ask Ohm without making a model call', async () => {
        const el = create();
        await flush();
        el.shadowRoot.querySelector('[data-id="review-panel"]').dispatchEvent(new CustomEvent('reviewaction', { detail: { artifactId: 'TOPIC1', artifactKey: 'bundle|Topic|triage', intent: 'draft', question: 'Help me preserve the escalation requirement.' } }));
        await flush(16);
        const assistant = el.shadowRoot.querySelector('[data-id="ask-assistant"]');
        expect(el.shadowRoot.querySelector('[data-id="source-workspace"]').open).toBe(true);
        expect(assistant.artifactKey).toBe('bundle|Topic|triage');
        expect(assistant.expectedSourceHash).toBe('source-hash');
        expect(assistant.shadowRoot.querySelector('[data-id="input"]').value).toContain('preserve the escalation requirement');
        expect(el.shadowRoot.activeElement).toBe(el.shadowRoot.querySelector('[data-id="workspace-heading"]'));
        expect(assistant.shadowRoot.activeElement).not.toBe(assistant.shadowRoot.querySelector('[data-id="input"]'));
        expect(askAssistant).not.toHaveBeenCalled();
    });

    it('honors deep links after asynchronous detail loading', async () => {
        const el = createElement('c-ohm-process-page', { is: OhmProcessPage });
        el.initialNodeId = 'TOPIC1';
        el.initialIntent = 'source';
        el.plannerId = 'P1';
        document.body.appendChild(el);
        await flush(16);
        expect(el.shadowRoot.querySelector('[data-id="node-inspector"]').node.id).toBe('TOPIC1');
        expect(el.shadowRoot.querySelector('[data-id="source-workspace"]').open).toBe(true);
    });

    it('offers no compare affordance for an unaudited process', async () => {
        getProcessDetail.mockReset();
        getProcessDetail.mockResolvedValue(JSON.parse(JSON.stringify(UNAUDITED)));
        const el = create('P2');
        await flush();

        expect(
            el.shadowRoot.querySelector('[data-id="compare-toggle"]')
        ).toBeNull();
    });

    it('fires backtofleet from the back affordance', async () => {
        const el = create('P1');
        await flush();
        const handler = jest.fn();
        el.addEventListener('backtofleet', handler);

        el.shadowRoot.querySelector('[data-id="back"]').click();
        expect(handler).toHaveBeenCalled();
    });

    it('shows a load error with retry when getProcessDetail rejects', async () => {
        getProcessDetail.mockReset();
        getProcessDetail.mockRejectedValue({ body: { message: 'boom' } });
        const el = create('P1');
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="load-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('boom');
    });

    it('waits through retrieval and version validation before showing the exact completed report', async () => {
        auditProcess.mockResolvedValue('R2');
        getProcessDetail.mockResolvedValueOnce(AUDITED).mockResolvedValue({ ...AUDITED, reportId: 'R2', grade: 'B' });
        getAuditStatus
            .mockResolvedValueOnce({ runStatus: 'Discovering', stageMessage: 'Waiting for Salesforce source retrieval', percentComplete: 25 })
            .mockResolvedValueOnce({ runStatus: 'Discovering', stageMessage: 'Validating source evidence', percentComplete: 55 })
            .mockResolvedValueOnce({ runStatus: 'Analyzing', stageMessage: 'Running efficiency signals', percentComplete: 75 });
        const el = create();
        await flush();
        el.shadowRoot.querySelector('[data-id="reaudit"]').click();
        await flush();
        expect(getProcessDetail).toHaveBeenCalledTimes(1);
        expect(el.shadowRoot.querySelector('[data-id="grade-chip"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="call-graph"]')).toBeNull();
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress').run.stageMessage).toBe('Waiting for Salesforce source retrieval');
        expect(pendingAudits()[0].reportId).toBe('R2');
        jest.advanceTimersByTime(1500);
        await flush();
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress').run.stageMessage).toBe('Validating source evidence');
        jest.advanceTimersByTime(1500);
        await flush();
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress').run.runStatus).toBe('Analyzing');
        expect(getProcessDetail).toHaveBeenCalledTimes(1);
        jest.advanceTimersByTime(1500);
        await flush(16);
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress').run.runStatus).toBe('Complete');
        expect(el.shadowRoot.querySelector('[data-id="legacy-grade"]').textContent).toContain('Legacy detector grade: B');
        expect(el.shadowRoot.querySelector('[data-id="review-panel"]').reviewJson).toBe(AUDITED.reviewJson);
        expect(pendingAudits()).toHaveLength(0);
        expect(getProcessDetail).toHaveBeenCalledTimes(2);
    });

    it('keeps the previous report hidden if completed results have not reached detail yet', async () => {
        auditProcess.mockResolvedValue('R2');
        const el = create();
        await flush();
        el.shadowRoot.querySelector('[data-id="reaudit"]').click();
        await flush(16);
        const progress = el.shadowRoot.querySelector('c-ohm-audit-progress');
        expect(progress.run.error).toContain('results are not available yet');
        expect(progress.run.terminal).toBe(false);
        expect(el.shadowRoot.querySelector('[data-id="grade-chip"]')).toBeNull();
        expect(pendingAudits()[0].reportId).toBe('R2');
        getProcessDetail.mockResolvedValue({ ...AUDITED, reportId: 'R2' });
        progress.dispatchEvent(new CustomEvent('retry'));
        await flush(16);
        expect(auditProcess).toHaveBeenCalledTimes(1);
        expect(el.shadowRoot.querySelector('[data-id="review-panel"]')).not.toBeNull();
        expect(pendingAudits()).toHaveLength(0);
    });

    it('resumes a pending audit after refresh without starting a duplicate and cancels disconnected polls', async () => {
        auditProcess.mockResolvedValue('R2');
        getAuditStatus.mockResolvedValue({ runStatus: 'Discovering', stageMessage: 'Retrieving published source', percentComplete: 25 });
        const first = create();
        await flush();
        first.shadowRoot.querySelector('[data-id="reaudit"]').click();
        await flush();
        document.body.removeChild(first);
        jest.advanceTimersByTime(4500);
        await flush();
        expect(getAuditStatus).toHaveBeenCalledTimes(1);
        const next = create();
        await flush();
        expect(getAuditStatus).toHaveBeenLastCalledWith({ reportId: 'R2' });
        expect(getAuditStatus).toHaveBeenCalledTimes(2);
        expect(auditProcess).toHaveBeenCalledTimes(1);
        expect(next.shadowRoot.querySelector('[data-id="call-graph"]')).toBeNull();
        expect(next.shadowRoot.querySelector('c-ohm-audit-progress').run.reportId).toBe('R2');
    });

    it('retains a run after a connection error and resumes checking the same report', async () => {
        rememberAudit({ plannerId: 'P1', reportId: 'R2', label: 'Lead Concierge' });
        getAuditStatus.mockRejectedValueOnce({ body: { message: 'Connection interrupted' } });
        const el = create();
        await flush();
        const progress = el.shadowRoot.querySelector('c-ohm-audit-progress');
        expect(progress.run.error).toBe('Connection interrupted');
        expect(progress.run.terminal).toBe(false);
        expect(pendingAudits()).toHaveLength(1);
        getProcessDetail.mockResolvedValue({ ...AUDITED, reportId: 'R2' });
        progress.dispatchEvent(new CustomEvent('retry'));
        await flush(16);
        expect(auditProcess).not.toHaveBeenCalled();
        expect(getAuditStatus).toHaveBeenCalledTimes(2);
        expect(progress.run.runStatus).toBe('Complete');
        expect(pendingAudits()).toHaveLength(0);
    });

    it('shows a terminal retrieval failure and retries as a new audit', async () => {
        rememberAudit({ plannerId: 'P1', reportId: 'R2' });
        getAuditStatus.mockResolvedValueOnce({ runStatus: 'Failed', stageMessage: 'Published version changed. Refresh the fleet and audit again.', percentComplete: 30 });
        const el = create();
        await flush();
        const progress = el.shadowRoot.querySelector('c-ohm-audit-progress');
        expect(progress.run.terminal).toBe(true);
        expect(progress.run.error).toContain('Published version changed');
        expect(pendingAudits()).toHaveLength(0);
        auditProcess.mockResolvedValue('R3');
        getProcessDetail.mockResolvedValue({ ...AUDITED, reportId: 'R3' });
        progress.dispatchEvent(new CustomEvent('retry'));
        await flush(16);
        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(progress.run.reportId).toBe('R3');
        expect(progress.run.runStatus).toBe('Complete');
    });

    it('does not let an old planner status or delayed detail replace the selected process', async () => {
        let resolveStatus;
        rememberAudit({ plannerId: 'P1', reportId: 'R2' });
        getAuditStatus.mockReturnValue(new Promise((resolve) => { resolveStatus = resolve; }));
        const el = create();
        await flush();
        getProcessDetail.mockResolvedValue(UNAUDITED);
        el.plannerId = 'P2';
        await flush();
        resolveStatus({ runStatus: 'Complete', percentComplete: 100 });
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="process-label"]').textContent).toContain('Billing Assistant');
        expect(el.shadowRoot.querySelector('c-ohm-audit-progress')).toBeNull();
        expect(pendingAudits()[0].plannerId).toBe('P1');
        expect(getProcessDetail).toHaveBeenCalledTimes(2);
    });
});
