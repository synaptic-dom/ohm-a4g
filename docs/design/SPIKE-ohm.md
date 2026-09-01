# SPIKE-ohm — Salesforce Capability Spike Report

**Project:** Ohm — agentic AI sustainability auditor (LWC app-page + Agentforce hybrid)
**Org alias:** `ohm` — EPIC OrgFarm (00Daj000013wTtpEAE)
**Date:** 2026-09-01
**Method:** 5 parallel CLI probes + synthesis + adversarial completeness critic (workflow `wf_9427f2a1-832`, 7 agents)
**Verdict:** **GO_WITH_RISKS** — build surface fully capable; Agentforce is *licensed but not yet enabled* (an admin task, not a blocker); org is empty (needs fixtures) and expires after the hackathon (not a submission risk).

---

## 1. Org profile

| Attribute | Value |
|---|---|
| Org name / ID | EPIC OrgFarm / 00Daj000013wTtpEAE |
| Edition | Enterprise Edition (`IsSandbox=false`) |
| Instance / API | USA838 (`orgfarm-08e0e83a93.my.salesforce.com`) / v67.0 |
| Trial expiration | **2026-10-07** (~36 days) |
| User / profile | epic.f1c1977a25ca@orgfarm.salesforce.com / **System Administrator** |
| Build perms | `AuthorApex=true`, `CustomizeApplication=true`, `ModifyAllData=true` |
| Daily API | 99,972 / 100,000 remaining |

**Trial-expiry note (corrected):** Oct 7 is *after* both the submission deadline (Sep 7) and the finalist showdown (Sep 16), so the expiry is **not a risk to the hackathon**. It only matters if Ohm is kept as a product past Oct 7 — a post-hackathon migration concern, not a build blocker.

---

## 2. Build surface — ✅ fully supported

