import { LightningElement, api, track } from 'lwc';
import getFleet from '@salesforce/apex/OhmAuditController.getFleet';
import auditProcess from '@salesforce/apex/OhmAuditController.auditProcess';
import { formatNumber, GRADE_WORDS } from 'c/ohmConstants';

/**
 * ohmFleetTable — the Fleet home (SPEC §2.1).
 * Imperatively lists discovered processes (getFleet), audits one on demand
 * (auditProcess -> refresh), and fires `openprocess` for audited rows. Filter by
 * domain + grade, sort by energy, search over label — all client-side over the
 * returned list. Everything is null-guarded because an un-audited row has null
 * grade/score/energy/lastAudited.
 */
const GRADE_ORDER = { A: 0, B: 1, C: 2, D: 3, F: 4 };

export default class OhmFleetTable extends LightningElement {
    @api calmMode = false;

    @track rows = [];
    @track isLoading = true;
    @track loadError;

    // filter / sort / search state
    @track domainFilter = 'ALL';
    @track gradeFilter = 'ALL';
    @track sortDir = 'desc'; // energy sort: desc | asc | none
    @track searchTerm = '';

    // per-row audit progress + error, keyed by plannerId
    @track auditingId;
    @track rowErrors = {};

    connectedCallback() {
        this.loadFleet();
    }

