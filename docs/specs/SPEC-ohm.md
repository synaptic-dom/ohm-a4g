# SPEC-ohm.md — Ohm: Agentic AI Sustainability Auditor (Implementation + Testing Spec)

**Version:** 1.0 · **Date:** 2026-09-01 · **Author:** Spec synthesis pass (solo build, Dom) · **Deadline:** Sep 7 2026 (hard close; target submit Sep 6)
**Grounded in:** DESIGN-ohm.md (authoritative), REQUIREMENTS-ohm.md (F1–F11, AC-F1..AC-Demo, NFR-1..5), SPIKE-ohm.md (confirmed org capabilities).
**Org:** EPIC OrgFarm (00Daj000013wTtpEAE), Enterprise, API **v67.0**, Agentforce enabled, System Admin, **empty** (fixtures required). My Domain: `https://orgfarm-08e0e83a93.my.salesforce.com`. All `sf` commands run via the **PowerShell tool** (Bash cannot invoke the CLI — SPIKE §7.5); treat `sf org display` output as secret.

> This spec operationalizes the approved design into buildable, testable units. It does **not** re-litigate any canonical choice. All cross-section inconsistencies flagged by the design critic are resolved here in **§0.2 Canonical Contracts** and are binding on every downstream section. TDD discipline per CLAUDE.md Commandment II: **failing test → minimal code → refactor green, one task at a time.**

---

## 0. Overview, Canon, and Build Order

### 0.1 Product thesis (the one load-bearing principle)
*Apex computes; the agent reasons and narrates.* The inventory walk, the four waste signals, and all footprint arithmetic run in deterministic Apex. The LLM earns tokens only for narration, phrasing/prioritizing recommendations, and methodology defense. Ohm's own agent (`Ohm_Auditor`), inspected by Ohm, scores clean on all four signals — that dogfooding **is** the demo. Award lanes: Headless Hero (agent observability), Equality Group Champion (sustainability), Accessibility Excellence (Calm Mode).

### 0.2 Canonical Contracts (LOCKED — every section obeys these)

These resolve all critic `mustFix` + `driftFromDesign` findings. They are the single source of truth; where any inherited section text disagreed, **this block wins.**

**C0 — Type-name alias vs DESIGN.** The in-memory discovery graph is `OhmDTO.AgentModel` throughout this spec; DESIGN-ohm.md calls the same structure `OhmGraph`. They are the **same type** — one Apex class, spec name wins in code (`OhmDTO.AgentModel`). Any `OhmGraph` reference in DESIGN reads as `AgentModel` here.

**C1 — One `Finding__c` object.** No `Recommendation__c`. Recommendation fields live on `Finding__c`.

**C2 — Canonical `Signal_Type__c` values (RESTRICTED picklist):** `LLM_WHERE_DETERMINISTIC`, `MODEL_RIGHTSIZING`, `INSTRUCTION_BLOAT`, `REDUNDANT_CALLS`. No `Model_Right_Sizing`/`Redundant_Call_Pattern` variants anywhere. **All canonical picklists carry `<restricted>true</restricted>`** (Signal_Type, Severity, Confidence, Artifact_Type, Fix_Type, Generated_By, Effort, Rec_Status, Run_Status) so invalid values raise a `DmlException` (required by AC-A2 / DM.3).

**C3 — Uncertainty vocabulary is `{Low, Central, High}` everywhere.** DTO fields are `energyWh{Low,Central,High}`, `waterMl{...}`, `co2eG{...}`. No `mid`/`point`.

**C4 — Action-class names are UNPREFIXED Apex classes** (matches DESIGN §2.1/§8): `DiscoverAgenticWork`, `RunSignals`, `EstimateFootprint`, `RecommendImprovements`, `PersistAuditReport`, `CreateRemediationTask`. The GenAiFunction **metadata** files MAY be `Ohm_`-prefixed for org-namespacing, but each `<invocationTarget>` MUST equal the **unprefixed Apex class name**. (Resolves the §S.10 vs §T9.3 name drift — build-breaking otherwise.)

**C5 — Canonical service signatures** (the agent door and the LWC door both call these identical methods — "one service, two doors"):
```apex
OhmDiscoveryService.discover() : OhmDTO.AgentModel
OhmSignalService.analyze(OhmDTO.AgentModel g) : List<OhmDTO.Finding>
OhmSignalService.rate(OhmDTO.AgentModel g, List<OhmDTO.Finding> f) : OhmDTO.EfficiencyResult
OhmFootprintService.estimate(OhmDTO.FootprintRequest req) : OhmDTO.FootprintResponse      // SINGULAR — the ONE engine
OhmFootprintService.estimateForArtifact(OhmDTO.Finding f, OhmDTO.VolumeInput v) : OhmDTO.FootprintResponse
OhmFootprintService.savingsFor(OhmDTO.Finding f, OhmDTO.VolumeInput v) : OhmDTO.FootprintResponse
OhmFootprintService.sumAll(List<OhmDTO.FootprintResponse> parts) : OhmDTO.FootprintResponse
OhmRecommendationService.attachRecommendations(List<OhmDTO.Finding> f) : List<OhmDTO.Finding>
OhmPersistenceService.createReport() : Id
OhmPersistenceService.updateProgress(Id reportId, String status, String stageMessage, Integer pct) : void
OhmPersistenceService.persistFindings(Id reportId, OhmDTO.AgentModel g, List<OhmDTO.Finding> f, OhmDTO.EfficiencyResult r) : void
OhmPersistenceService.writeAgentNarratives(Id reportId, List<OhmDTO.AgentNarrativeInput> narratives) : Integer
OhmPersistenceService.createRemediationTask(OhmDTO.RemediationInputDTO input) : Id   // the SINGLE F8 method
OhmPersistenceService.loadReadout(Id reportId) : OhmDTO.AuditReadoutDTO
```
The `@InvocableMethod EstimateFootprint.estimate(List<Request>) : List<Response>` iterates and calls the **singular** `OhmFootprintService.estimate(FootprintRequest)` per element (resolves the estimate-arity drift). `OhmAuditController` exposes the `@AuraEnabled` twin `estimateFootprint(FootprintRequest) : FootprintResponse` calling the same singular method (this is the target of the invocable==aura equality test).

**C6 — One `annualCalls` formula (4 factors):**
```
annualCalls = sessionsPerPeriod × turnsPerSession × callsPerTurn × periodsPerYear
```
Sourced from `Ohm_Constants.volumeScenario = { sessionsPerDay:50, turnsPerSession:6, callsPerTurn:1, daysPerYear:365 }` (period = day, `periodsPerYear = daysPerYear`). Baseline `callsPerTurn = 1`; the RedundantCall detector overrides `callsPerTurn` per-finding from `AgentGraph`. Demo baseline = 50×6×1×365 = **109,500 calls/yr** per artifact path. (Resolves the §S.6 3-factor vs §T.2.3 4-factor contradiction; `callsPerTurn` is now in the scenario.)

**C7 — severityScore (0–1) → `Severity__c` band cutoffs (single function `OhmSeverity.band(score)`):**
`High` if `score ≥ 0.67`; `Medium` if `0.34 ≤ score < 0.67`; `Low` if `score < 0.34`.
Per-detector score formulas:
- (a) `LLM_WHERE_DETERMINISTIC`: `score = min(1, 0.4 + 0.15×hitCount)` → 1 hit=0.55 (Medium), 2 hits=0.70 (High).
- (b) `MODEL_RIGHTSIZING`: `score = min(1, overshoot/2)` → overshoot 1=0.5 (Medium), 2=1.0 (High).
- (c) `INSTRUCTION_BLOAT`: `score = min(1, excessTokens/softThreshold)`.
- (d) `REDUNDANT_CALLS`: `score = min(1, 0.34 + 0.165×extraCalls)` → 1=0.505 (Medium), 2=0.67 (High); a prompt-bearing **cycle forces score=1.0 (High)**.
`Confidence__c`: (a)=Medium, (c)=High, (b)=Medium (Low when `modelAssumed`), (d)=Low.

**C8 — `Efficiency_Score__c` (0–100) → `Efficiency_Grade__c` letter cutoffs:**
`A ≥ 90`, `B ≥ 80`, `C ≥ 70`, `D ≥ 60`, `F < 60`, where `score = round(100 × (1 − Σ weightedSeverity / maxPossible))`. A clean org (all apex actions, lean scopes) yields **A** (NFR-4 dogfood).

**C9 — `Metric_Value__c` semantics for INSTRUCTION_BLOAT = EXCESS tokens over the SOFT threshold** (not total). Fixture canonical size **5,200 chars → 1,300 total tokens → `Metric_Value__c = 800` (1300−500), `Metric_Unit__c='tokens'`, severity = min(1,800/500)=1.0 (High)**; `Evidence__c` records total tokens for context. (Resolves the 5000/5200 + total-vs-excess inconsistency across §S.5c/§T2.2/§T.2.1.)

**C10 — Prompt-template discovery is deterministic + degrade-safe.** The `GenAiPromptTemplate` sObject is "not supported" and Tooling reachability is unproven (SPIKE §4). Therefore `Prompt_Templates_Discovered__c` / `AgentModel.promptTemplateCount` are populated by **counting distinct prompt templates referenced by `prompt`-typed actions** (`GenAiFunctionDefinition.InvocationTarget` of prompt actions), which is already in the discovery data. A best-effort Tooling `GenAiPromptTemplate` query is attempted first; on failure the reference-count path is used; neither throws. Fixture `Ohm_Fixture_SummarizeLead` → `Ohm_Fixture_LeadSummary` gives count ≥ 1 without needing the sObject.

**C11 — `Discovery_Graph_Json__c` (LongTextArea 131072) is a field on `Agent_Audit_Report__c`** (added to the Task-3 data model, §A.2.1). Task 9's agent re-entrancy depends on it.

**C12 — One `RemediationInputDTO` for F8.** Both doors marshal to `OhmDTO.RemediationInputDTO { findingId, reportId, fixType, recommendedTarget, recommendationText, estimatedSavingsCentralWh, note }`. The LWC passes the full DTO. The agent door (`CreateRemediationTask`, primitives `findingId` + optional `note`) **loads the persisted `Finding__c` to populate the remaining fields**, builds the same DTO, and calls the single `OhmPersistenceService.createRemediationTask(RemediationInputDTO)`. (Resolves the two-doors violation and the undefined-service-method gap.)

**C13 — SUPERSEDED (2026-09-01, ground-truth probe): discovery uses INLINE APEX SOQL, no callout, no auth chain.** Connected-app creation is **disabled** on this org ("contact Salesforce Customer Support"), so the Tooling-callout path is dead — but it is unnecessary: inline Apex SOQL reads `GenAiPlannerDefinition`, `GenAiPluginDefinition`, and `GenAiFunctionDefinition` directly (verified: `[SELECT Id, DeveloperName, MasterLabel, PlannerType, AgentGraph FROM GenAiPlannerDefinition]`, `[SELECT ... InvocationTargetType, InvocationTarget, PluginId, PlannerId FROM GenAiFunctionDefinition]` both return rows in a plain `sf apex run`). **Therefore `OhmToolingClient`, Named Credential `Ohm_Self`, the External/Connected credentials, and permset `Ohm_Integration` are ALL DELETED. `OhmDiscoveryService.discover()` runs SOQL directly. Task 0 and Task 0.5's auth pieces are removed from the build order.** Governor note: `discover()` stays bulk-safe (no SOQL/DML in loops); the three definition queries are 3 SOQL total. This is a net de-risk — the product's single highest-risk dependency is eliminated.

