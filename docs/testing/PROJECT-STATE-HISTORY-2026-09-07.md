# Archived project state — superseded

This preserves earlier session notes. Use the root PROJECT_STATE.md for current status and remaining work.

# PROJECT_STATE.md — Ohm (source of truth)

> **September 7, 2026 — environmental review implemented with GPT-5.5.** The Salesforce Prompt Builder template `Ohm_Bundle_Environmental_Review` reviews verified Agent Script bundles and linked prompts. Apex owns measurements, exact source/response validation, four category ratings (Input, Output, Model, Calls), coverage and environmental explanations. The model returns flat assessments using code-assigned aliases; Apex groups and saves them atomically after a second freshness check. Empty instructions cannot earn Input/Output A ratings, model fit remains Unrated without quality evaluation, and existing deterministic `run`/`set` bindings cannot justify moving work to code. The UI leads with per-category and per-prompt reviews; legacy detectors and footprint scenarios are supporting evidence. Ask OHM explains saved ratings without another model call. Final deployment `0AfEc00000nZdBzKAK` passed **302 Apex executions, zero failures**; **25 Jest suites / 197 tests passed**, plus the final 8-test UI subset. All four live bundle reviews passed independent checks against 13 instruction snapshots and four configurations. Four bounded reviewer probes passed, including bad prompts, source injection and deterministic chains. The schedule prompt has a supported opportunity to evaluate code for overlap/gap checks and ordering while preserving model presentation. See [evidence](docs/testing/results/2026-09-07/environmental-review/summary.json), [implementation and limits](docs/testing/ENVIRONMENTAL-REVIEW-2026-09-07.md), and [demo runbook](docs/testing/DEMO-RUNBOOK-2026-09-07.md). Scope remains bundle-only; runtime telemetry, model-quality evaluation and automatic publication remain outside this implementation. Work is local and deployed to `ohm-audit-lab`, not committed or pushed. The following entries are prior milestones.

> **September 7, 2026 — current scope: published Agent Script bundles, deployed and verified.** OHM audits each published Agent Script bundle together with the active prompt-template text referenced by its actions. Linked prompts remain part of that bundle audit; they are not independent audit targets. Legacy agents and standalone prompt templates, Flows and Apex classes are outside this scope. Flow/Apex action references provide context; their implementation source is not audited. The four public/controlled demo bundles remain in scope: `ActionDefinitions.v1`, `ActionChaining.v1`, `PromptTemplateActions.v1` and `Ohm_Weather_Demo.v4`. Broad asset discovery is not planned within this scope. Legacy parser utilities are retained for compatibility tests and are outside the production audit path. Deployment `0AfEc00000nZaHKKA0` succeeded with **264 Apex executions, zero failures**; **24 Jest suites / 187 tests passed**. Browser verification confirmed the “Published Agent Script bundles” heading, dependency boundary copy, Bundle table and exactly these four planner rows. See [scope validation](docs/testing/results/2026-09-07/bundle-scope/summary.json). A post-deployment browser re-audit of `PromptTemplateActions_v1` completed (`a00Ec00000lt3JxIAI`), verifying all four source snapshots and the linked prompt's exact 832 characters and active model. The original four baselines remain; the prompt bundle now has an additional same-source comparison. The older invocable graph-analysis helpers are outside this dashboard acquisition path; see the implementation notes. The next entry records the prior retrieval baseline.

> **September 7, 2026 — prior retrieval baseline, before the bundle-only scope change.** Audit buttons queue durable Apex jobs that retrieve published Agent Script and active prompt-template content from Salesforce through renewable OAuth and a Named Credential. Exact publication targets, active template/model bindings, metadata freshness and source hashes are verified before atomic audit completion. Fleet, process and audit screens show progress, resume after refresh and expose source provenance. Four real workflows passed live retrieval; the prompt's exact 832-character hash matches independent Salesforce retrieval. The prior check passed **259 Apex executions and 187 Jest tests**. Old demo audit data was backed up and soft-deleted; four fresh baselines and one prompt-size finding remain, with published agents preserved. Current clean weather publication is still `Ohm_Weather_Demo_v4`. See [current demo runbook](docs/testing/DEMO-RUNBOOK-2026-09-07.md), [implementation/evidence](docs/testing/LIVE-RETRIEVAL-2026-09-07.md), and [connection setup](docs/testing/LIVE-SOURCE-SETUP.md). Missing execution graphs still produce Incomplete coverage; runtime telemetry and automatic apply/revert remain unfinished. Scratch alias **ohm-audit-lab** expires **September 13**. The prior retrieval implementation is local and deployed; it has not been pushed to GitHub. All notes below are historical and are superseded where they conflict with these updates.

