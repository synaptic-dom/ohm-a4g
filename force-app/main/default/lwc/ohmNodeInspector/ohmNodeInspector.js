import { LightningElement, api, track } from 'lwc';
import createRemediationTask from '@salesforce/apex/OhmAuditController.createFindingRemediationTask';
import {
    SIGNAL_LABELS,
    SEVERITY_LABELS,
    formatNumber,
    formatSavingsBand
} from 'c/ohmConstants';

/**
 * ohmNodeInspector — the node detail panel (SPEC §2.2, Idea 5 + 6).
 *
 * Given the selected NodeDTO (+ any matching FindingDTO) it shows: the node
 * header (label/type/apiName/tokenCount/invocationTargetType/model), and — the
 * key part — the raw `instructions` in a scrollable mono block WITH THE WASTEFUL
 * EXCESS HIGHLIGHTED. For INSTRUCTION_BLOAT the excess beyond the soft budget
 * (~500 tokens ≈ 2000 chars) is split off by character position and shown
 * highlighted, captioned "N tokens over budget — re-sent every turn".
 *
 * Process-specific fix CTAs (Trim / Downsize / Replace) show only for the node's
 * signalType; each opens an inline fix panel with the concrete recommendation and
 * a "Create remediation task" button (createRemediationTask). Clean node → a
 * quiet "No findings in available evidence". No node → the empty invitation.
 */
const SOFT_BUDGET_TOKENS = 500;
const SOFT_BUDGET_CHARS = 2000;

// signalType -> the single relevant fix CTA
const CTA_BY_SIGNAL = {
    INSTRUCTION_BLOAT: { key: 'trim', label: 'Trim instructions' },
    MODEL_RIGHTSIZING: { key: 'downsize', label: 'Review model sizing' },
    LLM_WHERE_DETERMINISTIC: { key: 'replace', label: 'Replace with Flow/Apex' }
};

export default class OhmNodeInspector extends LightningElement {
    @api node;
    @api finding;
    @api reportId;
    @api calmMode = false;

    @track activeFix; // which CTA panel is open
    @track taskState = 'idle'; // idle | saving | done | error
    @track taskError;
    @track createdTaskId;

    // reset transient UI whenever a different node is selected
    _lastNodeId;
    renderedCallback() {
        const id = this.node ? this.node.id : null;
        if (id !== this._lastNodeId) {
            this._lastNodeId = id;
            this.activeFix = undefined;
            this.taskState = 'idle';
            this.taskError = undefined;
            this.createdTaskId = undefined;
        }
    }

    get hostClass() {
        return 'ohm-inspector';
    }

    get hasNode() {
        return !!this.node;
    }

    get isWasteful() {
        return !!(this.node && this.node.wasteful && this.node.signalType !== 'MODEL_RIGHTSIZING');
    }

    // ---- header fields ------------------------------------------------------
    get typeLabel() {
        return this.node ? this.node.nodeType : '';
    }
    get tokenText() {
        return this.node && this.node.tokenCount !== null && this.node.tokenCount !== undefined
            ? `${formatNumber(this.node.tokenCount)} tokens`
            : '—';
    }
    get isAction() {
        return this.node && this.node.nodeType === 'Action';
    }
    get invocationTarget() {
        return this.node ? this.node.invocationTargetType : null;
    }
    get boundModel() {
        // NodeDTO may not carry a model today — surface it only if present.
        return this.node ? this.node.boundModel || this.node.model : null;
    }

    // ---- finding summary ----------------------------------------------------
    get signalLabel() {
        const s = this.node && this.node.signalType;
        return (s && SIGNAL_LABELS[s]) || s || '';
    }
    get severityLabel() {
        const sv = this.node && this.node.severity;
        return (sv && SEVERITY_LABELS[sv]) || sv || '';
    }
    get severityChipClass() {
        const sv = this.node && this.node.severity;
        let tone = 'muted';
        if (sv === 'High') {
            tone = 'hot';
        } else if (sv === 'Medium') {
            tone = 'warm';
        } else if (sv === 'Low') {
            tone = 'cool';
        }
        return `ohm-inspector__chip ohm-inspector__chip--${tone}`;
    }
    get evidenceText() {
        return this.finding ? this.finding.evidence : null;
    }
    get hasSavings() {
        return !!(
            this.finding &&
            this.finding.estimatedSavingsCentral !== null &&
            this.finding.estimatedSavingsCentral !== undefined
        );
    }
    get savingsText() {
        if (!this.hasSavings) {
            return '—';
        }
        return formatSavingsBand(
            this.finding.estimatedSavingsLow,
            this.finding.estimatedSavingsCentral,
            this.finding.estimatedSavingsHigh
        );
    }

