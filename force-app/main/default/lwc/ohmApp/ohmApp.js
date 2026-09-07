import { LightningElement } from 'lwc';
const TABS = [
    { id: 'OVERVIEW', label: 'Overview' },
    { id: 'FLEET', label: 'Bundles' },
    { id: 'RECOMMENDATIONS', label: 'Recommendations' },
    { id: 'HOW', label: 'How it works' }
];
export default class OhmApp extends LightningElement {
    activeTab = 'OVERVIEW';
    selectedPlannerId;
    selectedPlannerLabel;
    selectedNodeId;
    selectedArtifactKey;
    selectedIntent;
    selectedQuestion;
    _navigationPending = false;
    renderedCallback() {
        if (!this._navigationPending) return;
        this._navigationPending = false;
        const shell = this.template.querySelector('[data-id="shell"]');
        const panel = this.template.querySelector('[role="tabpanel"]');
        if (shell && typeof shell.scrollIntoView === 'function') shell.scrollIntoView({ block: 'start', behavior: 'auto' });
        if (panel) panel.focus({ preventScroll: true });
    }
    get tabs() {
        return TABS.map((tab) => ({ ...tab,
            selected: tab.id === this.activeTab ? 'true' : 'false',
            tabindex: tab.id === this.activeTab ? '0' : '-1',
            cssClass: tab.id === this.activeTab ? 'ohm-app__tab ohm-app__tab--active' : 'ohm-app__tab'
        }));
    }
    get isOverview() { return this.activeTab === 'OVERVIEW'; }
    get isFleetList() { return this.activeTab === 'FLEET' && !this.selectedPlannerId; }
    get isProcessOpen() { return this.activeTab === 'FLEET' && !!this.selectedPlannerId; }
    get isRecommendations() { return this.activeTab === 'RECOMMENDATIONS'; }
    get isHow() { return this.activeTab === 'HOW'; }
    get activePanelLabel() { return this.isProcessOpen ? this.selectedPlannerLabel || 'Bundle review' : TABS.find((tab) => tab.id === this.activeTab).label; }
    navigate(tab) {
        if (!TABS.some((item) => item.id === tab)) return;
        this.clearProcess();
        this._navigationPending = true;
        this.activeTab = tab;
    }
    handleHome() { this.navigate('OVERVIEW'); }
    handleNavigate(event) { this.navigate(event.detail && event.detail.tab); }
    handleTabClick(event) { this.navigate(event.currentTarget.dataset.tab); }
    handleTabKeydown(event) {
        if (!['ArrowRight', 'ArrowLeft', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        const index = TABS.findIndex((tab) => tab.id === this.activeTab);
        const next = event.key === 'Home' ? 0 : event.key === 'End' ? TABS.length - 1 :
            (index + (event.key === 'ArrowRight' ? 1 : -1) + TABS.length) % TABS.length;
        this.navigate(TABS[next].id);
        Promise.resolve().then(() => this.template.querySelector(`[data-tab="${this.activeTab}"]`).focus());
    }
    handleOpenProcess(event) {
        const detail = event.detail || {};
        if (!detail.plannerId) return;
        this._navigationPending = true;
        this.activeTab = 'FLEET';
        this.selectedPlannerId = detail.plannerId;
        this.selectedPlannerLabel = detail.label;
        this.selectedNodeId = detail.nodeId;
        this.selectedArtifactKey = detail.artifactKey;
        this.selectedIntent = detail.intent;
        this.selectedQuestion = detail.question;
    }
    handleBackToFleet() { this.navigate('FLEET'); }
    clearProcess() {
        this.selectedPlannerId = undefined;
        this.selectedPlannerLabel = undefined;
        this.selectedNodeId = undefined;
        this.selectedArtifactKey = undefined;
        this.selectedIntent = undefined;
        this.selectedQuestion = undefined;
    }
}
