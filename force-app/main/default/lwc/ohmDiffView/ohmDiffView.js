import { LightningElement, api, track } from 'lwc';
import getDiff from '@salesforce/apex/OhmAuditController.getArtifactDiff';
import { formatNumber, gradeTone, GRADE_WORDS } from 'c/ohmConstants';

/**
 * ohmDiffView — before/after fix comparison for ONE process (SPEC §2.6).
 *
 * @api plannerId -> connectedCallback getDiff(plannerId). Renders two columns
 * BEFORE | AFTER (grade chip, score, energy, findings), a prominent DELTA row
 * (grade transition, energy delta, findings delta) toned teal when improved and
 * amber when worse, and — when the reports carry instruction snapshots — a
 * compact instructions comparison (old vs new char count + the two texts in
 * scrollable mono blocks). With only one audit (beforeReportId null) it shows a
 * quiet "re-audit after a change" prompt. [Keep]/[Revert] are intentionally
 * omitted — this view never writes to the org.
 */
export default class OhmDiffView extends LightningElement {
    @api calmMode = false;
    _artifactKey;
    @api
    get artifactKey() { return this._artifactKey; }
    set artifactKey(value) {
        if (this._artifactKey !== value) {
            this._artifactKey = value;
            if (this._plannerId) this.refresh();
        }
    }

    @track diff;
    @track isLoading = false;
    @track loadError;

    _plannerId;
    _loadedFor;

    @api
    get plannerId() {
        return this._plannerId;
    }
    set plannerId(value) {
        this._plannerId = value;
        if (value && value !== this._loadedFor) {
            this.load();
        }
    }

    connectedCallback() {
        if (this._plannerId && this._plannerId !== this._loadedFor) {
            this.load();
        }
    }

    /** Re-fetch the diff (public so the process page can refresh after a re-audit). */
    @api
    refresh() {
        this._loadedFor = undefined;
        this.load();
    }

