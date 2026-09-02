import { createElement } from 'lwc';
import OhmCalmModeToggle from 'c/ohmCalmModeToggle';

function create(props = {}) {
    const el = createElement('c-ohm-calm-mode-toggle', { is: OhmCalmModeToggle });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c-ohm-calm-mode-toggle', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('conveys On/Off state as text, never colour alone', () => {
        const el = create({ calmMode: true });
        const state = el.shadowRoot.querySelector('[data-id="state-text"]');
        expect(state.textContent).toContain('On');

        const el2 = create({ calmMode: false });
        const state2 = el2.shadowRoot.querySelector('[data-id="state-text"]');
        expect(state2.textContent).toContain('Off');
    });

    it('emits calmtoggle with enabled from the input change', () => {
        const el = create({ calmMode: false });
        const handler = jest.fn();
        el.addEventListener('calmtoggle', handler);

        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ enabled: true });
    });

    it('is accessible in both Calm variants', async () => {
        const on = create({ calmMode: true });
        await expect(on).toBeAccessible();
        const off = create({ calmMode: false });
        await expect(off).toBeAccessible();
    });
});
