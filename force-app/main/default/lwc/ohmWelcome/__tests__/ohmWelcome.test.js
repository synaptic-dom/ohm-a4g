import { createElement } from 'lwc';
import OhmWelcome from 'c/ohmWelcome';

function create(props = {}) {
    const el = createElement('c-ohm-welcome', { is: OhmWelcome });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c-ohm-welcome', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders exactly one h1 with data-focus-heading', () => {
        const el = create();
        const h1s = el.shadowRoot.querySelectorAll('h1');
        expect(h1s.length).toBe(1);
        expect(h1s[0].hasAttribute('data-focus-heading')).toBe(true);
        expect(h1s[0].getAttribute('tabindex')).toBe('-1');
    });

    it('emits startaudit from the single CTA', () => {
        const el = create();
        const handler = jest.fn();
        el.addEventListener('startaudit', handler);
        el.shadowRoot.querySelector('[data-id="start-button"]').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('Calm Mode hides the decorative hero but keeps the h1 structure', () => {
        const el = create({ calmMode: true });
        expect(el.shadowRoot.querySelector('.ohm-welcome__hero')).toBeNull();
        expect(el.shadowRoot.querySelectorAll('h1').length).toBe(1);
    });

    it('non-Calm renders the decorative hero', () => {
        const el = create({ calmMode: false });
        expect(el.shadowRoot.querySelector('.ohm-welcome__hero')).not.toBeNull();
    });

    it('focusHeading() moves focus to the h1', () => {
        const el = create();
        el.focusHeading();
        const h1 = el.shadowRoot.querySelector('h1');
        expect(el.shadowRoot.activeElement).toBe(h1);
    });

    it('is accessible in both Calm variants', async () => {
        await expect(create({ calmMode: false })).toBeAccessible();
        await expect(create({ calmMode: true })).toBeAccessible();
    });
});
