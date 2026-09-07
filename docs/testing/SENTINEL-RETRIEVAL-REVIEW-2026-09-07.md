# Sentinel reuse and live source retrieval check

Verified September 7, 2026 against Slack Sentinel commit `a6d3d9f` and OHM scratch org `ohm-audit-lab`, API 67.0. Sentinel's local main matched GitHub after fetching origin. This was a code review and read-only retrieval check; no Salesforce business data, agent metadata, or credentials were changed.

## Decision

Use Sentinel's authenticated Apex HTTP client pattern as the starting point for OHM source acquisition. Keep OHM's audit evidence and coverage model. Add readers for agent instructions and active prompt templates, then connect them to a background audit job.

This check establishes live source availability through CLI-authenticated Salesforce APIs. It does **not** establish authentication from installed OHM Apex or an implemented in-app retrieval flow.

## Reusable Sentinel code

- `ToolingAPIManager.cls:7`: `callout:Tooling_API` Named Credential endpoint. The client implements paginated queries and composite reads of Flow metadata and ApexClass/ApexTrigger bodies.
- `AgentMetadataDrillDown.cls:124`: full source responses with identity, Flow version/status, and Salesforce Setup links.
- `ChunkerMasterBatch.cls:7`: asynchronous callout-capable orchestration. With scope size one, each artifact-family step retrieves before writing.

The existing template code calls `generateMessagesForPromptTemplate` with `isPreview=false` and consumes generated text. It does not retrieve template definitions. No agent-instruction or prompt-source reader was found.

## Verified live reads

### Prompt template

GET `/services/data/v67.0/einstein/prompt-templates/Generate_Personalized_Schedule/versions?includingContent=true&includingVersionDetail=true` returned actual template content, `ActiveVersionId`, `IsActiveVersion`, `VersionIdentifier`, `Status`, `LastModifiedDate`, and `PrimaryModel`.

The active version is published, with model `sfdc_ai__DefaultOpenAIGPT4OmniMini`. Its version identifier matches separately retrieved `GenAiPromptTemplate` metadata XML. Standard SOQL against `GenAiPromptTemplateVersion` returned `INVALID_TYPE`; this test does not support replacing the API reader with ordinary SOQL.

REST content has 903 characters and XML content has 832. For this fixture, eleven `&#92;n` sequences and four `&#39;` sequences account for the entire difference. A single pass replacing those exact representations with LF and apostrophe produces byte-identical content, SHA256 `dce551c323ad092321d0f2389dc1247dbaeecf140cf968ff071354827bb47628`. Preserve raw evidence and test literal backslashes/entities before adopting general decoding behavior. Do not trim, collapse whitespace, or normalize Unicode indiscriminately.

### Agent Script

CLI retrieval of authoring bundles returned source and companion bundle metadata from Salesforce:

| Published target | Source bytes | Match with reviewed repository source |
|---|---:|---|
| `Ohm_Weather_Demo.v4` | 6,429 | Exact match with controlled after source |
| `PromptTemplateActions.v1` | 2,998 | Exact match with upstream public recipe |

Retrieving weather versions also returned v1–v4. The retrieved source for v2 and v4 matches the clean source; v1 and v3 have the larger prior source. Select using the bundle's `target`, not a filename suffix. Exact-version retrieval can return an unversioned directory name. The CLI's reported `fileProperties` omitted authoring files even though the retrieved output contained them; validate actual source output and version relationships.

The direct transport was also verified in the installed Salesforce CLI implementation: `@salesforce/source-deploy-retrieve` calls SOAP Metadata API `retrieve`, polls `checkRetrieveStatus`, base64-decodes `result.zipFile`, and extracts those ZIP entries. Metadata-format retrieval skips source-conversion hooks. JSforce uses `/services/Soap/m/{version}`. The CLI deletes the ZIP after extraction when `--unzip` is set, explaining the missing archive afterward. There is no custom authoring REST fetch in this path. The retrieved authoring source therefore came from the Metadata API ZIP, despite the omitted `fileProperties` entries.

## Changes required for OHM

1. Provision and prove an OHM API connection. Sentinel's original checkout points to `hackathon`; neither that alias nor `dom@slacksentinel.com` is currently authorized. Available Git history and the original checkout contain no deployable credential configuration. Sentinel's README explicitly lists the credentials as external setup.
2. Adapt the HTTP transport to the current API version and report every query/subrequest failure. Sentinel currently skips failed composite items and parses query bodies before checking HTTP status.
3. Implement artifact-specific source readers and published-version matching. Include prompt-template version freshness independently of planner timestamps.
4. Store lossless, versioned source in OHM's evidence layer. Sentinel truncates Flow content at 12,000 characters and Apex content at 16,000; its search chunks are unsuitable as authoritative audit source.
5. Partition background jobs by bounded artifact work. Sentinel's composite batch size controls HTTP request grouping; its master batch still loads an entire artifact family in one transaction. Keep callouts before DML and persist durable failure/completeness status.
6. Wire retrieval to `auditProcess`, reuse the detector/persistence chain, and make Fleet and ProcessPage poll report status. Verify that a fresh audit needs neither local files nor a CLI import.

Machine-readable proof: [verification.json](results/2026-09-07/source-retrieval/verification.json).
