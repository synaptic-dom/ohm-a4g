import { LightningElement, api, track } from 'lwc';
import getProcessDetail from '@salesforce/apex/OhmAuditController.getProcessDetail';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';
import { pendingAudits, rememberAudit, forgetAudit, watchAudit, auditError } from 'c/ohmAuditRun';
import { formatNumber, GRADE_WORDS } from 'c/ohmConstants';
import { parseReview } from 'c/ohmReviewData';
import { bundleLabel } from 'c/ohmDisplay';

/**
 * ohmProcessPage — the drill-down from a Fleet row into ONE process (SPEC §2.2).
 *
 * On receiving a plannerId it imperatively getProcessDetail(plannerId): loading →
 * content. Layout: a context header (label/domain/grade/energy + Re-audit), the
 * centerpiece <c-ohm-call-graph> (agent→topic→action), a side <c-ohm-node-inspector>
 * for the selected node, and an "Ask Ohm" assistant strip placeholder (Wave 6 seam).
 *
 * Handles the unaudited case (nodes present, findings=[], grade/energy null): a
 * prominent "Audit this process" CTA that runs auditProcess then reloads. Selection
 * is owned here and passed down to both the graph (ring) and the inspector (finding).
 */
export default class OhmProcessPage extends LightningElement {
    @api calmMode = false;

    @track detail;
    @track isLoading = false;
    @track loadError;
    @track selectedNodeId;
    @track isReauditing;
    // Whether the before/after diff panel is revealed under the graph.
    @track showDiff = false;
    @track auditRun;
    _stopAuditWatch;
    _connected = false;
    _loadRevision = 0;
    showWorkspace = false;
    _initialNodeId;
    _initialArtifactKey;
    _initialIntent;
    _initialQuestion;
    _initialApplied;
    _pendingFocus;
    _pendingQuestion;
    _pendingQuestionFocus = false;

    @api get initialNodeId() { return this._initialNodeId; }
    set initialNodeId(value) { this._initialNodeId = value; this.applyInitialSelection(); }
    @api get initialArtifactKey() { return this._initialArtifactKey; }
    set initialArtifactKey(value) { this._initialArtifactKey = value; this.applyInitialSelection(); }
    @api get initialIntent() { return this._initialIntent; }
    set initialIntent(value) { this._initialIntent = value; this.applyInitialSelection(); }
    @api get initialQuestion() { return this._initialQuestion; }
    set initialQuestion(value) { this._initialQuestion = value; this.applyInitialSelection(); }

    renderedCallback() {
        if (this._pendingQuestion) {
            const assistant = this.template.querySelector('[data-id="ask-assistant"]');
            if (assistant && typeof assistant.prepareQuestion === 'function') {
                assistant.prepareQuestion(this._pendingQuestion, this._pendingQuestionFocus);
                this._pendingQuestion = null;
                this._pendingQuestionFocus = false;
            }
        }
        if (this._pendingFocus) {
            const target = this.template.querySelector(this._pendingFocus === 'source' ? '[data-id="workspace-heading"]' : '[data-id="review-panel"]');
            if (target) {
                if (typeof target.focusHeading === 'function') target.focusHeading();
                else target.focus();
                if (typeof target.scrollIntoView === 'function') target.scrollIntoView({ block: 'start' });
                this._pendingFocus = null;
            }
        }
    }

    _plannerId;
    _loadedFor;

    @api
    get plannerId() {
        return this._plannerId;
    }
    set plannerId(value) {
        if (value !== this._plannerId) {
            if (this._stopAuditWatch) this._stopAuditWatch();
            this.auditRun = undefined;
            this.isReauditing = false;
            this.detail = undefined;
            this.showDiff = false;
            this.showWorkspace = false;
            this._initialApplied = null;
        }
        this._plannerId = value;
        if (this._connected) this.resumeAudit();
        if (value && value !== this._loadedFor) {
            this.loadDetail();
        }
    }

    connectedCallback() {
        this._connected = true;
        if (this.auditRun && this.auditRun.reportId && !this.auditRun.error && this.auditRun.runStatus !== 'Complete') {
            this.observeAudit(this.auditRun);
        }
        this.resumeAudit();
        if (this._plannerId && this._plannerId !== this._loadedFor) {
            this.loadDetail();
        }
    }

    disconnectedCallback() {
        this._connected = false;
        if (this._stopAuditWatch) this._stopAuditWatch();
    }

