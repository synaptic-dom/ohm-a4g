/** Non-admin data-path checks. Test users and audit records roll back after each method. */
@IsTest
private class OhmAuditorPermissionAcceptanceTest {
    private static User auditor() {
        Profile baseline = [SELECT Id, PermissionsModifyAllData FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        System.assertEquals(false, baseline.PermissionsModifyAllData, 'Use a minimum-access non-admin profile');
        String suffix = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.valueOf(Crypto.getRandomInteger()) + System.now()))).substring(0,16);
        User person = new User(ProfileId=baseline.Id, Username='ohm-auditor-'+suffix+'@example.com',
            Email='ohm-auditor@example.com', Alias='ohmaudit', LastName='Ohm Permission Test',
            TimeZoneSidKey='America/Denver', LocaleSidKey='en_US', EmailEncodingKey='UTF-8', LanguageLocaleKey='en_US');
        insert person;
        List<PermissionSetAssignment> grants = new List<PermissionSetAssignment>();
        for (PermissionSet permission : [SELECT Id, Name, PermissionsModifyAllData FROM PermissionSet WHERE Name IN ('Ohm_App_Access','Ohm_Data_Access')]) {
            System.assertEquals(false, permission.PermissionsModifyAllData, 'Ohm access must not require global Modify All Data');
            grants.add(new PermissionSetAssignment(AssigneeId=person.Id, PermissionSetId=permission.Id));
        }
        System.assertEquals(2, grants.size());
        insert grants;
        return person;
    }
    @IsTest static void auditorPersistsAndReadsImpactAndImmutableSource() {
        User person = auditor();
        System.runAs(person) {
            System.assert(Agent_Audit_Report__c.SObjectType.getDescribe().isCreateable());
            System.assert(Audit_Artifact_Snapshot__c.SObjectType.getDescribe().isCreateable());
            System.assertEquals(false,Audit_Artifact_Snapshot__c.SObjectType.getDescribe().isUpdateable(),
                'Saved source snapshots must be immutable to the auditor');
            System.assert(Agent_Audit_Report__c.Impact_Snapshot__c.getDescribe().isUpdateable());
            System.assert(Audit_Artifact_Snapshot__c.Source_Json__c.getDescribe().isCreateable());
            OhmDTO.AgentModel graph = new OhmDTO.AgentModel();
            graph.coverageComplete = true;
            OhmDTO.AgentNode agent = new OhmDTO.AgentNode();
            agent.id = '16j000000000001'; agent.developerName = 'Permission_Weather_v1';
            agent.instructions = 'Help with weather.'; agent.sourceKind = 'ImportedAgentScript';
            agent.sourceVersion = 'permission-fixture-v1'; agent.sourcePath = 'permission.agent#system';
            graph.agentsById.put(agent.id,agent);
            OhmDTO.TopicNode topic = new OhmDTO.TopicNode();
            topic.id = 'topic-permission'; topic.plannerId = agent.id; topic.developerName = 'weather_lookup_16j000000000001';
            topic.instructions = '  Keep this exact instruction source.\n'; topic.scope = topic.instructions;
            topic.sourceKind = 'ImportedAgentScript'; topic.sourceVersion = 'permission-fixture-v1'; topic.sourcePath = 'permission.agent#weather_lookup';
            graph.topics.add(topic);
            OhmPersistenceService persistence = new OhmPersistenceService();
            Id reportId = persistence.createProcessReport((Id)agent.id,agent.developerName);
            OhmAuditImpactService.save(reportId,graph,new List<OhmDTO.Finding>(),null);
            OhmDTO.EfficiencyResult rating = new OhmDTO.EfficiencyResult(); rating.grade='A'; rating.score=100;
            persistence.persistFindings(reportId,graph,new List<OhmDTO.Finding>(),rating);
            Agent_Audit_Report__c report = [SELECT Id, Modeled_Energy_Wh__c, Impact_Snapshot__c, Coverage_Status__c FROM Agent_Audit_Report__c WHERE Id=:reportId WITH USER_MODE];
            System.assert(report.Modeled_Energy_Wh__c>0,'A clean audit retains modeled source cost');
            System.assertEquals(2,OhmAuditImpactService.readSnapshot(report.Impact_Snapshot__c).artifactCount);
            Map<String,Audit_Artifact_Snapshot__c> saved = OhmArtifactSnapshotService.load(new Set<Id>{reportId}).get(reportId);
            System.assertEquals(2,saved.size());
            String key = OhmPersistenceService.artifactKey('permission_weather','Topic',topic.developerName,null);
            System.assertEquals(topic.instructions,saved.get(key).Instructions__c,'Non-admin reader receives exact source, including whitespace');
            System.assertEquals(OhmPersistenceService.sha256(topic.instructions),saved.get(key).Source_Hash__c);
        }
    }
    @IsTest static void auditorCanReadButCannotOverwriteImportedSource() {
        User person = auditor();
        Id recordId;
        System.runAs(new User(Id=UserInfo.getUserId())) {
            Ohm_Instruction_Source__c source = new Ohm_Instruction_Source__c(Planner_Id__c='16j000000000001',
                Metadata_Fingerprint__c='fingerprint',Source_Revision__c='read-only-fixture',Manifest__c='{"schemaVersion":1}');
            insert source; recordId=source.Id;
        }
        System.runAs(person) {
            System.assert(Ohm_Instruction_Source__c.SObjectType.getDescribe().isAccessible());
            System.assertEquals(false,Ohm_Instruction_Source__c.SObjectType.getDescribe().isCreateable());
            System.assertEquals(false,Ohm_Instruction_Source__c.SObjectType.getDescribe().isUpdateable());
            System.assertEquals(false,Ohm_Instruction_Source__c.Manifest__c.getDescribe().isUpdateable());
            Ohm_Instruction_Source__c source = [SELECT Id, Planner_Id__c, Metadata_Fingerprint__c, Source_Revision__c, Manifest__c FROM Ohm_Instruction_Source__c WHERE Id=:recordId WITH USER_MODE];
            System.assertEquals('read-only-fixture',source.Source_Revision__c);
            Database.SaveResult denied = Database.update(
                new Ohm_Instruction_Source__c(Id=recordId,Source_Revision__c='unauthorized-overwrite'),
                false,AccessLevel.USER_MODE);
            System.assertEquals(false,denied.isSuccess(),'Auditor cannot overwrite imported provenance');
        }
    }
}
