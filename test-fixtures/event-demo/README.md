# Event demo fixtures — installed, published, and active in the hackathon org

Checkpoint: September 7, 2026 (evening). Target alias `ohm-hackathon`, org `00Daj000013wTtpEAE`.

**Agent type note.** The bundles are published as `AgentforceServiceAgent`, not the upstream recipes' `AgentforceEmployeeAgent`. The hackathon trial org is not licensed for the Employee Agent template: the publish API returns HTTP 401 "you don't have access to agent templates associated with the AgentforceEmployeeAgent agent type" (the CLI masks this as an empty `FetchError` against `test.api.salesforce.com`). Each `.agent` therefore sets `default_agent_user` to the dedicated Einstein Agent User `ohm.fixture.agent@orgfarm-08e0e83a93.ohm` (User `005aj00000dVdUrAAK`, profile Einstein Agent User, permission sets `AgentforceServiceAgentBase`, `AgentforceServiceAgentUser`, `EinsteinGPTPromptTemplateUser`, `Ohm_Event_Fixture_Access`). That user exists only in the hackathon org; recreate it, or change `DEFAULT_AGENT_USER` in `scripts/prepare-fixtures.py`, before publishing elsewhere. `company_name` is not a valid config field. Ohm discovery reads `GenAiPlannerDefinition` regardless of agent type.

These are controlled, synthetic test workflows adapted from the pinned Salesforce Agent Script Recipes. They are not upstream defects or production customer data. [PROVENANCE.json](PROVENANCE.json) records source commit, exact upstream paths, modifications and generated file hashes; [LICENSE.md](LICENSE.md) retains Apache-2.0. Original public fixtures remain unchanged.

| Bundle API | Display label | Linked prompt | Intended audit evidence |
|---|---|---|---|
| `Ohm_Support_Desk` | Customer Support | `Ohm_Support_Reply` | Repeated replacement-policy paragraphs; consolidate without losing eligibility and approval rules. |
| `Ohm_Sales_Follow_Up` | Sales Follow-up | `Ohm_Sales_Follow_Up_Email` | Unused email alternatives, multiple encodings and commentary for a single draft request. |
| `Ohm_Schedule_Planner` | Schedule Planning | `Ohm_Plan_Day` | Prompt performs bounded overlap, minimum-gap and ordering calculations. |
| `Ohm_Schedule_Desk` | Efficient Schedule Desk | `Ohm_Present_Validated_Plan` | Actual Apex prepares the same schedule; linked prompt only presents it. Existing run/set bindings must not be mislabeled as LLM calculations. |

Review outcomes are not seeded or guaranteed. The control can have unknown coverage; do not preassign an A or claim measured savings. Every linked prompt belongs to an Agent Script bundle, and none is a standalone Ohm audit target.

The package has seventeen metadata files: four authoring bundles, four linked prompts, a pure invocable Apex scheduling class plus its test, and a fixture permission set. Inputs are required primitive strings. No custom objects, Data Cloud, outbound requests, email delivery, bookings or business-record updates are required. The schedule action validates every row, sorts by start time, and greedily selects the earliest compatible activities with at least sixty minutes between them. Equal starts retain input order. It does not optimize for the maximum number of activities.

## Current state

- Local XML, source hashes, action-to-template references, template input/version consistency, and Ohm instruction extraction checks **passed** for all four bundles. Each has three nonblank instruction blocks and one linked prompt.
- **Deployed:** dependencies (classes, prompt templates, permission set) in deploy `0Afaj00000jVrVxCAK`, 7/7 components, `OhmDemoScheduleServiceTest` 4/4 passed. Authoring bundles deployed as metadata in `0Afaj00000jVvbBCAS` (Employee type) and redeployed as Service type in `0Afaj00000jW1wjCAC`. All four linked prompt templates are active with the source `activeVersionIdentifier`.
- **Published and activated (all v1, Status Active):**

| Bundle | BotDefinition | BotVersion | GenAiPlannerDefinition |
|---|---|---|---|
| `Ohm_Schedule_Desk` | `0Xxaj000004AwzhCAC` | `0X9aj0000073iEzCAI` | `Ohm_Schedule_Desk_v1` `16jaj000003G45xAAC` |
| `Ohm_Support_Desk` | `0Xxaj000004Ax1JCAS` | `0X9aj0000073iGbCAI` | `Ohm_Support_Desk_v1` `16jaj000003G47ZAAS` |
| `Ohm_Sales_Follow_Up` | `0Xxaj000004Ax2vCAC` | `0X9aj0000073iIDCAY` | `Ohm_Sales_Follow_Up_v1` `16jaj000003G49BAAS` |
| `Ohm_Schedule_Planner` | `0Xxaj000004Ax4XCAS` | `0X9aj0000073iJpCAI` | `Ohm_Schedule_Planner_v1` `16jaj000003G4AnAAK` |

