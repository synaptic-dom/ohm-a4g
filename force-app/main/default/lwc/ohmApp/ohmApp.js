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
 * Leaves a clean seam for Wave 3: an `openprocess` event from a fleet row is
 * captured into `selectedPlannerId` (and logged); the process page itself is
 * NOT built here.
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

    // Wave-3 seam: which process a fleet row asked us to open (records only).
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
    get isFindings() {
        return this.activeTab === 'FINDINGS';
    }
    get isRecommendations() {
        return this.activeTab === 'RECOMMENDATIONS';
    }
    get isTrends() {
        return this.activeTab === 'TRENDS';
    }
    get isPlaceholder() {
        return !this.isFleet;
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
            case 'FINDINGS':
                return 'A cross-fleet backlog of every waste finding — owners, due dates and status — is coming in a later build.';
            case 'RECOMMENDATIONS':
                return 'Prioritized quick-wins ranked by savings against effort are coming in a later build.';
            case 'TRENDS':
                return 'Footprint and grade over time, org-wide and per-agent, are coming in a later build.';
            default:
                return '';
        }
    }

    // ---- interaction --------------------------------------------------------
    handleTabClick(event) {
        const tabId = event.currentTarget.dataset.tab;
        if (tabId && tabId !== this.activeTab) {
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

    // Wave-3 seam: record + log the requested process; no navigation yet.
    handleOpenProcess(event) {
        const detail = event.detail || {};
        this.selectedPlannerId = detail.plannerId;
        this.selectedPlannerLabel = detail.label;
        // eslint-disable-next-line no-console
        console.log(
            `[ohmApp] openprocess requested for planner ${detail.plannerId} (${
                detail.label || 'unknown'
            }) — process page arrives in Wave 3.`
        );
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
