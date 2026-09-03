/**
 * OhmAssistantServiceTest — Wave 6 gate. The Trust-Layer call is replaced by the
 * OhmAssistantService.mockModelReply seam so tests never hit the LLM; everything else
 * (grounding assembly, intent detection, draft size deltas) runs for real against the
 * live Ohm_Waste_Demo agent surface (SeeAllData — GenAi*Definition are org metadata rows).
 */
@IsTest
private class OhmAssistantServiceTest {

    private static Id wastePlannerId() {
        List<GenAiPlannerDefinition> ps = [
            SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName = 'Ohm_Waste_Demo' LIMIT 1
        ];
        return ps.isEmpty() ? null : ps[0].Id;
    }

    // ---------- getContext: grounded summary, chips, quick prompts ----------

    @IsTest(SeeAllData=true)
    static void testGetContextGroundsOnAudit() {
        Id wasteId = wastePlannerId();
        System.assertNotEquals(null, wasteId, 'Ohm_Waste_Demo planner must exist');

        Test.startTest();
        OhmAuditController.auditProcess(wasteId); // so the context carries grade/energy/finding
        OhmDTO.AssistantContextDTO ctx = OhmAuditController.getAssistantContext(wasteId);
        Test.stopTest();

        System.assertNotEquals(null, ctx, 'context must load');
        System.assertEquals(true, ctx.available, 'Models API is available on this org');
        System.assertNotEquals(null, ctx.groundingSummary, 'grounding summary set');
        System.assert(ctx.groundingSummary.contains('Grounded in'), 'summary phrased as grounded');
        System.assert(ctx.groundedOn != null && !ctx.groundedOn.isEmpty(), 'grounding chips present');
        System.assert(ctx.quickPrompts != null && ctx.quickPrompts.size() >= 3,
            'at least the why/impact/save quick prompts');
        System.assertNotEquals(null, ctx.modelLabel, 'provenance label set');
        // a draft quick prompt exists because the bloated scope is present
        Boolean hasDraft = false;
        for (OhmDTO.AssistantPromptDTO p : ctx.quickPrompts) {
            if (p.id == 'draft') { hasDraft = true; }
        }
        System.assertEquals(true, hasDraft, 'a Draft-instructions quick prompt is offered');
    }

    // ---------- ask: a normal question returns a non-draft grounded answer ----------

    @IsTest(SeeAllData=true)
    static void testAskReturnsGroundedAnswer() {
        Id wasteId = wastePlannerId();
        OhmAssistantService.mockModelReply = 'It is wasteful because the scope is bloated.';

        Test.startTest();
        OhmAuditController.auditProcess(wasteId);
        OhmDTO.AssistantReplyDTO reply = OhmAuditController.askAssistant(
            wasteId, 'Why is this process wasteful?');
        Test.stopTest();

        System.assertNotEquals(null, reply, 'reply must return');
        System.assertEquals(false, reply.isDraft == true, 'a "why" question is not a draft');
        System.assert(reply.answer.contains('bloated'), 'answer echoes the (mocked) model text');
        System.assert(reply.groundedOn != null && !reply.groundedOn.isEmpty(), 'answer carries grounding chips');
        System.assertNotEquals(null, reply.modelLabel, 'answer carries provenance');
    }

    // ---------- ask: a rewrite request returns a draft with size deltas ----------

    @IsTest(SeeAllData=true)
    static void testAskDraftReturnsRewriteWithDeltas() {
        Id wasteId = wastePlannerId();
        OhmAssistantService.mockModelReply = 'You are the Lead Triage specialist. Greet leads, collect details, tier, route.';

        Test.startTest();
        OhmAuditController.auditProcess(wasteId);
        OhmDTO.AssistantReplyDTO reply = OhmAuditController.askAssistant(
            wasteId, 'Draft the trimmed instructions for this topic.');
        Test.stopTest();

        System.assertEquals(true, reply.isDraft, 'a "draft" request is a draft');
        System.assertNotEquals(null, reply.draftText, 'draft text present');
        System.assert(reply.beforeChars != null && reply.beforeChars > reply.afterChars,
            'the trimmed draft is shorter than the original bloated scope; before='
            + reply.beforeChars + ' after=' + reply.afterChars);
        System.assertNotEquals(null, reply.beforeTokens, 'before token estimate set');
        System.assertNotEquals(null, reply.afterTokens, 'after token estimate set');
        System.assert(reply.answer.contains('%'), 'the frame states the percent reduction');
    }

    // ---------- the "(unoptimized)" label must NOT trip the draft intent ----------

    @IsTest(SeeAllData=true)
    static void testUnoptimizedLabelDoesNotTriggerDraft() {
        Id wasteId = wastePlannerId();
        OhmAssistantService.mockModelReply = 'A plain explanation.';

        Test.startTest();
        OhmAuditController.auditProcess(wasteId);
        // this question embeds "(unoptimized)" — the old greedy regex mis-fired the draft path
        OhmDTO.AssistantReplyDTO reply = OhmAuditController.askAssistant(
            wasteId, 'Explain why Lead Concierge (unoptimized) is flagged as wasteful.');
        Test.stopTest();

        System.assertEquals(false, reply.isDraft == true,
            'the word "unoptimized" must not be read as an optimize/rewrite request');
    }

    // ---------- guards ----------

    @IsTest
    static void testNullArgumentsThrow() {
        OhmAssistantService.mockModelReply = 'x';
        Integer thrown = 0;
        try { OhmAuditController.getAssistantContext(null); } catch (AuraHandledException e) { thrown++; }
        try { OhmAuditController.askAssistant(null, 'hi'); } catch (AuraHandledException e) { thrown++; }
        System.assertEquals(2, thrown, 'null planner is rejected on both doorways');
    }

    @IsTest(SeeAllData=true)
    static void testBlankQuestionThrows() {
        Id wasteId = wastePlannerId();
        Boolean thrown = false;
        try {
            OhmAuditController.askAssistant(wasteId, '   ');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'a blank question is rejected');
    }

    @IsTest
    static void testSignalLabelMapsKnownValues() {
        System.assertEquals('Bloated instructions / scope',
            OhmAssistantService.signalLabel('INSTRUCTION_BLOAT'));
        System.assertEquals('Redundant LLM calls',
            OhmAssistantService.signalLabel('REDUNDANT_CALLS'));
        System.assertEquals('a waste finding', OhmAssistantService.signalLabel(null));
    }
}
