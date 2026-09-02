import { LightningElement, api, track } from 'lwc';
import createRemediationTask from '@salesforce/apex/OhmAuditController.createRemediationTask';

/**
 * S4 Recommendations container. Renders one card per finding and owns the ONLY
 * Apex call in this screen: createRemediationTask (C12 RemediationInputDTO).
 * On success it back-populates the finding's remediationTaskId so the card
 * flips to "Task created"; on failure it feeds the card an error message.
 */
export default class OhmRecommendations extends LightningElement {
    @api reportId;
    @api calmMode = false;
    @api volumeAssumption;
    @api telemetryBacked = false;

    @track _findings = [];
    @track _errors = {};

    @api
    get findings() {
        return this._findings;
    }
    set findings(value) {
        this._findings = (value || []).map((f) => Object.assign({}, f));
    }

    get cards() {
        return this._findings.map((f) => ({
            key: f.id,
            finding: f,
            error: this._errors[f.id]
        }));
    }

    get hasFindings() {
        return this._findings.length > 0;
    }

    @api
    focusHeading() {
        const h = this.template.querySelector('[data-focus-heading]');
        if (h) {
            h.focus();
        }
    }

    handleCreateTask(event) {
        const findingId = event.detail && event.detail.findingId;
        const finding = this._findings.find((f) => f.id === findingId);
        if (!finding) {
            return;
        }
        const input = {
            findingId: finding.id,
            reportId: this.reportId,
            fixType: finding.fixType,
            recommendedTarget: finding.recommendedTarget,
            recommendationText: finding.recommendationText,
            estimatedSavingsCentralWh: finding.estimatedSavingsCentral,
            note: null
        };
        createRemediationTask({ input })
            .then((taskId) => {
                this._errors = Object.assign({}, this._errors, {
                    [findingId]: undefined
                });
                this._findings = this._findings.map((f) =>
                    f.id === findingId
                        ? Object.assign({}, f, { remediationTaskId: taskId })
                        : f
                );
            })
            .catch((error) => {
                const message =
                    (error && error.body && error.body.message) ||
                    (error && error.message) ||
                    'Could not create the task. Please try again.';
                this._errors = Object.assign({}, this._errors, {
                    [findingId]: message
                });
            });
    }
}
