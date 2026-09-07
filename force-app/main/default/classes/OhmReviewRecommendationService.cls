/** Saved Salesforce review recommendations, gated by the existing current-source check. */
public with sharing class OhmReviewRecommendationService {
    public class RecommendationPage {
        @AuraEnabled public Id plannerId;
        @AuraEnabled public Id reportId;
        @AuraEnabled public String bundleLabel;
        @AuraEnabled public String plannerApiName;
        @AuraEnabled public Boolean sourceCurrent = false;
        @AuraEnabled public Boolean reviewAvailable = false;
        @AuraEnabled public String reviewerTemplate;
        @AuraEnabled public String reviewerVersion;
        @AuraEnabled public String reviewerModel;
        @AuraEnabled public Datetime reviewedAt;
        @AuraEnabled public String reason;
        @AuraEnabled public List<Item> items = new List<Item>();
        private String reviewDigest;
    }
    public class Item {
        @AuraEnabled public String key;
        @AuraEnabled public Id reportId;
        @AuraEnabled public Id plannerId;
        @AuraEnabled public String bundleLabel;
        @AuraEnabled public String artifactId;
        @AuraEnabled public String artifactKey;
        @AuraEnabled public String nodeId;
        @AuraEnabled public String artifactLabel;
        @AuraEnabled public String artifactType;
        @AuraEnabled public String categoryId;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public String rating;
        @AuraEnabled public String origin;
        @AuraEnabled public String code;
        @AuraEnabled public String explanation;
        @AuraEnabled public String recommendation;
        @AuraEnabled public String preserve;
        @AuraEnabled public String validation;
        @AuraEnabled public String reviewerVersion;
        @AuraEnabled public Id taskId;
        @AuraEnabled public String taskStatus;
        @AuraEnabled public Boolean taskClosed;
        @AuraEnabled public List<Evidence> evidence = new List<Evidence>();
    }
    public class Evidence {
        @AuraEnabled public String artifactId;
        @AuraEnabled public String artifactKey;
        @AuraEnabled public String nodeId;
        @AuraEnabled public String artifactLabel;
        @AuraEnabled public String sourcePath;
        @AuraEnabled public String quote;
    }
    public virtual class Gateway {
        public virtual OhmDTO.ProcessDetailDTO detail(Id plannerId) {
            return OhmAuditController.getProcessDetail(plannerId);
        }
    }
    @TestVisible private static Gateway gateway = new Gateway();

    /** Per-bundle requests avoid accumulating discovery callouts and SOQL across the fleet. */
    @AuraEnabled(cacheable=false)
    public static RecommendationPage getReviewRecommendations(Id plannerId) {
        if (plannerId == null) throw new AuraHandledException('Choose an Agent Script bundle to load its recommendations.');
        OhmDTO.ProcessDetailDTO detail = gateway.detail(plannerId);
        RecommendationPage page = new RecommendationPage(); page.plannerId = plannerId;
        if (detail == null) { page.reason = 'The bundle could not be loaded.'; return page; }
        page.reportId = detail.reportId; page.bundleLabel = detail.label; page.plannerApiName = detail.plannerApiName;
        page.sourceCurrent = detail.sourceCurrent == true;
        if (detail.reportId == null) { page.reason = 'Audit this bundle to get Salesforce review recommendations.'; return page; }
        if (!page.sourceCurrent) { page.reason = 'Source changed since this audit. Re-audit the bundle before using its recommendations.'; return page; }
        if (String.isBlank(detail.reviewJson)) { page.reason = 'This audit has no saved Salesforce review. Re-audit the bundle.'; return page; }
        OhmReviewService.Result review;
        try { review = (OhmReviewService.Result)JSON.deserialize(detail.reviewJson, OhmReviewService.Result.class); }
        catch (Exception ex) { page.reason = 'The saved review could not be read. Re-audit the bundle.'; return page; }
        if (review == null || review.schemaVersion != 1 || !'Reviewed'.equals(review.status)
            || !OhmReviewTemplate.TEMPLATE_API_NAME.equals(review.reviewerTemplate)
            || !OhmReviewTemplate.REVIEWER_VERSION.equals(review.reviewerVersion)
            || review.categories == null || review.artifacts == null) {
            page.reason = 'The saved review uses an earlier reviewer version. Re-audit the bundle for current recommendations.';
            return page;
        }
        page.reviewerTemplate = review.reviewerTemplate; page.reviewerVersion = review.reviewerVersion;
        page.reviewerModel = review.reviewerModel; page.reviewedAt = review.reviewedAt;
        page.reviewDigest = OhmPersistenceService.sha256(detail.reviewJson);
        Map<String,Evidence> sources = new Map<String,Evidence>();
        Map<String,OhmDTO.NodeDTO> nodes = new Map<String,OhmDTO.NodeDTO>();
        if (detail.nodes != null) for (OhmDTO.NodeDTO node : detail.nodes) {
            if (node != null && String.isNotBlank(node.id)) nodes.put(node.id, node);
        }
        for (OhmReviewService.ArtifactResult artifact : review.artifacts) {
            if (artifact == null || String.isBlank(artifact.artifactId)) continue;
            Evidence source = new Evidence(); source.artifactId = artifact.artifactId;
            source.artifactKey = artifact.artifactKey;
            source.nodeId = nodes.containsKey(artifact.artifactId) ? artifact.artifactId : null;
            source.artifactLabel = artifact.label; source.sourcePath = artifact.sourcePath;
            sources.put(source.artifactId, source);
        }
        if (review.contextSources != null) for (OhmReviewService.ContextSource context : review.contextSources) {
            if (context == null || String.isBlank(context.artifactId)) continue;
            Evidence source = new Evidence(); source.artifactId = context.artifactId;
            source.nodeId = nodes.containsKey(context.plannerId) ? context.plannerId : null;
            source.artifactKey = source.nodeId == null ? null : nodes.get(source.nodeId).artifactKey;
            source.artifactLabel = context.label; source.sourcePath = context.sourcePath;
            sources.put(source.artifactId, source);
        }
        Set<String> keys = new Set<String>();
        append(page, review.categories, null, sources, nodes, keys);
        for (OhmReviewService.ArtifactResult artifact : review.artifacts) {
            if (artifact != null) append(page, artifact.categories, artifact, sources, nodes, keys);
        }
        page.reviewAvailable = true;
        attachTasks(page);
        if (page.items.isEmpty()) page.reason = 'No changes were recommended in the current saved review. Unknown coverage still needs evaluation.';
        return page;
    }

    /** Creates a standard Task from the saved issue only; client prose is never accepted. */
    @AuraEnabled
    public static Id createReviewTask(Id plannerId, Id reportId, String key) {
        if (reportId == null || String.isBlank(key)) throw new AuraHandledException('A current saved recommendation is required.');
        // Discovery can call Salesforce. Finish it before taking the report lock.
        RecommendationPage page = getReviewRecommendations(plannerId);
        if (!page.reviewAvailable || !page.sourceCurrent || page.reportId != reportId) {
            throw new AuraHandledException('This recommendation is no longer current. Refresh or re-audit the bundle.');
        }
        Item selected;
        for (Item item : page.items) if (item.key.equals(key)) { selected = item; break; }
        if (selected == null) throw new AuraHandledException('The saved recommendation was not found. Refresh the recommendations.');
        List<Agent_Audit_Report__c> reports = [
            SELECT Id, Target_Type__c, Target_Planner_Id__c, Run_Status__c, Review_Result__c
            FROM Agent_Audit_Report__c WHERE Id = :reportId LIMIT 1 FOR UPDATE
        ];
        if (reports.isEmpty() || reports[0].Target_Type__c != 'Process'
            || reports[0].Target_Planner_Id__c != String.valueOf(plannerId)
            || reports[0].Run_Status__c != 'Complete'
            || OhmPersistenceService.sha256(reports[0].Review_Result__c) != page.reviewDigest) {
            throw new AuraHandledException('The audit changed while creating the task. Refresh the recommendations.');
        }
        String planner = String.valueOf(plannerId);
        List<Agent_Audit_Report__c> latest = [SELECT Id FROM Agent_Audit_Report__c
            WHERE Target_Type__c = 'Process' AND Target_Planner_Id__c = :planner AND Run_Status__c = 'Complete'
            ORDER BY CreatedDate DESC, Id DESC LIMIT 1];
        if (latest.isEmpty() || latest[0].Id != reportId) {
            throw new AuraHandledException('A newer audit is available. Refresh the recommendations.');
        }
        String legacySubject = legacyTaskSubject(selected);
        List<Task> existing = [SELECT Id, Subject, Description, Ohm_Review_Key__c FROM Task
            WHERE WhatId = :reportId AND (Ohm_Review_Key__c = :key OR (Ohm_Review_Key__c = null AND Subject = :legacySubject))
            ORDER BY CreatedDate ASC];
        for (Task candidate : existing) if (key.equals(candidate.Ohm_Review_Key__c)) return candidate.Id;
        if (!existing.isEmpty()) {
            Task prior = existing[0];
            Task migrated = new Task(Id = prior.Id, Ohm_Review_Key__c = key, Subject = taskSubject(selected));
            // Keep any user edits to the description while adopting older generated Tasks.
            if (legacyTaskBody(selected, page).equals(prior.Description)) migrated.Description = taskBody(selected);
            Database.update(migrated, AccessLevel.USER_MODE);
            return prior.Id;
        }
        Task task = new Task(Subject = taskSubject(selected), Description = taskBody(selected), WhatId = reportId,
            Ohm_Review_Key__c = key, OwnerId = UserInfo.getUserId(), Status = 'Not Started', Priority = 'Normal');
        Database.insert(task, AccessLevel.USER_MODE);
        return task.Id;
    }

    private static String taskBody(Item item) {
        List<String> description = new List<String>{
            'Change\n' + item.recommendation, 'Why\n' + item.explanation,
            'Keep\n' + item.preserve, 'Test\n' + item.validation};
        List<String> quotes = new List<String>(); Set<String> seen = new Set<String>();
        for (Evidence evidence : item.evidence) {
            String entry = evidence.artifactLabel + ':\n“' + evidence.quote + '”';
            if (seen.add(entry)) quotes.add(entry);
        }
        if (!quotes.isEmpty()) description.add('Source evidence\n' + String.join(quotes, '\n\n'));
        String body = String.join(description, '\n\n');
        if (body.length() > 32000) throw new AuraHandledException('The saved recommendation exceeds Task description storage. Open the bundle to review it.');
        return body;
    }

    /** Recognizes the exact former generated body; never overwrites subsequent user notes. */
    @TestVisible private static String legacyTaskBody(Item selected, RecommendationPage page) {
        List<String> description = new List<String>{
            selected.recommendation, 'Why: ' + selected.explanation, 'Preserve: ' + selected.preserve,
            'Validate: ' + selected.validation, 'Bundle: ' + selected.bundleLabel,
            'Source: ' + selected.artifactLabel, 'Audit report: ' + String.valueOf(page.reportId),
            'Recommendation identity: ' + selected.key,
            'Reviewer: ' + page.reviewerTemplate + ' / ' + page.reviewerVersion};
        for (Evidence evidence : selected.evidence) {
            description.add('Evidence (' + evidence.artifactLabel + ', ' + evidence.sourcePath + '):\n' + evidence.quote);
        }
        return String.join(description, '\n\n');
    }

    private static String taskSubject(Item item) {
        Map<String,String> titles = new Map<String,String>{
            'INPUT_UNNECESSARY_CONTEXT'=>'Remove unrelated context', 'INPUT_CONFLICT'=>'Resolve conflicting instructions',
            'INPUT_REDUNDANCY'=>'Consolidate repeated instructions', 'INPUT_HARD_BUDGET'=>'Review instruction length',
            'OUTPUT_UNBOUNDED'=>'Add an output stopping condition', 'OUTPUT_UNNECESSARY_VERBOSITY'=>'Shorten unnecessary output',
            'OUTPUT_FORMAT_MISMATCH'=>'Align the output format', 'MODEL_OVERSIZED_CANDIDATE'=>'Evaluate a smaller model',
            'MODEL_CAPABILITY_RISK'=>'Check model capability', 'CALLS_DETERMINISTIC_ALTERNATIVE'=>'Review fixed checks',
            'CALLS_REPEAT_CANDIDATE'=>'Review repeated AI calls', 'CALLS_MISSING_BOUND'=>'Set a stopping condition'};
        String title = titles.containsKey(item.code) ? titles.get(item.code) : 'Review recommended change';
        if ('CALLS_DETERMINISTIC_ALTERNATIVE'.equals(item.code) && String.isNotBlank(item.artifactLabel)
            && item.artifactLabel.toLowerCase().contains('schedule')) title = 'Review schedule validation';
        return (title + (String.isBlank(item.artifactLabel) ? '' : ' — ' + item.artifactLabel)).abbreviate(255);
    }
    @TestVisible private static String legacyTaskSubject(Item item) {
        return 'Ohm review: ' + item.code + ' [' + item.key.substringAfter('review:') + ']';
    }
    private static void attachTasks(RecommendationPage page) {
        if (page.items.isEmpty()) return;
        Map<String,Item> byKey = new Map<String,Item>(); Map<String,Item> byLegacySubject = new Map<String,Item>();
        for (Item item : page.items) { byKey.put(item.key, item); byLegacySubject.put(legacyTaskSubject(item), item); }
        Set<String> keys = byKey.keySet(); Set<String> subjects = byLegacySubject.keySet(); Set<String> mappedKeys = new Set<String>();
        for (Task task : [SELECT Id, Subject, Status, IsClosed, Ohm_Review_Key__c FROM Task
            WHERE WhatId = :page.reportId AND (Ohm_Review_Key__c IN :keys OR (Ohm_Review_Key__c = null AND Subject IN :subjects))
            ORDER BY CreatedDate ASC]) {
            Item item = String.isBlank(task.Ohm_Review_Key__c) ? byLegacySubject.get(task.Subject) : byKey.get(task.Ohm_Review_Key__c);
            if (item == null || (item.taskId != null && String.isBlank(task.Ohm_Review_Key__c))) continue;
            if (String.isNotBlank(task.Ohm_Review_Key__c) && !mappedKeys.add(task.Ohm_Review_Key__c)) continue;
            item.taskId = task.Id; item.taskStatus = task.Status; item.taskClosed = task.IsClosed;
        }
    }

    private static void append(RecommendationPage page, List<OhmReviewService.Category> categories,
        OhmReviewService.ArtifactResult artifact, Map<String,Evidence> sources,
        Map<String,OhmDTO.NodeDTO> nodes, Set<String> keys) {
        if (categories == null) return;
        for (OhmReviewService.Category category : categories) {
            if (category == null || category.issues == null) continue;
            for (OhmReviewService.Issue issue : category.issues) {
                if (issue == null || String.isBlank(issue.code) || String.isBlank(issue.recommendation)) continue;
                Item item = new Item(); item.reportId = page.reportId; item.plannerId = page.plannerId;
                item.bundleLabel = page.bundleLabel; item.artifactId = artifact == null ? 'bundle' : artifact.artifactId;
                item.artifactKey = artifact == null ? null : artifact.artifactKey;
                item.nodeId = artifact != null && nodes.containsKey(artifact.artifactId) ? artifact.artifactId : null;
                item.artifactLabel = artifact == null ? page.bundleLabel : artifact.label;
                item.artifactType = artifact == null ? 'Bundle' : artifact.artifactType;
                item.categoryId = category.id; item.categoryLabel = category.label; item.rating = category.rating;
                item.origin = issue.origin; item.code = issue.code; item.explanation = issue.explanation;
                item.recommendation = issue.recommendation; item.preserve = issue.preserve; item.validation = issue.validation;
                item.reviewerVersion = page.reviewerVersion;
                List<String> quoteIdentity = new List<String>();
                if (issue.evidence != null) for (OhmReviewService.QuoteEvidence quote : issue.evidence) {
                    if (quote == null || !sources.containsKey(quote.artifactId)) continue;
                    Evidence source = sources.get(quote.artifactId); Evidence evidence = new Evidence();
                    evidence.artifactId = source.artifactId; evidence.nodeId = source.nodeId;
                    evidence.artifactKey = source.artifactKey;
                    evidence.artifactLabel = source.artifactLabel; evidence.sourcePath = source.sourcePath;
                    evidence.quote = quote.quote; item.evidence.add(evidence);
                    quoteIdentity.add(JSON.serialize(new List<String>{quote.artifactId, quote.quote}));
                }
                if (item.evidence.isEmpty()) continue;
                quoteIdentity.sort();
                item.key = 'review:' + OhmPersistenceService.sha256(JSON.serialize(new List<String>{
                    String.valueOf(page.reportId), item.artifactId, item.categoryId, item.code,
                    String.join(quoteIdentity, '\n'), item.explanation, item.recommendation, item.preserve, item.validation}));
                if (keys.add(item.key)) page.items.add(item);
            }
        }
    }
}
