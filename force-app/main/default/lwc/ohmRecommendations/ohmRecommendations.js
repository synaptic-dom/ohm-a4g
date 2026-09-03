import { LightningElement, api, track } from 'lwc';
import createRemediationTask from '@salesforce/apex/OhmAuditController.createRemediationTask';
import getRecommendations from '@salesforce/apex/OhmAuditController.getRecommendations';
import assignFinding from '@salesforce/apex/OhmAuditController.assignFinding';
import USER_ID from '@salesforce/user/Id';
import {
    SIGNAL_LABELS,
    FIX_TYPE_LABELS,
    formatSavingsBand
} from 'c/ohmConstants';

/**
 * ohmRecommendations — two modes on one component.
 *
 * v1 (default): a container fed `findings` by ohmAuditExperience. Renders one
 * <c-ohm-recommendation-card> per finding and owns createRemediationTask (C12).
 *
 * v2 standalone (`standalone` set true by the RECOMMENDATIONS tab in ohmApp):
 * self-fetches getRecommendations() — findings ranked as QUICK WINS
 * (savings ÷ effort) — and renders them as ranked cards, each with a
 * "Create task" that calls assignFinding(finding, me, null). The v1 path is
 * untouched so the existing experience + suite stay green.
 */
const EFFORT_WEIGHT = { Low: 1, Medium: 2, High: 3 };

export default class OhmRecommendations extends LightningElement {
    @api reportId;
    @api calmMode = false;
    @api volumeAssumption;
    @api telemetryBacked = false;

    // v2: flip the component into the self-fetching quick-wins tab.
    @api standalone = false;

    @track _findings = [];
    @track _errors = {};

    // ---- v2 standalone state ------------------------------------------------
    @track _items = [];
    @track isLoading = false;
    @track loadError;
    @track _busyId;
    @track _createdIds = {}; // findingId -> taskId once a task is made
    @track _itemErrors = {};

    @api
    get findings() {
        return this._findings;
    }
    set findings(value) {
        this._findings = (value || []).map((f) => Object.assign({}, f));
    }

    connectedCallback() {
        if (this.standalone) {
            this.loadRecommendations();
        }
    }

    // ---- v1 container -------------------------------------------------------
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

    // ---- v2 standalone quick-wins ------------------------------------------
    get hostClass() {
        return this.calmMode ? 'ohm-recs2 ohm-recs2--calm' : 'ohm-recs2';
    }

    async loadRecommendations() {
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getRecommendations();
            this._items = Array.isArray(data) ? data : [];
        } catch (e) {
            this.loadError =
                this._msg(e) || 'Could not load the recommendations.';
            this._items = [];
        } finally {
            this.isLoading = false;
        }
    }

    // Ranked, decorated quick-win cards. The server already ranks by
    // savings ÷ effort; we surface the rank and the display fields.
    get quickWins() {
        return this._items.map((it, idx) => {
            const findingId = it.findingId;
            const created = !!this._createdIds[findingId] || !!it.taskId;
            const effort = it.effort || 'Low';
            return {
                key: findingId,
                findingId,
                rank: idx + 1,
                signalLabel:
                    SIGNAL_LABELS[it.signal] || it.signal || 'Unknown signal',
                processText: it.processLabel || it.plannerApiName || '—',
                severityText: it.severity || 'Unknown',
                changeText:
                    it.recommendationText ||
                    it.recommendedTarget ||
                    (FIX_TYPE_LABELS[it.fixType] || it.fixType) ||
                    '',
                targetText: it.recommendedTarget || '',
                fixLabel: FIX_TYPE_LABELS[it.fixType] || it.fixType || '',
                savingsText: `saves ${formatSavingsBand(
                    it.savingsLowWh,
                    it.savingsCentralWh,
                    it.savingsHighWh
                )}`,
                effortText: `Effort: ${effort}`,
                effortClass: `ohm-recs2__effort ohm-recs2__effort--${effort.toLowerCase()}`,
                isBusy: this._busyId === findingId,
                created,
                error: this._itemErrors[findingId] || null
            };
        });
    }

    get hasQuickWins() {
        return !this.isLoading && !this.loadError && this._items.length > 0;
    }
    get isEmptyStandalone() {
        return !this.isLoading && !this.loadError && this._items.length === 0;
    }

    async handleCreateQuickTask(event) {
        const findingId = event.currentTarget.dataset.finding;
        if (!findingId || this._busyId) {
            return;
        }
        this._busyId = findingId;
        this._itemErrors = Object.assign({}, this._itemErrors, {
            [findingId]: null
        });
        try {
            const taskId = await assignFinding({
                findingId,
                userId: USER_ID,
                dueDate: null
            });
            this._createdIds = Object.assign({}, this._createdIds, {
                [findingId]: taskId
            });
        } catch (e) {
            this._itemErrors = Object.assign({}, this._itemErrors, {
                [findingId]: this._msg(e) || 'Could not create the task.'
            });
        } finally {
            this._busyId = undefined;
        }
    }

    handleRetry() {
        this.loadRecommendations();
    }

    _msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || null;
    }
}
