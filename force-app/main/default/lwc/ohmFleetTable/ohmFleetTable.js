import { LightningElement, api, track } from 'lwc';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';
import { pendingAudits, rememberAudit, forgetAudit, watchAudit, auditError } from 'c/ohmAuditRun';
import { formatNumber } from 'c/ohmConstants';
import { parseReview } from 'c/ohmReviewData';
import { bundleLabel } from 'c/ohmDisplay';

/**
 * ohmFleetTable — the Fleet home (SPEC §2.1).
 * Imperatively lists discovered processes (getFleet), audits one on demand
 * (auditProcess -> refresh), and fires `openprocess` for audited rows. Filter by
 * domain + grade, sort by energy, search over label — all client-side over the
 * returned list. Everything is null-guarded because an un-audited row has null
 * grade/score/energy/lastAudited.
 */
export default class OhmFleetTable extends LightningElement {
    @api calmMode = false;

    @track rows = [];
    @track isLoading = true;
    @track loadError;

    // filter / sort / search state
    @track domainFilter = 'ALL';
    @track gradeFilter = 'ALL';
    @track sortDir = 'desc'; // energy sort: desc | asc | none
    @track searchTerm = '';

    // per-row audit progress + error, keyed by plannerId
    @track rowErrors = {};
    @track auditRuns = {};
    _auditWatches = new Map();
    _connected = false;
    _fleetLoadRevision = 0;

    connectedCallback() {
        this._connected = true;
        this.loadFleet();
        pendingAudits().forEach((run) => this.observeAudit({ ...run, runStatus: 'Queued', stageMessage: 'Reconnecting to your audit in Salesforce.' }));
    }
    disconnectedCallback() {
        this._connected = false;
        this._auditWatches.forEach((stop) => stop());
        this._auditWatches.clear();
    }
    get progressRuns() { return Object.values(this.auditRuns); }
    get anyAuditPending() { return this.progressRuns.some((run) => !run.error && run.runStatus !== 'Complete' && run.runStatus !== 'Failed'); }


