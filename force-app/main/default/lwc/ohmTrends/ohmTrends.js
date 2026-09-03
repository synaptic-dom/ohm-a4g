import { LightningElement, api, track } from 'lwc';
import getTrends from '@salesforce/apex/OhmAuditController.getTrends';
import { formatNumber, gradeTone, GRADE_WORDS } from 'c/ohmConstants';

/**
 * ohmTrends — the TRENDS tab (SPEC §2.5).
 *
 * connectedCallback -> getTrends(null) for the org-wide view. Renders, with
 * INLINE SVG only (no CDN libs — CSP), an org energy trendline (oldest→newest,
 * amber area + line), a "realized savings" callout, and a per-agent grade-history
 * strip (org scope only). A scope toggle switches between "Org" and a per-process
 * dropdown that re-calls getTrends(plannerId). Sparse data (1–2 points) still
 * renders as dots with a caption. Dark Instrument + Calm; tabular-mono;
 * accessible (the SVG carries role=img + a summary aria-label, and every grade
 * chip prints its letter as text).
 */

// SVG plot geometry (a fixed viewBox scaled to the container width).
const VB_W = 640;
const VB_H = 220;
const PAD_L = 52;
const PAD_R = 18;
const PAD_T = 18;
const PAD_B = 34;
const PLOT_W = VB_W - PAD_L - PAD_R;
const PLOT_H = VB_H - PAD_T - PAD_B;

export default class OhmTrends extends LightningElement {
    @api calmMode = false;

    @track trend;
    @track isLoading = false;
    @track loadError;

    // 'Org' or a planner id string; drives the scope toggle + which fetch runs.
    @track scope = 'Org';

    // Process options for the dropdown, captured from the org trend's perAgent
    // list so we never need a second round-trip to enumerate the fleet.
    @track processOptions = [];

    connectedCallback() {
        this.load(null);
    }

