# Live Salesforce source retrieval

OHM's audit unit is a published Agent Script bundle. It retrieves that bundle's instructions and the active prompt-template text referenced by its actions from Salesforce when an audit starts. Linked prompt content remains part of the bundle audit. Local source import is no longer required for the tested workflows.

The scope excludes legacy agents and independent prompt-template, Flow or Apex audits. Flow/Apex action references provide context within a bundle; their implementation source is not retrieved or audited. Broad asset discovery is not planned within this scope. Legacy parser utilities remain for compatibility tests, outside the production audit path.

The bundle-only scope change is deployed and verified. Deployment `0AfEc00000nZaHKKA0` succeeded with **264 Apex executions and zero failures**; **24 Jest suites / 187 tests passed**. Browser verification confirmed the “Published Agent Script bundles” heading, dependency boundary copy, Bundle table and exactly four rows: `ActionDefinitions_v1`, `Ohm_Weather_Demo_v4`, `PromptTemplateActions_v1` and `ActionChaining_v1`. See [scope validation](results/2026-09-07/bundle-scope/summary.json). The live source, hash and refreshed dataset evidence below records the prior retrieval baseline.

After the scope deployment, a browser **Re-audit** of `PromptTemplateActions_v1` completed as report `a00Ec00000lt3JxIAI`. Its four source snapshots passed hash and binding checks. The linked prompt again contained exactly **832 characters**, retained the same active model and source hash, and appeared under its parent bundle in the inspector. The before/after view matched the same artifact with no source change. [Post-scope live evidence](results/2026-09-07/bundle-scope/linked-prompt-reaudit.json).

## What runs in the application

1. The LWC starts an audit and receives a durable queued report ID.
2. Apex discovers the selected Agent Script planner, topics and actions through Salesforce records and pins their metadata fingerprint.
3. Background jobs call the Metadata API through `Ohm_Salesforce`, using renewable OAuth client credentials stored in an encrypted External Credential. The SOAP API receives its required session header. No CLI token is injected into Apex.
4. Retrieval lists source candidates, downloads a metadata ZIP, and checks the authoring bundle's actual publication target. A bundle's numeric authoring revision is not assumed to equal the runtime version.
5. Actions that invoke a prompt template resolve its exact API name. The parser selects the active version's content and model, preserving source whitespace. This adds the linked prompt source to the bundle audit; the template does not need topics or actions of its own. Metadata modification times are verified again before completion.
6. The audit pins fresh source, computes findings and modeled impact, saves immutable snapshots, and updates remediation state atomically. Source JSON preserves edge whitespace that Salesforce long-text fields otherwise trim.
7. The UI resumes pending report IDs after refresh, shows retryable failures, and only displays completion after receiving that report's results. The inspector identifies Salesforce retrieval, exact version, retrieval time, source location and SHA-256.

## Prior live verification

All four tested Agent Script bundles completed through this application retrieval path and remain in the selected scope:

| Workflow | Verified publication | Topics / actions | Result |
|---|---|---:|---|
| Public weather bundle with Flow/Apex action references | `ActionDefinitions.v1` | 2 / 3 | Bundle source retrieved; no findings |
| Public payment action chain | `ActionChaining.v1` | 2 / 4 | Source retrieved; no findings |
| Public prompt-template schedule | `PromptTemplateActions.v1` | 2 / 1 | Source and active model retrieved; one instruction-size finding |
| Controlled clean weather | `Ohm_Weather_Demo.v4` | 2 / 3 | Source retrieved; no findings |

The schedule prompt contains **832 characters**, including its original trailing newlines. Its content hash matches the independently retrieved Salesforce XML:

`dce551c323ad092321d0f2389dc1247dbaeecf140cf968ff071354827bb47628`

Its active version is `ul8eo8Wmi00b0AAaWZ5z5Q0cwb3Wq2HdIrEhx41Dtl4=_1`; the selected model is `sfdc_ai__DefaultOpenAIGPT4OmniMini`. The public Agent Script file also matches its upstream fixture hash exactly.

A browser rehearsal caught the scratch org's default five-job chain limit. The initial job now declares a bounded 200-job chain, and durable execution, time, poll and retry limits remain in force. A subsequent prompt run completed across seven transactions. Refreshing the browser during that run resumed the same report. Failure retention, retry, completion and the source inspector were inspected in the real application, including long version/path/hash wrapping at a narrow panel width.

The rehearsal also exposed duplicate coverage warnings; the coordinator now deduplicates them before persistence.

Evidence: [live runs](results/2026-09-07/live-retrieval/live-rehearsal.json), [exact prompt hashes](results/2026-09-07/live-retrieval/prompt-source-proof.json), [Apex connection](results/2026-09-07/live-retrieval/apex-connection.json), [browser checks](results/2026-09-07/live-retrieval/browser-checks.json), and [Apex suite](results/2026-09-07/live-retrieval/apex-tests.json).

## Fresh demo and prior validation

The scoped reset backed up and soft-deleted 15 reports, 64 snapshots, five findings, 11 stored source manifests and one linked remediation Task. No published agent or action metadata was deleted. The private backup directory is recorded in [the reset receipt](results/2026-09-07/live-retrieval/data-refresh.json).

The four replacement audits all completed. Each has a newly retrieved source manifest, verified hashes and verified source bindings. There is one current Open prompt-size finding and no remediation Task. [Fresh dataset](results/2026-09-07/live-retrieval/fresh-demo-results.json).

Prior retrieval validation: **259 Apex executions passed**, **24 Jest suites / 187 tests passed**, plus the focused Python setup, reset, parser and async-collector checks. These counts predate the bundle-only scope change. The reusable setup script's `--update` path passed against the scratch org, restored the original REST-secret access setting and removed its temporary permissions. A subsequent Apex Metadata API call succeeded. [Jest evidence](results/2026-09-07/live-retrieval/jest-tests.json), [setup smoke result](results/2026-09-07/live-retrieval/connection-setup-smoke.json). The script's new-org provisioning path has offline tests; the initial live connection was provisioned during implementation before the reusable script was completed.

## Remaining boundaries

These are authored instruction sources, not rendered runtime prompts or measured token usage. Source retrieval does not execute the agent or its actions. Complete execution graphs remain unavailable for these publications, so repeated-call coverage is Unknown and overall coverage remains Incomplete. The energy estimates remain modeled scenarios.

Automatic edit/apply/revert, runtime telemetry, arbitrary authoring aliases and large-org retrieval beyond the documented bounds remain separate work. Legacy agents, standalone assets and broader RAG discovery are outside the selected scope; they are not retrieval gaps to fill for this demo. Compatibility tests for legacy parsing do not make legacy agents supported production audit targets.

The older `DiscoverAgenticWork` / `RunSignals` invocable helpers are outside this supported demo audit path. They can analyze saved or supplied graphs without the dashboard retrieval gate and cannot complete a full audit themselves. No current dashboard or deployed Flow/action XML references them; migrating that interface remains separate work.

Connection setup is org-specific; use [the setup guide](LIVE-SOURCE-SETUP.md). The demo scratch org expires September 13, 2026. No changes have been pushed to GitHub.
