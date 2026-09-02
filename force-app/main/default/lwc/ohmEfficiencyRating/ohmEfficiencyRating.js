import { LightningElement, api } from 'lwc';
import { GRADE_WORDS } from 'c/ohmConstants';

/**
 * Efficiency rating badge: letter + plain word + score, ALL as text.
 * Colour is redundant only — the grade is never conveyed by colour alone
 * (AC-F4 / NFR-2 color+text pairing).
 */
export default class OhmEfficiencyRating extends LightningElement {
    @api grade;
    @api score;
    @api calmMode = false;

    get letter() {
        return this.grade || '—';
    }

    get word() {
        return GRADE_WORDS[this.grade] || 'Not yet rated';
    }

    get scoreText() {
        return this.score === null || this.score === undefined
            ? 'Score unavailable'
            : `Efficiency score ${this.score} of 100`;
    }

    // A theme class for colour, but colour is decoration layered on top of text.
    get badgeClass() {
        const key = this.grade ? this.grade.toLowerCase() : 'none';
        return `ohm-rating__badge ohm-rating__badge--${key}`;
    }
}
