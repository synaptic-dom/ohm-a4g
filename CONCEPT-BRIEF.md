# Ohm: Concept Brief (v3)

**Hackathon:** Agentforce for Good at Dreamforce 2026, Builder Track
**Equality Group prompt:** Earthforce
**Name:** Ohm. The agent of least resistance.
**Product:** AI fleet observability. Ohm is the agent that watches the agents: it itemizes what its own answers cost the planet, keeps a running tally, audits every other agent in the org for wasted compute, and turns findings into remediation tasks.
**Team:** Solo (Dom). Official rules require every team member to be registered for Dreamforce with a full conference pass and attend in person, and the Independent Work clause bars substantive assistance from any other individual. Non-attending Synaptic teammates cannot join or help.
**Status:** v4, feature interview complete + official rules compliance pass, awaiting final approval
**Deadline:** Submissions close Sep 7, 2026, 5:00 PM PT (per official rules). Finalist showdown Sep 16, 4:00 PM PT at Dreamforce.

## Official rules constraints (read Aug 25, PDF in ~/Downloads)

1. **New Work Only.** Submission work products must be created after the Submission Period opens (Aug 28, 9:00 AM EDT). Nothing written before then may ship in the submission. The spike is verification and provisioning only; all real code starts Aug 28.
2. **Independent Work.** No substantive assistance from any other individual. Solo means solo.
3. **Prize stacking is capped.** One podium prize + one special category award + audience vote, maximum. The "triple stack" framing is dead; the strategy is podium plus strongest single special award.
4. **Headless Hero award ($750, Builder Track)** rewards "evaluating agent behavior in production (observability tooling, testing, logging, or metrics ensuring the agent performs reliably, transparently, and safely)." This is Ohm's category verbatim, and a required submission question asks about "responsible AI and Agent Observability in your build." Ohm now has three automatic special-award lanes: Headless Hero, Equality Group Champion, Accessibility Excellence. Note: the rules prize table does not list the Sustainability Award the marketing page mentions; treat it as unconfirmed.
5. **Demonstrability rubric** requires "a working prototype demonstrated in under three minutes." The demo arc must show the working prototype inside a 3-minute window of the 5-minute video.
6. Finalists must confirm Showdown attendance within 48 hours of the Sep 14 announcement email.

## Decisions log

**Concept round (Aug 24):** locked pending spike; solo; constructive-candor tone; name Ohm (beat Wattson, Watt, Bill, Joule); full-rigor methodology; checkpoint Sep 1 with agreed cut order; evaluate Capsule for the demo video; Calm Mode as a shipped feature; actively engineer against estimation-credibility and heart-deficit risks.

**Feature interview (Aug 24):**
1. Product core is B: AI fleet observability. The mock sustainability dataset and general carbon Q&A from v2 are cut entirely. The earlier "real Q&A depth" decision is superseded by this pivot; depth now means audit depth.
2. Receipts show all three metrics every time (energy, water, CO2e). Relatable equivalents available on request, not by default.
3. Tracking is per-answer plus a persistent org-level running tally with trend, backed by an interaction-log custom object.
4. Receipts render as an LWC card in chat via Custom Lightning Type, gated on the spike confirming CLT support in the provisioned org. Structured text fallback ships regardless (Calm Mode and screen readers use it).
5. Audit output is a persistent Audit Report record per agent plus a chat summary with links.
6. Auditor checks all four signals: LLM-to-deterministic replacement, model right-sizing, instruction bloat, redundant call patterns.
7. Action model: audit findings become remediation task records ("this topic could be deterministic, est. savings X Wh/mo") via a single write action.
8. Calm Mode is a persistent per-user preference, respected every session without re-requesting. Accommodations should not need to be asked for twice.
9. Cut order if the schedule collapses: the high-resistance twin degrades to a staged comparison first. Receipts, tally, and live auditor are protected.

## The problem

Companies are deploying AI agents at scale with zero visibility into what that compute costs the planet. Data centers used roughly 415 TWh of electricity in 2024 (about 1.5% of global demand) and the IEA projects that roughly doubles by 2030, with AI the primary driver. Sustainability tooling like Net Zero Cloud tracks flights, buildings, and procurement. Nothing tracks the agent layer, and the agent layer is the fastest-growing compute category in the enterprise.

The Earthforce prompt asks how Agentforce can surface sustainability insights, reduce organizational carbon footprint, and empower climate-informed action. Ohm answers it literally: it surfaces the insight nobody has (what your AI fleet consumes), reduces footprint (right-sized architecture, audit-driven fixes), and turns insight into action (remediation tasks). You cannot manage what you cannot see. Ohm makes it visible, then makes it smaller.

