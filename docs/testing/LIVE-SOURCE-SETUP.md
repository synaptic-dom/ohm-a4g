# Salesforce source retrieval connection

OHM retrieves published Agent Script bundle source and the active prompt-template text referenced by the bundle's actions from the target Salesforce org when an audit starts. Linked prompts are included in that bundle audit. Independent prompt-template, Flow and Apex audits, and legacy-agent audits, are outside the selected scope. Flow/Apex action references supply context; their implementation source is not retrieved or audited. Broad asset discovery is not planned within this scope, and legacy parser utilities are retained only for compatibility tests outside the production audit path.

Install the application first, then configure this connection once per org. The audit runs in asynchronous Apex; a developer's Salesforce CLI session is used only during connection setup. The connection setup below is unchanged by the deployed bundle-only scope restriction. Scope validation passed **264 Apex executions with zero failures** and **24 Jest suites / 187 tests**; the browser confirmed the four expected bundle rows and explicit dependency boundary. See [scope validation](results/2026-09-07/bundle-scope/summary.json). These checks supplement the earlier connection and retrieval evidence; they do not represent a new connection setup run.

The setup administrator needs an authenticated Salesforce CLI target, permission to deploy metadata, manage named credentials, and create, assign, and delete permission sets. The target needs API version 67.0, Agentforce metadata, and an existing active integration user. Supply the integration user's exact Salesforce **Username**, which can differ from their email address.

Use a dedicated integration user in production. Grant API access, the metadata API permissions needed to list and retrieve Agent Script bundles and their linked prompt templates, and only the other object or setup access the retrieval endpoints require. Salesforce's metadata API permission is broader than read-only source access; OHM only invokes retrieval operations, but the integration credential must still be treated as a privileged credential. Do not grant Modify All Data merely to avoid identifying required permissions. The scratch demo uses its administrator as the run-as user; that is a demo configuration, not a production permission template. Salesforce recommends dedicated integration users with access limited through permission sets. [Integration user guidance](https://developer.salesforce.com/blogs/2024/02/invoke-rest-apis-with-the-salesforce-integration-user-and-oauth-client-credentials), [metadata permission requirement](https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_org_list_metadata.html).

Create a new connection from the repository root:

```sh
python3 scripts/source/setup-connection.py \
  --target-org YOUR_EXPLICIT_ORG_ALIAS \
  --run-as integration-user@example.com \
  --contact-email salesforce-admin@example.com \
  --audit-user demo-auditor@example.com
```

`--target-org` and `--run-as` are required. `--contact-email` defaults to the integration user's Email field. `--audit-user` is optional and repeatable; it grants the connection's principal access to the named audit initiators. Without it, assign `Ohm_Source_Retrieval_API` to the intended audit users separately, alongside the existing OHM app permissions. Principal access belongs to the person starting the audit; the OAuth token separately runs as the fixed integration user.

The script creates these dedicated components:

| Component | API name | Purpose |
| --- | --- | --- |
| Local External Client App | `Ohm_Source_Retrieval` | API OAuth scope with client credentials enabled |
| ECA policy | `Ohm_Source_Retrieval_defaultPolicy` | Fixed run-as user; IP restrictions remain enforced |
| Custom External Credential | `Ohm_Salesforce_Auth` | Encrypted credential parameters under named principal `SourceReader` |
| Named Credential | `Ohm_Salesforce` | This org's HTTPS My Domain endpoint; body merge fields enabled |
| Permission Set | `Ohm_Source_Retrieval_API` | Access to the source retrieval principal |

New setup refuses to overwrite any existing reserved component. If all components are already configured, refresh their current credential values with:

```sh
python3 scripts/source/setup-connection.py \
  --target-org YOUR_EXPLICIT_ORG_ALIAS \
  --run-as integration-user@example.com \
  --update
```

`--update` validates the existing endpoint, authentication protocol, named principal, and run-as policy. It only refreshes the vault; it does not redeploy the existing ECA or connection, change the run-as user, grant audit users, or rotate a consumer key or secret. A partial previous setup must be inspected and completed or removed before retrying. The script deliberately leaves durable application components in place after a failed new setup rather than deleting a potentially usable connection.

