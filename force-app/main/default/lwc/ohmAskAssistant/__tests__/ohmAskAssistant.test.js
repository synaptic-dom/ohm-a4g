import { createElement } from 'lwc';
import OhmAskAssistant from 'c/ohmAskAssistant';
import getAssistantContext from '@salesforce/apex/OhmAuditController.getArtifactAssistantContext';
import askAssistant from '@salesforce/apex/OhmAuditController.askArtifactAssistant';

jest.mock(
    '@salesforce/apex/OhmAuditController.getArtifactAssistantContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.askArtifactAssistant',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const CONTEXT = {
    plannerId: 'P1',
    processLabel: 'Lead Concierge (unoptimized)',
    greeting: 'Ask me about Lead Concierge.',
    groundingSummary: 'Grounded in Lead Concierge · grade F · 82,486 Wh/yr',
    groundedOn: ['Lead Triage scope (5,400 chars)', 'Bloated instructions / scope (High)'],
    quickPrompts: [
        { id: 'why', label: 'Why is this wasteful?', prompt: 'Explain why…' },
        { id: 'draft', label: 'Draft trimmed instructions', prompt: 'Draft a tightened…' }
    ],
    available: true,
    modelLabel: 'GPT 5.5 · Einstein Trust Layer'
};

const ANSWER = {
    answer: 'It is wasteful because the scope is bloated to 5,400 chars.',
    isDraft: false,
    groundedOn: CONTEXT.groundedOn,
    followUps: [{ id: 'draft', label: 'Draft trimmed instructions', prompt: 'Draft…' }],
    modelLabel: CONTEXT.modelLabel
};

const DRAFT = {
    answer: 'Here is a tightened version — 83% fewer characters.',
    isDraft: true,
    draftText: 'You are the Lead Triage specialist. Greet leads warmly.',
    beforeChars: 5400,
    afterChars: 914,
    beforeTokens: 1350,
    afterTokens: 229,
    groundedOn: CONTEXT.groundedOn,
    followUps: [],
    modelLabel: CONTEXT.modelLabel
};

function create(plannerId = 'P1', calmMode = false) {
    const el = createElement('c-ohm-ask-assistant', { is: OhmAskAssistant });
    el.calmMode = calmMode;
    el.processLabel = 'Lead Concierge (unoptimized)';
    el.plannerId = plannerId;
    document.body.appendChild(el);
    return el;
}

async function flush(times = 10) {
    for (let i = 0; i < times; i += 1) {
        // eslint-disable-next-line no-await-in-loop
        await Promise.resolve();
    }
}

describe('c-ohm-ask-assistant', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders grounding, chips, provenance and quick prompts from context', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        const el = create();
        await flush();

        expect(getAssistantContext).toHaveBeenCalledWith({ plannerId: 'P1', artifactKey: null });
        expect(el.shadowRoot.querySelector('[data-id="grounding"]').textContent).toContain(
            'Grounded in'
        );
        expect(el.shadowRoot.querySelector('[data-id="model-label"]').textContent).toContain(
            'Trust Layer'
        );
        expect(el.shadowRoot.querySelectorAll('[data-id="chips"] li')).toHaveLength(2);
        expect(el.shadowRoot.querySelectorAll('[data-id="quick-prompts"] button')).toHaveLength(2);
    });

    it('prefills a recommendation for review without sending and omits model-sizing suggestions', async () => {
        getAssistantContext.mockResolvedValue({ ...CONTEXT, quickPrompts: [CONTEXT.quickPrompts[0], { id: 'impact', label: 'Modeled impact', prompt: 'Explain modeled impact' }, { id: 'save', label: 'Review opportunities', prompt: 'Explain opportunities' }, CONTEXT.quickPrompts[1], { id: 'model', label: 'Review model fit', prompt: 'Downsize the model' }] });
        const el = create();
        el.prepareQuestion('Review this change and preserve escalation.');
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="input"]').value).toBe('Review this change and preserve escalation.');
        expect(el.shadowRoot.querySelector('[data-id="quick-prompts"]').textContent).not.toContain('model fit');
        expect(el.shadowRoot.querySelector('[data-id="quick-prompts"]').textContent).toContain('Draft trimmed instructions');
        expect(askAssistant).not.toHaveBeenCalled();
        expect(el.shadowRoot.querySelector('.ohm-ask__context').open).toBe(false);
    });

    it('prefills without taking focus when entering from a recommendation, but focuses on explicit Ask', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        const el = create();
        el.prepareQuestion('Review this recommendation.', false);
        await flush();
        const input = el.shadowRoot.querySelector('[data-id="input"]');
        expect(input.value).toBe('Review this recommendation.');
        expect(el.shadowRoot.activeElement).not.toBe(input);
        el.prepareQuestion('Explain this source.', true);
        await flush();
        expect(input.value).toBe('Explain this source.');
        expect(el.shadowRoot.activeElement).toBe(input);
        expect(askAssistant).not.toHaveBeenCalled();
    });

    it('retries failed source context without sending a question or losing its source binding', async () => {
        getAssistantContext.mockRejectedValueOnce({ body: { message: 'Connection interrupted' } }).mockResolvedValue(CONTEXT);
        const el = create();
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="ctx-error"]').textContent).toContain('Connection interrupted');
        el.shadowRoot.querySelector('[data-id="retry-context"]').click();
        await flush();
        expect(getAssistantContext).toHaveBeenLastCalledWith({ plannerId: 'P1', artifactKey: null });
        expect(el.shadowRoot.querySelector('[data-id="ctx-error"]')).toBeNull();
        expect(askAssistant).not.toHaveBeenCalled();
    });

    it('sends a question and renders the grounded answer with provenance', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        askAssistant.mockResolvedValue(ANSWER);
        const el = create();
        await flush();

        el.shadowRoot.querySelector('[data-id="quick-prompts"] button').click();
        await flush();

        expect(askAssistant).toHaveBeenCalled();
        const bubbles = el.shadowRoot.querySelectorAll('.ohm-ask__bubble');
        // user turn + ohm turn
        expect(bubbles.length).toBeGreaterThanOrEqual(2);
        const text = el.shadowRoot.textContent;
        expect(text).toContain('bloated to 5,400');
        expect(text).toContain('Trust Layer');
    });

    it('renders a draft rewrite with a before→after size readout and copy affordance', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        askAssistant.mockResolvedValue(DRAFT);
        const el = create();
        await flush();

        // type into the composer, then send with Enter
        const input = el.shadowRoot.querySelector('[data-id="input"]');
        input.value = 'draft the trimmed instructions';
        input.dispatchEvent(new Event('input'));
        await flush(2);
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
        await flush();

        const delta = el.shadowRoot.querySelector('[data-id="draft-delta"]');
        expect(delta).not.toBeNull();
        expect(delta.textContent).toContain('chars');
        expect(delta.textContent).toContain('tokens');
        expect(el.shadowRoot.querySelector('[data-id="draft-text"]').textContent).toContain(
            'Lead Triage specialist'
        );
        expect(el.shadowRoot.querySelector('.ohm-ask__copy')).not.toBeNull();
    });

    it('signs the draft delta as +N% when the rewrite came back longer (G5)', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        askAssistant.mockResolvedValue({
            ...DRAFT,
            draftText: 'x'.repeat(6000),
            beforeChars: 5400,
            afterChars: 6000,
            beforeTokens: 1350,
            afterTokens: 1500
        });
        const el = create();
        await flush();
        const input = el.shadowRoot.querySelector('[data-id="input"]');
        input.value = 'rewrite the instructions';
        input.dispatchEvent(new Event('input'));
        await flush(2);
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
        await flush();

        const badge = el.shadowRoot.querySelector('[data-id="draft-delta"] span');
        expect(badge.textContent).toContain('+');
        expect(badge.textContent).not.toContain('−-');
        expect(badge.className).toContain('warn');
    });

    it('exposes refresh() to re-ground after a re-audit (G4)', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        const el = create();
        await flush();
        expect(typeof el.refresh).toBe('function');
        getAssistantContext.mockClear();
        el.refresh();
        await flush();
        expect(getAssistantContext).toHaveBeenCalledWith({ plannerId: 'P1', artifactKey: null });
    });

    it('shows an unavailable state when the model is not reachable', async () => {
        getAssistantContext.mockResolvedValue({
            ...CONTEXT,
            available: false,
            unavailableReason: 'The Trust Layer model is not enabled on this org.'
        });
        const el = create();
        await flush();

        expect(el.shadowRoot.querySelector('[data-id="unavailable"]')).not.toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="input"]')).toBeNull();
    });
    it('sends the selected artifact and exact source hash for a rewrite', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        askAssistant.mockResolvedValue(DRAFT);
        const el = create();
        el.artifactKey = 'weather-topic';
        el.expectedSourceHash = 'source-hash';
        await flush();
        Array.from(el.shadowRoot.querySelectorAll('[data-id="quick-prompts"] button')).find((button) => button.dataset.prompt === 'Draft a tightened…').click();
        await flush();
        expect(askAssistant).toHaveBeenCalledWith({ plannerId: 'P1', artifactKey: 'weather-topic',
            expectedSourceHash: 'source-hash', question: 'Draft a tightened…', calmMode: false });
    });

    it('discards a draft if the selected artifact changes during the model call', async () => {
        getAssistantContext.mockResolvedValue(CONTEXT);
        let finish;
        askAssistant.mockImplementation(() => new Promise((resolve) => { finish = resolve; }));
        const el = create();
        el.artifactKey = 'first-topic'; el.expectedSourceHash = 'first-hash';
        await flush();
        el.shadowRoot.querySelectorAll('[data-id="quick-prompts"] button')[1].click();
        el.artifactKey = 'second-topic'; el.expectedSourceHash = 'second-hash';
        await flush();
        finish(DRAFT);
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="draft-text"]')).toBeNull();
    });

});
