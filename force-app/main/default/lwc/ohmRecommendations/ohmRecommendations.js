import { LightningElement, api, track } from 'lwc';
import createRemediationTask from '@salesforce/apex/OhmAuditController.createFindingRemediationTask';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import getReviewRecommendations from '@salesforce/apex/OhmReviewRecommendationService.getReviewRecommendations';
import createReviewTask from '@salesforce/apex/OhmReviewRecommendationService.createReviewTask';
import { bundleLabel } from 'c/ohmDisplay';

const CATEGORIES = [
    { value: 'All', label: 'All categories' },
    { value: 'INPUT', label: 'Input efficiency' },
    { value: 'OUTPUT', label: 'Output efficiency' },
    { value: 'CALLS', label: 'Call efficiency' }
];

/** Current saved review recommendations, with older detector work kept separately. */
export default class OhmRecommendations extends LightningElement {
    @api reportId;
    @api calmMode = false;
    @api volumeAssumption;
    @api telemetryBacked = false;
    @api standalone = false;
    @track _findings = [];
    @track _errors = {};
    @track _pages = [];
    @track _items = [];
    @track _itemErrors = {};
    @track _busyKeys = {};
    isLoading = false;
    loadError;
    categoryFilter = 'All';
    bundleFilter = 'All';
    _fleet = [];
    showTrackedWork = false;
    _loadSequence = 0;

    @api get findings() { return this._findings; }
    set findings(value) { this._findings = (Array.isArray(value) ? value : []).map((f) => ({ ...f })); }
    connectedCallback() { if (this.standalone) this.loadRecommendations(); }
    disconnectedCallback() { this._loadSequence += 1; }
    @api refresh() { return this.standalone ? this.loadRecommendations() : Promise.resolve(); }
    @api focusHeading() {
        const heading = this.template.querySelector('[data-focus-heading]');
        if (heading) heading.focus();
    }
    get cards() { return this._findings.map((finding) => ({ key: finding.id, finding, error: this._errors[finding.id], busy: !!this._busyKeys[finding.id] })); }
    get hasFindings() { return this._findings.length > 0; }

    async handleCreateTask(event) {
        const findingId = event.detail && event.detail.findingId;
        const finding = this._findings.find((f) => f.id === findingId);
        if (!finding || finding.remediationTaskId || this._busyKeys[findingId]) return;
        this._busyKeys = { ...this._busyKeys, [findingId]: true };
        this._errors = { ...this._errors, [findingId]: null };
        try {
            const taskId = await createRemediationTask({ findingId, note: null });
            this._findings = this._findings.map((f) => f.id === findingId ? { ...f, remediationTaskId: taskId } : f);
        } catch (error) {
            this._errors = { ...this._errors, [findingId]: this.message(error) || 'Could not create the task. Please try again.' };
        } finally {
            this._busyKeys = { ...this._busyKeys, [findingId]: false };
        }
    }

