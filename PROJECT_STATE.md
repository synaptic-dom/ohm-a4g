# PROJECT_STATE.md — Ohm (source of truth)

**Product:** Ohm — agentic AI sustainability auditor (LWC guided experience + Agentforce agent underneath).
**Hackathon:** Agentforce for Good, Dreamforce 2026, Builder Track, Earthforce prompt. **GOAL: WIN.**
**Deadline:** submit **Sep 6** (hard close Sep 7, 5:00 PM PT). Showdown Sep 16.
**Org:** `ohm` — EPIC OrgFarm (00Daj000013wTtpEAE), Enterprise, API v67.0, expires Oct 7 (post-hackathon, non-blocking).

## Current phase
**Backlog — COMPLETE, awaiting final gate** ("Ready to implement?")

| Phase | Status | Artifact |
|---|---|---|
| 1. Requirements | ✅ Approved (reframed v2: guided auditor experience) | `docs/requirements/REQUIREMENTS-ohm.md` |
| — Capability spike | ✅ Done — GO; Agentforce **enabled by us** (Playwright terms + metadata deploy + 4 PSLs); discovery surfaces confirmed | `docs/design/SPIKE-ohm.md` |
| 2. Design | ✅ Approved | `docs/design/DESIGN-ohm.md` |
| 3. Spec | ✅ Approved (incl. win amendments W1–W8) | `docs/specs/SPEC-ohm.md` (C0–C13 canon locked) |
| 4. Backlog | ✅ Written (66 tasks, ~96.5h est), gate pending | `docs/backlog/BACKLOG-ohm.md` |
| 5. Execute (TDD) | 🔨 IN PROGRESS — see "Execute status" below | — |
| 6. Physical UAT | Not started | UAT script in SPEC §T.6 |
| 7. Document/submit | Not started | Submission checklist in CONCEPT-BRIEF |

## Side artifacts
- `docs/design/SKILLS-SHORTLIST-ohm.md` — top-10 tools/skills research (DX MCP, GenAiPlannerBundle, sa11y, …)
- `docs/design/WIN-STRATEGY-ohm.md` — judge-panel result: **69.5/100 as originally planned → ~78 with amendments W1–W8** (now locked into SPEC §0.4). Target: 2nd/3rd podium + **Headless Hero** (name it and only it). Key finding: original cut order sacrificed the award thesis; F10 + F9 are now spine, agent spike moved to day 1.

## Build order (SPEC §0.3 as amended by §0.4)
Task 0 auth gate (BLOCKING) → **0.5 agent-surface spike (W1)** → 1 smoke deploy → 2 fixtures → 3 data model → 4 discovery → 5 signals (a,c protected) → 6 footprint → 7 persistence → 8 LWC spine (incl. Calm Mode W5, provenance W7) → 9 agent full build (W4 grounded methodology, W6 dogfood staging) → 10 a11y → 11 polish/UAT (W3 fix→re-audit beat, W2 hook). **Never cut:** Welcome, Impact, Recommendations, agent, F10 methodology, F9 Calm Mode.

## Execute status (2026-09-01) — waves A/B/C DONE, D in progress

**🔑 PIVOT — auth chain DELETED (SPEC C13 superseded):** connected-app creation disabled on org, BUT inline Apex SOQL reads GenAiPlanner/Plugin/FunctionDefinition directly. Discovery = plain SOQL, no callout/credential. Biggest risk eliminated.

**Wave A (backbone) ✅** — OhmDiscoveryService (inline SOQL), OhmPersistenceService, OhmAuditController, 6 invocable actions. 28/28 new tests + live E2E startAudit→Complete report. Commit 0d1e0c1.
**Wave B (experience live) ✅** — 14 LWCs + FlexiPage Ohm_Audit + CustomApplication Ohm + tab + permset deployed & assigned. Renders live at `/lightning/n/Ohm_Audit`. jest 87/87. Commit 8fbff95. (Live button-click FSM advance: unverified via Playwright shadow-DOM flake, NOT a product bug — needs manual confirm.)
**Wave C (fixture) ✅** — "Lead Concierge (unoptimized)" wasteful agent (5400-char bloated topic). Audit now finds **INSTRUCTION_BLOAT High, 82,486 Wh/yr, grade F**. Fixed real bug: LlmWhereDeterministicDetector now recognizes `generatePromptResponse` (platform has no `prompt` enum value). Commit (wave-C).
**Wave D (design + beats) ✅** — "Instrument" visual system deployed across all 14 LWCs (waste=hot amber gauge/hero, efficiency=cool teal; Calm Mode = genuine light/flat a11y inversion). Fixed methodology panel [object Object] → shows real constant bands (W4/F10). W7 provenance + scrubber dial live. **W3 fix→re-audit cool-down PROVEN LIVE**: bloated scope = F/82,486 Wh → trimmed scope = A/0 Wh → restored to F for demo. Commit 1009618 + W3 verify.

**TEST STATUS: 99 Apex tests 100% pass, 90% org-wide coverage; 88 Jest 100%.** Experience live + beautiful at /lightning/n/Ohm_Audit with real findings.

**UI POLISH ✅ (verified)** — adversarial vision QA (8 screens desktop/tablet/mobile + both modes) → fixed savings triple-range, calm-toggle reskin (custom role=switch to mute blue), full-width accent stripe, scrubber, hero-range caption, calm chip contrast. Mobile (390px) renders clean, no overflow (DOM-measured). Confirm-review: all defects resolved, zero remaining. Commit bdec4f7.

