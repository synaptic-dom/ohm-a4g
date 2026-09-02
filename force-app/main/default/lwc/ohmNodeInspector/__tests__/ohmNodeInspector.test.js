import { createElement } from 'lwc';
import OhmNodeInspector from 'c/ohmNodeInspector';
import createRemediationTask from '@salesforce/apex/OhmAuditController.createRemediationTask';

jest.mock(
    '@salesforce/apex/OhmAuditController.createRemediationTask',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const LONG = 'A'.repeat(1800); // within budget
const EXCESS = 'B'.repeat(900); // pushes total past 2000 chars

const BLOAT_NODE = {
    id: 'TOPIC1',
    nodeType: 'Topic',
    apiName: 'Lead_Triage',
    label: 'Lead Triage',
    tokenCount: 1300,
    wasteful: true,
    signalType: 'INSTRUCTION_BLOAT',
    severity: 'High',
    instructions: LONG + EXCESS
};

const BLOAT_FINDING = {
    id: 'F1',
    signal: 'INSTRUCTION_BLOAT',
    severity: 'High',
    evidence: '1,300 tokens, ~800 over the 500-token budget',
    estimatedSavingsLow: 47041,
    estimatedSavingsCentral: 52921,
    estimatedSavingsHigh: 58802,
    fixType: 'Trim_Instructions',
    recommendedTarget: 'Trimmed Scope (≤ 500 tokens)',
    recommendationText: 'Cut the redundant tone guidance; keep the task contract.'
};

const CLEAN_NODE = {
    id: 'ACTION1',
    nodeType: 'Action',
    apiName: 'Classify_Lead_Tier',
    label: 'Classify Lead Tier',
    invocationTargetType: 'apex',
    tokenCount: 40,
    wasteful: false,
    instructions: 'Short deterministic action.'
};

function create(props = {}) {
    const el = createElement('c-ohm-node-inspector', { is: OhmNodeInspector });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

async function flush(times = 4) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

describe('c-ohm-node-inspector', () => {
    beforeEach(() => {
        createRemediationTask.mockReset();
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows the empty invitation when no node is selected', async () => {
        const el = create();
        await flush();
        const empty = el.shadowRoot.querySelector('[data-id="inspector-empty"]');
        expect(empty).not.toBeNull();
        expect(empty.textContent).toContain('Select a node to inspect it.');
    });

    it('renders the finding summary + savings band for a wasteful node', async () => {
        const el = create({ node: BLOAT_NODE, finding: BLOAT_FINDING });
        await flush();

        expect(
            el.shadowRoot.querySelector('[data-id="node-label"]').textContent
        ).toContain('Lead Triage');
        expect(
            el.shadowRoot.querySelector('[data-id="node-tokens"]').textContent
        ).toContain('1,300 tokens');
        expect(
            el.shadowRoot.querySelector('[data-id="node-signal"]').textContent
        ).toContain('Bloated instructions');
        expect(
            el.shadowRoot.querySelector('[data-id="node-severity"]').textContent
        ).toContain('High');
        expect(
            el.shadowRoot.querySelector('[data-id="node-savings"]').textContent
        ).toContain('52,921 Wh/yr');
    });

    it('highlights the over-budget excess of the instructions with a caption', async () => {
        const el = create({ node: BLOAT_NODE, finding: BLOAT_FINDING });
        await flush();

        const excess = el.shadowRoot.querySelector('[data-id="instr-excess"]');
        expect(excess).not.toBeNull();
        // excess is everything past the 2000-char soft budget
        expect(excess.textContent.length).toBe(
            BLOAT_NODE.instructions.length - 2000
        );
        const caption = el.shadowRoot.querySelector('[data-id="excess-caption"]');
        expect(caption.textContent).toContain('800 tokens over budget');
        expect(caption.textContent).toContain('re-sent every turn');
    });

    it('does not highlight when instructions are short', async () => {
        const shortNode = {
            ...BLOAT_NODE,
            tokenCount: 120,
            instructions: 'Short and tidy instructions.'
        };
        const el = create({ node: shortNode, finding: BLOAT_FINDING });
        await flush();
        expect(
            el.shadowRoot.querySelector('[data-id="instr-excess"]')
        ).toBeNull();
        expect(
            el.shadowRoot.querySelector('[data-id="excess-caption"]')
        ).toBeNull();
    });

    it('opens the fix panel and creates a remediation task from the finding', async () => {
        createRemediationTask.mockResolvedValue('00T000000000001');
        const el = create({
            node: BLOAT_NODE,
            finding: BLOAT_FINDING,
            reportId: 'R1'
        });
        await flush();

        // one relevant CTA (Trim) for a bloat node
        const cta = el.shadowRoot.querySelector('[data-id="fix-cta"]');
        expect(cta.textContent).toContain('Trim instructions');
        cta.click();
        await flush();

        const panel = el.shadowRoot.querySelector('[data-id="fix-panel"]');
        expect(panel).not.toBeNull();
        expect(
            el.shadowRoot.querySelector('[data-id="fix-rec"]').textContent
        ).toContain('Cut the redundant tone guidance');

        el.shadowRoot.querySelector('[data-id="create-task"]').click();
        await flush();

        expect(createRemediationTask).toHaveBeenCalledTimes(1);
        const arg = createRemediationTask.mock.calls[0][0].input;
        expect(arg.findingId).toBe('F1');
        expect(arg.reportId).toBe('R1');
        expect(arg.fixType).toBe('Trim_Instructions');
        expect(arg.estimatedSavingsCentralWh).toBe(52921);
        expect(
            el.shadowRoot.querySelector('[data-id="task-done"]')
        ).not.toBeNull();
    });

    it('surfaces an error when task creation fails', async () => {
        createRemediationTask.mockRejectedValue({ body: { message: 'nope' } });
        const el = create({ node: BLOAT_NODE, finding: BLOAT_FINDING });
        await flush();

        el.shadowRoot.querySelector('[data-id="fix-cta"]').click();
        await flush();
        el.shadowRoot.querySelector('[data-id="create-task"]').click();
        await flush();

        const err = el.shadowRoot.querySelector('[data-id="task-error"]');
        expect(err).not.toBeNull();
        expect(err.textContent).toContain('nope');
    });

    it('shows a quiet message for a clean node (no CTAs)', async () => {
        const el = create({ node: CLEAN_NODE });
        await flush();

        expect(
            el.shadowRoot.querySelector('[data-id="node-clean"]').textContent
        ).toContain('No waste found on this node.');
        expect(el.shadowRoot.querySelector('[data-id="fix-cta"]')).toBeNull();
        expect(
            el.shadowRoot.querySelector('[data-id="node-invocation"]').textContent
        ).toContain('apex');
    });

    it('resets transient task state when a different node is selected', async () => {
        createRemediationTask.mockResolvedValue('00T1');
        const el = create({ node: BLOAT_NODE, finding: BLOAT_FINDING });
        await flush();
        el.shadowRoot.querySelector('[data-id="fix-cta"]').click();
        await flush();
        el.shadowRoot.querySelector('[data-id="create-task"]').click();
        await flush();
        expect(
            el.shadowRoot.querySelector('[data-id="task-done"]')
        ).not.toBeNull();

        // switch node -> fix panel + done state cleared
        el.node = CLEAN_NODE;
        el.finding = null;
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="fix-panel"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="task-done"]')).toBeNull();
    });
});
