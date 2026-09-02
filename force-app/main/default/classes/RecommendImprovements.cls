/**
 * RecommendImprovements — agent-door invocable action (SPEC §S.11, canon C4/C5).
 * Thin marshaller: deserializes findings from findingsJson (or rebuilds them from the
 * report's saved discovery graph when blank), delegates to
 * OhmRecommendationService.attachRecommendations (the same method the aura door calls),
 * and returns the recommendation candidates as JSON. generatedBy stays 'Deterministic';
 * the agent only narrates on top of these candidates.
 */
public with sharing class RecommendImprovements {

    @InvocableMethod(
        label='Recommend Improvements'
        description='Attaches a deterministic fix recommendation (fix type, target, effort, estimated savings) to each waste finding. Pass the findings JSON from Run Waste Signals, or just the report Id to rebuild findings from the saved discovery graph.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return out;
        }

        // Bulk-safe: one query for every report whose graph must be reloaded.
        Set<Id> reportIdsToLoad = new Set<Id>();
        for (Request r : requests) {
            if (r != null && String.isBlank(r.findingsJson) && String.isNotBlank(r.reportId)) {
                reportIdsToLoad.add(Id.valueOf(r.reportId.trim()));
            }
        }
        Map<Id, Agent_Audit_Report__c> reports = reportIdsToLoad.isEmpty()
            ? new Map<Id, Agent_Audit_Report__c>()
            : new Map<Id, Agent_Audit_Report__c>([
                SELECT Id, Discovery_Graph_Json__c
                FROM Agent_Audit_Report__c
                WHERE Id IN :reportIdsToLoad
              ]);

        OhmSignalService signals = new OhmSignalService();
        OhmRecommendationService recommendations = new OhmRecommendationService();

        for (Request r : requests) {
            Response resp = new Response();
            try {
                List<OhmDTO.Finding> findings;
                if (r != null && String.isNotBlank(r.findingsJson)) {
                    findings = (List<OhmDTO.Finding>) JSON.deserialize(r.findingsJson, List<OhmDTO.Finding>.class);
                } else if (r != null && String.isNotBlank(r.reportId)) {
                    Agent_Audit_Report__c rep = reports.get(Id.valueOf(r.reportId.trim()));
                    String graphJson = (rep == null) ? null : rep.Discovery_Graph_Json__c;
                    if (String.isBlank(graphJson)) {
                        resp.summary = 'Error: report ' + r.reportId + ' has no saved discovery graph. Run Discover Agentic Work first.';
                        out.add(resp);
                        continue;
                    }
                    OhmDTO.AgentModel graph = (OhmDTO.AgentModel) JSON.deserialize(graphJson, OhmDTO.AgentModel.class);
                    findings = signals.analyze(graph);
                } else {
                    resp.summary = 'Error: provide findingsJson or a reportId with a saved discovery graph.';
                    out.add(resp);
                    continue;
                }

                findings = recommendations.attachRecommendations(findings);

                Set<String> fixTypes = new Set<String>();
                for (OhmDTO.Finding f : findings) {
                    if (f.fixType != null) {
                        fixTypes.add(f.fixType);
                    }
                }

                resp.recommendationCount = findings.size();
                resp.candidatesJson = JSON.serialize(findings);
                resp.summary = (findings.isEmpty())
                    ? 'No findings to recommend against — nothing to fix.'
                    : 'Attached deterministic recommendations to ' + findings.size() + ' finding(s). Fix types: ' +
                      String.join(new List<String>(fixTypes), ', ') + '. Each carries modeled savings bands.';
            } catch (Exception e) {
                resp.summary = 'Error: ' + e.getMessage();
            }
            out.add(resp);
        }
        return out;
    }

    public class Request {
        @InvocableVariable(
            label='Report Id'
            description='Id of the Agent Audit Report whose findings should be rebuilt from the saved discovery graph when Findings JSON is blank.'
            required=false)
        public String reportId;
        @InvocableVariable(
            label='Findings JSON'
            description='Serialized findings list from Run Waste Signals. Leave blank to rebuild from the report.'
            required=false)
        public String findingsJson;
    }

    public class Response {
        @InvocableVariable(label='Recommendation Count' description='Number of findings that now carry a recommendation.')
        public Integer recommendationCount;
        @InvocableVariable(label='Candidates JSON' description='Serialized findings with fix type, target, effort, and savings attached. Do not parse.')
        public String candidatesJson;
        @InvocableVariable(label='Summary' description='Natural-language result of the recommendation step.')
        public String summary;
    }
}