**Other locked canon (from DESIGN):** one `EstimateFootprint` contract; `Ohm_Constants` StaticResource (no CMDT); polling progress (no platform event on the spine); Named Credential `Ohm_Self` (client-credentials; `UserInfo.getSessionId()` rejected); unified `OhmAuditController`; two-region `Ohm_Audit` FlexiPage AppPage; sync `startAudit()` pipeline.

### 0.3 Build order (tied to the cut order — DESIGN §9, REQUIREMENTS §5.2)

| Task | Deliverable | Gate |
|---|---|---|
| **0** | Prove Tooling self-callout auth via `Ohm_Self` (BLOCKING) | HTTP 200 (C13) |
| **0.5** | **Agent-surface spike (WIN-1):** deploy a minimal `GenAiPlannerBundle` + one apex-action binding + embedded-panel render attempt; record scripted-conversation fallback footage the moment anything works | agent invokes an apex action in-org |
| **1** | Smoke-deploy one LWC on `Ohm_Audit` AppPage | dry-run RunLocalTests passes |
| **2** | Seed 4-signal fixture agent + clean dogfood agent; mirror as canned Tooling JSON | parser test green |
| **3** | Data model (`Agent_Audit_Report__c` + `Finding__c` + `Discovery_Graph_Json__c`) + `Ohm_Constants` + Calm Mode store | rollups + constants load |
| **4** | `OhmToolingClient` + `OhmDiscoveryService` | discovery unit tests ≥90% |
| **5** | `OhmSignalService` + 4 detectors (a,c protected; b,d best-effort) | detectors ≥90% |
| **6** | `OhmFootprintService` (one contract) + `VolumeProvider` + savings | band math exact |
| **7** | `OhmPersistenceService` (persist + narrative write-back + F8 task) | ≥4 findings, rollups |
| **8** | LWC spine S1→S4 + Calm Mode + polling + `OhmAuditController` | Jest ≥80% |
| **9** | `Ohm_Auditor` GenAiPlannerBundle + 6 apex actions + 4 topics; wire both doors | invocable==aura + manual smoke |
| **10** | a11y tests (sa11y both variants) + targeted assertions | 0 axe violations |
| **11** | Polish + rehearsed Physical UAT < 3 min | green UAT, RunLocalTests ≥75% |

**Cut order if schedule collapses (AMENDED per WIN-STRATEGY):** F11 polish → F8 tasks → F7 persistence; signals (b)+(d) degrade to best-effort before (a)+(c); embedded agent panel → scripted conversation. **Never cut:** S1 Welcome, S3 Impact (F4), S4 Recommendations (F5), the agent (F6), **F10 methodology defense, F9 Calm Mode** — the panel's finding: the original cut order protected the engineering spine while sacrificing the two features that anchor the two 20% award categories (RAI, Accessibility). They are now spine.

### 0.4 Win-strategy amendments (LOCKED — from WIN-STRATEGY-ohm.md, judge-panel score 69.5→~78)

| # | Amendment | Rubric target |
|---|---|---|
| W1 | **Task 0.5 agent-surface spike day 1** (see table above) — de-risks the three stacked [UNCONFIRMED]s that could ship the demo without its Agentforce thesis | Demonstrability +1.5, Originality |
| W2 | **Hook + close rewrite (do-now):** IEA 415 TWh-doubling × agent-adoption stakes in the 30s hook; energy-labels-changed-buildings close; **proud on-camera fixture disclosure** ("we seeded a deliberately wasteful agent so you can watch Ohm catch it") | Social Impact collapse-prevention |
| W3 | **Fix→re-audit demo loop:** apply one recommendation live (trim the bloated fixture Scope), re-run audit, efficiency grade visibly moves (e.g. D→B) with the Wh delta — the one beat no rival can stage | Social Impact +1.5, Originality +1 |
| W4 | **Grounded methodology defense:** `Ohm_Methodology` topic gets a read-only apex action returning the actual `Ohm_Constants`/assumptions JSON (no constants copy in Scope); `Agent_Narrative__c` carries NO numerals — all figures render exclusively from the Apex DTO ("the LLM literally cannot touch a number") | RAI +1.5 |
| W5 | **Calm Mode demo beat (15s):** flip toggle → receipt restructures → reload → persisted. Both persistence paths tested day 1 of Task 8 | Accessibility +1.5 |
| W6 | **Stage the dogfooding:** `Ohm_Auditor` rendered in the discovered inventory beside the messy fixture with its clean 4-signal scorecard; log its own action invocations during the run and show that log ~5s (Headless Hero letter-of-award: runtime observability of an agent in production) | Originality +0.5, Headless Hero |
| W7 | **Point-of-display provenance:** every savings figure carries its scenario inline ("at 50 sessions/day × 6 turns, modeled — Confidence: Low"); scrubber is a real slider (arrow keys, `aria-valuetext`, debounced polite announce) | RAI/SI/A11y +0.5 each |
| W8 | **Submission week:** shot-list per-beat second budgets, one unedited continuous take with visible org clock + auto-refreshing report list view; RAI Self Check as artifact-mapping table + Known Limitations; NVDA clip + sa11y CI output as a11y evidence pack; description names **Headless Hero and only Headless Hero** ("pre-production observability — the inspection before the incident") | Demonstrability +1, RAI +1, A11y +1, Scalability +1 |
| W-skip | Real telemetry generation; platform events; Flow-prompt detection; CLT-in-chat; Queueable impl — **confirmed skips**, every hour goes to the agent beat + video | — |

---

## §A — Auth Bootstrap (Task 0), Data Model, Config, Calm Mode

> **Ordering rule:** Task 0 is blocking and runs before any object/class/LWC exists. No auth path ⇒ no product (DESIGN §10 Risk 1). §A.2–§A.4 are built only after §A.1 prints a 200.

### A.1 — TASK 0: Prove the Tooling self-callout auth path (BLOCKING)

Goal: an in-org Apex `Http` callout, authenticated by a same-org **client-credentials Connected App** through Named Credential **`Ohm_Self`**, returns a `200` from Tooling REST `query`. `UserInfo.getSessionId()` is NOT used (rejected for API callouts from Lightning/async — DESIGN §3.1).

#### A.1.1 Connected App `Ohm_Self_CC` (client-credentials, same org)
`force-app/main/default/connectedApps/Ohm_Self_CC.connectedApp-meta.xml`:
- Label/API: `Ohm_Self_CC`; `<oauthConfig>`: `<callbackUrl>https://login.salesforce.com/services/oauth2/callback</callbackUrl>` (unused by CC but required), `<scopes>Api</scopes>` + `<scopes>RefreshToken</scopes>`, `<isAdminApproved>true</isAdminApproved>`, `<isClientCredentialEnabled>true</isClientCredentialEnabled>`; profile/perm-set pre-authorization for the running user.
- **Manual Setup steps (not fully expressible in metadata):** App Manager → `Ohm_Self_CC` → Manage → Edit Policies → **Client Credentials Flow → Run As = the integration/admin user** (`epic.f1c1977a25ca@orgfarm.salesforce.com`) — this is the consent step (CC has no interactive user). Save; wait ~2–10 min propagation (retry a transient 401). View → copy **Consumer Key/Secret** (secrets — never commit; SPIKE §7.5).

#### A.1.2 External Credential `Ohm_Self_Cred`
`externalCredentials/Ohm_Self_Cred.externalCredential-meta.xml`: `<authenticationProtocol>OAuth</authenticationProtocol>`, `<authenticationProtocolVariant>ClientCredentials</authenticationProtocolVariant>`, token endpoint `https://orgfarm-08e0e83a93.my.salesforce.com/services/oauth2/token`, a **Named Principal** parameter block holding `ClientId`/`ClientSecret` entered in Setup UI (NOT committed).

#### A.1.3 Named Credential `Ohm_Self`
`namedCredentials/Ohm_Self.namedCredential-meta.xml`: `<label>Ohm_Self</label>`, `<url>https://orgfarm-08e0e83a93.my.salesforce.com</url>`, `<generateAuthorizationHeader>true</generateAuthorizationHeader>`, `<externalCredential>Ohm_Self_Cred</externalCredential>`.

#### A.1.4 Permission Set `Ohm_Integration`
Grants the running user `<externalCredentialPrincipalAccesses>` to `Ohm_Self_Cred - <PrincipalName>`. Assign: `sf org assign permset -n Ohm_Integration -o ohm`. Without this the callout returns 401.

#### A.1.5 Deploy order
connectedApps → externalCredentials → namedCredentials → permissionsets. Enter Consumer Key/Secret in Setup between deploy and smoke test.

#### A.1.6 Smoke test (the gate) — anonymous Apex
`scripts/apex/task0_smoke.apex`, run `sf apex run -o ohm -f scripts/apex/task0_smoke.apex`:
```apex
String soql = 'SELECT Id, DeveloperName FROM GenAiPlannerDefinition LIMIT 5';
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Ohm_Self/services/data/v67.0/tooling/query/?q=' +
    EncodingUtil.urlEncode(soql, 'UTF-8'));
req.setMethod('GET');
req.setHeader('Accept', 'application/json');
HttpResponse res = new Http().send(req);
System.debug('STATUS=' + res.getStatusCode());
System.debug('BODY=' + res.getBody());
Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
System.assertEquals(200, res.getStatusCode(), 'Tooling callout must return 200 — auth path broken');
System.assert(parsed.containsKey('records'), 'Response missing records key — endpoint/auth suspect');
System.debug('TASK0 PASS — 200 from GenAiPlannerDefinition, records=' +
    ((List<Object>) parsed.get('records')).size());
```
**Exit gate (C13):** debug log shows `STATUS=200` and `TASK0 PASS`, with `records=[]` on the empty org proving the *real* discovery object is reachable **regardless of row count**. Auth is proven by the 200; the empty array is expected and not a failure. Only then proceed to A.2.

### A.2 — Data Model (Task 3)

Two objects, one master-detail. `CustomObject` metadata, fields inline. All picklists in C2 are `<restricted>true</restricted>`.