Salesforce generates the actual consumer credentials. Supplying a `consumerSecret` in metadata did not produce a usable client secret in the scratch-org verification. The script therefore never supplies a key or secret in an ECA metadata deployment. It temporarily enables `ExternalClientAppSettings.enableClientSecretInRestApiAccess`, grants its administrator a uniquely named temporary setup permission set, and reads the generated credentials through Connect REST:

1. `/apps/oauth/usage` identifies the exact ECA by developer name.
2. `/apps/oauth/credentials/{appId}` identifies its current OAuth consumer.
3. The consumer URL with `?part=key` and `?part=secret` returns the current generated values. Staged credentials are not accessed.
4. `GET /named-credentials/credential` validates the exact named principal and checks its authentication parameter names. Custom credentials can report status `Unknown` even when working, so that status alone does not establish whether a vault exists. The script creates an absent vault with POST, or replaces existing values with PUT only under `--update`.

The temporary permissions are `ExternalClientAppDeveloper`, `ViewClientSecret`, `ExternalClientAppAdmin`, and `ExternalClientAppViewer`. The older `enableConsumerSecretApiAccess` metadata flag is not used. [Salesforce credential access prerequisites](https://help.salesforce.com/s/articleView?id=xcloud.eca_stage_oauth_credentials.htm&language=en_US&type=5), [Connect REST credential resources](https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/salesforce_chatter_rest_api.pdf).

The key and secret are URL-encoded into encrypted parameters `ClientIdEncoded` and `ClientSecretEncoded`. This encoding is required because Apex merges them into the form-encoded token request body. The script passes the values to `sf api request rest` through stdin, captures and suppresses raw CLI output, disables CLI file logging and telemetry for its child processes, and uses a private temporary directory with restrictive permissions. Its printed result includes deployment IDs and nonsecret setup facts; it does not print credential values or tokens. Credential values are not saved to repository files. [Populating external credential principals](https://developer.salesforce.com/docs/platform/named-credentials/guide/nc-populate-external-credentials.html).

Cleanup runs on success, ordinary failure, and handled interruption. It restores the original REST-secret setting, removes only its temporary permission assignment and definition, and compares all external-client-app settings against their original values. A pre-existing setting of `true` is preserved. If cleanup cannot be verified, the script exits unsuccessfully with specific nonsecret recovery instructions. A forced process kill or machine failure can prevent cleanup; check the REST-secret flag and remove the uniquely named `Ohm_Source_Setup_*` permission and its assignment if that happens. Do not run competing connection-setup processes against the same org.

At runtime, `OhmSalesforceApi` sends a client-credentials token request through `callout:Ohm_Salesforce`. It places the resulting token into the SOAP `SessionHeader` for Metadata API requests and the Bearer header for REST requests. A Bearer header alone does not authenticate the SOAP metadata calls. No CLI access token or session ID is stored in the app. [Client credentials flow setup](https://help.salesforce.com/s/articleView?id=sf.configure_client_credentials_flow_for_external_client_apps.htm&language=en_US).

Verify the connection by opening OHM as an authorized audit user and starting an audit for a published Agent Script bundle. A queued report should move through source retrieval to Complete, and its node inspector should identify a retrieved Salesforce source snapshot with version, retrieval time, and verified binding. Include a bundle whose action invokes a prompt template to verify that linked prompt content and the active model are retrieved too. A Complete report can still have incomplete detector coverage; review its coverage warnings. A source or authorization failure must produce a Failed report without partial findings. Publish a source change and re-audit to verify that the new report retrieves fresh source independently of the previous snapshot.

The environmental review phase also requires the deployed `Ohm_Bundle_Environmental_Review` Prompt Builder template to be active and the audit initiator to have **Execute Prompt Templates** (standard permission set `EinsteinGPTPromptTemplateUser`). The scratch administrator already has it. OHM invokes this reviewer after source verification and checks freshness again before completing the audit. A generation or response-validation failure stops completion while preserving prior reports. This permission is separate from the source integration user's OAuth access. See [the review contract and verification](ENVIRONMENTAL-REVIEW-2026-09-07.md).

The setup script's local safety tests do not contact Salesforce:

```sh
python3 -m unittest discover -s scripts/source -p test_setup_connection.py -v
```

They cover secret-free errors, stdin transport, same-org route validation, URL encoding, 15/18-character record identity, explicit vault replacement, refusal to overwrite metadata, and cleanup after source-read or uncertain-assignment failures. Live OAuth and retrieval behavior still requires the org smoke test above.
