// ===== Task 3 data-model verification (dynamic to bypass stale Apex schema cache) =====
Boolean t1Pass=false, t2Pass=false, t3Pass=false;
String t1Msg='', t2Msg='', t3Msg='';

// ---- Test 1: report + 2 findings, rollups ----
SObject rpt = Schema.getGlobalDescribe().get('Agent_Audit_Report__c').newSObject();
rpt.put('Run_Status__c','Queued');
rpt.put('Percent_Complete__c',0);
insert rpt;
Id rptId = rpt.Id;

List<SObject> fs = new List<SObject>();
Map<String,Object> a = new Map<String,Object>{
  'Agent_Audit_Report__c'=>rptId,'Signal_Type__c'=>'INSTRUCTION_BLOAT',
  'Annual_Energy_Wh_Central__c'=>10,'Annual_Water_mL_Central__c'=>5,
  'Annual_CO2e_g_Central__c'=>3,'Annual_Energy_Savings_Wh__c'=>2};
Map<String,Object> b = new Map<String,Object>{
  'Agent_Audit_Report__c'=>rptId,'Signal_Type__c'=>'REDUNDANT_CALLS',
  'Annual_Energy_Wh_Central__c'=>20,'Annual_Water_mL_Central__c'=>7,
  'Annual_CO2e_g_Central__c'=>4,'Annual_Energy_Savings_Wh__c'=>6};
for (Map<String,Object> m : new List<Map<String,Object>>{a,b}) {
  SObject f = Schema.getGlobalDescribe().get('Finding__c').newSObject();
  for (String k : m.keySet()) f.put(k, m.get(k));
  fs.add(f);
}
insert fs;

SObject r2 = Database.query('SELECT Findings_Count__c, Total_Annual_Energy_Wh__c, '
  + 'Total_Annual_Water_mL__c, Total_Annual_CO2e_g__c, Total_Annual_Energy_Savings_Wh__c '
  + 'FROM Agent_Audit_Report__c WHERE Id = :rptId');
Decimal cnt = Decimal.valueOf(String.valueOf(r2.get('Findings_Count__c')));
Decimal en  = Decimal.valueOf(String.valueOf(r2.get('Total_Annual_Energy_Wh__c')));
Decimal wa  = Decimal.valueOf(String.valueOf(r2.get('Total_Annual_Water_mL__c')));
Decimal co  = Decimal.valueOf(String.valueOf(r2.get('Total_Annual_CO2e_g__c')));
Decimal sv  = Decimal.valueOf(String.valueOf(r2.get('Total_Annual_Energy_Savings_Wh__c')));
t1Pass = (cnt==2 && en==30 && wa==12 && co==7 && sv==8);
t1Msg = 'count='+cnt+' energy='+en+' water='+wa+' co2e='+co+' savings='+sv;

// ---- Test 2: restricted picklist rejects Model_Right_Sizing ----
try {
  SObject bad = Schema.getGlobalDescribe().get('Finding__c').newSObject();
  bad.put('Agent_Audit_Report__c', rptId);
  bad.put('Signal_Type__c','Model_Right_Sizing');
  insert bad;
  t2Pass=false; t2Msg='NO EXCEPTION — restricted picklist NOT enforced';
} catch (Exception e) {
  t2Pass = (e instanceof DmlException);
  t2Msg = e.getTypeName()+': '+e.getMessage();
}

// ---- Test 3: Ohm_Constants volumeScenario product == 109500 ----
StaticResource sr = [SELECT Body FROM StaticResource WHERE Name='Ohm_Constants' LIMIT 1];
Map<String,Object> j = (Map<String,Object>) JSON.deserializeUntyped(sr.Body.toString());
Map<String,Object> vs = (Map<String,Object>) j.get('volumeScenario');
Decimal prod = Decimal.valueOf(String.valueOf(vs.get('sessionsPerDay')))
             * Decimal.valueOf(String.valueOf(vs.get('turnsPerSession')))
             * Decimal.valueOf(String.valueOf(vs.get('callsPerTurn')))
             * Decimal.valueOf(String.valueOf(vs.get('daysPerYear')));
t3Pass = (prod == 109500);
t3Msg = 'product='+prod;

// ---- cleanup (cascade deletes findings) ----
delete rpt;

System.debug('T1 ROLLUPS ' + (t1Pass?'PASS':'FAIL') + ' :: ' + t1Msg);
System.debug('T2 RESTRICTED ' + (t2Pass?'PASS':'FAIL') + ' :: ' + t2Msg);
System.debug('T3 CONSTANTS ' + (t3Pass?'PASS':'FAIL') + ' :: ' + t3Msg);
System.assert(t1Pass && t2Pass && t3Pass, 'TASK3 VERIFY FAIL -> T1='+t1Pass+' T2='+t2Pass+' T3='+t3Pass+' | '+t1Msg+' | '+t2Msg+' | '+t3Msg);
System.debug('TASK3 VERIFY PASS');
