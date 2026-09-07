# Demo implementation and verification — September 6, 2026

Implementation branch: `codex/demo-audit-repairs`, based on GitHub `038b5a0`. Scratch org: `ohm-audit-lab` (`00DEc00000kvSbNMAU`), expires September 13, 2026.

This completes the scoped repairs from [the audit fix plan](DEMO-FIX-PLAN-2026-09-06.md). The original audit results remain historical evidence; current measurements are stored in [fixed-demo](results/2026-09-06/fixed-demo/).

## What changed

| Demo priority | Implemented behavior |
|---|---|
| P0 — discovery | Authoritative planner/topic/action ownership; normalized prompt actions; latest logical agent version in Fleet. Old versions remain addressable for history. |
| P0 — evidence | Explicit versioned source import with planner fingerprint, file hashes and artifact hashes; actual instruction text, including conditional DSL. Missing graph/model evidence is visible per detector. |
| P0 — detection | Mini model classification and word boundaries corrected. Keyword or graph suspicions require review and carry no promised replacement savings. Unknown coverage withholds a complete grade. |
| P0 — accounting | Independent, deduplicated instruction-source baseline, conditional trim scenario, nonzero residual, ranges and frozen assumptions. Comparisons require the same logical agent/artifact and method/model/volume assumptions. |
| P0 — lifecycle | Stable issue identity across publications, exact immutable snapshots on clean and flagged audits, preserved Task ownership/due date/status, automatic resolution and reopening. |
| P0 — assistant | Exact selected source and hash, stale/oversize refusal, complete input, deterministic numerical answers, guarded qualitative claims and structural validation of Agent Script drafts, and exact adjacent duplicate prose removal without a model call. |
| P1 — handoff | Exact source path/version/hash, manual application instructions, working browser Task creation, linked Task owner/due-date editing. |
| P1 — Calm Mode | Saved preference, suppressed animations/transitions, reduced-motion CSS, concise assistant responses. |
| P1 — permissions | Controller access, scoped data grants, read-only imported source, immutable snapshot permissions, minimum-access persona tests. |

## Verified public workflow coverage

The pinned upstream corpus contains 365 hash-verified files from three official Salesforce repositories. Public originals are unchanged.

| Published recipe | Topics / actions | Current audit result |
|---|---|---|
| Weather / mixed Flow and Apex (`ActionDefinitions_v1`) | 2 / 3 | Actual source imported; no findings; modeled instruction baseline 14,782.50 Wh/year. |
| Payment / four-step Flow chain (`ActionChaining_v1`) | 2 / 4 | Required chain retained as a negative control; no findings; 11,116.44 modeled Wh/year. |
| Personalized schedule / prompt template (`PromptTemplateActions_v1`) | 2 / 1 | Prompt action recognized; source-size review plus informational assumed-model review; 14,723.37 modeled Wh/year. |

All three correctly report **Incomplete** overall coverage. Their platform execution graphs are unavailable. The schedule model comes from imported template source and remains an assumption because it can change independently of planner metadata. An incomplete audit is not a failed workflow or a clean A grade.

## Controlled remediation rehearsal

The controlled weather variant repeats an existing instruction 36 times. This is an intentionally introduced condition, not an upstream Salesforce defect. Its reviewed repair removes only that repetition; actions and branches are unchanged. Full source and patch provenance are in [the fixture](../../test-fixtures/controlled-weather/README.md).

Both browser rehearsals passed. Each used the Inspector selection, a source-bound explanation and full draft, the real Task control, a scoped source deployment/publication/import, and a fresh UI audit of the new version.

| Rehearsal | Before report | After report | Modeled instruction input | Finding |
|---|---|---|---|---|
| 1: v1 → v2 | `a00Ec00000lpuukIAA` | `a00Ec00000lpeoWIAQ` | 63,742.14 → 14,782.50 Wh/year | 1 → 0 |
| 2: v3 → v4 | `a00Ec00000lq00rIAA` | `a00Ec00000lpk2aIAA` | 63,742.14 → 14,782.50 Wh/year | 1 → 0 |

