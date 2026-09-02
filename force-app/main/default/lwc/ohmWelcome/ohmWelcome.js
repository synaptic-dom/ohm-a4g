import { LightningElement, api } from 'lwc';

/**
 * S1 Welcome screen. Single "Start the audit" CTA -> `startaudit`.
 * One <h1 data-focus-heading>. Calm Mode drops the decorative hero but keeps
 * the heading + copy structure (AC-F1 / AC-F9).
 */
export default class OhmWelcome extends LightningElement {
    @api calmMode = false;

    get showHero() {
        return !this.calmMode;
    }

    @api
    focusHeading() {
        const h = this.template.querySelector('[data-focus-heading]');
        if (h) {
            h.focus();
        }
    }

    handleStart() {
        this.dispatchEvent(new CustomEvent('startaudit'));
    }
}
