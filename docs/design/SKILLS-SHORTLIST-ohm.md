## Top 10 Salesforce-dev tools for building Ohm

**Ohm** is an LWC experience + Agentforce agent that discovers *all* agentic work in a Salesforce org (agents, Prompt Builder templates, prompt-invoking Flows, Einstein generative features), scores each on four waste signals (LLM-where-deterministic, model right-sizing, instruction bloat, redundant calls), and estimates energy/water/CO2e impact with recommended fixes. Targeted awards: **Headless Hero** (observability), **Equality Group Champion** (sustainability), **Accessibility Excellence**.

This shortlist is deduped across seven research angles and ranked by *concrete* value to Ohm — how directly each item enables the auditor/discovery engine, the Agentforce agent, the LWC experience, the impact methodology, or a targeted award. The **Salesforce DX MCP Server** recurred across the most angles and sits at #1 because a single server covers retrieval, SOQL, Apex-test, and LWC scaffolding.

### Ranked

| # | Item | Kind | Why for Ohm (specific) | Confidence |
|---|------|------|------------------------|:---:|
| 1 | **Salesforce DX MCP Server** ([repo](https://github.com/salesforcecli/mcp)) | mcp-server | `retrieve_metadata` pulls GenAiPlannerBundle/GenAiPromptTemplate/AiAuthoringBundle/Flow; `run_soql_query` reaches telemetry; `run_apex_test` validates EstimateFootprint; lwc-experts scaffold + a11y-review the UI. Touches 4 of 5 pillars. | high |
| 2 | **GenAiPlannerBundle** ([docs](https://developer.salesforce.com/blogs/2026/05/new-agentforce-metadata-and-development-lifecycle)) | agentforce-feature | Ohm's primary analysis target: agentGraph + plannerActions + localActions = the action graph Ohm scores for LLM-where-deterministic and redundant-call waste. Use API v66.0+ (GenAiPlanner deprecated). | high |
| 3 | **GenAiPromptTemplate / …Actv** ([docs](https://developer.salesforce.com/docs/atlas.en-us.api_meta.meta/api_meta/meta_genaiprompttemplateactv.htm)) | agentforce-feature | Every unstructured-output action is a prompt template — one retrieve yields instruction text (bloat signal) + bound model config (right-sizing signal) across standalone templates and agent actions. | high |
| 4 | **forcedotcom/sf-skills** ([repo](https://github.com/forcedotcom/sf-skills)) | claude-skill | `observing-agentforce` is the official prior art for Ohm's discover-and-analyze core (Headless Hero); `agentforce-generate` documents the bundle shapes Ohm parses. The line community repos are consolidating into. | high |
| 5 | **Agentforce Observability** ([announce](https://www.salesforce.com/news/stories/agentforce-studio-observability-tools-announcement/)) | agentforce-feature | Session Tracing + Agent Analytics give the real run counts that turn static waste into grounded energy/water/CO2e; "ineffective topics/actions" maps onto Ohm's findings. | medium |
| 6 | **Google Gemini environmental-impact paper** ([PDF](https://services.google.com/fh/files/misc/measuring_the_environmental_impact_of_delivering_ai_at_google_scale.pdf)) | data-source | Best per-inference anchor: 0.24 Wh / 0.03 gCO2e / 0.26 mL per median prompt, with a full-stack boundary to cite. Pair with Epoch AI for a defensible range. | high |
| 7 | **AiAuthoringBundle + Agent Script** ([docs](https://developer.salesforce.com/docs/ai/agentforce/guide/agent-dx-nga-author-agent.html)) | agentforce-feature | Readable `.agent` text makes instruction-bloat and deterministic-vs-reasoning detection cheap; fixes can be expressed as concrete Agent Script edits. | high |
| 8 | **Agentforce DX CLI (plugin-agent)** ([repo](https://github.com/salesforcecli/plugin-agent)) | cli-tool | Scriptable full-inventory pull + the exact package.xml type list for discovery; `sf agent test` proves a recommended fix leaves the agent passing. | high |
| 9 | **Code Analyzer v5 (Flow Scanner)** ([docs](https://developer.salesforce.com/docs/platform/salesforce-code-analyzer/guide/engine-flow.html)) | cli-tool | Proven pattern for Ohm's per-artifact waste scan (flags prompt-invoking Flows) AND emits SARIF bulk-safety evidence for Ohm's own Apex. | high |
| 10 | **sa11y + sfdx-lwc-jest** ([repo](https://github.com/salesforce/sa11y)) | library | `toBeAccessible()` proves each app-page step + Calm Mode is WCAG 2.2 accessible in the LWC Jest harness — hard evidence for Accessibility Excellence. | high |

### Runners-up

- **Salesforce Development plugin for Claude Code** (Aug 2026) — ~40 skills + salesforce-lsp MCP + deploy hook; fastest path to clean deploys and 75%+ coverage on Ohm's Apex. Overlaps #1/#4.
- **Agentforce Vibes IDE (Claude Sonnet 4.5, free in Dev Edition)** — generates LWC + Apex + Jest against real org metadata; build-velocity accelerator.
- **How Hungry is AI? (arXiv 2505.09598)** — per-token energy/water/carbon methodology; backs model-right-sizing and instruction-bloat math.
- **Epoch AI — ChatGPT energy (~0.3 Wh GPT-4o)** — independent cross-validation of the Google anchor; supports a defensible range.
- **Agentforce Testing Center / sf agent test** — AI Evaluation metadata for Ohm's Responsible-AI rubric and before/after fix validation.
- **MetadataComponentDependency + dependencies-cli** — dependency graph powering the redundant-calls signal and discovery completeness.
- **Salesforce Hosted MCP Servers (GA Feb 2026)** — exposes Flows and Prompt Templates as MCP tools; a native discovery channel to watch.
- **SLDS 2 + SLDS Linter/Validator** — theme/dark-mode-ready accessible components + styling-compliance linting; complements sa11y.

### Install these first

For a working discovery + audit loop on day one:

```bash
# 1. Discovery + retrieval + Apex-test backbone (MCP client)
npx -y @salesforce/mcp --orgs <alias> --toolsets metadata,data,testing,lwc-experts

# 2. Official skills incl. observing-agentforce + agentforce-generate
npx skills forcedotcom/sf-skills

# 3. Agent inventory + package.xml types + agent re-validation
sf plugins install @salesforce/plugin-agent

# 4. Per-artifact waste scan + SARIF evidence for your own Apex
sf plugins install code-analyzer

# 5. Accessibility proof for the LWC experience
npm i -D @salesforce/sfdx-lwc-jest @sa11y/jest
```

Then retrieve the audit targets (API v66.0+): `sf project retrieve start -m GenAiPlannerBundle,GenAiPromptTemplate,AiAuthoringBundle,Flow` and hardcode the Google Gemini constants (0.24 Wh / 0.03 gCO2e / 0.26 mL) into your `EstimateFootprint` Apex, scaling by run counts pulled from the Agentforce Session Tracing data model.

*Confidence note:* everything above is grounded in 2025–2026 sources. The one **medium**-confidence item is Agentforce Observability — the feature is real and central, but its exact GA dates come from reputable secondary sources (SalesforceDevops, the SF newsroom); confirm against official Spring '26 release notes before the pitch.