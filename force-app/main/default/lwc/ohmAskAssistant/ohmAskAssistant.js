import { LightningElement, api, track } from 'lwc';
import getAssistantContext from '@salesforce/apex/OhmAuditController.getAssistantContext';
import askAssistant from '@salesforce/apex/OhmAuditController.askAssistant';
import { formatNumber } from 'c/ohmConstants';

/**
 * ohmAskAssistant — Wave 6, the per-process "Ask Ohm" assistant (SPEC-ohm-v2 §2.2).
 *
 * A grounded, HEADLESS chat: every answer comes from Apex → the Einstein Trust Layer
 * (no embedded messaging widget). On mount it pulls getAssistantContext(plannerId) for
 * the grounding summary + process-specific quick prompts; each question calls
 * askAssistant(plannerId, question). A rewrite request comes back as a draft block with a
 * before→after size readout. Selection/turns are owned here; the transcript is local.
 */
export default class OhmAskAssistant extends LightningElement {
    @api calmMode = false;
    @api processLabel;

    @track context;
    @track turns = [];
    @track draftInput = '';
    @track isLoadingContext = false;
    @track contextError;
    @track isThinking = false;
    @track sendError;

    _plannerId;
    _loadedFor;
    _seq = 0;

    @api
    get plannerId() {
        return this._plannerId;
    }
    set plannerId(value) {
        this._plannerId = value;
        if (value && value !== this._loadedFor) {
            this.loadContext();
        }
    }

    connectedCallback() {
        if (this._plannerId && this._plannerId !== this._loadedFor) {
            this.loadContext();
        }
    }

    async loadContext() {
        const planner = this._plannerId;
        if (!planner) {
            return;
        }
        this._loadedFor = planner;
        this.isLoadingContext = true;
        this.isThinking = false; // a stale in-flight answer must not keep the composer disabled
        this.contextError = undefined;
        this.turns = [];
        this.sendError = undefined;
        try {
            const ctx = await getAssistantContext({ plannerId: planner });
            // G10: the process may have changed while we awaited — drop this stale context.
            if (this._plannerId !== planner) {
                return;
            }
            this.context = ctx;
        } catch (e) {
            if (this._plannerId !== planner) {
                return;
            }
            this.contextError = this._msg(e) || 'Ask Ohm is unavailable right now.';
            this.context = undefined;
        } finally {
            if (this._plannerId === planner) {
                this.isLoadingContext = false;
            }
        }
    }

    /**
     * G4: re-ground the assistant after the process changes underneath it (e.g. a re-audit,
     * which keeps the same plannerId so the setter guard won't fire). Called imperatively by
     * the host; forces a fresh getAssistantContext and clears the prior transcript.
     */
    @api
    refresh() {
        this._loadedFor = undefined;
        this.loadContext();
    }

    // ---- host / presentation ------------------------------------------------
    get hostClass() {
        return this.calmMode ? 'ohm-ask ohm-ask--calm' : 'ohm-ask';
    }
    get available() {
        return !!(this.context && this.context.available);
    }
    get unavailable() {
        return !!(this.context && !this.context.available);
    }
    get unavailableReason() {
        return this.context ? this.context.unavailableReason : undefined;
    }
    get groundingSummary() {
        return this.context ? this.context.groundingSummary : '';
    }
    get modelLabel() {
        return this.context ? this.context.modelLabel : '';
    }
    get greeting() {
        return this.context ? this.context.greeting : '';
    }
    get groundedChips() {
        return (this.context && this.context.groundedOn) || [];
    }
    get quickPrompts() {
        return (this.context && this.context.quickPrompts) || [];
    }
    get hasTurns() {
        return this.turns.length > 0;
    }
    // The opening line shows only before the first exchange.
    get showGreeting() {
        return !!this.greeting && !this.hasTurns;
    }
    // Show the standing quick-prompt tray until the first answer carries its own follow-ups.
    get showQuickPrompts() {
        return this.available && this.quickPrompts.length > 0 && !this.hasTurns;
    }
    get inputDisabled() {
        return !this.available || this.isThinking;
    }
    get sendDisabled() {
        return this.inputDisabled || !this.draftInput || !this.draftInput.trim();
    }

    // ---- interaction --------------------------------------------------------
    handleInput(event) {
        this.draftInput = event.target.value;
    }

