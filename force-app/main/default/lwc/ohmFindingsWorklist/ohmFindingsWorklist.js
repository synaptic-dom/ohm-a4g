import { LightningElement, api, track } from 'lwc';
import getFindings from '@salesforce/apex/OhmAuditController.getFindings';
import updateFindingStatus from '@salesforce/apex/OhmAuditController.updateFindingStatus';
import assignFinding from '@salesforce/apex/OhmAuditController.assignFinding';
import USER_ID from '@salesforce/user/Id';
import { SIGNAL_LABELS } from 'c/ohmConstants';

/** Existing detector findings and their real Task assignment/status lifecycle. */
const STATUS_CHOICES = ['Open', 'Accepted', 'Dismissed', 'Applied'];

export default class OhmFindingsWorklist extends LightningElement {
    @api calmMode = false;

    @track rows = [];
    @track isLoading = true;
    @track loadError;

    // controls
    @track statusFilter = 'All';
    @track severityFilter = 'All';
    @track sortDir = 'desc'; // severity priority: desc | asc

    // per-row ui state
    @track expandedId;
    @track assignOpenId;
    @track busyId; // a status/assign call is in flight for this finding
    @track rowErrors = {};
    @track assignDates = {}; // findingId -> 'YYYY-MM-DD'

    connectedCallback() {
        this.loadFindings();
    }

    async loadFindings() {
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const data = await getFindings({
                statusFilter: this.statusFilter,
                severityFilter: this.severityFilter
            });
            this.rows = Array.isArray(data) ? data : [];
        } catch (e) {
            this.loadError = this._msg(e) || 'Could not load the findings.';
            this.rows = [];
        } finally {
            this.isLoading = false;
        }
    }

    // ---- host + control models ---------------------------------------------
    get hostClass() { return 'ohm-work'; }

    get statusFilterOptions() {
        return [
            { label: 'All statuses', value: 'All' },
            { label: 'Open', value: 'Open' },
            { label: 'Accepted', value: 'Accepted' },
            { label: 'Dismissed', value: 'Dismissed' },
            { label: 'Applied', value: 'Applied' }
        ];
    }

    get severityFilterOptions() {
        return [
            { label: 'All severities', value: 'All' },
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
    }

    get sortLabel() {
        return this.sortDir === 'asc' ? 'Low priority first' : 'High priority first';
    }

    // ---- decorated, sorted rows --------------------------------------------
    get visibleRows() {
        const dir = this.sortDir === 'asc' ? 1 : -1;
        const priority = { High: 3, Medium: 2, Low: 1 };
        const out = this.rows.slice().sort((a, b) =>
            ((priority[a.severity] || 0) - (priority[b.severity] || 0)) * dir ||
            (a.processLabel || a.plannerApiName || '').localeCompare(b.processLabel || b.plannerApiName || '')
        );
        return out.map((r) => this._decorate(r));
    }

    _decorate(r) {
        const severity = r.severity || 'Unknown';
        const status = r.findingStatus || 'Open';
        const assigned = !!r.assigneeId;
        const findingId = r.findingId;
        return {
            ...r,
            findingId,
            severity,
            severityText: severity,
            severityClass: `ohm-work__chip ohm-work__chip--${this._sevTone(
                severity
            )}`,
            signalLabel: SIGNAL_LABELS[r.signal] || r.signal || 'Unknown signal',
            processText: r.processLabel || r.plannerApiName || '—',
            artifactText: r.artifactLabel || '',
            assigned,
            assignmentLabel: r.assigneeId === USER_ID ? 'Yours' : (r.assigneeName || 'Assigned'),
            taskUrl: r.taskId ? `/lightning/r/Task/${r.taskId}/view` : null,
            assigneeText: assigned ? r.assigneeName || 'Assigned' : '—',
            dueText: r.dueDate ? r.dueDate : '—',
            statusValue: status,
            statusText: status,
            statusOptions: STATUS_CHOICES.map((s) => ({
                value: s,
                label: s,
                selected: s === status
            })),
            statusClass: `ohm-work__status ohm-work__status--${status.toLowerCase()}`,
            assignKey: `${findingId}-assign`,
            detailKey: `${findingId}-detail`,
            errKey: `${findingId}-err`,
            isExpanded: this.expandedId === findingId,
            assignOpen: this.assignOpenId === findingId,
            isBusy: this.busyId === findingId,
            rowError: this.rowErrors[findingId] || null,
            assignDate: Object.prototype.hasOwnProperty.call(this.assignDates, findingId) ? this.assignDates[findingId] : (r.dueDate || ''),
            hasRecommendation: !!r.recommendationText,
            expandLabel: this.expandedId === findingId ? 'Hide' : 'Details'
        };
    }

    _sevTone(sev) {
        if (sev === 'High') {
            return 'hot';
        }
        if (sev === 'Medium') {
            return 'warm';
        }
        if (sev === 'Low') {
            return 'muted';
        }
        return 'muted';
    }

    // ---- empty / state flags ------------------------------------------------
    get hasRows() {
        return !this.isLoading && !this.loadError && this.rows.length > 0;
    }
    get isEmpty() {
        return !this.isLoading && !this.loadError && this.rows.length === 0;
    }
    get isFiltered() {
        return this.statusFilter !== 'All' || this.severityFilter !== 'All';
    }

    // ---- filter / sort interaction -----------------------------------------
    handleStatusFilter(event) {
        this.statusFilter = event.target.value;
        this.loadFindings();
    }
    handleSeverityFilter(event) {
        this.severityFilter = event.target.value;
        this.loadFindings();
    }
    handleSortToggle() {
        this.sortDir = this.sortDir === 'desc' ? 'asc' : 'desc';
    }
    handleClearFilters() {
        this.statusFilter = 'All';
        this.severityFilter = 'All';
        this.loadFindings();
    }

    // ---- row interaction ----------------------------------------------------
    handleToggleExpand(event) {
        const id = event.currentTarget.dataset.finding;
        this.expandedId = this.expandedId === id ? undefined : id;
    }

    async handleRowStatusChange(event) {
        const findingId = event.target.dataset.finding;
        const status = event.target.value;
        if (!findingId || !status || this.busyId) {
            return;
        }
        this.busyId = findingId;
        this.rowErrors = { ...this.rowErrors, [findingId]: null };
        try {
            await updateFindingStatus({ findingId, status });
            await this.loadFindings();
        } catch (e) {
            this.rowErrors = {
                ...this.rowErrors,
                [findingId]: this._msg(e) || 'Could not update the status.'
            };
        } finally {
            this.busyId = undefined;
        }
    }

    handleToggleAssign(event) {
        const id = event.currentTarget.dataset.finding;
        this.assignOpenId = this.assignOpenId === id ? undefined : id;
    }

    handleDateChange(event) {
        const id = event.target.dataset.finding;
        this.assignDates = { ...this.assignDates, [id]: event.target.value };
    }

    async handleAssignToMe(event) {
        const findingId = event.currentTarget.dataset.finding;
        if (!findingId || this.busyId) {
            return;
        }
        const dueDate = this.assignDates[findingId] || null;
        this.busyId = findingId;
        this.rowErrors = { ...this.rowErrors, [findingId]: null };
        try {
            await assignFinding({ findingId, userId: USER_ID, dueDate });
            this.assignOpenId = undefined;
            await this.loadFindings();
        } catch (e) {
            this.rowErrors = {
                ...this.rowErrors,
                [findingId]: this._msg(e) || 'Could not assign the finding.'
            };
        } finally {
            this.busyId = undefined;
        }
    }

    handleRetry() {
        this.loadFindings();
    }

    _msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || null;
    }
}
