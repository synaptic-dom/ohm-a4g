import { createElement } from 'lwc';
import OhmEfficiencyRating from 'c/ohmEfficiencyRating';

function create(props = {}) {
    const el = createElement('c-ohm-efficiency-rating', { is: OhmEfficiencyRating });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}

describe('c-ohm-efficiency-rating', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('shows the grade letter AND a plain word as text (colour-independent)', () => {
        const el = create({ grade: 'D', score: 62 });
        const letter = el.shadowRoot.querySelector('[data-id="rating-letter"]');
        const word = el.shadowRoot.querySelector('[data-id="rating-word"]');
        expect(letter.textContent).toContain('D');
        expect(word.textContent).toBe('Poor');
    });

    it('renders the numeric score as text', () => {
        const el = create({ grade: 'A', score: 95 });
        const score = el.shadowRoot.querySelector('[data-id="rating-score"]');
        expect(score.textContent).toContain('95');
    });

    it('the grade is conveyed by text, not by the colour class alone', () => {
        const el = create({ grade: 'F', score: 40 });
        const badge = el.shadowRoot.querySelector('[data-id="rating-badge"]');
        // colour class present as decoration...
        expect(badge.className).toContain('ohm-rating__badge--f');
        // ...but the word is also present as text.
        expect(badge.textContent).toContain('Wasteful');
    });

    it('is accessible in both Calm variants', async () => {
        await expect(create({ grade: 'B', score: 82, calmMode: false })).toBeAccessible();
        await expect(create({ grade: 'B', score: 82, calmMode: true })).toBeAccessible();
    });
});
