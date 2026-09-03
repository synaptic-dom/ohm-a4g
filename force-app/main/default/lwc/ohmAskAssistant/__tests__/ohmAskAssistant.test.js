import { createElement } from 'lwc';
import OhmAskAssistant from 'c/ohmAskAssistant';
import getAssistantContext from '@salesforce/apex/OhmAuditController.getAssistantContext';
import askAssistant from '@salesforce/apex/OhmAuditController.askAssistant';

jest.mock(
    '@salesforce/apex/OhmAuditController.getAssistantContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/OhmAuditController.askAssistant',
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
    modelLabel: 'GPT-4o mini · Einstein Trust Layer'
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

        expect(getAssistantContext).toHaveBeenCalledWith({ plannerId: 'P1' });
        expect(el.shadowRoot.querySelector('[data-id="grounding"]').textContent).toContain(
            'Grounded in'
        );
        expect(el.shadowRoot.querySelector('[data-id="model-label"]').textContent).toContain(
            'Trust Layer'
        );
        expect(el.shadowRoot.querySelectorAll('[data-id="chips"] li')).toHaveLength(2);
        expect(el.shadowRoot.querySelectorAll('[data-id="quick-prompts"] button')).toHaveLength(2);
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
});