    async loadDetail(expectedReportId) {
        const planner = this._plannerId;
        if (!planner) {
            return;
        }
        const revision = ++this._loadRevision;
        this._loadedFor = planner;
        this.isLoading = true;
        this.loadError = undefined;
        const priorArtifact = this.selectedNode && this.selectedNode.artifactKey;
        this.selectedNodeId = undefined;
        try {
            const data = await getProcessDetail({ plannerId: planner });
            if (planner !== this._plannerId || revision !== this._loadRevision) return false;
            if (expectedReportId && (!data || data.reportId !== expectedReportId)) {
                throw new Error('The audit finished, but its results are not available yet. Resume checking to load this report.');
            }
            this.detail = data || null;
            const selected = this.nodes.find((node) => priorArtifact && node.artifactKey === priorArtifact);
            this.selectedNodeId = selected && selected.id;
            this.applyInitialSelection();
            return true;
        } catch (e) {
            if (planner !== this._plannerId || revision !== this._loadRevision) return false;
            if (expectedReportId) throw e;
            this.loadError = this._msg(e) || 'Could not load this process.';
            this.detail = null;
        } finally {
            if (planner === this._plannerId && revision === this._loadRevision) this.isLoading = false;
        }
        return false;
    }

    get showAuditResults() {
        return this.hasDetail && (!this.auditRun || (this.auditRun.runStatus === 'Complete' && !this.auditRun.error && this.reportId === this.auditRun.reportId));
    }
    get showSummaryMetrics() { return this.isAudited && this.showAuditResults; }
    get auditPendingNotice() { return this.auditRun && !this.showAuditResults; }

    // ---- host / presentation ------------------------------------------------
    get hostClass() {
        return 'ohm-process';
    }

    get hasDetail() {
        return !!this.detail;
    }
    get nodes() {
        return this.detail && this.detail.nodes ? this.detail.nodes : [];
    }
    get findings() {
        return this.detail && this.detail.findings ? this.detail.findings : [];
    }

    get label() {
        return this.detail ? bundleLabel(this.detail.label) : '';
    }
    get domain() {
        return this.detail && this.detail.domain && this.detail.domain.toLowerCase() !== 'general' ? this.detail.domain : '';
    }

    // audited == a process report exists for this planner
    get isAudited() {
        return !!(this.detail && this.detail.reportId);
    }
    get isUnaudited() {
        return this.hasDetail && !this.isAudited;
    }

    // ---- grade chip (reuses the fleet chip semantics) -----------------------
    get grade() {
        return this.detail ? this.detail.grade : null;
    }
    get gradeWord() {
        return this.grade ? GRADE_WORDS[this.grade] || '' : '';
    }
    get gradeChipClass() {
        const g = this.grade;
        let tone = 'muted';
        if (g === 'F') {
            tone = 'hot';
        } else if (g === 'D') {
            tone = 'warm';
        } else if (g === 'C') {
            tone = 'muted';
        } else if (g === 'A' || g === 'B') {
            tone = 'cool';
        }
        return `ohm-process__chip ohm-process__chip--${tone}`;
    }
    get energyText() {
        const e = this.detail ? this.detail.energyWhCentral : null;
        return e !== null && e !== undefined
            ? `${formatNumber(e)} Wh/yr`
            : '—';
    }

    // ---- selection → node + matching finding --------------------------------
    get selectedNode() {
        if (!this.selectedNodeId) {
            return null;
        }
        return this.nodes.find((n) => n.id === this.selectedNodeId) || null;
    }

    get selectedFinding() {
        const node = this.selectedNode;
        if (!node || !node.wasteful) {
            return null;
        }
        const findings = this.findings;
        // match on tooling id first, then artifactType|apiName (mirrors Apex)
        let match = findings.find(
            (f) =>
                f.targetArtifact &&
                f.targetArtifact.toolingId &&
                f.targetArtifact.toolingId === node.id
        );
        if (!match) {
            const type = (node.nodeType || '').toLowerCase();
            const api = (node.apiName || '').toLowerCase();
            match = findings.find(
                (f) =>
                    (f.artifactType || '').toLowerCase() === type &&
                    f.targetArtifact &&
                    (f.targetArtifact.apiName || '').toLowerCase() === api
            );
        }
        return match || null;
    }

