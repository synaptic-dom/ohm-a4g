import { createElement } from 'lwc';
import OhmImpactReadout from 'c/ohmImpactReadout';
import { mockAuditReadoutComplete } from 'c/ohmTestData';

function create(props = {}) {
    const el = createElement('c-ohm-impact-readout', { is: OhmImpactReadout });
    Object.assign(el, { readout: mockAuditReadoutComplete() }, props);
    document.body.appendChild(el);
    return el;
}

async function flush() {
    return Promise.resolve();
}

function centralTexts(el) {
    const receipt = el.shadowRoot.querySelector('[data-id="org-receipt"]');
    return [...receipt.shadowRoot.querySelectorAll('[data-id="receipt-central"]')].map(
        (n) => n.textContent.trim()
    );
}

describe('c-ohm-impact-readout', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('binds the DTO to the rating + receipt children', () => {
        const el = create();
        const rating = el.shadowRoot.querySelector('[data-id="rating"]');
        expect(rating.grade).toBe('D');
        const receipt = el.shadowRoot.querySelector('[data-id="org-receipt"]');
        expect(receipt.metrics.length).toBe(3);
    });

    it('renders one h2 with data-focus-heading', () => {
        const el = create();
        const h2s = el.shadowRoot.querySelectorAll('h2[data-focus-heading]');
        expect(h2s.length).toBe(1);
    });

    it('shows low/central/high text per metric via the receipt', () => {
        const el = create();
        const receipt = el.shadowRoot.querySelector('[data-id="org-receipt"]');
        const ranges = receipt.shadowRoot.querySelectorAll('[data-id="receipt-range"]');
        expect(ranges.length).toBe(3);
        expect(ranges[0].textContent).toContain('range');
    });

    it('recomputes bands CLIENT-SIDE and linearly on volumechange (no Apex)', async () => {
        const el = create();
        const before = centralTexts(el);

        // Baseline is 50 sessions; scrub to 100 -> everything doubles.
        el.shadowRoot
            .querySelector('[data-id="scrubber"]')
            .dispatchEvent(
                new CustomEvent('volumechange', { detail: { sessionsPerPeriod: 100 } })
            );
        await flush();

        const after = centralTexts(el);
        // energy central 88,695 -> 177,390
        expect(before[0]).toBe('88,695 Wh/yr');
        expect(after[0]).toBe('177,390 Wh/yr');
    });

    it('never imports getAuditStatus (scrub does no round-trip)', () => {
        // eslint-disable-next-line global-require
        const src = require('fs').readFileSync(
            require('path').join(__dirname, '..', 'ohmImpactReadout.js'),
            'utf8'
        );
        expect(src).not.toContain('@salesforce/apex');
    });

    it('updates the provenance scenario label when scrubbed to 150', async () => {
        const el = create();
        el.shadowRoot
            .querySelector('[data-id="scrubber"]')
            .dispatchEvent(
                new CustomEvent('volumechange', { detail: { sessionsPerPeriod: 150 } })
            );
        await flush();
        const receipt = el.shadowRoot.querySelector('[data-id="org-receipt"]');
        const prov = receipt.shadowRoot.querySelector('[data-id="receipt-provenance"]');
        expect(prov.textContent).toContain('150 sessions/day');
    });

    it('emits viewrecommendations from the CTA', () => {
        const el = create();
        const handler = jest.fn();
        el.addEventListener('viewrecommendations', handler);
        el.shadowRoot.querySelector('[data-id="view-recommendations"]').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('is accessible in both Calm variants', async () => {
        await expect(create({ calmMode: false })).toBeAccessible();
        await expect(create({ calmMode: true })).toBeAccessible();
    });
});
