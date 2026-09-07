/** Durable, bounded source acquisition. A worker performs callouts before its first DML. */
public with sharing class OhmAuditCoordinator {
    // Covers bounded retrieval polling/retries in Developer orgs, whose default is five jobs.
    @TestVisible private static final Integer MAX_JOB_EXECUTIONS = 200;
    public class AuditRunException extends Exception {}
    public class RunState {
        public String phase = 'Start';
        public List<String> plannerIds = new List<String>();
        public Map<String, String> plannerFingerprints = new Map<String, String>();
        public String inventoryFingerprint;
        public Integer plannerIndex = 0;
        public Integer polls = 0;
        public Integer retries = 0;
        public Integer jobExecutions = 0;
        public Datetime deadline;
        public String retrievalJson;
        public Set<Id> sourceIds = new Set<Id>();
        public Map<String, String> completedRetrievalStates = new Map<String, String>();
    }
    public class RetrievalOutcome {
        public Boolean pending;
        public String stateJson;
        public OhmSourceImportService.SourceBundle bundle;
        public List<String> warnings = new List<String>();
    }
    public virtual class RetrievalGateway {
        public virtual void validate(String stateJson) {
            OhmSourceRetrievalService.validateFreshness((OhmSourceRetrievalService.RetrievalState)
                JSON.deserialize(stateJson, OhmSourceRetrievalService.RetrievalState.class));
        }
        public virtual String start(OhmDTO.AgentModel graph) {
            return JSON.serialize(OhmSourceRetrievalService.start(graph));
        }
        public virtual RetrievalOutcome poll(String stateJson, OhmDTO.AgentModel graph) {
            OhmSourceRetrievalService.RetrievalState state = (OhmSourceRetrievalService.RetrievalState)
                JSON.deserialize(stateJson, OhmSourceRetrievalService.RetrievalState.class);
            OhmSourceRetrievalService.RetrievalResult result = OhmSourceRetrievalService.poll(state, graph);
            RetrievalOutcome outcome = new RetrievalOutcome();
            outcome.pending = result.pending;
            outcome.stateJson = JSON.serialize(result.state);
            outcome.bundle = result.bundle;
            outcome.warnings = result.warnings;
            return outcome;
        }
    }
    public virtual class InventoryGateway {
        private OhmDiscoveryService discovery = new OhmDiscoveryService();
        public virtual OhmDTO.AgentModel read(Id plannerId) { return discovery.discoverForRetrieval(plannerId); }
        public virtual String plannerFingerprint(OhmDTO.AgentModel graph, String plannerId) {
            return discovery.plannerFingerprint(graph, plannerId);
        }
        public virtual void attach(OhmDTO.AgentModel graph, Set<Id> sourceIds) {
            discovery.finishRetrievedDiscovery(graph, sourceIds);
        }
    }
    @TestVisible private static RetrievalGateway retrieval = new RetrievalGateway();
    @TestVisible private static InventoryGateway inventory = new InventoryGateway();
    public virtual class ReviewGateway {
        public virtual String review(OhmDTO.AgentModel graph) { return OhmReviewService.review(graph); }
    }
    @TestVisible private static ReviewGateway reviewer = new ReviewGateway();

    public static Id enqueue(Id reportId) {
        Id jobId = System.enqueueJob(new OhmAuditJob(reportId), initialQueueOptions());
        update new Agent_Audit_Report__c(Id = reportId, Async_Job_Id__c = String.valueOf(jobId));
        return jobId;
    }

    @TestVisible private static AsyncOptions initialQueueOptions() {
        AsyncOptions options = new AsyncOptions();
        options.MaximumQueueableStackDepth = MAX_JOB_EXECUTIONS;
        return options;
    }

    /** Each phase commits independently; only finalization writes findings or remediation. */
    public static void advance(Id reportId, Boolean scheduleNext) {
        Agent_Audit_Report__c report = read(reportId, false);
        if (terminal(report.Run_Status__c)) return;
        String observedState = report.Source_Retrieval_Context__c;
        RunState state;
        Savepoint work;
        try {
            Id target = String.isBlank(report.Target_Planner_Id__c) ? null : (Id)report.Target_Planner_Id__c;
            if (String.isBlank(observedState)) {
                OhmDTO.AgentModel graph = inventory.read(target);
                requireInventory(graph);
                state = new RunState();
                state.jobExecutions = 1;
                state.deadline = System.now().addMinutes(20);
                state.inventoryFingerprint = graph.metadataFingerprint;
                state.plannerIds.addAll(graph.agentsById.keySet());
                state.plannerIds.sort();
                for (String plannerId : state.plannerIds) {
                    state.plannerFingerprints.put(plannerId, inventory.plannerFingerprint(graph, plannerId));
                }
                if (state.plannerIds.isEmpty()) state.phase = 'Finalize';
                if (!unchanged(reportId, observedState)) return;
                save(reportId, state, 'Discovering', 'Retrieving published source', 10, scheduleNext, false);
                return;
            }
            state = (RunState)JSON.deserialize(observedState, RunState.class);
            state.jobExecutions = (state.jobExecutions == null ? 0 : state.jobExecutions) + 1;
            if (state.jobExecutions >= MAX_JOB_EXECUTIONS) {
                throw new AuditRunException('Source retrieval exceeded its background job budget. Audit each process separately or start a new run.');
            }
            if (state.deadline == null || System.now() > state.deadline) {
                throw new AuditRunException('Source retrieval timed out. The previous audit is unchanged; start a new run.');
            }
            if (state.phase == 'Finalize') {
                for (String completedState : state.completedRetrievalStates.values()) {
                    if (Limits.getCallouts() >= 80) throw new AuditRunException('This fleet exceeds the source verification capacity. Audit each process separately.');
                    retrieval.validate(completedState);
                }
                OhmDTO.AgentModel graph = inventory.read(target);
                requireInventory(graph);
                if (graph.metadataFingerprint != state.inventoryFingerprint) {
                    throw new AuditRunException('Published metadata changed during retrieval. Refresh the fleet and start a new audit.');
                }
                inventory.attach(graph, state.sourceIds);
                // Review is a real Prompt Builder invocation. Keep every callout before
                // the savepoint/DML, and reject publication changes during generation.
                String reviewJson = reviewer.review(graph);
                if (String.isBlank(reviewJson)) throw new AuditRunException('Salesforce returned no validated environmental review. Start a new audit.');
                for (String completedState : state.completedRetrievalStates.values()) {
                    if (Limits.getCallouts() >= 80) throw new AuditRunException('This fleet exceeds the source verification capacity. Audit each bundle separately.');
                    retrieval.validate(completedState);
                }
                OhmDTO.AgentModel afterReview = inventory.read(target);
                requireInventory(afterReview);
                if (afterReview.metadataFingerprint != state.inventoryFingerprint) {
                    throw new AuditRunException('Published metadata changed during the Salesforce review. Start a new audit.');
                }
                if (!unchanged(reportId, observedState)) return;
                work = Database.setSavepoint();
                OhmAuditRunService.finish(reportId, graph, reviewJson);
                // Context remains available for provenance and support; the run is terminal.
                return;
            }
            if (state.plannerIndex < 0 || state.plannerIndex >= state.plannerIds.size()) {
                throw new AuditRunException('Audit retrieval state is invalid. Start a new audit.');
            }
            String plannerId = state.plannerIds[state.plannerIndex];
            OhmDTO.AgentModel current = inventory.read((Id)plannerId);
            requireInventory(current);
            if (current.metadataFingerprint != state.plannerFingerprints.get(plannerId)) {
                throw new AuditRunException('Published metadata changed during retrieval. Refresh the fleet and start a new audit.');
            }
            String stage = 'Retrieving published source (' + (state.plannerIndex + 1) + ' of ' + state.plannerIds.size() + ')';
            Integer pct = 10 + (state.plannerIndex * 65 / Math.max(1, state.plannerIds.size()));
            if (state.phase == 'Start') {
                // start may call listMetadata/readMetadata/retrieve. No DML has occurred.
                state.retrievalJson = retrieval.start(current);
                state.phase = 'Poll'; state.polls = 0; state.retries = 0;
                if (!unchanged(reportId, observedState)) return;
                save(reportId, state, 'Discovering', stage, pct, scheduleNext, false);
                return;
            }
            if (state.phase != 'Poll') throw new AuditRunException('Unknown retrieval phase. Start a new audit.');
            if (state.polls >= 40) throw new AuditRunException('Salesforce source retrieval exceeded its retry limit. Start a new audit.');
            RetrievalOutcome outcome = retrieval.poll(state.retrievalJson, current);
            state.polls++; state.retries = 0; state.retrievalJson = outcome.stateJson;
            // Re-read after all callouts to reject a publication race before storing evidence.
            OhmDTO.AgentModel verified = inventory.read((Id)plannerId);
            requireInventory(verified);
            if (verified.metadataFingerprint != state.plannerFingerprints.get(plannerId)) {
                throw new AuditRunException('Published metadata changed while retrieving source. Start a new audit.');
            }
            if (!unchanged(reportId, observedState)) return;
            work = Database.setSavepoint();
            if (outcome.pending == true) {
                save(reportId, state, 'Discovering', 'Waiting for Salesforce source retrieval', pct, scheduleNext, state.polls >= 3);
                return;
            }
            if (outcome.bundle == null) throw new AuditRunException('Salesforce returned no verifiable source bundle. Start a new audit.');
            if (outcome.bundle.warnings == null) outcome.bundle.warnings = new List<String>();
            List<String> mergedWarnings = new List<String>();
            Set<String> seenWarnings = new Set<String>();
            for (List<String> warnings : new List<List<String>>{outcome.bundle.warnings, outcome.warnings}) {
                if (warnings == null) continue;
                for (String warning : warnings) {
                    if (!String.isBlank(warning) && seenWarnings.add(warning)) mergedWarnings.add(warning);
                }
            }
            outcome.bundle.warnings = mergedWarnings;
            state.sourceIds.add(OhmSourceImportService.importRetrievedBundle(outcome.bundle, verified));
            state.completedRetrievalStates.put(plannerId, outcome.stateJson);
            state.plannerIndex++; state.polls = 0; state.retrievalJson = null;
            state.phase = state.plannerIndex == state.plannerIds.size() ? 'Finalize' : 'Start';
            save(reportId, state, state.phase == 'Finalize' ? 'Analyzing' : 'Discovering',
                state.phase == 'Finalize' ? 'Reviewing source with Salesforce Prompt Builder' : stage,
                state.phase == 'Finalize' ? 80 : pct + 1, scheduleNext, false);
        } catch (Exception ex) {
            if (work != null) Database.rollback(work);
            String message = safeMessage(ex.getMessage());
            Boolean retryable = ex instanceof OhmSalesforceApi.SourceApiException && ((OhmSalesforceApi.SourceApiException)ex).retryable == true;
            if (state != null && retryable && state.retries < 2) {
                state.retries++;
                if (unchanged(reportId, observedState)) {
                    save(reportId, state, 'Discovering', 'Salesforce temporarily unavailable; retrying source retrieval',
                        10, scheduleNext, true);
                }
            } else if (unchanged(reportId, observedState)) {
                fail(reportId, message);
            }
        }
    }

    private static void requireInventory(OhmDTO.AgentModel graph) {
        if (graph == null || !graph.discoveryErrors.isEmpty()) {
            throw new AuditRunException('Published metadata inventory could not be verified. Check metadata permissions and retry.');
        }
    }
    private static Boolean unchanged(Id reportId, String expectedContext) {
        Agent_Audit_Report__c latest = read(reportId, true);
        return !terminal(latest.Run_Status__c) && latest.Source_Retrieval_Context__c == expectedContext;
    }
    private static Agent_Audit_Report__c read(Id reportId, Boolean lockRow) {
        if (lockRow) return [SELECT Id, Run_Status__c, Target_Planner_Id__c, Source_Retrieval_Context__c
                            FROM Agent_Audit_Report__c WHERE Id = :reportId FOR UPDATE];
        return [SELECT Id, Run_Status__c, Target_Planner_Id__c, Source_Retrieval_Context__c
                FROM Agent_Audit_Report__c WHERE Id = :reportId];
    }
    private static void save(Id reportId, RunState state, String status, String stage, Integer pct,
                             Boolean scheduleNext, Boolean delayed) {
        String serialized = JSON.serialize(state);
        if (serialized.length() > 131072) throw new AuditRunException('Retrieval state exceeds the supported inventory size. Audit one process at a time.');
        Agent_Audit_Report__c report = new Agent_Audit_Report__c(Id = reportId,
            Run_Status__c = status, Run_Stage_Message__c = stage.abbreviate(255),
            Percent_Complete__c = Math.min(95, pct), Source_Retrieval_Context__c = serialized);
        if (scheduleNext) {
            // Descendants inherit the initial maximum; Salesforce prohibits resetting it while chaining.
            Id nextId = delayed ? System.enqueueJob(new OhmAuditJob(reportId), 1) : System.enqueueJob(new OhmAuditJob(reportId));
            report.Async_Job_Id__c = String.valueOf(nextId);
        }
        update report;
    }
    public static void fail(Id reportId, String message) {
        Agent_Audit_Report__c report = read(reportId, true);
        if (terminal(report.Run_Status__c)) return;
        new OhmPersistenceService().updateProgress(reportId, 'Failed', 'Audit failed: ' + safeMessage(message), 100);
    }
    private static Boolean terminal(String status) { return status == 'Complete' || status == 'Failed'; }
    private static String safeMessage(String message) {
        if (String.isBlank(message)) return 'Source acquisition failed. Start a new audit.';
        return message.replaceAll('(?i)Bearer\\s+[^\\s]+', '[redacted]').abbreviate(220);
    }
}
