import { createElement } from 'lwc';
import OhmCallGraph from 'c/ohmCallGraph';

const NODES = [
    {
        id: 'AGENT1',
        nodeType: 'Agent',
        apiName: 'Lead_Concierge',
        label: 'Lead Concierge',
        parentId: null,
        wasteful: false
    },
    {
        id: 'TOPIC1',
        nodeType: 'Topic',
        apiName: 'Lead_Triage',
        label: 'Lead Triage',
        parentId: 'AGENT1',
        wasteful: true,
        signalType: 'INSTRUCTION_BLOAT',
        severity: 'High'
    },
    {
        id: 'ACTION1',
        nodeType: 'Action',
        apiName: 'Classify_Lead_Tier',
        label: 'Classify Lead Tier',
        parentId: 'TOPIC1',
        wasteful: false
    }
];

function create(props = {}) {
    const el = createElement('c-ohm-call-graph', { is: OhmCallGraph });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

function nodeButtons(el) {
    return Array.from(el.shadowRoot.querySelectorAll('[data-id="graph-node"]'));
}

async function flush() {
    await Promise.resolve();
}

describe('c-ohm-call-graph', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders one button per node from the parentId tree', async () => {
        const el = create({ nodes: NODES });
        await flush();

        const btns = nodeButtons(el);
        expect(btns).toHaveLength(3);
        const labels = btns.map((b) => b.textContent);
        expect(labels.some((t) => t.includes('Lead Concierge'))).toBe(true);
        expect(labels.some((t) => t.includes('Lead Triage'))).toBe(true);
        expect(labels.some((t) => t.includes('Classify Lead Tier'))).toBe(true);

        // an SVG edge is drawn for each parent→child link (agent→topic, topic→action)
        const edges = el.shadowRoot.querySelectorAll('path');
        expect(edges.length).toBe(2);
    });

    it('flags the wasteful node with a ⚠ marker + amber class, clean node quiet', async () => {
        const el = create({ nodes: NODES });
        await flush();

        const waste = nodeButtons(el).find((b) =>
            b.getAttribute('aria-label').includes('Lead Triage')
        );
        expect(waste.className).toContain('ohm-graph__node--waste');
        expect(waste.textContent).toContain('⚠');
        expect(waste.getAttribute('aria-label')).toContain('flagged wasteful');

        const clean = nodeButtons(el).find((b) =>
            b.getAttribute('aria-label').includes('Classify Lead Tier')
        );
        expect(clean.className).toContain('ohm-graph__node--clean');
        expect(clean.getAttribute('aria-label')).toContain('clean');
    });

    it('fires selectnode with the clicked node id', async () => {
        const el = create({ nodes: NODES });
        await flush();
        const handler = jest.fn();
        el.addEventListener('selectnode', handler);

        const waste = nodeButtons(el).find((b) =>
            b.getAttribute('aria-label').includes('Lead Triage')
        );
        waste.click();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.nodeId).toBe('TOPIC1');
    });

    it('marks the selected node with the selected class + aria-pressed', async () => {
        const el = create({ nodes: NODES, selectedNodeId: 'TOPIC1' });
        await flush();

        const waste = nodeButtons(el).find((b) =>
            b.getAttribute('aria-label').includes('Lead Triage')
        );
        expect(waste.className).toContain('ohm-graph__node--selected');
        expect(waste.getAttribute('aria-pressed')).toBe('true');
    });

    it('shows an empty message when there are no nodes', async () => {
        const el = create({ nodes: [] });
        await flush();
        expect(
            el.shadowRoot.querySelector('[data-id="graph-empty"]')
        ).not.toBeNull();
        expect(nodeButtons(el)).toHaveLength(0);
    });
});