    get reportId() {
        return this.detail ? this.detail.reportId : null;
    }
    get reviewJson() { return this.detail && this.detail.reviewJson; }
    get sourceOptions() { return this.nodes.map((node) => ({ value: node.id, label: `${node.label || node.apiName} · ${node.nodeType}`, selected: node.id === this.selectedNodeId })); }
    get selectedSourceLabel() { return this.selectedNode ? this.selectedNode.label : 'Explore published source'; }

    resolveSource(nodeId, artifactKey) {
        let node = this.nodes.find((item) => (nodeId && item.id === nodeId) || (artifactKey && item.artifactKey === artifactKey));
        if (!node && artifactKey) {
            const artifact = parseReview(this.reviewJson).artifacts.find((item) => item.artifactKey === artifactKey);
            if (artifact) node = this.nodes.find((item) => item.id === artifact.artifactId);
        }
        if (!node && nodeId && nodeId.startsWith('configuration:')) node = this.nodes.find((item) => item.id === nodeId.slice('configuration:'.length));
        return node;
    }
    applyInitialSelection() {
        if (!this.detail || (!this._initialNodeId && !this._initialArtifactKey && !this._initialIntent)) return;
        const key = [this._plannerId, this._initialNodeId, this._initialArtifactKey, this._initialIntent, this._initialQuestion].join('|');
        if (this._initialApplied === key) return;
        this._initialApplied = key;
        const node = this.resolveSource(this._initialNodeId, this._initialArtifactKey);
        if (node) {
            this.selectedNodeId = node.id;
            this.showWorkspace = this._initialIntent !== 'recommendation';
            this._pendingFocus = this.showWorkspace ? 'source' : 'review';
            this._pendingQuestion = this._initialQuestion;
            this._pendingQuestionFocus = false;
        } else this._pendingFocus = 'review';
    }
    handleReviewAction(event) {
        const detail = event.detail || {};
        const node = this.resolveSource(detail.artifactId, detail.artifactKey);
        if (node) this.selectedNodeId = node.id;
        else this.selectedNodeId = undefined;
        this.showWorkspace = true;
        this._pendingFocus = 'source';
        this._pendingQuestion = detail.question || null;
        this._pendingQuestionFocus = false;
    }
    handleWorkspaceToggle(event) { this.showWorkspace = event.target.open; }
    handleSourceChange(event) { this.selectedNodeId = event.target.value || undefined; }
    handleAskSource() {
        this._pendingQuestion = 'Help me understand this published source and the recommendations that apply to it. Explain a safe next change while preserving required behavior.';
        this._pendingQuestionFocus = true;
        this._pendingFocus = 'source';
        this.showWorkspace = true;
        Promise.resolve().then(() => {
            const assistant = this.template.querySelector('[data-id="ask-assistant"]');
            if (this._pendingQuestion && assistant && typeof assistant.prepareQuestion === 'function') { assistant.prepareQuestion(this._pendingQuestion, true); this._pendingQuestion = null; this._pendingQuestionFocus = false; }
        });
    }

    get selectedArtifactKey() { return this.selectedNode && this.selectedNode.artifactKey; }
    get selectedSourceHash() { return this.selectedNode && this.selectedNode.sourceHash; }
    get coverageStatus() { return (this.detail && this.detail.coverageStatus) || 'Incomplete'; }
    get coverageWarnings() { return (this.detail && this.detail.coverageWarnings) || []; }
    get impactScope() { return (this.detail && this.detail.impactScope) || 'Modeled instruction input'; }
    get impactAssumptions() { return this.detail && this.detail.impactAssumptions; }
    get impactFactors() { return this.detail && this.detail.impactFactors; }
    /** The strip reads the detail payload's modeled bands; an unaudited bundle yields its empty state. */
    get footprints() { return this.detail ? [{ ...this.detail, label: this.label }] : []; }
    get impactRange() {
        if (!this.detail || this.detail.energyWhLow == null) return 'Estimate unavailable until instruction source is available.';
        return `Range ${formatNumber(this.detail.energyWhLow)}–${formatNumber(this.detail.energyWhHigh)} Wh/year · Low confidence`;
    }
    get detectorCoverage() {
        const labels = { INSTRUCTION_BLOAT: 'Instructions', MODEL_RIGHTSIZING: 'Model suitability', LLM_WHERE_DETERMINISTIC: 'Action review', REDUNDANT_CALLS: 'Repeated calls' };
        return Object.entries((this.detail && this.detail.detectorCoverage) || {}).filter(([key]) => key !== 'MODEL_RIGHTSIZING').map(([key, status]) => ({ key, text: `${labels[key] || key}: ${status}` }));
    }

