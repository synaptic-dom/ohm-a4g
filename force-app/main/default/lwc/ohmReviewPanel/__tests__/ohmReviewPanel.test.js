import { createElement } from 'lwc';
import OhmReviewPanel from 'c/ohmReviewPanel';
import { parseReview } from 'c/ohmReviewData';
import { reviewFixture, reviewSummaryFixture } from '../../../../../../test-fixtures/review/reviewFixture';

function create(value, calmMode = false) {
    const element = createElement('c-ohm-review-panel', { is: OhmReviewPanel });
    element.reviewJson = typeof value === 'object' && value !== null ? JSON.stringify(value) : value;
    element.calmMode = calmMode;
    document.body.appendChild(element);
    return element;
}

describe('c-ohm-review-panel', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); });

    it('keeps absent, malformed, and unsupported reports distinct from completed reviews', () => {
        const absent = create(null);
        expect(absent.shadowRoot.querySelector('h2').textContent).toBe('Review not run');
        expect(absent.shadowRoot.querySelector('[data-id="category-card"]')).toBeNull();
        const malformed = create('{bad json');
        expect(malformed.shadowRoot.querySelector('h2').textContent).toBe('Review unavailable');
        const unsupported = create({ ...reviewFixture(), schemaVersion: 2 });
        expect(unsupported.shadowRoot.querySelector('[data-id="category-card"]')).toBeNull();
    });

    it('shows only Input, Output and Calls while preserving evidence behind disclosures', () => {
        const el = create(reviewFixture());
        const cards = Array.from(el.shadowRoot.querySelectorAll('[data-id="category-card"]'));
        expect(cards).toHaveLength(3);
        expect(cards.map((card) => card.querySelector('h3').textContent)).toEqual(['Input', 'Output', 'Calls']);
        expect(cards[2].getAttribute('aria-label')).toContain('Call efficiency');
        expect(cards.map((card) => card.querySelector('.review-category__grade').textContent)).toEqual(['B', 'A', 'UNRATED']);
        expect(el.shadowRoot.textContent).not.toContain('Model fit');
        expect(el.shadowRoot.querySelector('.review-issue__details').open).toBe(false);
        expect(el.shadowRoot.querySelector('[data-id="instruction-reviews"]').open).toBe(false);
        expect(el.shadowRoot.querySelector('blockquote').textContent).toBe('Always explain the full routing policy.');
        expect(el.shadowRoot.textContent).toContain('Keep the escalation and approval requirements.');
        expect(el.shadowRoot.textContent).toContain('Replay escalation and ordinary routing cases');
        expect(el.shadowRoot.textContent).toContain('Lead_Concierge.v4');
        expect(el.shadowRoot.textContent).toContain('a'.repeat(64));
        expect(el.shadowRoot.textContent).toContain('Ohm_Efficiency_Review · v1');
        expect(el.shadowRoot.textContent).toContain('No runtime telemetry was used.');
    });

    it('routes a recommendation to its exact source and prepares a question without sending it', () => {
        const review = reviewFixture();
        review.artifacts[0].artifactKey = 'bundle|Topic|triage';
        const el = create(review);
        const handler = jest.fn();
        el.addEventListener('reviewaction', handler);
        el.shadowRoot.querySelector('[data-id="review-change"]').click();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual(expect.objectContaining({ artifactId: 'topic:triage', artifactKey: 'bundle|Topic|triage', intent: 'draft' }));
        expect(handler.mock.calls[0][0].detail.question).toContain('Keep the escalation and approval requirements');
        el.shadowRoot.querySelector('[data-id="open-source"]').click();
        expect(handler.mock.calls[1][0].detail.intent).toBe('source');
    });

    it('promotes an artifact-owned prompt recommendation even when bundle issue arrays are empty', () => {
        const review = reviewFixture();
        const issue = { ...review.artifacts[0].categories[0].issues[0], code: 'CALLS_DETERMINISTIC_ALTERNATIVE' };
        review.categories = review.categories.map((category) => ({ ...category, issues: [] }));
        review.artifacts[0].label = 'Generate Personalized Schedule';
        review.artifacts[0].artifactType = 'Action';
        review.artifacts[0].artifactKey = 'bundle|Action|schedule';
        review.artifacts[0].categories = review.artifacts[0].categories.map((category) => ({ ...category, issues: category.id === 'CALLS' ? [issue] : [] }));
        const el = create(review);
        const handler = jest.fn();
        el.addEventListener('reviewaction', handler);
        expect(el.shadowRoot.querySelectorAll('[data-id="bundle-issue"]')).toHaveLength(1);
        expect(el.shadowRoot.querySelector('h2').textContent).toBe('Start with one change.');
        expect(el.shadowRoot.querySelector('[data-id="bundle-issue"]').textContent).toContain('Use code for fixed rules');
        el.shadowRoot.querySelector('[data-id="review-change"]').click();
        expect(handler.mock.calls[0][0].detail.artifactKey).toBe('bundle|Action|schedule');
        expect(el.shadowRoot.textContent).not.toContain('Model fit');
    });

    it('deduplicates exact bundle/artifact copies but retains distinct recommendations', () => {
        const review = reviewFixture();
        const el = create(review);
        expect(el.shadowRoot.querySelectorAll('[data-id="bundle-issue"]')).toHaveLength(1);
        review.artifacts[0].categories[0].issues.push({ ...review.artifacts[0].categories[0].issues[0], recommendation: 'A distinct recommended change.' });
        const changed = create(review);
        expect(changed.shadowRoot.querySelectorAll('[data-id="bundle-issue"]')).toHaveLength(2);
    });

    it('retains actionable ratings with partial coverage and never turns an incomplete A into a pass', () => {
        const review = reviewFixture();
        review.categories[0] = { ...review.categories[0], rating: 'C', coverageStatus: 'Partial', status: 'unknown' };
        review.categories[1].coverageStatus = 'Partial';
        const parsed = parseReview(JSON.stringify(review));
        expect(parsed.categories[0].rating).toBe('C');
        expect(parsed.categories[0].coverageStatus).toBe('Partial');
        expect(parsed.categories[1].rating).toBe('UNRATED');
        review.categories[1] = { ...review.categories[1], coverageStatus: 'Complete', issues: review.categories[0].issues };
        expect(parseReview(JSON.stringify(review)).categories[1].rating).toBe('UNRATED');
    });

    it('resolves configuration citations without treating configuration as an extra rated prompt', () => {
        const review = reviewFixture();
        review.contextSources = [{ artifactId: 'configuration:agent', label: 'Agent configuration', sourceVersion: 'v4', sourceHash: 'b'.repeat(64), sourcePath: 'agent.agent' }];
        review.artifacts[0].categories[0].issues[0].evidence = [{ artifactId: 'configuration:agent', quote: 'max_tokens: 300' }];
        const el = create(review);
        expect(el.shadowRoot.querySelectorAll('[data-id="artifact-review"]')).toHaveLength(1);
        expect(el.shadowRoot.querySelector('blockquote').textContent).toBe('max_tokens: 300');
        expect(el.shadowRoot.querySelector('.review-issue__source').textContent).toContain('Agent configuration');
    });

    it('shows bundle-only recommendations with readable labels and deterministic artifact facts', () => {
        const review = reviewFixture();
        review.artifacts[0].categories = review.artifacts[0].categories.map((category) => ({ ...category, issues: [] }));
        const el = create(review);
        expect(el.shadowRoot.querySelectorAll('[data-id="bundle-issue"]')).toHaveLength(1);
        expect(el.shadowRoot.querySelector('[data-id="bundle-issue"]').textContent).toContain('Review observation');
        expect(el.shadowRoot.querySelector('[data-id="bundle-issue"]').textContent).not.toContain('REPEATED_CONTEXT');
        expect(el.shadowRoot.querySelector('.review-artifact__facts').textContent).toBe('100 characters · approximately 25 source tokens');
    });

    it('does not render unbound quotations as retrieved evidence and rejects incomplete category sets', () => {
        const review = reviewFixture();
        review.artifacts[0].categories[0].issues[0].evidence[0].artifactId = 'not-retrieved';
        const el = create(review);
        expect(el.shadowRoot.querySelector('blockquote')).toBeNull();
        expect(el.shadowRoot.textContent).toContain('Evidence could not be matched');
        review.categories.pop();
        expect(parseReview(JSON.stringify(review)).state).toBe('unavailable');
    });

    it('accepts compact summaries without fabricating per-artifact detail and ignores generated impact numbers', () => {
        const review = reviewSummaryFixture();
        review.categories[0].environmentalMechanism = 'Save 10,000 Wh immediately';
        const parsed = parseReview(JSON.stringify(review));
        expect(parsed.state).toBe('reviewed');
        expect(parsed.artifacts).toEqual([]);
        expect(parsed.categories[0].environmentalMechanism).not.toContain('10,000');
    });

    it('supports keyboard focus and accessibility in both Calm variants', async () => {
        for (const calm of [false, true]) {
            const el = create(reviewFixture(), calm);
            el.focusHeading();
            expect(el.shadowRoot.activeElement).toBe(el.shadowRoot.querySelector('[data-focus-heading]'));
            await expect(el).toBeAccessible();
        }
    });
});
