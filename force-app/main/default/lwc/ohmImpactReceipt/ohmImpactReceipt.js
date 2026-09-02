import { LightningElement, api } from 'lwc';
import { formatNumber, formatRange, provenanceLabel } from 'c/ohmConstants';

/**
 * Text-first impact receipt. Renders a <dl> with one term per metric
 * (Energy / Water / CO₂e): each value shown as central + "range low–high"
 * TEXT first, with an optional decorative uncertainty bar in non-Calm.
 * The <dt> terms are IDENTICAL in Calm and non-Calm — only the bars are
 * stripped (the drift guard, AC-F9). Every figure carries an inline W7
 * provenance node.
 */
export default class OhmImpactReceipt extends LightningElement {
    /** [{ id, label, unit, low, central, high, dp }] */
    @api metrics = [];
    @api calmMode = false;
    @api volumeAssumption;
    @api confidence = 'Low';
    @api telemetryBacked = false;

    get showBars() {
        return !this.calmMode;
    }

    get provenance() {
        return provenanceLabel(
            this.volumeAssumption,
            this.confidence,
            this.telemetryBacked
        );
    }

    get displayRows() {
        const prov = this.provenance;
        const showBars = this.showBars;
        return (this.metrics || []).map((m) => {
            const dp = m.dp === undefined ? 0 : m.dp;
            const unit = m.unit || '';
            return {
                id: m.id || m.label,
                label: m.label,
                unit,
                low: m.low,
                central: m.central,
                high: m.high,
                centralText: `${formatNumber(m.central, dp)}${unit ? ' ' + unit : ''}`,
                rangeText: formatRange(m.low, m.high, dp),
                provenance: prov,
                showBar: showBars
            };
        });
    }
}
