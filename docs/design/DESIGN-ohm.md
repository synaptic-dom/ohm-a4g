# DESIGN-ohm.md — Ohm: Agentic AI Sustainability Auditor for Salesforce

**Version:** 1.0 (synthesized) · **Date:** 2026-09-01 · **Author:** Design synthesis pass · **Deadline:** Sep 7 2026 (solo)

> This document reconciles five area designs against the critic pass. Every cross-section inconsistency called out by the critic is resolved here with a single canonical choice, and the achievable-by-Sep-7 scope is fixed by an explicit cut order. **Confirmed** = validated in the 2026-09-01 spike. **[UNCONFIRMED]** = must be proven against a seeded fixture before the dependent feature is trusted.

---

## 1. Overview & Approach

Ohm is an agentic AI sustainability auditor for Salesforce. It is a guided Lightning Web Component (LWC) app-page experience — **Welcome → Discover & Analyze → Impact Readout → Recommendations** — with a real Agentforce agent (`Ohm_Auditor`) underneath doing the discover/analyze/recommend *narration and reasoning*. It discovers every agentic asset in the org, scores each on four waste signals, estimates its energy/water/CO₂e footprint as an uncertainty range, and recommends efficiency fixes with projected savings.

**The one load-bearing principle** (product thesis and NFR-4 in one): *Apex computes; the agent reasons and narrates.* Spending an LLM on deterministic work is literally signal (a), the first thing Ohm flags. So the inventory walk, the four signals, and the footprint arithmetic run in deterministic Apex — never delegated to the model. The LLM earns its tokens only where language synthesis genuinely helps: narrating discovery, phrasing/prioritizing recommendations, and defending methodology. Ohm's own agent, inspected by Ohm, scores clean on all four signals. That dogfooding *is* the demo.

**Award alignment:** Headless Hero (agent observability via a visible progress log + agent narration), Equality Group Champion (sustainability framing), Accessibility Excellence (Calm Mode).

**Org reality driving every choice:** Enterprise orgfarm, API v67.0, System Admin, Agentforce enabled, build surface confirmed (ApexClass, ApexTrigger, CustomObject, LWC, FlexiPage, LightningTypeBundle, StaticResource, PlatformEventChannel). The org is **empty** (0 agents/topics/actions/templates/flows), so **fixtures must be seeded** and every detector is otherwise validated only on its empty-result branch.

**Protected demo spine:** Welcome + Impact Readout + Recommendations + the agent. Everything else degrades gracefully to protect it.

---

## 2. Architecture

### 2.1 Layered component map

```
EXPERIENCE (LWC on a two-region FlexiPage app page)
  Region A (main): c-ohm-audit-experience (root FSM: Welcome→Discover→Impact→Recommendations)
  Region B (side): embedded Agentforce conversational panel  ← Path B live surface
        │ @AuraEnabled Apex (deterministic spine)     │ agent turns invoke same actions
────────┼──────────────────────────────────────────────┼──────────────────────────────
ACTION LAYER (thin: @InvocableMethod for agent + @AuraEnabled for LWC)
   DiscoverAgenticWork · RunSignals · EstimateFootprint ·
   RecommendImprovements · PersistAuditReport · CreateRemediationTask
────────────────────────────────────────────────────────────────────────
SERVICE LAYER (pure logic, no annotations, unit-testable)
   OhmDiscoveryService · OhmSignalService · OhmFootprintService ·
   OhmRecommendationService · OhmPersistenceService · OhmToolingClient
────────────────────────────────────────────────────────────────────────
ORCHESTRATION  OhmAuditController.startAudit() → sync pipeline (fixture scale)
               [future: OhmAuditQueueable chain for large orgs]
CONFIG         StaticResource Ohm_Constants (JSON) — footprint constants, model
               multipliers, thresholds   (NOT CMDT — see §2.4)
DATA           Agent_Audit_Report__c ── (master-detail) ── Finding__c
AGENT (metadata)  GenAiPlannerBundle Ohm_Auditor → GenAiPlugin topics →
                  GenAiFunction actions (all InvocationTargetType=apex)
```

### 2.2 One service, two doors (the hybrid rule)

