import { LightningElement, track } from 'lwc';
import startAudit from '@salesforce/apex/OhmAuditController.startAudit';
import { STATES } from 'c/ohmConstants';
import { watchAudit, auditError, pendingGuidedAudit, rememberGuidedAudit, forgetGuidedAudit } from 'c/ohmAuditRun';

/**
 * Root FSM + all Apex I/O for the Ohm audit experience (SPEC §L.4).
 * WELCOME -> DISCOVERING/ANALYZING -> IMPACT -> RECOMMENDATIONS (+ ERROR).
 * Owns the polling loop
 * (one in-flight call, durable report resumption, no assumed retrieval deadline).
 * Moves focus to the mounted screen's [data-focus-heading] after every transition.
 */
export default class OhmAuditExperience extends LightningElement {
    @track state = STATES.WELCOME;
    @track isReady = false;

    @track reportId;
    @track readout;
    @track errorMessage;

    // Live progress props threaded to ohmDiscoverAnalyze.
    @track runStatus;
    @track stageMessage;
    @track percentComplete = 0;

    _stopAuditWatch;
    _connected = false;
    _recoverableError = false;
    _focusPending = false;

    // ---- lifecycle ----------------------------------------------------------
    connectedCallback() {
        this._connected = true;
        this.isReady = true;
        this._focusPending = true;
        const pending = pendingGuidedAudit();
        if (pending) this._observeAudit(pending);
    }

    disconnectedCallback() {
        this._connected = false;
        this._stopPoll();
    }

    renderedCallback() {
        if (!this._focusPending || !this.isReady) {
            return;
        }
        const child = this.template.querySelector('[data-screen]');
        if (child && typeof child.focusHeading === 'function') {
            child.focusHeading();
            this._focusPending = false;
            return;
        }
        const heading = this.template.querySelector('[data-focus-heading]');
        if (heading) {
            heading.focus();
            this._focusPending = false;
        }
    }

    // ---- state getters ------------------------------------------------------
    get isWelcome() {
        return this.state === STATES.WELCOME;
    }
    get isDiscoverAnalyze() {
        return (
            this.state === STATES.DISCOVERING || this.state === STATES.ANALYZING
        );
    }
    get isImpact() {
        return this.state === STATES.IMPACT;
    }
    get isRecommendations() {
        return this.state === STATES.RECOMMENDATIONS;
    }
    get isError() {
        return this.state === STATES.ERROR;
    }
    get retryLabel() { return this._recoverableError ? 'Resume checking' : 'Try again'; }
    get errorHelp() { return this._recoverableError ? 'Your audit may still be processing in Salesforce. Resume checking this report without starting a duplicate.' : 'Start a new audit to retrieve fresh source.'; }
    get reportUrl() { return this.reportId ? `/lightning/r/Agent_Audit_Report__c/${encodeURIComponent(this.reportId)}/view` : null; }

    get findings() {
        return (this.readout && this.readout.findings) || [];
    }
    get reviewJson() { return this.readout && this.readout.reviewJson; }
    get volumeAssumption() {
        return this.readout && this.readout.volumeAssumption;
    }
    get telemetryBacked() {
        return !!(this.readout && this.readout.telemetryBacked);
    }

    _setState(next) {
        if (this.state !== next) {
            this.state = next;
            this._focusPending = true;
        }
    }

    // ---- transitions --------------------------------------------------------
    handleStart() {
        if (this.isDiscoverAnalyze) return;
        this.errorMessage = undefined;
        this._recoverableError = false;
        this.runStatus = 'Queued';
        this.stageMessage = 'Starting the audit…';
        this.percentComplete = 0;
        this._setState(STATES.DISCOVERING);
        startAudit()
            .then((reportId) => {
                if (!reportId) throw new Error('Salesforce did not return an audit record. Try again.');
                this.reportId = reportId;
                rememberGuidedAudit(reportId);
                if (this._connected) this._observeAudit(reportId);
            })
            .catch((error) => this._fail(error));
    }

    _observeAudit(reportId) {
        this._stopPoll();
        this.reportId = reportId;
        this.errorMessage = undefined;
        this.runStatus = 'Queued';
        this.stageMessage = 'Connecting to your audit in Salesforce.';
        this._setState(STATES.DISCOVERING);
        this._stopAuditWatch = watchAudit({ reportId },
            (status) => {
                this.runStatus = status.runStatus;
                this.stageMessage = status.stageMessage;
                this.percentComplete = status.percentComplete || 0;
                this._setState(['Analyzing', 'LoadingResults'].includes(status.runStatus) ? STATES.ANALYZING : STATES.DISCOVERING);
            },
            (readout) => {
                this.readout = readout;
                forgetGuidedAudit();
                this._setState(STATES.IMPACT);
            },
            (status) => {
                if (status.terminal) forgetGuidedAudit();
                this._fail({ message: status.error }, !status.terminal);
            });
    }

    handleViewRecommendations() {
        this._setState(STATES.RECOMMENDATIONS);
    }
    handleBack() {
        this._setState(STATES.IMPACT);
    }
    handleRetry() {
        if (this._recoverableError && this.reportId) {
            this._observeAudit(this.reportId);
            return;
        }
        this.reportId = undefined;
        this.readout = undefined;
        this.errorMessage = undefined;
        this._setState(STATES.WELCOME);
    }

    _fail(error, recoverable = false) {
        this._stopPoll();
        this._recoverableError = recoverable;
        this.errorMessage = auditError(error);
        this._setState(STATES.ERROR);
    }

    _stopPoll() {
        if (this._stopAuditWatch) {
            this._stopAuditWatch();
            this._stopAuditWatch = undefined;
        }
    }

}
