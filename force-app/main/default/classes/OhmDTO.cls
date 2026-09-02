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
}