Every unit of work exists exactly once as a **service-layer method** and is exposed through two thin doors: an `@AuraEnabled` door for the LWC and an `@InvocableMethod` door for the agent. Both call the identical service method, so **Path A (deterministic guided spine) and Path B (agent) can never compute different results.** Action-layer classes only marshal DTOs; all logic is in services, unit-testable without an agent runtime.

**Deterministic vs LLM split (the agent never computes a number):**

| Work unit | Where | LLM? |
|---|---|---|
| Tooling walk of `GenAi*Definition`; parse `AgentGraph` JSON | `OhmDiscoveryService` | No |
| Signals (a) LLM-where-deterministic, (b) right-sizing, (c) instruction bloat, (d) redundant calls | `OhmSignalService` | No |
| Footprint = per-inference constant × volume × band | `OhmFootprintService` | No |
| Deterministic fix candidates (signal → fix template + savings math) | `OhmRecommendationService` | No |
| **Narrate discovery** ("found 3 agents, 11 topics…") | agent topic `Ohm_Audit_Orchestration` | Yes |
| **Phrase & prioritize recommendations** from candidates | agent topic `Ohm_Recommendations` | Yes |
| **Methodology defense** ("how did you estimate this?") | agent topic `Ohm_Methodology` | Yes |

`RecommendImprovements` is the single deliberately-hybrid seam: Apex emits structured candidates (fix type, target, savings band); the agent phrases and orders them. **This phrased output is persisted back** so the LWC spine can render it (see §4 and the resolved agent-to-LWC bridge).

### 2.3 Async orchestration — sync-first (cut order applied)

The seeded fixture org is tiny, so **`startAudit()` runs the whole pipeline synchronously inside one `@AuraEnabled(callout=true)` call** (Discover → Signals → Footprint → Recommend → Persist), well within a 3-minute demo window. The chained-Queueable + chunk-by-agent design (Database.AllowsCallouts, 60s CPU / 12MB heap headroom, callouts-before-DML) is **documented future work** for large orgs and is *not* built for the hackathon. Progress is surfaced by **polling** (§6), not platform events (§2.5).

### 2.4 Config storage — StaticResource JSON, not CMDT

Confirmed build surface lists `StaticResource` but **not** Custom Metadata Types. Therefore all tunable constants — footprint constants (energy/water/CO₂e bands), model rate-card multipliers, and signal thresholds — live in a single StaticResource **`Ohm_Constants`** (JSON), loaded once per run with hardcoded, source-cited Apex `static final` defaults as the fallback. This makes the methodology inspectable/tunable without a redeploy and stays inside confirmed surfaces. *(Resolves the S2/S3/S4 CMDT-vs-StaticResource contradiction: `Ohm_Threshold__mdt`, `Ohm_Footprint_Constant__mdt`, `Ohm_Model_Rate__mdt` are all dropped in favor of `Ohm_Constants`.)*

### 2.5 Progress transport — polling primary, platform event optional

*(Resolves the S1-polling vs S4/S5-platform-event conflict and the `Session_Id__c` vs `RunId__c` field mismatch.)* The spine uses **polling**: the LWC calls `startAudit()` → gets a report Id, then polls `getAuditStatus(reportId)` on an interval, rendering a determinate progress bar + a text log from the report's status/stage fields. The Headless-Hero observability moment is carried by that log **plus** the agent's own live narration in the side panel — no custom PlatformEventChannel is required for the spine. A `Ohm_Audit_Progress__e` platform-event stream (with `Report_Id__c` as the single correlation key) remains an *optional enhancement* if time permits; the LWC is coded to accept either source behind one `handleProgress()` method. **Recommendation: ship polling; treat platform events as a stretch.**

---

## 3. Discovery Engine

### 3.1 Read path — Tooling REST via self-callout (Named Credential `Ohm_Self`)

The `GenAi*Definition` objects live only in the **Tooling API**, not the Apex sObject layer, so they are read via Tooling REST `query`, not inline SOQL. **[UNCONFIRMED — prove first, Task 0]** Apex issues an HTTP callout through a self-referential Named Credential **`Ohm_Self`** (unified name; External Credential + Named Credential, client-credentials OAuth to a same-org Connected App, `api` scope, My Domain URL):

