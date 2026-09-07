import { LightningElement } from 'lwc';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import { parseReview } from 'c/ohmReviewData';
import { bundleLabel } from 'c/ohmDisplay';
export default class OhmOverview extends LightningElement {
    rows = [];
    loading = true;
    error;
    connectedCallback() { this.load(); }
    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            const result = await getFleet();
            this.rows = (Array.isArray(result) ? result : []).map((row) => ({ ...row, review: parseReview(row.reviewJson) }));
        } catch (error) { this.error = error?.body?.message || error?.message || 'Could not load your bundles.'; }
        finally { this.loading = false; }
    }
    get ready() { return !this.loading && !this.error; }
    get total() { return this.rows.length; }
    get reviewed() { return this.rows.filter((row) => row.review.state === 'reviewed').length; }
    get opportunities() { return this.rows.filter((row) => row.review.state === 'reviewed' && row.review.categories.some((category) => category.id !== 'MODEL' && ['B', 'C'].includes(category.rating))); }
    get opportunityCount() { return this.opportunities.length; }
    get opportunityLabel() { return this.opportunityCount === 1 ? 'bundle to improve' : 'bundles to improve'; }
    get hasOpportunity() { return this.opportunityCount > 0; }
    get hasBundles() { return this.total > 0; }
    get nextBundle() {
        return this.opportunities.find((row) => row.review.categories.some((category) => category.id !== 'MODEL' && category.rating === 'C')) || this.opportunities[0] ||
            this.rows.find((row) => row.review.state !== 'reviewed') || this.rows[0];
    }
    get nextLabel() { return this.nextBundle ? bundleLabel(this.nextBundle.label) : ''; }
    get nextTitle() { return this.hasOpportunity ? 'Make your next change count.' : this.reviewed < this.total ? 'See where your agent stands.' : this.hasBundles ? 'Get to know your agents.' : 'Ready when your agent is.'; }
    get nextDescription() {
        if (this.hasOpportunity) return 'See what to change, what to preserve, and how to test it.';
        if (this.reviewed < this.total) return 'Review your instructions and linked prompts in one place.';
        if (this.hasBundles) return 'Inspect the ratings and see where more evidence is needed.';
        return 'Publish an Agent Script bundle in Salesforce, then refresh to discover it here.';
    }
    get nextAction() { return this.nextBundle?.audited ? 'Open review' : 'Open bundle'; }
    // Footprint inputs come straight from the fleet rows; the strip ignores rows without a modeled review.
    get impactFactors() { const row = this.rows.find((r) => r.impactFactors); return row ? row.impactFactors : undefined; }
    get impactAssumptions() { const row = this.rows.find((r) => r.impactAssumptions); return row ? row.impactAssumptions : undefined; }
    handleBundles() { this.navigate('FLEET'); }
    handleRecommendations() { this.navigate('RECOMMENDATIONS'); }
    navigate(tab) { this.dispatchEvent(new CustomEvent('navigate', { detail: { tab } })); }
    handleNext() {
        if (!this.nextBundle) return;
        this.dispatchEvent(new CustomEvent('openprocess', { detail: { plannerId: this.nextBundle.plannerId, label: this.nextBundle.label } }));
    }
    handleRefresh() { this.load(); }
}