    async loadFleet() {
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getFleet();
            this.rows = Array.isArray(data) ? data : [];
        } catch (e) {
            this.loadError = this._msg(e) || 'Could not load the fleet.';
            this.rows = [];
        } finally {
            this.isLoading = false;
        }
    }

    // ---- host class ---------------------------------------------------------
    get hostClass() {
        return this.calmMode ? 'ohm-fleet ohm-fleet--calm' : 'ohm-fleet';
    }

    // ---- filter option models ----------------------------------------------
    get domainOptions() {
        const set = new Set();
        this.rows.forEach((r) => {
            if (r.domain) {
                set.add(r.domain);
            }
        });
        const opts = [{ label: 'All domains', value: 'ALL' }];
        Array.from(set)
            .sort()
            .forEach((d) => opts.push({ label: d, value: d }));
        return opts;
    }

    get gradeOptions() {
        return [
            { label: 'All grades', value: 'ALL' },
            { label: 'A', value: 'A' },
            { label: 'B', value: 'B' },
            { label: 'C', value: 'C' },
            { label: 'D', value: 'D' },
            { label: 'F', value: 'F' },
            { label: 'Not audited', value: 'NONE' }
        ];
    }

    // ---- the visible, decorated rows ---------------------------------------
    get visibleRows() {
        let out = this.rows.slice();

        if (this.domainFilter !== 'ALL') {
            out = out.filter((r) => r.domain === this.domainFilter);
        }
        if (this.gradeFilter === 'NONE') {
            out = out.filter((r) => !r.audited);
        } else if (this.gradeFilter !== 'ALL') {
            out = out.filter((r) => r.audited && r.grade === this.gradeFilter);
        }
        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            out = out.filter(
                (r) =>
                    (r.label || '').toLowerCase().includes(term) ||
                    (r.plannerApiName || '').toLowerCase().includes(term)
            );
        }
        if (this.sortDir !== 'none') {
            const dir = this.sortDir === 'asc' ? 1 : -1;
            out.sort((a, b) => {
                const av = a.energyWhCentral;
                const bv = b.energyWhCentral;
                // null energy (un-audited) always sorts to the bottom
                if (av === null || av === undefined) {
                    return bv === null || bv === undefined ? 0 : 1;
                }
                if (bv === null || bv === undefined) {
                    return -1;
                }
                return (av - bv) * dir;
            });
        }

        return out.map((r) => this._decorate(r));
    }

    _decorate(r) {
        const audited = !!r.audited;
        const grade = audited ? r.grade || null : null;
        const isAuditing = this.auditingId === r.plannerId;
        return {
            ...r,
            audited,
            grade,
            gradeWord: grade ? GRADE_WORDS[grade] || '' : '',
            energyText:
                audited && r.energyWhCentral !== null && r.energyWhCentral !== undefined
                    ? `${formatNumber(r.energyWhCentral)} Wh/yr`
                    : '—',
            topicText: this._count(r.topicCount),
            actionText: this._count(r.actionCount),
            chipClass: `ohm-fleet__chip ohm-fleet__chip--${this._chipTone(
                grade
            )}`,
            isAuditing,
            rowError: this.rowErrors[r.plannerId] || null,
            statusLabel: audited ? 'Audited' : 'Not audited yet'
        };
    }

    _count(n) {
        return n === null || n === undefined ? '—' : formatNumber(n);
    }

    // grade -> tone bucket (F/D hot, C muted, B/A cool)
    _chipTone(grade) {
        if (grade === 'F') {
            return 'hot';
        }
        if (grade === 'D') {
            return 'warm';
        }
        if (grade === 'C') {
            return 'muted';
        }
        if (grade === 'A' || grade === 'B') {
            return 'cool';
        }
        return 'muted';
    }

    // ---- summary strip ------------------------------------------------------
    get discoveredCount() {
        return this.rows.length;
    }
    get auditedCount() {
        return this.rows.filter((r) => r.audited).length;
    }
    get totalEnergyText() {
        const sum = this.rows.reduce((acc, r) => {
            if (
                r.audited &&
                r.energyWhCentral !== null &&
                r.energyWhCentral !== undefined
            ) {
                return acc + Number(r.energyWhCentral);
            }
            return acc;
        }, 0);
        return this.auditedCount > 0 ? `${formatNumber(sum)} Wh/yr` : '—';
    }
    get worstGradeText() {
        let worst = null;
        this.rows.forEach((r) => {
            if (r.audited && r.grade) {
                if (
                    worst === null ||
                    (GRADE_ORDER[r.grade] || 0) > (GRADE_ORDER[worst] || 0)
                ) {
                    worst = r.grade;
                }
            }
        });
        return worst || '—';
    }

    get hasRows() {
        return this.visibleRows.length > 0;
    }
    get isEmptyAfterLoad() {
        return !this.isLoading && !this.loadError && this.rows.length === 0;
    }
    get isFilteredEmpty() {
        return (
            !this.isLoading &&
            !this.loadError &&
            this.rows.length > 0 &&
            this.visibleRows.length === 0
        );
    }

    get sortLabel() {
        if (this.sortDir === 'desc') {
            return 'Energy ▼';
        }
        if (this.sortDir === 'asc') {
            return 'Energy ▲';
        }
        return 'Energy —';
    }

    // ---- interaction --------------------------------------------------------
    handleDomainChange(event) {
        this.domainFilter = event.target.value;
    }
    handleGradeChange(event) {
        this.gradeFilter = event.target.value;
    }
    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }
    handleSortToggle() {
        this.sortDir =
            this.sortDir === 'desc'
                ? 'asc'
                : this.sortDir === 'asc'
                ? 'none'
                : 'desc';
    }

    async handleAudit(event) {
        const plannerId = event.currentTarget.dataset.planner;
        if (!plannerId || this.auditingId) {
            return;
        }
        this.auditingId = plannerId;
        this.rowErrors = { ...this.rowErrors, [plannerId]: null };
        try {
            await auditProcess({ plannerId });
            await this.loadFleet();
        } catch (e) {
            this.rowErrors = {
                ...this.rowErrors,
                [plannerId]: this._msg(e) || 'Audit failed. Please try again.'
            };
        } finally {
            this.auditingId = undefined;
        }
    }

    handleOpen(event) {
        const plannerId = event.currentTarget.dataset.planner;
        const row = this.rows.find((r) => r.plannerId === plannerId);
        this.dispatchEvent(
            new CustomEvent('openprocess', {
                detail: {
                    plannerId,
                    label: row ? row.label : undefined
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleRetry() {
        this.loadFleet();
    }

    _msg(e) {
        return (
            (e && e.body && e.body.message) ||
            (e && e.message) ||
            null
        );
    }
}