    handleKeydown(event) {
        // Enter sends, Shift+Enter is a newline; never submit mid-IME-composition (CJK candidates).
        if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
            event.preventDefault();
            this.send(this.draftInput);
        }
    }

    handleSendClick() {
        this.send(this.draftInput);
    }

    handleQuickPrompt(event) {
        const prompt = event.currentTarget.dataset.prompt;
        if (prompt) {
            this.send(prompt);
        }
    }

    async handleCopyDraft(event) {
        const text = event.currentTarget.dataset.text;
        if (!text) {
            return;
        }
        try {
            await navigator.clipboard.writeText(text);
            const btn = event.currentTarget;
            const original = btn.textContent;
            btn.textContent = 'Copied';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                btn.textContent = original;
            }, 1400);
        } catch (e) {
            // clipboard blocked (non-secure context / permissions) — tell the user how to copy
            const btn = event.currentTarget;
            const original = btn.textContent;
            btn.textContent = 'Press Ctrl/Cmd-C to copy';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                btn.textContent = original;
            }, 2200);
        }
    }

    async send(question) {
        const q = (question || '').trim();
        if (!q || !this.available || this.isThinking) {
            return;
        }
        this.sendError = undefined;
        this.draftInput = '';
        const askedFor = this._plannerId; // G10: bind the reply to the process it was asked for
        this._pushTurn({ role: 'user', text: q });
        this.isThinking = true;
        try {
            const reply = await askAssistant({ plannerId: askedFor, question: q });
            if (this._plannerId !== askedFor) {
                return; // process changed mid-flight — this answer belongs to a page that's gone
            }
            this._pushTurn(this._toOhmTurn(reply));
        } catch (e) {
            if (this._plannerId !== askedFor) {
                return;
            }
            this.sendError = this._msg(e) || 'Ohm could not answer just now.';
            this._pushTurn({
                role: 'ohm',
                text: this.sendError,
                isError: true
            });
        } finally {
            if (this._plannerId === askedFor) {
                this.isThinking = false;
                this._scrollToEnd();
                this._refocusComposer(); // G11: don't strand keyboard focus after each turn
            }
        }
    }

    // ---- turn shaping -------------------------------------------------------
    _pushTurn(turn) {
        this._seq += 1;
        this.turns = [
            ...this.turns,
            {
                key: `t${this._seq}`,
                isUser: turn.role === 'user',
                isOhm: turn.role === 'ohm',
                bubbleClass:
                    turn.role === 'user'
                        ? 'ohm-ask__bubble ohm-ask__bubble--user'
                        : turn.isError
                        ? 'ohm-ask__bubble ohm-ask__bubble--ohm ohm-ask__bubble--error'
                        : 'ohm-ask__bubble ohm-ask__bubble--ohm',
                ...turn
            }
        ];
        this._scrollToEnd();
    }

    _toOhmTurn(reply) {
        const t = { role: 'ohm', text: reply.answer, modelLabel: reply.modelLabel };
        if (reply.isDraft && reply.draftText) {
            t.isDraft = true;
            t.draftText = reply.draftText;
            t.beforeChars = reply.beforeChars;
            t.afterChars = reply.afterChars;
            t.charDeltaText = `${formatNumber(reply.beforeChars)} → ${formatNumber(
                reply.afterChars
            )} chars`;
            t.tokenDeltaText = `${formatNumber(reply.beforeTokens)} → ${formatNumber(
                reply.afterTokens
            )} tokens`;
            // G5: sign the delta explicitly — a rewrite that came back LONGER must read "+N%",
            // never "−-N%", and the badge tone flips to warn.
            const delta = reply.beforeChars - reply.afterChars;
            const pct =
                reply.beforeChars > 0
                    ? Math.round((Math.abs(delta) / reply.beforeChars) * 100)
                    : 0;
            t.isExpansion = delta < 0;
            t.reductionText = `${delta < 0 ? '+' : '−'}${pct}%`;
            t.deltaClass = delta < 0
                ? 'ohm-ask__delta-pct ohm-ask__delta-pct--warn'
                : 'ohm-ask__delta-pct';
        }
        if (reply.followUps && reply.followUps.length) {
            t.followUps = reply.followUps;
        }
        return t;
    }

    _refocusComposer() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            const input = this.template.querySelector('[data-id="input"]');
            if (input && !input.disabled) {
                input.focus();
            }
        });
    }

    _scrollToEnd() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            const log = this.template.querySelector('[data-id="transcript"]');
            if (log) {
                log.scrollTop = log.scrollHeight;
            }
        });
    }

    _msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || null;
    }
}