## The product

### Receipts

Every Ohm response ends with a footprint receipt showing all three metrics with uncertainty bands:

> Energy 0.3 to 0.6 Wh | Water 0.2 to 0.4 mL | CO2e 0.1 to 0.3 g
> Org tally this week: 340 Wh across 4 agents. Ask "what does that mean?" for real-world equivalents, or "how do you estimate this?" for methodology.

Rendered as an LWC card in chat (via CLT, spike-gated): headline numbers, uncertainty band, org tally sparkline. Structured text fallback always available.

**Methodology (full rigor):** estimates derive from input/output size against published per-query research (Google's 2025 Gemini paper: median text prompt 0.24 Wh, 0.26 mL water, 0.03 g CO2e; Epoch AI's GPT-4o estimates; IEA fleet data), with per-model differentiation, sensitivity analysis on key assumptions, and uncertainty bands on every receipt. A methodology document ships with the submission, and Ohm itself answers "how do you estimate this?" so judges can interrogate the numbers live.

**Tally:** every interaction logs to a custom object; Ohm reports org-level totals and trends on request. The receipt is a moment; the tally is observability.

### Ohm practices what it preaches

Built in Agent Script with aggressive right-sizing: deterministic routing and flow lookups wherever an LLM call is not needed, small model for classification, large model only for synthesis, concise-by-default outputs. The counterfactual is part of the demo: a deliberately naive "high-resistance" twin agent (throwaway prop, ~2 hours of intentionally lazy build) answers the same question with an all-LLM design and roughly 4x the receipt. Ohm displays the delta and projects it at 10,000 conversations a month.

### Fleet audit

Point Ohm at the org. An Apex action reads agent metadata (planner bundles, topics, actions) and checks four signals:

1. **LLM-to-deterministic:** topics or actions where a flow or formula could replace an LLM call
2. **Model right-sizing:** big-model usage on simple classification or routing steps
3. **Instruction bloat:** oversized system prompts and topic instructions that spend tokens every turn
4. **Redundant call patterns:** multi-call-per-turn designs that could collapse to one

Output: a persistent Audit Report record per agent (judges exploring the org find real artifacts) plus a chat summary. Each finding carries an estimated savings figure.

### Remediation tasks

From any finding, Ohm creates a remediation task record: what to change, estimated savings, link to the report. Assess to act in one conversation. This is the prompt's "empower action" clause, answered in the fleet-observability frame.

### Calm Mode

A persistent per-user accessibility preference: low-stimulation, plain-language responses at a controlled reading level, no decorative formatting, text receipts structured for screen readers, no information carried by color alone. Set once, respected every session. Restraint as accessibility, restraint as sustainability, one design philosophy. Baseline accessibility applies everywhere regardless; Accessibility Expert Skill runs week 1 with findings treated as backlog items and documented responses.

## Demo arc (5 minutes)

1. **Hook (30s):** "Every booth at this conference is selling you agents. Nobody is telling you what they cost the planet. Meet the agent that watches the agents."
2. **Receipt (60s):** Ask Ohm about the org's AI footprint. Answer arrives with the receipt card and org tally. Ask "how do you estimate this?" and it defends its own numbers.
3. **Why so small (60s):** Same question to the high-resistance twin. 4x receipt. Show the Agent Script routing that makes the difference.
4. **Fleet audit (75s):** Run the audit. Report records generate, the twin gets flagged on all four signals, findings carry savings estimates.
5. **Act + Calm Mode (45s):** Turn a finding into a remediation task in one sentence. Flip Calm Mode on, show the same answer restructured. Set once, remembered.
6. **Close (30s):** "We can't make AI free. We can make it visible, and we can make it lean. Energy labels changed buildings, calorie counts changed menus, this is that for AI. And Agentforce is where accountable agents get built."

Video production: evaluate Capsule during the spike; fallback is screen recording with Dom on camera for hook and close.

## Award stack and rubric mapping

