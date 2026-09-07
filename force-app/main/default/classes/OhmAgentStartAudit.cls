/** Agent action: start a real audit of one bundle through the same door the app uses. */
public with sharing class OhmAgentStartAudit {
    public class Request {
        @InvocableVariable(required=true label='Bundle' description='The bundle display name or API name as shown in Ohm.')
        public String bundle;
    }
    public class Response {
        @InvocableVariable(label='Report Id' description='The audit report to check on later.')
        public String reportId;
        @InvocableVariable(label='Status' description='Queued when the audit has started.')
        public String status;
        @InvocableVariable(label='Summary' description='What was started and how to follow it.')
        public String summary;
    }
    @InvocableMethod(label='Ohm: Start an audit'
        description='Starts a real audit of one published bundle: retrieves the published source, reviews it with Prompt Builder, verifies every quote and saves the results. Returns the report id to check on.')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null) return out;
        List<OhmDTO.ProcessSummaryDTO> rows;
        String error;
        try { rows = OhmAgentActions.fleet(); } catch (Exception e) { error = OhmAgentActions.errorText(e); }
        for (Request r : requests) {
            Response resp = new Response();
            try {
                if (error != null) { resp.summary = 'Ohm could not read the bundles: ' + error; out.add(resp); continue; }
                OhmDTO.ProcessSummaryDTO row = OhmAgentActions.resolve(r == null ? null : r.bundle, rows);
                if (row == null) {
                    resp.summary = 'Bundle "' + (r == null ? '' : r.bundle) + '" was not found. ' + OhmAgentActions.availableBundles(rows);
                    out.add(resp); continue;
                }
                Id reportId = OhmAuditController.auditProcess(row.plannerId);
                resp.reportId = String.valueOf(reportId);
                resp.status = 'Queued';
                resp.summary = 'Audit of ' + OhmAgentActions.displayLabel(row) + ' started; report ' + resp.reportId
                    + '. It retrieves the published source, reviews it and verifies every quote before anything is saved. Ask me to check on it in a minute or two.';
            } catch (Exception e) {
                resp.summary = 'Ohm could not start the audit: ' + OhmAgentActions.errorText(e);
            }
            out.add(resp);
        }
        return out;
    }
}
