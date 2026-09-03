// Wave 6 live E2E: getAssistantContext + a grounded Q&A + a draft rewrite, all against
// the real Einstein Trust Layer (no mock). Uses the wasteful Lead Concierge planner.
Id pid = [SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName LIKE 'Ohm_Waste%' LIMIT 1].Id;
System.debug('OHM_W6 planner=' + pid);

OhmDTO.AssistantContextDTO ctx = OhmAuditController.getAssistantContext(pid);
System.debug('OHM_W6 ctx.available=' + ctx.available + ' label=' + ctx.processLabel);
System.debug('OHM_W6 ctx.summary=' + ctx.groundingSummary);
System.debug('OHM_W6 ctx.chips=' + ctx.groundedOn);
System.debug('OHM_W6 ctx.quickPrompts=' + (ctx.quickPrompts == null ? 0 : ctx.quickPrompts.size()));
for (OhmDTO.AssistantPromptDTO p : ctx.quickPrompts) { System.debug('OHM_W6   qp[' + p.id + '] ' + p.label); }

OhmDTO.AssistantReplyDTO why = OhmAuditController.askAssistant(pid, 'Why is this process wasteful?');
System.debug('OHM_W6 WHY answer=' + why.answer);
System.debug('OHM_W6 WHY groundedOn=' + why.groundedOn + ' followUps=' + (why.followUps==null?0:why.followUps.size()));

OhmDTO.AssistantReplyDTO draft = OhmAuditController.askAssistant(pid, 'Draft the trimmed instructions for this topic.');
System.debug('OHM_W6 DRAFT isDraft=' + draft.isDraft + ' before=' + draft.beforeChars + ' after=' + draft.afterChars
    + ' beforeTok=' + draft.beforeTokens + ' afterTok=' + draft.afterTokens);
System.debug('OHM_W6 DRAFT frame=' + draft.answer);
String preview = draft.draftText == null ? '(null)' : draft.draftText.substring(0, Math.min(320, draft.draftText.length()));
System.debug('OHM_W6 DRAFT preview=' + preview);
