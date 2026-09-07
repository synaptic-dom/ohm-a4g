import { LightningElement, api } from 'lwc';
import { SIGNAL_LABELS } from 'c/ohmConstants';
import { bundleLabel } from 'c/ohmDisplay';

/** A saved review recommendation, or a supporting detector check. Never applies a change. */
export default class OhmRecommendationCard extends LightningElement {
    @api recommendation;
    @api finding;
    // Retained for existing embedded callers; the interface has one visual theme.
    @api calmMode = false;
    @api volumeAssumption;
    @api telemetryBacked = false;
    @api errorMessage;
    @api busy = false;
    expanded = false;

    get isReview() { return !!this.recommendation; }
    get item() { return this.recommendation || {}; }
    get cardClass() { return this.isReview ? 'ohm-rec-card ohm-rec-card--review' : 'ohm-rec-card'; }
    get bundleLabel() { return bundleLabel(this.item.bundleLabel || 'Agent Script bundle'); }
    get sourceLabel() { return this.item.artifactLabel || 'Bundle setup'; }
    get categoryLabel() { return this.item.categoryLabel || 'Review recommendation'; }
    get ratingLabel() { return this.item.rating === 'C' ? 'Configured rule' : 'Review candidate'; }
    get displayRecommendation() {
        if (this.isReview) return this.item.recommendation;
        const f = this.finding || {};
        return f.agentNarrative || f.recommendationText;
    }
    get signalLabel() {
        const f = this.finding || {};
        return SIGNAL_LABELS[f.signal] || f.signal || 'Supporting check';
    }
    get severityText() { return `Severity: ${(this.finding || {}).severity || 'Unknown'}`; }
    get effortText() { return `Effort: ${(this.finding || {}).effort || 'Unknown'}`; }
    get generatedByText() { return (this.finding || {}).generatedBy === 'Agentforce' ? 'Agent-phrased' : 'Deterministic'; }
    get created() { return !!(this.isReview ? this.item.taskId : (this.finding || {}).remediationTaskId); }
    get taskUrl() {
        const id = this.isReview ? this.item.taskId : (this.finding || {}).remediationTaskId;
        return id ? `/lightning/r/Task/${id}/view` : null;
    }
    get taskText() { return this.item.taskStatus ? `Task · ${this.item.taskStatus}` : 'Task created'; }
    get taskButtonLabel() { return this.busy ? 'Creating task…' : 'Create task'; }
    get detailsLabel() { return this.expanded ? 'Hide reasoning' : 'Why this change'; }
    get evidence() {
        return (Array.isArray(this.item.evidence) ? this.item.evidence : []).map((entry, index) => ({
            ...entry,
            key: `${this.item.key}-evidence-${index}`,
            index,
            label: entry.artifactLabel || 'Source excerpt',
            canOpen: !!(this.item.plannerId && (entry.nodeId || entry.artifactKey))
        }));
    }
    get hasEvidence() { return this.evidence.length > 0; }
    get canOpen() { return !!this.item.plannerId; }
    handleToggleDetails() { this.expanded = !this.expanded; }
    handleOpen() { this.openSource(this.item); }
    handleOpenEvidence(event) {
        const entry = this.evidence[Number(event.currentTarget.dataset.index)];
        if (entry) this.openSource(entry, 'source');
    }
    openSource(source, intent = 'recommendation') {
        if (!this.item.plannerId) return;
        this.dispatchEvent(new CustomEvent('openprocess', {
            detail: {
                plannerId: this.item.plannerId,
                label: this.bundleLabel,
                nodeId: source.nodeId || undefined,
                artifactKey: source.artifactKey || undefined,
                intent
            },
            bubbles: true,
            composed: true
        }));
    }
    handleCreateTask() {
        if (this.busy || this.created) return;
        const detail = this.isReview
            ? { plannerId: this.item.plannerId, reportId: this.item.reportId, key: this.item.key }
            : { findingId: (this.finding || {}).id };
        this.dispatchEvent(new CustomEvent('createtask', { detail }));
    }
}
