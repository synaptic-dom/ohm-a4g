// Cross-surface number consistency — NO model calls (deterministic).
Id wasteId = [SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName='Ohm_Waste_Demo' LIMIT 1].Id;

OhmDTO.ProcessDetailDTO detail = OhmAuditController.getProcessDetail(wasteId);
System.debug('OHM_C DETAIL grade=' + detail.grade + ' energy=' + detail.energyWhCentral + ' findings=' + (detail.findings==null?0:detail.findings.size()));

for (OhmDTO.ProcessSummaryDTO row : OhmAuditController.getFleet()) {
    if (String.valueOf(row.plannerId) == String.valueOf(wasteId)) {
        System.debug('OHM_C FLEET grade=' + row.grade + ' energy=' + row.energyWhCentral + ' audited=' + row.audited);
        System.debug('OHM_C MATCH grade=' + (row.grade == detail.grade) + ' energy=' + (row.energyWhCentral == detail.energyWhCentral));
    }
}

OhmDTO.DiffDTO diff = OhmAuditController.getDiff(wasteId);
System.debug('OHM_C DIFF afterGrade=' + diff.afterGrade + ' afterEnergy=' + diff.afterEnergyWhCentral + ' before=' + diff.beforeReportId);
System.debug('OHM_C DIFF_MATCH grade=' + (diff.afterGrade == detail.grade) + ' energy=' + (diff.afterEnergyWhCentral == detail.energyWhCentral));

OhmDTO.TrendDTO trend = OhmAuditController.getTrends(wasteId);
Decimal lastTrendEnergy = (trend.points != null && !trend.points.isEmpty()) ? trend.points[trend.points.size()-1].energyWhCentral : null;
String lastTrendGrade = (trend.points != null && !trend.points.isEmpty()) ? trend.points[trend.points.size()-1].grade : null;
System.debug('OHM_C TREND lastGrade=' + lastTrendGrade + ' lastEnergy=' + lastTrendEnergy + ' points=' + (trend.points==null?0:trend.points.size()));
System.debug('OHM_C TREND_MATCH grade=' + (lastTrendGrade == detail.grade) + ' energy=' + (lastTrendEnergy == detail.energyWhCentral));

// Findings worklist: is the waste finding present exactly once for this planner?
Integer wasteRows = 0;
Decimal worklistSavings = null;
for (OhmDTO.WorklistItemDTO w : OhmAuditController.getFindings('All','All')) {
    if (w.plannerApiName != null && w.plannerApiName.startsWithIgnoreCase('Ohm_Waste')) { wasteRows++; worklistSavings = w.savingsCentralWh; }
}
System.debug('OHM_C WORKLIST wasteRows=' + wasteRows + ' savings=' + worklistSavings);
// compare to detail finding savings
Decimal detailSavings = (detail.findings != null && !detail.findings.isEmpty()) ? detail.findings[0].estimatedSavingsCentral : null;
System.debug('OHM_C SAVINGS_MATCH worklist==detailFinding=' + (worklistSavings == detailSavings) + ' (worklist=' + worklistSavings + ' detail=' + detailSavings + ')');
