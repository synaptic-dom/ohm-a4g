import { LightningElement, api } from 'lwc';
import { formatNumber } from 'c/ohmConstants';

/**
 * Decorative low–central–high band visual (non-Calm only). Exposed to AT as a
 * single role="img" node whose aria-label REPEATS the numbers, so the picture
 * never carries information the numbers don't (AC-F4 / NFR-2).
 */
export default class OhmUncertaintyBar extends LightningElement {
    @api label = 'Range';
    @api unit = '';
    @api low;
    @api central;
    @api high;

    get ariaLabel() {
        const u = this.unit ? ` ${this.unit}` : '';
        return `${this.label}: low ${formatNumber(this.low)}${u}, central ${formatNumber(
            this.central
        )}${u}, high ${formatNumber(this.high)}${u}.`;
    }

    // Central marker position as a percentage of the low–high span.
    get centralPercent() {
        const lo = Number(this.low);
        const hi = Number(this.high);
        const c = Number(this.central);
        if (!isFinite(lo) || !isFinite(hi) || hi <= lo) {
            return 50;
        }
        const pct = ((c - lo) / (hi - lo)) * 100;
        return Math.max(0, Math.min(100, pct));
    }

    get centralStyle() {
        return `left:${this.centralPercent}%;`;
    }
}
