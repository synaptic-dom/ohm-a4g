/** Display labels only: identifiers used for routing and evidence remain unchanged. */
export function bundleLabel(value) {
    const label = String(value || 'Untitled bundle');
    if (label.includes(' ') && !label.includes('_')) return label;
    return label.replace(/_v\d+$/i, '').replace(/_/g, ' ').replace(/([a-z\d])([A-Z])/g, '$1 $2').trim();
}

// ---- Footprint units ------------------------------------------------------
// Fixed decimals per unit so bands read consistently ("33.6 to 42.0 kWh").
function fixed(value, dp) {
    return Number(value).toLocaleString('en-US', { minimumFractionDigits: dp, maximumFractionDigits: dp });
}
function scaled(value, units) {
    if (value === null || value === undefined || Number.isNaN(Number(value))) {
        return '—';
    }
    const n = Number(value);
    const unit = units.find((u) => Math.abs(n) >= u.min) || units[units.length - 1];
    const v = n / unit.divisor;
    const dp = unit.dp !== undefined ? unit.dp : Math.abs(v) < 10 ? 2 : 1;
    return `${fixed(v, dp)} ${unit.suffix}`;
}
/** Watt-hours rendered as Wh, kWh or MWh. */
export function formatEnergy(wh) {
    return scaled(wh, [
        { min: 1e6, divisor: 1e6, suffix: 'MWh' },
        { min: 1e3, divisor: 1e3, suffix: 'kWh' },
        { min: 10, divisor: 1, suffix: 'Wh', dp: 0 },
        { min: 0, divisor: 1, suffix: 'Wh', dp: 2 }
    ]);
}
/** Grams rendered as g or kg (the caller adds "CO2e"). */
export function formatMass(grams) {
    return scaled(grams, [
        { min: 1e3, divisor: 1e3, suffix: 'kg' },
        { min: 0, divisor: 1, suffix: 'g', dp: 0 }
    ]);
}
/** Millilitres rendered as mL or L. */
export function formatWater(ml) {
    return scaled(ml, [
        { min: 1e3, divisor: 1e3, suffix: 'L' },
        { min: 0, divisor: 1, suffix: 'mL', dp: 0 }
    ]);
}
