# Event org install checklist

> **Checkpoint correction (September 7):** The first core deployment was canceled after tests failed on missing old weather/public fixture metadata. Before repeating step 1, finish test portability and install/publish the four event fixtures (steps 4–5) first. Initial fixture deployment must select only classes, linked prompt templates, and permission sets, with `RunSpecifiedTests` / `OhmDemoScheduleServiceTest`; authoring bundles are published afterward. Use an explicit working directory and verify the planned source paths. See the root [PROJECT_STATE.md](../../PROJECT_STATE.md) for exact current status. No current event install is yet verified.

This is the installation order for the current OHM app and the four controlled event fixtures in `test-fixtures/event-demo`. It is not a deployment receipt. Checks below were read-only on 2026-09-07; deployment, permission assignment, source setup, publication, and live verification are separate steps.

## Target and verified preflight

| Item | Observed value |
| --- | --- |
| CLI alias | `ohm-hackathon` |
| Organization ID | `00Daj000013wTtpEAE` |
| My Domain | `https://orgfarm-08e0e83a93.my.salesforce.com` |
| Demo username | `epic.f1c1977a25ca@orgfarm.salesforce.com` |
| Edition / sandbox flag | Enterprise Edition / `IsSandbox=false` |
| API | SOQL and metadata retrieval at 67.0 succeeded |
| Agent metadata | `GenAiPlannerDefinition` exists and is queryable |
| Required feature settings | Einstein GPT Platform, Agent Platform, Bots, and Einstein Copilot enabled |
| Prompt template deployment activation | `enableEinsteinGPTDeployPromptTemplatesAsActive=false` |
| AI providers | OpenAI and Azure OpenAI provider-disable flags are false |
| Beta models | `enableAIModelBeta=false` |
| Existing app permissions | `Ohm_App_Access` and `Ohm_Data_Access` existed and were assigned at preflight |
| Prompt permissions | Standard Prompt Template User and Manager permission sets exist; Execute/Manage Prompt Templates were not granted by the demo user's assignments at preflight |
| Reviewer template | `GenAiPromptTemplate` inventory was empty at preflight |

Existing app permission records do not prove that current app code was installed. No deployment was initiated by this preflight. The settings retrieval succeeded in an isolated temporary Salesforce project, with no changes to the target org or repository settings.

The three required model aliases are listed in Salesforce's current [Supported Models documentation](https://developer.salesforce.com/docs/ai/agentforce/guide/supported-models.html). Availability in this org still requires live verification: metadata capability and a provider-enabled flag do not establish execution permission, remaining capacity, or model access.

| Use | Exact model alias |
| --- | --- |
| OHM reviewer template | `sfdc_ai__DefaultGPT55` |
| Ask Ohm generated answers and drafts | `sfdc_ai__DefaultGPT55` (changed Sept 7 evening from `sfdc_ai__DefaultGPT4OmniMini` per user decision: no GPT-4o mini, use the latest model) |
| Four event linked prompts | `sfdc_ai__DefaultGPT55` (changed Sept 7 evening from the recipe default `sfdc_ai__DefaultOpenAIGPT4OmniMini`) |

Do not enable beta models merely because an older documentation page called GPT 5.5 beta. The current official list does not mark that alias beta. Probe the configured model first.

## 1. Deploy the app with an explicit metadata boundary

**Current integration-test prerequisite:** `OhmAuditTestSupport` reads a real published control bundle. A completely fresh org must first install and publish the event fixtures from steps 4–5 before the final app deployment with `RunLocalTests`. The test helper now accepts `Ohm_Schedule_Desk` or the prior Weather control; the other three event fixtures are required by fleet integration assertions. Coordinate fixture bootstrap with the deployment owner. Do not bypass the assertions or add a production discovery fallback. `OhmAuditControllerTest.testLegacyPlannerCannotQueueAnAuditOrAppearInAcquisition` still assumes the old legacy `Ohm_Waste_Demo` metadata exists; replacing that remaining integration dependency with a deterministic test seam is outstanding.

Run from the repository root. This includes Apex, UI, data fields, app navigation, permissions, and the reviewer template:

```sh
sf project deploy start --target-org ohm-hackathon \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/objects \
  --source-dir force-app/main/default/lwc \
  --source-dir force-app/main/default/staticresources \
  --source-dir force-app/main/default/applications \
  --source-dir force-app/main/default/tabs \
  --source-dir force-app/main/default/flexipages \
  --source-dir force-app/main/default/permissionsets \
  --source-dir force-app/main/default/genAiPromptTemplates \
  --test-level RunLocalTests --wait 30 --json
```

Keep `settings` out of this deployment. Repository settings are scratch-org snapshots and contain org-wide AI security and provider choices, including disabled masking and detection controls. Installing OHM does not require replacing those choices. The target's required feature flags are already enabled. Also exclude the legacy `genAiPlannerBundles`, `genAiPlugins`, and `genAiFunctions` folders: their old sample targets are outside current Agent Script scope and are not the event fixtures.