    // ---- before/after diff --------------------------------------------------
    // A comparison is only meaningful once at least one audit exists; the diff
    // component itself handles the single-report ("re-audit to compare") state.
    get canCompare() {
        return this.isAudited;
    }
    get compareToggleLabel() {
        return this.showDiff
            ? 'Hide comparison'
            : 'Compare last two audits';
    }

    // ---- interaction --------------------------------------------------------
    handleSelectNode(event) {
        const nodeId = event.detail && event.detail.nodeId;
        if (nodeId) {
            this.selectedNodeId = nodeId;
            this.showWorkspace = true;
            this._pendingFocus = 'source';
        }
    }

    handleBack() {
        this.dispatchEvent(
            new CustomEvent('backtofleet', { bubbles: true, composed: true })
        );
    }

    handleToggleDiff() {
        this.showDiff = !this.showDiff;
    }

    async handleReaudit() {
        if (!this._plannerId || this.isReauditing) return;
        if (this.auditRun && this.auditRun.reportId && !this.auditRun.terminal && this.auditRun.error) {
            this.observeAudit({ ...this.auditRun, error: null, canRetry: false });
            return;
        }
        const plannerId = this._plannerId;
        const run = { plannerId, label: this.label, hadPriorAudit: this.isAudited, runStatus: 'Queued', stageMessage: 'Requesting a fresh audit from Salesforce.' };
        this.auditRun = run;
        this.isReauditing = true;
        this.loadError = undefined;
        this.showDiff = false;
        try {
            const reportId = await auditProcess({ plannerId });
            if (!reportId) throw new Error('Salesforce did not return an audit record. Retry the audit.');
            const pending = { ...run, reportId };
            rememberAudit(pending);
            if (plannerId === this._plannerId && this._connected) this.observeAudit(pending);
        } catch (error) {
            if (plannerId !== this._plannerId) return;
            this.isReauditing = false;
            this.auditRun = { ...run, error: auditError(error), canRetry: true, terminal: true };
        }
    }

    resumeAudit() {
        if (!this._plannerId || this.auditRun) return;
        const pending = pendingAudits().find((run) => run.plannerId === this._plannerId);
        if (pending) this.observeAudit({ ...pending, runStatus: 'Queued', stageMessage: 'Reconnecting to your audit in Salesforce.' });
    }

    observeAudit(run) {
        if (this._stopAuditWatch) this._stopAuditWatch();
        this.auditRun = run;
        this.isReauditing = true;
        this._stopAuditWatch = watchAudit(run,
            (status) => { this.auditRun = status; },
            async (status) => {
                try {
                    const loaded = await this.loadDetail(status.reportId);
                    if (!loaded) return;
                    if (status.plannerId !== this._plannerId || !this._connected) return;
                    forgetAudit(status.plannerId);
                    this.auditRun = status;
                    this.isReauditing = false;
                    this.showDiff = false;
                    Promise.resolve().then(() => {
                        for (const selector of ['[data-id="ask-assistant"]', '[data-id="diff-view"]']) {
                            const child = this.template.querySelector(selector);
                            if (child && typeof child.refresh === 'function') child.refresh();
                        }
                    });
                } catch (error) {
                    if (status.plannerId !== this._plannerId) return;
                    this.isReauditing = false;
                    this.auditRun = { ...status, error: auditError(error), canRetry: true, terminal: false };
                }
            },
            (status) => {
                this.auditRun = status;
                this.isReauditing = false;
                if (status.terminal) forgetAudit(status.plannerId);
            });
    }

    handleAuditRetry() {
        if (!this.auditRun || this.isReauditing) return;
        if (this.auditRun.terminal || !this.auditRun.reportId) this.handleReaudit();
        else this.observeAudit({ ...this.auditRun, error: null, canRetry: false, stageMessage: 'Reconnecting to your audit in Salesforce.' });
    }

    handleRetry() {
        this._loadedFor = undefined;
        this.loadDetail();
    }

    _msg(e) {
        return (
            (e && e.body && e.body.message) || (e && e.message) || null
        );
    }
}
