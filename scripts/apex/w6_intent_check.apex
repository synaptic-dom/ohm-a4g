// Verify intent classification on the EXACT quick-prompt strings (the ones the UI sends),
// which embed the "(unoptimized)" label that previously mis-triggered the draft path.
Id pid = [SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName LIKE 'Ohm_Waste%' LIMIT 1].Id;
String label = 'Lead Concierge (unoptimized)';
Map<String,String> prompts = new Map<String,String>{
  'why'    => 'Explain in plain language why ' + label + ' is flagged as wasteful. Cite the specific finding and its modeled energy impact.',
  'impact' => 'What is the annual energy, water, and CO2e footprint of ' + label + ', and what drives it?',
  'save'   => 'If we fix the top finding on ' + label + ', how much energy would we save and what would the grade become?',
  'draft'  => 'Draft a tightened version of the Lead Triage (unoptimized) instructions that preserves every rule but removes repetition and redundancy.'
};
for (String k : prompts.keySet()) {
  OhmDTO.AssistantReplyDTO r = OhmAuditController.askAssistant(pid, prompts.get(k));
  System.debug('OHM_INTENT ' + k + ' isDraft=' + (r.isDraft == true) + ' answerHead=' + r.answer.substring(0, Math.min(90, r.answer.length())));
}