#### A.2.1 `Agent_Audit_Report__c` (one per run; F7)
| API Name | Type | Notes |
|---|---|---|
| `Name` | AutoNumber | `AUDIT-{00000}` |
| `Run_Timestamp__c` | DateTime | |
| `Run_Status__c` | Picklist (restricted) | `Queued`,`Discovering`,`Analyzing`,`Complete`,`Failed` (default `Queued`) |
| `Run_Stage_Message__c` | Text(255) | drives polled progress log |
| `Percent_Complete__c` | Number(3,0) | 0–100 |
| `Org_Id__c` | Text(18) | |
| `Agents_Discovered__c` / `Topics_Discovered__c` / `Actions_Discovered__c` / `Prompt_Templates_Discovered__c` | Number(6,0) | inventory (prompt count per **C10**) |
| `Discovery_Graph_Json__c` | LongTextArea(131072) | **C11** — serialized `OhmGraph` for agent re-entrancy |
| `Findings_Count__c` | Rollup (COUNT of `Finding__c`) | |
| `Total_Annual_Energy_Wh__c` | Rollup SUM(`Finding__c.Annual_Energy_Wh_Central__c`) | |
| `Total_Annual_Water_mL__c` | Rollup SUM(`Annual_Water_mL_Central__c`) | |
| `Total_Annual_CO2e_g__c` | Rollup SUM(`Annual_CO2e_g_Central__c`) | |
| `Total_Annual_Energy_Savings_Wh__c` | Rollup SUM(`Annual_Energy_Savings_Wh__c`) | |
| `Efficiency_Grade__c` | Text(2) | letter (**C8**) |
| `Efficiency_Score__c` | Number(3,0) | 0–100 (**C8**) |
| `Methodology_Version__c` | Text(20) | |
| `Discovery_Errors__c` | LongTextArea(32768) | partial-failure log |

Rollup field XML pattern:
```xml
<fields>
  <fullName>Total_Annual_Energy_Wh__c</fullName>
  <type>Summary</type>
  <summaryForeignKey>Finding__c.Agent_Audit_Report__c</summaryForeignKey>
  <summaryOperation>sum</summaryOperation>
  <summarizedField>Finding__c.Annual_Energy_Wh_Central__c</summarizedField>
</fields>
```
**Deploy note:** child Number fields must exist before the parent rollups reference them — deploy `Finding__c` fields before the report rollups (single-package deploy resolves ordering; split into two pushes if the platform complains).

#### A.2.2 `Finding__c` (one per waste-signal instance per artifact) — Master-Detail → `Agent_Audit_Report__c`
```xml
<fields>
  <fullName>Agent_Audit_Report__c</fullName>
  <type>MasterDetail</type>
  <referenceTo>Agent_Audit_Report__c</referenceTo>
  <relationshipName>Findings</relationshipName>
  <reparentableMasterDetail>false</reparentableMasterDetail>
  <writeRequiresMasterRead>false</writeRequiresMasterRead>
</fields>
```
| API Name | Type | Notes |
|---|---|---|
| `Name` | AutoNumber | `FIND-{00000}` |
| `Signal_Type__c` | Picklist (restricted) | **C2** canonical values only |
| `Severity__c` | Picklist (restricted) | `High`,`Medium`,`Low` (**C7**) |
| `Confidence__c` | Picklist (restricted) | `High`,`Medium`,`Low` |
| `Artifact_Type__c` | Picklist (restricted) | `Agent`,`Topic`,`Action`,`PromptTemplate` |
| `Artifact_Api_Name__c` / `Artifact_Label__c` | Text(255) | |
| `Artifact_Tooling_Id__c` | Text(18) | |
| `Parent_Agent_Api_Name__c` / `Parent_Topic_Api_Name__c` | Text(255) | |
| `Evidence__c` | LongTextArea(32768) | |
| `Metric_Value__c` | Number(16,2) | **C9** (bloat = excess tokens) |
| `Metric_Unit__c` | Text(40) | `tokens`/`calls-per-turn`/`model-multiplier` |
| `Annual_Energy_Wh_Central__c` (+`_Low`/`_High`) | Number(16,4) | |
| `Annual_Water_mL_Central__c` (+`_Low`/`_High`) | Number(16,4) | |
| `Annual_CO2e_g_Central__c` (+`_Low`/`_High`) | Number(16,4) | |
| `Estimated_Annual_Calls__c` | Number(16,0) | |
| `Per_Inference_Wh__c` | Number(16,6) | |
| `Annual_Energy_Savings_Wh__c` (+`_Low`/`_High`) | Number(16,4) | |
| `Fix_Type__c` | Picklist (restricted) | `Replace_With_Flow`,`Replace_With_Apex`,`Downsize_Model`,`Trim_Instructions`,`Consolidate_Calls` |
| `Recommended_Target__c` | Text(255) | |
| `Recommendation_Text__c` | LongTextArea(32768) | deterministic candidate |
| `Agent_Narrative__c` | LongTextArea(32768) | agent-phrased (hybrid seam) |
| `Generated_By__c` | Picklist (restricted) | `Deterministic`,`Agentforce` (default `Deterministic`) |
| `Effort__c` | Picklist (restricted) | `Low`,`Medium`,`High` |
| `Rec_Status__c` | Picklist (restricted) | `Proposed`,`Accepted`,`Dismissed`,`Applied` (default `Proposed`) |
| `Remediation_Task_Id__c` | Text(18) | |

### A.3 — Config: `Ohm_Constants` StaticResource + Apex fallbacks (Task 3)

Single StaticResource `Ohm_Constants` (contentType `application/json`, cacheControl `Public`). Loaded once per run (memoized); `static final` defaults are the fallback if the resource is missing/unparseable (DESIGN §2.4). No CMDT.

#### A.3.1 `Ohm_Constants.json`
```json
{
  "methodologyVersion": "1.0",
  "footprint": {
    "energyPerPromptWh":        { "low": 0.24, "central": 0.27, "high": 0.30 },
    "gridIntensityGco2ePerWh":  { "low": 0.125, "central": 0.30, "high": 0.475 },
    "waterMlPerWh":             { "low": 0.8,  "central": 1.08, "high": 1.4 },
    "referencePromptTokens": 500, "typicalOutputTokens": 250, "outputWeight": 1.0, "charsPerToken": 4.0
  },
  "modelMultipliers": {
    "SMALL":  { "tier": "SMALL",  "rank": 1, "rateCardMultiplier": 0.5 },
    "MEDIUM": { "tier": "MEDIUM", "rank": 2, "rateCardMultiplier": 1.0 },
    "LARGE":  { "tier": "LARGE",  "rank": 3, "rateCardMultiplier": 2.0 },
    "_baseline": "MEDIUM"
  },
  "thresholds": {
    "topicScopeSoftTokens": 500, "topicScopeHardTokens": 1000,
    "agentSoftTokens": 400, "agentHardTokens": 800,
    "actionSoftTokens": 150, "actionHardTokens": 300,
    "modelOvershootMin": 1, "redundantExtraCallsMin": 1, "sequentialChainMin": 3
  },
  "volumeScenario": { "sessionsPerDay": 50, "turnsPerSession": 6, "callsPerTurn": 1, "daysPerYear": 365 },
  "signalWeights": {
    "LLM_WHERE_DETERMINISTIC": 1.0, "MODEL_RIGHTSIZING": 0.7,
    "INSTRUCTION_BLOAT": 0.5, "REDUNDANT_CALLS": 0.8
  },
  "gradeCutoffs": { "A": 90, "B": 80, "C": 70, "D": 60 }
}
```
(`volumeScenario.callsPerTurn` added per **C6**; `gradeCutoffs` per **C8**.)

#### A.3.2 `OhmConstants` loader (signature)
```apex
public with sharing class OhmConstants {
    public class Band { public Decimal low; public Decimal central; public Decimal high; }
    public static OhmConstants load();                 // memoized per transaction
    public Decimal energyPerPromptWh(String band);
    public Band gridIntensityGco2ePerWh();
    public Band waterMlPerWh();
    public Integer topicScopeSoftTokens();             // + agent/action soft/hard accessors
    public Decimal rateCardMultiplier(String modelTierOrName);  // unknown ⇒ _baseline, caller sets modelAssumed
    public OhmDTO.VolumeInput defaultVolume();         // from volumeScenario (C6)
    public Decimal signalWeight(String signalType);
    public Map<String,Integer> gradeCutoffs();
    @TestVisible private static OhmConstants parseOrDefault(String rawJson);  // fallback test seam
    // Source-cited static-final fallbacks (identical numbers to §A.3.1):
    @TestVisible private static final Decimal ENERGY_CENTRAL_WH = 0.27;  // Epoch AI GPT-4o / Gemini 2025 median
    @TestVisible private static final Decimal GRID_CENTRAL     = 0.30;
    @TestVisible private static final Decimal WATER_CENTRAL_ML = 1.08;
    @TestVisible private static final Integer TOPIC_SCOPE_SOFT = 500;
    // every JSON leaf has a matching static-final default
}
```
Load: `[SELECT Body FROM StaticResource WHERE Name='Ohm_Constants']` → `blob.toString()` → `JSON.deserializeUntyped`. Any exception ⇒ static-final default for that key + a note appended to the `assumptions` output. Memoize in a private static (one SOQL per transaction — NFR-1).

### A.4 — Calm Mode persistence (Task 8 consumer, built with the data layer)

Primary store: hierarchy Custom Setting `Ohm_Preferences__c` with `Calm_Mode__c` (Checkbox, default false), `<customSettingsType>Hierarchy</customSettingsType>`, `<visibility>Public</visibility>`. Fallback if custom-setting deploy fails (DESIGN §7.4 `[UNCONFIRMED]`): a `Calm_Mode__c` Checkbox on `User`; controller contract identical.

Controller doors (part of unified `OhmAuditController`):
```apex
@AuraEnabled(cacheable=true) public static Boolean getCalmModePreference();
@AuraEnabled                 public static void setCalmModePreference(Boolean enabled);
```
Read: `Ohm_Preferences__c.getInstance(UserInfo.getUserId())?.Calm_Mode__c == true` (null-safe ⇒ false). Write: upsert an org-user-tier row keyed on `SetupOwnerId = UserInfo.getUserId()`. Single boolean over the wire. LWC calls `getCalmModePreference` in root `connectedCallback` before first render.

---

## §S — Service + Action Layer (Deterministic Core)

All logic in annotation-free **service** classes (unit-testable without an agent runtime). **Action** classes are thin `@InvocableMethod` marshalers (**C4** unprefixed names). `OhmAuditController` is the thin `@AuraEnabled` door. Path A (LWC) and Path B (agent) call identical service methods (**C5**). API v67.0, `with sharing` unless noted; no SOQL/DML in loops (NFR-1).

### S.0 Shared DTOs — `OhmDTO.cls` (all inner classes `@AuraEnabled` for LWC + `JSON.serialize` across the invocable boundary)