> **September 6, 2026 implementation update — historical.** The scoped demo repairs are implemented on `codex/demo-audit-repairs` and deployed to **ohm-audit-lab** (expires **September 13**). Two complete browser remediation loops passed across weather publications v1→v2 and v3→v4. Actual versioned source, honest coverage, stable Tasks/snapshots, source-bound assistant drafts and comparable modeled impact now work. Each trim reduced modeled instruction input **63,742.14→14,782.50 Wh/year** with **1→0 findings**; the same Task reopened and completed with owner/date preserved. **215 Apex test methods + 2 setup executions, 165 Jest tests and 6 importer tests pass.** Five published weather behaviors plus an exact alert execution check pass after the trim. All three public recipe inventories are correct; missing execution graphs still show **Incomplete**, not A. Current clean publication: `Ohm_Weather_Demo_v4`. See [implementation/evidence](docs/testing/DEMO-IMPLEMENTATION-2026-09-06.md) and [demo runbook](docs/testing/DEMO-RUNBOOK-2026-09-06.md). Runtime telemetry, automatic apply/revert and full legacy/RAG support remain follow-on work. Work is local/deployed to the scratch org; it has not been pushed to GitHub.

> **September 6, 2026 independent audit update — read first.** The historical “DEMO-READY / no known defects” assessment below is superseded by [the public-workflow test results and fix plan](docs/testing/DEMO-FIX-PLAN-2026-09-06.md). GitHub `main` was pulled to `038b5a0`; application code remains unchanged. A new scratch org **`ohm-audit-lab`**, expiring **September 13**, hosts Ohm and three published public Agent Script Recipes. All **125 existing Apex tests pass**, while **9 of 10 new acceptance checks fail**. All three public per-process audits discover **0 topics / 0 actions** and return **A/100 / 0 Wh** despite real relationships exposing 6 topics and 8 actions. Relationship fields are populated on these agents, so the null-linkage assumption below is specific to the old fixtures. Actual published instruction source is also missing from discovery. Eleven distinct upstream action checks have passing evidence after lab permission setup; one direct Models API call succeeds. This does not validate the complete public-agent browser/edit/re-audit loop. LocalInfo publishing failed; Coral Cloud is source-only. See [recorded evidence](docs/testing/results/2026-09-06/lab-results.json). The CLI runs natively in zsh on this machine. Prior `ohm` org state and old coverage claims below were not independently revalidated.

> **Historical session notes, September 4, 2026:** retained below for context; use the September 6 plan for current blockers and implementation priority.

**Product:** Ohm — an agentic AI **sustainability auditor** for Salesforce. It audits an org's Agentforce AI agents for wasted compute and estimates their energy / water / CO₂e footprint, then helps trim the waste. A tabbed LWC "Fleet Workbench" on top; Apex + the Einstein Trust Layer underneath.
**Hackathon:** Agentforce for Good, Dreamforce 2026, Builder Track, Earthforce (sustainability) prompt. **GOAL: WIN** — target podium + the **Headless Hero** award.
**Deadline:** submit **Sep 6**, hard close **Sep 7 5:00 PM PT** (today is Sep 4 → ~2 days). Showdown Sep 16.
**Org:** alias `ohm` — EPIC OrgFarm, Enterprise, API v67.0 (expires Oct 7, non-blocking).
**Repo:** github.com/synaptic-dom/ohm-a4g · branch `main` · in sync with origin at **`f299d3b`**.

---

## ⭐ CURRENT STATUS: v2 build COMPLETE, hardened, pushed — DEMO-READY

The v2 "Fleet Workbench" is fully built, adversarially QA'd, and every fix verified live. **Code work is done.** What remains is submission craft (writeups / video / UAT), not features.

**All six surfaces are real and E2E-verified (deployed + browser-driven + screenshots read):**

| Surface | What it does |
|---|---|
| **Fleet** | Lists the org's agents (processes); per-row targeted **Audit** fills in a grade in place |
| **Process page** | Call graph (agent→topic→action, waste flagged) + node **Inspector** (raw instructions, excess highlighted, fix CTAs) |
| **Findings** | Cross-fleet worklist backed by Salesforce **Tasks** (status pipeline, assign, due dates, filters) |
| **Recommendations** | Ranked quick-wins (savings ÷ effort) |
| **Trends** | Inline-SVG footprint trendline + per-agent grade history |
| **Before/after diff** | BEFORE\|AFTER columns + delta; the live **fix→re-audit cool-down** (F→A) proven through `getDiff` |
| **Ask Ohm** (per process) | **Headless grounded assistant** — see below |

