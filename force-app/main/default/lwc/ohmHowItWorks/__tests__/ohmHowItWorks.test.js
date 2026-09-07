import { createElement } from 'lwc';
import OhmHowItWorks from 'c/ohmHowItWorks';

function create() {
    const el = createElement('c-ohm-how-it-works', { is: OhmHowItWorks });
    document.body.appendChild(el);
    return el;
}
afterEach(() => { document.body.replaceChildren(); });

it('explains the loop, the stack and the footprint math with labeled diagrams', async () => {
    const el = create();
    await Promise.resolve();
    const diagrams = [...el.shadowRoot.querySelectorAll('svg[role="img"]')];
    expect(diagrams.map((svg) => svg.dataset.id)).toEqual(['diagram-loop', 'diagram-stack', 'diagram-math']);
    diagrams.forEach((svg) => {
        expect(svg.getAttribute('aria-label').length).toBeGreaterThan(40);
        expect(svg.querySelector('title')).not.toBeNull();
    });
    const text = el.shadowRoot.textContent;
    expect(text).toContain('Verify');
    expect(text).toContain('Prompt Builder');
    expect(text).toContain('GPT 5.5');
    expect(text).toContain('Metadata API');
    expect(text).toContain('No match: nothing is saved');
    expect(el.shadowRoot.querySelectorAll('.how__steps li')).toHaveLength(6);
    expect([...el.shadowRoot.querySelectorAll('.how__card h3')].map((h) => h.textContent)).toEqual(['Input', 'Output', 'Calls']);
    await expect(el).toBeAccessible();
});
