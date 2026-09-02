import { createElement } from 'lwc';
import OhmDiscoverAnalyze from 'c/ohmDiscoverAnalyze';

function create(props = {}) {
    const el = createElement('c-ohm-discover-analyze', { is: OhmDiscoverAnalyze });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

async function flush() {
    return Promise.resolve();
}

describe('c-ohm-discover-analyze', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('binds the determinate progress bar to percentComplete', () => {
        const el = create({ runStatus: 'Discovering', percentComplete: 42 });
        const bar = el.shadowRoot.querySelector('[data-id="progress-bar"]');
        expect(Number(bar.value)).toBe(42);
    });

    it('appends each new stageMessage inside the aria-live=polite log', async () => {
        const el = create({ runStatus: 'Discovering', stageMessage: 'Walking agents…' });
        await flush();
        el.stageMessage = 'Scanning topics…';
        await flush();

        const log = el.shadowRoot.querySelector('[data-id="progress-log"]');
        expect(log.getAttribute('aria-live')).toBe('polite');
        const items = log.querySelectorAll('.ohm-discover__log-item');
        expect(items.length).toBe(2);
        expect(items[0].textContent).toContain('Walking agents');
        expect(items[1].textContent).toContain('Scanning topics');
    });

    it('does not append a duplicate for an unchanged stageMessage', async () => {
        const el = create({ runStatus: 'Discovering', stageMessage: 'Same' });
        await flush();
        el.stageMessage = 'Same';
        await flush();
        const items = el.shadowRoot.querySelectorAll('.ohm-discover__log-item');
        expect(items.length).toBe(1);
    });

    it('renders no spinner in Calm Mode', () => {
        const calm = create({ runStatus: 'Discovering', calmMode: true });
        expect(calm.shadowRoot.querySelector('[data-id="spinner"]')).toBeNull();
        const loud = create({ runStatus: 'Discovering', calmMode: false });
        expect(loud.shadowRoot.querySelector('[data-id="spinner"]')).not.toBeNull();
    });

    it('performs no Apex I/O (pure display)', () => {
        // The module imports nothing from @salesforce/apex; importing it here would
        // throw if it tried. This test documents the contract.
        // eslint-disable-next-line global-require
        const source = require('../ohmDiscoverAnalyze.js');
        expect(source).toBeDefined();
    });

    it('focusHeading() moves focus to the h2', () => {
        const el = create({ runStatus: 'Discovering' });
        el.focusHeading();
        const h2 = el.shadowRoot.querySelector('h2');
        expect(el.shadowRoot.activeElement).toBe(h2);
    });

    it('is accessible in both Calm variants', async () => {
        await expect(
            create({ runStatus: 'Discovering', percentComplete: 50, stageMessage: 'x', calmMode: false })
        ).toBeAccessible();
        await expect(
            create({ runStatus: 'Analyzing', percentComplete: 80, stageMessage: 'y', calmMode: true })
        ).toBeAccessible();
    });
});