All types needed for the LWC experience, data model, and Apex are present: `ApexClass`, `ApexTrigger`, `CustomObject`, `CustomTab`, `CustomApplication`, `FlexiPage`, `LightningComponentBundle`, `AuraDefinitionBundle`, `LightningTypeBundle`, `PlatformEventChannel`, `StaticResource`. (`CustomField` is managed via `CustomObject`; that's normal.)

**Conclusion:** LWC app-page experience, custom objects, Apex actions, FlexiPage host, and Custom Lightning Types can all be built. *(Deploy round-trip not yet proven — see §6.)*

---

## 3. Discovery surface — ⚠️ works, but org is empty

`sf org list metadata` succeeds for `GenAiPlannerBundle`, `GenAiPlugin`, `GenAiPromptTemplate`, `Flow` — but **all return 0 components**. `Bot` and legacy `GenAiPlanner` error `INVALID_TYPE` (Bot not provisioned; `GenAiPlanner` superseded by `GenAiPlannerBundle` in v67).

**Conclusion:** The enumeration path is structurally valid but only the empty-result path was exercised. **Fixtures must be seeded** to demo the auditor against non-empty data. The auditor must target `GenAiPlannerBundle` (not `GenAiPlanner`) and treat `Bot` `INVALID_TYPE` as "not provisioned," not a failure.

---

## 4. Agentforce enablement — licensed, NOT yet switched on

Runtime sObject probes:

| Core object | Queryable | Records | Meaning |
|---|:---:|:---:|---|
| BotDefinition | ❌ | — | "sObject not supported" → bot/agent layer not turned on |
| GenAiPromptTemplate | ❌ | — | "sObject not supported" → Prompt Builder not turned on |
| GenAiPlannerDefinition | ✅ | 0 | Object recognized & queryable; zero planners exist |

**But entitlement is present.** `PermissionSetLicense` lists all the Agentforce/Einstein licenses already provisioned in the org, including:

- **Agentforce (Default)** — `EinsteinGPTCopilotPsl`
- **Agentforce Platform Developer and Admin** — `AgentforcePlatformDeveloperAndAdminPsl`
- **Einstein Prompt Templates** — `EinsteinGPTPromptTemplatesPsl`
- **Data Cloud**, **Einstein AI Skills / Manager**, **Unmetered Platform Developer and Admin AI User**, and ~50 more.

**Conclusion (revised from the synthesis's "blocked"):** Agentforce is **enable-able on this org** — the licenses exist; the Einstein/Agentforce features simply need to be **turned on in Setup** and the permission-set licenses **assigned to the user**. This is an admin enablement task with no procurement lead time. F6 (the hybrid Agentforce agent) is therefore **not blocked — it is gated on a Setup toggle we control.**

### 4.1 Enablement performed — 2026-09-01 (RESOLVED)

Executed programmatically (Playwright for the click-through terms gate + Metadata API for the rest):

| Action | Method | Result |
|---|---|---|
| Einstein Bots on + "Try Einstein" legal terms accepted | Playwright (browser drove Setup → Einstein Bots toggle + authorization checkbox) | ✅ enabled, persisted across reload |
| `EinsteinCopilot.enableEinsteinGptCopilot = true` | Metadata deploy | ✅ changed=true |
| `AgentPlatform.enableAgentPlatform = true` | Metadata deploy | ✅ changed=true |
| `Bot.enableBots = true` | Metadata deploy (post-terms) | ✅ no-op (already on via UI) |
| Assign PSLs (Agentforce Default, Prompt Templates, Platform Dev/Admin, Unmetered AI) | Anonymous Apex | ✅ 4/4 assigned to user |
| `EinsteinGpt.enableEinsteinGptPlatform` | (was already true) | ✅ |

**Post-enablement probe:**
- `Bot` metadata type: `INVALID_TYPE` → **now listable** (0 components). `GenAiPlannerBundle` / `GenAiPromptTemplate` / `GenAiPlugin` metadata all listable (0 components — org still empty).
- **Discovery surface CONFIRMED (Tooling API):** `GenAiPlannerDefinition` (agents), `GenAiPluginDefinition` (topics), and `GenAiFunctionDefinition` (actions) are all queryable (0 records — org empty). This is exactly the SOQL/Tooling-API discovery mechanism the critic recommended for an in-org Apex app. ✅
- **Discovery surface (Metadata API):** `Bot`, `GenAiPlannerBundle`, `GenAiPromptTemplate`, `GenAiPlugin` all listable (0 components). ✅
- Legacy `BotDefinition` and the `GenAiPromptTemplate` *sObject* still report "not supported" post-enablement — **not on the critical path**: Agentforce agents are the `GenAiPlanner*` objects (live), and prompt templates are discoverable via Metadata API. Re-verify only if a Tooling-API prompt-template read is later required.

**Net:** Agentforce enablement is DONE and the discovery surface is proven. Remaining: (a) seed fixture agentic assets so the auditor has non-empty data to demo (org is empty), (b) proceed to Design grounded in the confirmed Tooling-API + Metadata-API discovery surfaces.

---

## 5. Feature readiness

| Feature | Status | Note |
|---|:---:|---|
| F1 Welcome LWC experience | ✅ ready | LWC + FlexiPage supported; CustomizeApplication=true |
| F2 Discovery of agentic work | ⚠️ ready-with-fixtures | Enumeration works; org empty → seed fixtures |
| F3 Per-system analysis + 4 signals | ⚠️ ready-with-fixtures | Apex buildable; needs assets to analyze; read/parse path unproven (§6) |
| F4 Impact readout (energy/water/CO₂e) | ✅ ready | Pure Apex/LWC compute |
| F5 Recommendations + savings | ✅ ready | Deterministic logic buildable; LLM variant rides on F6 |
| F6 Agentforce agent (hybrid) | 🟡 gated-on-enablement | Licensed; needs Setup enable + PSL assignment |
| F7 Persist Agent_Audit_Report__c | ✅ ready | CustomObject supported; ModifyAllData=true |
| F8 Remediation task creation | ✅ ready* | *Task object write not yet probed (§6) |
| F9 Calm Mode preference | ✅ ready | Custom field/setting + LWC |
| F10 Methodology defense | ✅ ready | LWC + StaticResource |
| F11 LWC visual polish | ✅ ready | LWC + StaticResource; ample headroom |

---

## 6. Open verifications (from the adversarial critic — do in Design, confidence: medium)

The "ready" statuses rest on metadata-type listing + permission flags. These were **not** yet proven and should be closed early in Design:

1. **Apex deploy round-trip** under this org's semantics — deploy a trivial ApexClass + test; confirm any coverage/test-level gate is satisfiable (`sf project deploy start --dry-run --test-level RunLocalTests`).
2. **Custom-object persistence** end-to-end — deploy a throwaway object, insert + query a record.
3. **F6 fallback callout** — if native Agentforce ever fails, confirm outbound HTTP callout works (Remote Site / Named Credential + anonymous Apex `Http`). *(Fallback only; native Agentforce is the intended path.)*
4. **Can GenAi fixture types be DEPLOYED** (not just listed) — attempt to deploy a minimal `GenAiPromptTemplate` / `GenAiPlannerBundle` **after** enabling Agentforce. If they fail pre-enablement, F2/F3 fixtures depend on the F6 enablement step.
5. **Auditor read path** — retrieve a `Flow` / `GenAiPlannerBundle` source XML and confirm we can parse it to compute the four signals. *This is the core product capability and no probe touched it.*
6. **Storage remaining** (not just max) for F7/F10/F11.
7. **Task/Activities** object enabled & writable for F8.
8. **LWC render + app-page activation** (and `LightningTypeBundle` rendering) actually work in-org.
9. **Metadata-API vs sObject** authority for discovery — reconcile which surface the auditor uses (`GenAiPromptTemplate` lists as metadata but isn't a queryable sObject pre-enablement).

---

## 7. Recommendations / next actions (Design phase)

1. **Enable Agentforce in Setup** (the gating action): turn on Einstein Generative AI + Agentforce, assign the Agentforce / Prompt-Template permission-set licenses to the user, then **re-run the enablement probe** to confirm `BotDefinition` / `GenAiPromptTemplate` become queryable.
2. **Seed discovery fixtures** post-enablement: at least one agent (`GenAiPlannerBundle` + `GenAiPlugin`), one `GenAiPromptTemplate`, and one prompt-invoking `Flow` — so F2/F3 demo a non-empty audit. (These double as the "systems to make leaner" in the demo.)
3. **Close the §6 open verifications** with a short deploy/round-trip smoke test before committing the architecture.
4. **Target correct types & API surface**: `GenAiPlannerBundle` not `GenAiPlanner`; handle `Bot` `INVALID_TYPE` gracefully; manage `CustomField` via `CustomObject`.
5. **Operational**: run all `sf` commands via the **PowerShell tool** (the Bash tool can't invoke the CLI through a pipe due to the space in its install path). Treat `sf org display [user]` output as sensitive — it prints live access tokens.
6. **Post-hackathon only**: plan a source export/migration off this trial before 2026-10-07 if Ohm is kept beyond the showdown.

---

*Every capability above is asserted only to the extent the probes evidenced it. Items in §6 are explicitly unproven and flagged as such.*
