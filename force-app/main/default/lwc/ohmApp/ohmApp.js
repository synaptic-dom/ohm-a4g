import { LightningElement, track } from 'lwc';
import getCalmModePreference from '@salesforce/apex/OhmAuditController.getCalmModePreference';
import setCalmModePreference from '@salesforce/apex/OhmAuditController.setCalmModePreference';

/**
 * ohmApp — the v2 root: a dark "Instrument" workbench SHELL.
 * Owns the tab strip (FLEET | FINDINGS | RECOMMENDATIONS | TRENDS), the
 * breadcrumb/context line, and the Calm Mode context (loaded before first paint
 * and passed down to every child). FLEET renders <c-ohm-fleet-table>; the other
 * three tabs render an on-brand "coming in this build" placeholder for now.
 *
 * Wave 3: an `openprocess` event from a fleet row swaps the FLEET body from the
 * fleet table to <c-ohm-process-page> (the drill-down) and sets the breadcrumb
 * "Fleet › <label>"; a `backtofleet` event (or clicking any tab) returns home.
 */
const TABS = [
    { id: 'FLEET', label: 'Fleet' },
    { id: 'FINDINGS', label: 'Findings' },
    { id: 'RECOMMENDATIONS', label: 'Recommendations' },
    { id: 'TRENDS', label: 'Trends' }
];

export default class OhmApp extends LightningElement {
    @track activeTab = 'FLEET';
    @track calmMode = false;
    @track isReady = false;

    // Which process a fleet row asked us to open (drives the process page).
    @track selectedPlannerId;
    @track selectedPlannerLabel;

    async connectedCallback() {
        try {
            const calm = await getCalmModePreference();
            this.calmMode = !!calm;
        } catch (e) {
            this.calmMode = false;
        } finally {
            this.isReady = true;
        }
    }

    // ---- presentation -------------------------------------------------------
    get shellClass() {
        return this.calmMode
            ? 'ohm-app ohm-app--calm'
            : 'ohm-app';
    }

    // Tab strip model with per-tab active state + a11y attributes.
    get tabs() {
        return TABS.map((t) => {
            const isActive = t.id === this.activeTab;
            return {
                ...t,
                isActive,
                selected: isActive ? 'true' : 'false',
                tabindex: isActive ? '0' : '-1',
                cssClass: isActive
                    ? 'ohm-app__tab ohm-app__tab--active'
                    : 'ohm-app__tab'
            };
        });
    }

    get isFleet() {
        return this.activeTab === 'FLEET';
    }
    // The process page lives inside the FLEET tab once a row is opened.
    get isProcessOpen() {
        return this.isFleet && !!this.selectedPlannerId;
    }
    get isFleetList() {
        return this.isFleet && !this.selectedPlannerId;
    }
    get isFindings() {
        return this.activeTab === 'FINDINGS';
    }
    get isRecommendations() {
        return this.activeTab === 'RECOMMENDATIONS';
    }
    get isTrends() {
        return this.activeTab === 'TRENDS';
    }
    // Only Trends is still a placeholder; Findings + Recommendations are live.
    get isPlaceholder() {
        return this.isTrends;
    }

    // Breadcrumb: "Fleet" or "Fleet › <process>" once a row is opened.
    get breadcrumb() {
        const active = TABS.find((t) => t.id === this.activeTab);
        const head = (active && active.label) || 'Fleet';
        if (this.activeTab === 'FLEET' && this.selectedPlannerLabel) {
            return `${head} › ${this.selectedPlannerLabel}`;
        }
        return head;
    }

    // On-brand placeholder copy per non-Fleet tab.
    get placeholderTitle() {
        const active = TABS.find((t) => t.id === this.activeTab);
        return (active && active.label) || '';
    }
    get placeholderBody() {
        switch (this.activeTab) {
            case 'TRENDS':
                return 'Footprint and grade over time, org-wide and per-agent, are coming in a later build.';
            default:
                return '';
        }
    }

    // ---- interaction --------------------------------------------------------
    handleTabClick(event) {
        const tabId = event.currentTarget.dataset.tab;
        if (!tabId) {
            return;
        }
        // Any tab click returns home from an open process (incl. FLEET itself).
        this._clearProcess();
        if (tabId !== this.activeTab) {
            this.activeTab = tabId;
        }
    }

    handleTabKeydown(event) {
        const { key } = event;
        if (key !== 'ArrowRight' && key !== 'ArrowLeft') {
            return;
        }
        event.preventDefault();
        const idx = TABS.findIndex((t) => t.id === this.activeTab);
        const delta = key === 'ArrowRight' ? 1 : -1;
        const next = (idx + delta + TABS.length) % TABS.length;
        this.activeTab = TABS[next].id;
        // Move focus to the newly-selected tab.
        Promise.resolve().then(() => {
            const el = this.template.querySelector(
                `[data-tab="${this.activeTab}"]`
            );
            if (el) {
                el.focus();
            }
        });
    }

    // Open the process page for the requested planner (drill-down from a row).
    handleOpenProcess(event) {
        const detail = event.detail || {};
        this.activeTab = 'FLEET';
        this.selectedPlannerId = detail.plannerId;
        this.selectedPlannerLabel = detail.label;
    }

    // Return to the fleet list (back affordance on the process page).
    handleBackToFleet() {
        this._clearProcess();
    }

    _clearProcess() {
        this.selectedPlannerId = undefined;
        this.selectedPlannerLabel = undefined;
    }

    // ---- Calm Mode ----------------------------------------------------------
    handleCalmToggle(event) {
        const enabled = event.detail ? !!event.detail.enabled : !this.calmMode;
        const previous = this.calmMode;
        this.calmMode = enabled; // optimistic
        Promise.resolve(setCalmModePreference({ enabled })).catch(() => {
            this.calmMode = previous; // revert on reject
        });
    }
}
