import { LightningElement, api, track } from 'lwc';
import { formatNumber, provenanceLabel } from 'c/ohmConstants';

/**
 * S3 Impact readout (composition). Composes the efficiency rating, the org-wide
 * impact receipt, per-artifact rows, the methodology panel and the volume
 * scrubber. On `volumechange` it recomputes every band CLIENT-SIDE by linear
 * scaling (footprint ∝ annualCalls ∝ sessionsPerPeriod, C6) — NO Apex round-trip.
 * One <h2 data-focus-heading>. "See recommendations" -> `viewrecommendations`.
 */
export default class OhmImpactReadout extends LightningElement {
    @api readout;
    @api calmMode = false;

    @track _currentSessions = null;

    get baselineSessions() {
        const v = this.readout && this.readout.volumeAssumption;
        return v && v.sessionsPerPeriod ? Number(v.sessionsPerPeriod) : 50;
    }

    get currentSessions() {
        return this._currentSessions === null
            ? this.baselineSessions
            : this._currentSessions;
    }

    get scale() {
        const base = this.baselineSessions;
        return base ? this.currentSessions / base : 1;
    }

    get turnsPerSession() {
        const v = this.readout && this.readout.volumeAssumption;
        return v && v.turnsPerSession ? Number(v.turnsPerSession) : 6;
    }

    // Volume assumption reflecting the CURRENT scrubber position (drives provenance).
    get scaledVolume() {
        const base = (this.readout && this.readout.volumeAssumption) || {};
        return Object.assign({}, base, {
            sessionsPerPeriod: this.currentSessions,
            scenarioLabel: `${this.currentSessions} sessions/day × ${this.turnsPerSession} turns`
        });
    }

    get confidence() {
        return 'Low';
    }

    get telemetryBacked() {
        return !!(this.readout && this.readout.telemetryBacked);
    }

    _scaled(value) {
        if (value === null || value === undefined) {
            return value;
        }
        return Number(value) * this.scale;
    }

    // Org-wide metrics for the impact receipt.
    get orgMetrics() {
        const r = this.readout || {};
        return [
            {
                id: 'energy',
                label: 'Energy',
                unit: 'Wh/yr',
                low: this._scaled(r.orgEnergyWhLow),
                central: this._scaled(r.orgEnergyWhCentral),
                high: this._scaled(r.orgEnergyWhHigh),
                dp: 0
            },
            {
                id: 'water',
                label: 'Water',
                unit: 'mL/yr',
                low: this._scaled(r.orgWaterMlLow),
                central: this._scaled(r.orgWaterMlCentral),
                high: this._scaled(r.orgWaterMlHigh),
                dp: 0
            },
            {
                id: 'co2e',
                label: 'CO₂e',
                unit: 'g/yr',
                low: this._scaled(r.orgCo2eGLow),
                central: this._scaled(r.orgCo2eGCentral),
                high: this._scaled(r.orgCo2eGHigh),
                dp: 0
            }
        ];
    }

    // Per-artifact rows: label + scaled energy central + scaled savings + provenance.
    get artifactRows() {
        const findings = (this.readout && this.readout.findings) || [];
        const prov = provenanceLabel(
            this.scaledVolume,
            this.confidence,
            this.telemetryBacked
        );
        return findings.map((f) => {
            const art = f.targetArtifact || {};
            return {
                id: f.id,
                label: art.label || art.apiName || 'Artifact',
                energyText: `${formatNumber(this._scaled(f.energyWhCentral))} Wh/yr`,
                savingsText: `saves ${formatNumber(
                    this._scaled(f.estimatedSavingsCentral)
                )} Wh/yr`,
                provenance: prov
            };
        });
    }

    get grade() {
        return this.readout && this.readout.efficiencyGrade;
    }
    get score() {
        return this.readout && this.readout.efficiencyScore;
    }
    get assumptions() {
        return this.readout && this.readout.assumptions;
    }
    get hasArtifacts() {
        return this.artifactRows.length > 0;
    }

    handleVolumeChange(event) {
        const s = event.detail && event.detail.sessionsPerPeriod;
        if (s !== undefined && s !== null) {
            this._currentSessions = Number(s);
        }
    }

    handleViewRecommendations() {
        this.dispatchEvent(new CustomEvent('viewrecommendations'));
    }

    @api
    focusHeading() {
        const h = this.template.querySelector('[data-focus-heading]');
        if (h) {
            h.focus();
        }
    }
}
