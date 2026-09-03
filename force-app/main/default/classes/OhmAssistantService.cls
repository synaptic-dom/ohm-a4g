/**
 * OhmAssistantService — Wave 6, the per-process "Ask Ohm" assistant (SPEC-ohm-v2 §2.2).
 *
 * HEADLESS by design: the LLM is invoked entirely from Apex through the Einstein Trust
 * Layer via the callout-free Models API (aiplatform.ModelsAPI, GA Winter '25). There is
 * NO embedded messaging widget and NO connected app / Agent API (both disabled on this
 * org) — the whole conversation is server-driven, which is the Headless Hero thesis.
 *
 * Every answer is GROUNDED: before each call we assemble the process's real audit context
 * (grade, modeled energy, the specific waste finding, and the raw bloated topic scope) and
 * constrain the model to answer only from it. A "draft the trimmed instructions" request is
 * detected server-side and returns ONLY the rewrite plus a before→after size readout.
 */
public with sharing class OhmAssistantService {

    // The Trust-Layer model. GPT-4o mini is fast + cheap and available on this org
    // (verified live via scripts/apex/probe_models_api.apex).
    @TestVisible private static final String MODEL_NAME = 'sfdc_ai__DefaultGPT4OmniMini';
    @TestVisible private static final String MODEL_LABEL = 'GPT-4o mini · Einstein Trust Layer';

    // Bound the raw instructions we hand the model (the demo scope is ~5,400 chars).
    private static final Integer MAX_INSTRUCTION_CHARS = 8000;

    // Draft/rewrite intent — when the question asks to produce tightened instructions.
    // Word-boundaried so a process label like "Lead Concierge (unoptimized)" does NOT
    // trip 'optimize' (the label is embedded in every grounded prompt).
    private static final Pattern DRAFT_INTENT = Pattern.compile(
        '(?i).*\\b(draft|rewrite|trim|tighten|shorten|condense|optimi[sz]e|reduce)\\b.*'
    );

    // Test seam: when set, callModel() returns this instead of hitting the Trust Layer.
    @TestVisible private static String mockModelReply;

    // ------------------------------------------------------------------ context

    /**
     * Build the assistant's opening context for a process: grounding summary, chips, and
     * process-specific quick prompts. Never calls the model (cheap, safe to run on render).
     */
    public static OhmDTO.AssistantContextDTO getContext(Id plannerId) {
        if (plannerId == null) {
            throw new AuraHandledException('Ask Ohm requires a plannerId.');
        }
        try {
            OhmDTO.ProcessDetailDTO detail = OhmAuditController.getProcessDetail(plannerId);
            Grounding gr = new Grounding(detail);

            OhmDTO.AssistantContextDTO ctx = new OhmDTO.AssistantContextDTO();
            ctx.plannerId = plannerId;
            ctx.processLabel = gr.label;
            ctx.available = true;
            ctx.modelLabel = MODEL_LABEL;
            ctx.groundedOn = gr.chips();
            ctx.groundingSummary = gr.summary();
            ctx.quickPrompts = gr.quickPrompts();
            ctx.greeting = gr.greeting();
            return ctx;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not prepare Ask Ohm: ' + e.getMessage());
        }
    }

    // ---------------------------------------------------------------------- ask

    /**
     * Answer one grounded question about a process. Detects a rewrite request and, for one,
     * returns only the trimmed instructions with a before→after size delta.
     */
    public static OhmDTO.AssistantReplyDTO ask(Id plannerId, String question) {
        if (plannerId == null) {
            throw new AuraHandledException('Ask Ohm requires a plannerId.');
        }
        if (String.isBlank(question)) {
            throw new AuraHandledException('Ask Ohm a question first.');
        }
        try {
            OhmDTO.ProcessDetailDTO detail = OhmAuditController.getProcessDetail(plannerId);
            Grounding gr = new Grounding(detail);

            Boolean wantsDraft = DRAFT_INTENT.matcher(question).matches()
                && String.isNotBlank(gr.wastefulInstructions);

            OhmDTO.AssistantReplyDTO reply = new OhmDTO.AssistantReplyDTO();
            reply.modelLabel = MODEL_LABEL;
            reply.groundedOn = gr.chips();
            reply.followUps = gr.followUps(wantsDraft);

            if (wantsDraft) {
                String rewrite = trimText(callModel(gr.draftPrompt(question)));
                reply.isDraft = true;
                reply.draftText = rewrite;
                reply.beforeChars = gr.wastefulInstructions.length();
                reply.afterChars = rewrite.length();
                reply.beforeTokens = TokenEstimator.approxTokens(gr.wastefulInstructions);
                reply.afterTokens = TokenEstimator.approxTokens(rewrite);
                Integer pct = reply.beforeChars > 0
                    ? (Integer) Math.round(
                        (Decimal) (reply.beforeChars - reply.afterChars)
                            / reply.beforeChars * 100)
                    : 0;
                reply.answer = 'Here is a tightened version of the ' + gr.wastefulLabel
                    + ' instructions — every rule preserved, roughly ' + pct
                    + '% fewer characters. Trimming the scope is what turns the grade around.';
            } else {
                reply.answer = trimText(callModel(gr.answerPrompt(question)));
            }
            return reply;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Ohm could not answer just now: ' + e.getMessage());
        }
    }

    // ---------------------------------------------------------------- model call

    /**
     * Single point of contact with the Trust Layer. Sends one grounded user message and
     * returns the model's text. Honours the test mock so unit tests never hit the LLM.
     */
    @TestVisible
    private static String callModel(String prompt) {
        if (mockModelReply != null) {
            return mockModelReply;
        }
        aiplatform.ModelsAPI.createChatGenerations_Request req =
            new aiplatform.ModelsAPI.createChatGenerations_Request();
        req.modelName = MODEL_NAME;

        aiplatform.ModelsAPI_ChatMessageRequest msg =
            new aiplatform.ModelsAPI_ChatMessageRequest();
        msg.content = prompt;
        msg.role = 'user';

        aiplatform.ModelsAPI_ChatGenerationsRequest body =
            new aiplatform.ModelsAPI_ChatGenerationsRequest();
        body.messages = new List<aiplatform.ModelsAPI_ChatMessageRequest>{ msg };
        req.body = body;

        aiplatform.ModelsAPI api = new aiplatform.ModelsAPI();
        aiplatform.ModelsAPI.createChatGenerations_Response res = api.createChatGenerations(req);

        if (res == null || res.Code200 == null
                || res.Code200.generationDetails == null
                || res.Code200.generationDetails.generations == null
                || res.Code200.generationDetails.generations.isEmpty()) {
            throw new OhmAssistantException('The model returned no content.');
        }
        return res.Code200.generationDetails.generations[0].content;
    }

    private static String trimText(String s) {
        return s == null ? '' : s.trim();
    }

    public class OhmAssistantException extends Exception {}

    // ===================================================================== grounding
    /**
     * Assembles a process's real audit context and turns it into (a) display chips, (b) a
     * one-line summary, (c) quick prompts, and (d) the grounded prompts handed to the model.
     * The single source of what the assistant "knows" — everything is drawn from the live
     * audit, so answers cite real grades, energy figures, and the actual instruction text.
     */
    private class Grounding {
        String label;
        String domain;
        String grade;
        Integer score;
        Decimal energyWh;
        Boolean audited;
        // the dominant waste finding + the raw instructions of the node it targets
        OhmDTO.FindingDTO topFinding;
        String wastefulLabel;
        String wastefulInstructions;

        Grounding(OhmDTO.ProcessDetailDTO d) {
            this.label = d != null && String.isNotBlank(d.label) ? d.label : 'this process';
            this.domain = d != null ? d.domain : null;
            this.grade = d != null ? d.grade : null;
            this.score = d != null ? d.score : null;
            this.energyWh = d != null ? d.energyWhCentral : null;
            this.audited = d != null && d.reportId != null;

            // pick the highest-impact finding (by central savings, then severity)
            if (d != null && d.findings != null) {
                for (OhmDTO.FindingDTO f : d.findings) {
                    if (f == null) { continue; }
                    if (topFinding == null || savings(f) > savings(topFinding)) {
                        topFinding = f;
                    }
                }
            }
            // the raw instruction text of the wasteful node (the bloated topic scope)
            if (d != null && d.nodes != null) {
                OhmDTO.NodeDTO best;
                for (OhmDTO.NodeDTO n : d.nodes) {
                    if (n == null || String.isBlank(n.instructions)) { continue; }
                    if (n.wasteful == true) {
                        if (best == null
                                || n.instructions.length() > best.instructions.length()) {
                            best = n;
                        }
                    }
                }
                // fall back to the longest instructions if nothing is flagged wasteful yet
                if (best == null) {
                    for (OhmDTO.NodeDTO n : d.nodes) {
                        if (n == null || String.isBlank(n.instructions)) { continue; }
                        if (best == null
                                || n.instructions.length() > best.instructions.length()) {
                            best = n;
                        }
                    }
                }
                if (best != null) {
                    this.wastefulLabel = String.isNotBlank(best.label)
                        ? best.label : best.apiName;
                    this.wastefulInstructions = best.instructions.length() > MAX_INSTRUCTION_CHARS
                        ? best.instructions.substring(0, MAX_INSTRUCTION_CHARS)
                        : best.instructions;
                }
            }
        }

        Decimal savings(OhmDTO.FindingDTO f) {
            return f != null && f.estimatedSavingsCentral != null
                ? f.estimatedSavingsCentral : 0;
        }

        String greeting() {
            if (!audited) {
                return 'Audit ' + label + ' first, then ask me why it\'s wasteful or to '
                    + 'draft tighter instructions — I answer from its live audit.';
            }
            return 'Ask me about ' + label + '. I answer from its live audit — the '
                + (grade != null ? 'grade-' + grade + ' ' : '')
                + 'result, the modeled energy, and the actual instruction text.';
        }

        String summary() {
            List<String> parts = new List<String>();
            parts.add(label);
            if (String.isNotBlank(grade)) { parts.add('grade ' + grade); }
            if (energyWh != null) { parts.add(formatInt(energyWh) + ' Wh/yr'); }
            return 'Grounded in ' + String.join(parts, ' · ');
        }

        List<String> chips() {
            List<String> chips = new List<String>();
            if (wastefulInstructions != null) {
                chips.add(wastefulLabel + ' scope (' + formatInt(wastefulInstructions.length())
                    + ' chars)');
            }
            if (topFinding != null) {
                String sig = OhmAssistantService.signalLabel(topFinding.signal);
                chips.add(sig + (String.isNotBlank(topFinding.severity)
                    ? ' (' + topFinding.severity + ')' : ''));
            }
            if (String.isNotBlank(grade)) {
                chips.add('Grade ' + grade
                    + (energyWh != null ? ' · ' + formatInt(energyWh) + ' Wh/yr' : ''));
            }
            return chips;
        }

        List<OhmDTO.AssistantPromptDTO> quickPrompts() {
            List<OhmDTO.AssistantPromptDTO> out = new List<OhmDTO.AssistantPromptDTO>();
            out.add(prompt('why', 'Why is this wasteful?',
                'Explain in plain language why ' + label + ' is flagged as wasteful. '
                + 'Cite the specific finding and its modeled energy impact.'));
            if (String.isNotBlank(wastefulInstructions)) {
                out.add(prompt('draft', 'Draft trimmed instructions',
                    'Draft a tightened version of the ' + wastefulLabel + ' instructions '
                    + 'that preserves every rule but removes repetition and redundancy.'));
            }
            out.add(prompt('impact', 'Environmental impact',
                'What is the annual energy, water, and CO2e footprint of ' + label
                + ', and what drives it?'));
            out.add(prompt('save', 'What could we save?',
                'If we fix the top finding on ' + label
                + ', how much energy would we save and what would the grade become?'));
            return out;
        }

        List<OhmDTO.AssistantPromptDTO> followUps(Boolean afterDraft) {
            List<OhmDTO.AssistantPromptDTO> out = new List<OhmDTO.AssistantPromptDTO>();
            if (afterDraft) {
                out.add(prompt('impact', 'Environmental impact',
                    'What is the annual energy, water, and CO2e footprint of ' + label + '?'));
                out.add(prompt('save', 'What could we save?',
                    'How much energy would trimming these instructions save on ' + label + '?'));
            } else if (String.isNotBlank(wastefulInstructions)) {
                out.add(prompt('draft', 'Draft trimmed instructions',
                    'Draft a tightened version of the ' + wastefulLabel + ' instructions '
                    + 'that preserves every rule but removes repetition.'));
                out.add(prompt('save', 'What could we save?',
                    'If we fix the top finding on ' + label
                    + ', how much energy would we save and what would the grade become?'));
            }
            return out;
        }

        // --- prompts handed to the model -----------------------------------

        String contextBlock() {
            List<String> lines = new List<String>();
            lines.add('PROCESS: ' + label + (String.isNotBlank(domain) ? ' (' + domain + ')' : ''));
            if (audited) {
                lines.add('EFFICIENCY GRADE: ' + (grade == null ? 'n/a' : grade)
                    + (score != null ? ' (score ' + score + '/100)' : ''));
                if (energyWh != null) {
                    lines.add('MODELED ANNUAL ENERGY: ' + formatInt(energyWh) + ' Wh/yr');
                }
            } else {
                lines.add('STATUS: not yet audited');
            }
            if (topFinding != null) {
                lines.add('TOP FINDING: ' + OhmAssistantService.signalLabel(topFinding.signal)
                    + ' — severity ' + nvl(topFinding.severity, 'n/a'));
                if (String.isNotBlank(topFinding.evidence)) {
                    lines.add('EVIDENCE: ' + topFinding.evidence);
                }
                if (topFinding.estimatedSavingsCentral != null) {
                    lines.add('ESTIMATED SAVINGS IF FIXED: '
                        + formatInt(topFinding.estimatedSavingsCentral) + ' Wh/yr');
                }
                if (topFinding.co2eGCentral != null) {
                    lines.add('CO2e (central): ' + formatInt(topFinding.co2eGCentral) + ' g/yr');
                }
                if (topFinding.waterMlCentral != null) {
                    lines.add('WATER (central): ' + formatInt(topFinding.waterMlCentral) + ' mL/yr');
                }
            }
            if (String.isNotBlank(wastefulInstructions)) {
                lines.add('RAW INSTRUCTIONS OF ' + wastefulLabel + ' ('
                    + formatInt(wastefulInstructions.length()) + ' chars):');
                lines.add('"""');
                lines.add(wastefulInstructions);
                lines.add('"""');
            }
            return String.join(lines, '\n');
        }

        String persona() {
            return 'You are Ohm, an AI sustainability auditor built into Salesforce. You help '
                + 'engineers cut the energy, water, and CO2e footprint of their Agentforce AI '
                + 'agents by removing wasteful, bloated instructions. You are precise, concrete, '
                + 'and calm — never alarmist. Answer ONLY from the CONTEXT provided; if the '
                + 'context does not contain the answer, say so briefly. Cite the real numbers '
                + '(grade, Wh/yr, savings) when they are relevant. Keep answers under 120 words '
                + 'unless asked to draft text.';
        }

        String answerPrompt(String question) {
            return persona() + '\n\n=== CONTEXT ===\n' + contextBlock()
                + '\n\n=== QUESTION ===\n' + question
                + '\n\nAnswer in plain, specific prose. No preamble.';
        }

        String draftPrompt(String question) {
            return 'You are Ohm, an AI sustainability auditor. Rewrite the following Agentforce '
                + 'agent instructions so they are as short as possible while preserving EVERY '
                + 'rule, tier threshold, ordering, and routing behavior exactly. Remove '
                + 'repetition, redundant restatements, and filler. Do not invent new rules. '
                + 'Return ONLY the rewritten instructions as plain text — no explanation, no '
                + 'markdown fences, no preamble.\n\n=== ORIGINAL INSTRUCTIONS ('
                + wastefulLabel + ') ===\n' + wastefulInstructions;
        }

        OhmDTO.AssistantPromptDTO prompt(String id, String label, String text) {
            OhmDTO.AssistantPromptDTO p = new OhmDTO.AssistantPromptDTO();
            p.id = id;
            p.label = label;
            p.prompt = text;
            return p;
        }

        String nvl(String s, String fallback) {
            return String.isBlank(s) ? fallback : s;
        }
    }

    // Signal_Type value -> human label (mirrors the LWC SIGNAL_LABELS map).
    @TestVisible
    private static String signalLabel(String signal) {
        if (signal == null) { return 'a waste finding'; }
        switch on signal {
            when 'INSTRUCTION_BLOAT' { return 'Bloated instructions / scope'; }
            when 'MODEL_RIGHTSIZING' { return 'Model larger than the task needs'; }
            when 'LLM_WHERE_DETERMINISTIC' { return 'LLM used where deterministic code would do'; }
            when 'REDUNDANT_CALLS' { return 'Redundant LLM calls'; }
            when else { return signal; }
        }
    }

    // Thousands-grouped integer for prompts/chips (Apex has no locale formatter here).
    private static String formatInt(Decimal d) {
        if (d == null) { return '0'; }
        Long n = (Long) d.round();
        Boolean neg = n < 0;
        String s = String.valueOf(Math.abs(n));
        String out = '';
        Integer c = 0;
        for (Integer i = s.length() - 1; i >= 0; i--) {
            out = s.substring(i, i + 1) + out;
            if (++c == 3 && i > 0) { out = ',' + out; c = 0; }
        }
        return neg ? '-' + out : out;
    }
}