    // ---- instructions + highlighted excess ----------------------------------
    get hasInstructions() {
        return !!(this.node && this.node.instructions);
    }
    get sourcePath() { return this.node && this.node.sourcePath; }
    get sourceVersion() { return this.node && this.node.sourceVersion; }
    get sourceKind() { return this.node && this.node.sourceKind; }
    get sourceHash() { return this.node && this.node.sourceHash; }
    get sourceRetrievedAt() { return this.node && this.node.sourceRetrievedAt; }
    get sourceVersionLabel() { return this.node && (this.node.sourceVersionIdentifier || this.node.sourceVersion) || 'Version unavailable'; }
    get sourceApiName() { return this.node && this.node.sourceApiName; }
    get isRetrievedSource() { return (this.sourceKind || '').toLowerCase().startsWith('retrieved'); }
    get isImportedSource() { return (this.sourceKind || '').toLowerCase().startsWith('imported'); }
    get sourceVerified() { return this.node && this.node.sourceBindingVerified === true; }
    get sourceTitle() {
        if (this.isRetrievedSource) return 'Retrieved from Salesforce';
        if (this.isImportedSource) return 'Imported source snapshot';
        if (this.sourceKind === 'PlatformScope') return 'Salesforce metadata field';
        return this.hasInstructions ? 'Instruction source snapshot' : 'Instruction source unavailable';
    }
    get sourceStatus() {
        if (!this.hasInstructions) return 'This artifact has no available instruction text. Review audit coverage before drawing conclusions.';
        if (this.isRetrievedSource) return this.sourceVerified ? 'Matched to the selected published version at retrieval time.' : 'Retrieved text is available; publication matching has not been verified.';
        if (this.isImportedSource) return 'This is an imported snapshot. Run a fresh audit to retrieve the published Salesforce source.';
        return 'Source reflects the recorded metadata snapshot.';
    }
    get sourceTimeText() {
        if (!this.sourceRetrievedAt) return this.isImportedSource ? 'Retrieval time not recorded for this import' : 'Retrieval time unavailable';
        const date = new Date(this.sourceRetrievedAt);
        return Number.isNaN(date.getTime()) ? 'Retrieval time unavailable' : date.toISOString().replace('T', ' ').replace('.000Z', ' UTC');
    }
    get sourcePanelClass() { return `ohm-inspector__source ${this.isRetrievedSource && this.sourceVerified ? 'ohm-inspector__source--verified' : ''}`; }
    get sourceHandoffText() {
        return this.isRetrievedSource ? 'Review against this exact source, apply the edit manually and publish if required. Re-audit to retrieve and verify the new version.' : 'Review the draft against its recorded source. Apply and publish manually, then re-audit to retrieve the current Salesforce version.';
    }


    get _isBloat() {
        return this.node && this.node.signalType === 'INSTRUCTION_BLOAT';
    }

    // Split the raw instructions at the soft budget when this is a bloat finding
    // and the text actually exceeds the budget; otherwise it's all "normal".
    get instructionParts() {
        const text = (this.node && this.node.instructions) || '';
        const highlight =
            this.isWasteful &&
            this._isBloat &&
            text.length > SOFT_BUDGET_CHARS;
        if (!highlight) {
            return { normal: text, excess: '', highlighted: false };
        }
        return {
            normal: text.slice(0, SOFT_BUDGET_CHARS),
            excess: text.slice(SOFT_BUDGET_CHARS),
            highlighted: true
        };
    }

    get isHighlighted() {
        return this.instructionParts.highlighted;
    }
    get normalInstructions() {
        return this.instructionParts.normal;
    }
    get excessInstructions() {
        return this.instructionParts.excess;
    }
    get excessCaption() {
        const tc = this.node ? this.node.tokenCount : null;
        let excessTokens;
        if (tc !== null && tc !== undefined && tc > SOFT_BUDGET_TOKENS) {
            excessTokens = tc - SOFT_BUDGET_TOKENS;
        } else {
            // fall back to a char-based estimate (~4 chars/token)
            excessTokens = Math.round(this.excessInstructions.length / 4);
        }
        return `${formatNumber(excessTokens)} tokens over the modeled instruction budget`;
    }

    // ---- fix CTAs -----------------------------------------------------------
    get fixCtas() {
        if (!this.isWasteful) {
            return [];
        }
        const signal = this.node && this.node.signalType;
        const cta = CTA_BY_SIGNAL[signal];
        // default to Trim for the bloat fixtures / unknown-but-wasteful nodes
        const chosen = cta || CTA_BY_SIGNAL.INSTRUCTION_BLOAT;
        return [
            {
                ...chosen,
                cssClass:
                    this.activeFix === chosen.key
                        ? 'ohm-inspector__cta ohm-inspector__cta--active'
                        : 'ohm-inspector__cta'
            }
        ];
    }

    get showFixPanel() {
        return !!this.activeFix;
    }
    get recommendationText() {
        return this.finding ? this.finding.recommendationText : null;
    }
    get recommendedTarget() {
        return this.finding ? this.finding.recommendedTarget : null;
    }

    get canCreateTask() {
        return !!(this.finding && this.finding.id && this.taskState !== 'saving');
    }
    get isSavingTask() {
        return this.taskState === 'saving';
    }
    get taskDone() {
        return this.taskState === 'done';
    }
    get taskFailed() {
        return this.taskState === 'error';
    }

    // ---- interaction --------------------------------------------------------
    handleCtaClick(event) {
        const key = event.currentTarget.dataset.fix;
        this.activeFix = this.activeFix === key ? undefined : key;
    }
    handleAskSource() { this.dispatchEvent(new CustomEvent('asksource', { bubbles: true, composed: true })); }

    async handleCreateTask() {
        if (!this.canCreateTask) {
            return;
        }
        const f = this.finding;
        this.taskState = 'saving';
        this.taskError = undefined;
        try {
            const id = await createRemediationTask({ findingId: f.id, note: null });
            this.createdTaskId = id;
            this.taskState = 'done';
        } catch (e) {
            this.taskState = 'error';
            this.taskError =
                (e && e.body && e.body.message) ||
                (e && e.message) ||
                'Could not create the remediation task.';
        }
    }
}