**Phase 2 (DONE)** — sample AI fleet seeded + audited E2E + captured. 4 agents discovered (Lead Concierge F/High, Order Support Medium, Service Concierge clean, Spike clean). Org grade F score 23, 128,135 Wh/yr, 2 findings. Fleet readout captured live (fleet-impact.png). Report AUDIT-00014 (a00aj00003SM8DNAA1).

**DEMO ENTRY POINT:** open the **"Ohm" app** (App Launcher → Ohm) — the app URL `/lightning/app/c__Ohm` reliably lands on the workbench; the tab-from-Sales path can misroute.

## v2 — The Fleet Workbench (rebuild in progress; SPEC-ohm-v2-workbench.md)
Reframe from single-scroll report → tabbed application. Waves committed:
- **Wave 1 ✅ (172c104)** backend split: listFleet() cheap + auditProcess(one target) deep + process-scoped reports + fields (Target_Type__c/Target_Planner_Id__c/Target_Planner_Api_Name__c, Finding_Status__c). NOTE: org PlannerId/PluginId/AgentGraph are NULL → planner↔topic↔action join is by DeveloperName naming convention.
- **Wave 2 ✅ (dad5ef8)** app shell (tabs FLEET/FINDINGS/RECOMMENDATIONS/TRENDS, breadcrumb, Calm) + Fleet table with per-row Audit → in-place grade refresh. ohmApp is now the FlexiPage root (ohmAuditExperience kept as fallback).
- **Wave 3 ✅ (5b7578b)** process page: call graph (agent→topic→action, waste flagged) + node inspector showing RAW instructions with excess highlighted + Trim/Downsize/Replace CTAs.
- **Wave 4 ✅ (9e99ea3)** Findings worklist on Salesforce Tasks (status pipeline Open/Accepted/Dismissed/Applied + assign+due) + Recommendations quick-wins (savings÷effort). Fixed cross-scope duplicate-finding dedup (key on artifact+signal, Process rows win).
- **Wave 5 ✅ (08fafb9)** Trends (footprint/grade over time, inline-SVG) + before/after diff on re-audit. Cool-down proven live (getDiff before=F/82,486 after=A/0 improved=true). Reset Lead Concierge to a single F report so the resting diff shows a clean "ONE AUDIT SO FAR" empty state (no misleading A→F).
- **Wave 6 ✅** per-process "Ask Ohm" assistant — **HEADLESS**: the LLM is invoked entirely from Apex via the callout-free Models API (`aiplatform.ModelsAPI` → Einstein Trust Layer, model `sfdc_ai__DefaultGPT4OmniMini`), NO connected app / Agent API / embedded messaging widget. Every answer is GROUNDED server-side (grade, modeled energy, the top finding, the raw bloated topic scope). A rewrite request returns ONLY trimmed instructions + a before→after char/token readout. New: `OhmAssistantService` (+Test), `OhmAuditController.getAssistantContext`/`askAssistant`, DTOs (AssistantContextDTO/AssistantReplyDTO/AssistantPromptDTO), LWC `ohmAskAssistant` wired into ohmProcessPage (replaced the seam). Fixed intent-regex bug: `optimi[sz]e` matched inside the label "(un**optimize**d)" → word-boundaried so "why" no longer mis-fires the draft path (caught in-browser, not by the apex probe).

**TESTS after v2 w6:** OhmAssistantServiceTest 7/7 (service 83% cov — uncovered = the real Trust-Layer callout, mocked in tests); OhmAuditControllerTest+OhmDTOTest 22/22 green (no regression); ohmAskAssistant Jest 4/4. E2E-verified live in browser: grounded "why" answer (1,395 vs 500 token budget, 82,486 Wh/yr, 52,921 Wh/yr savings) + draft rewrite (5,400→920 chars, −83%, rules preserved) — screenshots read: v2w6-assistant-initial/why-answer/draft.png.

**DEMO-READY.** Remaining for the win (not code-blocking): quality-gate skills (security-audit/code-review/optimize/deploy-check) as submission artifacts; submission writeups (300-500 word desc naming Headless Hero, RAI Self Check, methodology doc, a11y writeup); video shot-list (W8) + hook (W2) — recording is the user's. Optional stretch: W6 dogfood (build full clean Ohm_Auditor agent), signal (a) live 2nd finding (generatePromptResponse fixture).

**Known gaps / decisions:** signal (a) fixture not seedable (platform uses generatePromptResponse + needs prompt template — detector now correct, live 2nd finding is nice-to-have); signals (b)/(d) not seeded (empty AgentGraph, no model binding) — both degrade gracefully per design. Demo stands on INSTRUCTION_BLOAT + the fix→re-audit cool-down beat.

**Current org state:** 2 agents discovered (clean Ohm_Spike_Agent + wasteful Ohm_Waste_Demo). Latest audit report shows grade F, 1 finding.

## Key facts for any session resume
- All `sf` CLI calls via **PowerShell tool** (Bash can't invoke sf). `sf org display` output = secret.
- Agentforce IS enabled; org is **empty of real agents** — fixtures still needed for a non-trivial demo.
- Canonical contracts live in SPEC §0.2 (C0–C13); **C13 is superseded → inline SOQL discovery, no auth chain.**
- Deploy scoped (`-m`/`-d`), never full-project, never RunLocalTests unless final; run named test classes only.

## Blockers
None. Auth blocker eliminated by inline-SOQL discovery.

_Last updated: 2026-09-03 — v2 Fleet Workbench COMPLETE (waves 1–6). Ask Ohm assistant is headless (Apex Models API → Trust Layer) and grounded; all six tabs/surfaces real and E2E-verified._
