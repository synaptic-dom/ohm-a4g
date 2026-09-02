import { createElement } from 'lwc';
import OhmUncertaintyBar from 'c/ohmUncertaintyBar';

function create(props = {}) {
    const el = createElement('c-ohm-uncertainty-bar', { is: OhmUncertaintyBar });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c-ohm-uncertainty-bar', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('exposes role="img" with a numeric aria-label that repeats the numbers', () => {
        const el = create({
            label: 'Energy',
            unit: 'Wh/yr',
            low: 78840,
            central: 88695,
            high: 98550
        });
        const bar = el.shadowRoot.querySelector('[data-id="uncertainty-bar"]');
        expect(bar.getAttribute('role')).toBe('img');
        const aria = bar.getAttribute('aria-label');
        expect(aria).toContain('78,840');
        expect(aria).toContain('88,695');
        expect(aria).toContain('98,550');
        expect(aria).toContain('Energy');
    });

    it('positions the central marker within the low–high span', () => {
        const el = create({ low: 0, central: 50, high: 100 });
        const marker = el.shadowRoot.querySelector('.ohm-bar__marker');
        expect(marker.style.left).toBe('50%');
    });

    it('is accessible', async () => {
        await expect(
            create({ label: 'Water', unit: 'mL/yr', low: 1, central: 2, high: 3 })
        ).toBeAccessible();
    });
});
