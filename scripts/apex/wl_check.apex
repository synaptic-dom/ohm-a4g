List<OhmDTO.WorklistItemDTO> items = OhmAuditController.getFindings(null, null);
System.debug('OHM_WL_COUNT=' + items.size());
for (OhmDTO.WorklistItemDTO w : items) {
    System.debug('OHM_WL ' + w.processLabel + ' | ' + w.artifactLabel + ' | ' + w.signal + ' | sev=' + w.severity + ' | saves=' + w.savingsCentralWh);
}
List<OhmDTO.WorklistItemDTO> recs = OhmAuditController.getRecommendations();
System.debug('OHM_REC_COUNT=' + recs.size());
