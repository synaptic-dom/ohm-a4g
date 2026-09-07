import { LightningElement, api } from 'lwc';

export default class OhmAuditProgress extends LightningElement {
    @api run;
    get failed() { return !!(this.run && this.run.error); }
    get complete() { return this.run && this.run.runStatus === 'Complete' && !this.failed; }
    get working() { return !this.failed && !this.complete; }
    get rootClass() { return `run ${this.failed ? 'run--error' : this.complete ? 'run--complete' : 'run--working'}`; }
    get title() { return this.failed ? 'Audit needs attention' : this.complete ? 'Review ready' : this.run && this.run.runStatus === 'LoadingResults' ? 'Preparing your review' : 'Auditing your bundle'; }
    get label() { return this.run && this.run.label; }
    get message() {
        if (this.failed) return this.run.error;
        return (this.run && this.run.stageMessage) || (this.complete ? 'Salesforce has saved the review.' : 'Waiting for Salesforce to start this audit.');
    }
    get footnote() {
        if (this.failed) return this.run.terminal ? 'Your previous completed review is still available.' : 'The audit may still be running. Resume checking the same run.';
        if (this.complete) return 'Open the bundle to explore its review and recommendations.';
        if (this.run && this.run.runStatus === 'LoadingResults') return 'The audit has finished. We are loading its saved review.';
        if (this.activeStage === 2) return 'Checking source evidence for useful changes. You can leave and return while this runs.';
        return 'Published source is retrieved and checked before review. You can leave and return while this runs.';
    }
    get hasPercent() {
        const value = this.run && this.run.percentComplete;
        return !this.failed && value != null && (typeof value === 'number' || (typeof value === 'string' && value.trim() !== '')) && Number.isFinite(Number(value));
    }
    get percent() { return this.hasPercent ? Math.max(0, Math.min(100, Number(this.run.percentComplete))) : 0; }
    get meterStyle() { return `width: ${this.percent}%`; }
    get progressText() {
        if (this.failed) return this.run.terminal ? 'Stopped' : 'Paused';
        if (this.hasPercent) return `${this.percent}%`;
        if (this.complete) return 'Ready';
        return this.run && this.run.runStatus !== 'Queued' ? 'In progress' : 'Queued';
    }
    get retryLabel() { return this.run && this.run.terminal ? 'Retry audit' : 'Resume checking'; }
    get canRetry() { return this.run && this.run.canRetry; }
    get reportUrl() { return this.run && this.run.reportId ? `/lightning/r/Agent_Audit_Report__c/${encodeURIComponent(this.run.reportId)}/view` : null; }
    get showSupport() { return this.failed && this.reportUrl; }
    get showSteps() { return !this.failed; }
    get activeStage() {
        if (this.complete || (this.run && this.run.runStatus === 'LoadingResults')) return 3;
        if (!this.run || this.failed || this.run.runStatus === 'Queued') return -1;
        if (this.run.runStatus === 'Analyzing') return 2;
        const message = (this.run.stageMessage || '').toLowerCase();
        if (/validat|verif|version check/.test(message)) return 1;
        return this.run.runStatus === 'Discovering' ? 0 : -1;
    }
    get steps() {
        const active = this.activeStage;
        return ['Retrieve source', 'Verify version', 'Review evidence'].map((label, index) => ({
            label, number: index < active ? '✓' : index + 1, key: label,
            current: index === active ? 'step' : undefined,
            accessibleLabel: `${label}: ${index < active ? 'completed' : index === active ? 'current stage' : 'upcoming'}`,
            css: `run__step ${index < active ? 'run__step--done' : index === active ? 'run__step--active' : ''}`,
            state: index < active ? 'Completed stage' : index === active ? 'Current stage' : 'Upcoming stage'
        }));
    }
    handleRetry() { this.dispatchEvent(new CustomEvent('retry', { detail: { plannerId: this.run.plannerId, reportId: this.run.reportId } })); }
}
