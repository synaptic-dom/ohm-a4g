import { createElement } from 'lwc';
import OhmFootprintStrip from 'c/ohmFootprintStrip';
import { formatEnergy, formatMass, formatWater } from 'c/ohmDisplay';

// One bundle at the model's own scenario: 300 requests/day × 365 = 109,500 requests/year.
const SUPPORT = {
    label: 'Customer Support',
    annualCalls: 109500,
    energyWhLow: 33585.84, energyWhCentral: 37784.07, energyWhHigh: 41982.3,
    savingsWhLow: 17082, savingsWhCentral: 19217.25, savingsWhHigh: 21352.5,
    co2eGLow: 4198.23, co2eGCentral: 11335.221, co2eGHigh: 19941.5925,
    waterMlLow: 26868.672, waterMlCentral: 40806.7956, waterMlHigh: 58775.22
};
const DESK = {
    label: 'Efficient Schedule Desk',
    annualCalls: 109500,
    energyWhLow: 20445.84, energyWhCentral: 23001.57, energyWhHigh: 25557.3,
    savingsWhLow: 1944.72, savingsWhCentral: 2187.81, savingsWhHigh: 2430.9,
    co2eGLow: 2555.73, co2eGCentral: 6900.471, co2eGHigh: 12139.7175,
    waterMlLow: 16356.672, waterMlCentral: 24841.6956, waterMlHigh: 35780.22
};
const FACTORS = {
    energyPerPromptWh: { low: 0.24, central: 0.27, high: 0.3 },
    gridIntensityGco2ePerWh: { low: 0.125, central: 0.3, high: 0.475 },
    waterMlPerWh: { low: 0.8, central: 1.08, high: 1.4 },
    referencePromptTokens: 500,
    charsPerToken: 4,
    methodologyVersion: '1.0'
};

function create(props = {}) {
    const el = createElement('c-ohm-footprint-strip', { is: OhmFootprintStrip });
    Object.assign(el, props);
    document.body.appendChild(el);
    return el;
}
const text = (el, id) => el.shadowRoot.querySelector(`[data-id="${id}"]`).textContent;
afterEach(() => { document.body.replaceChildren(); });

describe('display helpers', () => {
    it('chooses units that keep the figures readable', () => {
        expect(formatEnergy(37784.07)).toBe('37.8 kWh');
        expect(formatEnergy(345)).toBe('345 Wh');
        expect(formatEnergy(0.3451)).toBe('0.35 Wh');
        expect(formatEnergy(1259469)).toBe('1.26 MWh');
        expect(formatEnergy(null)).toBe('—');
        expect(formatMass(11335.221)).toBe('11.3 kg');
        expect(formatMass(656.3)).toBe('656 g');
        expect(formatWater(40806.8)).toBe('40.8 L');
        expect(formatWater(820)).toBe('820 mL');
    });
});

