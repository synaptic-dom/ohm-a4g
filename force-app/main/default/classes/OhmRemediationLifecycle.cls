/** Stable remediation identity shared by immutable per-run findings and standard Tasks. */
public with sharing class OhmRemediationLifecycle {
    public static void prepare(Id reportId, Agent_Audit_Report__c report, OhmDTO.AgentModel graph,
            List<Finding__c> rows) {
        Set<String> processKeys = new Set<String>();
        Set<String> plannerNames = new Set<String>();
        String reportKey = OhmPersistenceService.logicalProcessKey(report.Target_Planner_Api_Name__c, report.Target_Planner_Id__c);
        if (report.Target_Type__c == 'Process' && String.isNotBlank(reportKey)) { processKeys.add(reportKey); }
        if (String.isNotBlank(report.Target_Planner_Api_Name__c)) { plannerNames.add(report.Target_Planner_Api_Name__c); }
        if (graph != null && graph.agentsById != null) {
            for (OhmDTO.AgentNode agent : graph.agentsById.values()) {
                if (agent == null) { continue; }
                processKeys.add(OhmPersistenceService.logicalProcessKey(agent.developerName, agent.id));
                if (String.isNotBlank(agent.developerName)) { plannerNames.add(agent.developerName); }
            }
        }
        Set<String> currentKeys = new Set<String>();
        for (Finding__c row : rows) {
            String processKey = report.Target_Type__c == 'Process' ? reportKey :
                OhmPersistenceService.logicalProcessKey(row.Parent_Agent_Api_Name__c, null);
            // Unidentified legacy fleet findings remain report-local; never merge unrelated agents.
            if (String.isBlank(processKey)) { processKey = 'report:' + reportId; }
            row.Process_Key__c = processKey;
            row.Artifact_Key__c = OhmPersistenceService.artifactKey(processKey, row.Artifact_Type__c,
                String.isBlank(row.Artifact_Api_Name__c) ? row.Artifact_Label__c : row.Artifact_Api_Name__c,
                row.Parent_Topic_Api_Name__c);
            row.Issue_Key__c = OhmPersistenceService.issueKey(row.Artifact_Key__c, row.Signal_Type__c);
            processKeys.add(processKey);
            currentKeys.add(row.Issue_Key__c);
        }
        if (processKeys.isEmpty()) { return; }
        Map<String, Finding__c> priorByKey = new Map<String, Finding__c>();
        Set<Id> taskIds = new Set<Id>();
        for (Finding__c old : [
            SELECT Id, Process_Key__c, Artifact_Key__c, Issue_Key__c, Artifact_Type__c,
                   Artifact_Api_Name__c, Artifact_Label__c, Parent_Agent_Api_Name__c, Parent_Topic_Api_Name__c,
                   Signal_Type__c, Finding_Status__c, Rec_Status__c, Remediation_Task_Id__c,
                   Agent_Audit_Report__r.Target_Planner_Api_Name__c, Agent_Audit_Report__r.Target_Planner_Id__c,
                   Agent_Audit_Report__r.Target_Type__c
            FROM Finding__c
            WHERE Agent_Audit_Report__c != :reportId
              AND Agent_Audit_Report__r.Run_Status__c = 'Complete'
              AND (Process_Key__c IN :processKeys OR Agent_Audit_Report__r.Target_Planner_Api_Name__c IN :plannerNames)
            ORDER BY Agent_Audit_Report__r.Run_Timestamp__c DESC NULLS LAST,
                     Agent_Audit_Report__r.CreatedDate DESC, CreatedDate DESC, Id DESC
        ]) {
            String key = keyOf(old);
            if (!priorByKey.containsKey(key)) {
                priorByKey.put(key, old);
                Id taskId = taskIdOf(old.Remediation_Task_Id__c);
                if (taskId != null) { taskIds.add(taskId); }
            }
        }
        Map<Id, Task> tasks = new Map<Id, Task>();
        if (!taskIds.isEmpty()) { tasks = new Map<Id, Task>([SELECT Id, IsClosed, Status FROM Task WHERE Id IN :taskIds]); }
        Map<Id, Task> taskUpdates = new Map<Id, Task>();
        List<Finding__c> resolved = new List<Finding__c>();
        for (Finding__c row : rows) {
            Finding__c old = priorByKey.get(row.Issue_Key__c);
            if (old == null) { continue; }
            row.Rec_Status__c = old.Rec_Status__c;
            row.Finding_Status__c = old.Finding_Status__c;
            Id taskId = taskIdOf(old.Remediation_Task_Id__c);
            Task task = tasks.get(taskId);
            if (task != null) { row.Remediation_Task_Id__c = task.Id; }
            // A persisted finding is evidence the issue still exists. A previously applied fix
            // or closed Task is reopened; a deliberate dismissal remains dismissed.
            if (old.Finding_Status__c == 'Applied' ||
                (task != null && task.IsClosed && old.Finding_Status__c != 'Dismissed')) {
                row.Finding_Status__c = 'Open';
                row.Rec_Status__c = 'Proposed';
                if (task != null && task.IsClosed) {
                    taskUpdates.put(task.Id, new Task(Id = task.Id, Status = 'Not Started'));
                }
            }
        }
        if (graph != null) {
            for (String key : priorByKey.keySet()) {
                Finding__c old = priorByKey.get(key);
                Boolean signalCovered = (graph.discoveryErrors == null || graph.discoveryErrors.isEmpty())
                    && (graph.coverageComplete == true || (graph.detectorCoverage != null
                    && graph.detectorCoverage.get(old.Signal_Type__c) == 'Covered'));
                if (!signalCovered) { continue; }
                if (currentKeys.contains(key) || old.Finding_Status__c == 'Applied' || old.Finding_Status__c == 'Dismissed') { continue; }
                resolved.add(new Finding__c(Id = old.Id, Finding_Status__c = 'Applied', Rec_Status__c = 'Applied'));
                Id taskId = taskIdOf(old.Remediation_Task_Id__c);
                Task task = tasks.get(taskId);
                if (task != null && !task.IsClosed) {
                    taskUpdates.put(task.Id, new Task(Id = task.Id, Status = 'Completed'));
                }
            }
        }
        if (!resolved.isEmpty()) { update resolved; }
        if (!taskUpdates.isEmpty()) { update taskUpdates.values(); }
    }

    /** Read-only compatibility for pre-identity rows; new findings always store these keys. */
    public static String processOf(Finding__c row) {
        if (String.isNotBlank(row.Process_Key__c)) { return row.Process_Key__c; }
        Agent_Audit_Report__c report = row.Agent_Audit_Report__r;
        String name = report != null && report.Target_Type__c == 'Process' ? report.Target_Planner_Api_Name__c : row.Parent_Agent_Api_Name__c;
        String idValue = report == null ? null : report.Target_Planner_Id__c;
        return OhmPersistenceService.logicalProcessKey(name, idValue);
    }

    public static String keyOf(Finding__c row) {
        if (String.isNotBlank(row.Issue_Key__c)) { return row.Issue_Key__c; }
        String artifactKey = row.Artifact_Key__c;
        if (String.isBlank(artifactKey)) {
            artifactKey = OhmPersistenceService.artifactKey(processOf(row), row.Artifact_Type__c,
                String.isBlank(row.Artifact_Api_Name__c) ? row.Artifact_Label__c : row.Artifact_Api_Name__c,
                row.Parent_Topic_Api_Name__c);
        }
        return OhmPersistenceService.issueKey(artifactKey, row.Signal_Type__c);
    }

    public static Id taskIdOf(String value) {
        if (String.isBlank(value)) { return null; }
        try { return (Id) value; } catch (Exception ignored) { return null; }
    }
}