    async loadFleet() {
        const revision = ++this._fleetLoadRevision;
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getFleet();
            if (revision !== this._fleetLoadRevision) return;
            this.rows = Array.isArray(data) ? data.map((row) => ({ ...row, _review: parseReview(row.reviewJson) })) : [];
        } catch (e) {
            if (revision !== this._fleetLoadRevision) return;
            this.loadError = this._msg(e) || 'Could not load the fleet.';
            this.rows = [];
        } finally {
            if (revision === this._fleetLoadRevision) this.isLoading = false;
        }
    }

    // ---- host class ---------------------------------------------------------
    get hostClass() {
        return 'ohm-fleet';
    }

    // ---- filter option models ----------------------------------------------
    get domainOptions() {
        const set = new Set();
        this.rows.forEach((r) => {
            if (r.domain) {
                set.add(r.domain);
            }
        });
        const opts = [{ label: 'All domains', value: 'ALL' }];
        Array.from(set)
            .sort()
            .forEach((d) => opts.push({ label: d, value: d }));
        return opts;
    }

    get gradeOptions() {
        return [
            { label: 'All reviews', value: 'ALL' },
            { label: 'A · No material issue', value: 'A' },
            { label: 'B · Improvement opportunity', value: 'B' },
            { label: 'C · Priority fix', value: 'C' },
            { label: 'Unrated · Insufficient evidence', value: 'UNRATED' },
            { label: 'Review not run', value: 'NONE' }
        ].map((option) => ({ ...option, selected: option.value === this.gradeFilter }));
    }

    // ---- the visible, decorated rows ---------------------------------------
    get visibleRows() {
        let out = this.rows.slice();

        if (this.domainFilter !== 'ALL') {
            out = out.filter((r) => r.domain === this.domainFilter);
        }
        if (this.gradeFilter === 'NONE') {
            out = out.filter((r) => r._review.state === 'not-run');
        } else if (this.gradeFilter !== 'ALL') {
            out = out.filter((r) => r._review.state === 'reviewed' && r._review.categories.some((category) => category.id !== 'MODEL' && category.rating === this.gradeFilter));
        }
        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            out = out.filter(
                (r) =>
                    (r.label || '').toLowerCase().includes(term) ||
                    (r.plannerApiName || '').toLowerCase().includes(term)
            );
        }
        // Put supported opportunities first; never prioritize estimated energy totals.
        const priority = (row) => row._review.categories.some((c) => c.id !== 'MODEL' && c.rating === 'C') ? 3 :
            row._review.categories.some((c) => c.id !== 'MODEL' && c.rating === 'B') ? 2 : row._review.state !== 'reviewed' ? 1 : 0;
        out.sort((a, b) => priority(b) - priority(a) || bundleLabel(a.label).localeCompare(bundleLabel(b.label)));

        return out.map((r) => this._decorate(r));
    }

    _decorate(r) {
        const audited = !!r.audited;
        const review = r._review;
        const run = this.auditRuns[r.plannerId];
        const isAuditing = !!(run && !run.error && run.runStatus !== 'Complete' && run.runStatus !== 'Failed');
        return {
            ...r,
            audited,
            hasReview: review.state === 'reviewed',
            displayLabel: bundleLabel(r.label),
            reviewCategories: review.categories.filter((category) => category.id !== 'MODEL'),
            opportunityLabel: review.categories.some((c) => c.id !== 'MODEL' && c.rating === 'C') ? 'Priority fix' : review.categories.some((c) => c.id !== 'MODEL' && c.rating === 'B') ? 'Improvement opportunity' : null,
            reviewStateLabel: review.state === 'unavailable' ? 'Review unavailable' : 'Review not run',
            hasScenario: audited && r.energyWhCentral != null,
            energyText:
                audited && r.energyWhCentral !== null && r.energyWhCentral !== undefined
                    ? `${formatNumber(r.energyWhCentral)} Wh/yr`
                    : '—',
            topicText: this._count(r.topicCount),
            topicNoun: r.topicCount === 1 ? 'topic' : 'topics',
            actionNoun: r.actionCount === 1 ? 'action' : 'actions',
            actionText: this._count(r.actionCount),
            isAuditing,
            hasPriorResults: audited && isAuditing,
            auditDisabled: this.anyAuditPending,
            progressLabel: run ? run.stageMessage || 'Checking published source…' : '',
            rowError: this.rowErrors[r.plannerId] || null,
            statusLabel: audited ? 'Audited' : 'Not audited yet'
        };
    }

    _count(n) {
        return n === null || n === undefined ? '—' : formatNumber(n);
    }

    // ---- summary strip ------------------------------------------------------
    get discoveredCount() {
        return this.rows.length;
    }
    get auditedCount() {
        return this.rows.filter((r) => r._review.state === 'reviewed').length;
    }
    get totalEnergyText() {
        const hasImpact = this.rows.some((r) => r.audited && r.energyWhCentral != null);
        const sum = this.rows.reduce((acc, r) => {
            if (
                r.audited &&
                r.energyWhCentral !== null &&
                r.energyWhCentral !== undefined
            ) {
                return acc + Number(r.energyWhCentral);
            }
            return acc;
        }, 0);
        return hasImpact ? `${formatNumber(sum)} Wh/yr` : '—';
    }
    get priorityCount() { return this.rows.filter((r) => r._review.categories.some((category) => category.id !== 'MODEL' && category.rating === 'C')).length; }
    get opportunityCount() { return this.rows.filter((r) => r._review.categories.some((category) => category.id !== 'MODEL' && category.rating === 'B')).length; }

    get hasRows() {
        return this.visibleRows.length > 0;
    }
    get isEmptyAfterLoad() {
        return !this.isLoading && !this.loadError && this.rows.length === 0;
    }
    get isFilteredEmpty() {
        return (
            !this.isLoading &&
            !this.loadError &&
            this.rows.length > 0 &&
            this.visibleRows.length === 0
        );
    }

    get sortLabel() {
        if (this.sortDir === 'desc') {
            return 'Input scenario ▼';
        }
        if (this.sortDir === 'asc') {
            return 'Input scenario ▲';
        }
        return 'Input scenario —';
    }

    // ---- interaction --------------------------------------------------------
    handleDomainChange(event) {
        this.domainFilter = event.target.value;
    }
    handleGradeChange(event) {
        this.gradeFilter = event.target.value;
    }
    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }
    handleClearFilters() { this.searchTerm = ''; this.domainFilter = 'ALL'; this.gradeFilter = 'ALL'; }
    handleSortToggle() {
        this.sortDir =
            this.sortDir === 'desc'
                ? 'asc'
                : this.sortDir === 'asc'
                ? 'none'
                : 'desc';
    }

    async handleAudit(event) {
        const plannerId = event.currentTarget.dataset.planner;
        await this.startRowAudit(plannerId);
    }
    async startRowAudit(plannerId) {
        if (!plannerId || this.anyAuditPending) return;
        const existing = this.auditRuns[plannerId];
        if (existing && existing.reportId && !existing.terminal && existing.error) {
            this.observeAudit({ ...existing, error: null, canRetry: false });
            return;
        }
        const row = this.rows.find((item) => item.plannerId === plannerId);
        const run = { plannerId, label: row && row.label, hadPriorAudit: row && row.audited, runStatus: 'Queued', stageMessage: 'Requesting a fresh audit from Salesforce.' };
        this.auditRuns = { ...this.auditRuns, [plannerId]: run };
        this.rowErrors = { ...this.rowErrors, [plannerId]: null };
        try {
            const reportId = await auditProcess({ plannerId });
            if (!reportId) throw new Error('Salesforce did not return an audit record. Retry the audit.');
            const pending = { ...run, reportId };
            rememberAudit(pending);
            if (this._connected) this.observeAudit(pending);
        } catch (error) {
            this.failAudit({ ...run, error: auditError(error), canRetry: true, terminal: true });
        }
    }
    observeAudit(run) {
        const prior = this._auditWatches.get(run.plannerId);
        if (prior) prior();
        this.auditRuns = { ...this.auditRuns, [run.plannerId]: run };
        this._auditWatches.set(run.plannerId, watchAudit(run,
            (status) => { this.auditRuns = { ...this.auditRuns, [run.plannerId]: status }; },
            async (status) => {
                try {
                    await this.loadFleet();
                    if (!this._connected) return;
                    const row = this.rows.find((item) => item.plannerId === status.plannerId);
                    if (!row || row.latestReportId !== status.reportId) throw new Error('The audit finished, but its results are not available yet. Resume checking this report.');
                    forgetAudit(status.plannerId);
                    this.auditRuns = { ...this.auditRuns, [status.plannerId]: status };
                    this._auditWatches.delete(status.plannerId);
                } catch (error) { this.failAudit({ ...status, error: auditError(error), canRetry: true, terminal: false }); }
            }, (status) => this.failAudit(status)));
    }
    failAudit(run) {
        this.auditRuns = { ...this.auditRuns, [run.plannerId]: run };
        this.rowErrors = { ...this.rowErrors, [run.plannerId]: run.error };
        if (run.terminal) forgetAudit(run.plannerId);
    }
    handleRunRetry(event) {
        const run = this.auditRuns[event.detail.plannerId];
        if (!run) return;
        this.rowErrors = { ...this.rowErrors, [run.plannerId]: null };
        if (run.terminal || !run.reportId) this.startRowAudit(run.plannerId);
        else this.observeAudit({ ...run, error: null, canRetry: false, stageMessage: 'Reconnecting to your audit in Salesforce.' });
    }

    handleOpen(event) {
        const plannerId = event.currentTarget.dataset.planner;
        const row = this.rows.find((r) => r.plannerId === plannerId);
        this.dispatchEvent(
            new CustomEvent('openprocess', {
                detail: {
                    plannerId,
                    label: row ? row.label : undefined
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleRetry() {
        this.loadFleet();
    }

    _msg(e) {
        return (
            (e && e.body && e.body.message) ||
            (e && e.message) ||
            null
        );
    }
}
