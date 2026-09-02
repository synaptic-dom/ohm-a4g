import { createElement } from 'lwc';
import OhmMethodologyPanel from 'c/ohmMethodologyPanel';
import { mockAssumptions } from 'c/ohmTestData';

function create(props = {}) {
    const el = createElement('c-ohm-methodology-panel', { is: OhmMethodologyPanel });
    Object.assign(el, { assumptions: mockAssumptions() }, props);
    document.body.appendChild(el);
    return el;
}

describe('c-ohm-methodology-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders every assumption key from the DTO', () => {
        const assumptions = mockAssumptions();
        const el = create({ assumptions });
        const rendered = [
            ...el.shadowRoot.querySelectorAll('[data-id="methodology-value"]')
        ].map((n) => n.dataset.key);
        Object.keys(assumptions).forEach((key) => {
            expect(rendered).toContain(key);
        });
    });

    it('surfaces the actual constant values from the DTO (no hardcoded copies)', () => {
        const el = create({ assumptions: mockAssumptions({ energyPerPromptWhCentral: 0.27 }) });
        const value = el.shadowRoot.querySelector(
            '[data-id="methodology-value"][data-key="energyPerPromptWhCentral"]'
        );
        expect(value.textContent.trim()).toBe('0.27');
    });

    it('renders the CO₂e band-width note', () => {
        const el = create();
        const note = el.shadowRoot.querySelector(
            '[data-id="methodology-value"][data-key="co2eBandNote"]'
        );
        expect(note.textContent).toContain('grid');
    });

    it('discloses telemetryBacked=false honestly', () => {
        const el = create({ telemetryBacked: false });
        const t = el.shadowRoot.querySelector('[data-id="methodology-telemetry"]');
        expect(t.textContent).toContain('modeled');
    });

    it('is accessible in both Calm variants', async () => {
        await expect(create({ calmMode: false })).toBeAccessible();
        await expect(create({ calmMode: true })).toBeAccessible();
    });
});
