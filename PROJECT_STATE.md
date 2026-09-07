# Ohm — current project state

_Last updated: September 7, 2026. Checkpoint requested by the user to conserve usage. This file supersedes all older readiness claims._

## Resume here

**As of the Sept 7 evening session the hackathon org is demo-ready: the four fixture agents are published and active (as Service agents), the Ohm core app is installed with all local tests passing, the source connection is configured, all four bundles have current GPT 5.5 reviews, and the new environmental footprint strip is deployed (see the evening-session section for every ID).** The only remaining step is the browser rehearsal / recording. The scratch org remains the earlier verified implementation.

The user authorized completing the event install, test data, UI polish, and five-minute demo. No additional permission is needed for those steps. No commit, push, public submission, or third-party message has been requested. At this checkpoint, stop new org operations; resume from the list below when the user continues.

- Workspace: `/Users/dom/Documents/ohm-a4g`
- Repository: `github.com/synaptic-dom/ohm-a4g`
- Branch: `codex/demo-audit-repairs`
- Many tracked edits and new files are intentionally uncommitted. Preserve them. Do not reset or pull over the working tree.
- Native Salesforce Apex/LWC, API 67.0. Node, Python, and `sf` run natively in zsh on this machine. The old PowerShell-only instructions are obsolete.
- Earlier state is preserved in [PROJECT-STATE-HISTORY-2026-09-07.md](docs/testing/PROJECT-STATE-HISTORY-2026-09-07.md). It contains obsolete architecture and readiness statements; use it only as history.

## Current product decisions

- Audit only **published Agent Script bundles**, including active prompt text linked from their actions. No standalone prompt targets, legacy agents, or separate Flow/Apex implementation audits. Action references still provide structural context.
- User-facing categories are **Input / Output / Calls**. Model Fit is removed from the UI. The persisted reviewer schema still contains four categories for compatibility; do not casually change that contract.
- The Salesforce Prompt Builder reviewer interprets instruction meaning. Apex computes facts, verifies exact source quotes and freshness, applies rating rules, and persists results atomically. No invented ratings, successful-review fallbacks, or measured energy claims.
- Main navigation: **Overview / Bundles / Recommendations**. No Calm Mode or Trends. Evidence details remain available on demand.
- Loading/progress follows real retrieval and review jobs, including queued/error states. No pretend progress or completion.
- Recommendations must lead to the exact source, preserve required behavior, explain validation, and create a readable real Salesforce Task.

## Target orgs

### Hackathon org — destination for all remaining work

| Field | Value |
| --- | --- |
| CLI alias | `ohm-hackathon` |
| Org ID | `00Daj000013wTtpEAE` |
| Username | `epic.f1c1977a25ca@orgfarm.salesforce.com` |
| Admin User ID | `005aj00000boA3hAAE` |
| Domain | `https://orgfarm-08e0e83a93.my.salesforce.com` |
| Edition | Enterprise; `IsSandbox=false` |
| Event | Agents for Good Hackathon at Dreamforce; event code `FTLINNA3` |
| Expiry | September 23, per user |

