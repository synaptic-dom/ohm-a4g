/** Agent action: rank every published bundle by the modeled energy its recommendations avoid. */
public with sharing class OhmAgentListBundles {
    public class Request {
        @InvocableVariable(label='Requests per day' description='Requests a day to model. Optional; defaults to 300.')
        public Decimal requestsPerDay;
    }
    public class Response {
        @InvocableVariable(label='Summary' description='Ranked bundles with Input, Output and Calls grades and the modeled energy, CO2e and water avoided per year.')
        public String summary;
        @InvocableVariable(label='Bundles JSON' description='Structured rows behind the summary. Do not read aloud.')
        public String bundlesJson;
    }
    @InvocableMethod(label='Ohm: List bundles and modeled savings'
        description='Lists every published Agent Script bundle Ohm has reviewed, with its Input, Output and Calls grades and the modeled energy, carbon and water its recommendations would avoid at a request volume (default 300 a day).')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        List<Request> work = (requests == null || requests.isEmpty()) ? new List<Request>{ new Request() } : requests;
        List<OhmDTO.ProcessSummaryDTO> rows;
        String error;
        try { rows = OhmAgentActions.fleet(); } catch (Exception e) { error = OhmAgentActions.errorText(e); }
        for (Request r : work) {
            Response resp = new Response();
            if (error != null) { resp.summary = 'Ohm could not read the bundles: ' + error; out.add(resp); continue; }
            Decimal perDay = (r == null || r.requestsPerDay == null || r.requestsPerDay <= 0) ? OhmAgentActions.DEFAULT_REQUESTS_PER_DAY : r.requestsPerDay;
            List<OhmDTO.ProcessSummaryDTO> ranked = OhmAgentActions.rankBySavings(rows);
            List<String> lines = new List<String>();
            Integer i = 1;
            for (OhmDTO.ProcessSummaryDTO row : ranked) { lines.add(i + '. ' + OhmAgentActions.bundleLine(row, perDay)); i++; }
            resp.summary = ranked.isEmpty() ? 'No published Agent Script bundles were found.'
                : 'At ' + perDay.setScale(0) + ' requests a day, ranked by modeled energy avoided: ' + String.join(lines, ' ')
                  + ' All energy, CO2e and water figures are modeled from source tokens, not measured.';
            resp.bundlesJson = JSON.serialize(ranked);
            out.add(resp);
        }
        return out;
    }
}
