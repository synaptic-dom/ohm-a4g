/** Atomic completion of acquired source, validated reviewer output and deterministic analysis. */
public with sharing class OhmAuditRunService {
    /** Compatibility entry for explicit deterministic fixtures; app audits pass a validated review. */
    public static void finish(Id reportId, OhmDTO.AgentModel graph) {
        finish(reportId, graph, null);
    }
    public static void finish(Id reportId, OhmDTO.AgentModel graph, String reviewJson) {
        Agent_Audit_Report__c report = [
            SELECT Id, Run_Status__c FROM Agent_Audit_Report__c WHERE Id = :reportId FOR UPDATE
        ];
        if (report.Run_Status__c == 'Complete') return;
        if (reviewJson != null) {
            if (String.isBlank(reviewJson) || reviewJson.length() > 131072) {
                throw new OhmPersistenceService.OhmPersistenceException('The environmental review exceeds its supported storage size. No truncated review was saved.');
            }
            Map<String, Object> summary = (Map<String, Object>) JSON.deserializeUntyped(reviewJson);
            summary.put('artifacts', new List<Object>());
            summary.put('summaryOnly', true);
            String compact = JSON.serialize(summary);
            if (compact.length() > 32768) {
                throw new OhmPersistenceService.OhmPersistenceException('The review summary exceeds its supported storage size. No truncated review was saved.');
            }
            update new Agent_Audit_Report__c(Id = reportId, Review_Result__c = reviewJson, Review_Summary__c = compact);
        }
        OhmPersistenceService persistence = new OhmPersistenceService();
        OhmSignalService signals = new OhmSignalService();
        List<OhmDTO.Finding> findings = signals.analyze(graph);
        OhmFootprintService footprint = new OhmFootprintService();
        OhmDTO.VolumeInput volume = new AssumptionVolumeProvider().defaultVolume();
        for (OhmDTO.Finding finding : findings) {
            finding.footprint = finding.reviewRequired == true ? null : footprint.estimateForArtifact(finding, volume);
        }
        new OhmRecommendationService().attachRecommendations(findings);
        OhmDTO.EfficiencyResult rating = signals.rate(graph, findings);
        persistence.persistFindings(reportId, graph, findings, rating);
        OhmAuditImpactService.save(reportId, graph, findings, volume);
        persistence.updateProgress(reportId, 'Complete', reviewJson != null
            ? 'Salesforce review complete; category ratings ready'
            : graph.coverageComplete == true ? 'Audit complete' : 'Audit complete with coverage gaps', 100);
    }
}