**Graph (in-memory `AgentModel`, not persisted):**
```apex
public class AgentModel { public Map<String,AgentNode> agentsById; public List<TopicNode> topics;
  public List<ActionNode> actions; public Map<String,List<TopicNode>> topicsByPlanner;
  public Map<String,List<ActionNode>> actionsByPlugin; public Map<String,List<ActionNode>> actionsByPlanner;
  public List<String> discoveryErrors; public Integer promptTemplateCount; }
public class AgentNode { public String id, developerName, masterLabel, description, plannerType, capabilities, agentGraphJson; }
public class TopicNode { public String id, developerName, masterLabel, description, scope, pluginType, plannerId, parentId; public Boolean isLocal; }
public class ActionNode { public String id, developerName, masterLabel, description, invocationTargetType, invocationTarget, pluginId, plannerId; public Boolean isLocal; public String boundModel; public Boolean modelAssumed; }
```
**Finding (service-internal, maps 1:1 to `Finding__c`):**
```apex
public class Finding { public String signalType, severity, confidence, artifactType, artifactApiName, artifactLabel,
  artifactToolingId, parentAgentApiName, parentTopicApiName, evidence; public Decimal metricValue; public String metricUnit;
  public FootprintResponse footprint; public FootprintResponse savings;
  public String fixType, recommendedTarget, recommendationText, agentNarrative, generatedBy, effort; public Id findingRecordId; }
```
**Footprint:**
```apex
public class FootprintRequest { public String artifactId, artifactType, boundModel; public Decimal tokensPerInference;
  public Decimal annualCalls; public Boolean modelAssumed; public String scenarioLabel; }
public class FootprintResponse { public Decimal energyWhLow, energyWhCentral, energyWhHigh;
  public Decimal waterMlLow, waterMlCentral, waterMlHigh; public Decimal co2eGLow, co2eGCentral, co2eGHigh;
  public Decimal annualCalls, perInferenceWh; public Boolean telemetryBacked; public String confidence; public Map<String,Object> assumptions; }
```
**Volume (C6):**
```apex
public class VolumeInput { public Decimal sessionsPerPeriod, turnsPerSession, callsPerTurn, periodsPerYear; public String scenarioLabel; }
```
**Efficiency:**
```apex
public class EfficiencyResult { public Integer score; public String grade; public Decimal weightedSeveritySum, maxPossible;
  public Integer deterministicActionCount, withinBudgetInstructionCount; }
```
**Cross-boundary contract DTOs (the LWC/agent bind to these — resolves the missing-DTO gap):**
```apex
public class AuditReadoutDTO {
  public Id reportId; public String runStatus, stageMessage; public Integer percentComplete;
  public Integer agentsDiscovered, topicsDiscovered, actionsDiscovered, promptTemplatesDiscovered;
  public String efficiencyGrade; public Integer efficiencyScore; public String methodologyVersion;
  public Decimal orgEnergyWhLow, orgEnergyWhCentral, orgEnergyWhHigh;
  public Decimal orgWaterMlLow, orgWaterMlCentral, orgWaterMlHigh;
  public Decimal orgCo2eGLow, orgCo2eGCentral, orgCo2eGHigh;
  public Decimal orgEnergySavingsWhLow, orgEnergySavingsWhCentral, orgEnergySavingsWhHigh;
  public Boolean telemetryBacked; public VolumeInput volumeAssumption; public Map<String,Object> assumptions;
  public List<FindingDTO> findings; public String discoveryErrors; }
public class FindingDTO {
  public Id id; public String signal, severity, confidence, artifactType;
  public TargetArtifact targetArtifact; public String evidence; public Decimal metricValue; public String metricUnit;
  public Decimal energyWhLow, energyWhCentral, energyWhHigh, waterMlLow, waterMlCentral, waterMlHigh,
    co2eGLow, co2eGCentral, co2eGHigh, estimatedAnnualCalls, perInferenceWh,
    estimatedSavingsLow, estimatedSavingsCentral, estimatedSavingsHigh;
  public String fixType, recommendedTarget, recommendationText, agentNarrative, generatedBy, effort, recStatus, remediationTaskId; }
public class TargetArtifact { public String apiName, label, toolingId, parentAgentApiName, parentTopicApiName; }
public class RemediationInputDTO { public Id findingId, reportId; public String fixType, recommendedTarget, recommendationText; public Decimal estimatedSavingsCentralWh; public String note; }   // C12
public class AgentNarrativeInput { public Id findingId; public String narrative; public Integer rank; }
```

### S.1 `OhmToolingClient` (`without sharing` — system callout)
Owns all Tooling REST I/O through `Ohm_Self`. Implements `IToolingClient` (test seam).
- `List<Map<String,Object>> query(String soql)` — GETs `callout:Ohm_Self/services/data/v67.0/tooling/query/?q={urlEncoded}`; follows `nextRecordsUrl` until absent; returns flat records. Throws `OhmCalloutException` on non-200 with body captured.
- `Map<String,Object> getRecordMetadata(String sobjectType, String recordId)` — GETs `/tooling/sobjects/{type}/{id}` for the per-record `Metadata` complexvalue (§3.3).
- Private `HttpResponse send(String relativeUrl)` — builds GET, 120s timeout; callouts precede DML. Base path `/services/data/v67.0` from a `static final`; `EncodingUtil.urlEncode(soql,'UTF-8')`.
- Alternate `OhmSoqlToolingClient : IToolingClient` swaps in if inline Tooling SOQL proves supported — no caller change.

### S.2 `OhmDiscoveryService`
Consumes `IToolingClient`, produces `AgentModel`. Deterministic, no LLM.
- `AgentModel discover()` — orchestrates Q1→Q2→Q3→(Q4 prompt-template best-effort per **C10**), builds the tree, runs the bounded model-binding pass, computes `promptTemplateCount`, returns the graph. Each query in a try/catch that appends to `discoveryErrors` and continues (partial-failure tolerance, Risk 2).
- `List<AgentNode> queryAgents()` — Q1 `GenAiPlannerDefinition`: `Id,DeveloperName,MasterLabel,Description,PlannerType,Capabilities,AgentGraph,FullName`.
- `List<TopicNode> queryTopics()` — Q2 `GenAiPluginDefinition`: incl `Scope,PluginType,PlannerId,ParentId,IsLocal`.
- `List<ActionNode> queryActions()` — Q3 `GenAiFunctionDefinition`: incl `InvocationTargetType,InvocationTarget,PluginId,PlannerId,IsLocal`.
- `Integer countPromptTemplates(AgentModel g)` — **C10**: try Tooling `GenAiPromptTemplate` query; on failure count distinct `InvocationTarget` of `prompt`-typed actions; never throws.
- `void buildTree(AgentModel g)` — populates `topicsByPlanner`/`actionsByPlugin`/`actionsByPlanner`; de-dupes local clones by `IsLocal/ParentId` for org counts while keeping per-agent instances for findings (§3.2).
- `void bindModels(AgentModel g)` — for **every** `invocationTargetType=='prompt'` action (bounded set), resolve model via `ModelBindingResolver`: (1) fixture-known config, else (2) `client.getRecordMetadata('GenAiFunctionDefinition', id)`, else null + `modelAssumed=true` (closes the S1/S2 circularity so signal (b) never fetches).
- Empty-org branch: all queries `[]` → empty graph, zero counts, no exception.

### S.3 `TokenEstimator` (stateless static)
- `Integer approxTokens(String text)` — `text==null ? 0 : (Integer)Math.ceil(text.length()/4.0)`.
- `Integer promptTurnTokens(AgentNode a, TopicNode activeTopic, List<ActionNode> inContext, Integer historyTokens, Integer userMsgTokens)` — sums system text + Scope + action descriptions + history + user msg; `REFERENCE_PROMPT_TOKENS`/`TYPICAL_OUTPUT_TOKENS`/`OUTPUT_WEIGHT` from `Ohm_Constants` with static-final fallbacks.

### S.4 `ModelRegistry`
- `class ModelInfo { String tier; Integer rank; Decimal rateCardMultiplier; }`
- `ModelInfo lookup(String modelApiName)` — normalized; **unknown ⇒ baseline MEDIUM, multiplier 1.0, caller sets `modelAssumed=true`**.
- `ModelInfo recommendedFor(TaskComplexity c)` — smallest tier covering the task (signal-b target).
- Config memoized from `Ohm_Constants`; parse failure ⇒ hardcoded defaults (no throw).

### S.5 `VolumeProvider` (resolves the missing-impl gap)
- `VolumeInput defaultVolume()` — reads `Ohm_Constants.volumeScenario` → `{sessionsPerPeriod:50, turnsPerSession:6, callsPerTurn:1, periodsPerYear:365, scenarioLabel:"50 sessions/day × 6 turns"}`.
- `VolumeInput withCallsPerTurn(VolumeInput base, Decimal callsPerTurn)` — per-finding override from `AgentGraph`.
- `Decimal annualCalls(VolumeInput v)` — **C6**: `v.sessionsPerPeriod * v.turnsPerSession * v.callsPerTurn * v.periodsPerYear`.
- Abstraction keeps a future `TelemetryVolumeProvider` swap-in with no caller change; `telemetryBacked=false` on modeled volume.

### S.6 `OhmSignalService` + four detectors
`interface SignalDetector { List<OhmDTO.Finding> detect(OhmDTO.AgentModel g); }`. `OhmSignalService.analyze(AgentModel)` instantiates the four detectors, concatenates results, attaches `Severity__c` via `OhmSeverity.band(score)` (**C7**). `rate(AgentModel, List<Finding>)` → `EfficiencyResult`: `score = round(100 × (1 − Σ(signalWeight×severityScore)/maxPossible))`; deterministic actions + within-budget instructions count as positive evidence; letter via **C8** cutoffs.

Helper `OhmSeverity.band(Decimal score) : String` — **C7** cutoffs (the single mapping used by every detector and its tests).

**(a) `LlmWhereDeterministicDetector` — CONFIRMED, protected.** For each `invocationTargetType=='prompt'` action, classify intent from `masterLabel+developerName+description` against the deterministic lexicon (classify, categorize, route, lookup, format, validate, extract, parse, calculate, boolean/yes-no). Fire when `hitCount≥1`. `score = min(1, 0.4 + 0.15×hitCount)`; `Severity = OhmSeverity.band(score)`; `Confidence='Medium'`. flow/apex never flagged (good-contrast). Savings = full per-inference footprint × volume (call removed).

**(c) `InstructionBloatDetector` — CONFIRMED, protected.** `totalTokens = approxTokens(scope|description|capabilities)`. Thresholds from `Ohm_Constants` (Topic 500/1000; Agent 400/800; Action 150/300). Fire when `totalTokens > soft`; `excess = totalTokens − soft`; `score = min(1, excess/soft)`; `Metric_Value__c = excess` (**C9**), `Metric_Unit__c='tokens'`, `Evidence__c` notes total. Savings recurring: `excess × turnsPerConversation × conversations`.

**(b) `ModelRightSizingDetector` — best-effort.** Uses `action.boundModel` (from S.2). If null → informational finding, no savings, `evidence='model unknown'`, `Confidence='Low'`. Else `overshoot = lookup(bound).rank − taskComplexity.rank` (triviality lexicon); fire when `overshoot ≥ 1`; `score = min(1, overshoot/2)`; `Confidence='Medium'`. Savings = `perInference × (1 − multiplier(recommended)/multiplier(bound))`.

**(d) `RedundantCallDetector` — best-effort.** `JSON.deserializeUntyped(agent.agentGraphJson)` tolerant walker. Tag nodes prompt vs deterministic via `invocationTargetType`. Heuristics: fan-out `extraCalls=max(0,promptNodeCount−1)`; sequential prompt chain ≥3; prompt-bearing cycle via DFS back-edge; duplicate target. Fire on `extraCalls≥1` OR prompt cycle. `score = min(1, 0.34 + 0.165×extraCalls)`, cycle forces `score=1.0`; `Metric_Value__c=extraCalls`, `Metric_Unit__c='calls-per-turn'`; `Confidence='Low'`. Savings = `perInference × extraCalls × turns × conversations`; cycles carry an explicit "×N" caveat. Malformed/absent `agentGraphJson` → no finding + `discoveryError` note (never a false positive).