    async load() {
        const planner = this._plannerId;
        const artifact = this._artifactKey;
        if (!planner) {
            return;
        }
        this._loadedFor = planner;
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getDiff({ plannerId: planner, artifactKey: artifact || null });
            if (planner !== this._plannerId || artifact !== this._artifactKey) return;
            this.diff = data || null;
        } catch (e) {
            this.loadError = this._msg(e) || 'Could not load the comparison.';
            this.diff = null;
        } finally {
            this.isLoading = false;
        }
    }

    // ---- host / presentation ------------------------------------------------
    get hostClass() {
        return this.calmMode ? 'ohm-diff ohm-diff--calm' : 'ohm-diff';
    }

    get hasDiff() {
        return !!this.diff;
    }

    // Only one audit exists -> nothing to compare against yet.
    get isSingle() {
        return this.hasDiff && !this.diff.beforeReportId;
    }
    get hasComparison() {
        return this.hasDiff && !!this.diff.beforeReportId;
    }
    get comparisonReason() { return this.diff && this.diff.comparisonReason; }
    get artifactLabel() { return this.diff && this.diff.artifactLabel; }

    get label() {
        return this.diff ? this.diff.label : '';
    }

    // ---- BEFORE column ------------------------------------------------------
    get beforeGrade() {
        return this.diff ? this.diff.beforeGrade : null;
    }
    get beforeGradeWord() {
        return GRADE_WORDS[this.beforeGrade] || '';
    }
    get beforeChipClass() {
        return `ohm-diff__chip ohm-diff__chip--${gradeTone(this.beforeGrade)}`;
    }
    get beforeScoreText() {
        return this._num(this.diff && this.diff.beforeScore);
    }
    get beforeEnergyText() {
        return `${formatNumber(this.diff && this.diff.beforeEnergyWhCentral)} Wh/yr`;
    }
    get beforeFindingsText() {
        return this._num(this.diff && this.diff.beforeFindings);
    }
    get beforeAtText() {
        return this._fmtDate(this.diff && this.diff.beforeAt);
    }

    // ---- AFTER column -------------------------------------------------------
    get afterGrade() {
        return this.diff ? this.diff.afterGrade : null;
    }
    get afterGradeWord() {
        return GRADE_WORDS[this.afterGrade] || '';
    }
    get afterChipClass() {
        return `ohm-diff__chip ohm-diff__chip--${gradeTone(this.afterGrade)}`;
    }
    get afterScoreText() {
        return this._num(this.diff && this.diff.afterScore);
    }
    get afterEnergyText() {
        return `${formatNumber(this.diff && this.diff.afterEnergyWhCentral)} Wh/yr`;
    }
    get afterFindingsText() {
        return this._num(this.diff && this.diff.afterFindings);
    }
    get afterAtText() {
        return this._fmtDate(this.diff && this.diff.afterAt);
    }

    // ---- DELTA row ----------------------------------------------------------
    get improved() {
        return !!(this.diff && this.diff.comparable === true && this.diff.improved);
    }
    get deltaClass() {
        if (!this.diff || this.diff.comparable !== true) return 'ohm-diff__delta';
        return this.improved
            ? 'ohm-diff__delta ohm-diff__delta--improved'
            : 'ohm-diff__delta ohm-diff__delta--worse';
    }
    get gradeTransition() {
        const b = this.beforeGrade || '—';
        const a = this.afterGrade || '—';
        return `${b} → ${a}`;
    }
    // energyDeltaWh = before - after (positive = improvement / energy saved).
    get energyDeltaText() {
        if (!this.diff || this.diff.comparable !== true) return 'Not comparable';
        const d = this.diff ? Number(this.diff.energyDeltaWh) : 0;
        if (!d) {
            return '0 Wh/yr';
        }
        const sign = d > 0 ? '−' : '+';
        return `${sign}${formatNumber(Math.abs(d))} Wh/yr`;
    }
    get scoreDeltaText() {
        const d = this.diff ? Number(this.diff.scoreDelta) : 0;
        const sign = d > 0 ? '+' : d < 0 ? '−' : '';
        return `${sign}${formatNumber(Math.abs(d))}`;
    }
    get findingsTransition() {
        const b = this._num(this.diff && this.diff.beforeFindings);
        const a = this._num(this.diff && this.diff.afterFindings);
        return `${b} → ${a} findings`;
    }
    get deltaSummary() {
        if (!this.diff || this.diff.comparable !== true) return 'Comparison unavailable';
        return this.improved ? 'Improved' : 'No improvement';
    }

    // ---- instructions comparison (optional) --------------------------------
    get hasInstructions() {
        if (!this.hasComparison) {
            return false;
        }
        const b = this.diff.beforeInstructions;
        const a = this.diff.afterInstructions;
        return (b !== null && b !== undefined) || (a !== null && a !== undefined);
    }
    get beforeInstructions() {
        return (this.diff && this.diff.beforeInstructions) || '';
    }
    get afterInstructions() {
        return (this.diff && this.diff.afterInstructions) || '';
    }
    get beforeCharCount() {
        return formatNumber(this.beforeInstructions.length);
    }
    get afterCharCount() {
        return formatNumber(this.afterInstructions.length);
    }
    // ~4 chars/token is the estimator's convention; a rough, honest approximation.
    get beforeTokenCount() {
        return formatNumber(Math.ceil(this.beforeInstructions.length / 4));
    }
    get afterTokenCount() {
        return formatNumber(Math.ceil(this.afterInstructions.length / 4));
    }
    get charDeltaText() {
        const d = this.beforeInstructions.length - this.afterInstructions.length;
        if (!d) {
            return 'no change';
        }
        const sign = d > 0 ? '−' : '+';
        return `${sign}${formatNumber(Math.abs(d))} chars`;
    }

    // ---- interaction --------------------------------------------------------
    handleRetry() {
        this.refresh();
    }

    // ---- helpers ------------------------------------------------------------
    _num(v) {
        return v === null || v === undefined ? '—' : formatNumber(v);
    }
    _fmtDate(value) {
        if (!value) {
            return '';
        }
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) {
            return '';
        }
        return d.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric'
        });
    }
    _msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || null;
    }
}
