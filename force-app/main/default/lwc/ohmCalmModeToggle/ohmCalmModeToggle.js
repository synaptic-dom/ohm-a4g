import { LightningElement, api } from 'lwc';

/**
 * Calm Mode toggle. State is conveyed as persistent visible text ("On"/"Off"),
 * never colour alone (AC-F9 / NFR-2). Emits `calmtoggle` with { enabled }.
 */
export default class OhmCalmModeToggle extends LightningElement {
    @api calmMode = false;

    get stateText() {
        return this.calmMode ? 'On' : 'Off';
    }

    handleChange(event) {
        const enabled = event.detail ? !!event.detail.checked : !this.calmMode;
        this.dispatchEvent(
            new CustomEvent('calmtoggle', { detail: { enabled } })
        );
    }
}
