# Controlled weather remediation demo

This is an explicitly controlled variant of Salesforce's public `ActionDefinitions` recipe. The original public corpus is unchanged. The `before` version repeats an existing weather instruction 36 times; the `after` version removes only those duplicate lines. It demonstrates a known audit condition, not a newly discovered defect in Salesforce's sample.

Both versions use the logical agent API `Ohm_Weather_Demo`, keep the original weather actions and conditional branches, and depend on the already-deployed `GetCurrentWeather`, `GetWeatherForecast`, and `WeatherAlertService` fixture dependencies. This package contains only the authoring bundle. The source commit, hashes and exact edits are recorded in [PROVENANCE.json](PROVENANCE.json) and [remove-controlled-redundancy.patch](remove-controlled-redundancy.patch).

The extracted weather instruction shrinks from **4085 characters (~1022 tokens)** to **773 characters (~194 tokens)** using Ohm's character-based estimator. The system and router instructions remain unchanged. The source remains below the assistant's 8000-character rewrite guard. Dynamic source text is a static estimate; the demo does not claim measured runtime token usage or full graph coverage.

Run the following from `test-fixtures/controlled-weather/before` after the updated Ohm application and original weather dependencies are deployed:

```sh
sf project deploy start --target-org ohm-audit-lab --source-dir force-app --test-level NoTestRun --wait 1 --json
sf agent publish authoring-bundle --api-name Ohm_Weather_Demo --target-org ohm-audit-lab --skip-retrieve --api-version 67.0 --json
```

Query the actual published version; do not assume its suffix or reuse a stale planner ID:

```sh
sf data query --target-org ohm-audit-lab --query "SELECT Id,DeveloperName,LastModifiedDate FROM GenAiPlannerDefinition WHERE DeveloperName LIKE 'Ohm_Weather_Demo_v%' ORDER BY LastModifiedDate DESC" --json
```

Activate the exact published version before behavior testing (`sf agent activate --api-name Ohm_Weather_Demo --version <actual-version-number> --target-org ohm-audit-lab --json`).

From the repository root, import the matching source using the exact returned planner API name (initial publication is normally `Ohm_Weather_Demo_v1`):

```sh
python3 scripts/source/import-instructions.py \
  --target-org ohm-audit-lab \
  --planner-api-name Ohm_Weather_Demo_v1 \
  --source-revision controlled-weather-before \
  --agent-script test-fixtures/controlled-weather/before/force-app/main/default/aiAuthoringBundles/Ohm_Weather_Demo/Ohm_Weather_Demo.agent \
  --output /tmp/ohm-controlled-weather-before-source.json \
  --apply
```

Audit this agent, inspect the weather topic, create a remediation Task, and retain the report ID and source hash. Ask Ohm about the selected instruction artifact. Review any assistant draft against the exact source before applying it. The clean `after` version is the reviewed reference repair; it can be diffed directly against a draft.

To apply the reference repair, run the deploy/publish commands from `test-fixtures/controlled-weather/after`, resolve the newly published planner version again, then repeat the import command with that exact planner API name, the `after` source path and `controlled-weather-after` revision. Re-audit that logical agent, verify that the bloat finding cleared, and compare the same source artifact and usage scenario. Residual modeled instruction cost must remain above zero. Verify that the preserved remediation Task completed automatically.

For a second rehearsal, deploy/publish/import `before` again, capture the new version and audit it, then repeat the `after` steps. A reopened issue should retain its logical identity and avoid duplicate remediation Tasks. Publication may create a new platform planner ID; the application must compare its normalized logical API identity and instruction artifact, not two unrelated processes. Record actual report IDs and planner versions for both rehearsals.

The reference packages can be regenerated with `python3 scripts/source/prepare-controlled-weather.py`. This only writes `test-fixtures/controlled-weather`; it never mutates the public corpus or a Salesforce org.

## Published behavior smoke

After activation, run the five independent published cases with Salesforce's official evaluation CLI. This does not deploy source or create test metadata:

```sh
python3 scripts/testing/smoke-weather-workflow.py \
  --planner-api-name Ohm_Weather_Demo_v1 \
  --phase before \
  --source-file test-fixtures/controlled-weather/before/force-app/main/default/aiAuthoringBundles/Ohm_Weather_Demo/Ohm_Weather_Demo.agent \
  --output docs/testing/results/2026-09-06/fixed-demo/workflow-before.json
```

After publishing and activating the clean version, use its actual planner API name, `--phase after`, the `after` file, and `workflow-after.json`. The JSON specification is [workflow-smoke.json](workflow-smoke.json). It checks missing location, current weather, five-day forecast, an out-of-scope programming request, and the formatting-only weather-alert action. The evaluator scores expected response meaning; inspect the retained outputs as well as its pass count. The initial remote action-name evaluator received nested function objects and reported a mismatch even for a successful alert call. That failed before probe remains in the evidence. The corrected repeatable runner requests agent state without that unsupported remote assertion, then directly verifies the exact function name, input, successful execution, and returned alert text. No real alert or email delivery is performed.

With installed `@salesforce/plugin-agent` 1.42.1, published `agent preview start` hardcodes `bypassUser:true`. The controlled employee agent has no default service user, so that preview path fails with an empty user-ID error even after activation. `agent test run-eval` supplies the current user's identity and successfully exercises the published agent. The [Agent API documentation](https://developer.salesforce.com/docs/ai/agentforce/guide/agent-api-examples.html) distinguishes the assigned-agent user from the token user. Keep the fixture's employee-agent type; do not change its identity merely to accommodate that CLI preview default.
