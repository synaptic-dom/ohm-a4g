/**
 * OhmAuditController — the unified @AuraEnabled door (SPEC §S.10, canon C5).
 * Sync pipeline: createReport → discover → saveDiscoveryGraph → analyze → footprint →
 * recommendations → rate → persistFindings → Complete. reportId == runId.
 * "One service, two doors": every method delegates to the same services the agent
 * actions call — the doors can never diverge.
 */
public with sharing class OhmAuditController {

    /** The full synchronous audit pipeline. Returns the reportId (== runId). */
    @AuraEnabled
    public static Id startAudit() {
        OhmPersistenceService persistence = new OhmPersistenceService();
        Id reportId = persistence.createReport();
        try {
            persistence.updateProgress(reportId, 'Discovering', 'Discovering agentic work', 10);
            OhmDTO.AgentModel graph = new OhmDiscoveryService().discover();
            persistence.saveDiscoveryGraph(reportId, graph);

            persistence.updateProgress(reportId, 'Analyzing', 'Running efficiency signals', 40);
            OhmSignalService signals = new OhmSignalService();
            List<OhmDTO.Finding> findings = signals.analyze(graph);

            persistence.updateProgress(reportId, 'Analyzing', 'Estimating footprint and savings', 70);
            OhmFootprintService footprint = new OhmFootprintService();
            OhmDTO.VolumeInput volume = new AssumptionVolumeProvider().defaultVolume();
            for (OhmDTO.Finding f : findings) {
                f.footprint = footprint.estimateForArtifact(f, volume);
            }
            // attachRecommendations fills fixType/recommendationText and savings (savingsFor)
            new OhmRecommendationService().attachRecommendations(findings);

            OhmDTO.EfficiencyResult rating = signals.rate(graph, findings);
            persistence.persistFindings(reportId, graph, findings, rating);
            persistence.updateProgress(reportId, 'Complete', 'Audit complete', 100);
            return reportId;
        } catch (Exception e) {
            try {
                persistence.updateProgress(reportId, 'Failed',
                    ('Audit failed: ' + e.getMessage()), 100);
            } catch (Exception ignored) {
                // best-effort failure stamp; surface the original error below
            }
            throw new AuraHandledException('Audit failed: ' + e.getMessage());
        }
    }

    /** Poll target: status during the run, the full readout once Complete. */
    @AuraEnabled(cacheable=false)
    public static OhmDTO.AuditReadoutDTO getAuditStatus(Id reportId) {
        try {
            return new OhmPersistenceService().loadReadout(reportId);
        } catch (Exception e) {
            throw new AuraHandledException('Could not load audit status: ' + e.getMessage());
        }
    }

    /** F9 Calm Mode — read from the Ohm_Preferences__c hierarchy custom setting. */
    @AuraEnabled(cacheable=true)
    public static Boolean getCalmModePreference() {
        Ohm_Preferences__c prefs = Ohm_Preferences__c.getInstance(UserInfo.getUserId());
        return prefs != null && prefs.Calm_Mode__c == true;
    }

    /** F9 Calm Mode — persist at the current-user level of the hierarchy. */
    @AuraEnabled
    public static void setCalmModePreference(Boolean enabled) {
        try {
            Ohm_Preferences__c prefs = Ohm_Preferences__c.getValues(UserInfo.getUserId());
            if (prefs == null) {
                prefs = new Ohm_Preferences__c(SetupOwnerId = UserInfo.getUserId());
            }
            prefs.Calm_Mode__c = (enabled == true);
            upsert prefs;
        } catch (Exception e) {
            throw new AuraHandledException('Could not save Calm Mode preference: ' + e.getMessage());
        }
    }

    /** F8 — LWC door for remediation; same single service method as the agent door (C12). */
    @AuraEnabled
    public static Id createRemediationTask(OhmDTO.RemediationInputDTO input) {
        try {
            return new OhmPersistenceService().createRemediationTask(input);
        } catch (Exception e) {
            throw new AuraHandledException('Could not create remediation task: ' + e.getMessage());
        }
    }

    /** Aura twin of the EstimateFootprint action — per element, the ONE singular engine (C5). */
    @AuraEnabled
    public static List<OhmDTO.FootprintResponse> estimateFootprint(List<OhmDTO.FootprintRequest> reqs) {
        List<OhmDTO.FootprintResponse> responses = new List<OhmDTO.FootprintResponse>();
        if (reqs == null) {
            return responses;
        }
        OhmFootprintService footprint = new OhmFootprintService();
        for (OhmDTO.FootprintRequest req : reqs) {
            responses.add(footprint.estimate(req));
        }
        return responses;
    }
}
