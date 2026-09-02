import { LightningElement, api, track } from 'lwc';

const ANNOUNCE_DEBOUNCE_MS = 400;

/**
 * W7 volume scrubber — a REAL accessible slider.
 * Non-Calm: role="slider" with arrow-key stepping, aria-valuemin/max/now and a
 * live aria-valuetext ("150 sessions per day"); a separate debounced
 * aria-live="polite" region announces the recalculated scenario.
 * Calm: a plain numeric input (no slider).
 * Emits `volumechange` with { sessionsPerPeriod } on every change.
 */
export default class OhmVolumeScrubber extends LightningElement {
    @api min = 10;
    @api max = 500;
    @api step = 10;
    @api calmMode = false;

    _value = 50;
    @track announceText = '';
    _announceHandle;

    @api
    get value() {
        return this._value;
    }
    set value(v) {
        const n = Number(v);
        if (isFinite(n)) {
            this._value = this._clamp(n);
        }
    }

    _clamp(n) {
        return Math.max(Number(this.min), Math.min(Number(this.max), n));
    }

    get valueText() {
        return `${this._value} sessions per day`;
    }

    get minNum() {
        return Number(this.min);
    }
    get maxNum() {
        return Number(this.max);
    }

    handleKeydown(event) {
        const key = event.key;
        let next = this._value;
        if (key === 'ArrowRight' || key === 'ArrowUp') {
            next = this._clamp(this._value + Number(this.step));
        } else if (key === 'ArrowLeft' || key === 'ArrowDown') {
            next = this._clamp(this._value - Number(this.step));
        } else if (key === 'Home') {
            next = this.minNum;
        } else if (key === 'End') {
            next = this.maxNum;
        } else {
            return;
        }
        event.preventDefault();
        this._commit(next);
    }

    handleNumberChange(event) {
        const raw = event.detail && event.detail.value !== undefined
            ? event.detail.value
            : event.target.value;
        const next = this._clamp(Number(raw));
        this._commit(next);
    }

    _commit(next) {
        if (next === this._value) {
            return;
        }
        this._value = next;
        // Live scaling: fire immediately so the readout recomputes bands.
        this.dispatchEvent(
            new CustomEvent('volumechange', {
                detail: { sessionsPerPeriod: next }
            })
        );
        // Debounced polite announcement of the recalculated scenario.
        this._scheduleAnnounce();
    }

    _scheduleAnnounce() {
        if (this._announceHandle) {
            clearTimeout(this._announceHandle);
        }
        this._announceHandle = setTimeout(() => {
            this.announceText = `Now modeling ${this._value} sessions per day.`;
            this._announceHandle = undefined;
        }, ANNOUNCE_DEBOUNCE_MS);
    }

    disconnectedCallback() {
        if (this._announceHandle) {
            clearTimeout(this._announceHandle);
        }
    }
}