**Tests:** 125 Apex 100% pass / **89% org coverage**; 15 Jest (ohmAskAssistant + ohmProcessPage). No known open defects.

---

## How to run / demo (do this to see it live)

1. **`sf` CLI runs via the PowerShell tool only** (the Bash tool can't invoke `sf`). `sf org display` output is a **secret** — never paste it anywhere external.
2. **Demo entry point:** App Launcher → **"Ohm" app**, i.e. URL **`/lightning/app/c__Ohm`**. This reliably lands on the workbench. Do NOT use the "Ohm Audit" tab from within Sales — it can misroute.
3. **Browser drive (Playwright):** scripts live in the session scratchpad `…/scratchpad/pw/`. Pattern: mint a **fresh** frontdoor each run (`sf org open --url-only -o ohm` → write `frontdoor.txt`; frontdoor tokens are **single-use**), then `page.goto(frontdoor)` → `page.goto($OHM_APP)`. Pierce shadow DOM to click (helpers in the existing `v2w6-*.mjs` scripts). App URL: `https://orgfarm-08e0e83a93.my.salesforce.com/lightning/app/c__Ohm`.
4. **Deploy scoped**, never full-project: `sf project deploy start -o ohm -d <path> …` (note: this CLI **rejects mixing `-m` and `-d`** in one call — use all `-d`, class files are valid `-d` paths). Run named test classes; only `--test-level RunLocalTests` for a final gate.

---

## The headless "Ask Ohm" assistant (the award thesis)

The per-process assistant is **fully headless** — the strongest Headless Hero evidence:
- The LLM is invoked **entirely from Apex** via the callout-free **Models API** (`aiplatform.ModelsAPI` → Einstein Trust Layer, model `sfdc_ai__DefaultGPT4OmniMini`). **No connected app, no Agent API, no embedded messaging widget** (connected-app creation is disabled on this org anyway).
- Every answer is **grounded server-side** on the process's real audit: grade, modeled energy, the top finding, and the raw bloated topic scope. Hallucination-clean (verified: it says when a fact isn't in context).
- A **rewrite request** returns *only* the trimmed instructions + a before→after char/token readout (e.g. 5,400→~1,100 chars).
- **Hardened:** prompt injection is **refused** (guardrails in a `system` message + untrusted grounding fenced in `<ohm-data>`), off-topic is redirected, intent classification is precise (a "how much would trimming reduce?" question **answers**, it doesn't draft).

Backend: `OhmAssistantService` (+ `OhmAssistantServiceTest`), doorways `OhmAuditController.getAssistantContext` / `askAssistant`, DTOs `AssistantContextDTO` / `AssistantReplyDTO` / `AssistantPromptDTO`. Front: LWC `ohmAskAssistant` wired into `ohmProcessPage`.

---

## Architecture / key files

**Apex (`force-app/main/default/classes/`):**
- `OhmAuditController` — the unified `@AuraEnabled` door. Fleet/process methods: `getFleet`, `auditProcess`, `getProcessDetail`, `getFindings`, `getRecommendations`, `getTrends`, `getDiff`, finding-status/assign, plus assistant doorways.
- `OhmDiscoveryService` — inline-SOQL discovery of the agent surface. `listFleet()` (cheap), `discoverProcess(plannerId)` (deep), `resolveIdentity(plannerId)` (cheap single-planner), naming-convention join (see gotcha below).
- `OhmPersistenceService` — reports/findings persistence + `loadReadout`.
- `OhmAssistantService` — the headless grounded assistant.
- `OhmDTO` — all DTOs.
- Detectors: `InstructionBloatDetector` (the one that fires), + LLM-where-deterministic / model-rightsizing / redundant-calls.

**LWC (`force-app/main/default/lwc/`):** `ohmApp` (shell/tabs/breadcrumb/Calm), `ohmFleetTable`, `ohmProcessPage`, `ohmCallGraph`, `ohmNodeInspector`, `ohmFindingsWorklist`, `ohmRecommendations`, `ohmTrends`, `ohmDiffView`, `ohmAskAssistant`, `ohmConstants` (shared helpers). FlexiPage `Ohm_Audit` hosts `ohmApp`.

**Custom fields** (all in permission set `Ohm_Data_Access` — FLS required at runtime): `Agent_Audit_Report__c.Target_Type__c` (Fleet/Process), `Target_Planner_Id__c`, `Target_Planner_Api_Name__c`; `Finding__c.Finding_Status__c`, `Instructions_Snapshot__c`.

---

## ⚠️ Critical gotchas (will bite a fresh session)

1. **Org metadata linkage is NULL.** On the deployed agents, `GenAiPluginDefinition.PlannerId` / `GenAiFunctionDefinition.PluginId` / `ParentId` and `GenAiPlannerDefinition.AgentGraph` are **all null**. There is no structural planner↔topic↔action link to query. The join is reconstructed by **DeveloperName naming convention** (distinctive-key matching in `OhmDiscoveryService.bestPlannerFor`, now collision-safe + whole-segment-preferred). Never write `WHERE PlannerId = :x` — always go through `discoverProcess` / `getFleet` / `getProcessDetail`.
2. **No auth chain.** Connected-app creation is disabled on the org → discovery is **plain inline Apex SOQL** on `GenAi*Definition` (no callout, no Named Credential). SPEC canon C13 is superseded by this.
3. **`AuraHandledException` can't propagate in anonymous Apex** — a failing `askAssistant`/`getProcessDetail` call in an `sf apex run` script throws an opaque `System.LimitException: Can only throw this exception type from Visualforce or Aura context` and aborts the script. This is a **test-harness artifact, not a product bug** (in the LWC/Aura context it's caught fine). To probe model behavior in anon apex, call the raw `aiplatform.ModelsAPI` directly (see `scripts/apex/w6_model_direct.apex`).
4. **Frontdoor URLs are single-use** — mint a fresh one per Playwright run.
5. **PowerShell commit messages**: avoid parentheses (parsed as pathspecs); use heredocs / single-line messages. Git commits go through the **Bash tool** (it's a git repo); `sf` goes through **PowerShell**.

---

## Fixtures / current org data

- **`Ohm_Waste_Demo`** ("Lead Concierge (unoptimized)") — the wasteful star: a 5,400-char bloated `Ohm_Waste_LeadTriage` topic scope → audit finds **INSTRUCTION_BLOAT High, grade F, 82,486 Wh/yr**, savings **52,921 Wh/yr** if trimmed. This is the demo spine.
- **`Ohm_Spike_Agent`** — a clean agent (contrast).
- The **fix→re-audit cool-down** is a live demo beat: trim the scope → re-audit → F→A, ~82,486 Wh saved → restore for the next run. Resting diff state is a single F report (clean "ONE AUDIT SO FAR" empty state, no misleading A→F).

---

## What's LEFT for the win (submission craft — NOT code-blocking)

Pick one to start; the user will choose:
1. **Submission writeup** — 300–500 word description **naming Headless Hero** (now genuinely earned by the headless assistant), + RAI self-check, methodology doc, a11y writeup. *(Highest value — these are what judges score.)*
2. **Demo video shot-list** — click-path + narration landing: wasteful→trim→A cool-down, the headless Ask Ohm moment, the injection-refused proof (~2–3 min).
3. **Physical UAT** — user clicks through all six surfaces + Ask Ohm with a guided script before writeups.
4. **More demo** (optional stretch) — a second live finding (a real `MODEL_RIGHTSIZING` or `REDUNDANT_CALLS` fixture) so the audit shows more than one waste type.

Recording the video is the user's to do; everything else I can produce.

---

## Known limitations (documented, acceptable for the demo)

- Only **INSTRUCTION_BLOAT** fires live; the other three detectors are correct but their fixtures aren't seedable on this org (empty AgentGraph, no model binding, needs a prompt template). They degrade gracefully by design. A 2nd live finding is a nice-to-have, not required.
- The naming-convention join is now collision-safe and deterministic, but a genuinely ambiguous name containing two planners' keys as whole segments is resolved deterministically rather than "correctly" (no structural linkage exists to be correct against). Not reachable with the current fixtures.

---

## Commit history (key)

`f299d3b` G1–G12 adversarial hardening · `e61bf6b` Wave 6 headless Ask Ohm · `08fafb9` Wave 5 Trends + diff · `9e99ea3` Wave 4 Findings/Recs · `5b7578b` Wave 3 process page · `dad5ef8` Wave 2 shell+Fleet · `172c104` Wave 1 backend split · `0d1e0c1` backbone.

**Adversarial gap-analysis artifact (all 12 fixed):** https://claude.ai/code/artifact/6010f2ec-f107-4fb4-83c1-f252d143ae97

## Blockers
None.

_Last updated: 2026-09-04 — v2 Fleet Workbench complete + hardened (G1–G12) + pushed to origin (`f299d3b`). Next: submission craft._