[Event app URL](https://orgfarm-08e0e83a93.lightning.force.com/lightning/n/Ohm_Audit?c__scope=agentScript&c__review=v1&c__ui=studio)

CLI authorization succeeded. Do not reauthenticate unless the saved connection fails. Never print `sf org display` access tokens, email login links, OAuth secrets, or credential setup payloads.

Read-only preflight verified API67, AgentScript metadata capability, Einstein Platform, Agent Platform, Bots, and Copilot enabled. OpenAI/Azure provider-disable flags are false. **Deploy prompt templates as active is false**, so inspect/activate intended versions after deployment rather than changing global policy. Existing `Ohm_App_Access` and `Ohm_Data_Access` were already assigned, but that does NOT prove current code is installed. Prompt Template User/Manager permissions were missing at preflight; no new assignments were made before this checkpoint.

### Scratch org — current verified implementation

- Alias `ohm-audit-lab`, org `00DEc00000kvSbNMAU`, expires September13.
- Username `test-0w1smir2zegu@example.com`.
- [Scratch app](https://innovation-inspiration-231-dev-ed.scratch.lightning.force.com/lightning/n/Ohm_Audit?c__scope=agentScript&c__review=v1&c__ui=studio).
- Existing four bundles: ActionDefinitions_v1, ActionChaining_v1, PromptTemplateActions_v1, Ohm_Weather_Demo_v4.
- Keep this working installation intact. Do not use these old sample bundles to populate the new event demo.

## Completed implementation

### UI and loading

The studio redesign is implemented and deployed to scratch: new Overview hero (“Better agents. Lighter footprint.”), real reviewed/opportunity counts, clear next action, simplified searchable bundle list, three ratings, source workspace, and recommendations. New components include `ohmOverview`, `ohmLoadingState`, and `ohmDisplay`. `ohmApp` owns navigation, keyboard tab movement, and scroll/focus reset. Loading visuals respect reduced motion. Real audit polling, resumption, failure, and retry remain intact.

The review page merges bundle and individual-artifact issues; previously the useful linked-prompt finding was missing from the primary list. “Review this change” selects the exact source and prepares Ask without automatically sending or stealing focus from the source. Three short category headings fit narrow screens. Raw IDs, hashes, legacy metrics, and structure are behind disclosures. Some unused legacy properties/components remain in source for compatibility, but removed surfaces are not in the app navigation.

### Recommendations and Tasks

New `OhmReviewRecommendationService` reads accepted current-source/current-reviewer saved issues and returns real semantic recommendations. No model call is needed to list them. Task creation revalidates the report, evidence identity, current source, and reviewer version, with locked duplicate protection.

New field: `objects/Activity/fields/Ohm_Review_Key__c.field-meta.xml`; Task FLS in `Ohm_Data_Access`. Internal identity lives in that field, not the Task subject. Readable subject/body preserve original quotes and Change/Why/Keep/Test guidance. Editing a Task subject does not create duplicates. The original legacy `OhmRecommendationService` still exists and was restored after a temporary local filename collision; do not replace it with the new service.

Scratch Task `00TEc00000aB0WDMA0` was repaired with exact-ID guards to “Review schedule validation — Generate Personalized Schedule”. Owner, status, and report were preserved. `/tmp/ohm-review-task-readability-live-proof.json` verifies it.

### Retrieval and reviewer

- Renewable same-org source connection retrieves and pins the published AgentScript and active linked prompts, then verifies publication, content hashes, active model/version, and freshness before review completion.
- Reviewer template: `Ohm_Bundle_Environmental_Review`; model `sfdc_ai__DefaultGPT55`; rubric `OHM_ENVIRONMENTAL_REVIEW_V1`.
- Real invocation: `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`, not preview; one generation, no GPT5 temperature override.
- Evidence uses aliases and exact quotes. Invalid model output fails atomically. Existing deterministic `run`/`set` configuration cannot alone support a “move to code” finding.
- A = no material issue in sufficient reviewed evidence; B = supported opportunity; C = deterministic hard-budget exceedance; Unrated = missing evidence. These are not measurements of energy consumption.
- Saved-review Ask answers use the selected source and existing accepted review, with no extra model call. Generated drafts use the existing Models API path and stay source-bound.

## Verified tests and deployments — scratch only

| Check | Result / proof |
| --- | --- |
| Main studio app + assistant deployment | `0AfEc00000nZUWtKAO`; 310 Apex executions, zero failures; `/tmp/ohm-ui-rework-deploy.json` |
| Final UI polish | `0AfEc00000nZbDOKA0`; succeeded; `/tmp/ohm-ui-final-polish-deploy.json` |
| Final full Jest | 26 suites / 209 tests, zero failures; `/tmp/ohm-ui-final-jest.json` and `.log` |
| Task field/readability service | `0AfEc00000nZiGTKA0`; 11 focused Apex tests passed; `/tmp/ohm-review-task-readability-deploy.json` |
| Live scratch UI re-audit | PromptTemplateActions report `a00Ec00000lswLvIAI` reached Complete; started 19:24:54 UTC September7 |

Do not describe these as successful event-org validation. The final event UI still needs rehearsal, including cache refresh, readable Task, source-first scroll, and actual reviewer/model access.

## New event fixture source — prepared, NOT deployed

[Fixture project](test-fixtures/event-demo/) contains self-contained Employee AgentScript bundles, four linked prompt templates, `OhmDemoScheduleService` + four Apex tests, permission set `Ohm_Event_Fixture_Access`, scenarios, four eval specs, pinned provenance, license, generator, and local checks.

| Bundle API / human label | Intended review case |
| --- | --- |
| `Ohm_Support_Desk` / Customer Support | Same support policy repeated six times: Input opportunity |
| `Ohm_Sales_Follow_Up` / Sales Follow-up | Eight email variants plus unused formats: Output opportunity |
| `Ohm_Schedule_Planner` / Schedule Planning | Prompt calculates end times, chronological ordering, overlap and sixty-minute gaps: Calls opportunity |
| `Ohm_Schedule_Desk` / Efficient Schedule Desk | Actual Apex computes the rules; linked prompt presents validated results: control |

These are deliberately synthetic test cases adapted from pinned public Salesforce recipe wiring; do not attribute the inserted inefficiencies to upstream authors. Ratings are not preassigned. They use primitive String inputs, no Data Cloud, no custom business objects, and no email, bookings, outbound service, or business-record writes. Apex schedule code validates input, sorts deterministically, uses earliest-compatible selection, and explicitly does not claim global optimization.

Local XML, links, provenance, source extraction checks passed via `python3 test-fixtures/event-demo/scripts/check-fixtures.py`. Platform compilation, publication, activation, runtime action smoke tests, and OHM audits remain pending.

The [fixture README](test-fixtures/event-demo/README.md) contains exact deployment and publication commands. All agents have stopped org operations; no commands remain in flight. An isolated publication copy exists at `/tmp/ohm-event-fixtures-runtime`. Publication mutates local authoring metadata; preserve repository originals. **Pass this exact working directory to exec tools.** A command with relative paths run from root will select the wrong `force-app` tree. A future session may recreate the runtime copy from current source if `/tmp` is gone.

## September 7 evening session — fixture install progress and publish blocker

Completed in the hackathon org (all receipts nonsecret):

| Step | Result |
| --- | --- |
| Fixture dependencies (classes, genAiPromptTemplates, permissionsets) from `/tmp/ohm-event-fixtures-runtime` | Deploy `0Afaj00000jVrVxCAK` Succeeded; 7/7 components; `OhmDemoScheduleServiceTest` 4/4 passed; `/tmp/ohm-event-fixture-deps-deploy.json` |
| Linked prompt templates | All four deployed with `activeVersionIdentifier` matching source; verified by retrieve. No manual activation needed. |
| Permission sets assigned to admin | `Ohm_Event_Fixture_Access`, `EinsteinGPTPromptTemplateUser`, `EinsteinGPTPromptTemplateManager` (admin already had `CopilotSalesforceAdmin`, `CopilotSalesforceUser`, `AgentforceDeveloperAndAdminTools` since Sept 2) |
| `sf agent validate authoring-bundle` | All four bundles succeed |
| Authoring bundles deployed as metadata | Deploy `0Afaj00000jVvbBCAS` Succeeded 4/4; org lists `Ohm_*_1`; no BotDefinition created (deploy stores source only) |

**Publish blocker, root cause verified.** `sf agent publish authoring-bundle` fails for all four bundles. The real response from `POST https://api.salesforce.com/einstein/ai-agent/v1.1/authoring/agents` is HTTP 401: "Looks like you don't have access to agent templates associated with the AgentforceEmployeeAgent agent type." The CLI masks this: on 401 jsforce refreshes the session and retries with a plain org token (bare 404), then `requestWithEndpointFallback` tries `test.api.salesforce.com`, which is unreachable from this network (TCP connect to 443 times out), so the CLI reports an empty `FetchError`. Yesterday's log shows the same failure.

Ruled out: user permissions (admin has effective `EinsteinCopilotBuilder`/`EinsteinAgentPlatformBuilder`; scratch user has neither and publishes fine), org settings (`EinsteinGpt`, `AgentPlatform`, `EinsteinCopilot` match or exceed scratch), JWT scopes (compile on same host succeeds). The check is org-level Employee Agent template licensing. Scratch has `AgentPlatformBuilderPsl` and `TaskBasedAgentsPsl`; the hackathon trial does not. The hackathon org does have `AgentforceServiceAgentBuilderPsl` (10000) and `AgentforceServiceAgentUserPsl` (200).

**Decision (user, Sept 7):** switch the four fixtures to `AgentforceServiceAgent` with a dedicated Einstein Agent User as `default_agent_user`, update provenance, republish. Ohm discovery reads `GenAiPlannerDefinition` regardless of agent type, so audits are unaffected.

**Outcome: all four fixture agents are published and active in the hackathon org.**

- Einstein Agent User created: `ohm.fixture.agent@orgfarm-08e0e83a93.ohm` (`005aj00000dVdUrAAK`, profile Einstein Agent User) with `AgentforceServiceAgentBase`, `AgentforceServiceAgentUser`, `EinsteinGPTPromptTemplateUser`, `Ohm_Event_Fixture_Access`.
- Generator `test-fixtures/event-demo/scripts/prepare-fixtures.py` now emits `agent_type: "AgentforceServiceAgent"` + `default_agent_user`; PROVENANCE regenerated; local checks pass; `company_name` is not a valid config field.
- Bundles redeployed as Service type: `0Afaj00000jW1wjCAC` (4/4). Publish succeeded for all four (`summary.deployed=3` each). Activation `--version 1` succeeded for all four; `BotVersion.Status = Active`.
- IDs (Bot / BotVersion / Planner): Schedule_Desk `0Xxaj000004AwzhCAC` / `0X9aj0000073iEzCAI` / `Ohm_Schedule_Desk_v1` `16jaj000003G45xAAC`; Support_Desk `0Xxaj000004Ax1JCAS` / `0X9aj0000073iGbCAI` / `Ohm_Support_Desk_v1` `16jaj000003G47ZAAS`; Sales_Follow_Up `0Xxaj000004Ax2vCAC` / `0X9aj0000073iIDCAY` / `Ohm_Sales_Follow_Up_v1` `16jaj000003G49BAAS`; Schedule_Planner `0Xxaj000004Ax4XCAS` / `0X9aj0000073iJpCAI` / `Ohm_Schedule_Planner_v1` `16jaj000003G4AnAAK`.
- Receipt: [fixture-install-receipt.json](docs/testing/results/2026-09-07/event-checkpoint/fixture-install-receipt.json).
- Remaining-steps list below: steps 2 and 3 are done. Note for step 1: the hackathon org already contains an `Ohm_Waste_Demo` planner (`16jaj0000038D3BAAU`, Sept 2), so `OhmAuditControllerTest`'s legacy-rejection test passes unchanged there; `OhmAuditTestSupport` finds `Ohm_Schedule_Desk_v1`.

**Core app validation (step 4, check-only) `0Afaj00000jW409CAC`:** 213/213 components, 0 component errors, **282/283 tests passed**. All 20 fixture-dependent failures from the morning attempt now pass. The single failure was `OhmDiscoveryServiceTest.test_listFleetReturnsProcessesWithCountsAndDomainsNoGrade` asserting `domainsSeen.size() >= 2`; `deriveDomain` maps every `Ohm_*` fixture to `Internal`, so that assertion was fixture-specific. Test-only fix applied: assert every fleet row's domain is in the documented keyword-map set instead.

**Core app deployed to the hackathon org (step 4 DONE): `0Afaj00000jW4o9CAC` Succeeded, 212/212 components, 0 component errors, 283/283 Apex tests passed** (`RunLocalTests`; source dirs classes, objects, lwc, staticresources, applications, tabs, flexipages, permissionsets, genAiPromptTemplates; `settings` and legacy genAi* folders excluded). Local proof `/tmp/ohm-event-app-deploy-final.json`.

**Post-deploy verification (steps 5–6 partially DONE):**
- Reviewer template `Ohm_Bundle_Environmental_Review` retrieved from the org: `activeVersionIdentifier` `WCyeBTg2NZWRDVRViggPve0yyaQfI6t9+0AlEdZ1LCQ=_1`, model `sfdc_ai__DefaultGPT55`, status Published. No manual activation needed.
- Fleet smoke test via anonymous Apex `OhmAuditController.getFleet()`: 4 rows — the four `Ohm_*_v1` planners with topic/action counts (control has 2 actions: Apex + prompt).
- Source connection created with `scripts/source/setup-connection.py` (run-as and audit user = admin, contact `dominick@synaptic.build`): status `Configured`, mode `create`, original settings restored, temporary setup permission removed, no credential values printed. Deployment steps `0Afaj00000jW0uECAS`, `0Afaj00000jW5p3CAC`, `0Afaj00000jVoMoCAK`, `0Afaj00000jW5ttCAC`, `0Afaj00000jW5vVCAS`, `0Afaj00000jW60LCAS`. Nonsecret output `/tmp/ohm-event-source-setup.json`. Pre-existing `Ohm_Self_ECA` (Sept 2) is unrelated and untouched.
- Live reviewer/model execution verified: see the audit results below.

**Real Ohm audits of all four event bundles (step 7 DONE), started via anonymous Apex `OhmAuditController.auditProcess(plannerId)`; all reached `Complete` with reviewer `Salesforce Prompt Builder`, model `sfdc_ai__DefaultGPT55`, template version `WCyeBTg2NZWRDVRViggPve0yyaQfI6t9+0AlEdZ1LCQ=_1`. Observed ratings (not preassigned):**

| Bundle | Report | Input | Output | Calls | Reviewer issues |
| --- | --- | --- | --- | --- | --- |
| `Ohm_Support_Desk_v1` | `a00aj00003WVjcnAAD` | **C** | A | A | `INPUT_REDUNDANCY`, `INPUT_HARD_BUDGET` |
| `Ohm_Sales_Follow_Up_v1` | `a00aj00003WVjcoAAD` | A | **B** | A | `OUTPUT_UNNECESSARY_VERBOSITY`, `OUTPUT_FORMAT_MISMATCH` |
| `Ohm_Schedule_Planner_v1` | `a00aj00003WVjcpAAD` | A | A | **B** | `CALLS_DETERMINISTIC_ALTERNATIVE` |
| `Ohm_Schedule_Desk_v1` (control) | `a00aj00003WVjPtAAL` | A | A | A | none |

Model Fit is `UNRATED`/coverage Unknown on all four, so `Coverage_Status__c = Incomplete` and legacy `Efficiency_Grade__c = IN` — identical to the verified scratch reports from earlier today (UI shows the three category ratings; `IN` means Incomplete). `Findings_Count__c = 1` per report. Independent verification: `scripts/testing/collect-review-results.py` → [review-results.json](docs/testing/results/2026-09-07/event-org/review-results.json), `allVerified: true` for all four (source hashes, quote continuity, Fleet/detail consistency). Source retrieval used the new connection: retrieval state keys `AiAuthoringBundle:Ohm_*_1` and the linked `GenAiPromptTemplate`, zero retries.

**Recommendations tab data verified via anonymous Apex `OhmReviewRecommendationService.getReviewRecommendations(plannerId)`** (the method the LWC calls; `sourceCurrent=true` on all four): Schedule Planning → 2 items (`CALLS_DETERMINISTIC_ALTERNATIVE` on the bundle and the `Plan Day` action); Customer Support → 4 items (`INPUT_REDUNDANCY` + `INPUT_HARD_BUDGET`, bundle and `Draft Support Reply`); Sales Follow-up → 4 items (`OUTPUT_UNNECESSARY_VERBOSITY` + `OUTPUT_FORMAT_MISMATCH`, bundle and `Draft Follow Up`); Efficient Schedule Desk → 0 items, reason "No changes were recommended in the current saved review. Unknown coverage still needs evaluation." The legacy `OhmAuditController.getRecommendations` still returns 3 stale Sept 2 `Ohm_Waste_Demo`/Fleet items, but no current LWC imports it; the org holds 20 legacy Sept 2–3 reports and 18 planner-less findings that do not affect Overview counts (per current planner) or the Recommendations tab. No Ohm Tasks exist yet.

**Fixture evals (step 8 DONE) via `sf agent test run-eval` against the active Service agents: 7/8 cases passed** (bot_response_rating threshold 3.0, all scored 5/5) — the one failure is `Ohm_Schedule_Planner` `schedule-day` (score 2/5): the prompt-computed plan kept the overlapping `Clay studio` row that the Apex control (`Ohm_Schedule_Desk` `control-day`, 5/5) correctly omitted. That is behavioral evidence for the Calls B recommendation, not a fixture defect. Trimmed evidence: [evals/](docs/testing/results/2026-09-07/event-org/evals/).

**Model decision (user, Sept 7 evening): no GPT-4o mini anywhere; use the latest model.** A Models API probe from anonymous Apex showed these aliases generate in the hackathon org: `sfdc_ai__DefaultGPT55`, `DefaultGPT5`, `DefaultGPT5Mini`, `DefaultGPT41`, `DefaultGPT41Mini`, `DefaultOpenAIGPT5`, `DefaultVertexAIGemini25Flash001`, `DefaultBedrockAnthropicClaude4Sonnet`, `DefaultBedrockAnthropicClaude45Sonnet`, `DefaultGPT4Omni`, `DefaultGPT4OmniMini`; `DefaultGPT55Mini`, Gemini 2.5 Pro and Gemini 3.0 Pro do not. GPT 5.5 is the newest working alias, so:
- Ask Ohm: `OhmAssistantService.MODEL_NAME = 'sfdc_ai__DefaultGPT55'`, label `GPT 5.5 · Einstein Trust Layer` (Jest mock label updated too). Deployed with `RunSpecifiedTests OhmAssistantServiceTest`: `0Afaj00000jW7ajCAC` Succeeded, 27/27.
- Four fixture prompts: generator `PROMPT_MODEL = 'sfdc_ai__DefaultGPT55'`, model included in the version hash so new versions were published rather than mutating the active ones. Deploy `0Afaj00000jW7cLCAS` Succeeded 4/4; retrieve confirms the new identifiers are active (`Ohm_Support_Reply` `31QM9vZYaYGCYPXHuMnRtW+weKTVFFx+hcNF+0lbong=_1`, `Ohm_Sales_Follow_Up_Email` `idRnqeRNdIt+HAaNMKSN8f/HV1Axqun4xLtFTqte6do=_1`, `Ohm_Plan_Day` `L1PNBZ6TQ9eEd55V7vLGp3/nCjcpAye+Zd078e8PLGY=_1`, `Ohm_Present_Validated_Plan` `KOgTdSzVM2/3z2KU2t/XM9yiO7qX46j5hEljCJFkikc=_1`). The org's deploy-as-active=false setting did not block activation here.
- Because the linked prompt versions changed, all four bundles were re-audited afterward and the evals were rerun against GPT 5.5.

**Fresh saved reviews (current for the demo), all `Complete`, same ratings as before:** Schedule Desk `a00aj00003WVl57AAD` A/A/A; Support Desk `a00aj00003WVlczAAD` **C**/A/A (first retry attempt `a00aj00003WVl58AAD` failed atomically with "Reviewer evidence does not match the exact published source" — the designed rejection of unverifiable model quotes; the retry passed); Sales Follow-up `a00aj00003WVl59AAD` A/**B**/A (`OUTPUT_UNNECESSARY_VERBOSITY`); Schedule Planner `a00aj00003WVl5AAAT` A/A/**B** (`CALLS_DETERMINISTIC_ALTERNATIVE`). Verified: [review-results-gpt55.json](docs/testing/results/2026-09-07/event-org/review-results-gpt55.json). `getFleet()` points each bundle at these reports.

**Ask Ohm live check (GPT 5.5) via anonymous Apex on Sales Follow-up → `Draft Follow Up`:** context `available=true`, `rewriteSupported=true`, label `GPT 5.5 · Einstein Trust Layer`; the saved-review question answered without a model call; a live draft request called GPT 5.5 successfully and returned a rewrite of 1106 chars vs 900 source chars, which the app reported as "not shorter … No improvement is established." Keep the recorded demo on the saved-review explanation as scripted.

**Evals rerun on GPT 5.5:** 7/8 — `Ohm_Schedule_Planner` `schedule-day` now passes 5/5 (it failed on GPT-4o mini), so the eval evidence is "prompt arithmetic is model-dependent; Apex was right both times". `Ohm_Support_Desk` `support-damaged-lantern` errored before a response on the rerun (no evaluation recorded); the GPT-4o mini run had passed it 5/5. Evidence: [evals-gpt55/](docs/testing/results/2026-09-07/event-org/evals-gpt55/).

**Environmental footprint surfaced in the app (user decision, Sept 7 evening: "claim energy and environmental impact transparently with assumptions; make the app environmentally focused").** Design (revised on user request "put the environmental strip at the top and make it much clearer that we will save the environment"): one reusable LWC `ohmFootprintStrip`, now the FIRST element on Overview (heading "What your agents can stop costing the planet"), placed ABOVE the three ratings on the bundle page, and at the top of Recommendations. It leads with the energy avoided a year if the recommended changes are applied (big green figure, kicker "Apply the recommended change(s) and avoid"), then carbon avoided, water avoided, saved per request, and footprint today with its low–high band drawn as a meter (solid = central, hatched tail = high, bright segment = avoided); avoided CO2e/water derive from the energy share because the model's factors are linear. Requests-a-day selector (300 = the model's own scenario, 1k, 10k, 100k); Assumptions disclosure lists every constant with its band plus the sentence that avoided figures assume the changes are applied and behave as before; badge "Modeled, not measured" on every render. Hero copy: eyebrow "Less energy. Less carbon. Less water.", headline "Better agents. A lighter planet.", description names energy, carbon and water and says the assumptions are in the open. Bundles with no recommended change fall back to showing the footprint itself. Client-side scaling divides the saved review's modeled annual figures by the requests/year it assumed (`annualCallsPerArtifact`, 109,500) and multiplies by the chosen volume × 365, so no environmental constant is duplicated on the client. Apex: `ProcessSummaryDTO`/`ProcessDetailDTO` gained savings/CO2e/water bands, `annualCalls`, `impactAssumptions`, `impactFactors`; `OhmAuditImpactService.factors()` discloses the constants; `applyBands(...)` copies a saved Impact snapshot onto fleet rows and detail; `getFleet` now also selects `Modeled_Energy_Wh_Low/High__c` and `Impact_Snapshot__c`. Helpers `formatEnergy/formatMass/formatWater` in `ohmDisplay`. Tests: 6 new Jest cases (216 total green), 2 new Apex tests in `OhmAuditImpactServiceTest`, footprint assertions added to `OhmAuditControllerTest`. **Footprint deploy:** `0Afaj00000jWHtRCAW` Succeeded (10/10 components, 285/285 local tests) plus `0Afaj00000jWBGACA4` (strip rounding fix). Verified via anonymous Apex: every fleet row carries `annualCalls=109500`, energy/savings/CO2e/water bands, `impactFactors` and the assumption summary; detail for Support Desk likewise. Fleet at the default 300 requests/day: about 108 kWh/yr modeled, about 31.9 kWh (30%) recoverable, 32.4 kg CO2e, 117 L water; the selector rescales linearly (10k/day ≈ 3.6 MWh/yr). Measured-token evidence (372→137 input tokens on GPT 5.5 for the Support fix; 241→171 for Sales) lives in [measured-tokens-gpt55.json](docs/testing/results/2026-09-07/event-org/measured-tokens-gpt55.json) and the demo narration, not in the app, because the app can only show modeled figures honestly.

**Demo script rewritten as a plain spoken narration** ([DEMO-SCRIPT-5-MINUTES.md](docs/testing/DEMO-SCRIPT-5-MINUTES.md), 546 words ≈ 4 minutes, recorded over a screen capture of the live app; opens with the presenter intro, leads with the fleet headline numbers, never names individual agents, keeps only two-word screen cues). Judge Q&A, expected on-screen figures, recording checklist and receipts moved to [DEMO-JUDGE-NOTES.md](docs/testing/DEMO-JUDGE-NOTES.md).

**"How it works" tab added (user request):** fourth tab in `ohmApp` (`HOW`), new LWC `ohmHowItWorks` with three inline SVG diagrams in the app palette: the loop (Discover → Retrieve → Review → Verify gate → Recommend → Act, re-audit arrow, red "No match: nothing is saved" branch), the stack (Experience/LWC, Services/Apex, Platform bands), and the footprint math (tokens × energy per prompt → per request × volume → energy a year → CO2e / water), plus a six-step list and the three questions with the grade legend. Deploy `0Afaj00000jWSGzCAO` (2/2). Jest 28 suites / 218 tests. App tests updated for four destinations; keyboard End lands on the new tab. Demo script cue `[How it works tab]` precedes the technical section.

**Remaining before/for the recording:** browser rehearsal in the event org (Overview → Bundles → Schedule Planning → Review this change → Ask → Recommendations → Create/Open Task → re-audit). Salesforce may cache old LWC; hard-refresh. Optional cleanup not done: 20 legacy Sept 2–3 reports and 18 planner-less findings remain in the org (not visible in the current UI); the fixture agent user `ohm.fixture.agent@…` must stay active for the Service agents to run.

Diagnostic replay scripts (nonsecret, redact tokens): `/tmp/ohm-raw-fetch.cjs` (raw fetch with SFAP JWT shows the true 401), `/tmp/ohm-publish-replay-body.json` (CLI publish payload). Run with `NODE_PATH=/Users/dom/.local/share/sf/node_modules node ...`.

## Event deployment attempts and current blocker (earlier in the day)

1. Core deployment `0Afaj00000jVnvNCAS` was deliberately canceled: **0 component errors**, 169 tests executed, 20 failures before cancellation. Failures assume old Weather/ActionDefinitions fixture metadata exists in the org. Cancellation is confirmed `Canceled`, `done=true`, `success=false`.
2. Fixture attempt `0Afaj00000jVocvCAC` accidentally resolved the root working directory and was immediately canceled before tests. Confirmed `Canceled`, `done=true`, `success=false`, 0 component/test errors. Corrected fixture deployment has **not** started.
3. No fixtures have been published or activated. No live fixture/model tests have run in the event org. No source credential setup or new permission assignments have run.

Durable nonsecret receipts: [deployment-checkpoint.json](docs/testing/results/2026-09-07/event-checkpoint/deployment-checkpoint.json). Full local CLI outputs remain `/tmp/ohm-event-app-deploy.json`, `/tmp/ohm-event-app-deploy-cancel.json`, `/tmp/ohm-event-fixture-deploy.json`, and `/tmp/ohm-event-fixture-deploy-cancel.json`.

### Test portability repair

`OhmAuditTestSupport.scriptPlannerId()` previously selected only `Ohm_Weather_Demo_v*`. `OhmAuditCoordinatorTest` hardcoded `ActionDefinitions_v1`. `OhmDiscoveryServiceTest` explicitly required Weather and its Apex action. The bounded test-only repair selects the current event `Ohm_Schedule_Desk` publication (Weather fallback for scratch), uses its exact ID, and verifies its real topic/action/Apex relationships. Integration tests still require actual published fixture metadata; do not bypass assertions or add production success fallbacks.

The limited patch is saved in `OhmAuditTestSupport.cls`, `OhmAuditCoordinatorTest.cls`, and `OhmDiscoveryServiceTest.cls`. `git diff --check` passed; Apex compilation and test execution after this patch have NOT run. Inspect the final diff before deploying. **Also inspect `OhmAuditControllerTest`'s legacy-rejection test: it assumes `Ohm_Waste_Demo` exists. That portability issue was identified but not yet repaired.** Run all local Apex tests after fixes. A broader future refactor could inject deterministic discovery fixtures, but is not required to resume this install.

## Remaining steps, in order

> **Status as of Sept 7 evening:** steps 1–8 below are DONE in the hackathon org (see the evening-session section for IDs and results). Only step 9 (browser rehearsal / recording) and the final confirmation in step 10 remain. Deviations from the plan as written: bundles are `AgentforceServiceAgent` (not Employee), and Ask Ohm plus the linked prompts run on `sfdc_ai__DefaultGPT55` (not GPT-4o mini).

1. **Finish/review test portability.** Check helper, Coordinator, Discovery, and legacy-rejection controller test. Preserve assertions about exact publication, scope rejection, relationships, synthetic instruction evidence, and lifecycle behavior.
2. **Deploy fixture dependencies first**, from the isolated event fixture project. Select ONLY classes, genAiPromptTemplates, and permissionsets; use `RunSpecifiedTests --tests OhmDemoScheduleServiceTest`. Do not deploy authoring bundles as part of this dependency pass. Resolve real compilation errors. Assign fixture and standard Prompt Template User/Manager permissions as needed.
3. **Activate linked prompt versions, publish the four AgentScript bundles, then activate exact observed versions.** Use `sf agent publish authoring-bundle --api-name NAME --target-org ohm-hackathon --json` from the runtime project. Query actual resulting names/IDs; never assume v1. No service-agent user is needed for these Employee agents. Keep safe publication receipts.
4. **Deploy core app and run local tests.** Select classes, objects, lwc, staticresources, applications, tabs, flexipages, permissionsets, genAiPromptTemplates explicitly. **Exclude `settings`** (old snapshots include disabled masking/detection controls) and exclude legacy genAiPlannerBundles/genAiPlugins/genAiFunctions. Target required AI features already enabled. Do not blanket-deploy root force-app. See [EVENT-ORG-INSTALL.md](docs/testing/EVENT-ORG-INSTALL.md), including its checkpoint correction about fixture-first order.
5. **Assign app/data/Prompt Template access and configure retrieval.** After core succeeds, run the setup below. Inspect cleanup and identity; keep secrets out of output. Reserved-component collisions require inspection, not blind reruns or deletes.

```sh
python3 scripts/source/setup-connection.py \
  --target-org ohm-hackathon \
  --run-as epic.f1c1977a25ca@orgfarm.salesforce.com \
  --audit-user epic.f1c1977a25ca@orgfarm.salesforce.com \
  --contact-email dominick@synaptic.build
```

6. **Verify reviewer activation and execute real model calls.** Preserve GPT5.5 reviewer; metadata alias existence is not proof of org execution access. Ask uses `sfdc_ai__DefaultGPT4OmniMini`; linked fixtures use `sfdc_ai__DefaultOpenAIGPT4OmniMini`. Check active versions without replacing global activation/security settings.
7. **Run actual source retrieval + OHM audits for all four event bundles.** Use actual publication IDs. Do not run old `scripts/apex/audit-public-workflows.apex` unchanged: it hardcodes old samples. Wait for Complete; fail honestly on missing source/reviewer evidence. Collect each real report via `scripts/testing/collect-review-results.py --target-org ohm-hackathon --report-id ID ... --output PATH`, independently verifying hashes, quote continuity, and Fleet/detail consistency. Record observed ratings rather than forcing intended ones.
8. **Run fixture behavior evals**, including the Apex control's invalid rows, overlaps, minimum gap, and ordering. The fixtures have prepared `evals/*.json` and scenarios. Verify action execution traces in addition to model-judged response quality where useful.
9. **Rehearse the app end to end in the event org.** Overview → Bundles → Schedule Planning ratings → exact “Plan a Guest Day” source → saved-review Ask → individual prompt reviews/structure → Recommendations evidence → Create/Open readable Task → re-audit real progress. Check all screens and narrow layout. Salesforce may cache old LWC; refresh/reopen and verify actual deployed source if UI appears stale.
10. **Finalize the five-minute script and evidence.** [DEMO-SCRIPT-5-MINUTES.md](docs/testing/DEMO-SCRIPT-5-MINUTES.md) is written and updated for the new four bundles, but explicitly marked event rehearsal pending. Replace that status only after real verification; adjust counts/ratings to observations. Update the event install/runbook and this state with exact successful IDs. No measured savings or automatically applied changes should be claimed.

## Browser / tooling handoff

At checkpoint, IAB tab1 is the user’s scratch app, tab2 its Prompt Builder, and agent-created tab3 is the logged-in event org (1280×720). Event tab3 last showed Personal Information; use it for final app rehearsal. Chrome's OAuth success tab is disposable. Use `cua.getState()` to reacquire actual tab IDs after a fresh runtime. Do not print saved one-click login URLs or inspect unrelated mail. Native automation of the Codex app was denied; browser automation works normally.

Source setup docs: [LIVE-SOURCE-SETUP.md](docs/testing/LIVE-SOURCE-SETUP.md). It creates dedicated renewable client credentials, briefly changes the exact required secret-visibility setting, restores its prior value, and removes temporary setup permissions. It does not store the CLI access token in app data.

Known practical limits remain: no runtime energy telemetry, no verified model-quality benchmark, no automatic source application/publication, and structural graphs do not establish actual execution order or call counts. They do not block the planned evidence-based demo, but event installation and live rehearsal still do.
