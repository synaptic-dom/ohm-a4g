import { createElement } from 'lwc';
import OhmImpactReceipt from 'c/ohmImpactReceipt';
import { mockVolumeAssumption } from 'c/ohmTestData';

const METRICS = [
    { id: 'energy', label: 'Energy', unit: 'Wh/yr', low: 10, central: 20, high: 30 },
    { id: 'water', label: 'Water', unit: 'mL/yr', low: 40, central: 50, high: 60 },
    { id: 'co2e', label: 'CO₂e', unit: 'g/yr', low: 70, central: 80, high: 90 }
];

function create(props = {}) {
    const el = createElement('c-ohm-impact-receipt', { is: OhmImpactReceipt });
    Object.assign(
        el,
        { metrics: METRICS, volumeAssumption: mockVolumeAssumption() },
        props
    );
    document.body.appendChild(el);
    return el;
}

function terms(el) {
    return [...el.shadowRoot.querySelectorAll('[data-id="receipt-term"]')].map(
        (t) => t.textContent.trim()
    );
}

describe('c-ohm-impact-receipt', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders a <dl> with one term per metric', () => {
        const el = create();
        expect(el.shadowRoot.querySelector('dl')).not.toBeNull();
        expect(terms(el)).toEqual(['Energy', 'Water', 'CO₂e']);
    });

    it('shows central value + "range low–high" as text', () => {
        const el = create();
        const central = el.shadowRoot.querySelector('[data-id="receipt-central"]');
        const range = el.shadowRoot.querySelector('[data-id="receipt-range"]');
        expect(central.textContent).toContain('20');
        expect(range.textContent).toBe('range 10–30');
    });

    it('carries a W7 provenance node on every figure', () => {
        const el = create({ confidence: 'Low' });
        const prov = el.shadowRoot.querySelectorAll('[data-id="receipt-provenance"]');
        expect(prov.length).toBe(3);
        expect(prov[0].textContent).toContain('50 sessions/day × 6 turns');
        expect(prov[0].textContent).toContain('Confidence: Low');
    });

    it('adds uncertainty bars only in non-Calm', () => {
        const loud = create({ calmMode: false });
        expect(
            loud.shadowRoot.querySelectorAll('c-ohm-uncertainty-bar').length
        ).toBe(3);
        const calm = create({ calmMode: true });
        expect(
            calm.shadowRoot.querySelectorAll('c-ohm-uncertainty-bar').length
        ).toBe(0);
    });

    it('drift guard: Calm and non-Calm expose IDENTICAL <dl> terms', () => {
        const loud = create({ calmMode: false });
        const calm = create({ calmMode: true });
        expect(terms(calm)).toEqual(terms(loud));
    });

    it('is accessible in both Calm variants', async () => {
        await expect(create({ calmMode: false })).toBeAccessible();
        await expect(create({ calmMode: true })).toBeAccessible();
    });
});
