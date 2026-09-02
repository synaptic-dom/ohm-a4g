import { LightningElement, api } from 'lwc';

/**
 * F10 methodology defense. Renders EVERY constant/assumption straight from the
 * readout `assumptions` map — no hardcoded copy of any constant lives here, so
 * the panel can never drift from the Apex source of truth (W4).
 */
export default class OhmMethodologyPanel extends LightningElement {
    @api assumptions;
    @api telemetryBacked = false;
    @api calmMode = false;

    // Human labels are optional sugar; the VALUES always come from the DTO.
    _labels = {
        methodologyVersion: 'Methodology version',
        energyPerPromptWhLow: 'Energy per prompt — low (Wh)',
        energyPerPromptWhCentral: 'Energy per prompt — central (Wh)',
        energyPerPromptWhHigh: 'Energy per prompt — high (Wh)',
        gridIntensityGco2ePerWhLow: 'Grid intensity — low (gCO₂e/Wh)',
        gridIntensityGco2ePerWhCentral: 'Grid intensity — central (gCO₂e/Wh)',
        gridIntensityGco2ePerWhHigh: 'Grid intensity — high (gCO₂e/Wh)',
        waterMlPerWhLow: 'Water per Wh — low (mL)',
        waterMlPerWhCentral: 'Water per Wh — central (mL)',
        waterMlPerWhHigh: 'Water per Wh — high (mL)',
        referencePromptTokens: 'Reference prompt tokens',
        charsPerToken: 'Characters per token (≈ ceil(chars/4))',
        telemetryBacked: 'Telemetry-backed',
        co2eBandNote: 'CO₂e band-width note'
    };

    get entries() {
        const a = this.assumptions;
        if (!a || typeof a !== 'object') {
            return [];
        }
        return Object.keys(a).map((key) => {
            let value = a[key];
            if (value === null || value === undefined) {
                value = '—';
            } else if (typeof value === 'boolean') {
                value = value ? 'Yes' : 'No';
            } else {
                value = String(value);
            }
            return {
                key,
                label: this._labels[key] || key,
                value
            };
        });
    }

    get telemetryText() {
        return this.telemetryBacked
            ? 'These figures are telemetry-backed.'
            : 'These figures are modeled, not measured (telemetryBacked = false).';
    }
}
