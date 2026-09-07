/** Agent action: progress of a running audit, and the grades once it completes. */
public with sharing class OhmAgentAuditStatus {
    public class Request {
        @InvocableVariable(required=true label='Report Id' description='The audit report id returned when the audit started.')
        public String reportId;
    }
    public class Response {
        @InvocableVariable(label='Status' description='Queued, running stage, Complete or Failed.')
        public String status;
        @InvocableVariable(label='Percent complete' description='Progress 0 to 100.')
        public Integer percentComplete;
        @InvocableVariable(label='Summary' description='Stage, progress and the grades when finished.')
        public String summary;
    }
    @InvocableMethod(label='Ohm: Check an audit'
        description='Reports how a running audit is doing and, once it has completed, its Input, Output and Calls grades.')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null) return out;
        for (Request r : requests) {
            Response resp = new Response();
            Id reportId;
            try { reportId = Id.valueOf(r == null || r.reportId == null ? '' : r.reportId.trim()); } catch (Exception e) { reportId = null; }
            if (reportId == null) { resp.summary = 'That is not a valid report id. Use the id returned when the audit was started.'; out.add(resp); continue; }
            try {
                OhmDTO.AuditReadoutDTO readout = OhmAuditController.getAuditStatus(reportId);
                resp.status = readout.runStatus;
                resp.percentComplete = readout.percentComplete;
                String base = 'Report ' + reportId + ' is ' + readout.runStatus
                    + (readout.percentComplete == null ? '' : ' at ' + readout.percentComplete + '%')
                    + (String.isBlank(readout.stageMessage) ? '.' : ': ' + readout.stageMessage);
                if (readout.runStatus == 'Complete') {
                    base += ' Grades: ' + OhmAgentActions.gradeLine(OhmAgentActions.grades(readout.reviewJson)) + '. Open the bundle in Ohm to see the recommendations and the modeled footprint.';
                } else if (readout.runStatus == 'Failed') {
                    base += ' Nothing was saved from this run; you can start it again.';
                }
                resp.summary = base;
            } catch (Exception e) {
                resp.summary = 'Ohm could not read that report: ' + OhmAgentActions.errorText(e);
            }
            out.add(resp);
        }
        return out;
    }
}