### S.7 `OhmFootprintService` — the ONE contract (**C5**, DESIGN §6.1)
- `FootprintResponse estimate(FootprintRequest req)` — the single engine (singular). `perInferenceWh_{Low,Central,High} = energyPerPrompt_{band} × lookup(req.boundModel).rateCardMultiplier × (req.tokensPerInference / referencePromptTokens)`; `energyWh_* = perInferenceWh_* × req.annualCalls`; `co2eG_* = energyWh_* × gridIntensity_*`; `waterMl_* = energyWh_* × waterMlPerWh_*`. `assumptions` returns every constant used (F10). `telemetryBacked=false`, `confidence='Low'`.
- `FootprintResponse estimateForArtifact(Finding f, VolumeInput v)` — builds the request (tokens via `TokenEstimator`, `annualCalls = VolumeProvider.annualCalls(v)`) and delegates to `estimate`.
- `FootprintResponse savingsFor(Finding f, VolumeInput v)` — re-runs `estimate` with the one fixed parameter per signal (a: removed call → annualCalls delta; b: cheaper multiplier; c: reduced tokens; d: reduced callsPerTurn). `savings = baseline − fixed`. Single path.
- `FootprintResponse sumAll(List<FootprintResponse> parts)` — element-wise band sum = org-wide totals (NOT a separate engine). Private `perInference(...)` helper only.

### S.8 `OhmRecommendationService`
- `Finding attachRecommendation(Finding f)` — maps `signalType → {fixType, recommendationText template, recommendedTarget, effort}`: `LLM_WHERE_DETERMINISTIC→Replace_With_Flow|Replace_With_Apex`, `MODEL_RIGHTSIZING→Downsize_Model` (target `ModelRegistry.recommendedFor`), `INSTRUCTION_BLOAT→Trim_Instructions` (target token budget), `REDUNDANT_CALLS→Consolidate_Calls`. Fills `recommendationText` + `savings` via `OhmFootprintService.savingsFor`; `generatedBy='Deterministic'`.
- `List<Finding> attachRecommendations(List<Finding>)` (**C5** name) — bulk.

### S.9 `OhmPersistenceService` (`without sharing` for report write)
- `Id createReport()` — inserts `Agent_Audit_Report__c` `Queued`, returns Id (== runId).
- `void updateProgress(Id reportId, String status, String stageMessage, Integer pct)` — one status/stage/pct update (polling, §2.5).
- `void persistFindings(Id reportId, AgentModel g, List<Finding> findings, EfficiencyResult rating)` — sets inventory counts, `Discovery_Graph_Json__c` (**C11**), grade/score; bulk-inserts `Finding__c` children mapping every DTO field incl canonical `Signal_Type__c` + impact bands. One DML per object (bulk-safe); rollups compute `Total_*`.
- `Integer writeAgentNarratives(Id reportId, List<AgentNarrativeInput> narratives)` (**C5** name) — bulk-updates `Agent_Narrative__c` + `Generated_By__c='Agentforce'`; returns count.
- `Id createRemediationTask(RemediationInputDTO input)` (**C12** — the single F8 method) — inserts a `Task` (subject/description from fix + savings, `WhatId = input.reportId`), writes `Remediation_Task_Id__c` back on the finding, returns taskId.
- `AuditReadoutDTO loadReadout(Id reportId)` — one report + child findings query → the full readout for `getAuditStatus` on completion.

### S.10 `OhmAuditController` (unified `@AuraEnabled` door, DESIGN §7.2)
```apex
@AuraEnabled public static Id startAudit();                                              // callout=true
@AuraEnabled(cacheable=false) public static OhmDTO.AuditReadoutDTO getAuditStatus(Id reportId);
@AuraEnabled(cacheable=true)  public static Boolean getCalmModePreference();
@AuraEnabled public static void setCalmModePreference(Boolean enabled);
@AuraEnabled public static Id createRemediationTask(OhmDTO.RemediationInputDTO input);   // → OhmPersistenceService (C12)
@AuraEnabled public static OhmDTO.FootprintResponse estimateFootprint(OhmDTO.FootprintRequest req); // aura twin (C5)
```
`startAudit()`: `createReport()` → sync pipeline Discover→Signals→Footprint→Recommend→Persist (§2.3), `updateProgress` at each stage, returns reportId. Callouts (discovery) complete before any DML. `getAuditStatus` returns status during the run and the full readout when `Run_Status='Complete'` (merges old `getLatestAudit`). All exceptions caught → report `Failed` + `AuraHandledException`.

### S.11 Action classes (`@InvocableMethod`, thin; **C4** unprefixed; JSON-string payloads per DESIGN §8)
Each `Request`/`Response` holds **only primitives** + a `summary` NL string; rich structures cross as `JSON.serialize(dto)` strings. The model reads only `summary`; it never parses a `*Json` field. Each body ≤ marshal-in, call the **same service method the aura door calls** (**C5**), marshal-out. Re-entrant, keyed by `reportId` (shared state on the persisted report + `Discovery_Graph_Json__c`).

| Apex class (**C4**) | Request primitives | Response primitives | Service call | callout |
|---|---|---|---|---|
| `DiscoverAgenticWork` | `Id reportId` (blank ⇒ new) | `Id reportId`, `Integer agentCount/topicCount/actionCount/promptTemplateCount`, `String graphJson`, `String summary` | `OhmDiscoveryService.discover()` + persist graphJson | yes |
| `RunSignals` | `Id reportId`, `String graphJson` (blank ⇒ reload from `Discovery_Graph_Json__c`) | `Integer findingsCount`, `String signalBreakdownJson`, `String summary` | `OhmSignalService.analyze(graph)` | no |
| `EstimateFootprint` | `Id reportId`, `String requestJson` (one `FootprintRequest`; blank ⇒ org-wide) | `Decimal energyWhLow/Central/High`, `Decimal waterMlCentral`, `Decimal co2eGCentral`, `String assumptionsJson`, `String summary` | `OhmFootprintService.estimate(FootprintRequest)` per element (**C5** singular) | no |
| `RecommendImprovements` | `Id reportId` | `String candidatesJson`, `String summary` | `OhmRecommendationService.attachRecommendations(...)` | no |
| `PersistAuditReport` | `Id reportId`, `String narrativesJson` (`[{findingId,narrative,rank}]`) | `Integer recordsUpdated`, `String summary` | `OhmPersistenceService.writeAgentNarratives(...)` | no |
| `CreateRemediationTask` | `Id findingId`, `String note` | `Id taskId`, `String summary` | loads finding → builds `RemediationInputDTO` → `OhmPersistenceService.createRemediationTask(...)` (**C12**) | no |

`EstimateFootprint.estimate(List<Request>) : List<Response>` **is** the single `EstimateFootprint` door in canon; `OhmAuditController.estimateFootprint` reuses the same singular service method, so Path A and Path B can never diverge.

---

## §G — Ohm's Own Agent (`Ohm_Auditor`) + Fixtures (Tasks 9 & 2)

### G.1 `Ohm_Auditor` (GenAiPlannerBundle, v67)
Four topics; six actions all `InvocationTargetType=apex` (dogfood: Ohm scores clean on signal (a)); one `EstimateFootprint` contract; rich payloads cross as JSON strings; polling spine carries the demo if the panel fails.

**Metadata layout** under `force-app/main/default/`:
```
genAiPlannerBundles/Ohm_Auditor/Ohm_Auditor.genAiPlannerBundle-meta.xml   (lists all 4 genAiPlugins; router pinned to small/medium — clean on signal b)
genAiPlugins/  Ohm_Audit_Orchestration | Ohm_Recommendations | Ohm_Remediation | Ohm_Methodology  (.genAiPlugin-meta.xml)
genAiFunctions/  Ohm_DiscoverAgenticWork | Ohm_RunSignals | Ohm_EstimateFootprint | Ohm_RecommendImprovements | Ohm_PersistAuditReport | Ohm_CreateRemediationTask (.genAiFunction-meta.xml)
bots/Ohm_Auditor/Ohm_Auditor.bot-meta.xml + Ohm_Auditor.botVersion-meta.xml
classes/  (the six UNPREFIXED invocable classes + services + tests — deploy FIRST)
```
**Deploy dependency order:** Apex invocable classes → GenAiFunction → GenAiPlugin → GenAiPlannerBundle → Bot/BotVersion → activate → surface on FlexiPage Region B. A two-step push (classes first) de-risks apex-action binding validation.

**GenAiFunction ↔ Apex binding (C4):** the metadata `DeveloperName` MAY be `Ohm_`-prefixed but `<invocationTarget>` MUST equal the unprefixed class (e.g. `Ohm_DiscoverAgenticWork.genAiFunction-meta.xml` → `<invocationTarget>DiscoverAgenticWork</invocationTarget>`). For `apex` targets, input/output schema is derived by the platform from the invocable `Request`/`Response` `@InvocableVariable` fields — do NOT hand-author `<genAiFunctionInputs>`/`<genAiFunctionOutputs>` (avoids drift; verify assumption on first deploy).

**Topics (`GenAiPlugin`, scopes kept < 500 tok to stay clean on signal c):**
| Topic | pluginType | Scope (abridged) | genAiFunctions |
|---|---|---|---|
| `Ohm_Audit_Orchestration` | Topic | "Run and narrate a sustainability audit… Never compute numbers yourself — call the actions; read back their `summary`." | DiscoverAgenticWork, RunSignals, EstimateFootprint |
| `Ohm_Recommendations` | Topic | "Turn the deterministic fix candidates into prioritized human guidance, then persist the phrased narrative. Order by savings then effort." | RecommendImprovements, PersistAuditReport |
| `Ohm_Remediation` | Topic | "When the user accepts a recommendation, create one remediation task from it." | CreateRemediationTask |
| `Ohm_Methodology` | Topic | Holds F10 constants inline (per-inference 0.24/0.27/0.30 Wh, grid 0.125/0.30/0.475 gCO₂e/Wh, water 0.8/1.08/1.4 mL/Wh, tokens≈ceil(chars/4), `telemetryBacked=false` disclosure); answers "how did you estimate this?" | (none) |

**JSON-string marshaling contract (why Ohm stays clean on signal a):** the model never parses/reasons over any `*Json` string — those are opaque carriers persisted or handed to the next apex action; the model reads only `summary` fields (and, in Recommendations, phrases from `candidatesJson` treated as content to render, not compute). All arithmetic is deterministic Apex. This lets Ohm audit `Ohm_Auditor` and record **zero** `LLM_WHERE_DETERMINISTIC` findings against its own six apex actions.

**Verification:** (1) automatable Tooling query — `SELECT DeveloperName, InvocationTargetType, InvocationTarget FROM GenAiFunctionDefinition WHERE PlannerId IN (SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName='Ohm_Auditor')` → assert 6 rows, all `InvocationTargetType='apex'`, `InvocationTarget` = the class name. (2) Agent Builder Preview: "Audit this org" → planner selects `Ohm_Audit_Orchestration` → `DiscoverAgenticWork` (debug log shows the invocable). (3) Embedded panel on `Ohm_Audit` FlexiPage Region B; **fallback = standalone Agent Builder Preview scripted conversation** with Path A carrying AC-Demo.

