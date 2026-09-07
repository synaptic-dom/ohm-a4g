/** Agent action: turn one saved recommendation into a real Salesforce Task, never duplicated. */
public with sharing class OhmAgentCreateTask {
    public class Request {
        @InvocableVariable(required=true label='Bundle' description='The bundle display name or API name as shown in Ohm.')
        public String bundle;
        @InvocableVariable(label='Category' description='Optional: Input, Output or Calls to choose which recommendation. Defaults to the highest-priority one.')
        public String category;
    }
    public class Response {
        @InvocableVariable(label='Task Id' description='The Task created or already tracking this recommendation.')
        public String taskId;
        @InvocableVariable(label='Summary' description='What the task covers and its id.')
        public String summary;
    }
    @InvocableMethod(label='Ohm: Create a task for a recommendation'
        description='Creates a standard Salesforce Task for a saved recommendation on one bundle so a builder can own the change. Returns the existing task if one already tracks it.')
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
                OhmReviewRecommendationService.RecommendationPage page = OhmReviewRecommendationService.getReviewRecommendations(row.plannerId);
                if (page.reviewAvailable != true || page.sourceCurrent != true) {
                    resp.summary = OhmAgentActions.recommendationSummary(row, page); out.add(resp); continue;
                }
                OhmReviewRecommendationService.Item item = OhmAgentActions.pickRecommendation(page, r.category);
                if (item == null) {
                    resp.summary = OhmAgentActions.displayLabel(row) + ' has no current recommendation' + (String.isBlank(r.category) ? '' : ' in ' + r.category) + ' to track.';
                    out.add(resp); continue;
                }
                if (item.taskId != null) {
                    resp.taskId = String.valueOf(item.taskId);
                    resp.summary = 'A task already tracks that change for ' + OhmAgentActions.displayLabel(row) + ': ' + resp.taskId + ' (' + item.taskStatus + '). ' + item.recommendation;
                    out.add(resp); continue;
                }
                Id taskId = OhmReviewRecommendationService.createReviewTask(row.plannerId, page.reportId, item.key);
                resp.taskId = String.valueOf(taskId);
                resp.summary = 'Created task ' + resp.taskId + ' for ' + OhmAgentActions.displayLabel(row) + ' [' + item.categoryLabel + ', ' + item.rating + ']: ' + item.recommendation
                    + ' The task carries the evidence, what to keep intact and how to validate the change.';
            } catch (Exception e) {
                resp.summary = 'Ohm could not create the task: ' + OhmAgentActions.errorText(e);
            }
            out.add(resp);
        }
        return out;
    }
}
