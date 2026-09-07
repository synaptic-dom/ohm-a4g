import { LightningElement, api, track } from 'lwc';

/**
 * S2 progress host (Discovering + Analyzing). PURE DISPLAY — the root polls;
 * this component performs ZERO Apex I/O. Determinate progress bar + an
 * aria-live="polite" running log that appends each new stageMessage.
 * Calm Mode = discrete text only, no shimmer/spinner (AC-F2).
 */
export default class OhmDiscoverAnalyze extends LightningElement {
    @api reportId;
    @api runStatus;
    @api percentComplete = 0;
    @api calmMode = false;

    _stageMessage;
    @track logEntries = [];
    _seq = 0;

    @api
    get stageMessage() {
        return this._stageMessage;
    }
    set stageMessage(value) {
        if (value && value !== this._stageMessage) {
            this._stageMessage = value;
            this._seq += 1;
            this.logEntries = [
                ...this.logEntries,
                { id: this._seq, text: value }
            ];
        } else {
            this._stageMessage = value;
        }
    }

    get showSpinner() {
        return !this.calmMode;
    }

    get progressValue() {
        return this.percentComplete || 0;
    }

    get headingText() {
        return this.runStatus === 'Analyzing'
            ? 'Analyzing for waste signals'
            : 'Discovering published Agent Script bundles';
    }

    @api
    focusHeading() {
        const h = this.template.querySelector('[data-focus-heading]');
        if (h) {
            h.focus();
        }
    }
}
