/**
 * OhmDTO — shared data-transfer objects for the Ohm sustainability auditor.
 * SPEC §S.0. All inner classes are @AuraEnabled (LWC) and JSON.serialize-safe.
 * Canon: C0 (AgentModel == OhmGraph), C3 ({Low,Central,High} vocabulary), C12 (one RemediationInputDTO).
 */
public with sharing class OhmDTO {

    // ----- Discovery graph (in-memory AgentModel, not persisted) — C0 -----
    public class AgentModel {
        @AuraEnabled public Map<String, AgentNode> agentsById;
        @AuraEnabled public List<TopicNode> topics;
        @AuraEnabled public List<ActionNode> actions;
        @AuraEnabled public Map<String, List<TopicNode>> topicsByPlanner;
        @AuraEnabled public Map<String, List<ActionNode>> actionsByPlugin;
        @AuraEnabled public Map<String, List<ActionNode>> actionsByPlanner;
        @AuraEnabled public List<String> discoveryErrors;
        @AuraEnabled public Integer promptTemplateCount;

        public AgentModel() {
            this.agentsById = new Map<String, AgentNode>();
            this.topics = new List<TopicNode>();
            this.actions = new List<ActionNode>();
            this.topicsByPlanner = new Map<String, List<TopicNode>>();
            this.actionsByPlugin = new Map<String, List<ActionNode>>();
            this.actionsByPlanner = new Map<String, List<ActionNode>>();
            this.discoveryErrors = new List<String>();
            this.promptTemplateCount = 0;
        }
    }

    public class AgentNode {
        @AuraEnabled public String id;
        @AuraEnabled public String developerName;
        @AuraEnabled public String masterLabel;
        @AuraEnabled public String description;
        @AuraEnabled public String plannerType;
        @AuraEnabled public String capabilities;
        @AuraEnabled public String agentGraphJson;
    }

    public class TopicNode {
        @AuraEnabled public String id;
        @AuraEnabled public String developerName;
        @AuraEnabled public String masterLabel;
        @AuraEnabled public String description;
        @AuraEnabled public String scope;
        @AuraEnabled public String pluginType;
        @AuraEnabled public String plannerId;
        @AuraEnabled public String parentId;
        @AuraEnabled public Boolean isLocal;
    }

    public class ActionNode {
        @AuraEnabled public String id;
        @AuraEnabled public String developerName;
        @AuraEnabled public String masterLabel;
        @AuraEnabled public String description;
        @AuraEnabled public String invocationTargetType;
        @AuraEnabled public String invocationTarget;
        @AuraEnabled public String pluginId;
        @AuraEnabled public String plannerId;
        @AuraEnabled public Boolean isLocal;
        @AuraEnabled public String boundModel;
        @AuraEnabled public Boolean modelAssumed;
    }

    // ----- Finding (service-internal, maps 1:1 to Finding__c) -----
    public class Finding {
        @AuraEnabled public String signalType;
        @AuraEnabled public String severity;
        @AuraEnabled public String confidence;
        @AuraEnabled public String artifactType;
        @AuraEnabled public String artifactApiName;
        @AuraEnabled public String artifactLabel;
        @AuraEnabled public String artifactToolingId;
        @AuraEnabled public String parentAgentApiName;
        @AuraEnabled public String parentTopicApiName;
        @AuraEnabled public String evidence;
        @AuraEnabled public Decimal metricValue;
        @AuraEnabled public String metricUnit;
        @AuraEnabled public Decimal severityScore; // internal 0-1 detector score (drives rate())
        @AuraEnabled public FootprintResponse footprint;
        @AuraEnabled public FootprintResponse savings;
        @AuraEnabled public String fixType;
        @AuraEnabled public String recommendedTarget;
        @AuraEnabled public String recommendationText;
        @AuraEnabled public String agentNarrative;
        @AuraEnabled public String generatedBy;
        @AuraEnabled public String effort;
        @AuraEnabled public Id findingRecordId;
    }

    // ----- Footprint -----
    public class FootprintRequest {
        @AuraEnabled public String artifactId;
        @AuraEnabled public String artifactType;
        @AuraEnabled public String boundModel;
        @AuraEnabled public Decimal tokensPerInference;
        @AuraEnabled public Decimal annualCalls;
        @AuraEnabled public Boolean modelAssumed;
        @AuraEnabled public String scenarioLabel;
    }

    public class FootprintResponse {
        @AuraEnabled public Decimal energyWhLow;
        @AuraEnabled public Decimal energyWhCentral;
        @AuraEnabled public Decimal energyWhHigh;
        @AuraEnabled public Decimal waterMlLow;
        @AuraEnabled public Decimal waterMlCentral;
        @AuraEnabled public Decimal waterMlHigh;
        @AuraEnabled public Decimal co2eGLow;
        @AuraEnabled public Decimal co2eGCentral;
        @AuraEnabled public Decimal co2eGHigh;
        @AuraEnabled public Decimal annualCalls;
        @AuraEnabled public Decimal perInferenceWh;
        @AuraEnabled public Boolean telemetryBacked;
        @AuraEnabled public String confidence;
        @AuraEnabled public Map<String, Object> assumptions;
    }

    // ----- Volume (C6) -----
    public class VolumeInput {
        @AuraEnabled public Decimal sessionsPerPeriod;
        @AuraEnabled public Decimal turnsPerSession;
        @AuraEnabled public Decimal callsPerTurn;
        @AuraEnabled public Decimal periodsPerYear;
        @AuraEnabled public String scenarioLabel;
    }

    // ----- Efficiency -----
    public class EfficiencyResult {
        @AuraEnabled public Integer score;
        @AuraEnabled public String grade;
        @AuraEnabled public Decimal weightedSeveritySum;
        @AuraEnabled public Decimal maxPossible;
        @AuraEnabled public Integer deterministicActionCount;
        @AuraEnabled public Integer withinBudgetInstructionCount;
    }

    // ----- Cross-boundary contract DTOs -----
    public class AuditReadoutDTO {
        @AuraEnabled public Id reportId;
        @AuraEnabled public String runStatus;
        @AuraEnabled public String stageMessage;
        @AuraEnabled public Integer percentComplete;
        @AuraEnabled public Integer agentsDiscovered;
        @AuraEnabled public Integer topicsDiscovered;
        @AuraEnabled public Integer actionsDiscovered;
        @AuraEnabled public Integer promptTemplatesDiscovered;
        @AuraEnabled public String efficiencyGrade;
        @AuraEnabled public Integer efficiencyScore;
        @AuraEnabled public String methodologyVersion;
        @AuraEnabled public Decimal orgEnergyWhLow;
        @AuraEnabled public Decimal orgEnergyWhCentral;
        @AuraEnabled public Decimal orgEnergyWhHigh;
        @AuraEnabled public Decimal orgWaterMlLow;
        @AuraEnabled public Decimal orgWaterMlCentral;
        @AuraEnabled public Decimal orgWaterMlHigh;
        @AuraEnabled public Decimal orgCo2eGLow;
        @AuraEnabled public Decimal orgCo2eGCentral;
        @AuraEnabled public Decimal orgCo2eGHigh;
        @AuraEnabled public Decimal orgEnergySavingsWhLow;
        @AuraEnabled public Decimal orgEnergySavingsWhCentral;
        @AuraEnabled public Decimal orgEnergySavingsWhHigh;
        @AuraEnabled public Boolean telemetryBacked;
        @AuraEnabled public VolumeInput volumeAssumption;
        @AuraEnabled public Map<String, Object> assumptions;
        @AuraEnabled public List<FindingDTO> findings;
        @AuraEnabled public String discoveryErrors;
    }

    public class FindingDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String signal;
        @AuraEnabled public String severity;
        @AuraEnabled public String confidence;
        @AuraEnabled public String artifactType;
        @AuraEnabled public TargetArtifact targetArtifact;
        @AuraEnabled public String evidence;
        @AuraEnabled public Decimal metricValue;
        @AuraEnabled public String metricUnit;
        @AuraEnabled public Decimal energyWhLow;
        @AuraEnabled public Decimal energyWhCentral;
        @AuraEnabled public Decimal energyWhHigh;
        @AuraEnabled public Decimal waterMlLow;
        @AuraEnabled public Decimal waterMlCentral;
        @AuraEnabled public Decimal waterMlHigh;
        @AuraEnabled public Decimal co2eGLow;
        @AuraEnabled public Decimal co2eGCentral;
        @AuraEnabled public Decimal co2eGHigh;
        @AuraEnabled public Decimal estimatedAnnualCalls;
        @AuraEnabled public Decimal perInferenceWh;
        @AuraEnabled public Decimal estimatedSavingsLow;
        @AuraEnabled public Decimal estimatedSavingsCentral;
        @AuraEnabled public Decimal estimatedSavingsHigh;
        @AuraEnabled public String fixType;
        @AuraEnabled public String recommendedTarget;
        @AuraEnabled public String recommendationText;
        @AuraEnabled public String agentNarrative;
        @AuraEnabled public String generatedBy;
        @AuraEnabled public String effort;
        @AuraEnabled public String recStatus;
        @AuraEnabled public String remediationTaskId;
    }

    public class TargetArtifact {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String toolingId;
        @AuraEnabled public String parentAgentApiName;
        @AuraEnabled public String parentTopicApiName;
    }

    // C12 — the single F8 remediation input
    public class RemediationInputDTO {
        @AuraEnabled public Id findingId;
        @AuraEnabled public Id reportId;
        @AuraEnabled public String fixType;
        @AuraEnabled public String recommendedTarget;
        @AuraEnabled public String recommendationText;
        @AuraEnabled public Decimal estimatedSavingsCentralWh;
        @AuraEnabled public String note;
    }

    public class AgentNarrativeInput {
        @AuraEnabled public Id findingId;
        @AuraEnabled public String narrative;
        @AuraEnabled public Integer rank;
    }

    // ----- v2 Workbench (SPEC-ohm-v2-workbench §4) — Fleet + per-process views -----

    /** Fleet-table row: cheap discovery counts, joined with the latest process report (if any). */
    public class ProcessSummaryDTO {
        @AuraEnabled public Id plannerId;
        @AuraEnabled public String plannerApiName;
        @AuraEnabled public String label;
        @AuraEnabled public String domain;
        @AuraEnabled public Integer topicCount;
        @AuraEnabled public Integer actionCount;
        @AuraEnabled public Boolean audited;
        @AuraEnabled public String grade;
        @AuraEnabled public Integer score;
        @AuraEnabled public Decimal energyWhCentral;
        @AuraEnabled public Id latestReportId;
        @AuraEnabled public Datetime lastAudited;
    }

    /** Process page payload: latest report findings + the agent/topic/action node list. */
    public class ProcessDetailDTO {
        @AuraEnabled public Id plannerId;
        @AuraEnabled public String plannerApiName;
        @AuraEnabled public String label;
        @AuraEnabled public String domain;
        @AuraEnabled public String grade;
        @AuraEnabled public Integer score;
        @AuraEnabled public Decimal energyWhCentral;
        @AuraEnabled public Id reportId;
        @AuraEnabled public List<FindingDTO> findings;   // reuse existing FindingDTO
        @AuraEnabled public List<NodeDTO> nodes;         // graph nodes (agent/topic/action)
    }

    /** One graph node in a process subtree (agent, topic, or action). */
    public class NodeDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String nodeType;             // 'Agent' | 'Topic' | 'Action'
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String parentId;
        @AuraEnabled public String invocationTargetType; // for actions
        @AuraEnabled public String instructions;         // topic Scope / agent instructions (raw)
        @AuraEnabled public Integer tokenCount;
        @AuraEnabled public Boolean wasteful;
        @AuraEnabled public String signalType;
        @AuraEnabled public String severity;
    }

    // ----- Wave 4 Worklist (Findings backlog + Recommendations quick-wins) -----

    /** One row of the cross-fleet worklist: a finding joined with its remediation Task (if any). */
    public class WorklistItemDTO {
        @AuraEnabled public Id findingId;
        @AuraEnabled public String signal;
        @AuraEnabled public String severity;
        @AuraEnabled public String confidence;
        @AuraEnabled public String processLabel;
        @AuraEnabled public String plannerApiName;
        @AuraEnabled public String artifactLabel;
        @AuraEnabled public Decimal savingsCentralWh;
        @AuraEnabled public Decimal savingsLowWh;
        @AuraEnabled public Decimal savingsHighWh;
        @AuraEnabled public String fixType;
        @AuraEnabled public String recommendedTarget;
        @AuraEnabled public String recommendationText;
        @AuraEnabled public String findingStatus;   // Finding_Status__c: Open|Accepted|Dismissed|Applied
        @AuraEnabled public Id taskId;
        @AuraEnabled public String assigneeName;
        @AuraEnabled public Id assigneeId;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String effort;
    }

    // ----- Wave 5 Trends + before/after diff (SPEC §2.5 / §2.6) -----

    /** One audit report reduced to a plottable point (chronological in a TrendDTO). */
    public class TrendPointDTO {
        @AuraEnabled public Datetime auditedAt;
        @AuraEnabled public String grade;
        @AuraEnabled public Integer score;
        @AuraEnabled public Decimal energyWhCentral;
        @AuraEnabled public Integer findingsCount;
        @AuraEnabled public Id reportId;
    }

    /** A time series of audits for one scope (org-wide or one process). */
    public class TrendDTO {
        @AuraEnabled public String scope;                 // 'Org' or a process label
        @AuraEnabled public Id plannerId;                 // null for org-wide
        @AuraEnabled public List<TrendPointDTO> points;   // chronological (oldest->newest)
        @AuraEnabled public Decimal firstEnergyWhCentral;
        @AuraEnabled public Decimal lastEnergyWhCentral;
        @AuraEnabled public Decimal realizedSavingsWh;    // max(0, first - last)
        @AuraEnabled public List<AgentGradeHistoryDTO> perAgent; // org scope only
    }

    /** Per-planner grade timeline for the org-wide Trends view. */
    public class AgentGradeHistoryDTO {
        @AuraEnabled public Id plannerId;
        @AuraEnabled public String label;
        @AuraEnabled public List<String> gradeHistory;    // chronological (oldest->newest)
        @AuraEnabled public String currentGrade;
    }

    /** Before/after comparison of the two most recent process reports for a planner. */
    public class DiffDTO {
        @AuraEnabled public Id plannerId;
        @AuraEnabled public String label;
        @AuraEnabled public Id beforeReportId;
        @AuraEnabled public Datetime beforeAt;
        @AuraEnabled public String beforeGrade;
        @AuraEnabled public Integer beforeScore;
        @AuraEnabled public Decimal beforeEnergyWhCentral;
        @AuraEnabled public Integer beforeFindings;
        @AuraEnabled public Id afterReportId;
        @AuraEnabled public Datetime afterAt;
        @AuraEnabled public String afterGrade;
        @AuraEnabled public Integer afterScore;
        @AuraEnabled public Decimal afterEnergyWhCentral;
        @AuraEnabled public Integer afterFindings;
        @AuraEnabled public Decimal energyDeltaWh;        // before - after (positive = improvement)
        @AuraEnabled public Integer scoreDelta;
        @AuraEnabled public Integer findingsDelta;
        @AuraEnabled public String beforeInstructions;    // topic Scope snapshot (may be null)
        @AuraEnabled public String afterInstructions;     // topic Scope snapshot (may be null)
        @AuraEnabled public Boolean improved;             // afterScore > beforeScore
    }
}
