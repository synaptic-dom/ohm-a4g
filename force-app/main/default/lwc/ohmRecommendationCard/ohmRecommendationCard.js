import { LightningElement, api } from 'lwc';
import {
    SIGNAL_LABELS,
    formatNumber,
    provenanceLabel
} from 'c/ohmConstants';

/**
 * One recommendation card per finding (S4).
 * - displayRecommendation = agentNarrative ?? recommendationText (hybrid seam).
 * - savings shown as a band ("saves low–central–high Wh/yr").
 * - severity + signal rendered as TEXT (never colour alone).
 * - W7 provenance line under every savings figure.
 * Emits `createtask` { findingId }; the container performs the Apex call and
 * feeds back the finding with a remediationTaskId, flipping this card to
 * "Task created".
 */
export default class OhmRecommendationCard extends LightningElement {
    @api finding;
    @api calmMode = false;
    @api volumeAssumption;
    @api telemetryBacked = false;
    @api errorMessage;

    get displayRecommendation() {
        const f = this.finding || {};
        return f.agentNarrative != null && f.agentNarrative !== ''
            ? f.agentNarrative
            : f.recommendationText;
    }

    get signalLabel() {
        const f = this.finding || {};
        return SIGNAL_LABELS[f.signal] || f.signal || 'Unknown signal';
    }

    get severityText() {
        const f = this.finding || {};
        return `Severity: ${f.severity || 'Unknown'}`;
    }

    get effortText() {
        const f = this.finding || {};
        return `Effort: ${f.effort || 'Unknown'}`;
    }

    get savingsText() {
        const f = this.finding || {};
        return `saves ${formatNumber(f.estimatedSavingsLow)}–${formatNumber(
            f.estimatedSavingsCentral
        )}–${formatNumber(f.estimatedSavingsHigh)} Wh/yr`;
    }

    get provenance() {
        const f = this.finding || {};
        return provenanceLabel(
            this.volumeAssumption,
            f.confidence,
            this.telemetryBacked
        );
    }

    get generatedByText() {
        const f = this.finding || {};
        return f.generatedBy === 'Agentforce' ? 'Agent-phrased' : 'Deterministic';
    }

    get created() {
        const f = this.finding || {};
        return !!f.remediationTaskId;
    }

    handleCreateTask() {
        const f = this.finding || {};
        this.dispatchEvent(
            new CustomEvent('createtask', { detail: { findingId: f.id } })
        );
    }
}