| Surface | Fit |
|---|---|
| Accessibility (20%) | Calm Mode as a persistent shipped feature + baseline accessibility + documented Accessibility Expert Skill engagement |
| Responsible AI (20%) | Full-rigor transparency about cost and uncertainty, interrogable live inside the agent; RAI Self Check writeup becomes an asset |
| Demonstrability (15%) | Receipt cards, twin delta, live audit generating records, one-sentence remediation. All visual, all fast |
| Social Impact (20%) | Systemic visibility mechanism plus quantified stakes (agent adoption curves x per-query footprint = fleet-scale impact) |
| Originality (15%) | Self-receipting agents and AI-fleet carbon observability exist nowhere else in the field of 22 |
| Scalability (10%) | Every org deploying Agentforce needs this; natural AgentExchange product story |
| Headless Hero Award | Rules text ("observability tooling ... ensuring the agent performs reliably, transparently, and safely") describes Ohm's product category verbatim; strongest special-award lane |
| Equality Group Champion Award | Earthforce prompt, named explicitly |
| Accessibility Excellence Award | Calm Mode + baseline accessibility design |
| Sustainability Award | Marketing page names it; rules prize table does not. Design for it anyway (it costs nothing extra), treat as unconfirmed |

Prize stacking is capped at one podium prize + one special award (+ audience vote), so the special-award lanes are alternates for judges to pick from, not a stack to sweep.

## Architecture sketch

- **Agent:** Agent Script authoring bundle. Topics: Footprint Q&A (self + org tally), Explain My Estimate, Fleet Audit, Remediation, Calm Mode preference handling
- **Apex actions:** `EstimateFootprint` (size-based, per-model constants, ranges and uncertainty), `AuditAgentFleet` (metadata read + four-signal heuristics + report record generation), `CreateRemediationTask`, `LogInteraction` (tally)
- **Data:** `AI_Interaction_Log__c` (tally), `Agent_Audit_Report__c` (findings), remediation tasks, per-user Calm Mode preference field
- **UI:** LWC receipt card via Custom Lightning Type (spike-gated), text fallback built first
- **High-resistance twin:** throwaway all-LLM agent, exists purely for the comparison demo
- **Org:** provisioned hackathon org (event code FTLINNA3), Agentforce enabled per quick start guide

## Build plan (solo, size L, checkpoint-gated)

| Phase | Window | Work |
|---|---|---|
| Verification spike (S) | Aug 25-27 | Provisioning and throwaway verification ONLY (New Work Only rule): provision org, enable Agentforce, verify Agent Script support, metadata API access, size/token signals, CLT/LWC rendering, evaluate Capsule. No submission artifacts written. Design docs and methodology research fine. |
| Core build (M) | Aug 28-31 | Starts at Submission Period open (Aug 28, 9:00 AM EDT). Agent Script bundle, `EstimateFootprint` full-rigor engine, text receipts, `LogInteraction` + org tally, LWC receipt card if spike cleared it, Calm Mode preference |
| **Checkpoint** | **Sep 1** | **Assess against plan. If behind, apply cut order: twin degrades to staged first. Receipts, tally, and live auditor are protected.** |
| Audit + act (S) | Sep 1-3 | `AuditAgentFleet` with four signals, report records, `CreateRemediationTask`, high-resistance twin |
| Rigor + writeups (S) | Sep 3-4 | Methodology doc with sensitivity analysis, Accessibility Expert Skill + RAI Self Check runs and response writeups, 300-500 word description including quantified stakes, Agent Observability submission question answered with the product itself |
| Video + submit (S) | Sep 5-7 | Record 5-minute demo with working prototype inside a 3-minute window (Capsule or fallback), buffer day, submit Sep 6, never deadline day (hard close Sep 7 5:00 PM PT) |

## Risks

1. **Estimation credibility. Engineered against.** Full-rigor methodology doc, uncertainty bands on every receipt, in-agent "how do you estimate this?" so judges can poke at it live.
2. **Heart deficit. Engineered against.** Quantified-stakes section in the description: agent adoption projections multiplied by per-query footprint equals fleet-scale impact. Close makes the behavioral-change case (energy labels, calorie counts).
3. **Platform reach. Spike resolves.** Auditor needs metadata reads, receipts need size signals, card needs CLT support. Fallbacks: character-count estimation, audit from exported metadata, text-only receipts.
4. **Provisioned org capability unknowns. Spike resolves.** Two-day spike leaves time to reshape.

## Submission checklist

- [ ] 5-minute demo video (YouTube/Vimeo/Drive, unlisted OK)
- [ ] Project description, 300-500 words, includes quantified stakes section
- [ ] Org admin credentials
- [ ] Accessibility Expert Skill output + response writeup
- [ ] RAI Self Check output + response writeup
- [ ] Methodology document (full rigor)
- [ ] Earthforce prompt named for Equality Group Champion consideration
- [ ] Sustainability Award design-decisions section
- [ ] Optional: GitHub repo, screenshots
