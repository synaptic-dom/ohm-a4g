import { LightningElement, api } from 'lwc';
import { parseReview } from 'c/ohmReviewData';

export default class OhmReviewPanel extends LightningElement {
    @api calmMode = false;
    _reviewJson;
    review = parseReview(null);
    showAllRecommendations = false;

    @api
    get reviewJson() { return this._reviewJson; }
    set reviewJson(value) {
        this._reviewJson = value;
        this.review = parseReview(value);
        this.showAllRecommendations = false;
    }

    get rootClass() { return 'review'; }
    get reviewed() { return this.review.state === 'reviewed'; }
    get emptyHeading() { return this.review.state === 'not-run' ? 'Review not run' : 'Review unavailable'; }
    get emptyMessage() {
        return this.review.state === 'not-run'
            ? 'Run a fresh audit to review input, output, and calls against this bundle’s published source.'
            : 'This report does not contain a readable efficiency review. Run a fresh audit to produce source-bound assessments.';
    }
    get categories() { return this.review.categories.filter((category) => category.id !== 'MODEL'); }
    get hasBundleIssues() { return this.recommendations.length > 0; }
    get recommendations() {
        const recommendations = [];
        const seen = new Set();
        const append = (category, owner) => category.issues.forEach((issue) => {
            const cited = issue.evidence.find((evidence) => evidence.artifactKey) || issue.evidence.find((evidence) => evidence.artifactId);
            const target = owner || cited || {};
            const signature = JSON.stringify([category.id, issue.code, target.artifactId, issue.explanation,
                issue.recommendation, issue.preserve, issue.validation,
                issue.evidence.map((evidence) => [evidence.artifactId, evidence.quote])]);
            if (seen.has(signature)) return;
            seen.add(signature);
            recommendations.push({ ...issue, categoryLabel: category.label, target,
                index: `${category.id}-${target.artifactId || 'bundle'}-${recommendations.length}` });
        });
        this.categories.forEach((category) => append(category, null));
        this.artifacts.forEach((artifact) => artifact.categories.forEach((category) => append(category, artifact)));
        return recommendations;
    }
    get recommendationCountText() { const count = this.recommendations.length; return `${count} ${count === 1 ? 'opportunity' : 'opportunities'} to review`; }
    get visibleRecommendations() { return (this.showAllRecommendations ? this.recommendations : this.recommendations.slice(0, 3)).map((issue, index) => ({ ...issue, buttonClass: index === 0 ? 'review__primary' : 'review__secondary' })); }
    get hasMoreRecommendations() { return this.recommendations.length > 3; }
    get moreLabel() { return this.showAllRecommendations ? 'Show fewer recommendations' : `Show all ${this.recommendations.length} recommendations`; }
    handleMore() { this.showAllRecommendations = !this.showAllRecommendations; }
    get summaryText() { return this.hasBundleIssues ? 'Start with one change.' : 'Your source review is ready.'; }
    handleReviewAction(event) {
        const issue = this.recommendations.find((item) => item.index === event.currentTarget.dataset.issue);
        if (!issue) return;
        const target = issue.target || {};
        const question = `Help me review this recommendation: ${issue.recommendation}\nPreserve: ${issue.preserve}\nValidate: ${issue.validation}\nExplain the safest next change against the selected published source before drafting.`;
        this.dispatchEvent(new CustomEvent('reviewaction', { detail: { artifactId: target.artifactId, artifactKey: target.artifactKey, intent: 'draft', question }, bubbles: true, composed: true }));
    }
    handleSourceAction(event) {
        const artifact = this.artifacts.find((item) => item.artifactId === event.currentTarget.dataset.artifact);
        if (artifact) this.dispatchEvent(new CustomEvent('reviewaction', { detail: { artifactId: artifact.artifactId, artifactKey: artifact.artifactKey, intent: 'source' }, bubbles: true, composed: true }));
    }
    get artifacts() { return this.review.artifacts.map((artifact) => ({ ...artifact, categories: artifact.categories.filter((category) => category.id !== 'MODEL') })); }
    get limitations() { return (this.review.limitations || []).filter((limitation) => !/model[- ]fit|model quality|model evaluation|model binding|model sizing|smaller model/i.test(limitation)); }
    get hasLimitations() { return this.limitations.length > 0; }
    get reviewedAtText() {
        const date = this.review.reviewedAt && new Date(this.review.reviewedAt);
        return date && !Number.isNaN(date.getTime())
            ? date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
            : 'Review time not recorded';
    }
    get templateText() {
        return this.review.reviewerTemplate
            ? `${this.review.reviewerTemplate} · ${this.review.reviewerVersion || 'Version not recorded'}`
            : 'Reviewer template version not recorded';
    }
    @api
    focusHeading() {
        const heading = this.template.querySelector('[data-focus-heading]');
        if (heading) heading.focus();
    }
}
