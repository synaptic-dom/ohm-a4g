import { LightningElement, api } from 'lwc';

/**
 * Calm Mode toggle. A custom accessible switch (role="switch" + aria-checked) so
 * the "on" colour is the instrument's own muted cool/ink — never the saturated
 * SLDS toggle blue (that base-component colour is not reachable via styling hooks
 * in the Lightning runtime). State is conveyed as persistent visible text
 * ("On"/"Off"), never colour alone (AC-F9 / NFR-2). Emits `calmtoggle` with
 * { enabled }; the @api calmMode contract is unchanged.
 */
export default class OhmCalmModeToggle extends LightningElement {
    @api calmMode = false;

    get stateText() {
        return this.calmMode ? 'On' : 'Off';
    }

    // Loud = a raised dark card that belongs to the panel; Calm = flush hairline.
    get containerClass() {
        return this.calmMode
            ? 'ohm-calm-toggle ohm-calm-toggle--calm'
            : 'ohm-calm-toggle ohm-calm-toggle--loud';
    }

    handleToggle() {
        const enabled = !this.calmMode;
        this.dispatchEvent(
            new CustomEvent('calmtoggle', { detail: { enabled } })
        );
    }
}
