/** Agent action: the saved recommendations for one bundle, phrased as change, keep, validate. */
public with sharing class OhmAgentRecommendations {
    public class Request {
        @InvocableVariable(required=true label='Bundle' description='The bundle display name or API name as shown in Ohm.')
        public String bundle;
    }
    public class Response {
        @InvocableVariable(label='Summary' description='Readable recommendations, or the available bundles if the name was not found.')
        public String summary;
        @InvocableVariable(label='Recommendations JSON' description='Structured items behind the summary. Do not read aloud.')
        public String recommendationsJson;
        @InvocableVariable(label='Report Id' description='The saved review the recommendations come from.')
        public String reportId;
    }
    @InvocableMethod(label='Ohm: Get recommendations for a bundle'
        description='Returns the current saved recommendations for one published bundle: what to change, what must stay intact, how to validate it, with quoted source evidence.')
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
                resp.reportId = page.reportId == null ? null : String.valueOf(page.reportId);
                resp.recommendationsJson = JSON.serialize(page.items);
                resp.summary = OhmAgentActions.recommendationSummary(row, page);
            } catch (Exception e) {
                resp.summary = 'Ohm could not load recommendations: ' + OhmAgentActions.errorText(e);
            }
            out.add(resp);
        }
        return out;
    }
}
