import { LightningElement, api } from 'lwc';
import { formatNumber } from 'c/ohmConstants';
import { formatEnergy, formatMass, formatWater } from 'c/ohmDisplay';

/**
 * Modeled footprint for one bundle or a fleet, rescaled to a chosen request volume.
 *
 * Every figure derives from the saved review's Impact snapshot: per-request energy is
 * the modeled annual energy divided by the requests/year the review assumed, and the
 * selected volume multiplies it back out. CO2e, water and savings scale by the same
 * ratio, so no environmental constant is duplicated on the client. Nothing here is a
 * measurement; the badge and the Assumptions list say so on every render.
 */
const VOLUMES = [300, 1000, 10000, 100000];
const DAYS_PER_YEAR = 365;
const FIELDS = [
    'energyWhLow', 'energyWhCentral', 'energyWhHigh',
    'savingsWhLow', 'savingsWhCentral', 'savingsWhHigh',
    'co2eGLow', 'co2eGCentral', 'co2eGHigh',
    'waterMlLow', 'waterMlCentral', 'waterMlHigh'
];

function factor(value) {
    const n = Number(value);
    if (Number.isNaN(n)) return '—';
    return Number.isInteger(Math.round(n * 100 * 1e6) / 1e6) ? n.toFixed(2) : String(n);
}
function band(b) {
    return b ? ` (band ${factor(b.low)} to ${factor(b.high)})` : '';
}
function pct(part, whole) {
    if (!whole) return '0%';
    return `${Number(((part / whole) * 100).toFixed(1))}%`;
}
function wholePct(part, whole) {
    if (!whole) return '0%';
    return `${Math.round((part / whole) * 100)}%`;
}

export default class OhmFootprintStrip extends LightningElement {
    @api heading = 'Footprint';
    /** 'bundle' | 'fleet' — changes the coverage line and the empty-state wording. */
    @api scope = 'bundle';
    /** Rows carrying the energy, savings, CO2e and water bands plus annualCalls (requests/year modeled). */
    @api footprints = [];
    /** Disclosed constants from Apex (OhmAuditImpactService.factors). */
    @api factors;
    /** The review's own assumption summary sentence. */
    @api assumptionSummary;

    volume = VOLUMES[0];

    get rows() {
        const list = Array.isArray(this.footprints) ? this.footprints : [];
        return list.filter((r) => r && Number(r.annualCalls) > 0 && r.energyWhCentral !== null && r.energyWhCentral !== undefined);
    }
    get hasData() { return this.rows.length > 0; }
    get isFleet() { return this.scope === 'fleet'; }

    /** Sum of every band scaled to the selected volume, plus the per-request central figure. */
    get totals() {
        const t = { perRequestWh: 0 };
        FIELDS.forEach((f) => { t[f] = 0; });
        this.rows.forEach((row) => {
            const calls = Number(row.annualCalls);
            const k = (this.volume * DAYS_PER_YEAR) / calls;
            FIELDS.forEach((f) => { t[f] += Number(row[f] || 0) * k; });
            t.perRequestWh += Number(row.energyWhCentral) / calls;
        });
        return t;
    }

