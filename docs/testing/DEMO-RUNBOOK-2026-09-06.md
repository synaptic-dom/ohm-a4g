# Verified Ohm demo runbook

> Historical import-based rehearsal. Use the [September 7 live retrieval runbook](DEMO-RUNBOOK-2026-09-07.md) for the refreshed demo. The old audit records and Task IDs below were backed up and soft-deleted.

Use scratch alias `ohm-audit-lab`, expiring **September 13, 2026**. The final clean weather agent is active as `Ohm_Weather_Demo_v4`. [Implementation and evidence](DEMO-IMPLEMENTATION-2026-09-06.md) record two completed browser rehearsals.

Open the app:

```sh
sf org open --target-org ohm-audit-lab --path /lightning/app/c__Ohm
```

## Show the verified result

1. Fleet: show three real Salesforce recipes—weather with Flow/Apex, a four-step payment Flow chain, and a prompt-template schedule. Inventory must read **2/3, 2/4 and 2/1** topics/actions. Explain that graph/model gaps produce **Incomplete** coverage.
2. Open **Controlled Weather Demo**. Select **Weather Lookup**. Show the imported source path/version/hash and its current 773 characters, approximately 194 source tokens.
3. Expand **Compare last two audits**. Both sides must identify Weather Lookup. Show **4,085 → 773 characters**, **1 → 0 findings**, and modeled instruction input **63,742.14 → 14,782.50 Wh/year**. Coverage remains Incomplete because a complete execution graph is unavailable.
4. Open Findings: the weather issue is absent. The existing remediation Task is **Completed**, still assigned to the scratch administrator with due date September 8. Its ID is `00TEc00000a9bLNMAY`.
5. Trends: select the weather process. History spans the logical agent's publications. Describe **modeled reduction**; do not imply measured energy, actual call volume or realized environmental savings.

## Rehearse a fresh full loop

The [controlled fixture instructions](../../test-fixtures/controlled-weather/README.md) contain scoped deploy/publish/import commands. Keep the original public corpus immutable.

1. Deploy and publish the `before` authoring bundle. Query the actual new planner version, activate that exact version, then import the matching before file and revision. A fresh published version should appear unaudited in Fleet.
2. Audit through the UI, open Weather Lookup, and inspect its source and finding. The restored baseline is approximately 63,742 modeled Wh/year. The original Task should reopen and retain its owner/date.
3. Use **Explain the evidence**, then **Draft trimmed instructions**. Exact adjacent duplicate prose removal is deterministic and explicitly labeled. Review the entire 773-character draft against the reference repair, including all conditional branches and action/variable references. A model draft that changes structure must be rejected.
4. Use **Create remediation task** and verify that it reuses the existing Task. Set the finding to Accepted. The pre-edit 500-token-budget estimate is **30,865.86 Wh/year**, which is different from the actual reviewed trim's later modeled delta.
5. Apply the reviewed `after` authoring bundle manually, publish and activate its actual new version, then import matching after source. Audit that new version through the UI.
6. Verify the finding clears, Task completes, same-artifact snapshots exist on both sides, and the modeled residual remains **14,782.50 Wh/year**. Confirm no duplicate Task. Use the published workflow smoke runner when the source or action dependencies materially change.
7. Refresh the evidence bundle with `python3 scripts/testing/collect-demo-results.py`.

Publication/import and model calls take variable time. If recording a short demo, clearly mark cuts around those waits. Source import is an explicit operator assertion that the supplied files match the publication; it is not automatic source retrieval or automatic application.

## Boundaries to state

The weather redundancy is intentionally introduced for a controlled test. Published weather/forecast/alert actions are sample stubs. Ohm's energy figure is a low-confidence instruction-source scenario with default modeled volume, excluding output tokens, actual branch frequency and tool compute. Automatic apply/revert, measured runtime energy, full execution-graph extraction and broad legacy/RAG support remain follow-on work.