The actual modeled reduction is **48,959.64 Wh/year** under unchanged assumptions. It differs from the pre-edit **30,865.86 Wh/year** potential trim estimate because that estimate targets the 500-token review budget; the reviewed repair reaches approximately 194 tokens. Both are modeled source-input scenarios, not realized savings.

Task `00TEc00000a9bLNMAY` completed after the first repair, reopened when the repeated source returned, and completed after the second repair. Creating a Task again reused it. Owner `005Ec00000deLvLIAU` and due date **September 8, 2026** survived. Final collection contains four reports, 24 artifact snapshots, one linked Task, and no duplicate issue Tasks or orphan Tasks. The current worklist excludes the resolved weather issue.

The before/after artifact hashes are `cf1d706095580fc6506fdb98c03a16a46d0ffdb6455a148e278e66a4ba085f10` and `8128ac0e1af2b1cda6aa7100fe60f3f1da96c1ae234d6740c5eb5f192cdae226`. Both drafts were identical to the reviewed after source (773 characters). Current publication is `Ohm_Weather_Demo_v4`, planner `16jEc000000PBBZIA4`.

Published before and after checks cover missing location, current weather, five-day forecast, out-of-scope routing and the alert action. After: **5/5 response checks plus 1/1 exact successful alert trace**. Before evidence retains an initial remote action-comparator failure caused by the evaluator's nested function shape; successful action execution was verified directly and the reusable harness was corrected. All three v4 source hashes match behavior-validated v2, so that identical-source repetition was not billed as another behavior test. Weather values and alerts are fixture stubs; no real notification is sent.

[Final comparison screenshot](results/2026-09-06/fixed-demo/loop-2-comparison.png) · [Repeatable demo runbook](DEMO-RUNBOOK-2026-09-06.md)

## Validation

Current full scratch run: 217/217 Apex executions pass (215 test methods and two setup methods), including all ten original acceptance checks, public recipe action tests, lifecycle/accounting tests, exact snapshots, assistant guards and two minimum-access persona checks. Current UI suite: 23 suites, 165/165 Jest tests pass. Source importer: six parser tests pass. Apex run `707Ec00002XgeKi` is green. The CLI omits two setup rows from its detailed list; a direct Tooling query reconciles all 217 executions. Final run identifiers are recorded in the evidence bundle.

Browser verification caught defects missed by the old tests: an unsupported nested DTO request dropped the finding ID; Salesforce cached old LWC code; a model relabeled baseline energy as savings; and a model draft changed Agent Script structure. The exact-removal draft matched the reviewed reference byte-for-byte (4,085 to 773 characters), with explicit deterministic provenance. The Task endpoint now takes primitive IDs and reconstructs evidence server-side. Quantitative answers are deterministic, and invalid structured drafts are rejected. Scratch-user debug mode and a temporary performance-cache setting were used during component refresh testing. Both are restored to their original values; the refreshed browser shows the deployed review labels. The temporary flag change affected only browser caching, with all other Mobile settings verified unchanged. See [cache evidence](results/2026-09-06/fixed-demo/cache-refresh.json) and [Salesforce debugging guidance](https://developer.salesforce.com/docs/platform/lwc/guide/debug-disable-caching.html).

## Demo boundary and remaining work

Source import and source application remain explicit CLI/manual steps. The importer verifies identity and freshness but relies on the operator supplying the exact published files. Instruction-size energy is a **low-confidence modeled scenario**, not measured runtime consumption or realized environmental savings. Defaults assume 109,500 calls/year per source block; conditional rendered paths, output tokens, tool compute and actual invocation frequency are excluded.

Automatic apply/revert, runtime telemetry, complete execution graph extraction, full fleet accounting, broader legacy/RAG adapters and a richer reassignment UI remain follow-on work. LocalInfo publication remains blocked by its platform publish error; Coral Cloud is source-only. The non-admin tests validate scoped persistence/read access; the live browser rehearsal uses the scratch administrator.
