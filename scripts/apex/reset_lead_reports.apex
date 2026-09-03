// Clean Lead Concierge (Ohm_Waste_Demo) report history to a single fresh F report so:
//  - Fleet shows F (the wasteful-agent story)
//  - getDiff returns the single-report empty state (no misleading A->F regression)
//  - the F->A cool-down is a LIVE demo beat (trim -> re-audit -> diff reveals improvement)
Id pid = [SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName LIKE 'Ohm_Waste%' LIMIT 1].Id;
List<Agent_Audit_Report__c> old = [
    SELECT Id FROM Agent_Audit_Report__c
    WHERE Target_Type__c = 'Process' AND Target_Planner_Id__c = :pid
];
System.debug('OHM_RESET deleting ' + old.size() + ' Lead Concierge process reports');
delete old;   // Finding__c children cascade (master-detail)

Id rid = OhmAuditController.auditProcess(pid);
Agent_Audit_Report__c r = [SELECT Efficiency_Grade__c, Findings_Count__c FROM Agent_Audit_Report__c WHERE Id = :rid];
System.debug('OHM_RESET fresh report grade=' + r.Efficiency_Grade__c + ' findings=' + r.Findings_Count__c);

OhmDTO.DiffDTO d = OhmAuditController.getDiff(pid);
System.debug('OHM_RESET diff beforeReportId=' + d.beforeReportId + ' afterGrade=' + d.afterGrade + ' (null before = clean empty state)');
