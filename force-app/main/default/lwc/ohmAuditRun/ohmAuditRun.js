import getAuditStatus from '@salesforce/apex/OhmAuditController.getAuditStatus';

const STORAGE_KEY = 'ohm:pending-audits:v1';
const GUIDED_STORAGE_KEY = 'ohm:pending-guided-audit:v1';
export const AUDIT_POLL_MS = 1500;
// Org-wide guided runs have no planner ID and must not be resumed as Fleet rows.
export function pendingGuidedAudit() {
    try {
        const value = JSON.parse(window.sessionStorage.getItem(GUIDED_STORAGE_KEY) || 'null');
        return value && typeof value.reportId === 'string' && value.reportId ? value.reportId : null;
    } catch (e) { return null; }
}
export function rememberGuidedAudit(reportId) {
    try { window.sessionStorage.setItem(GUIDED_STORAGE_KEY, JSON.stringify({ reportId })); }
    catch (e) { /* The run remains usable without browser storage. */ }
}
export function forgetGuidedAudit() {
    try { window.sessionStorage.removeItem(GUIDED_STORAGE_KEY); }
    catch (e) { /* The completed result is still available in Salesforce. */ }
}
export function pendingAudits() {
    try {
        const value = JSON.parse(window.sessionStorage.getItem(STORAGE_KEY) || '{}');
        return Object.values(value).filter((run) => run && typeof run.plannerId === 'string' && typeof run.reportId === 'string');
    } catch (e) { return []; }
}
export function rememberAudit(run) {
    try {
        const entries = Object.fromEntries(pendingAudits().map((item) => [item.plannerId, item]));
        entries[run.plannerId] = { plannerId: run.plannerId, reportId: run.reportId, label: run.label, hadPriorAudit: run.hadPriorAudit };
        window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
    } catch (e) { /* A blocked browser store must not prevent an audit. */ }
}
export function forgetAudit(plannerId) {
    try {
        const entries = Object.fromEntries(pendingAudits().filter((run) => run.plannerId !== plannerId).map((run) => [run.plannerId, run]));
        window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
    } catch (e) { /* Polling still works when storage is unavailable. */ }
}
export function auditError(error) {
    return (error && error.body && error.body.message) || (error && error.message) || 'Could not check the audit. Your run may still be processing.';
}
/** One in-flight status request at a time. A paused connection resumes the same report. */
export function watchAudit(run, onStatus, onComplete, onError) {
    let stopped = false;
    let timer;
    async function poll() {
        try {
            const status = await getAuditStatus({ reportId: run.reportId });
            if (stopped) return;
            if (!status || !status.runStatus) throw new Error('The audit status was unavailable. Check this run again.');
            const next = { ...run, ...status, reportId: run.reportId, error: null, canRetry: false };
            onStatus(status.runStatus === 'Complete' ? { ...next, runStatus: 'LoadingResults', stageMessage: 'Loading the completed audit report.' } : next);
            if (status.runStatus === 'Complete') {
                stopped = true;
                await onComplete(next);
            } else if (status.runStatus === 'Failed') {
                stopped = true;
                onError({ ...next, error: status.stageMessage || 'The audit failed. Retry to retrieve fresh source.', canRetry: true, terminal: true });
            } else {
                timer = setTimeout(poll, AUDIT_POLL_MS);
            }
        } catch (error) {
            if (!stopped) onError({ ...run, error: auditError(error), canRetry: true, terminal: false });
        }
    }
    poll();
    return () => { stopped = true; clearTimeout(timer); };
}