describe('c-ohm-footprint-strip', () => {
    it('leads with what the recommended change avoids for one bundle at 300 requests a day', async () => {
        const el = create({ footprints: [SUPPORT], scope: 'bundle', factors: FACTORS, assumptionSummary: 'summary text' });
        await Promise.resolve();
        expect(text(el, 'kicker')).toBe('Apply the recommended change and avoid');
        expect(text(el, 'savings-central')).toBe('19.2 kWh');
        expect(text(el, 'basis')).toContain('300 requests a day');
        expect(text(el, 'footprint-context')).toContain('51% of a modeled 37.8 kWh footprint');
        expect(text(el, 'footprint-context')).toContain('range 33.6 kWh to 42.0 kWh');
        // avoided CO2e and water follow the energy share (19,217 / 37,784 = 50.9%)
        expect(text(el, 'co2e-saved')).toContain('5.77 kg');
        expect(text(el, 'water-saved')).toContain('20.8 L');
        expect(text(el, 'per-request-saved')).toContain('0.18 Wh');
        expect(text(el, 'per-request')).toBe('0.35 Wh');
        expect(text(el, 'energy-central')).toContain('37.8 kWh');
        expect(text(el, 'co2e')).toBe('11.3 kg');
        expect(text(el, 'water')).toBe('40.8 L');
        expect(text(el, 'badge')).toBe('Modeled, not measured');
        const pressed = el.shadowRoot.querySelector('[data-id="volume"][aria-pressed="true"]');
        expect(pressed.dataset.volume).toBe('300');
        await expect(el).toBeAccessible();
    });

    it('rescales every figure from the per-request value when the volume changes', async () => {
        const el = create({ footprints: [SUPPORT], scope: 'bundle', factors: FACTORS });
        await Promise.resolve();
        el.shadowRoot.querySelector('[data-id="volume"][data-volume="1000"]').click();
        await Promise.resolve();
        // 19,217 Wh × (1,000 × 365 / 109,500) = 64,058 Wh avoided; footprint 125,947 Wh
        expect(text(el, 'savings-central')).toBe('64.1 kWh');
        expect(text(el, 'energy-central')).toContain('125.9 kWh');
        expect(text(el, 'co2e-saved')).toContain('19.2 kg');
        expect(text(el, 'per-request-saved')).toContain('0.18 Wh');
        expect(text(el, 'basis')).toContain('1,000 requests a day');
        el.shadowRoot.querySelector('[data-id="volume"][data-volume="100000"]').click();
        await Promise.resolve();
        expect(text(el, 'savings-central')).toBe('6.41 MWh');
        expect(text(el, 'energy-central')).toContain('12.6 MWh');
    });

    it('sums a fleet, names how many bundles the figure covers, and speaks in the plural', async () => {
        const unreviewed = { label: 'Draft bundle', annualCalls: null, energyWhCentral: null };
        const el = create({ footprints: [SUPPORT, DESK, unreviewed], scope: 'fleet', factors: FACTORS });
        await Promise.resolve();
        // avoided 19,217 + 2,188 = 21,405 Wh of a 60,786 Wh footprint (35%)
        expect(text(el, 'kicker')).toBe('Apply the recommended changes and avoid');
        expect(text(el, 'savings-central')).toBe('21.4 kWh');
        expect(text(el, 'footprint-context')).toContain('35% of a modeled 60.8 kWh footprint');
        expect(text(el, 'coverage')).toContain('2 reviewed bundles');
        expect(text(el, 'per-request')).toBe('0.56 Wh');
    });

    it('draws the band meter from the high estimate and marks the avoided share', async () => {
        const el = create({ footprints: [SUPPORT], scope: 'bundle', factors: FACTORS });
        await Promise.resolve();
        const central = el.shadowRoot.querySelector('[data-id="meter-central"]');
        const savings = el.shadowRoot.querySelector('[data-id="meter-savings"]');
        expect(central.style.width).toBe('90%');   // 37,784 / 41,982
        expect(savings.style.width).toBe('45.8%'); // 19,217 / 41,982
    });

    it('falls back to the footprint itself when nothing is recommended', async () => {
        const clean = { ...DESK, savingsWhLow: 0, savingsWhCentral: 0, savingsWhHigh: 0 };
        const el = create({ footprints: [clean], scope: 'bundle', factors: FACTORS });
        await Promise.resolve();
        expect(text(el, 'kicker')).toContain('No changes are recommended');
        expect(text(el, 'savings-central')).toBe('23.0 kWh');
        expect(text(el, 'footprint-context')).toContain('Modeled footprint 23.0 kWh a year');
        expect(text(el, 'co2e-saved')).toContain('0 g');
    });

    it('lists each assumption with its band and refuses to invent a figure without data', async () => {
        const el = create({ footprints: [SUPPORT], scope: 'bundle', factors: FACTORS, assumptionSummary: 'Chars / 4 approximate tokens.' });
        await Promise.resolve();
        const items = [...el.shadowRoot.querySelectorAll('[data-id="assumption"]')].map((li) => li.textContent);
        expect(items.some((t) => t.includes('0.27 Wh') && t.includes('0.24') && t.includes('500-token'))).toBe(true);
        expect(items.some((t) => t.includes('0.30 g CO2e per Wh'))).toBe(true);
        expect(items.some((t) => t.includes('1.08 mL per Wh'))).toBe(true);
        expect(items.some((t) => t.includes('Avoided figures assume the recommended changes are applied'))).toBe(true);
        expect(items.some((t) => t.includes('Chars / 4 approximate tokens.'))).toBe(true);
        expect(items.some((t) => t.includes('No energy telemetry'))).toBe(true);

        const empty = create({ footprints: [{ label: 'New bundle', energyWhCentral: null }], scope: 'bundle' });
        await Promise.resolve();
        expect(empty.shadowRoot.querySelector('[data-id="savings-central"]')).toBeNull();
        expect(text(empty, 'empty')).toContain('Run an audit');
        await expect(empty).toBeAccessible();
    });
});
