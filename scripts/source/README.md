# Import versioned instruction source

Ohm inventories published planner/topic/action records through Salesforce relationships. Modern `.agent` instruction blocks and legacy nested plugin instructions are not available in the queried `Scope`/`AgentGraph` fields. This importer makes the actual source available to the audit without guessing that descriptions are instructions.

Deploy the application first. Run as an administrator authorized to read source and create `Ohm_Instruction_Source__c` records. The script reads local source and org inventory, writes a reviewable JSON manifest, and only appends it to Ohm when `--apply` is supplied. It never publishes an agent or changes a business record.

```sh
python3 scripts/source/import-instructions.py \
  --target-org ohm-audit-lab \
  --planner-api-name ActionDefinitions_v1 \
  --source-revision ac5ccac8f675153035370abbdce174e2b769c89c \
  --agent-script test-fixtures/public-agents/agent-script-recipes/force-app/main/02_actionConfiguration/actionDefinitions/aiAuthoringBundles/actionDefinitions/actionDefinitions.agent \
  --output /tmp/ohm-weather-source-manifest.json \
  --apply
```

Use the same command with `ActionChaining_v1` and its `actionChaining` bundle for the payment control. For `PromptTemplateActions_v1`, use its `promptTemplateActions` bundle and add:

```sh
--prompt-template test-fixtures/public-agents/agent-script-recipes/force-app/main/02_actionConfiguration/promptTemplateActions/genAiPromptTemplates/Generate_Personalized_Schedule.genAiPromptTemplate-meta.xml
```

Each import records the exact published planner ID, its API name, a fingerprint of current planner/topic/action metadata IDs and modification times, the supplied immutable source revision, a hash of each whole file, and the SHA-256 of each extracted instruction block. Topic matching requires the exact source block name and the published owning-planner suffix. The importer resolves prompt metadata IDs using Salesforce's metadata listing. Unknown expressions, unmapped topics, missing prompt versions and source mismatches fail instead of substituting nearby text.

An import is an explicit assertion that the supplied local files correspond to the selected publication; the metadata fingerprint does not prove that assertion by itself. Use the exact files that were published or freshly retrieved source. After a metadata publication, the audit rejects an old fingerprint and asks for a fresh import. The source revision must describe the new files. Audit reports retain the source version and content hash independently of later imports.

Agent Script conditional DSL is retained verbatim within the extracted instruction block. Its static source size is not a measurement of the prompt rendered on a particular execution path. Ohm does not infer an execution graph from the script and marks redundant-call coverage unknown when the platform graph is absent. Prompt templates can change independently of planner metadata; an imported model remains assumed and does not establish a live binding or justify model-switch savings. These limits appear in audit coverage.

The `--legacy-plugin` option (repeat per topic, instead of `--agent-script`) reads `genAiPluginInstructions/description`, separately from `scope`. It currently requires authoritative topic relationships and exact plugin API names. Legacy metadata lacking these relationships requires a future explicit mapping adapter; the importer refuses to infer one. Planner-level instructions and graph coverage remain unknown for plugin-only imports.

The storage limit is 131072 characters per manifest. Oversized bundles are rejected before insertion. The read path is bulk-safe and does not make metadata or model callouts.

Parser regressions:

```sh
python3 -m unittest discover -s scripts/source -p 'test_*.py' -v
```

Apex relationship, fingerprint and source-staleness contracts are in `OhmDiscoveryContractTest`; deployed public inventory contracts remain in the separate lab test package.