    async load(plannerId) {
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getTrends({ plannerId: plannerId || null });
            this.trend = data || null;
            // Only the org scope carries a perAgent list; keep it as the dropdown
            // source so the toggle works even while viewing a single process.
            if (!plannerId && data && Array.isArray(data.perAgent)) {
                this.processOptions = data.perAgent.map((a) => ({
                    value: a.plannerId,
                    label: a.label
                }));
            }
        } catch (e) {
            this.loadError = this._msg(e) || 'Could not load trends.';
            this.trend = null;
        } finally {
            this.isLoading = false;
        }
    }

    // ---- host / presentation ------------------------------------------------
    get hostClass() {
        return this.calmMode ? 'ohm-trends ohm-trends--calm' : 'ohm-trends';
    }

    get hasTrend() {
        return !!this.trend;
    }

    get points() {
        return this.trend && Array.isArray(this.trend.points)
            ? this.trend.points
            : [];
    }

    get isOrgScope() {
        return this.scope === 'Org';
    }

    get orgBtnClass() {
        return this.isOrgScope
            ? 'ohm-trends__scope-btn ohm-trends__scope-btn--active'
            : 'ohm-trends__scope-btn';
    }

    get scopeLabel() {
        if (this.isOrgScope) {
            return 'Org-wide';
        }
        return (this.trend && this.trend.scope) || 'Process';
    }

    get hasProcessOptions() {
        return this.processOptions.length > 0;
    }

    // Options for the per-process dropdown; the org entry sits first.
    get scopeOptions() {
        return [
            { value: 'Org', label: 'Org-wide' },
            ...this.processOptions
        ].map((o) => ({
            ...o,
            selected: o.value === this.scope
        }));
    }

    // ---- empty / sparse states ---------------------------------------------
    get hasNoPoints() {
        return this.hasTrend && this.points.length === 0;
    }
    get isSparse() {
        const n = this.points.length;
        return n > 0 && n < 2;
    }
    get sparseCaption() {
        return 'More points appear as you re-audit this process.';
    }

    // ---- realized savings callout ------------------------------------------
    get realizedSavingsText() {
        const v = this.trend ? this.trend.realizedSavingsWh : null;
        return v !== null && v !== undefined ? `${formatNumber(v)} Wh/yr` : '—';
    }
    get hasRealizedSavings() {
        const v = this.trend ? this.trend.realizedSavingsWh : null;
        return v !== null && v !== undefined && Number(v) > 0;
    }
    get firstEnergyText() {
        return formatNumber(this.trend && this.trend.firstEnergyWhCentral);
    }
    get lastEnergyText() {
        return formatNumber(this.trend && this.trend.lastEnergyWhCentral);
    }

    // ---- SVG trendline geometry --------------------------------------------
    get vbWidth() {
        return VB_W;
    }
    get vbHeight() {
        return VB_H;
    }
    get viewBox() {
        return `0 0 ${VB_W} ${VB_H}`;
    }

    // Baseline y (bottom of the plot) — the foot of the area fill.
    get baselineY() {
        return PAD_T + PLOT_H;
    }

    // Per-point plotted coordinates + labels (oldest→newest, left→right).
    get plotted() {
        const pts = this.points;
        const n = pts.length;
        if (n === 0) {
            return [];
        }
        const energies = pts.map((p) => Number(p.energyWhCentral) || 0);
        const min = Math.min(...energies);
        const max = Math.max(...energies);
        const span = max - min;
        return pts.map((p, i) => {
            const cx =
                n === 1 ? PAD_L + PLOT_W / 2 : PAD_L + (i / (n - 1)) * PLOT_W;
            const v = Number(p.energyWhCentral) || 0;
            const cy =
                span === 0
                    ? PAD_T + PLOT_H / 2
                    : PAD_T + (1 - (v - min) / span) * PLOT_H;
            return {
                key: p.reportId || `pt-${i}`,
                cx: this._round(cx),
                cy: this._round(cy),
                grade: p.grade,
                energyText: `${formatNumber(v)} Wh/yr`,
                dateText: this._fmtDate(p.auditedAt),
                title: `${this._fmtDate(p.auditedAt)}: ${p.grade || '—'} · ${formatNumber(
                    v
                )} Wh/yr`
            };
        });
    }

    get hasLine() {
        return this.plotted.length >= 2;
    }

    // polyline "x,y x,y …" for the trend stroke.
    get linePoints() {
        return this.plotted.map((p) => `${p.cx},${p.cy}`).join(' ');
    }

    // area path: down the baseline, along the top line, back to the baseline.
    get areaPath() {
        const pts = this.plotted;
        if (pts.length < 2) {
            return '';
        }
        const base = this.baselineY;
        let d = `M ${pts[0].cx} ${base}`;
        pts.forEach((p) => {
            d += ` L ${p.cx} ${p.cy}`;
        });
        d += ` L ${pts[pts.length - 1].cx} ${base} Z`;
        return d;
    }

    // A concise text summary of the whole trend for role=img consumers.
    get chartAriaLabel() {
        const n = this.points.length;
        if (n === 0) {
            return 'Energy trend chart, no audits yet.';
        }
        const first = this.firstEnergyText;
        const last = this.lastEnergyText;
        const scopeTxt = this.isOrgScope ? 'Org-wide' : this.scopeLabel;
        if (n === 1) {
            return `${scopeTxt} energy trend, a single audit at ${last} Wh per year.`;
        }
        const dir = this.hasRealizedSavings ? 'down' : 'across';
        return `${scopeTxt} energy trend across ${n} audits, ${dir} from ${first} to ${last} Wh per year.`;
    }

    // ---- per-agent grade history strip (org scope only) --------------------
    get showGradeHistory() {
        return (
            this.isOrgScope &&
            this.trend &&
            Array.isArray(this.trend.perAgent) &&
            this.trend.perAgent.length > 0
        );
    }

    get agentRows() {
        const agents =
            this.trend && Array.isArray(this.trend.perAgent)
                ? this.trend.perAgent
                : [];
        return agents.map((a) => {
            const history = Array.isArray(a.gradeHistory) ? a.gradeHistory : [];
            const lastIdx = history.length - 1;
            const chips = history.map((g, i) => {
                const isCurrent = i === lastIdx;
                return {
                    key: `${a.plannerId}-${i}`,
                    grade: g,
                    isCurrent,
                    cssClass: `ohm-trends__gchip ohm-trends__gchip--${gradeTone(
                        g
                    )}${isCurrent ? ' ohm-trends__gchip--current' : ''}`,
                    ariaLabel: isCurrent
                        ? `current grade ${g}`
                        : `grade ${g}`
                };
            });
            return {
                key: a.plannerId,
                label: a.label,
                currentGrade: a.currentGrade,
                currentWord: GRADE_WORDS[a.currentGrade] || '',
                chips,
                hasChips: chips.length > 0
            };
        });
    }

    // ---- interaction --------------------------------------------------------
    handleScopeChange(event) {
        const value = event.target.value;
        if (!value || value === this.scope) {
            return;
        }
        this.scope = value;
        this.load(value === 'Org' ? null : value);
    }

    handleOrgClick() {
        if (this.scope === 'Org') {
            return;
        }
        this.scope = 'Org';
        this.load(null);
    }

    handleRetry() {
        this.load(this.scope === 'Org' ? null : this.scope);
    }

    // ---- helpers ------------------------------------------------------------
    _round(n) {
        return Math.round(n * 100) / 100;
    }

    _fmtDate(value) {
        if (!value) {
            return '—';
        }
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) {
            return '—';
        }
        return d.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric'
        });
    }

    _msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || null;
    }
}
