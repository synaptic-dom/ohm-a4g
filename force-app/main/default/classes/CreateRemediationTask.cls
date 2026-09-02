/**
 * CreateRemediationTask — agent-door invocable action (SPEC §S.11, canon C4/C12).
 * Thin marshaller: takes a findingId (+ optional note), loads the persisted Finding__c
 * (ONE bulk query), populates the single OhmDTO.RemediationInputDTO, and delegates to
 * OhmPersistenceService.createRemediationTask — the SAME method the aura door calls
 * (C12 resolves the two-doors violation). Returns the created Task Id.
 */
public with sharing class CreateRemediationTask {

    @InvocableMethod(
        label='Create Remediation Task'
        description='Creates a remediation Task from a waste finding so the fix gets owned and tracked. Pass the finding Id and an optional note; the task subject, description, and savings come from the persisted finding. Returns the new Task Id.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return out;
        }

        // Bulk-safe: ONE query loads every requested finding before the loop.
        Set<Id> findingIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && String.isNotBlank(r.findingId)) {
                findingIds.add(Id.valueOf(r.findingId.trim()));
            }
        }
        Map<Id, Finding__c> findings = findingIds.isEmpty()
            ? new Map<Id, Finding__c>()
            : new Map<Id, Finding__c>([
                SELECT Id, Agent_Audit_Report__c, Fix_Type__c, Recommended_Target__c,
                       Recommendation_Text__c, Annual_Energy_Savings_Wh__c
                FROM Finding__c
                WHERE Id IN :findingIds
              ]);

        // Agentforce invokes with one Request per call; task DML lives in the
        // persistence service (single F8 method, C12).
        OhmPersistenceService persistence = new OhmPersistenceService();

        for (Request r : requests) {
            Response resp = new Response();
            try {
                if (r == null || String.isBlank(r.findingId)) {
                    resp.summary = 'Error: findingId is required.';
                    out.add(resp);
                    continue;
                }
                Finding__c f = findings.get(Id.valueOf(r.findingId.trim()));
                if (f == null) {
                    resp.summary = 'Error: no Finding found with Id ' + r.findingId + '.';
                    out.add(resp);
                    continue;
                }

                OhmDTO.RemediationInputDTO input = new OhmDTO.RemediationInputDTO();
                input.findingId = f.Id;
                input.reportId = f.Agent_Audit_Report__c;
                input.fixType = f.Fix_Type__c;
                input.recommendedTarget = f.Recommended_Target__c;
                input.recommendationText = f.Recommendation_Text__c;
                input.estimatedSavingsCentralWh = f.Annual_Energy_Savings_Wh__c;
                input.note = (r.note == null) ? null : r.note.trim();

                Id taskId = persistence.createRemediationTask(input);
                resp.taskId = taskId;
                resp.summary = 'Created remediation task ' + taskId + ' for finding ' + f.Id +
                    ((f.Fix_Type__c == null) ? '' : ' (fix: ' + f.Fix_Type__c + ')') + '.';
            } catch (Exception e) {
                resp.summary = 'Error: ' + e.getMessage();
            }
            out.add(resp);
        }
        return out;
    }

    public class Request {
        @InvocableVariable(
            label='Finding Id'
            description='Id of the persisted Finding record to remediate.'
            required=true)
        public String findingId;
        @InvocableVariable(
            label='Note'
            description='Optional note appended to the remediation task description.'
            required=false)
        public String note;
    }

    public class Response {
        @InvocableVariable(label='Task Id' description='Id of the remediation Task that was created.')
        public String taskId;
        @InvocableVariable(label='Summary' description='Natural-language result of the task creation.')
        public String summary;
    }
}