```apex
req.setEndpoint('callout:Ohm_Self/services/data/v67.0/tooling/query/?q=' +
    EncodingUtil.urlEncode(soql, 'UTF-8'));
```

`UserInfo.getSessionId()` is rejected (unusable for API callouts from Lightning/async). Pagination loops `nextRecordsUrl` until absent. Callouts-before-DML is enforced. If inline Apex SOQL against these Tooling objects turns out to be supported, `OhmToolingClient` collapses to plain SOQL with no caller change.

### 3.2 Queries (confirmed real fields)

**Q1 — Agents (`GenAiPlannerDefinition`):** `Id, DeveloperName, MasterLabel, Description, PlannerType, Capabilities, AgentGraph, FullName`. `AgentGraph` (JSON textarea) is the authoritative wiring and the evidence source for signal (d).

**Q2 — Topics (`GenAiPluginDefinition`):** `Id, DeveloperName, MasterLabel, Description, PluginType, Scope, IsLocal, ParentId, CanEscalate, Source, PlannerId, LocalDeveloperName`. `Scope` (textarea) = topic instructions, the char source for signal (c). `PlannerId` joins topic→agent.

**Q3 — Actions (`GenAiFunctionDefinition`):** `Id, DeveloperName, MasterLabel, Description, InvocationTargetType, InvocationTarget, IsConfirmationRequired, IsLocal, ParentId, Source, PluginId, PlannerId, LocalDeveloperName`. `InvocationTargetType` (picklist flow/apex/prompt/…) drives signal (a). `PluginId` joins action→topic, `PlannerId`→agent.

**In-memory tree build (`OhmGraph`):** `agentsById` (Q1) → `topicsByPlanner` (Q2) → `actionsByPlugin` + `actionsByPlanner` (Q3), then walk each agent's `AgentGraph` to mark reachability and per-turn call order. `IsLocal`/`ParentId`/`Source` de-duplicate local clones for org counts while keeping per-agent instances for findings.

### 3.3 Model-binding second pass (resolves the S1/S2 circularity)

Signal (b) needs each prompt-typed action's bound model **before** it can flag. So the `Metadata` complexvalue is fetched **per-record for *all* prompt-typed actions** (a bounded set) during discovery via `GET /tooling/sobjects/GenAiFunctionDefinition/{Id}` — *not* gated on a signal-(b) flag. This closes the "flag triggers the fetch that the flag depends on" loop. Complexvalue fields are excluded from bulk queries (heap + reliability). **[UNCONFIRMED]** whether the model actually lives in this complexvalue vs the linked prompt template; see §5 signal (b) degrade path.

### 3.4 Cut surfaces (per cut order)

- **Prompt-invoking Flow detection — CUT for demo.** Audits `InvocationTargetType='prompt'` directly. Flow-hosted prompt steps and the unverified `generatePromptResponse` `actionType` are documented as future work. *(Resolves the S1-claims/S2-omits inconsistency by removing the feature.)*
- **Prompt-template Metadata SOAP read — DEGRADED.** No hand-rolled `listMetadata`/`readMetadata` SOAP client. Signal (b)'s model is read from the **seeded fixture's known configuration** (we control the fixtures); where genuinely unknown, emit an informational "model unknown" note with no savings figure rather than a false negative.
- **Runtime usage telemetry spike — CUT.** The org is empty, so telemetry is empty regardless; volume is modeled (§5.5, §6).

---

## 4. Data Model

*(Resolves the three-name findings object, the Recommendation-object contradiction, and the agent-to-LWC bridge gap.)*

**Two objects, one master-detail link.** `Recommendation__c` is collapsed into fields on `Finding__c` (per cut order — simpler to build/validate, and it solves the two-level-rollup problem natively). The agent's phrased output persists onto the finding, so it reaches the LWC spine.

