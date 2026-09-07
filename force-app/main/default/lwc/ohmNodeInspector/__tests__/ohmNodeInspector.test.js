import { createElement } from 'lwc';
import OhmNodeInspector from 'c/ohmNodeInspector';
import createRemediationTask from '@salesforce/apex/OhmAuditController.createFindingRemediationTask';

jest.mock(
    '@salesforce/apex/OhmAuditController.createFindingRemediationTask',
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
        expect(empty.textContent).toContain('Select a source above or open one from a recommendation.');
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
        expect(caption.textContent).toContain('800 tokens over the modeled instruction budget');
        expect(caption.textContent).not.toContain('re-sent every turn');
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

    it('presents unknown model evidence as a review rather than an oversized-model claim', async () => {
        const el = create({
            node: { ...CLEAN_NODE, wasteful: true, signalType: 'MODEL_RIGHTSIZING' },
            finding: { id: 'MODEL1', signal: 'MODEL_RIGHTSIZING', evidence: 'model unknown', fixType: null }
        });
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="node-signal"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="fix-cta"]')).toBeNull();
        expect(el.shadowRoot.textContent).not.toContain('Model larger than the task needs');
        expect(el.shadowRoot.textContent).not.toContain('Downsize / swap model');
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
        expect(createRemediationTask).toHaveBeenCalledWith({ findingId: 'F1', note: null });
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
        ).toContain('No detector finding recorded for this source.');
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

    it('identifies a retrieved publication with its exact version, retrieval time and artifact', async () => {
        const el = create({ node: { ...BLOAT_NODE, sourceKind: 'RetrievedAgentScript', sourceBindingVerified: true,
            sourceVersionIdentifier: 'WeatherLookup_v7', sourceRetrievedAt: '2026-09-07T15:42:19.000Z',
            sourceApiName: 'WeatherLookup', sourcePath: 'Salesforce#reasoning.instructions', sourceHash: 'sha256-example' } });
        await flush();
        const panel = el.shadowRoot.querySelector('[data-id="source-handoff"]');
        expect(panel.textContent).toContain('Retrieved from Salesforce');
        expect(panel.textContent).toContain('Matched to the selected published version at retrieval time.');
        expect(panel.querySelector('[data-id="source-version"]').textContent).toBe('WeatherLookup_v7');
        expect(panel.querySelector('[data-id="source-time"]').textContent).toBe('2026-09-07 15:42:19 UTC');
        expect(panel.textContent).toContain('WeatherLookup');
        expect(panel.textContent).toContain('sha256-example');
    });

    it('labels imported instructions as a snapshot and does not claim Salesforce retrieval', async () => {
        const el = create({ node: { ...BLOAT_NODE, sourceKind: 'ImportedAgentScript', sourceVersion: 'git-revision:full-file-hash', sourcePath: '/fixtures/weather.agent#instructions' } });
        await flush();
        const panel = el.shadowRoot.querySelector('[data-id="source-handoff"]');
        expect(panel.textContent).toContain('Imported source snapshot');
        expect(panel.textContent).toContain('Run a fresh audit to retrieve the published Salesforce source.');
        expect(panel.textContent).not.toContain('Retrieved from Salesforce');
        expect(panel.querySelector('[data-id="source-version"]').textContent).toBe('git-revision:full-file-hash');
    });

    it('makes unavailable instructions and unverified retrieval explicit', async () => {
        const el = create({ node: { ...CLEAN_NODE, instructions: null } });
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="source-status"]').textContent).toContain('no available instruction text');
        expect(el.shadowRoot.querySelector('[data-id="source-time"]')).toBeNull();
        el.node = { ...CLEAN_NODE, sourceKind: 'RetrievedPromptTemplate', sourceBindingVerified: false };
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="source-status"]').textContent).toContain('publication matching has not been verified');
    });
});
