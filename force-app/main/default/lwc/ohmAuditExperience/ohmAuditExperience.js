import { LightningElement, track } from 'lwc';
import startAudit from '@salesforce/apex/OhmAuditController.startAudit';
import getAuditStatus from '@salesforce/apex/OhmAuditController.getAuditStatus';
import getCalmModePreference from '@salesforce/apex/OhmAuditController.getCalmModePreference';
import setCalmModePreference from '@salesforce/apex/OhmAuditController.setCalmModePreference';
import {
    STATES,
    POLL_INTERVAL_MS,
    MAX_POLLS
} from 'c/ohmConstants';

/**
 * Root FSM + all Apex I/O for the Ohm audit experience (SPEC §L.4).
 * WELCOME -> DISCOVERING/ANALYZING -> IMPACT -> RECOMMENDATIONS (+ ERROR).
 * Owns the Calm Mode context (loaded before first paint) and the polling loop
 * (setTimeout, never setInterval; one in-flight call; hard stop after MAX_POLLS).
 * Moves focus to the mounted screen's [data-focus-heading] after every transition.
 */
export default class OhmAuditExperience extends LightningElement {
    @track state = STATES.WELCOME;
    @track calmMode = false;
    @track isReady = false;

    @track reportId;
    @track readout;
    @track errorMessage;

    // Live progress props threaded to ohmDiscoverAnalyze.
    @track runStatus;
    @track stageMessage;
    @track percentComplete = 0;

    _pollHandle;
    _pollCount = 0;
    _focusPending = false;

    // ---- lifecycle ----------------------------------------------------------
    async connectedCallback() {
        try {
            const calm = await getCalmModePreference();
            this.calmMode = !!calm;
        } catch (e) {
            this.calmMode = false;
        } finally {
            this.isReady = true;
            this._focusPending = true;
        }
    }

    disconnectedCallback() {
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

    get findings() {
        return (this.readout && this.readout.findings) || [];
    }
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
        this.errorMessage = undefined;
        this._pollCount = 0;
        this.runStatus = 'Discovering';
        this.stageMessage = 'Starting the audit…';
        this.percentComplete = 0;
        this._setState(STATES.DISCOVERING);
        startAudit()
            .then((reportId) => {
                this.reportId = reportId;
                this._schedulePoll();
            })
            .catch((error) => this._fail(error));
    }

    _schedulePoll() {
        this._stopPoll();
        this._pollHandle = setTimeout(() => {
            this._pollHandle = undefined;
            this.pollStatus();
        }, POLL_INTERVAL_MS);
    }

    pollStatus() {
        if (this._pollCount >= MAX_POLLS) {
            this._fail({ message: 'The audit timed out. Please try again.' });
            return;
        }
        this._pollCount += 1;
        getAuditStatus({ reportId: this.reportId })
            .then((readout) => this._applyStatus(readout))
            .catch((error) => this._fail(error));
    }

    _applyStatus(readout) {
        if (!readout) {
            this._schedulePoll();
            return;
        }
        this.runStatus = readout.runStatus;
        this.stageMessage = readout.stageMessage;
        this.percentComplete = readout.percentComplete || 0;

        switch (readout.runStatus) {
            case 'Analyzing':
                this._setState(STATES.ANALYZING);
                this._schedulePoll();
                break;
            case 'Complete':
                this.readout = readout;
                this._setState(STATES.IMPACT);
                this._stopPoll();
                break;
            case 'Failed':
                this._fail({ message: readout.stageMessage || 'The audit failed.' });
                break;
            default:
                // Queued / Discovering -> keep waiting.
                this._setState(STATES.DISCOVERING);
                this._schedulePoll();
                break;
        }
    }

    handleViewRecommendations() {
        this._setState(STATES.RECOMMENDATIONS);
    }
    handleBack() {
        this._setState(STATES.IMPACT);
    }
    handleRetry() {
        this.reportId = undefined;
        this.readout = undefined;
        this.errorMessage = undefined;
        this._pollCount = 0;
        this._setState(STATES.WELCOME);
    }

    _fail(error) {
        this._stopPoll();
        this.errorMessage =
            (error && error.body && error.body.message) ||
            (error && error.message) ||
            'Something went wrong. Please try again.';
        this._setState(STATES.ERROR);
    }

    _stopPoll() {
        if (this._pollHandle) {
            clearTimeout(this._pollHandle);
            this._pollHandle = undefined;
        }
    }

    // ---- Calm Mode ----------------------------------------------------------
    handleCalmToggle(event) {
        const enabled = event.detail ? !!event.detail.enabled : !this.calmMode;
        const previous = this.calmMode;
        this.calmMode = enabled; // optimistic
        Promise.resolve(setCalmModePreference({ enabled })).catch(() => {
            this.calmMode = previous; // revert on reject
        });
    }
}