    async loadRecommendations() {
        const sequence = ++this._loadSequence;
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getFleet();
            const fleet = (Array.isArray(data) ? data : []).filter((row) => row && row.plannerId);
            if (sequence === this._loadSequence) this._fleet = fleet;
            // Each source freshness check gets its own Apex transaction. One unavailable bundle does not hide the others.
            const pages = await Promise.all(fleet.map(async (row) => {
                try {
                    const page = await getReviewRecommendations({ plannerId: row.plannerId });
                    return { ...page, plannerId: row.plannerId, bundleLabel: bundleLabel((page && page.bundleLabel) || row.label || row.plannerApiName || 'Agent Script bundle') };
                } catch (error) {
                    return { plannerId: row.plannerId, bundleLabel: bundleLabel(row.label || row.plannerApiName || 'Agent Script bundle'), failed: true, reason: this.message(error) || 'Could not check this bundle’s saved review.' };
                }
            }));
            if (sequence !== this._loadSequence) return;
            this._pages = pages;
            this._items = pages.filter((page) => this.currentReview(page)).flatMap((page) =>
                (Array.isArray(page.items) ? page.items : []).filter((item) => item && item.key && item.recommendation && item.categoryId !== 'MODEL').map((item) => ({ ...item }))
            ).sort((a, b) => {
                const priority = (a.rating === 'C' ? 0 : 1) - (b.rating === 'C' ? 0 : 1);
                return priority || (a.bundleLabel || '').localeCompare(b.bundleLabel || '') || (a.categoryId || '').localeCompare(b.categoryId || '') || a.key.localeCompare(b.key);
            });
        } catch (error) {
            if (sequence !== this._loadSequence) return;
            this.loadError = this.message(error) || 'Could not load the bundles.';
            this._pages = [];
            this._items = [];
            this._fleet = [];
        } finally {
            if (sequence === this._loadSequence) this.isLoading = false;
        }
    }
    currentReview(page) { return page.sourceCurrent === true && page.reviewAvailable === true; }
    get categoryOptions() { return CATEGORIES.map((option) => ({ ...option, selected: option.value === this.categoryFilter })); }
    get bundleOptions() {
        return [{ value: 'All', label: 'All bundles' }, ...this._pages.map((page) => ({ value: page.plannerId, label: page.bundleLabel }))]
            .map((option) => ({ ...option, selected: option.value === this.bundleFilter }));
    }
    get visibleCards() {
        return this._items.filter((item) => (this.categoryFilter === 'All' || item.categoryId === this.categoryFilter) && (this.bundleFilter === 'All' || item.plannerId === this.bundleFilter))
            .map((item) => ({ key: item.key, item, busy: !!this._busyKeys[item.key], error: this._itemErrors[item.key] }));
    }
    get hasCards() { return !this.isLoading && !this.loadError && this.visibleCards.length > 0; }
    get hasFilters() { return !this.isLoading && !this.loadError && this._items.length > 0; }
    get isEmpty() { return !this.isLoading && !this.loadError && this.visibleCards.length === 0; }
    get isFiltered() { return this.categoryFilter !== 'All' || this.bundleFilter !== 'All'; }
    get hasBundles() { return this._pages.length > 0; }
    get hasCurrentReviews() { return this._pages.some((page) => this.currentReview(page)); }
    get coverageText() {
        const count = this._pages.filter((page) => this.currentReview(page)).length;
        return `${this._items.length} ${this._items.length === 1 ? 'recommendation' : 'recommendations'} · ${count} of ${this._pages.length} bundles have a current review`;
    }
    get unavailablePages() {
        return this._pages.filter((page) => !this.currentReview(page)).map((page) => ({
            ...page,
            statusLabel: page.failed ? 'Review unavailable' : 'Review needed',
            reason: page.reason || 'Run a fresh audit to produce recommendations from the current source.'
        }));
    }
    get hasUnavailable() { return !this.isLoading && !this.loadError && this.unavailablePages.length > 0; }
    get trackedWorkLabel() { return this.showTrackedWork ? 'Hide tracked work' : 'Tracked work from supporting checks'; }
    handleCategoryFilter(event) { this.categoryFilter = event.target.value; }
    handleBundleFilter(event) { this.bundleFilter = event.target.value; }
    // ---- footprint strip: the fleet, or the filtered bundle -------------------
    get footprints() { return this.bundleFilter === 'All' ? this._fleet : this._fleet.filter((row) => row.plannerId === this.bundleFilter); }
    get footprintScope() { return this.bundleFilter === 'All' ? 'fleet' : 'bundle'; }
    get footprintHeading() { return this.bundleFilter === 'All' ? 'What these recommendations save the planet' : 'What this bundle’s recommendations save the planet'; }
    get footprintFactors() { const row = this._fleet.find((r) => r.impactFactors); return row ? row.impactFactors : undefined; }
    get footprintSummary() { const row = this.footprints.find((r) => r.impactAssumptions); return row ? row.impactAssumptions : undefined; }
    get hasFootprint() { return !this.isLoading && !this.loadError && this._fleet.length > 0; }
    handleClearFilters() { this.categoryFilter = 'All'; this.bundleFilter = 'All'; }
    handleToggleTrackedWork() { this.showTrackedWork = !this.showTrackedWork; }
    handleRetry() { this.loadRecommendations(); }
    handleOpenBundle(event) {
        const page = this._pages.find((entry) => entry.plannerId === event.currentTarget.dataset.planner);
        if (page) this.dispatchEvent(new CustomEvent('openprocess', { detail: { plannerId: page.plannerId, label: page.bundleLabel, intent: 'recommendation' }, bubbles: true, composed: true }));
    }
    async handleCreateReviewTask(event) {
        const detail = event.detail || {};
        const item = this._items.find((entry) => entry.key === detail.key && entry.reportId === detail.reportId && entry.plannerId === detail.plannerId);
        if (!item || item.taskId || this._busyKeys[item.key]) return;
        this._busyKeys = { ...this._busyKeys, [item.key]: true };
        this._itemErrors = { ...this._itemErrors, [item.key]: null };
        try {
            const taskId = await createReviewTask({ plannerId: item.plannerId, reportId: item.reportId, key: item.key });
            if (!taskId) throw new Error('The task was not returned. Refresh before trying again.');
            // The returned Task identity confirms creation. Completion or applied state is never inferred.
            this._items = this._items.map((entry) => entry.key === item.key ? { ...entry, taskId } : entry);
        } catch (error) {
            this._itemErrors = { ...this._itemErrors, [item.key]: this.message(error) || 'Could not create the task.' };
        } finally {
            this._busyKeys = { ...this._busyKeys, [item.key]: false };
        }
    }
    message(error) { return (error && error.body && error.body.message) || (error && error.message) || null; }
}