### `Agent_Audit_Report__c` — one per run (F7)
- `Name` Auto Number `AUDIT-{00000}`
- `Run_Timestamp__c` (DateTime), `Run_Status__c` (Picklist: Queued/Discovering/Analyzing/Complete/Failed), `Run_Stage_Message__c` (Text — drives the polled progress log), `Percent_Complete__c` (Number), `Org_Id__c` (Text 18)
- Inventory: `Agents_Discovered__c`, `Topics_Discovered__c`, `Actions_Discovered__c`, `Prompt_Templates_Discovered__c` (Number)
- Rollups from `Finding__c` (master-detail SUM/COUNT): `Findings_Count__c`, `Total_Annual_Energy_Wh__c`, `Total_Annual_Water_mL__c`, `Total_Annual_CO2e_g__c`, `Total_Annual_Energy_Savings_Wh__c`
- `Efficiency_Grade__c` (Text, letter), `Efficiency_Score__c` (Number 0–100), `Methodology_Version__c` (Text), `Discovery_Errors__c` (Long Text — partial-failure log)

### `Finding__c` — one per waste-signal instance per artifact; Master-Detail → `Agent_Audit_Report__c`
- `Name` Auto Number `FIND-{00000}`
- **Signal:** `Signal_Type__c` (Picklist — **canonical values:** `LLM_WHERE_DETERMINISTIC`, `MODEL_RIGHTSIZING`, `INSTRUCTION_BLOAT`, `REDUNDANT_CALLS`), `Severity__c` (High/Medium/Low), `Confidence__c` (High/Medium/Low)
- **Artifact:** `Artifact_Type__c` (Agent/Topic/Action/PromptTemplate), `Artifact_Api_Name__c`, `Artifact_Label__c`, `Artifact_Tooling_Id__c` (Text 18), `Parent_Agent_Api_Name__c`, `Parent_Topic_Api_Name__c`
- **Evidence/metric:** `Evidence__c` (Long Text), `Metric_Value__c` (Number), `Metric_Unit__c` (Text: tokens/calls-per-turn/model-multiplier)
- **Impact (low/central/high):** `Annual_Energy_Wh_Central__c` (+`_Low`/`_High`), `Annual_Water_mL_Central__c`, `Annual_CO2e_g_Central__c`, `Estimated_Annual_Calls__c`, `Per_Inference_Wh__c`, `Annual_Energy_Savings_Wh__c` (+band)
- **Recommendation (formerly Recommendation__c):** `Fix_Type__c` (Replace_With_Flow/Replace_With_Apex/Downsize_Model/Trim_Instructions/Consolidate_Calls), `Recommended_Target__c` (Text), `Recommendation_Text__c` (Long Text — deterministic candidate), **`Agent_Narrative__c`** (Long Text — the agent's phrased/prioritized version; the hybrid seam made visible), `Generated_By__c` (Deterministic/Agentforce), `Effort__c` (Low/Medium/High), `Rec_Status__c` (Proposed/Accepted/Dismissed/Applied), `Remediation_Task_Id__c` (Text 18)

**Agent-to-LWC bridge:** `PersistAuditReport` writes deterministic candidates to `Recommendation_Text__c`; when the agent phrases them it writes `Agent_Narrative__c` + sets `Generated_By__c=Agentforce`. The LWC reads whichever is present (narrative preferred), so the agent's contribution is visible on the protected spine even though the spine itself is deterministic.

**Signal picklist canonicalization** (mustFix): all detectors, DTOs, and LWC use the single UPPER set above. No `Model_Right_Sizing`/`Redundant_Call_Pattern` variants anywhere.

---

## 5. Four-Signal Analysis Engine (F3)

Consumes `OhmGraph`; runs four independent detectors implementing `SignalDetector { List<Finding> detect(AgentModel) }`, orchestrated by `OhmSignalService`. Shared services: `TokenEstimator.approxTokens = ceil(chars/4)` (Apex has no tiktoken; uniform so relative comparisons hold), `ModelRegistry` (model→{tier SMALL/MEDIUM/LARGE, rateCardMultiplier} from `Ohm_Constants`), and `OhmFootprintService` (the one estimation engine — §6.5).

### Signal (a) LLM-where-deterministic — **CONFIRMED fields, protected**
Gate on `InvocationTargetType == 'prompt'`; classify intent from `MasterLabel + DeveloperName + Description` against a deterministic-task lexicon (classify, categorize, route, lookup, format, validate, extract, parse, calculate, boolean/yes-no…). Fire when target is `prompt` AND ≥1 lexicon hit. `severity = min(1, 0.4 + 0.15 × hitCount)`. flow/apex actions are the never-flagged "good" contrast class. Candidate/review-grade (inferred from NL metadata) — never auto-remediated. **Savings** = full per-inference footprint × volume (the LLM call is removed).

### Signal (c) Instruction bloat — **CONFIRMED fields, protected**
Measure `GenAiPluginDefinition.Scope` (primary), agent `Description`+`Capabilities`, action `Description`. `tokens = ceil(chars/4)`. Thresholds from `Ohm_Constants` (Topic Scope soft 500 / hard 1000 tok; Agent 400/800; Action 150/300). Fire when `tokens > soft`; `severity = min(1, excess/soft)`. **Savings (recurring, per-turn):** excess instruction tokens re-sent every turn → `excessPromptsEq × turnsPerConversation × conversations`. This is the one signal whose cost compounds with turn count (surfaced in methodology).

### Signal (b) Model right-sizing — **best-effort (degrades)**
`ModelBindingResolver.resolve(action)` reads the model from (1) the fixture's known prompt-template config, else (2) the per-record `Metadata` complexvalue fetched in §3.3, else emit "model unknown" (no savings, informational). `overshoot = modelTier.rank − taskComplexity.rank` (triviality lexicon); fire when `overshoot ≥ 1`, `severity = overshoot/2`. **Savings** = perInference × `(1 − multiplier(recommended)/multiplier(bound))` using Einstein Requests Rate-Card multipliers as the on-platform energy proxy.

### Signal (d) Redundant call patterns — **best-effort (degrades)**
Parse `GenAiPlannerDefinition.AgentGraph` with a **tolerant `JSON.deserializeUntyped` walker** validated against a seeded fixture ([UNCONFIRMED] schema; closable because we own the fixtures). Cross-reference nodes to `InvocationTargetType` to tag LLM (`prompt`) vs deterministic nodes. Heuristics: fan-out (`extraCalls = max(0, promptNodeCount − 1)`), sequential prompt chain ≥3, prompt-bearing cycle (DFS back-edge), duplicate target. Fire on `extraCalls ≥ 1` OR prompt cycle. **Savings** = perInference × extraCalls × turns × conversations; cycles reported per-iteration with an explicit "×N" caveat.

**Time-box protection:** signals (a)+(c) rest on **confirmed** fields (InvocationTargetType picklist, Scope length) and are demo-safe; (b)+(d) rest on unconfirmed surfaces (model binding, AgentGraph schema) and may degrade to best-effort. The Impact readout and Recommendations spine still stand on two solid signals.

**Org-wide efficiency rating** (feeds F4): `efficiency = 1 − (Σ weighted severity / maxPossible)`, weights in `Ohm_Constants`; deterministic actions and within-budget instructions count as positive evidence, so a lean org scores high. Mapped to a letter grade + 0–100 score on the report.

---

## 6. Impact Estimation Methodology (`OhmFootprintService` / `EstimateFootprint`)

Activity-data × emission-factor model (the GHG-Protocol / Net-Zero-Cloud shape). **Every figure is a low/central/high band** — the band is Ohm's honesty mechanism and its methodology defense (F10). `footprint = per_inference_impact × call_volume`.

### 6.1 One canonical contract (mustFix — resolves three signatures)
There is exactly one engine. `OhmFootprintService.estimate(FootprintRequest) : FootprintResponse` (per-artifact, typed, low/central/high), exposed through **one** `@InvocableMethod` door `EstimateFootprint.estimate(List<Request>) : List<Response>` and one `@AuraEnabled` door. Org-wide totals are the service **summing** per-artifact responses — *not* a separate signature. Savings for each signal = re-running `estimate` with the fixed parameter (removed call for a, cheaper multiplier for b, reduced tokens for c, reduced callsPerTurn for d). The S2 `perInference(...)` becomes a private helper. **Uncertainty vocabulary is unified to low/central/high everywhere** (no "mid"/"point"); DTO fields are `energyWh{Low,Central,High}`, `co2eG{...}`, `waterMl{...}`.

### 6.2 Per-inference constants (bands, cited in `Ohm_Constants`)
| Quantity | Low | Central | High | Basis |
|---|---|---|---|---|
| Energy per median prompt (Wh) | 0.24 | 0.27 | 0.30 | Gemini 2025 median (0.24) → Epoch AI GPT-4o (~0.30) |
| Grid intensity (gCO₂e/Wh) | 0.125 | 0.30 | 0.475 | Google clean-energy implied → global-average grid |
| Water (mL/Wh) | 0.8 | 1.08 | 1.4 | Gemini 0.26 mL @ 0.24 Wh ±30% |

CO₂e band is deliberately wide (grid intensity is the dominant uncertainty) and is surfaced explicitly, not hidden.

### 6.3 Token-based sizing
`tokens ≈ ceil(chars/4)` (sensitivity chars/3.5–4.5 feeds the band). Input tokens per turn = agent system text + active topic Scope + in-context action descriptions + history + user msg; instructions reprocess every turn (why signals c/d compound). `REFERENCE_PROMPT_TOKENS`, `TYPICAL_OUTPUT_TOKENS`, `OUTPUT_WEIGHT` are **stated assumptions** in `Ohm_Constants`, disclosed in the `assumptions` output.

### 6.4 Call volume — the runtime-volume solution
Impact = per-inference × **volume**, and volume dominates. Resolution order:
1. **Runtime telemetry — [UNCONFIRMED + empty in demo org].** Do **not** spike it (cut order). The AI-Agent Generative-AI Usage Data Model / Session Tracing objects are unconfirmed as queryable and the org has 0 sessions regardless.
2. **Modeled volume (primary demo path):** `sessions_per_period × turns_per_session × calls_per_turn` (calls_per_turn from `AgentGraph`, signal d). Explicit, editable assumption; `telemetryBacked=false`, `Confidence=Low`.
3. **What-if projection (demo strength):** the Impact readout defaults to a labeled scenario (e.g. "50 sessions/day × 6 turns") and lets the presenter **scrub volume live** to show how footprint and savings scale — turning the telemetry gap into an interactive strength. A `VolumeProvider` abstraction keeps a future `TelemetryVolumeProvider` swap-in with no caller change.

### 6.5 Per-model differentiation
`energy_per_call × RATE_CARD_MULTIPLIER(model)` normalized to a 1.0 baseline (Einstein Requests Rate Card as on-platform energy proxy). [UNCONFIRMED] exact multipliers + per-artifact binding; unknown model ⇒ baseline + `modelAssumed=true`.

### 6.6 Uncertainty & framing
Band = favorable extremes (low) / adverse extremes (high) / midpoints (central), a deliberately conservative bounding interval; the `assumptions` JSON returns every constant used (reproducible, F10). Optional tornado ranking shows which input drives the band. **Net Zero Cloud is narrative framing only** — output presented in NZC-compatible Scope-3 terms, no live NZC object read/write (not on confirmed surface).

---

## 7. LWC Experience (S1–S4, Calm Mode, a11y)

### 7.1 Host & tree
Two-region `Ohm_Audit` AppPage FlexiPage: **Region A** = root `c-ohm-audit-experience` (owns the FSM, Calm Mode context, all Apex I/O); **Region B** = the embedded Agentforce conversational panel (Path B). *(Resolves the S4/S5 single-region conflict — the agent now has a live surface.)*

```
c-ohm-audit-experience  (FSM: WELCOME→DISCOVERING→ANALYZING→IMPACT→RECOMMENDATIONS, +ERROR)
├─ c-ohm-calm-mode-toggle
├─ c-ohm-welcome                 (S1)
├─ c-ohm-discover-analyze        (S2, polled progress log — aria-live)
├─ c-ohm-impact-readout          (S3: efficiency-rating + impact-receipt + methodology-panel)
└─ c-ohm-recommendations         (S4: recommendation-card per finding)
```
Single root FSM, one screen mounted at a time (`lwc:if`) so focus/aria-live are unambiguous; parent-held state, `@api` down, `CustomEvent` up (no LMS/Redux). On every screen change, focus moves to the new screen heading.

### 7.2 Controller contract (unified — mustFix)
`reportId` **is** the `runId` (single identifier). `OhmAuditController`:
```apex
@AuraEnabled public static Id startAudit();                         // returns Agent_Audit_Report__c Id
@AuraEnabled(cacheable=false) public static AuditReadoutDTO getAuditStatus(Id reportId); // status + (when Complete) full readout
@AuraEnabled(cacheable=true)  public static Boolean getCalmModePreference();
@AuraEnabled public static void setCalmModePreference(Boolean enabled);
@AuraEnabled public static Id createRemediationTask(RemediationInputDTO input);
```
`getAuditStatus` is polled during the run and returns the full `AuditReadoutDTO` on completion (merges the old `getLatestAudit`). DTOs carry `energyWh{Low,Central,High}` etc.; `FindingDTO.signal` uses the canonical picklist values; each `FindingDTO` carries `recommendationText`, `agentNarrative`, `estimatedSavings` (band), `targetArtifact`.

### 7.3 Screens
- **S1 Welcome:** framing + one "Start the audit" CTA → `startAudit()`.
- **S2 Discover & Analyze:** polls `getAuditStatus`; renders a determinate bar + an `aria-live="polite"` progress log from `Run_Stage_Message__c`. Doubles as the Headless-Hero observability surface (with the agent panel narrating alongside). On `Run_Status=Complete` → IMPACT.
- **S3 Impact Readout:** `c-ohm-efficiency-rating` (letter grade + word label + text badge — color is redundant reinforcement only), `c-ohm-impact-receipt` (text-first `<dl>` per Energy/Water/CO₂e with point + "range low–high" + decorative `c-ohm-uncertainty-bar` [`role=img`, `aria-label` repeats the numbers]), org-wide + per-artifact rows, plus the "How is this estimated?" `c-ohm-methodology-panel` (F10). Live volume scrubber (§6.4).
- **S4 Recommendations:** `c-ohm-recommendation-card` per finding — the change, savings delta (band), severity as **text**, "Create remediation task" → `createRemediationTask` (F8). Renders `agentNarrative` when present, else `recommendationText`.

### 7.4 Calm Mode (F9)
One `@api calm-mode` Boolean passed to every child, branching templates via `lwc:if`. Persisted in hierarchy Custom Setting `Ohm_Preferences__c.Calm_Mode__c`; **[UNCONFIRMED]** custom-setting deploy — **fallback** to a `Calm_Mode__c` field on `User`, UI-contract-identical. Calm variant: drops uncertainty bars/animations/sparklines, single column, larger line-height, discrete aria-live text only, metrics as plain `<dl>`. Semantics (heading hierarchy, definition lists, landmarks) exist in both modes; Calm strips decoration, not structure. Loaded at root `connectedCallback` before first render.

### 7.5 Accessibility test strategy
`sfdx-lwc-jest` + `@sa11y/jest` `toBeAccessible()` (axe) on **every component in both Calm and non-Calm variants**. Targeted assertions axe can't catch: color-text pairing on efficiency-rating and uncertainty-bar; `aria-live` on the progress log; focus-lands-on-heading on FSM transition; single `<h1>`/no skipped levels. Non-a11y Jest: FSM transitions, DTO binding (low/central/high renders), Calm persistence path; Apex + empApi mocked.

---

## 8. Ohm's Own Agentforce Agent (`Ohm_Auditor`)

Deployed as **`GenAiPlannerBundle`** (v67, not legacy `GenAiPlanner`) with `GenAiPlugin` topics and `GenAiFunction` actions where **every action is `apex`-backed** (`InvocationTargetType=apex` → an `@InvocableMethod`), so Ohm's own agent scores clean on signal (a). Router kept on a small model (signal b); large-model synthesis reserved for recommendation/methodology turns. Topic Scopes kept lean (signal c).

| Topic (GenAiPlugin) | Scope | Actions |
|---|---|---|
| `Ohm_Audit_Orchestration` | Run & narrate the audit; report counts/progress in plain language | DiscoverAgenticWork, RunSignals, EstimateFootprint |
| `Ohm_Recommendations` | Turn deterministic fix candidates into prioritized guidance; persist phrased narrative | RecommendImprovements, PersistAuditReport |
| `Ohm_Remediation` | Create a remediation task from a chosen recommendation | CreateRemediationTask |
| `Ohm_Methodology` | Answer "how did you estimate this?" from constants held in Scope (F10) | (none) |

Rich structures cross the invocable boundary as JSON strings (Agentforce marshals flat/primitive variables most reliably). **[UNCONFIRMED]** apex-action binding, GenAiPlannerBundle deploy, and embedded-panel rendering must be exercised in-org; if the embedded panel fails live, a scripted agent conversation is the fallback and the deterministic Path A carries the spine.

---

## 9. Build Sequence (tied to the cut order)

**Task 0 — Prove the core read path FIRST (blocking).** Provision + consent a same-org client-credentials Connected App; create External + Named Credential `Ohm_Self`; prove an Apex Tooling REST callout returns rows synchronously. *No auth path ⇒ no product.* This is the single highest-risk dependency.

**Task 1 — Smoke deploy** one LWC on the FlexiPage AppPage (prove the deploy round-trip).

**Task 2 — Author fixtures** (unowned gap — now owned here): one agent + topic + action carrying **all four** waste signals — (a) a prompt action over a deterministically-named task, (b) a large model on a trivial task, (c) an oversized topic Scope, (d) an AgentGraph with a multi-call-per-turn topology — plus 1 prompt template. (Flow fixture deferred with Flow detection.) Validates the AgentGraph parser and every detector.

**Task 3 — Data model:** `Agent_Audit_Report__c` + `Finding__c` (with recommendation fields), rollups, `Ohm_Constants` StaticResource.

**Task 4 — Discovery service** (Q1–Q3 + bounded model-binding second pass).

**Task 5 — Signals (a)+(c) first** (confirmed, protected), then **(b)+(d) best-effort**.

**Task 6 — `OhmFootprintService`/`EstimateFootprint`** (one contract) + savings math.

**Task 7 — `PersistAuditReport`** (report + findings + agent-narrative write-back).

**Task 8 — LWC spine** S1→S4 + Calm Mode + polling; sync `startAudit`.

**Task 9 — `Ohm_Auditor` agent** (GenAiPlannerBundle + apex actions + topics); wire the two doors.

**Task 10 — a11y tests** (sa11y both variants) + targeted assertions.

**Task 11 — Polish** (methodology panel, volume scrubber, demo pacing <3 min). Stretch only: platform-event progress, Flow detection, CLT receipt-in-chat.

---

## 10. Risks

1. **Tooling callout auth (Task 0) — highest.** Client-credentials Connected App must be provisioned + consented; `getSessionId()` is rejected, so there is no fallback auth. Mitigation: Task 0 is blocking, day one.
2. **Empty org.** Every detector is validated only on the empty branch until fixtures exist (Task 2). Mitigation: fixtures own the four topologies explicitly.
3. **Signal (b) model binding** — no confirmed Apex read path for prompt-template model config; degrades to fixture-known config or "model unknown" note (no savings number).
4. **AgentGraph schema undocumented** — signal (d) and reachability depend on a tolerant parser unverifiable until a fixture exists; mis-tagging yields false findings. Mitigation: we own the fixture.
5. **Real-volume claim absent for demo** — telemetry empty/unconfirmed; all impact rests on modeled volume at Low confidence. Mitigation: reframed as the interactive what-if strength; band + `telemetryBacked=false` disclosed.
6. **Deploy/render unknowns** — FlexiPage round-trip, custom-setting deploy, embedded Agentforce panel, GenAiPlannerBundle + apex-action binding all [UNCONFIRMED]; each has a specified fallback (User field, polling, scripted conversation).
7. **CO₂e band width** could read as imprecision; mitigate by explicitly framing the band as the F10 methodology-defense feature.
8. **Contract drift** across F3/F4/F6 — mitigated by the single canonical DTO/picklist/EstimateFootprint contract fixed in this doc.

---

## 11. Open Decisions (design gate)

The following are settled in this document but flagged for confirmation; the small set genuinely needing Dom's call is in `openDecisionsForDom`. All picklist names, object names, the EstimateFootprint contract, the config store, the uncertainty vocabulary, the controller surface, the Named Credential name (`Ohm_Self`), and the progress transport are **canonicalized above** and require no further debate unless Dom overrides.
