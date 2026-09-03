import { createElement } from 'lwc';
import OhmProcessPage from 'c/ohmProcessPage';
import getProcessDetail from '@salesforce/apex/OhmAuditController.getProcessDetail';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';

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
        getProcessDetail.mockReset();
        auditProcess.mockReset();
        getProcessDetail.mockResolvedValue(JSON.parse(JSON.stringify(AUDITED)));
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('loads the detail then renders the header, graph and inspector', async () => {
        const el = create('P1');
        await flush();

        expect(getProcessDetail).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(
            el.shadowRoot.querySelector('[data-id="process-label"]').textContent
        ).toContain('Lead Concierge');
        expect(
            el.shadowRoot.querySelector('[data-id="grade-chip"]').textContent
        ).toContain('F');
        expect(
            el.shadowRoot.querySelector('[data-id="process-energy"]').textContent
        ).toContain('82,486 Wh/yr');

        const graph = el.shadowRoot.querySelector('[data-id="call-graph"]');
        expect(graph).not.toBeNull();
        expect(graph.nodes).toHaveLength(3);
        expect(
            el.shadowRoot.querySelector('[data-id="node-inspector"]')
        ).not.toBeNull();
        // assistant seam present
        expect(
            el.shadowRoot.querySelector('[data-id="assistant-strip"]')
        ).not.toBeNull();
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
        const el = create('P1');
        await flush();

        el.shadowRoot.querySelector('[data-id="reaudit"]').click();
        await flush();

        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P1' });
        // once on load, once after re-audit
        expect(getProcessDetail).toHaveBeenCalledTimes(2);
    });

    it('shows the "Audit this process" CTA for an unaudited process', async () => {
        getProcessDetail.mockReset();
        getProcessDetail.mockResolvedValue(JSON.parse(JSON.stringify(UNAUDITED)));
        auditProcess.mockResolvedValue('R9');
        const el = create('P2');
        await flush();

        // no grade chip, a prominent audit CTA + unaudited note instead
        expect(el.shadowRoot.querySelector('[data-id="grade-chip"]')).toBeNull();
        const cta = el.shadowRoot.querySelector('[data-id="audit-cta"]');
        expect(cta).not.toBeNull();
        expect(cta.textContent).toContain('Audit this process');
        expect(
            el.shadowRoot.querySelector('[data-id="unaudited-note"]')
        ).not.toBeNull();

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

    it('auto-reveals the diff after a re-audit of an already-audited process', async () => {
        auditProcess.mockResolvedValue('R2');
        const el = create('P1');
        await flush();

        expect(el.shadowRoot.querySelector('[data-id="diff-view"]')).toBeNull();
        el.shadowRoot.querySelector('[data-id="reaudit"]').click();
        await flush();

        expect(auditProcess).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(
            el.shadowRoot.querySelector('[data-id="diff-view"]')
        ).not.toBeNull();
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
});
