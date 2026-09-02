/**
 * OhmPersistenceService — persistence layer for audit runs (SPEC §S.9, canon C5/C11/C12).
 * One DML statement per object per method (bulk-safe, no SOQL/DML in loops).
 * reportId == runId (canon: the Agent_Audit_Report__c Id is the run handle).
 */
public with sharing class OhmPersistenceService {

    private static final Integer STAGE_MESSAGE_MAX = 255;
    private static final Integer GRAPH_JSON_MAX = 131072;

    /** Insert a Queued Agent_Audit_Report__c and return its Id (== runId). */
    public Id createReport() {
        Agent_Audit_Report__c report = new Agent_Audit_Report__c(
            Run_Status__c = 'Queued',
            Run_Stage_Message__c = 'Queued',
            Percent_Complete__c = 0,
            Run_Timestamp__c = System.now(),
            Org_Id__c = UserInfo.getOrganizationId()
        );
        insert report;
        return report.Id;
    }

    /**
     * v2 — insert a PROCESS-scoped Agent_Audit_Report__c (Target_Type__c='Process') tagged with
     * the planner it targets, and return its Id (== runId). Existing org-wide fields still apply;
     * persistFindings() later stamps grade/score/Complete without touching the Target_* tags.
     */
    public Id createProcessReport(Id plannerId, String plannerApiName) {
        Agent_Audit_Report__c report = new Agent_Audit_Report__c(
            Run_Status__c = 'Queued',
            Run_Stage_Message__c = 'Queued',
            Percent_Complete__c = 0,
            Run_Timestamp__c = System.now(),
            Org_Id__c = UserInfo.getOrganizationId(),
            Target_Type__c = 'Process',
            Target_Planner_Id__c = (plannerId == null) ? null : String.valueOf(plannerId),
            Target_Planner_Api_Name__c = (plannerApiName == null) ? null : plannerApiName.abbreviate(255)
        );
        insert report;
        return report.Id;
    }

    /** One status/stage/pct update for the polling spine (§2.5). */
    public void updateProgress(Id reportId, String status, String stageMessage, Integer pct) {
        Agent_Audit_Report__c report = new Agent_Audit_Report__c(Id = reportId);
        if (String.isNotBlank(status)) {
            report.Run_Status__c = status;
        }
        if (stageMessage != null) {
            report.Run_Stage_Message__c = stageMessage.abbreviate(STAGE_MESSAGE_MAX);
        }
        if (pct != null) {
            report.Percent_Complete__c = pct;
        }
        update report;
    }

    /** C11 — serialize the discovery graph onto the report for agent re-entrancy. */
    public void saveDiscoveryGraph(Id reportId, OhmDTO.AgentModel g) {
        String graphJson = (g == null) ? null : JSON.serialize(g);
        if (graphJson != null && graphJson.length() > GRAPH_JSON_MAX) {
            graphJson = graphJson.substring(0, GRAPH_JSON_MAX);
        }
        update new Agent_Audit_Report__c(
            Id = reportId,
            Discovery_Graph_Json__c = graphJson
        );
    }

    /**
     * Bulk-insert Finding__c children (one insert) and stamp the report with inventory
     * counts, grade/score and Run_Status__c='Complete' (one update). Rollups compute Total_*.
     */
    public void persistFindings(Id reportId, OhmDTO.AgentModel g,
                                List<OhmDTO.Finding> findings, OhmDTO.EfficiencyResult rating) {
        List<Finding__c> rows = new List<Finding__c>();
        if (findings != null) {
            for (OhmDTO.Finding f : findings) {
                if (f == null) { continue; }
                rows.add(toRecord(reportId, f));
            }
        }
        if (!rows.isEmpty()) {
            insert rows;
            // write the persisted Ids back onto the DTOs (same order as insert)
            Integer i = 0;
            for (OhmDTO.Finding f : findings) {
                if (f == null) { continue; }
                f.findingRecordId = rows[i].Id;
                i++;
            }
        }

        Agent_Audit_Report__c report = new Agent_Audit_Report__c(Id = reportId);
        report.Agents_Discovered__c = (g == null || g.agentsById == null) ? 0 : g.agentsById.size();
        report.Topics_Discovered__c = (g == null || g.topics == null) ? 0 : g.topics.size();
        report.Actions_Discovered__c = (g == null || g.actions == null) ? 0 : g.actions.size();
        report.Prompt_Templates_Discovered__c = (g == null || g.promptTemplateCount == null) ? 0 : g.promptTemplateCount;
        if (g != null && g.discoveryErrors != null && !g.discoveryErrors.isEmpty()) {
            report.Discovery_Errors__c = String.join(g.discoveryErrors, '\n').abbreviate(32768);
        }
        if (rating != null) {
            report.Efficiency_Grade__c = rating.grade;
            report.Efficiency_Score__c = rating.score;
        }
        report.Methodology_Version__c = OhmConstants.load().methodologyVersion();
        report.Run_Status__c = 'Complete';
        report.Run_Stage_Message__c = 'Audit complete';
        report.Percent_Complete__c = 100;
        update report;
    }

    /** Bulk-update Agent_Narrative__c (+ Generated_By__c='Agentforce'); returns rows updated. */
    public Integer writeAgentNarratives(Id reportId, List<OhmDTO.AgentNarrativeInput> narratives) {
        if (narratives == null || narratives.isEmpty()) {
            return 0;
        }
        Map<Id, String> narrativeByFindingId = new Map<Id, String>();
        for (OhmDTO.AgentNarrativeInput n : narratives) {
            if (n != null && n.findingId != null && String.isNotBlank(n.narrative)) {
                narrativeByFindingId.put(n.findingId, n.narrative);
            }
        }
        if (narrativeByFindingId.isEmpty()) {
            return 0;
        }
        // one SOQL: only touch findings that belong to this report
        List<Finding__c> toUpdate = new List<Finding__c>();
        for (Finding__c f : [
            SELECT Id FROM Finding__c
            WHERE Agent_Audit_Report__c = :reportId
              AND Id IN :narrativeByFindingId.keySet()
        ]) {
            f.Agent_Narrative__c = narrativeByFindingId.get(f.Id).abbreviate(32768);
            f.Generated_By__c = 'Agentforce';
            toUpdate.add(f);
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        return toUpdate.size();
    }

    /** C12 — the SINGLE F8 method: insert a standard Task, write Remediation_Task_Id__c back. */
    public Id createRemediationTask(OhmDTO.RemediationInputDTO input) {
        if (input == null || input.findingId == null) {
            throw new OhmPersistenceException('createRemediationTask requires a findingId.');
        }
        String fixLabel = String.isBlank(input.fixType) ? 'Apply recommendation' : input.fixType.replace('_', ' ');
        String subjectTarget = String.isBlank(input.recommendedTarget) ? '' : (' → ' + input.recommendedTarget);
        List<String> descParts = new List<String>();
        if (String.isNotBlank(input.recommendationText)) {
            descParts.add(input.recommendationText);
        }
        if (input.estimatedSavingsCentralWh != null) {
            descParts.add('Estimated annual energy savings (central): ' + input.estimatedSavingsCentralWh + ' Wh (modeled, telemetryBacked=false).');
        }
        if (String.isNotBlank(input.note)) {
            descParts.add('Note: ' + input.note);
        }
        descParts.add('Source finding: ' + input.findingId);
        if (input.reportId != null) {
            descParts.add('Audit report: ' + input.reportId);
        }

        // C12: the Task is tied to the audit report via WhatId (activities enabled
        // on Agent_Audit_Report__c); Ids are also echoed in the description.
        Task remediation = new Task(
            Subject = ('Ohm: ' + fixLabel + subjectTarget).abbreviate(255),
            Description = String.join(descParts, '\n\n').abbreviate(32000),
            Status = 'Not Started',
            Priority = 'Normal',
            OwnerId = UserInfo.getUserId(),
            WhatId = input.reportId
        );
        insert remediation;

        update new Finding__c(
            Id = input.findingId,
            Remediation_Task_Id__c = remediation.Id
        );
        return remediation.Id;
    }

    /** One report + child findings query → the full AuditReadoutDTO. */
    public OhmDTO.AuditReadoutDTO loadReadout(Id reportId) {
        Agent_Audit_Report__c report = [
            SELECT Id, Run_Status__c, Run_Stage_Message__c, Percent_Complete__c,
                   Agents_Discovered__c, Topics_Discovered__c, Actions_Discovered__c,
                   Prompt_Templates_Discovered__c, Efficiency_Grade__c, Efficiency_Score__c,
                   Methodology_Version__c, Discovery_Errors__c,
                   (SELECT Id, Signal_Type__c, Severity__c, Confidence__c, Artifact_Type__c,
                           Artifact_Api_Name__c, Artifact_Label__c, Artifact_Tooling_Id__c,
                           Parent_Agent_Api_Name__c, Parent_Topic_Api_Name__c,
                           Evidence__c, Metric_Value__c, Metric_Unit__c,
                           Annual_Energy_Wh_Low__c, Annual_Energy_Wh_Central__c, Annual_Energy_Wh_High__c,
                           Annual_Water_mL_Low__c, Annual_Water_mL_Central__c, Annual_Water_mL_High__c,
                           Annual_CO2e_g_Low__c, Annual_CO2e_g_Central__c, Annual_CO2e_g_High__c,
                           Estimated_Annual_Calls__c, Per_Inference_Wh__c,
                           Annual_Energy_Savings_Wh_Low__c, Annual_Energy_Savings_Wh__c, Annual_Energy_Savings_Wh_High__c,
                           Fix_Type__c, Recommended_Target__c, Recommendation_Text__c,
                           Agent_Narrative__c, Generated_By__c, Effort__c, Rec_Status__c,
                           Remediation_Task_Id__c
                    FROM Findings__r)
            FROM Agent_Audit_Report__c
            WHERE Id = :reportId
            LIMIT 1
        ];

        OhmConstants c = OhmConstants.load();
        OhmDTO.AuditReadoutDTO dto = new OhmDTO.AuditReadoutDTO();
        dto.reportId = report.Id;
        dto.runStatus = report.Run_Status__c;
        dto.stageMessage = report.Run_Stage_Message__c;
        dto.percentComplete = (report.Percent_Complete__c == null) ? 0 : Integer.valueOf(report.Percent_Complete__c);
        dto.agentsDiscovered = intOf(report.Agents_Discovered__c);
        dto.topicsDiscovered = intOf(report.Topics_Discovered__c);
        dto.actionsDiscovered = intOf(report.Actions_Discovered__c);
        dto.promptTemplatesDiscovered = intOf(report.Prompt_Templates_Discovered__c);
        dto.efficiencyGrade = report.Efficiency_Grade__c;
        dto.efficiencyScore = (report.Efficiency_Score__c == null) ? null : Integer.valueOf(report.Efficiency_Score__c);
        dto.methodologyVersion = report.Methodology_Version__c;
        dto.discoveryErrors = report.Discovery_Errors__c;
        dto.telemetryBacked = false;
        dto.volumeAssumption = c.defaultVolume();
        OhmConstants.Band energy = c.energyPerPromptWh();
        OhmConstants.Band grid = c.gridIntensityGco2ePerWh();
        OhmConstants.Band water = c.waterMlPerWh();
        dto.assumptions = new Map<String, Object>{
            'energyPerPromptWh' => new Map<String, Object>{ 'low' => energy.low, 'central' => energy.central, 'high' => energy.high },
            'gridIntensityGco2ePerWh' => new Map<String, Object>{ 'low' => grid.low, 'central' => grid.central, 'high' => grid.high },
            'waterMlPerWh' => new Map<String, Object>{ 'low' => water.low, 'central' => water.central, 'high' => water.high },
            'referencePromptTokens' => c.referencePromptTokens(),
            'telemetryBacked' => false,
            'methodologyVersion' => c.methodologyVersion()
        };

        dto.orgEnergyWhLow = 0; dto.orgEnergyWhCentral = 0; dto.orgEnergyWhHigh = 0;
        dto.orgWaterMlLow = 0; dto.orgWaterMlCentral = 0; dto.orgWaterMlHigh = 0;
        dto.orgCo2eGLow = 0; dto.orgCo2eGCentral = 0; dto.orgCo2eGHigh = 0;
        dto.orgEnergySavingsWhLow = 0; dto.orgEnergySavingsWhCentral = 0; dto.orgEnergySavingsWhHigh = 0;

        dto.findings = new List<OhmDTO.FindingDTO>();
        for (Finding__c f : report.Findings__r) {
            dto.findings.add(toFindingDTO(f));
            dto.orgEnergyWhLow += nz(f.Annual_Energy_Wh_Low__c);
            dto.orgEnergyWhCentral += nz(f.Annual_Energy_Wh_Central__c);
            dto.orgEnergyWhHigh += nz(f.Annual_Energy_Wh_High__c);
            dto.orgWaterMlLow += nz(f.Annual_Water_mL_Low__c);
            dto.orgWaterMlCentral += nz(f.Annual_Water_mL_Central__c);
            dto.orgWaterMlHigh += nz(f.Annual_Water_mL_High__c);
            dto.orgCo2eGLow += nz(f.Annual_CO2e_g_Low__c);
            dto.orgCo2eGCentral += nz(f.Annual_CO2e_g_Central__c);
            dto.orgCo2eGHigh += nz(f.Annual_CO2e_g_High__c);
            dto.orgEnergySavingsWhLow += nz(f.Annual_Energy_Savings_Wh_Low__c);
            dto.orgEnergySavingsWhCentral += nz(f.Annual_Energy_Savings_Wh__c);
            dto.orgEnergySavingsWhHigh += nz(f.Annual_Energy_Savings_Wh_High__c);
        }
        return dto;
    }

    // ---------- private mapping helpers ----------

    private Finding__c toRecord(Id reportId, OhmDTO.Finding f) {
        Finding__c row = new Finding__c(
            Agent_Audit_Report__c = reportId,
            Signal_Type__c = f.signalType,
            Severity__c = f.severity,
            Confidence__c = f.confidence,
            Artifact_Type__c = f.artifactType,
            Artifact_Api_Name__c = f.artifactApiName,
            Artifact_Label__c = f.artifactLabel,
            Artifact_Tooling_Id__c = f.artifactToolingId,
            Parent_Agent_Api_Name__c = f.parentAgentApiName,
            Parent_Topic_Api_Name__c = f.parentTopicApiName,
            Evidence__c = (f.evidence == null) ? null : f.evidence.abbreviate(32768),
            Metric_Value__c = f.metricValue,
            Metric_Unit__c = f.metricUnit,
            Fix_Type__c = f.fixType,
            Recommended_Target__c = f.recommendedTarget,
            Recommendation_Text__c = (f.recommendationText == null) ? null : f.recommendationText.abbreviate(32768),
            Agent_Narrative__c = (f.agentNarrative == null) ? null : f.agentNarrative.abbreviate(32768),
            Generated_By__c = String.isBlank(f.generatedBy) ? 'Deterministic' : f.generatedBy,
            Effort__c = f.effort,
            Rec_Status__c = 'Proposed'
        );
        if (f.footprint != null) {
            row.Annual_Energy_Wh_Low__c = f.footprint.energyWhLow;
            row.Annual_Energy_Wh_Central__c = f.footprint.energyWhCentral;
            row.Annual_Energy_Wh_High__c = f.footprint.energyWhHigh;
            row.Annual_Water_mL_Low__c = f.footprint.waterMlLow;
            row.Annual_Water_mL_Central__c = f.footprint.waterMlCentral;
            row.Annual_Water_mL_High__c = f.footprint.waterMlHigh;
            row.Annual_CO2e_g_Low__c = f.footprint.co2eGLow;
            row.Annual_CO2e_g_Central__c = f.footprint.co2eGCentral;
            row.Annual_CO2e_g_High__c = f.footprint.co2eGHigh;
            row.Estimated_Annual_Calls__c = f.footprint.annualCalls;
            row.Per_Inference_Wh__c = f.footprint.perInferenceWh;
        }
        if (f.savings != null) {
            row.Annual_Energy_Savings_Wh_Low__c = f.savings.energyWhLow;
            row.Annual_Energy_Savings_Wh__c = f.savings.energyWhCentral;
            row.Annual_Energy_Savings_Wh_High__c = f.savings.energyWhHigh;
        }
        return row;
    }

    private OhmDTO.FindingDTO toFindingDTO(Finding__c f) {
        OhmDTO.FindingDTO d = new OhmDTO.FindingDTO();
        d.id = f.Id;
        d.signal = f.Signal_Type__c;
        d.severity = f.Severity__c;
        d.confidence = f.Confidence__c;
        d.artifactType = f.Artifact_Type__c;
        OhmDTO.TargetArtifact t = new OhmDTO.TargetArtifact();
        t.apiName = f.Artifact_Api_Name__c;
        t.label = f.Artifact_Label__c;
        t.toolingId = f.Artifact_Tooling_Id__c;
        t.parentAgentApiName = f.Parent_Agent_Api_Name__c;
        t.parentTopicApiName = f.Parent_Topic_Api_Name__c;
        d.targetArtifact = t;
        d.evidence = f.Evidence__c;
        d.metricValue = f.Metric_Value__c;
        d.metricUnit = f.Metric_Unit__c;
        d.energyWhLow = f.Annual_Energy_Wh_Low__c;
        d.energyWhCentral = f.Annual_Energy_Wh_Central__c;
        d.energyWhHigh = f.Annual_Energy_Wh_High__c;
        d.waterMlLow = f.Annual_Water_mL_Low__c;
        d.waterMlCentral = f.Annual_Water_mL_Central__c;
        d.waterMlHigh = f.Annual_Water_mL_High__c;
        d.co2eGLow = f.Annual_CO2e_g_Low__c;
        d.co2eGCentral = f.Annual_CO2e_g_Central__c;
        d.co2eGHigh = f.Annual_CO2e_g_High__c;
        d.estimatedAnnualCalls = f.Estimated_Annual_Calls__c;
        d.perInferenceWh = f.Per_Inference_Wh__c;
        d.estimatedSavingsLow = f.Annual_Energy_Savings_Wh_Low__c;
        d.estimatedSavingsCentral = f.Annual_Energy_Savings_Wh__c;
        d.estimatedSavingsHigh = f.Annual_Energy_Savings_Wh_High__c;
        d.fixType = f.Fix_Type__c;
        d.recommendedTarget = f.Recommended_Target__c;
        d.recommendationText = f.Recommendation_Text__c;
        d.agentNarrative = f.Agent_Narrative__c;
        d.generatedBy = f.Generated_By__c;
        d.effort = f.Effort__c;
        d.recStatus = f.Rec_Status__c;
        d.remediationTaskId = f.Remediation_Task_Id__c;
        return d;
    }

    private Integer intOf(Decimal d) {
        return (d == null) ? 0 : Integer.valueOf(d);
    }

    private Decimal nz(Decimal d) {
        return (d == null) ? 0 : d;
    }

    public class OhmPersistenceException extends Exception {}
}