Wait for deployment success and inspect test failures before continuing. This target reports `IsSandbox=false`; do not assume scratch-only `NoTestRun` behavior is valid. If an existing org has unrelated failing Apex tests, report that evidence instead of treating the deployment as complete.

## 2. Grant access and verify the reviewer is active

Assign the app permissions and `EinsteinGPTPromptTemplateUser` to each audit user. Assign `EinsteinGPTPromptTemplateManager` to the setup admin who must inspect or activate templates. The setup connection step grants its separate principal-access permission.

```sh
sf org assign permset --target-org ohm-hackathon \
  --name Ohm_App_Access --name Ohm_Data_Access \
  --name EinsteinGPTPromptTemplateUser \
  --on-behalf-of epic.f1c1977a25ca@orgfarm.salesforce.com

sf org assign permset --target-org ohm-hackathon \
  --name EinsteinGPTPromptTemplateManager \
  --on-behalf-of epic.f1c1977a25ca@orgfarm.salesforce.com
```

Verify that `Ohm_Bundle_Environmental_Review` has an active version with model `sfdc_ai__DefaultGPT55` and required primitive String input `Input:evidenceJson`. The source metadata declares a published version and active version identifier, but this target's deploy-as-active setting is false. Inspect the deployed template and activate the intended version if necessary; do not assume source XML guarantees runtime activation. Preserve the existing org-wide activation setting.

For a non-admin demo user, also verify access to create and read Tasks. `Ohm_Data_Access` includes `Task.Ohm_Review_Key__c` field access; it does not establish all standard Task permissions on its own.

## 3. Configure the same-org source connection

Follow [LIVE-SOURCE-SETUP.md](LIVE-SOURCE-SETUP.md). For this temporary event demo the exact existing admin username may serve as both run-as and audit user; production should use a suitable dedicated integration user.

```sh
python3 scripts/source/setup-connection.py \
  --target-org ohm-hackathon \
  --run-as epic.f1c1977a25ca@orgfarm.salesforce.com \
  --audit-user epic.f1c1977a25ca@orgfarm.salesforce.com
```

The script creates External Client App `Ohm_Source_Retrieval`, its policy, External Credential `Ohm_Salesforce_Auth` with named principal `SourceReader`, Named Credential `Ohm_Salesforce`, and permission set `Ohm_Source_Retrieval_API`. It obtains Salesforce-generated current credentials and stores encoded values in the encrypted credential vault. Do not print credentials or substitute a CLI session for this connection.

Creation deliberately refuses collisions with reserved components. `--update` is only for validating a complete existing connection and refreshing its current vault values; it does not repair partial installation, change run-as, rotate secrets, or assign new users. Inspect a partial failure before choosing the repair. Check the script's cleanup result for its temporary setup permission and temporary credential-visibility setting.

## 4. Deploy the controlled event fixtures

Use `test-fixtures/event-demo`, not the old public recipe deployments, weather variants, or the entire `test-fixtures` tree. These four synthetic bundles adapt public Salesforce recipe wiring; deliberately added issues are not claims about upstream defects. Their provenance and Apache license are included in that project.

| Bundle API name | Linked prompt | Intended test |
| --- | --- | --- |
| `Ohm_Support_Desk` | `Ohm_Support_Reply` | Repeated input policy |
| `Ohm_Sales_Follow_Up` | `Ohm_Sales_Follow_Up_Email` | Unnecessary output variants and formats |
| `Ohm_Schedule_Planner` | `Ohm_Plan_Day` | Fixed scheduling calculations in a prompt |
| `Ohm_Schedule_Desk` | `Ohm_Present_Validated_Plan` | Existing Apex preparation and prompt presentation control |

**Correction (Sept 7 evening):** all four are published as `AgentforceServiceAgent`, not `AgentforceEmployeeAgent`. The hackathon trial org is not licensed for the Employee Agent template (publish returns HTTP 401 "no access to agent templates associated with the AgentforceEmployeeAgent agent type", which the CLI masks as an empty `FetchError` against `test.api.salesforce.com`). Each `.agent` sets `default_agent_user` to the dedicated Einstein Agent User `ohm.fixture.agent@orgfarm-08e0e83a93.ohm` (`005aj00000dVdUrAAK`; permission sets `AgentforceServiceAgentBase`, `AgentforceServiceAgentUser`, `EinsteinGPTPromptTemplateUser`, `Ohm_Event_Fixture_Access`). They use required primitive String inputs and synthetic scenarios, with no fixture custom objects or Data Cloud data providers. `OhmDemoScheduleService` and its Apex test are the only fixture classes. The control's grade is not preassigned; the live reviewer must assess its actual source.

From the `test-fixtures/event-demo` project directory:

