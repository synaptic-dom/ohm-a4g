/**
 * DiscoverAgenticWork — agent-door invocable action (SPEC §S.11, canon C4/C5/C13).
 * Thin marshaller: ensures an Agent_Audit_Report__c exists (blank reportId => create),
 * runs OhmDiscoveryService.discover() (inline SOQL per C13 — no callout), persists the
 * discovery graph on the report (C11), and returns counts + graphJson for the agent.
 * Re-entrant, keyed by reportId. Same service methods the aura door calls (C5).
 */
public with sharing class DiscoverAgenticWork {

    @InvocableMethod(
        label='Discover Agentic Work'
        description='Inventories every Agentforce agent, topic, and action in this org and saves the discovery graph onto an Agent Audit Report. Pass an existing report Id to reuse a report, or leave it blank to start a new audit. Returns the report Id, inventory counts, and the discovery graph JSON.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return out;
        }

        // Discover ONCE per invocation: the org inventory is identical for every request
        // in the batch, so discovery's 3 SOQL queries stay outside the loop (bulk-safe).
        OhmDTO.AgentModel graph;
        String discoverError;
        try {
            graph = new OhmDiscoveryService().discover();
        } catch (Exception e) {
            discoverError = e.getMessage();
        }
        String graphJson = (graph == null) ? null : JSON.serialize(graph);
        OhmPersistenceService persistence = new OhmPersistenceService();

        // Agentforce invokes with exactly one Request per call; the loop exists only for
        // Flow bulk compatibility. Report creation/graph save delegate to the persistence
        // service, which owns the (single-row) DML.
        for (Request r : requests) {
            Response resp = new Response();
            try {
                if (discoverError != null) {
                    resp.summary = 'Error: discovery failed — ' + discoverError;
                    out.add(resp);
                    continue;
                }
                String rawId = (r == null) ? null : r.reportId;
                Id reportId = String.isBlank(rawId)
                    ? persistence.createReport()
                    : Id.valueOf(rawId.trim());
                persistence.saveDiscoveryGraph(reportId, graph);

                resp.reportId = reportId;
                resp.agentCount = (graph.agentsById == null) ? 0 : graph.agentsById.size();
                resp.topicCount = (graph.topics == null) ? 0 : graph.topics.size();
                resp.actionCount = (graph.actions == null) ? 0 : graph.actions.size();
                resp.promptTemplateCount = (graph.promptTemplateCount == null) ? 0 : graph.promptTemplateCount;
                resp.graphJson = graphJson;

                Integer errCount = (graph.discoveryErrors == null) ? 0 : graph.discoveryErrors.size();
                resp.summary = 'Discovered ' + resp.agentCount + ' agent(s), ' + resp.topicCount +
                    ' topic(s), ' + resp.actionCount + ' action(s), and ' + resp.promptTemplateCount +
                    ' prompt template(s). Discovery graph saved to report ' + resp.reportId + '.' +
                    (errCount > 0 ? ' Note: ' + errCount + ' partial discovery error(s) were tolerated.' : '');
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
            description='Id of an existing Agent Audit Report to reuse. Leave blank to create a new report for this audit run.'
            required=false)
        public String reportId;
    }

    public class Response {
        @InvocableVariable(label='Report Id' description='Id of the Agent Audit Report holding this discovery run.')
        public String reportId;
        @InvocableVariable(label='Agent Count' description='Number of agents (GenAiPlannerDefinition) discovered.')
        public Integer agentCount;
        @InvocableVariable(label='Topic Count' description='Number of topics (GenAiPluginDefinition) discovered.')
        public Integer topicCount;
        @InvocableVariable(label='Action Count' description='Number of actions (GenAiFunctionDefinition) discovered.')
        public Integer actionCount;
        @InvocableVariable(label='Prompt Template Count' description='Number of distinct prompt templates referenced by prompt-typed actions.')
        public Integer promptTemplateCount;
        @InvocableVariable(label='Graph JSON' description='Serialized OhmDTO.AgentModel discovery graph. Pass through to Run Waste Signals; do not parse.')
        public String graphJson;
        @InvocableVariable(label='Summary' description='Natural-language result of the discovery step.')
        public String summary;
    }
}
