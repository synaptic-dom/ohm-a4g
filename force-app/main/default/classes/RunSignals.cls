/**
 * RunSignals — agent-door invocable action (SPEC §S.11, canon C4/C5).
 * Thin marshaller: deserializes the AgentModel from graphJson (or reloads it from
 * Agent_Audit_Report__c.Discovery_Graph_Json__c when blank — C11 re-entrancy), delegates
 * to OhmSignalService.analyze (the same method the aura door calls), and returns the
 * findings as JSON with a per-signal breakdown.
 */
public with sharing class RunSignals {

    @InvocableMethod(
        label='Run Waste Signals'
        description='Analyzes the discovered agent graph for the four AI waste signals (LLM_WHERE_DETERMINISTIC, MODEL_RIGHTSIZING, INSTRUCTION_BLOAT, REDUNDANT_CALLS) and returns the findings. Pass the graph JSON from Discover Agentic Work, or just the report Id to reuse the saved discovery graph.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return out;
        }

        // Bulk-safe: collect every report whose graph must be reloaded, then ONE query.
        Set<Id> reportIdsToLoad = new Set<Id>();
        for (Request r : requests) {
            if (r != null && String.isBlank(r.graphJson) && String.isNotBlank(r.reportId)) {
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

        for (Request r : requests) {
            Response resp = new Response();
            try {
                String graphJson = (r == null) ? null : r.graphJson;
                if (String.isBlank(graphJson)) {
                    if (r == null || String.isBlank(r.reportId)) {
                        resp.summary = 'Error: provide graphJson or a reportId with a saved discovery graph.';
                        out.add(resp);
                        continue;
                    }
                    Agent_Audit_Report__c rep = reports.get(Id.valueOf(r.reportId.trim()));
                    graphJson = (rep == null) ? null : rep.Discovery_Graph_Json__c;
                    if (String.isBlank(graphJson)) {
                        resp.summary = 'Error: report ' + r.reportId + ' has no saved discovery graph. Run Discover Agentic Work first.';
                        out.add(resp);
                        continue;
                    }
                }

                OhmDTO.AgentModel graph = (OhmDTO.AgentModel) JSON.deserialize(graphJson, OhmDTO.AgentModel.class);
                List<OhmDTO.Finding> findings = signals.analyze(graph);

                Map<String, Integer> breakdown = new Map<String, Integer>();
                for (OhmDTO.Finding f : findings) {
                    String key = (f.signalType == null) ? 'UNKNOWN' : f.signalType;
                    Integer n = breakdown.get(key);
                    breakdown.put(key, (n == null) ? 1 : n + 1);
                }

                resp.findingsCount = findings.size();
                resp.findingsJson = JSON.serialize(findings);
                resp.signalBreakdownJson = JSON.serialize(breakdown);
                resp.summary = (findings.isEmpty())
                    ? 'No waste signals fired — the inspected agent surface is clean on all four signals.'
                    : 'Detected ' + findings.size() + ' waste finding(s) across ' + breakdown.size() +
                      ' signal type(s): ' + String.join(new List<String>(breakdown.keySet()), ', ') + '.';
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
            description='Id of the Agent Audit Report whose saved discovery graph should be analyzed when Graph JSON is blank.'
            required=false)
        public String reportId;
        @InvocableVariable(
            label='Graph JSON'
            description='Serialized discovery graph from Discover Agentic Work. Leave blank to reload it from the report.'
            required=false)
        public String graphJson;
    }

    public class Response {
        @InvocableVariable(label='Findings Count' description='Total number of waste findings detected.')
        public Integer findingsCount;
        @InvocableVariable(label='Findings JSON' description='Serialized list of findings. Pass through to Recommend Improvements; do not parse.')
        public String findingsJson;
        @InvocableVariable(label='Signal Breakdown JSON' description='JSON map of signal type to finding count.')
        public String signalBreakdownJson;
        @InvocableVariable(label='Summary' description='Natural-language result of the signal analysis.')
        public String summary;
    }
}