```sh
sf project deploy start --target-org ohm-hackathon \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/genAiPromptTemplates \
  --source-dir force-app/main/default/permissionsets \
  --test-level RunSpecifiedTests --tests OhmDemoScheduleServiceTest --wait 10 --json

sf org assign permset --target-org ohm-hackathon \
  --name Ohm_Event_Fixture_Access \
  --on-behalf-of epic.f1c1977a25ca@orgfarm.salesforce.com
```

Verify or activate each of the four linked prompt templates before publishing its agent. Their exact configured model is `sfdc_ai__DefaultGPT55` (a Models API probe on Sept 7 showed `sfdc_ai__DefaultGPT55`, `DefaultGPT5`, `DefaultGPT5Mini`, `DefaultGPT41`, `DefaultGPT41Mini`, Gemini 2.5 Flash, and Claude 4/4.5 Sonnet generate in this org; `DefaultGPT55Mini` and Gemini 2.5 Pro/3.0 Pro do not).

## 5. Publish all four Agent Script bundles

Run sequentially from the event fixture project, keeping the CLI results and actual published versions:

```sh
sf agent publish authoring-bundle --api-name Ohm_Support_Desk --target-org ohm-hackathon --skip-retrieve --api-version 67.0 --json
sf agent publish authoring-bundle --api-name Ohm_Sales_Follow_Up --target-org ohm-hackathon --skip-retrieve --api-version 67.0 --json
sf agent publish authoring-bundle --api-name Ohm_Schedule_Planner --target-org ohm-hackathon --skip-retrieve --api-version 67.0 --json
sf agent publish authoring-bundle --api-name Ohm_Schedule_Desk --target-org ohm-hackathon --skip-retrieve --api-version 67.0 --json
```

Then query `GenAiPlannerDefinition` for those four API-name families and confirm the expected versioned planners. OHM selects the highest numeric published version per family, then verifies that the retrieved versioned `AiAuthoringBundle` targets the exact selected planner. An unversioned draft is insufficient. Never carry planner IDs or `_vN` suffixes from the scratch org into this org.

OHM auditing requires publication; activation is separately required for executing the agents in a runtime evaluation. If running that evaluation, activate each actual newly published version. Note: the authoring bundles must be deployed as metadata (`sf project deploy start --source-dir force-app/main/default/aiAuthoringBundles`) before `sf agent publish` succeeds. All four were published and activated as v1 on Sept 7 (see [fixture-install-receipt.json](results/2026-09-07/event-checkpoint/fixture-install-receipt.json)).

## 6. Establish fresh live evidence

1. Open `/lightning/n/Ohm_Audit` on the event org's Lightning domain and confirm the four expected bundles appear. Existing unrelated org agents may also be legitimate published bundle candidates; do not delete them to force a count.
2. Start a fresh OHM audit for each event bundle. Confirm retrieval, source binding, review, and persistence complete. Every run must retrieve current published source through the configured connection; no instruction-import script is needed.
3. Verify the linked prompt appears under the correct bundle, with the saved reviewer result and quoted evidence. Compare the support, sales, schedule, and efficient-control results without forcing expected grades.
4. Collect exact source-bound proof with the current report IDs:

   ```sh
   python3 scripts/testing/collect-review-results.py \
     --target-org ohm-hackathon \
     --report-id ACTUAL_REPORT_ID \
     --output docs/testing/results/2026-09-07/event-org/review-results.json
   ```

   Repeat `--report-id` to include all four reports. Save credentials-free deployment, test, and publication summaries alongside this result.

5. Verify Recommendations → bundle review → exact source → Ask Ohm. The recommendation route prefills a question without sending it. Explicit source-help requests can focus the composer. Saved review explanations may be deterministic; a generated answer or draft must separately prove the Ask model connection.
6. Exercise a draft from retrieved source, the review/diff surface, and a tracked Task with the actual current report. Confirm the source is not automatically changed or redeployed. Re-audit once to verify retry/resume and task lifecycle against a fresh report.
7. Rehearse the five-minute demo at the event browser width, including loading states and scroll position under the Salesforce fixed header.

## Automation boundaries and remaining gates

Safe installation automation can stage the explicit app folders, deploy and wait, verify permission assignments, call the existing source-setup script, install the isolated fixture project, publish sequentially, resolve actual planner versions, and collect exact new report IDs. Make org ID verification the first gate and keep every command's explicit target. Record nonsecret result summaries and fail on incomplete stages.

The remaining live gates are active templates, GPT 5.5 reviewer execution, GPT 5.5 for Ask Ohm and the linked prompts, source connection cleanup and retrieval, fixture publication, Apex tests, and the browser demo. The read-only preflight did not call an LLM or establish those results.

Do not reuse `refresh-demo-data.py` for the event org: its org-ID guard intentionally targets the old scratch org. `audit-public-workflows.apex` also hardcodes the old public planner names and weather version. `collect-demo-results.py` has a scratch-specific default task ID. Use exact new event IDs or a dedicated event runner; never bypass those guards or report old evidence as a new-org result.
