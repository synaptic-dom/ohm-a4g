/** One committed acquisition phase per transaction; finalizer records otherwise uncatchable failures. */
public with sharing class OhmAuditJob implements Queueable, Database.AllowsCallouts, Finalizer {
    private Id reportId;
    public OhmAuditJob(Id reportId) { this.reportId = reportId; }
    public void execute(QueueableContext context) {
        System.attachFinalizer(this);
        OhmAuditCoordinator.advance(reportId, true);
    }
    public void execute(FinalizerContext context) {
        if (context.getResult() != ParentJobResult.SUCCESS) {
            OhmAuditCoordinator.fail(reportId, 'The background audit stopped before completion. Start a new audit.');
        }
    }
}