    // ---- what you avoid (leads), what you burn (context) -----------------------
    get hasSavings() { return this.totals.savingsWhCentral > 0; }
    /** CO2e and water scale with energy by a fixed factor, so the avoided share equals the energy share. */
    get savingsShare() {
        const t = this.totals;
        return t.energyWhCentral > 0 ? t.savingsWhCentral / t.energyWhCentral : 0;
    }
    get kickerText() {
        if (!this.hasSavings) return this.isFleet ? 'No changes are recommended yet. Footprint today:' : 'No changes are recommended for this bundle. Footprint today:';
        return this.isFleet ? 'Apply the recommended changes and avoid' : 'Apply the recommended change and avoid';
    }
    get leadFigureText() { return formatEnergy(this.hasSavings ? this.totals.savingsWhCentral : this.totals.energyWhCentral); }
    get basisText() { return `of energy a year at ${formatNumber(this.volume)} requests a day`; }
    get footprintContextText() {
        const t = this.totals;
        const range = `range ${formatEnergy(t.energyWhLow)} to ${formatEnergy(t.energyWhHigh)}`;
        if (!this.hasSavings) return `Modeled footprint ${formatEnergy(t.energyWhCentral)} a year (${range}).`;
        return `${wholePct(t.savingsWhCentral, t.energyWhCentral)} of a modeled ${formatEnergy(t.energyWhCentral)} footprint a year (${range}).`;
    }
    get co2eSavedText() { return formatMass(this.totals.co2eGCentral * this.savingsShare); }
    get waterSavedText() { return formatWater(this.totals.waterMlCentral * this.savingsShare); }
    get perRequestSavedText() { return formatEnergy(this.totals.perRequestWh * this.savingsShare); }
    get energyCentralText() { return formatEnergy(this.totals.energyWhCentral); }
    get perRequestText() { return formatEnergy(this.totals.perRequestWh); }
    get co2eText() { return formatMass(this.totals.co2eGCentral); }
    get waterText() { return formatWater(this.totals.waterMlCentral); }
    get coverageText() {
        const n = this.rows.length;
        return `Across ${n} reviewed ${n === 1 ? 'bundle' : 'bundles'}. Bundles without a completed review are not counted.`;
    }
    get emptyText() {
        return this.isFleet
            ? 'No footprint yet. Run an audit on a bundle to see what its recommended changes would avoid.'
            : 'No footprint yet. Run an audit to see what this bundle’s recommended changes would avoid.';
    }

    // ---- band meter: widths relative to the high estimate --------------------
    get centralStyle() { return `width: ${pct(this.totals.energyWhCentral, this.totals.energyWhHigh)}`; }
    get savingsStyle() { return `width: ${pct(this.totals.savingsWhCentral, this.totals.energyWhHigh)}`; }
    get meterLabel() {
        const t = this.totals;
        return `Modeled footprint ${formatEnergy(t.energyWhCentral)} a year against a ${formatEnergy(t.energyWhHigh)} high estimate; ${formatEnergy(t.savingsWhCentral)} avoided by applying the recommended changes.`;
    }

    // ---- volume selector ------------------------------------------------------
    get volumeOptions() {
        return VOLUMES.map((v) => ({
            value: v,
            label: v >= 1000 ? `${v / 1000}k` : String(v),
            pressed: v === this.volume,
            className: `strip__volume-button${v === this.volume ? ' strip__volume-button--on' : ''}`
        }));
    }
    handleVolume(event) {
        const next = Number(event.currentTarget.dataset.volume);
        if (VOLUMES.includes(next)) this.volume = next;
    }

    // ---- disclosed assumptions ------------------------------------------------
    get assumptions() {
        const f = this.factors || {};
        const items = [];
        if (f.energyPerPromptWh) {
            items.push(`Energy per ${f.referencePromptTokens || 500}-token prompt: ${factor(f.energyPerPromptWh.central)} Wh${band(f.energyPerPromptWh)}, Epoch AI 2025 median for GPT-4o-class models, scaled by approximate source tokens.`);
        }
        if (f.gridIntensityGco2ePerWh) {
            items.push(`Grid intensity: ${factor(f.gridIntensityGco2ePerWh.central)} g CO2e per Wh${band(f.gridIntensityGco2ePerWh)}.`);
        }
        if (f.waterMlPerWh) {
            items.push(`Water: ${factor(f.waterMlPerWh.central)} mL per Wh${band(f.waterMlPerWh)}.`);
        }
        items.push(`Volume: ${formatNumber(this.volume)} requests a day for ${DAYS_PER_YEAR} days. Change the volume above to see the figures at a different load; the review itself modeled ${formatNumber(this.rows[0] ? this.rows[0].annualCalls : 0)} requests a year.`);
        items.push('Avoided figures assume the recommended changes are applied and behave as before; CO2e and water scale with energy by the factors above.');
        if (this.assumptionSummary) items.push(this.assumptionSummary);
        items.push(`Confidence is Low${f.methodologyVersion ? `, methodology ${f.methodologyVersion}` : ''}. No energy telemetry exists for these requests, so every figure here is modeled, not measured.`);
        return items.map((text, index) => ({ key: `a${index}`, text }));
    }
}