### G.2 Seeded fixtures (Task 2 — the "org to make leaner")
The org is empty, so every detector is otherwise validated only on its empty branch. Task 2 seeds ONE deliberately-wasteful fixture agent tripping **all four** signals, plus the clean dogfood agent. All prefixed `Ohm_Fixture_` (trivially isolable/deletable via `destructiveChanges`), discoverable via the same Tooling objects Ohm walks. Fixtures are **never** referenced by `Ohm_Auditor`.

| Fixture | Metadata type | Defect → signal | Finding lands on |
|---|---|---|---|
| `Ohm_Fixture_LeadBot` | GenAiPlannerBundle | `AgentGraph` runs 2 prompt actions and **re-calls** `ClassifyPriority` in one turn (`extraCalls≥1`) | `REDUNDANT_CALLS` (agent) |
| `Ohm_Fixture_LeadTriage` | GenAiPlugin (topic) | `Scope` ≈ **5,200 chars ≈ 1,300 tok > 1,000 hard** (**C9**) | `INSTRUCTION_BLOAT` (topic) |
| `Ohm_Fixture_ClassifyPriority` | GenAiFunction | `invocationTargetType=prompt`; label/desc "Classify/categorize/route into High/Medium/Low" (≥3 lexicon hits) | `LLM_WHERE_DETERMINISTIC` (action) |
| ⤷ same action, bound model | (bound model) | LARGE model on trivial 3-way classify → `overshoot≥1` | `MODEL_RIGHTSIZING` (action) |
| `Ohm_Fixture_SummarizeLead` | GenAiFunction | `invocationTargetType=prompt`; second prompt node feeding signal-d topology; references the template below | participates in `REDUNDANT_CALLS` + prompt-template count |
| `Ohm_Fixture_LeadSummary` | GenAiPromptTemplate | makes `Prompt_Templates_Discovered__c ≥ 1` (via **C10** reference-count); supplies fixture-known model for signal (b) | — |

One fixture agent yields **≥4 findings, one per canonical `Signal_Type__c`**. Signal-b fixture binds a LARGE model (e.g. `sfdc_ai__DefaultGPT4Omni`, fixture-controlled, mapped to tier `LARGE` in `Ohm_Constants.modelMultipliers`) so signal (b) exercises the **positive** branch (never falls back to "model unknown" here).

