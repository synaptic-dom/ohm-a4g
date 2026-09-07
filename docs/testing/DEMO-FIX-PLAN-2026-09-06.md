# Ohm: public workflow audit and demo fix plan

> **Implementation completed:** the historical gaps below drove the repairs and two live rehearsals. Use [the implementation report](DEMO-IMPLEMENTATION-2026-09-06.md) and [current demo runbook](DEMO-RUNBOOK-2026-09-06.md) for current status.

September 6, 2026 · application `main` at `038b5a0` · live Salesforce API 67.0 scratch lab

**Decision: the public-workflow demo is not ready to film.** Three external agents published successfully, but every per-process audit returned zero topics, zero actions, A/100, and zero modeled energy. The first work is discovery and evidence quality; the central fix → re-audit loop then needs accounting and persistence repairs. Existing tests passing does not establish that loop.

This work added a pinned public corpus, scratch-org configuration, audit probes, and a separate acceptance-test package. Application code in `force-app` was not changed. The [earlier technical review](../reviews/TECHNICAL-REVIEW-2026-09-06.md) contains the broader completeness assessment. This plan changes its implementation order based on live external examples.

## Lab and public test inputs

Created **`ohm-audit-lab`**, org `00DEc00000kvSbNMAU`, expiring **September 13, 2026**, using the configured Dev Hub and without changing global defaults. [Open the scratch Ohm app](https://innovation-inspiration-231-dev-ed.scratch.my.salesforce.com/lightning/app/c__Ohm) after signing in, or run `sf org open --target-org ohm-audit-lab --path /lightning/app/c__Ohm`.

Three public repositories were cloned. Selected original source, licenses, commit IDs, and hashes for **365 files** are retained in [the corpus](../../test-fixtures/public-agents/README.md) and [source manifest](../../test-fixtures/public-agents/SOURCES.json). These are Salesforce reference implementations, not production customer traffic.

| Workflow | Why it is useful | Actual lab state |
|---|---|---|
| Recipes: **ActionDefinitions** | Weather retrieval and alerting; 2 Flow actions and 1 Apex action | Published. Salesforce exposes 2 topics and 3 actions. |
| Recipes: **ActionChaining** | Payment → receipt → loyalty → log; a necessary chain of 4 deterministic Flow actions | Published. Salesforce exposes 2 topics and 4 actions. A negative control for unnecessary-LLM detection. |
| Recipes: **PromptTemplateActions** | Guest scheduling using a real prompt-template action and an Apex data provider | Published. Salesforce exposes 2 topics and 1 `generatePromptResponse` action. |
| Pro-Code Testdrive: **Local Info Agent** | Service-style weather/hours agent with conditional instructions | Dependencies and authoring bundle deployed. Two publish attempts failed at Salesforce's authoring endpoint with a request error. No planner was created; excluded from live audit results. |
| **Coral Cloud** | Legacy employee/service metadata, booking, credits, knowledge actions and nested topic instructions | Source acquired only. Full application needs further Data Cloud/base-app/service setup; not presented as a deployed working service. |

Sources are pinned to [Agent Script Recipes `ac5ccac`](https://github.com/trailheadapps/agent-script-recipes/tree/ac5ccac8f675153035370abbdce174e2b769c89c), [Pro-Code Testdrive `5fc6ead`](https://github.com/forcedotcom/afdx-pro-code-testdrive/tree/5fc6eadd1d19ae79097b4d5c9d24310f5ca0e128), and [Coral Cloud `d473624`](https://github.com/trailheadapps/coral-cloud/tree/d473624615907d015a7c1c2c339f101e732ecb7a). The Local Info README advertises a prompt action, but its pinned agent script wires only Apex weather and Flow hours; the scheduling recipe supplies actual connected prompt coverage.

The lab also contains the original Ohm metadata fixtures, deployed separately as controls required by existing `SeeAllData` tests. They are not counted among the three external workflows. Public audit measurements were collected before those controls were added.

## What actually ran

The [credential-free result bundle](results/2026-09-06/lab-results.json) records deployment outcomes, test methods and assertions, report IDs, and raw-versus-Ohm inventory counts. The [audit probe](../../scripts/apex/audit-public-workflows.apex) executes real discovery and `auditProcess`, persisting reports. It does not call models or execute the agents' business actions.

| Check | Result | Meaning |
|---|---|---|
| Existing Ohm Apex suite | **125/125 pass**, live in scratch org | Baseline remains green on the prepared controls. No new coverage percentage was measured. |
| Existing local Jest suite | **161/161 pass, 23 suites** | Previously run during this review; app code has remained unchanged. |
| New Ohm acceptance suite | **1/10 pass, 9 fail** | Reproduces discovery, grading, model, recommendation, trend and lifecycle defects. |
| Upstream recipe action tests | Initially **10/11 pass**; failed method **1/1 passes** after fixture permission repair | All 11 distinct checks have passing evidence. The first failure was missing lab data access for a USER_MODE query, not an Ohm defect. |
| Live model connectivity | **Pass**, one real Models API request to `sfdc_ai__DefaultGPT4OmniMini` | Returned a correct short Flow/Apex description. Confirms this model responds in the scratch org; does not validate Ask Ohm grounding or agent conversations. |
| Browser rehearsal and complete public-agent fix loop | **Not yet verified** | Unit tests and metadata publication do not establish interactive behavior or safe rewrites. |

The separate [lab test package](../../test-fixtures/lab-tests/README.md) intentionally remains red against the current application. Four checks query published metadata, one classifies the model name in the upstream source, and five exercise isolated contracts. Do not weaken their expected behavior to make the existing implementation pass.

### Confirmed blockers

1. **Real ownership is ignored.** The published topics have `PlannerId`; actions have `PluginId` while their own `PlannerId` is null. Ohm instead joins developer names. All three per-process audits therefore see **0/0** and silently award **A/100**, with no discovery errors. Raw full-org discovery sees all **6 topics and 8 actions**. See [discovery](../../force-app/main/default/classes/OhmDiscoveryService.cls).
2. **The instruction source is also missing.** All six published topics have empty `Scope`, and their planners have no `AgentGraph`. Real instructions are present in the pinned `.agent` source. Fixing ID joins alone will still leave bloat and graph checks blind. Discovery needs a supported source/import adapter with artifact version and provenance; an inaccessible source must produce a coverage warning.
3. **The platform's prompt type is not normalized.** Full discovery counts **0 prompt templates** even though Salesforce exposes a `generatePromptResponse` action. The prompt detector does recognize that type, so inventory and detection disagree.
4. **The scheduling workflow receives a false deterministic-replacement finding.** The word `information` in its action description matches the detector's `format` substring. One lexical hit leads to a claim that an exact, token-free replacement exists. It does not establish that personalized scheduling can be replaced by a formatting rule. See [detector](../../force-app/main/default/classes/LlmWhereDeterministicDetector.cls).
5. **Evidence and model handling overstate certainty.** The public schedule prompt's `sfdc_ai__DefaultOpenAIGPT4OmniMini` model is classified LARGE. A missing model still receives positive downsizing savings. Missing coverage still produces A.
6. **The demo's improvement record is unreliable.** New clean reports leave stale recommendations; persistent issues lose their Task association; two different agents audited once each produce **70,000 Wh of “realized savings”** in the isolated trend test. Source review also shows that energy is summed from findings and successful fixes lose the AFTER instruction snapshot.

The one passing new test confirms the four payment Flow actions are not flagged by `LlmWhereDeterministicDetector`. It does not prove the separate redundant-call detector understands the chain; graph coverage is still absent.

The Mini test checks classification of the actual upstream model name, not live model binding. Lifecycle tests manually insert reports/findings; implementation should strengthen them to exercise persistence with real stable artifact identities. The current “not A” assertion is only a minimum guard: the intended result is explicitly incomplete, not an arbitrary lower grade.

## Reconfirmed demo loop

Use a **three-minute core walkthrough** with one real public workflow as the subject and the other workflows visible as breadth/negative controls. The proposed promise is: **discover → audit with evidence → explain → propose → assign → manually apply → re-audit the same artifact → show comparable improvement**.

| Time | On-screen action | Evidence the viewer should see |
|---|---|---|
| 0:00–0:20 | Open Fleet and select the public weather workflow | Several kinds of agents; correct topic/action counts and source identity. |
| 0:20–0:45 | Run its audit | Complete/partial coverage, source version, modeled usage assumptions, and a defensible finding. |
| 0:45–1:10 | Inspect the exact instruction block and Ask Ohm why it matters | Highlighted source evidence; grounded explanation that distinguishes estimates from measurements. |
| 1:10–1:35 | Request a trim and review it | Full original input, actual before/after sizes, retained conditions/actions, no unannounced truncation. |
| 1:35–1:55 | Create a remediation Task with owner and due date | Persistent link to the same agent, artifact and issue. |
| 1:55–2:30 | Apply the reviewed edit manually to the exact source/Builder artifact; publish as required | Explicit manual step and verified target/version. Show the publication wait honestly or label a video time cut. |
| 2:30–3:00 | Re-audit, compare, and resolve the Task | Same artifact and usage scenario; before/after source survives; modeled reduction with residual footprint; cleared finding and preserved history. |

Do not promise a forced **F → A** or **zero energy**. An efficient agent still consumes compute. Replace the current spec's zero-footprint success criterion with a verified reduction at the same modeled scope and volume.

If none of the unchanged public recipes contains defensible waste, create a **clearly labeled controlled variant** of the public weather workflow for the remediation segment. Keep the upstream original as a negative control. Add only intentional redundant instruction text, preserve all actions and branches, record the patch, and restore the original semantics during the demo. Do not pass this controlled variant off as an upstream defect. This variant has not yet been created.

Calm Mode can be enabled at the start if its motion and response behavior are finished. It should support the walkthrough, not replace proof of the audit/fix loop. Broad Org Trends and automatic metadata writeback are unnecessary for this core demo.

## Gaps ranked by demo priority

**P0** means fix or remove the misleading claim before filming. **P1** improves the selected demo or is required when its feature is shown. **P2** can wait beyond this demo.

| Priority | Gap | Smallest credible demo completion |
|---|---|---|
| **P0** | Relationship joins and real instruction access | Follow authoritative IDs; fetch/import actual versioned instruction source; identify unsupported/missing coverage. Restrict demo support to the formats actually verified. |
| **P0** | False A, prompt inventory mismatch, Mini misclassification, unsupported savings | Shared action taxonomy, specific model matching, per-detector coverage and unknown states; withhold grade/savings when evidence is insufficient. |
| **P0** | `information` → `format` false positive | Remove substring evidence; require a supported reason for deterministic replacement. Mere keywords can suggest investigation, not assert exact equivalence. |
| **P0** | Finding totals masquerade as total energy; overlapping costs | Separate the audited workload baseline from findings, retain post-fix cost, deduplicate overlapping fixes. Expose volume/model/range and label the metric as modeled. If scope is only instruction input, say so explicitly. |
| **P0** | Stale worklist, lost Tasks/status and missing AFTER snapshot | Stable issue identity plus independent artifact snapshots; newest complete report governs current issues even when clean. Reconcile disappearance and reopening. |
| **P0** | Different-agent trend “savings” | Remove the fallback claim now. For the demo, compare the same agent/artifact and assumptions; call the result modeled reduction. Full fleet history can wait. |
| **P0** | Silent truncation of long rewrites | Preserve the original size and refuse unsupported full rewrites above the limit until complete-input handling exists. Never label a partial-input rewrite complete. |
| **P0** | Assistant finding and rewrite source can differ | Carry the selected artifact and source version from Inspector through Ask Ohm, manual apply and diff; do not independently pick a finding and the longest instruction block. |
| **P1** | Fix handoff ends at copy/advice | Identify the exact editable artifact and provide a reliable manual handoff. Verify new published source after applying. No one-click apply is needed. |
| **P1** | Team editing and non-admin setup | Use Findings' initial self-assignment with due date for the scoped demo; repair owner labels/navigation. Grant required Apex access and validate a non-admin if that persona is shown. Full reassignment UI can follow. |
| **P1** | Calm Mode is primarily a theme | Honor saved preference and reduced motion in actual screens; structure assistant responses appropriately. Required before making an accessibility behavior claim. |
| **P2** | Automatic apply/revert, fleet time series, runtime telemetry, full legacy/RAG support | Separate follow-on work. Coral Cloud deployment, runtime energy attribution and larger graph handling should not hold up the verified three-workflow scope. |

## Ordered fix plan and exit checks

### 1. Repair discovery and establish a coverage contract

Work in `OhmDiscoveryService`, `OhmDTO`, and the process/Fleet adapters. Prefer actual planner/topic/action relationships. Where they are absent, use a documented mapping/import path; label ambiguous fallback matches. Introduce one normalized action-kind mapping for discovery, counts and detectors. Obtain versioned instructions from a supported authoring-source interface or explicit source import, including legacy nested instructions when that format is claimed supported. Surface per-detector covered/unknown/unsupported states.

**Exit:** weather 2 topics/3 actions; payment 2/4; schedule 2/1; one published prompt action recognized; audited instruction text matches the pinned source and its identity/version. Missing instructions or graph data cannot silently become a complete A audit. Add checks for instruction retrieval and action ownership, not only inventory counts. Validate any metadata/API approach in this scratch org before building the UI around it.

### 2. Make detection and model recommendations defensible

Fix the Mini classification order in `ModelRegistry`. Carry actual prompt model evidence through discovery. Preserve informational unknown-model results without asserting downsizing savings. Replace substring matching with stricter evidence and appropriate confidence in `LlmWhereDeterministicDetector` and `ModelRightSizingDetector.classifyComplexity`; both can match `format` inside `information`. Have grading account for the coverage contract.

**Exit:** personalized scheduling is not flagged because of `information`; Mini is SMALL; unknown model yields no positive savings; missing evidence yields an incomplete state. The four required Flow actions remain a negative control. Add positive cases so the detector still catches genuine deterministic replacement opportunities.

### 3. Repair modeled impact and comparison semantics

Separate workload footprint from avoidable-waste findings in `OhmFootprintService`, controller, DTOs and persisted report data. Record scope, volume, model assumptions and methodology version with each report. Recompute a combined after-scenario instead of summing overlapping potential savings. Keep a nonzero residual where model work remains. Expose the assumptions/range in current v2 screens. Disable the different-agent Org Trends fallback immediately; build same-agent comparisons first.

**Exit:** a successful instruction trim reduces the modeled footprint without claiming all compute vanished; two flags on one inference do not double-count its baseline or savings; changing assumptions invalidates the comparison or is explicitly normalized. The 80,000/10,000 two-agent scenario reports no realized savings. Add these accounting regressions beyond the current ten acceptance checks.

### 4. Complete the audit-to-remediation lifecycle

Give an issue a stable key based on process, artifact and signal, separate from per-run finding rows. Persist source snapshots by report and artifact even when no finding exists. Select latest completed reports before selecting findings; retain prior reports as history. Preserve Task ownership/due date/status on persistent issues and reconcile clean reports, Task completion and reopening. Select the same artifact explicitly for both diff sides. Verify whether republishing changes planner/action IDs and use logical source identity across versions when necessary; the current single-publication evidence does not settle this.

**Exit:** unchanged issue retains its Task and accepted status; a newer clean report clears current Recommendations/Findings; the resolved artifact still has an AFTER snapshot; a different artifact cannot be compared accidentally; reopening has a defined, tested Task state. Do not delete audit history to clear the current worklist.

### 5. Finish only the demo-facing interactions

Wire coverage, methodology and snapshots into the process page and assistant grounding. Bind the selected finding to its exact source artifact/version: [current grounding](../../force-app/main/default/classes/OhmAssistantService.cls) independently selects the highest-savings finding and the longest wasteful instruction block. Guard long input, show real original size, and verify draft behavior with full source and injection-like text inside untrusted source. Add the exact manual-edit handoff. Repair owner labels/navigation; provide controller class access for the intended persona. Complete reduced motion and response presentation if Calm is shown.

**Exit:** the selected persona can audit → inspect → ask → review → assign → apply → re-audit → resolve without losing the target. Over-limit instructions produce an explicit unsupported state. The model cannot invent measured usage or whole-fleet savings from the supplied context. The app gives a useful failure state if the model is unavailable.

### 6. Rehearse and preserve repeatable evidence

Rerun the existing 125 Apex tests, 161 Jest tests when affected, the ten new acceptance checks and added discovery/accounting/snapshot regressions. Rerun the upstream action checks relevant to any workflow edits. Test actual conversational paths before and after the controlled trim, including weather forecast, alert branch, missing input, and out-of-scope requests. Unit action tests alone do not prove the agent behaves the same after a rewrite.

Run the complete browser loop twice from a documented reset state. Capture report IDs, source hashes, model/volume assumptions and screenshots of the same artifact before/after. Confirm no stale worklist entries or duplicate Tasks on the second run. Label any recording cuts around publish/model latency. Keep public originals immutable and use separate runtime copies: publishing can update local authoring-bundle metadata.

**Exit:** all applicable regression gates pass, live Ask Ohm behavior is confirmed, and two consecutive rehearsals produce the same defensible outcome. Refresh the expiring scratch org from the pinned corpus when needed.

Stages 1–4 are the dependency chain and the largest uncertainty is retrieving actual published instruction source. UI work can proceed in parallel once the coverage/snapshot contract is agreed. Prefer these six reviewable increments over attempting to finish every production feature before the demo. No application fixes have been implemented in this audit task.
