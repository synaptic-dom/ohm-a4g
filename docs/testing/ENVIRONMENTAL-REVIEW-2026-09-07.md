# Environmental review of Agent Script bundles

OHM retrieves the published Agent Script, its instruction blocks and active prompt templates invoked by the bundle. A published Salesforce Prompt Builder template, `Ohm_Bundle_Environmental_Review`, reviews the meaning of that evidence. Apex validates the response and assigns four independent ratings. Standalone prompts, Flow implementations and Apex implementations remain outside the audit scope.

## Division of work

| Apex computes or checks | Salesforce Prompt Builder reviews |
| --- | --- |
| Ownership, publication identity, active model binding, source hashes and freshness | Whether instructions contain unnecessary context, contradictions or removable repetition |
| Exact character counts, approximate source tokens, configured source budgets and exact repeated lines | Whether requested output is unnecessarily verbose, unbounded or mismatched to the task |
| Required response schema, category and issue enums, complete artifact coverage and exact source quotations | Whether a known model is a candidate for a suitability experiment |
| Final ratings, coverage and fixed environmental explanations | Whether the visible setup suggests unnecessary model calls or work better performed by code |

The reviewer returns a flat list of assessments with short source aliases, issue codes, source quotations, a recommended change, behavior to preserve and a validation step. Apex assigns the aliases, verifies every required source/category pair, groups the answers and restores the original Salesforce source identities. The reviewer cannot supply grades, numerical scores, token counts, measured energy, carbon or savings. A failed call or invalid response fails the audit; it does not produce a substitute review.

## Categories and ratings

| Category | Environmental consequence |
| --- | --- |
| Input efficiency | Removing unnecessary input may reduce inference work when that input is included in a request. |
| Output efficiency | Avoiding unnecessary output may reduce generation work while preserving the required answer. |
| Model fit | A suitable smaller model may use less compute; quality and environmental effects require validation. |
| Call efficiency | Avoiding unnecessary model invocations may reduce inference work; source alone cannot establish invocation frequency. |

- **A — No material issue found:** the reviewed source has no supported issue in that category and required source coverage is available.
- **B — Improvement opportunity:** the reviewer identifies a supported candidate change. This is a recommendation to validate, not proof of wasted energy.
- **C — Priority fix:** a defined deterministic rule is violated. Currently this is an approximate source-token count exceeding the configured hard review budget. It proves a budget violation, not unnecessary text or measured savings.
- **Unrated — Insufficient evidence:** the evidence needed to conclude is unavailable. A known model binding alone never earns an A for model fit because no quality evaluation is available.

Bundle ratings take the worst supported rating across the bundle assessment and its instruction/prompt assessments. Missing coverage remains explicit even when a B or C is present. Full Agent Script configuration informs setup and call recommendations but is not counted again as a separate prompt.

Agent Script control and data binding are already deterministic. Explicit `run` chains and `set` assignments from action outputs are not evidence of avoidable model reasoning. A deterministic-alternative finding requires instruction evidence that actually assigns work to the model; configuration-only bindings are insufficient. This distinction follows Salesforce's [action chaining](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-patterns-action-chaining.html) and [variable binding](https://developer.salesforce.com/docs/ai/agentforce/guide/ascript-patterns-variables.html) semantics.

## Runtime and persistence

The queue retrieves and pins source before the review call. It verifies publication and linked-prompt freshness before and after that call. The validated review, source snapshots and supporting detector results are then stored in the same transaction. A changed publication or failed review cannot complete the report.

`Review_Result__c` stores the complete review. `Review_Summary__c` stores category summaries for the Fleet view. Previous reports without this evidence display **Review not run**. Ask OHM answers rating and recommendation questions from the saved review without another model call.

The adapter invokes `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate` with `isPreview=false`, one generation and the registered application name `PromptBuilderPreview`. That application name does not make the request a preview: `isPreview=false` performs generation. The configured reviewer was upgraded to **GPT-5.5**, API name `sfdc_ai__DefaultGPT55`, on the user's request. Temperature is omitted so the configured model's supported defaults apply. Salesforce lists this model for Prompt Builder and Models API. [Salesforce supported models](https://developer.salesforce.com/docs/ai/agentforce/guide/supported-models.html).

Salesforce chooses the active template version; stored reviewer model/version values are declared deployment identities, not per-generation attestations. The active template content and model must be checked during deployment verification.

## Limits

- Scope is static source review, including linked prompt text. It does not execute the audited agent or its actions.
- No runtime call traces, rendered request sizes, generated token counts or task-quality evaluation are collected.
- Source tokens use the existing character-based approximation. Existing energy and savings scenarios remain supporting evidence and do not assign these ratings.
- The initial bounded reviewer supports up to 24 instruction artifacts, 200 action references and 60,000 total source characters per request, including configuration. Oversized evidence is rejected rather than truncated.
- Recommendations are shown for human review. Publishing changes remains manual; a fresh audit verifies the new publication.

## Verification

Final deployment `0AfEc00000nZdBzKAK` passed **302 Apex executions with no failures**. The UI passed **25 Jest suites / 197 tests**, followed by eight focused passing tests for the final category guidance. All four live bundle reviews completed. Independent collection verified thirteen instruction snapshots, four complete configuration sources, exact quoted evidence and agreement between Fleet summaries and detail results.

| Bundle | Input | Output | Model | Calls | Report |
| --- | --- | --- | --- | --- | --- |
| Action Chaining | A | A | Unrated | Unrated | `a00Ec00000lsvJMIAY` |
| Action Definitions | A | A | Unrated | Unrated | `a00Ec00000lsvJNIAY` |
| Controlled Weather Demo | A | A | Unrated | Unrated | `a00Ec00000lsvJOIAY` |
| Prompt Template Actions | A | A | Unrated | B | `a00Ec00000lsvJPIAY` |

The supported live opportunity is to evaluate deterministic overlap checks, free-time gap checks and chronological ordering for the schedule prompt while preserving model-generated presentation. The recommendation requires validation; it does not establish reduced call counts or measured energy savings.

Four bounded live reviewer probes passed: clean instructions, deliberately poor instructions, a source-injection override, and an existing deterministic Flow/Apex chain. The bad prompt produced supported Input, Output and Calls opportunities. Existing `run`/`set` bindings produced no false deterministic-alternative findings. These probes are not an exhaustive model evaluation.

Initial transport and nested-response failures were rejected, never treated as accepted reviews. Human inspection of the first valid GPT-5.5 runs identified two bad recommendations about already-deterministic DSL. Those results are retained as explicitly superseded evidence; the corrected template and evidence rule were deployed and all four bundles reviewed again.

See [summary](results/2026-09-07/environmental-review/summary.json), [live source checks](results/2026-09-07/environmental-review/live-reviews.json), [reviewer probes](results/2026-09-07/environmental-review/probes.json), [deterministic-chain regression](results/2026-09-07/environmental-review/deterministic-chain-regression.json), and [active template proof](results/2026-09-07/environmental-review/template-proof.json). Work is local and deployed to the scratch org; it has not been committed or pushed.
