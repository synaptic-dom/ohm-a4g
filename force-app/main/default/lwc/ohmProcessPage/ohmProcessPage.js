import { LightningElement, api, track } from 'lwc';
import getProcessDetail from '@salesforce/apex/OhmAuditController.getProcessDetail';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';
import { formatNumber, GRADE_WORDS } from 'c/ohmConstants';

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

    _plannerId;
    _loadedFor;

    @api
    get plannerId() {
        return this._plannerId;
    }
    set plannerId(value) {
        this._plannerId = value;
        if (value && value !== this._loadedFor) {
            this.loadDetail();
        }
    }

    connectedCallback() {
        if (this._plannerId && this._plannerId !== this._loadedFor) {
            this.loadDetail();
        }
    }

    async loadDetail() {
        const planner = this._plannerId;
        if (!planner) {
            return;
        }
        this._loadedFor = planner;
        this.isLoading = true;
        this.loadError = undefined;
        this.selectedNodeId = undefined;
        try {
            const data = await getProcessDetail({ plannerId: planner });
            this.detail = data || null;
        } catch (e) {
            this.loadError = this._msg(e) || 'Could not load this process.';
            this.detail = null;
        } finally {
            this.isLoading = false;
        }
    }

    // ---- host / presentation ------------------------------------------------
    get hostClass() {
        return this.calmMode
            ? 'ohm-process ohm-process--calm'
            : 'ohm-process';
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
        return this.detail ? this.detail.label : '';
    }
    get domain() {
        return this.detail ? this.detail.domain : '';
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

    // ---- interaction --------------------------------------------------------
    handleSelectNode(event) {
        const nodeId = event.detail && event.detail.nodeId;
        if (nodeId) {
            this.selectedNodeId = nodeId;
        }
    }

    handleBack() {
        this.dispatchEvent(
            new CustomEvent('backtofleet', { bubbles: true, composed: true })
        );
    }

    async handleReaudit() {
        if (!this._plannerId || this.isReauditing) {
            return;
        }
        this.isReauditing = true;
        this.loadError = undefined;
        try {
            await auditProcess({ plannerId: this._plannerId });
            this._loadedFor = undefined; // force a fresh load
            await this.loadDetail();
        } catch (e) {
            this.loadError = this._msg(e) || 'Audit failed. Please try again.';
        } finally {
            this.isReauditing = false;
        }
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