**AgentGraph fixture (signal d — the parser's ground truth):**
```json
{ "nodes":[
    {"id":"n1","type":"action","ref":"Ohm_Fixture_ClassifyPriority","invocationTargetType":"prompt"},
    {"id":"n2","type":"action","ref":"Ohm_Fixture_SummarizeLead","invocationTargetType":"prompt"},
    {"id":"n3","type":"action","ref":"Ohm_Fixture_ClassifyPriority","invocationTargetType":"prompt"} ],
  "edges":[{"from":"n1","to":"n2"},{"from":"n2","to":"n3"}],
  "turns":[{"turn":1,"calls":["n1","n2","n3"]}] }
```
`promptNodeCount=3` → `extraCalls=2` + duplicate target (`ClassifyPriority` twice) → `REDUNDANT_CALLS`. If the real v67 `AgentGraph` schema differs, the fixture is re-authored to the real shape once observed in-org and the walker's field names updated — the walker stays untyped/tolerant so a schema surprise degrades to best-effort, never a hard failure. **Deploy fixtures in their own push after prompt-template dependency; teardown via `destructiveChanges` on `Ohm_Fixture_*`.**

---

## §L — LWC Experience + Accessibility (Task 8, 10)

Canon: one `Finding__c`; canonical signal values; `reportId==runId`; low/central/high vocabulary; polling progress; Calm Mode via `getCalmModePreference`/`setCalmModePreference`.

### L.1 Module layout (`force-app/main/default/lwc/`)
```
ohmAuditExperience      (Region A root FSM, all Apex I/O, isExposed=true, target lightning__AppPage)
ohmCalmModeToggle · ohmWelcome (S1) · ohmDiscoverAnalyze (S2 polling host) ·
ohmImpactReadout (S3) · ohmEfficiencyRating · ohmImpactReceipt · ohmUncertaintyBar (decorative, non-Calm) ·
ohmMethodologyPanel (F10) · ohmVolumeScrubber (§6.4) · ohmRecommendations (S4) · ohmRecommendationCard
```
Shared ES module `ohmConstants/ohmConstants.js` exports FSM `STATES`, `SIGNAL_LABELS` (canonical value → human label), `SEVERITY_LABELS`, `POLL_INTERVAL_MS=1500`. Parent-held state, `@api` down, `CustomEvent` up (no LMS/Redux). Only the root is `isExposed=true`; children `isExposed=false`. Host: `flexipages/Ohm_Audit.flexipage-meta.xml` (`type=AppPage`, two-region: Region A = root, Region B = embedded Agentforce panel), surfaced via `CustomTab Ohm_Audit` + `CustomApplication`.

### L.2 DTO shapes consumed (mirror §S.0 `AuditReadoutDTO`/`FindingDTO`/`RemediationInputDTO`; JS plain objects)
Render rule on the card: `displayRecommendation = agentNarrative ?? recommendationText` (narrative preferred — the hybrid seam made visible).

### L.3 Controller contract consumed (from `OhmAuditController`, §S.10)
`startAudit():Id` · `getAuditStatus(Id):AuditReadoutDTO` (cacheable=false, polled) · `getCalmModePreference():Boolean` (cacheable=true) · `setCalmModePreference(Boolean):void` · `createRemediationTask(RemediationInputDTO):Id`.

### L.4 `ohmAuditExperience` (root FSM)
- `@track state` ∈ `STATES` (`WELCOME|DISCOVERING|ANALYZING|IMPACT|RECOMMENDATIONS|ERROR`); DISCOVERING/ANALYZING both rendered by `ohmDiscoverAnalyze`, transition driven by `runStatus`.
- `@track calmMode` — loaded in `connectedCallback` via `getCalmModePreference` BEFORE first meaningful render (guarded by `isReady`; no flash of non-Calm).
- `@track reportId`, `@track readout`, `@track errorMessage`; private `_pollHandle`.
- Getters drive `lwc:if` (one screen mounted): `isWelcome`, `isDiscoverAnalyze`, `isImpact`, `isRecommendations`, `isError`.
- **Transitions:** `handleStart()` → `startAudit()`, store reportId, DISCOVERING, kick poll. `pollStatus()` → `getAuditStatus`; `Discovering`→stay, `Analyzing`→ANALYZING, `Complete`→store readout + IMPACT + stop, `Failed`→ERROR; reschedule via `setTimeout(pollStatus, POLL_INTERVAL_MS)` (not setInterval — no overlap); cleared in `disconnectedCallback` + on terminal; hard stop after N polls → ERROR. `handleViewRecommendations()`→RECOMMENDATIONS; `handleBack()`→IMPACT; rejected promise→ERROR; `handleRetry()`→WELCOME.
- **Focus (a11y):** after every state change, `renderedCallback` (guarded by `_focusPending`) moves focus to `[data-focus-heading]` (`tabindex="-1"`) — exactly one per mounted screen.
- Renders `<c-ohm-calm-mode-toggle>` on every screen; `handleCalmToggle()` flips `calmMode`, calls `setCalmModePreference` optimistically (reverts on reject; no render block).

### L.5–L.9 Child components (presentational)
- **ohmCalmModeToggle:** `@api calmMode`; `lightning-input type="toggle"` with persistent visible "On"/"Off" text (never color-only); emits `calmtoggle {enabled}`.
- **ohmWelcome (S1):** `@api calmMode`; framing copy + single "Start the audit" → emits `startaudit`; one `<h1 data-focus-heading tabindex="-1">`; Calm drops decorative hero, keeps structure. AC-F1.
- **ohmDiscoverAnalyze (S2):** `@api reportId, runStatus, stageMessage, percentComplete, calmMode`; pure display (root polls); determinate `lightning-progress-bar` + `aria-live="polite"` running log of `stageMessage`; Calm = discrete text only, no shimmer/spinner; one `<h2 data-focus-heading>`. AC-F2/observability.
- **ohmImpactReadout (S3):** `@api readout, calmMode`; composes `ohmEfficiencyRating` (letter+word+text badge; color redundant only), `ohmImpactReceipt` (text-first `<dl>` per Energy/Water/CO₂e = central + "range low–high"; non-Calm adds `ohmUncertaintyBar` `role="img"` + numeric `aria-label`; Calm omits via `showBars=!calmMode`), org-wide + per-artifact rows, `ohmVolumeScrubber` (§6.4 — emits `volumechange`; readout recomputes bands **client-side** from `perInferenceWh` × scrubbed volume, no Apex round-trip; Calm = numeric inputs not sliders), `ohmMethodologyPanel` (F10 — every constant + CO₂e band-width note). "See recommendations" → `viewrecommendations`; one `<h2 data-focus-heading>`. AC-F4/F10.
- **ohmRecommendations (S4) + ohmRecommendationCard:** container `@api findings, reportId, calmMode`; card shows `displayRecommendation`, savings band ("saves low–central–high Wh/yr"), `Severity: High` as TEXT + `SIGNAL_LABELS[finding.signal]`, effort text, `data-generated-by` text badge ("Agent-phrased"/"Deterministic"); "Create remediation task" → container calls `createRemediationTask`, flips card to "Task created" (stores `remediationTaskId`). AC-F5/F8.

### L.10 Calm Mode (F9)
One `@api calmMode` threads to every child; persisted via the controller doors (hierarchy `Ohm_Preferences__c`, fallback `User.Calm_Mode__c`, contract identical). Loaded at root `connectedCallback` before first render. Calm strips decoration (bars/animations/sliders → single column, larger line-height, discrete `aria-live` text, plain `<dl>`) but **never structure** (single `<h1>`, ordered headings, definition lists, landmarks, focus-on-heading identical in both modes). AC-F9.

---

## §T — Testing Plan (authoritative)

TDD per Commandment II: each bullet is a **failing test written first**, then minimal code, then refactor green.

### T.1 Test pyramid & coverage gates
```
UAT   : 1 scripted Physical UAT (§T.6), live vs seeded fixtures (manual, non-CI)
INTEG : Apex integration + invocable doors (HttpCalloutMock self-callout, end-to-end startAudit)
UNIT  : Apex unit (many) + Jest/sa11y (deterministic core, LWC)
```
| Layer | Tool | Target | Gate |
|---|---|---|---|
| Apex org-wide | `sf apex run test --test-level RunLocalTests --code-coverage` | **≥75%** | hard platform gate — deploy blocks below |
| Apex services (`OhmFootprintService`, `OhmSignalService`+4 detectors, `OhmRecommendationService`, `OhmDiscoveryService`) | Apex unit | **≥90%** line, 100% public methods | self-imposed (they hold the methodology) |
| Apex action/controller | Apex unit + integration | **≥80%** | positive + one error path each |
| LWC | `sfdx-lwc-jest` | **≥80%** stmts/component; every `@api`+`CustomEvent` | `coverageThreshold` in jest.config.js |
| LWC a11y | `@sa11y/jest` `toBeAccessible()` | **0 axe violations**, both Calm variants | any violation fails suite (F9/NFR-2) |

Coverage is a floor: the engine and detectors assert **exact numeric outputs against cited `Ohm_Constants`**, not mere line execution.

**Test layout:** `classes/` — `OhmToolingClientTest`, `OhmDiscoveryServiceTest`, `OhmSignalDetectorTest` (shared harness, 4 detectors), `OhmSignalServiceTest`, `OhmFootprintServiceTest`, `OhmRecommendationServiceTest`, `OhmVolumeProviderTest`, `OhmConstantsTest`, `OhmDataModelTest`, `OhmCalmModeTest`, `OhmPersistenceServiceTest`, `OhmAuditControllerTest`, `OhmInvocableDoorsTest`, `OhmGraphParserTest`, `OhmTestFactory` (@IsTest builders), `OhmToolingCalloutMock` (HttpCalloutMock); `staticresources/Ohm_Test_Tooling_Responses/` (canned Tooling JSON = byte-capture of seeded fixtures); `lwc/<c>/__tests__/<c>.test.js`.

### T.2 Task 0 — auth smoke (manual gate, blocking)
- **T0.1** run `task0_smoke.apex` → **PASS = STATUS=200 + `TASK0 PASS`, `records=[]` on empty org (C13 — auth proven by 200, not row count).** Hard gate; no A.2 until green.
- **T0.2** optional secondary: swap SOQL to `SELECT Id,Name FROM ApexClass LIMIT 5` post-Task-1 → 200 with rows (confirms row return once data exists). Non-blocking.
- **T0.3** failure-diagnosis rehearsal: remove `Ohm_Integration` assignment, re-run, confirm 401 (documents the live-demo 401 signature); re-assign after.
- Note: Task 0 is validated by live anon Apex (self-callouts to Tooling aren't mockable in a way that proves the real grant); `OhmToolingClient` unit tests use `HttpCalloutMock`.

### T.3 Unit — the deterministic core (pure, no callouts/org data; `OhmTestFactory` builds `AgentModel` in-memory — neutralizes the empty-org constraint)

**T.3.1 `OhmConstantsTest`:** CFG.1 happy path (`energyPerPromptWh('central')==0.27`, `topicScopeSoftTokens()==500`, `rateCardMultiplier('LARGE')==2.0`); CFG.2 fallback via `parseOrDefault(null)` and `'{ not json'` → static-final defaults + fallback note; CFG.3 partial JSON (only `central` overridden) → that key overridden, all others fall back, no NPE; CFG.4 unknown model → `_baseline` (MEDIUM=1.0) + `modelAssumed`; CFG.5 memoization — two `load()` calls = 1 SOQL (`Limits.getQueries()` delta==1).

**T.3.2 `OhmDataModelTest`:** DM.1 insert report + 3 findings (energy 10/20/30) → `Findings_Count__c==3`, `Total_Annual_Energy_Wh__c==60` (+ water/CO₂e/savings SUM); DM.2 master-detail cascade delete → 0 findings; **DM.3 (C2/AC-A2)** insert each canonical `Signal_Type__c` → success; invalid `Model_Right_Sizing` → **`DmlException` (proves `<restricted>true</restricted>`)**; DM.4 bulk (200 findings, one DML) → no governor exception, rollup correct.

**T.3.3 `OhmVolumeProviderTest`:** `defaultVolume()` → 50/6/1/365; `annualCalls()` = 50×6×1×365 = **109,500** (**C6**); doubling `sessionsPerPeriod` doubles annualCalls (scrubber linear invariant); `withCallsPerTurn(base,3)` → callsPerTurn=3, annualCalls×3.

**T.3.4 `TokenEstimatorTest` / `ModelRegistryTest`:** `approxTokens(null)=0`, `('')=0`, `('abcd')=1`, `('abcde')=2`; known model → tier/rank/multiplier; unknown → MEDIUM 1.0 + `modelAssumed`; `recommendedFor(trivial)→SMALL`; config parse failure → defaults (no throw).

**T.3.5 `OhmSignalDetectorTest` (positive/negative/boundary/bulk each — AC-F3):** using the single `OhmSeverity.band` (**C7**):
- (a) POS "ClassifyLeadPriority" prompt action → `LLM_WHERE_DETERMINISTIC`, 1 hit → `score=0.55` → `Severity='Medium'`, `Confidence='Medium'`, `Fix_Type='Replace_With_Flow'`; 2 hits → `score=0.70` → `Severity='High'`. NEG-1 apex action same label → 0. NEG-2 "Draft Empathetic Reply" prompt (no hit) → 0. BULK 200 mixed → correct subset, no per-record SOQL/DML.
- (b) POS LARGE on trivial → `overshoot≥1`, `score=overshoot/2`, savings uses multiplier ratio. DEGRADE `boundModel=null` → informational, savings energy 0, `evidence='model unknown'`, `Confidence='Low'`. NEG right-sized → 0. Boundary overshoot exactly 1 → `score=0.5` → Medium. BULK.
- (c) POS Scope 5,200 chars → 1,300 tok > 1,000 hard → fires; `Metric_Value__c==800` (**C9** excess-over-soft), `Metric_Unit__c='tokens'`, `score=min(1,800/500)=1.0` → High. Boundary exactly soft (500 tok) → no fire (`>soft` strict); soft+1 → fires. NEG 200-char → 0. Agent/Action variants use 400/800, 150/300. BULK.
- (d) POS fan-out (T2.4 graph, 3 prompt nodes/turn) → `REDUNDANT_CALLS`, `Metric_Value__c==2`, `Metric_Unit__c='calls-per-turn'`, `score=0.67`→High. POS cycle → fires, `score=1.0`→High, "×N" caveat in `Evidence__c`. NEG single prompt node → 0. DEGRADE malformed/empty `agentGraphJson` → 0 + `discoveryError` (no throw, no false positive). BULK.
- **Invariants every case:** canonical `Signal_Type__c` (hard string assert guards C2); `Confidence__c` set; malformed/empty input → empty `List<Finding>`, never throws.

**T.3.6 `OhmSignalServiceTest.rate` (C8):** lean org (all apex, within-budget) → high score → **grade A**; four-signal fixture → low grade; assert weighted-severity formula + grade cutoffs with known inputs; empty graph → 0 findings, no exception.

**T.3.7 `OhmFootprintServiceTest` (band math pinned to §6.2):**
- `estimate` central: `annualCalls=10000`, multiplier 1.0, reference tokens → `energyWhCentral=0.27×10000=2700`, `co2eGCentral=2700×0.30=810`, `waterMlCentral=2700×1.08=2916` (delta 0.001).
- band ordering `low ≤ central ≤ high` on all three metrics (property assert).
- token scaling: `tokensPerInference=2×reference` → perInference doubles. Model multiplier 2.0 → energy central doubles. Unknown model → baseline + `modelAssumed` in `assumptions`.
- `annualCalls=0` → all-zero response, no divide-by-zero, populated band structure.
- `savingsFor` single-path (**C5**): (a) removed call = full baseline; (b) `baseline×(1−m2/m1)`; (c) token-delta share; (d) extraCalls share — each = `baseline − fixed`; **no second signature exists** (org-wide = `sumAll`, asserted by summing two findings vs `report.Total_Annual_Energy_Wh__c`).
- `assumptions` contains every constant + `telemetryBacked=false`, `confidence='Low'` (F10).
- **vocabulary (C3):** JSON round-trip key assertion — exactly `energyWh{Low,Central,High}` etc.; no `mid`/`point`.

**T.3.8 `OhmGraphParserTest`:** T2.4 JSON literal → `promptNodeCount=3`, `extraCalls=2`, duplicate-target detected; unknown/renamed keys ignored (no throw); truncated/invalid JSON → empty topology + `Discovery_Errors__c` note (no throw); `null`/`''` → empty, 0 d-findings; local-clone dedupe (`IsLocal`/`ParentId`) collapses org counts, keeps per-agent instances.

**T.3.9 `OhmRecommendationServiceTest`:** each `signalType` → correct `fixType/recommendedTarget/effort`, non-empty `recommendationText`, `generatedBy='Deterministic'`, `savings` band populated; bulk variant.

### T.4 Integration (HttpCalloutMock + DML)
**T.4.1 `OhmToolingClientTest`:** single-page query; pagination (`nextRecordsUrl`, `done:false`→`done:true`, 2 callouts concatenated); non-200 (400/401/500) → `OhmCalloutException` body captured; SOQL URL-encoded (endpoint has no raw spaces); `getRecordMetadata` hits `/tooling/sobjects/GenAiFunctionDefinition/{id}`; endpoint begins `callout:Ohm_Self/services/data/v67.0/tooling/query/` (guards the `Ohm_Self` name + no `getSessionId()`).

**T.4.2 `OhmDiscoveryServiceTest`:** empty org (`[]`) → empty graph, zero counts, no exception; Q1/Q2/Q3 field mapping; `buildTree` keys correct (topic→agent by `PlannerId`, action→topic by `PluginId`); local-clone dedupe; `bindModels` — GET issued **only** for prompt actions (bounded); fixture-known → `boundModel` set; metadata-GET → set; neither → null + `modelAssumed`; partial failure (Q2 throws) → `discoveryErrors` appended, Q1/Q3 still populate; **C10** promptTemplateCount via reference-count when Tooling query unavailable; bulk 200 actions/3 planners → no per-record SOQL/DML.

**T.4.3 `OhmAuditControllerTest` (end-to-end, four-signal fixture graph via `Test.setMock`):** `startAudit` → report `Complete`, `Percent_Complete__c=100`, inventory counts, **≥4 `Finding__c`** master-detail, rollups (`Findings_Count__c`, `Total_Annual_Energy_Wh__c`, `Total_Annual_Energy_Savings_Wh__c`) = child SUM; callouts precede DML (no "uncommitted work"); `getAuditStatus` returns status mid-run + full readout on Complete (`reportId==runId`); `test_efficiencyGrade` four-signal → low, clean dogfood → **A**; `test_bulkSafety` 50-agent synthetic → 0 SOQL/DML in loops, `Limits` well under cap (NFR-1); `createRemediationTask(RemediationInputDTO)` inserts `Task` (description/savings/report link), back-populates `Remediation_Task_Id__c` (AC-F8); failure path → report `Failed` + `AuraHandledException`; Calm get/set round-trip (CALM.1 default false null-safe; CALM.2 round-trip one org-user row; CALM.3 idempotent upsert; CALM.4 toggle back false).

**T.4.4 `OhmInvocableDoorsTest` (call each `@InvocableMethod` directly with `List<Request>`):** `test_EstimateFootprint_invocable_equalsAura` — `EstimateFootprint.estimate(List<Request>)` and `OhmAuditController.estimateFootprint(FootprintRequest)` return identical bands for the same artifact (**C5** — proves one service, two doors); each of the six doors returns its JSON-string DTO that round-trips via `JSON.deserialize` without loss and exposes a populated `summary`; `RunSignals` blank `graphJson` reloads from `Discovery_Graph_Json__c` (**C11**); `PersistAuditReport` `writeAgentNarratives` sets `Agent_Narrative__c` + `Generated_By__c='Agentforce'` on the right findings, and `getAuditStatus` then returns narrative-preferred text (hybrid seam end-to-end); `CreateRemediationTask` (primitives `findingId`+`note`) loads the finding, builds `RemediationInputDTO`, calls the single service method (**C12**).

**T.4.5 Fixture co-validation:** the canned `AgentGraph` JSON in `Ohm_Test_Tooling_Responses` is the **same topology** deployed in Task 2, so the tolerant parser is proven against the exact bytes it meets in the demo (closes Risk 4). Refresh the canned JSON whenever fixtures change.

> **Manual/non-CI (explicitly labeled):** AC-F6 (the live agent *drives* the actions), AC-Demo (<3-min spine), and embedded-panel render in Region B cannot run in the Apex/Jest harness. Covered by Physical UAT §T.6 + a pre-demo smoke checklist; fallback = scripted Agent Builder Preview conversation with Path A carrying the spine. The invocable==aura test proves the doors, not that the agent selects them.

### T.5 LWC unit + a11y (`sfdx-lwc-jest` + `@sa11y/jest`)
Apex mocked via `jest.mock('@salesforce/apex/OhmAuditController.*')`; `jest.useFakeTimers()` for polling; `__tests__/data/mockAuditReadoutComplete.js` (full `AuditReadoutDTO`, ≥4 findings one per canonical signal, one with non-null `agentNarrative`) + `mockAuditReadoutRunning.js`.

**Functional (per component):** `ohmAuditExperience` — renders WELCOME first, `isReady` gates until `getCalmModePreference` resolves; startaudit→`startAudit`+DISCOVERING+poll; poll maps Discovering→stay/Analyzing→ANALYZING/Complete→IMPACT+readout+**stop** (assert no timer after terminal via `runOnlyPendingTimers`+call count)/Failed→ERROR; setTimeout not setInterval (one in-flight call); viewrecommendations→RECOMMENDATIONS; back→IMPACT; reject→ERROR; retry→WELCOME; `disconnectedCallback` clears `_pollHandle`; calmMode true→passed to children; calmtoggle→`setCalmModePreference` flipped, optimistic, reverts on reject; focus lands on `[data-focus-heading]` each transition. `ohmCalmModeToggle` text On/Off not color-only. `ohmWelcome` single `<h1>`, emits startaudit, Calm hides hero keeps `<h1>`. `ohmDiscoverAnalyze` determinate bar bound to `percentComplete`, new `stageMessage` appended to `aria-live="polite"`, no Apex called, Calm no spinner. `ohmImpactReadout` binds DTO → children, low/central/high text per metric, `showBars` only non-Calm, volumechange recomputes bands client-side (assert `getAuditStatus` NOT called on scrub), "See recommendations" emits. `ohmEfficiencyRating` grade letter+word present as text (color-independent). `ohmImpactReceipt` `<dl>` per metric, central + "range low–high", non-Calm `ohmUncertaintyBar` `role="img"`+numeric `aria-label`, Calm omits. `ohmMethodologyPanel` renders each assumption + CO₂e band-width note. `ohmVolumeScrubber` non-Calm range / Calm numeric, emits volumechange. `ohmRecommendations/Card` one card/finding, `displayRecommendation` prefers `agentNarrative` else `recommendationText`, savings band text, severity+`SIGNAL_LABELS` as TEXT, create-task→`createRemediationTask`→"Task created"/error text.

**a11y gate (sa11y):** for **every** of the 12 components, two tests (`calmMode=false`/`true`), `await expect(el).toBeAccessible()`, fixtures fully populated. Plus targeted (axe can't catch): color+text pairing on efficiency-rating + uncertainty-bar; `aria-live` on the progress log (new `stageMessage` lands inside); focus-lands-on-heading each FSM transition; exactly one `<h1>` + no skipped heading levels across a WELCOME→IMPACT→RECOMMENDATIONS walk; Calm applied before first paint (no flash), toggle calls `setCalmModePreference` once.

### T.6 Physical UAT — scripted <3-min demo (AC-Demo, manual)
**Preconditions:** Agentforce enabled; Task-2 fixtures seeded (four-signal agent + clean dogfood); `Ohm_Self` green (Task 0); `Ohm_Audit` AppPage active. Presenter opens cold; timer starts. Pass = every observable matches, spine < 3:00, no white-screen error.

| # | ~Time | Action | Expected observable | AC |
|---|---|---|---|---|
| 0 | 0:00 | Open `Ohm_Audit` | S1 Welcome: headline + single "Start the audit"; agent panel in Region B; focus on `<h1>` | AC-F1 |
| 1 | 0:15 | Click Start | → S2; determinate bar advances; `aria-live` log streams stages; Region B agent narrates the same discovery | AC-F2, AC-F6 |
| 2 | 0:45 | Wait | log 100%, `Complete`; auto → S3; four-signal fixture shows **findings on all four signals** with readable evidence | AC-F3 |
| 3 | 1:15 | Read Impact | org-wide **grade letter+word+text badge** (color redundant); Energy/Water/CO₂e each central + "range low–high"; uncertainty bar `aria-label` repeats numbers; per-artifact rows | AC-F4 |
| 4 | 1:45 | Drag volume scrubber (50→150) | footprint + savings scale live + linearly; scenario label updates; `telemetryBacked=false`/Low disclosed | AC-F4, NFR-3 |
| 5 | 2:10 | → S4 Recommendations | one card/finding: specific change, savings band, severity text; agent narrative where phrased else deterministic | AC-F5, AC-F6 |
| 6 | 2:30 | Toggle Calm Mode | single-column, larger line-height, no bars/animations; headings/`<dl>`/landmarks remain; persists across reload | AC-F9 |
| 7 | 2:45 | Open "How is this estimated?" (or ask the agent) | research basis + constants + assumptions + band rationale (grid dominant) | AC-F10 |
| 8 | 2:55 | (opt) Create remediation task | `Task` with description+savings+report link; confirmation | AC-F8 |
| — | <3:00 | Timer check | full spine demonstrated in-window | AC-Demo |

Dry-run rehearsal logged in `PROJECT_STATE.md` before the recorded take; forced ERROR (kill callout) degrades gracefully, not white-screen.

### T.7 Traceability (AC → test)
| Requirement | Test(s) |
|---|---|
| AC-F1 | Jest `ohmWelcome` (CTA) + `ohmAuditExperience` start; UAT 0 |
| AC-F2 | `OhmToolingClientTest`, `OhmDiscoveryServiceTest`, `OhmAuditControllerTest.test_bulkSafety`; Jest `ohmDiscoverAnalyze`; UAT 1 |
| AC-F3 | `OhmSignalDetectorTest` (a/b/c/d pos+neg+boundary+bulk), `OhmSignalServiceTest`; UAT 2 |
| AC-F4 | `OhmFootprintServiceTest` (band math §6.2, ordering, savings re-run, assumptions), `OhmVolumeProviderTest`, Jest `ohmImpactReceipt`/`ohmEfficiencyRating`; RunLocalTests ≥75%; UAT 3–4 |
| AC-F5 | `OhmRecommendationServiceTest`, Jest `ohmRecommendationCard`; UAT 5 |
| AC-F6 | `OhmInvocableDoorsTest` (invocable==aura), `writeAgentNarratives` bridge; **manual** agent smoke + UAT 1/5 |
| AC-F7 | `OhmAuditControllerTest.test_startAudit_producesReportAndFindings` + rollups, `OhmPersistenceServiceTest`, `OhmDataModelTest`; UAT (explorable) |
| AC-F8 | `OhmAuditControllerTest.createRemediationTask`, `OhmInvocableDoorsTest` CreateRemediationTask; UAT 8 |
| AC-F9 | Jest Calm tests + `@sa11y` both variants + persistence path; UAT 6 |
| AC-F10 | `OhmFootprintServiceTest.test_assumptions_disclosed`, Jest `ohmMethodologyPanel`; UAT 7 |
| AC-Demo | Physical UAT §T.6 (steps 0–5 < 3:00) — **manual/non-CI** |
| NFR-1 | `test_bulkSafety`, per-detector 200-record cases |
| NFR-2 | `@sa11y` gate both variants + color-text/aria-live/focus asserts |
| NFR-3 | band-ordering + assumptions tests, methodology panel, UAT 4 |
| NFR-4 | `test_efficiencyGrade` clean dogfood → grade A; `AC-T9.3` zero signal-(a) on Ohm's own actions |

### T.8 CI / execution commands
```powershell
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20
npm run test:unit -- --coverage
sf project deploy start --dry-run --test-level RunLocalTests
```

---

## §D — Definition of Done (per build phase; each phase TDD)

- **Task 0:** Apex Tooling callout through `Ohm_Self` returns **HTTP 200** (C13) in-org AND `OhmToolingClientTest` green (endpoint asserts `callout:Ohm_Self/.../tooling/query/`, pagination, error-degrade). Blocking — no green, no product.
- **Task 1:** one LWC renders on `Ohm_Audit` AppPage; `--dry-run --test-level RunLocalTests` passes.
- **Task 2:** four-signal `GenAiPlannerBundle`+topic+2 actions+prompt template AND clean dogfood agent deployed; same topology mirrored in `Ohm_Test_Tooling_Responses`; `OhmGraphParserTest` green against it.
- **Task 3:** `Agent_Audit_Report__c`+`Finding__c` (restricted canonical picklists, `Discovery_Graph_Json__c`), rollups, `Ohm_Constants`, Calm store deploy; `OhmConstantsTest`+`OhmDataModelTest`+`OhmCalmModeTest` green (fallback + DM.3 DmlException + rollups).
- **Task 4:** `OhmDiscoveryServiceTest` green ≥90% (graph build, dedupe, model-binding 2nd pass, promptTemplateCount degrade, malformed-graph degrade).
- **Task 5:** all four detectors pass pos+neg+boundary+bulk; canonical-picklist string asserts + `OhmSeverity.band` mapping hold; (b)/(d) degrade paths return without throwing. Services ≥90%.
- **Task 6:** `OhmFootprintServiceTest` proves central band = §6.2 exactly, low≤central≤high always, savings = re-run-with-fixed-param (all four), org-wide = `sumAll`, assumptions disclosed, `{Low,Central,High}` vocabulary; `OhmVolumeProviderTest` proves the 4-factor formula. Service ≥90%.
- **Task 7:** `test_startAudit_producesReportAndFindings` ≥4 findings + correct rollups; `writeAgentNarratives` bridge proven; `createRemediationTask` single-method (C12) green.
- **Task 8:** every LWC Jest suite ≥80%; FSM/polling/DTO-binding/Calm-persistence green; spine renders S1→S4 in-org.
- **Task 9:** `OhmInvocableDoorsTest` proves invocable==aura + JSON round-trip for all six doors; Tooling query confirms 6 apex-bound actions; manual smoke confirms `Ohm_Auditor` narrates (fallback scripted).
- **Task 10:** `@sa11y toBeAccessible()` 0 violations on all 12 components both variants + targeted color-text/aria-live/focus/single-h1 asserts.
- **Task 11:** rehearsed Physical UAT < 3:00 against fixtures, every observable met; org-wide RunLocalTests ≥75% (services ≥90%); logged in `PROJECT_STATE.md`.

**OVERALL RELEASE GATE:** org-wide Apex ≥75% AND services ≥90% AND LWC ≥80% AND 0 sa11y violations AND green Physical UAT AND §T.7 traceability satisfied.

---

## §O — Open items requiring Dom's decision (each has a recommended default already applied)
See the structured `openItems` list. All have safe defaults baked into this spec so the backlog can proceed; each is a *confirm-in-flight* verification, not a blocker.
