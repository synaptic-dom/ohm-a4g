# Ohm scratch-lab acceptance checks

This separate Salesforce project contains test-only classes and narrowly scoped fixture permissions. It is excluded from the main Ohm application package. Current application baseline: `038b5a0`.

- `OhmPublicWorkflowAcceptanceTest` reads the three published Agent Script Recipes. Its five checks cover ownership discovery, prompt type, the real scheduling description, model classification, and a deterministic Flow negative control.
- `OhmAuditLifecycleAcceptanceTest` uses isolated synthetic reports/findings/Tasks to exercise desired lifecycle, trend, coverage and unknown-model behavior. Apex test data is rolled back.
- `Ohm_Public_Fixture_Access` grants access to the selected upstream recipe objects/classes and required Contact/Account reads. This repaired a fixture USER_MODE query failure. It is not the application's non-admin permission fix.

Observed on September 6, 2026: **1 pass / 9 fail of 10**. These failures reproduce unmet product contracts. Additional instruction-source, accounting, snapshot, Task synchronization and browser checks are still needed; ten passing tests alone will not establish a complete demo.

Deploy after the Ohm app and recipe dependencies exist:

```sh
cd test-fixtures/lab-tests
sf project deploy start --target-org ohm-audit-lab --source-dir force-app --test-level NoTestRun --wait 2
sf org assign permset --target-org ohm-audit-lab --name Ohm_Public_Fixture_Access
sf apex run test --target-org ohm-audit-lab --class-names OhmPublicWorkflowAcceptanceTest OhmAuditLifecycleAcceptanceTest --result-format json --wait 2
```

The public recipes must be published with `ActionDefinitions_v1`, `ActionChaining_v1` and `PromptTemplateActions_v1` planners. Use an isolated scratch org; prompt-count expectations assume this documented fixture set. Publishing new versions or introducing more prompt actions may require selecting the corresponding fixture identities explicitly.

The fixture permission set supports these upstream checks:

```sh
sf apex run test --target-org ohm-audit-lab --class-names ActionChainingFlowTest ActionDefinitionsFlowTest WeatherAlertServiceTest PersonalizedGuestExperiencesTest --result-format json --wait 2
```

If the CLI returns a test-run ID before results, retrieve them with `sf apex get test --target-org ohm-audit-lab --test-run-id <ID> --result-format json`. Keep pending output distinct from a completed result.

See [the fix plan](../../docs/testing/DEMO-FIX-PLAN-2026-09-06.md) and [recorded results](../../docs/testing/results/2026-09-06/lab-results.json).
