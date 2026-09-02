import { createElement } from 'lwc';
import OhmVolumeScrubber from 'c/ohmVolumeScrubber';

function create(props = {}) {
    const el = createElement('c-ohm-volume-scrubber', { is: OhmVolumeScrubber });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

function key(el, k) {
    const slider = el.shadowRoot.querySelector('[data-id="scrubber-slider"]');
    slider.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }));
}

describe('c-ohm-volume-scrubber', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.useRealTimers();
    });

    it('non-Calm renders a real slider with aria-valuetext', () => {
        const el = create({ value: 50 });
        const slider = el.shadowRoot.querySelector('[data-id="scrubber-slider"]');
        expect(slider.getAttribute('role')).toBe('slider');
        expect(slider.getAttribute('aria-valuetext')).toBe('50 sessions per day');
        expect(slider.getAttribute('aria-valuenow')).toBe('50');
    });

    it('ArrowRight / ArrowLeft change the value and emit volumechange', () => {
        const el = create({ value: 50, step: 10 });
        const handler = jest.fn();
        el.addEventListener('volumechange', handler);

        key(el, 'ArrowRight');
        expect(el.value).toBe(60);
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({ sessionsPerPeriod: 60 });

        key(el, 'ArrowLeft');
        expect(el.value).toBe(50);
        expect(handler).toHaveBeenCalledTimes(2);
    });

    it('updates aria-valuetext as the value changes', () => {
        const el = create({ value: 50, step: 100 });
        key(el, 'ArrowRight');
        return Promise.resolve().then(() => {
            const slider = el.shadowRoot.querySelector('[data-id="scrubber-slider"]');
            expect(slider.getAttribute('aria-valuetext')).toBe('150 sessions per day');
        });
    });

    it('clamps at the max bound', () => {
        const el = create({ value: 495, max: 500, step: 10 });
        key(el, 'ArrowRight');
        expect(el.value).toBe(500);
        key(el, 'ArrowRight');
        expect(el.value).toBe(500);
    });

    it('announces politely and debounced (one announcement for rapid keypresses)', () => {
        jest.useFakeTimers();
        const el = create({ value: 50, step: 10 });
        const announce = el.shadowRoot.querySelector('[data-id="scrubber-announce"]');
        expect(announce.getAttribute('aria-live')).toBe('polite');

        key(el, 'ArrowRight');
        key(el, 'ArrowRight');
        key(el, 'ArrowRight');
        // Nothing announced yet (debounced).
        expect(announce.textContent.trim()).toBe('');

        jest.runOnlyPendingTimers();
        return Promise.resolve().then(() => {
            const a = el.shadowRoot.querySelector('[data-id="scrubber-announce"]');
            expect(a.textContent).toContain('80');
        });
    });

    it('Calm variant renders a numeric input and no slider', () => {
        const el = create({ value: 50, calmMode: true });
        expect(el.shadowRoot.querySelector('[data-id="scrubber-slider"]')).toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="scrubber-number"]')).not.toBeNull();
    });

    it('is accessible in both Calm variants', async () => {
        await expect(create({ value: 50, calmMode: false })).toBeAccessible();
        await expect(create({ value: 50, calmMode: true })).toBeAccessible();
    });
});