- Org `AiAuthoringBundle` names carry a `_1` suffix (`Ohm_Schedule_Desk_1`, etc.). Admin holds `Ohm_Event_Fixture_Access`, `EinsteinGPTPromptTemplateUser`, `EinsteinGPTPromptTemplateManager`.
- **Ohm core app installed** (deploy `0Afaj00000jW4o9CAC`, 283/283 tests) and **all four bundles audited through the live source connection and GPT 5.5 reviewer**: Support Desk Input C, Sales Follow-up Output B, Schedule Planner Calls B, Schedule Desk A/A/A (reports `a00aj00003WVjcnAAD`, `a00aj00003WVjcoAAD`, `a00aj00003WVjcpAAD`, `a00aj00003WVjPtAAL`; verified in `docs/testing/results/2026-09-07/event-org/review-results.json`).
- **Not done:** live workflow evaluations (`evals/*.json`) and the browser demo rehearsal.
- Earlier accidental root-level deployment `0Afaj00000jVocvCAC` remains `Canceled`; it changed nothing.
- The runtime copy at `/tmp/ohm-event-fixtures-runtime` is in sync with this directory (only `.bundle-meta.xml` whitespace differs after publish). Run publication there because Salesforce CLI can modify authoring metadata. Keep this source/provenance package unchanged.

## Resume

From the repository root, verify local inputs:

```sh
python3 test-fixtures/event-demo/scripts/check-fixtures.py
```

**Run every Salesforce command below with working directory `/tmp/ohm-event-fixtures-runtime`, not the Ohm application root.** Verify that its `sfdx-project.json` has name `ohm-event-fixtures` first. If the runtime copy is missing, copy this directory to a separate staging location before publishing.

```sh
sf project deploy start --target-org ohm-hackathon --source-dir force-app --test-level RunSpecifiedTests --tests OhmDemoScheduleServiceTest --wait 10 --json
sf org assign permset --target-org ohm-hackathon --name Ohm_Event_Fixture_Access --json
```

Coordinate the standard Prompt Template User/Manager permissions with the main deployment task. The linked templates declare `sfdc_ai__DefaultGPT55` (changed Sept 7 evening from the recipe default `sfdc_ai__DefaultOpenAIGPT4OmniMini`; the model is part of each version identifier, so the change published new template versions). Ohm's reviewer also runs on GPT 5.5.

Validate, then publish each API name from the table, for example:

```sh
sf agent validate authoring-bundle --target-org ohm-hackathon --api-name Ohm_Support_Desk --api-version 67.0 --json
sf agent publish authoring-bundle --target-org ohm-hackathon --api-name Ohm_Support_Desk --skip-retrieve --api-version 67.0 --json
```

Query the actual generated `GenAiPlannerDefinition` rows and capture their IDs/names. Activate each logical agent using its observed version number with `sf agent activate --api-name <logical-api> --version <observed-number> --target-org ohm-hackathon --json`. Do not assume a `_v1` suffix or reuse IDs from the old scratch org.

[scenarios.json](scenarios.json) contains synthetic input examples and expected behavior. [evals/](evals/) contains two independent Salesforce evaluation cases per bundle, including missing/invalid input and direct agent-state capture. Once each agent is active, run its corresponding spec:

```sh
sf agent test run-eval --target-org ohm-hackathon --api-name Ohm_Support_Desk --spec evals/Ohm_Support_Desk.json --api-version 67.0 --result-format json --json
```

Retain real evaluator output and action traces. The inefficient sales fixture intentionally overproduces text; that is audit evidence, not a response-length acceptance test. Apex tests cover overlap rejection, exact-gap acceptance, chronological order, malformed input, bounds, bulk requests and equal-time ordering. They still need their first platform run.

After the Ohm app and source credential connection are installed, discover and audit the exact published bundles through Ohm. Do not import instruction snapshots or fabricate saved reviews. Capture actual Input/Output/Calls ratings, grounded recommendations and source freshness results. Model Fit remains hidden in the application interface while its raw review schema remains intact.

To regenerate local fixture metadata and source hashes, run `python3 test-fixtures/event-demo/scripts/prepare-fixtures.py` from the repository root. This only writes this fixture directory and never contacts an org. The scenario/evaluation JSON files are separately authored.
