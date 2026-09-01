# BACKLOG-ohm.md

**Project:** Ohm — Agentic AI Sustainability Auditor · **Spec:** `docs/specs/SPEC-ohm.md` v1.0 · **Win strategy:** `docs/design/WIN-STRATEGY-ohm.md` · **Deadline:** submit Sep 6 2026 (hard close Sep 7)

**Status legend:** `Todo` · `In Progress` · `Done` · `Blocked`

Rules of engagement (Commandments II/VI/VII): one task at a time, TDD (failing test first → minimal code → refactor green), one commit per task (`feat(scope): description [OHM-NNN]`), update `PROJECT_STATE.md` after every task. Canon in SPEC §0.2 (C0–C13) and win amendments §0.4 (W1–W8) are binding on every task below.

---

## Task 0 — Prove Tooling self-callout auth via `Ohm_Self` (BLOCKING)

### OHM-001 — Create Connected App `Ohm_Self_CC` (client-credentials) and set Run As policy
- **Phase:** Task 0 — Prove Tooling self-callout auth
- **Status:** Todo
- **Deliverable:** `force-app/main/default/connectedApps/Ohm_Self_CC.connectedApp-meta.xml` (`<isClientCredentialEnabled>true</isClientCredentialEnabled>`, scopes `Api`+`RefreshToken`, `<isAdminApproved>true</isAdminApproved>`) deployed; manual Setup step done: Manage → Edit Policies → Client Credentials Flow → Run As = `epic.f1c1977a25ca@orgfarm.salesforce.com`; Consumer Key/Secret copied (never committed).
- **TDD test first:** Non-code — observable verification: App Manager shows `Ohm_Self_CC` with Client Credentials Flow enabled and the Run As user set; Consumer Key/Secret viewable.
- **Done when:** App visible in App Manager with policy saved; key/secret held locally outside git; ~2–10 min propagation window noted in `PROJECT_STATE.md`.
- **Depends on:** —
- **Est:** 1h
- **Win-tag:** —

### OHM-002 — Create External Credential `Ohm_Self_Cred` and enter the principal secret
- **Phase:** Task 0 — Prove Tooling self-callout auth
- **Status:** Todo
- **Deliverable:** `externalCredentials/Ohm_Self_Cred.externalCredential-meta.xml` (protocol `OAuth`, variant `ClientCredentials`, token endpoint `https://orgfarm-08e0e83a93.my.salesforce.com/services/oauth2/token`, Named Principal block) deployed; ClientId/ClientSecret entered in Setup UI (not committed).
- **TDD test first:** Non-code — observable verification: Setup → Named Credentials → External Credentials shows `Ohm_Self_Cred` with the Named Principal in "Configured" state.
- **Done when:** External credential deployed, principal shows configured with secrets stored in Setup only.
- **Depends on:** OHM-001
- **Est:** 30m
- **Win-tag:** —

### OHM-003 — Create Named Credential `Ohm_Self`
- **Phase:** Task 0 — Prove Tooling self-callout auth
- **Status:** Todo
- **Deliverable:** `namedCredentials/Ohm_Self.namedCredential-meta.xml` — `<url>https://orgfarm-08e0e83a93.my.salesforce.com</url>`, `<generateAuthorizationHeader>true</generateAuthorizationHeader>`, `<externalCredential>Ohm_Self_Cred</externalCredential>` — deployed.
- **TDD test first:** Non-code — observable verification: Setup → Named Credentials lists `Ohm_Self` bound to `Ohm_Self_Cred`.
- **Done when:** `callout:Ohm_Self` is resolvable as an Apex endpoint prefix (named credential active in org).
- **Depends on:** OHM-002
- **Est:** 30m
- **Win-tag:** —

### OHM-004 — Create Permission Set `Ohm_Integration` and assign it
- **Phase:** Task 0 — Prove Tooling self-callout auth
- **Status:** Todo
- **Deliverable:** `permissionsets/Ohm_Integration.permissionset-meta.xml` granting `<externalCredentialPrincipalAccesses>` to the `Ohm_Self_Cred` principal; assigned via `sf org assign permset -n Ohm_Integration -o ohm`.
- **TDD test first:** Non-code — observable verification: running user appears under the permission set's Assigned Users; principal access listed in the permset detail.
- **Done when:** Assignment confirmed (without it the smoke callout would 401 per §A.1.4).
- **Depends on:** OHM-002
- **Est:** 30m
- **Win-tag:** —

### OHM-005 — Write and pass the Task 0 smoke script (HTTP 200 gate, C13)
- **Phase:** Task 0 — Prove Tooling self-callout auth
- **Status:** Todo
- **Deliverable:** `scripts/apex/task0_smoke.apex` (SOQL `SELECT Id, DeveloperName FROM GenAiPlannerDefinition LIMIT 5` through `callout:Ohm_Self/services/data/v67.0/tooling/query/`), run via `sf apex run -o ohm -f scripts/apex/task0_smoke.apex`.
- **TDD test first:** The script IS the failing test: run it before OHM-001–004 are complete → expect 401; it asserts `System.assertEquals(200, ...)` and `records` key present (T0.1). Also run the T0.3 failure-diagnosis rehearsal: unassign `Ohm_Integration`, re-run, record the 401 signature, re-assign.
- **Done when:** Debug log shows `STATUS=200` and `TASK0 PASS` with `records=[]` accepted as success (C13 — auth proven by 200, not row count); 401 signature documented in `PROJECT_STATE.md`. **No downstream task starts until green.**
- **Depends on:** OHM-001, OHM-002, OHM-003, OHM-004
- **Est:** 1h
- **Win-tag:** —

---

## Task 0.5 — Agent-surface spike (W1)

### OHM-006 — Spike: deploy a minimal GenAiPlannerBundle with one apex-action binding
- **Phase:** Task 0.5 — Agent-surface spike (W1)
- **Status:** Todo
- **Deliverable:** Minimal spike bundle (throwaway planner bundle + one GenAiPlugin + one GenAiFunction with `<invocationTarget>` pointing at a trivial `@InvocableMethod` Apex class) deployed to the org; Agent Builder Preview conversation in which the agent invokes the apex action.
- **TDD test first:** Non-code — observable verification: Agent Builder Preview turn triggers the invocable (Apex debug log shows the invocable executed); Tooling query returns the `GenAiFunctionDefinition` row with `InvocationTargetType='apex'`.
- **Done when:** An agent invokes an apex action in-org (the §0.3 Task 0.5 gate); deploy order + any schema surprises (e.g. hand-authored inputs/outputs rejected per §G.1 assumption) logged in `PROJECT_STATE.md` for Task 9 reuse.
- **Depends on:** OHM-005
- **Est:** 2h
- **Win-tag:** W1

### OHM-007 — Spike: attempt embedded-panel render and record scripted-conversation fallback footage
- **Phase:** Task 0.5 — Agent-surface spike (W1)
- **Status:** Todo
- **Deliverable:** Embedded Agentforce panel render attempt on a test FlexiPage region; recorded fallback footage of a scripted Agent Builder Preview conversation captured the moment anything works (insurance footage per WIN-STRATEGY risk 2/8).
- **TDD test first:** Non-code — observable verification: panel renders in a FlexiPage region OR the fallback path (standalone Agent Builder Preview) is captured on video.
- **Done when:** Footage file exists and is catalogued; panel feasibility verdict ([CONFIRMED]/[FALLBACK]) recorded in `PROJECT_STATE.md`.
- **Depends on:** OHM-006
- **Est:** 1h
- **Win-tag:** W1

---

## Task 1 — Smoke-deploy one LWC on `Ohm_Audit` AppPage

### OHM-008 — Scaffold project and smoke-deploy a placeholder LWC on the `Ohm_Audit` AppPage
- **Phase:** Task 1 — Smoke-deploy one LWC
- **Status:** Todo
- **Deliverable:** SFDX project skeleton (API v67.0) + placeholder `ohmAuditExperience` LWC (`isExposed=true`, target `lightning__AppPage`) + `flexipages/Ohm_Audit.flexipage-meta.xml` (type `AppPage`, two regions: A = LWC root, B reserved for agent panel) + `CustomTab Ohm_Audit` + `CustomApplication`.
- **TDD test first:** Non-code gate command run first and observed failing on an empty/misconfigured project: `sf project deploy start --dry-run --test-level RunLocalTests` — then made to pass.
- **Done when:** Placeholder renders on the `Ohm_Audit` tab in-org; dry-run RunLocalTests passes (§0.3 Task 1 gate).
- **Depends on:** OHM-005
- **Est:** 2h
- **Win-tag:** —

---

## Task 2 — Seed fixtures + canned Tooling JSON mirrors

### OHM-009 — Seed fixture prompt template and the two prompt-typed fixture actions
- **Phase:** Task 2 — Seed fixture agents
- **Status:** Todo
- **Deliverable:** `Ohm_Fixture_LeadSummary` (GenAiPromptTemplate) + `Ohm_Fixture_ClassifyPriority` (GenAiFunction, `invocationTargetType=prompt`, label/description with ≥3 deterministic-lexicon hits "Classify/categorize/route into High/Medium/Low", bound LARGE model `sfdc_ai__DefaultGPT4Omni`) + `Ohm_Fixture_SummarizeLead` (GenAiFunction, `prompt`, references `Ohm_Fixture_LeadSummary`). Deployed template-first per §G.2.
- **TDD test first:** Non-code — observable verification: Tooling query over `GenAiFunctionDefinition` returns both fixture actions with `InvocationTargetType='prompt'`; template reference visible in `InvocationTarget` (drives C10 count ≥ 1).
- **Done when:** Both actions + template deployed and queryable through the same Tooling objects Ohm walks; signal (b) will exercise its positive branch via the fixture-known LARGE binding.
- **Depends on:** OHM-008
- **Est:** 1h
- **Win-tag:** —

### OHM-010 — Seed `Ohm_Fixture_LeadBot` bundle + `Ohm_Fixture_LeadTriage` bloated topic + AgentGraph + teardown manifest
- **Phase:** Task 2 — Seed fixture agents
- **Status:** Todo
- **Deliverable:** `Ohm_Fixture_LeadBot` (GenAiPlannerBundle) whose `AgentGraph` matches the §G.2 canonical topology (3 prompt nodes/turn, `ClassifyPriority` re-called → `extraCalls=2` + duplicate target); `Ohm_Fixture_LeadTriage` (GenAiPlugin) with Scope ≈ 5,200 chars ≈ 1,300 tokens (> 1,000 hard, C9); `destructiveChanges` manifest covering all `Ohm_Fixture_*` for teardown.
- **TDD test first:** Non-code — observable verification: Tooling queries return the planner + topic rows; `AgentGraph` JSON retrieved from the org byte-matches the §G.2 fixture literal (or, if the real v67 schema differs, the fixture is re-authored to the observed shape and the delta logged).
- **Done when:** One fixture agent trips all four signals by design (≥4 findings, one per canonical `Signal_Type__c`); teardown manifest deletes cleanly in a dry run.
- **Depends on:** OHM-009
- **Est:** 2h
- **Win-tag:** —

### OHM-011 — Seed the clean dogfood agent
- **Phase:** Task 2 — Seed fixture agents
- **Status:** Todo
- **Deliverable:** Clean agent seeded per §0.3 Task 2 / §D Task 2: all actions `InvocationTargetType=apex`, all scopes < soft thresholds, no redundant graph — the agent that scores **A** in `test_efficiencyGrade` (NFR-4). (Spec gap: whether this is an early `Ohm_Auditor` shell or a distinct clean seed is unresolved — see Open Items; build it as the minimal clean bundle reusing the OHM-006 spike learnings, upgradeable into `Ohm_Auditor` at Task 9.)
- **TDD test first:** Non-code — observable verification: Tooling query shows the clean agent's actions all `apex`-typed and every Scope under its soft token threshold.
- **Done when:** Clean agent discoverable via the same Tooling walk; zero fixture defects present.
- **Depends on:** OHM-006, OHM-008
- **Est:** 1h
- **Win-tag:** —

### OHM-012 — Mirror fixtures as canned Tooling JSON (`Ohm_Test_Tooling_Responses`) with topology assertions
- **Phase:** Task 2 — Seed fixture agents
- **Status:** Todo
- **Deliverable:** StaticResource `staticresources/Ohm_Test_Tooling_Responses/` — byte-capture of the seeded fixtures' Tooling responses (Q1/Q2/Q3 payloads + the `AgentGraph` JSON) — plus `OhmGraphParserTest` written with the T.3.8 topology assertions against the canned literal.
- **TDD test first:** `OhmGraphParserTest.test_fixtureTopology` — asserts the canned §G.2 JSON yields `promptNodeCount=3`, `extraCalls=2`, duplicate-target detected. Written now (failing — the tolerant walker lands with OHM-027); the §0.3 Task 2 "parser test green" gate is satisfied by asserting the canned JSON parses to the expected raw shape and finally goes fully green at OHM-027 (flagged Open Item).
- **Done when:** Canned JSON committed and provably the **same topology** deployed in OHM-010 (T.4.5 co-validation); refresh procedure noted (re-capture whenever fixtures change).
- **Depends on:** OHM-010
- **Est:** 1h
- **Win-tag:** —

---

## Task 3 — Data model + `Ohm_Constants` + Calm Mode store

### OHM-013 — Create `Finding__c` with all fields and restricted canonical picklists (C2)
- **Phase:** Task 3 — Data model
- **Status:** Todo
- **Deliverable:** `objects/Finding__c/` per §A.2.2 — Master-Detail `Agent_Audit_Report__c` (relationship `Findings`), AutoNumber `FIND-{00000}`, restricted picklists `Signal_Type__c` (`LLM_WHERE_DETERMINISTIC`,`MODEL_RIGHTSIZING`,`INSTRUCTION_BLOAT`,`REDUNDANT_CALLS`), `Severity__c`, `Confidence__c`, `Artifact_Type__c`, `Fix_Type__c`, `Generated_By__c`, `Effort__c`, `Rec_Status__c`, all impact/savings band Number fields (`Annual_Energy_Wh_Central__c` +`_Low`/`_High`, water, CO2e, `Annual_Energy_Savings_Wh__c` bands), `Metric_Value__c`, `Metric_Unit__c`, `Evidence__c`, `Agent_Narrative__c`, `Remediation_Task_Id__c`, etc.
- **TDD test first:** `OhmDataModelTest.test_DM3_restrictedPicklists` — inserts one `Finding__c` per canonical `Signal_Type__c` value (succeeds) and one with `Model_Right_Sizing` asserting `DmlException` (proves `<restricted>true</restricted>`, DM.3/AC-A2).
- **Done when:** Object deployed; DM.3 green; every §A.2.2 field present with exact API names.
- **Depends on:** OHM-008
- **Est:** 1h
- **Win-tag:** —

### OHM-014 — Create `Agent_Audit_Report__c` with `Discovery_Graph_Json__c` (C11) and rollups
- **Phase:** Task 3 — Data model
- **Status:** Todo
- **Deliverable:** `objects/Agent_Audit_Report__c/` per §A.2.1 — AutoNumber `AUDIT-{00000}`, restricted `Run_Status__c` (`Queued`,`Discovering`,`Analyzing`,`Complete`,`Failed`), `Run_Stage_Message__c`, `Percent_Complete__c`, inventory counts, `Discovery_Graph_Json__c` LongTextArea(131072), `Efficiency_Grade__c`/`Efficiency_Score__c`, `Methodology_Version__c`, `Discovery_Errors__c`, and rollups `Findings_Count__c` + `Total_Annual_Energy_Wh__c`/`Total_Annual_Water_mL__c`/`Total_Annual_CO2e_g__c`/`Total_Annual_Energy_Savings_Wh__c` (child fields deployed first per §A.2.1 deploy note).
- **TDD test first:** `OhmDataModelTest.test_DM1_rollupSums` — report + 3 findings (energy 10/20/30) → `Findings_Count__c==3`, `Total_Annual_Energy_Wh__c==60` (+ water/CO2e/savings); `test_DM2_cascadeDelete` → 0 orphan findings; `test_DM4_bulk200OneDml` → no governor exception, rollup correct.
- **Done when:** DM.1/DM.2/DM.4 green; rollups compute in-org.
- **Depends on:** OHM-013
- **Est:** 2h
- **Win-tag:** —

### OHM-015 — Create the `Ohm_Constants` StaticResource JSON
- **Phase:** Task 3 — Data model
- **Status:** Todo
- **Deliverable:** `staticresources/Ohm_Constants.resource` (+meta, contentType `application/json`, cacheControl `Public`) with the exact §A.3.1 body: footprint bands (0.24/0.27/0.30 Wh etc.), modelMultipliers (SMALL/MEDIUM/LARGE, `_baseline: MEDIUM`), thresholds (topic 500/1000, agent 400/800, action 150/300), `volumeScenario {50,6,1,365}` (C6), signalWeights, gradeCutoffs (C8).
- **TDD test first:** `OhmConstantsTest.test_CFG1_happyPath` — `energyPerPromptWh('central')==0.27`, `topicScopeSoftTokens()==500`, `rateCardMultiplier('LARGE')==2.0` (fails until OHM-016 delivers the loader; the resource content is asserted byte-exact by this test).
- **Done when:** Resource deployed; JSON matches §A.3.1 exactly including `callsPerTurn` and `gradeCutoffs`.
- **Depends on:** OHM-008
- **Est:** 30m
- **Win-tag:** —

### OHM-016 — Build the `OhmConstants` loader with memoization and static-final fallbacks
- **Phase:** Task 3 — Data model
- **Status:** Todo
- **Deliverable:** `classes/OhmConstants.cls` per §A.3.2 — `load()` memoized (one SOQL/transaction), typed accessors (`energyPerPromptWh`, `gridIntensityGco2ePerWh`, `waterMlPerWh`, threshold accessors, `rateCardMultiplier` with `_baseline` fallback, `defaultVolume()`, `signalWeight`, `gradeCutoffs`), `@TestVisible parseOrDefault(String)`, source-cited static-final defaults for every JSON leaf.
- **TDD test first:** `OhmConstantsTest` CFG.1–CFG.5 — happy path; `parseOrDefault(null)` and `'{ not json'` → static-final defaults + fallback note; partial JSON → per-key fallback, no NPE; unknown model → `_baseline` MEDIUM 1.0 + `modelAssumed`; memoization: two `load()` calls → `Limits.getQueries()` delta == 1.
- **Done when:** All five CFG tests green; no CMDT anywhere.
- **Depends on:** OHM-015
- **Est:** 2h
- **Win-tag:** —

### OHM-017 — Build the Calm Mode store and controller doors (persistence tested day 1, W5)
- **Phase:** Task 3 — Data model
- **Status:** Todo
- **Deliverable:** Hierarchy Custom Setting `Ohm_Preferences__c` with `Calm_Mode__c` Checkbox (`<visibility>Public</visibility>`) + the two doors on `OhmAuditController`: `@AuraEnabled(cacheable=true) getCalmModePreference()` (null-safe getInstance → false) and `@AuraEnabled setCalmModePreference(Boolean)` (upsert keyed on `SetupOwnerId = UserInfo.getUserId()`). Fallback plan documented: `Calm_Mode__c` Checkbox on `User` with identical controller contract if the custom-setting deploy fails.
- **TDD test first:** `OhmCalmModeTest` CALM.1–CALM.4 — default false null-safe; round-trip creates exactly one org-user row; idempotent upsert; toggle back to false.
- **Done when:** CALM.1–4 green; both persistence paths' viability verdict recorded (W5 requires this proven early, not at Task 8).
- **Depends on:** OHM-008
- **Est:** 1h
- **Win-tag:** W5

---

## Task 4 — `OhmToolingClient` + `OhmDiscoveryService`

### OHM-018 — Create `OhmDTO.cls` with all canonical inner classes (C0/C3/C12)
- **Phase:** Task 4 — Tooling client + discovery
- **Status:** Todo
- **Deliverable:** `classes/OhmDTO.cls` per §S.0 — `AgentModel` (C0), `AgentNode`, `TopicNode`, `ActionNode`, `Finding`, `FootprintRequest`, `FootprintResponse`, `VolumeInput`, `EfficiencyResult`, `AuditReadoutDTO`, `FindingDTO`, `TargetArtifact`, `RemediationInputDTO` (C12), `AgentNarrativeInput`; all inner classes `@AuraEnabled` and `JSON.serialize`-safe.
- **TDD test first:** `OhmDTOTest.test_C3_vocabularyRoundTrip` — `JSON.serialize` of a populated `FootprintResponse` contains exactly the keys `energyWhLow/energyWhCentral/energyWhHigh` (+ water/co2e triads); asserts absence of `mid`/`point` (C3); round-trip deserialize is lossless.
- **Done when:** Class compiles; vocabulary test green; field names match §S.0 verbatim.
- **Depends on:** OHM-008
- **Est:** 1h
- **Win-tag:** —

### OHM-019 — Build `OhmToolingClient` (+`IToolingClient`) with test doubles `OhmToolingCalloutMock` and `OhmTestFactory`
- **Phase:** Task 4 — Tooling client + discovery
- **Status:** Todo
- **Deliverable:** `classes/OhmToolingClient.cls` (`without sharing`, implements `IToolingClient`): `query(String soql)` with `nextRecordsUrl` pagination + `OhmCalloutException` on non-200, `getRecordMetadata(String,String)`, 120s timeout, `EncodingUtil.urlEncode`; plus test infrastructure `OhmToolingCalloutMock` (HttpCalloutMock serving `Ohm_Test_Tooling_Responses`) and `OhmTestFactory` (@IsTest in-memory `AgentModel` builders).
- **TDD test first:** `OhmToolingClientTest` (T.4.1) — single-page query; pagination `done:false→true` across 2 callouts concatenated; 400/401/500 → `OhmCalloutException` with body captured; URL-encoded SOQL (no raw spaces); `getRecordMetadata` hits `/tooling/sobjects/GenAiFunctionDefinition/{id}`; endpoint begins `callout:Ohm_Self/services/data/v67.0/tooling/query/` (guards against `getSessionId()`).
- **Done when:** T.4.1 green; mock + factory consumable by every downstream test class.
- **Depends on:** OHM-018, OHM-012
- **Est:** 2h
- **Win-tag:** —

### OHM-020 — Build `OhmDiscoveryService` core: Q1–Q3, `buildTree`, dedupe, empty-org branch
- **Phase:** Task 4 — Tooling client + discovery
- **Status:** Todo
- **Deliverable:** `classes/OhmDiscoveryService.cls` — `discover()` orchestration skeleton, `queryAgents()` (`GenAiPlannerDefinition` incl `AgentGraph`), `queryTopics()` (`GenAiPluginDefinition` incl `Scope`), `queryActions()` (`GenAiFunctionDefinition` incl `InvocationTarget`), `buildTree()` populating `topicsByPlanner`/`actionsByPlugin`/`actionsByPlanner` with local-clone dedupe (`IsLocal`/`ParentId`).
- **TDD test first:** `OhmDiscoveryServiceTest` (T.4.2 core) — empty org (`[]`) → empty graph, zero counts, no exception; Q1/Q2/Q3 field mapping; `buildTree` keys correct (topic→agent by `PlannerId`, action→topic by `PluginId`); local-clone dedupe collapses org counts while keeping per-agent instances.
- **Done when:** Core discovery tests green against `OhmToolingCalloutMock`; ≥90% coverage trajectory on the class.
- **Depends on:** OHM-019
- **Est:** 2h
- **Win-tag:** —

### OHM-021 — Add discovery enrichment + degrade paths: `bindModels`, `countPromptTemplates` (C10), `discoveryErrors`
- **Phase:** Task 4 — Tooling client + discovery
- **Status:** Todo
- **Deliverable:** `bindModels()` via `ModelBindingResolver` (fixture-known → metadata GET → null + `modelAssumed=true`; bounded to `prompt`-typed actions only); `countPromptTemplates()` per C10 (best-effort Tooling `GenAiPromptTemplate` query, fallback = distinct prompt-action `InvocationTarget` count, never throws); per-query try/catch appending to `discoveryErrors` (partial-failure tolerance).
- **TDD test first:** `OhmDiscoveryServiceTest` degrade cases (T.4.2) — GET issued **only** for prompt actions; fixture-known → `boundModel` set; neither source → null + `modelAssumed`; Q2 throws → `discoveryErrors` appended, Q1/Q3 still populate; C10 reference-count path when Tooling query unavailable (`Ohm_Fixture_SummarizeLead` → count ≥ 1); bulk 200 actions / 3 planners → no per-record SOQL/DML.
- **Done when:** All T.4.2 cases green; `OhmDiscoveryService` ≥90% line coverage (§0.3 Task 4 gate).
- **Depends on:** OHM-020
- **Est:** 2h
- **Win-tag:** —

---

## Task 5 — `OhmSignalService` + 4 detectors

### OHM-022 — Build `OhmSeverity.band` (C7 single mapping)
- **Phase:** Task 5 — Signal service + detectors
- **Status:** Todo
- **Deliverable:** `classes/OhmSeverity.cls` — `band(Decimal score) : String` with C7 cutoffs (`High ≥ 0.67`, `Medium 0.34–0.67`, `Low < 0.34`) — the single mapping used by every detector and test.
- **TDD test first:** `OhmSeverityTest.test_bandCutoffs` — 0.66→Medium, 0.67→High, 0.33→Low, 0.34→Medium, 1.0→High, 0→Low.
- **Done when:** Boundary tests green; no detector defines its own banding.
- **Depends on:** OHM-008
- **Est:** 30m
- **Win-tag:** —

### OHM-023 — Build `TokenEstimator` and `ModelRegistry`
- **Phase:** Task 5 — Signal service + detectors
- **Status:** Todo
- **Deliverable:** `classes/TokenEstimator.cls` (`approxTokens` = ceil(len/4), null→0; `promptTurnTokens` summing system+Scope+action descriptions+history+user msg with `Ohm_Constants` fallbacks) and `classes/ModelRegistry.cls` (`ModelInfo lookup` — unknown ⇒ baseline MEDIUM 1.0 + caller sets `modelAssumed`; `recommendedFor(TaskComplexity)`; memoized config, parse failure ⇒ defaults, no throw).
- **TDD test first:** `TokenEstimatorTest` + `ModelRegistryTest` (T.3.4) — `approxTokens(null)=0`, `('')=0`, `('abcd')=1`, `('abcde')=2`; known model → tier/rank/multiplier; unknown → MEDIUM 1.0; `recommendedFor(trivial)→SMALL`; config parse failure → defaults.
- **Done when:** All T.3.4 assertions green.
- **Depends on:** OHM-016, OHM-018
- **Est:** 1h
- **Win-tag:** —

### OHM-024 — Build `LlmWhereDeterministicDetector` (signal a, protected)
- **Phase:** Task 5 — Signal service + detectors
- **Status:** Todo
- **Deliverable:** `classes/LlmWhereDeterministicDetector.cls` implementing `SignalDetector` — lexicon classification of `prompt`-typed actions (classify, categorize, route, lookup, format, validate, extract, parse, calculate, boolean/yes-no); `score = min(1, 0.4 + 0.15×hitCount)`; `Confidence='Medium'`; flow/apex never flagged; savings = full per-inference footprint (call removed).
- **TDD test first:** `OhmSignalDetectorTest` (a)-block (T.3.5) — POS "ClassifyLeadPriority" 1 hit → score 0.55 → Medium, `Fix_Type='Replace_With_Flow'`; 2 hits → 0.70 → High; NEG-1 apex action same label → 0 findings; NEG-2 "Draft Empathetic Reply" → 0; BULK 200 mixed → correct subset, no per-record SOQL/DML; invariants: canonical `Signal_Type__c` string assert (C2), `Confidence__c` set, malformed input → empty list.
- **Done when:** pos+neg+boundary+bulk green with `OhmSeverity.band` mapping.
- **Depends on:** OHM-019, OHM-022
- **Est:** 2h
- **Win-tag:** —

### OHM-025 — Build `InstructionBloatDetector` (signal c, protected; C9 excess semantics)
- **Phase:** Task 5 — Signal service + detectors
- **Status:** Todo
- **Deliverable:** `classes/InstructionBloatDetector.cls` — `totalTokens = approxTokens(scope|description|capabilities)`; thresholds Topic 500/1000, Agent 400/800, Action 150/300 from `Ohm_Constants`; fires strictly `> soft`; `Metric_Value__c = excess` (C9), `Metric_Unit__c='tokens'`, `Evidence__c` notes total; `Confidence='High'`; recurring savings.
- **TDD test first:** `OhmSignalDetectorTest` (c)-block (T.3.5) — POS 5,200-char Scope → 1,300 tok → fires with `Metric_Value__c==800` (1300−500), `score=min(1,800/500)=1.0` → High; boundary exactly 500 tok → no fire, 501 → fires; NEG 200-char → 0; Agent/Action threshold variants; BULK.
- **Done when:** All (c) cases green including the C9 excess-not-total assertion.
- **Depends on:** OHM-022, OHM-023
- **Est:** 2h
- **Win-tag:** —

### OHM-026 — Build `ModelRightSizingDetector` (signal b, best-effort)
- **Phase:** Task 5 — Signal service + detectors
- **Status:** Todo
- **Deliverable:** `classes/ModelRightSizingDetector.cls` — uses `action.boundModel` (no fetching, closes S1/S2 circularity); null → informational finding, zero savings, `evidence='model unknown'`, `Confidence='Low'`; else `overshoot = rank(bound) − rank(taskComplexity)`, fire ≥1, `score = min(1, overshoot/2)`, `Confidence='Medium'`; savings via multiplier ratio.
- **TDD test first:** `OhmSignalDetectorTest` (b)-block (T.3.5) — POS LARGE on trivial → fires, savings uses `(1 − m_recommended/m_bound)`; DEGRADE `boundModel=null` → informational, energy 0; NEG right-sized → 0; boundary overshoot exactly 1 → score 0.5 → Medium; BULK.
- **Done when:** Positive + degrade + boundary + bulk green; detector never performs a callout.
- **Depends on:** OHM-021, OHM-022, OHM-023
- **Est:** 2h
- **Win-tag:** —

### OHM-027 — Build `RedundantCallDetector` (signal d, best-effort) with the tolerant AgentGraph walker
- **Phase:** Task 5 — Signal service + detectors
- **Status:** Todo
- **Deliverable:** `classes/RedundantCallDetector.cls` — `JSON.deserializeUntyped` tolerant walker; fan-out `extraCalls=max(0,promptNodeCount−1)`, sequential chain ≥3, DFS back-edge cycle (forces score 1.0 + "×N" caveat), duplicate target; `score = min(1, 0.34 + 0.165×extraCalls)`; `Metric_Unit__c='calls-per-turn'`; `Confidence='Low'`; malformed/absent graph → no finding + `discoveryError` note.
- **TDD test first:** `OhmSignalDetectorTest` (d)-block + `OhmGraphParserTest` fully green (T.3.5/T.3.8) — POS fixture graph → `Metric_Value__c==2`, `score=0.67`→High; POS cycle → 1.0→High with "×N" caveat in `Evidence__c`; NEG single prompt node → 0; DEGRADE malformed/empty JSON → 0 findings + `discoveryError`, no throw; unknown keys ignored; BULK.
- **Done when:** (d) suite green AND the OHM-012 `OhmGraphParserTest` assertions are fully green against the canned fixture bytes (closes the Task 2 gate).
- **Depends on:** OHM-012, OHM-022
- **Est:** 2h
- **Win-tag:** —

### OHM-028 — Build `OhmSignalService.analyze` + `rate` (C8 grading)
- **Phase:** Task 5 — Signal service + detectors
- **Status:** Todo
- **Deliverable:** `classes/OhmSignalService.cls` — `analyze(AgentModel)` instantiating the four `SignalDetector`s, concatenating findings, attaching severity via `OhmSeverity.band`; `rate(AgentModel, List<Finding>)` → `EfficiencyResult` with `score = round(100 × (1 − Σ(signalWeight×severityScore)/maxPossible))`, positive evidence counts, letter grade via C8 cutoffs (A≥90…F<60).
- **TDD test first:** `OhmSignalServiceTest.test_rate` (T.3.6) — lean all-apex graph → grade **A**; four-signal fixture graph → low grade; weighted-severity formula asserted with known inputs; empty graph → 0 findings, no exception.
- **Done when:** T.3.6 green; services ≥90% coverage (§0.3 Task 5 gate); (b)/(d) degrade without throwing.
- **Depends on:** OHM-024, OHM-025, OHM-026, OHM-027, OHM-016
- **Est:** 2h
- **Win-tag:** —

---

## Task 6 — `OhmFootprintService` + `VolumeProvider` + savings + recommendations

### OHM-029 — Build `VolumeProvider` (C6 four-factor formula)
- **Phase:** Task 6 — Footprint engine
- **Status:** Todo
- **Deliverable:** `classes/VolumeProvider.cls` — `defaultVolume()` from `Ohm_Constants.volumeScenario` (`{50, 6, 1, 365}`, scenarioLabel "50 sessions/day × 6 turns"), `withCallsPerTurn(base, n)`, `annualCalls(v) = sessionsPerPeriod × turnsPerSession × callsPerTurn × periodsPerYear`; `telemetryBacked=false` on modeled volume.
- **TDD test first:** `OhmVolumeProviderTest` (T.3.3) — `annualCalls(defaultVolume()) == 109500`; doubling `sessionsPerPeriod` doubles annualCalls (scrubber linear invariant); `withCallsPerTurn(base,3)` → annualCalls ×3.
- **Done when:** T.3.3 green; 4-factor formula is the only volume math in the codebase.
- **Depends on:** OHM-016, OHM-018
- **Est:** 1h
- **Win-tag:** —

### OHM-030 — Build `OhmFootprintService.estimate` (the ONE engine) + `sumAll`
- **Phase:** Task 6 — Footprint engine
- **Status:** Todo
- **Deliverable:** `classes/OhmFootprintService.cls` — singular `estimate(FootprintRequest) : FootprintResponse` (C5): `perInferenceWh_band = energyPerPrompt_band × rateCardMultiplier × (tokensPerInference/referencePromptTokens)`; energy/CO2e/water bands; `assumptions` map discloses every constant (F10); `telemetryBacked=false`, `confidence='Low'`; `sumAll(List<FootprintResponse>)` element-wise band sum (NOT a second engine).
- **TDD test first:** `OhmFootprintServiceTest` (T.3.7) — central pin: annualCalls=10000, multiplier 1.0 → `energyWhCentral==2700`, `co2eGCentral==810`, `waterMlCentral==2916` (±0.001); band ordering low≤central≤high on all metrics; token 2× → perInference 2×; multiplier 2.0 → energy 2×; unknown model → baseline + `modelAssumed` in assumptions; `annualCalls=0` → all-zero, no divide-by-zero; `test_assumptions_disclosed`; C3 JSON key assertion.
- **Done when:** Band math exact per §6.2 (§0.3 Task 6 gate); ≥90% coverage.
- **Depends on:** OHM-016, OHM-018, OHM-023
- **Est:** 2h
- **Win-tag:** —

### OHM-031 — Build `estimateForArtifact` + `savingsFor` (single savings path)
- **Phase:** Task 6 — Footprint engine
- **Status:** Todo
- **Deliverable:** `OhmFootprintService.estimateForArtifact(Finding, VolumeInput)` (tokens via `TokenEstimator`, calls via `VolumeProvider.annualCalls`, delegates to `estimate`) and `savingsFor(Finding, VolumeInput)` — re-run `estimate` with the one fixed parameter per signal (a: removed call; b: cheaper multiplier; c: reduced tokens; d: reduced callsPerTurn); `savings = baseline − fixed`.
- **TDD test first:** `OhmFootprintServiceTest` savings block (T.3.7) — each of the four signal deltas equals `baseline − fixed`; (a) = full baseline; (b) = `baseline×(1−m2/m1)`; **no second `estimate` signature exists** (org-wide totals asserted as `sumAll` of two findings vs `Total_Annual_Energy_Wh__c`).
- **Done when:** Savings single-path proven for all four signals; C5 arity respected.
- **Depends on:** OHM-030, OHM-029
- **Est:** 2h
- **Win-tag:** —

### OHM-032 — Build `OhmRecommendationService`
- **Phase:** Task 6 — Footprint engine
- **Status:** Todo
- **Deliverable:** `classes/OhmRecommendationService.cls` — `attachRecommendation(Finding)` mapping signal → fix (`LLM_WHERE_DETERMINISTIC→Replace_With_Flow|Replace_With_Apex`, `MODEL_RIGHTSIZING→Downsize_Model` via `ModelRegistry.recommendedFor`, `INSTRUCTION_BLOAT→Trim_Instructions`, `REDUNDANT_CALLS→Consolidate_Calls`) + `recommendationText`, `effort`, `savings` via `savingsFor`, `generatedBy='Deterministic'`; bulk `attachRecommendations(List<Finding>)` (C5 name).
- **TDD test first:** `OhmRecommendationServiceTest` (T.3.9) — each signalType → correct `fixType/recommendedTarget/effort`, non-empty `recommendationText`, `generatedBy='Deterministic'`, populated savings band; bulk variant.
- **Done when:** T.3.9 green; all Fix_Type values are the C2-restricted picklist values.
- **Depends on:** OHM-031, OHM-023
- **Est:** 1h
- **Win-tag:** —

---

## Task 7 — `OhmPersistenceService`

### OHM-033 — Build report lifecycle: `createReport`, `updateProgress`, `loadReadout`
- **Phase:** Task 7 — Persistence
- **Status:** Todo
- **Deliverable:** `classes/OhmPersistenceService.cls` (`without sharing`) — `createReport()` inserts `Queued` report returning Id (== runId); `updateProgress(reportId, status, stageMessage, pct)`; `loadReadout(reportId) : AuditReadoutDTO` (one report + child findings query → full readout).
- **TDD test first:** `OhmPersistenceServiceTest.test_reportLifecycle` — createReport returns Id with `Run_Status__c='Queued'`; updateProgress sets status/stage/pct; loadReadout maps every `AuditReadoutDTO` field including findings list and `discoveryErrors`.
- **Done when:** Lifecycle tests green; exactly one SOQL for the readout child query.
- **Depends on:** OHM-014, OHM-018
- **Est:** 1h
- **Win-tag:** —

### OHM-034 — Build `persistFindings` (C11 graph JSON + bulk-safe insert)
- **Phase:** Task 7 — Persistence
- **Status:** Todo
- **Deliverable:** `OhmPersistenceService.persistFindings(reportId, AgentModel, List<Finding>, EfficiencyResult)` — sets inventory counts, `Discovery_Graph_Json__c` (C11), grade/score; bulk-inserts `Finding__c` children mapping every DTO field incl canonical `Signal_Type__c` + impact/savings bands; one DML per object.
- **TDD test first:** `OhmPersistenceServiceTest.test_persistFindings` — four-signal fixture findings → ≥4 `Finding__c` rows master-detailed to the report, rollups (`Findings_Count__c`, `Total_Annual_Energy_Wh__c`, `Total_Annual_Energy_Savings_Wh__c`) equal child SUMs, `Discovery_Graph_Json__c` non-null round-trippable JSON; bulk 200 findings → one insert DML.
- **Done when:** ≥4 findings + correct rollups (§0.3 Task 7 gate); C11 field populated for Task 9 re-entrancy.
- **Depends on:** OHM-033
- **Est:** 2h
- **Win-tag:** —

### OHM-035 — Build `writeAgentNarratives` (hybrid seam write-back)
- **Phase:** Task 7 — Persistence
- **Status:** Todo
- **Deliverable:** `OhmPersistenceService.writeAgentNarratives(reportId, List<AgentNarrativeInput>) : Integer` — bulk-updates `Agent_Narrative__c` + `Generated_By__c='Agentforce'`, returns updated count. Narratives carry NO numerals by contract (W4 — figures render exclusively from the Apex DTO).
- **TDD test first:** `OhmPersistenceServiceTest.test_writeAgentNarratives` — narratives land on the right findings, `Generated_By__c` flips to `Agentforce`, return count correct, one DML for N narratives.
- **Done when:** Bridge test green; count returned.
- **Depends on:** OHM-034
- **Est:** 1h
- **Win-tag:** W4

### OHM-036 — Build `createRemediationTask` (C12 single F8 method)
- **Phase:** Task 7 — Persistence
- **Status:** Todo
- **Deliverable:** `OhmPersistenceService.createRemediationTask(RemediationInputDTO) : Id` — inserts a `Task` (subject/description from fix + savings, `WhatId = input.reportId`), writes `Remediation_Task_Id__c` back on the finding, returns taskId. The ONLY F8 method — both doors marshal to it.
- **TDD test first:** `OhmPersistenceServiceTest.test_createRemediationTask` — Task inserted with description containing fixType + savings + report link; `Remediation_Task_Id__c` back-populated on `Finding__c` (AC-F8).
- **Done when:** Test green; no second remediation code path exists anywhere.
- **Depends on:** OHM-033
- **Est:** 1h
- **Win-tag:** —

---

## Task 8 — LWC spine S1→S4 + Calm Mode + polling + `OhmAuditController`

### OHM-037 — Build `OhmAuditController.startAudit` sync pipeline + `getAuditStatus`
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `classes/OhmAuditController.cls` — `@AuraEnabled startAudit()` (createReport → Discover→Signals→Footprint→Recommend→Persist with `updateProgress` per stage, callouts before DML, returns reportId) and `@AuraEnabled(cacheable=false) getAuditStatus(Id) : AuditReadoutDTO` (status mid-run, full readout on `Complete`); all exceptions → report `Failed` + `AuraHandledException`.
- **TDD test first:** `OhmAuditControllerTest` (T.4.3) — `test_startAudit_producesReportAndFindings`: report `Complete`, `Percent_Complete__c=100`, inventory counts, ≥4 `Finding__c`, rollups = child SUMs, no "uncommitted work" error; `test_efficiencyGrade` four-signal → low / clean dogfood → **A** (NFR-4); `test_bulkSafety` 50-agent synthetic → 0 SOQL/DML in loops (NFR-1); failure path → `Failed` + `AuraHandledException`; `getAuditStatus` `reportId==runId`.
- **Done when:** Full T.4.3 green via `Test.setMock` on the four-signal fixture graph.
- **Depends on:** OHM-021, OHM-028, OHM-031, OHM-032, OHM-034
- **Est:** 2h
- **Win-tag:** —

### OHM-038 — Add controller aura twins: `estimateFootprint` + `createRemediationTask`
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `@AuraEnabled estimateFootprint(FootprintRequest) : FootprintResponse` calling the singular `OhmFootprintService.estimate` (C5 aura twin) and `@AuraEnabled createRemediationTask(RemediationInputDTO) : Id` delegating to the single C12 service method.
- **TDD test first:** `OhmAuditControllerTest.test_auraTwins` — `estimateFootprint` returns bands identical to a direct service call; `createRemediationTask` inserts the Task and back-populates `Remediation_Task_Id__c` (AC-F8). (The full invocable==aura equality lands at OHM-050.)
- **Done when:** Both doors green; controller ≥80% coverage.
- **Depends on:** OHM-030, OHM-036, OHM-037
- **Est:** 1h
- **Win-tag:** —

### OHM-039 — Set up LWC test infrastructure + `ohmConstants` shared module + mock readout data
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `sfdx-lwc-jest` + `@sa11y/jest` configured (`jest.config.js` with `coverageThreshold` ≥80% stmts/component); `lwc/ohmConstants/ohmConstants.js` exporting `STATES`, `SIGNAL_LABELS` (canonical C2 value → human label), `SEVERITY_LABELS`, `POLL_INTERVAL_MS=1500`; `__tests__/data/mockAuditReadoutComplete.js` (full `AuditReadoutDTO`, ≥4 findings one per canonical signal, one non-null `agentNarrative`) + `mockAuditReadoutRunning.js`.
- **TDD test first:** `ohmConstants.test.js` — asserts `SIGNAL_LABELS` keys are exactly the four canonical C2 values and `POLL_INTERVAL_MS===1500`; a deliberately-failing placeholder a11y test proves the sa11y matcher is wired.
- **Done when:** `npm run test:unit -- --coverage` runs with thresholds enforced; mock data importable.
- **Depends on:** OHM-008
- **Est:** 1h
- **Win-tag:** —

### OHM-040 — Build `ohmAuditExperience` root FSM + focus management
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmAuditExperience` — `@track state` ∈ `WELCOME|DISCOVERING|ANALYZING|IMPACT|RECOMMENDATIONS|ERROR`, `lwc:if` getters (one screen mounted), transitions (`handleStart`, `handleViewRecommendations`, `handleBack`, `handleRetry`), and focus-on-`[data-focus-heading]` (`tabindex="-1"`) after every state change via guarded `renderedCallback`.
- **TDD test first:** `ohmAuditExperience.test.js` — renders WELCOME first; startaudit → `startAudit` called + DISCOVERING; viewrecommendations → RECOMMENDATIONS; back → IMPACT; reject → ERROR; retry → WELCOME; focus lands on `[data-focus-heading]` on each transition.
- **Done when:** FSM + focus Jest suites green; component ≥80% stmts.
- **Depends on:** OHM-039
- **Est:** 2h
- **Win-tag:** —

### OHM-041 — Add root polling engine + error handling + Calm-before-first-paint wiring
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** Root polling via `setTimeout(pollStatus, POLL_INTERVAL_MS)` (never setInterval), terminal stop on `Complete`/`Failed`, hard stop after N polls, `_pollHandle` cleared in `disconnectedCallback`; `calmMode` loaded in `connectedCallback` via `getCalmModePreference` gated by `isReady` (no flash of non-Calm); `handleCalmToggle` optimistic `setCalmModePreference` with revert on reject.
- **TDD test first:** `ohmAuditExperience.test.js` polling block — `jest.useFakeTimers()`: Discovering→stay, Analyzing→ANALYZING, Complete→IMPACT + readout + **no timer after terminal** (`runOnlyPendingTimers` + call count), one in-flight call only; disconnect clears handle; `isReady` gates first render until calm pref resolves; toggle calls `setCalmModePreference` once, reverts on reject.
- **Done when:** Polling + Calm wiring suites green; W5 reload-persistence beat demonstrable in-org (flip → reload → persisted).
- **Depends on:** OHM-040, OHM-037, OHM-017
- **Est:** 2h
- **Win-tag:** W5

### OHM-042 — Build `ohmCalmModeToggle` + `ohmWelcome` (S1)
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmCalmModeToggle` (`@api calmMode`, `lightning-input type="toggle"` with persistent visible "On"/"Off" text, emits `calmtoggle {enabled}`) and `lwc/ohmWelcome` (framing copy + single "Start the audit" emitting `startaudit`, one `<h1 data-focus-heading tabindex="-1">`, Calm drops decorative hero keeps structure).
- **TDD test first:** `ohmCalmModeToggle.test.js` — On/Off state conveyed as text, never color-only; `ohmWelcome.test.js` — single `<h1>`, emits `startaudit`, Calm hides hero keeps `<h1>` (AC-F1).
- **Done when:** Both Jest suites green ≥80%.
- **Depends on:** OHM-040
- **Est:** 1h
- **Win-tag:** W5

### OHM-043 — Build `ohmDiscoverAnalyze` (S2 polling display)
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmDiscoverAnalyze` — `@api reportId, runStatus, stageMessage, percentComplete, calmMode`; determinate `lightning-progress-bar` + `aria-live="polite"` running log of `stageMessage`; Calm = discrete text only (no shimmer/spinner); one `<h2 data-focus-heading>`; pure display, zero Apex.
- **TDD test first:** `ohmDiscoverAnalyze.test.js` — bar bound to `percentComplete`; each new `stageMessage` appended inside the `aria-live` region; no Apex imports called; Calm renders no spinner (AC-F2).
- **Done when:** Jest suite green ≥80%.
- **Depends on:** OHM-040
- **Est:** 1h
- **Win-tag:** —

### OHM-044 — Build S3 display children: `ohmEfficiencyRating` + `ohmImpactReceipt` + `ohmUncertaintyBar`
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmEfficiencyRating` (letter+word+text badge, color redundant only), `lwc/ohmImpactReceipt` (text-first `<dl>` per Energy/Water/CO2e = central + "range low–high"), `lwc/ohmUncertaintyBar` (decorative non-Calm, `role="img"` + numeric `aria-label`; receipt omits via `showBars=!calmMode`).
- **TDD test first:** Jest per component — grade letter+word present as text (color-independent); `<dl>` per metric with central + range text; `ohmUncertaintyBar` has `role="img"` and numeric `aria-label`; Calm omits bars entirely (AC-F4).
- **Done when:** Three Jest suites green ≥80% each.
- **Depends on:** OHM-039
- **Est:** 2h
- **Win-tag:** —

### OHM-045 — Build `ohmImpactReadout` (S3 composition) with client-side scrub recompute
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmImpactReadout` — `@api readout, calmMode`; composes rating/receipt/bars, org-wide + per-artifact rows, methodology panel slot, scrubber; on `volumechange` recomputes bands **client-side** from `perInferenceWh` × scrubbed volume (no Apex round-trip); "See recommendations" emits `viewrecommendations`; one `<h2 data-focus-heading>`.
- **TDD test first:** `ohmImpactReadout.test.js` — DTO bound to children; low/central/high text per metric; `volumechange` recomputes locally with assertion that `getAuditStatus` is NOT called on scrub; linear scaling matches the OHM-029 invariant.
- **Done when:** Jest suite green ≥80%; S3 renders end-to-end with `mockAuditReadoutComplete`.
- **Depends on:** OHM-044, OHM-040
- **Est:** 2h
- **Win-tag:** —

### OHM-046 — Build `ohmVolumeScrubber` as a real accessible slider (W7)
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmVolumeScrubber` — non-Calm: real slider with arrow-key operation, `aria-valuetext` (e.g. "150 sessions per day"), debounced `aria-live="polite"` announce; Calm: numeric inputs instead of slider; emits `volumechange`.
- **TDD test first:** `ohmVolumeScrubber.test.js` — ArrowRight/ArrowLeft change value and emit `volumechange`; `aria-valuetext` present and updates; announce region is polite and debounced (single announcement for rapid keypresses); Calm variant renders numeric inputs, no slider.
- **Done when:** Jest suite green ≥80%; keyboard-only operation proven.
- **Depends on:** OHM-039
- **Est:** 1h
- **Win-tag:** W7

### OHM-047 — Build `ohmMethodologyPanel` (F10)
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmMethodologyPanel` — renders every constant/assumption from the readout `assumptions` map (per-inference Wh bands, grid intensity, water, tokens≈ceil(chars/4), `telemetryBacked=false` disclosure) + the CO2e band-width rationale note (grid dominant).
- **TDD test first:** `ohmMethodologyPanel.test.js` — each assumption key from `mockAuditReadoutComplete.assumptions` rendered; CO2e band-width note present (AC-F10).
- **Done when:** Jest suite green ≥80%; panel content sourced only from the DTO (no hardcoded copies of constants).
- **Depends on:** OHM-039
- **Est:** 1h
- **Win-tag:** —

### OHM-048 — Build `ohmRecommendations` + `ohmRecommendationCard` (S4)
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** `lwc/ohmRecommendations` (container: `@api findings, reportId, calmMode`; one card per finding; calls `createRemediationTask`) + `lwc/ohmRecommendationCard` (`displayRecommendation = agentNarrative ?? recommendationText`, savings band text "saves low–central–high Wh/yr", `Severity: High` as TEXT + `SIGNAL_LABELS[finding.signal]`, effort text, `data-generated-by` text badge "Agent-phrased"/"Deterministic", "Create remediation task" → "Task created").
- **TDD test first:** Jest — one card per finding; narrative preferred over deterministic text when non-null; severity + signal label as text; create-task flow calls `createRemediationTask` and flips to "Task created" (stores `remediationTaskId`); error path shows text (AC-F5/AC-F8).
- **Done when:** Both Jest suites green ≥80%.
- **Depends on:** OHM-039, OHM-038
- **Est:** 2h
- **Win-tag:** —

### OHM-049 — Add point-of-display provenance labels to every savings figure (W7)
- **Phase:** Task 8 — LWC spine + controller
- **Status:** Todo
- **Deliverable:** Inline provenance on every displayed savings/footprint figure across `ohmImpactReceipt`, `ohmImpactReadout` rows, and `ohmRecommendationCard`: scenario label ("at 50 sessions/day × 6 turns, modeled — Confidence: Low"), sourced from the DTO's `volumeAssumption.scenarioLabel` + `confidence`/`telemetryBacked`, updating live when the scrubber changes the scenario.
- **TDD test first:** Jest additions per component — every element rendering a Wh/mL/g figure has an adjacent provenance text node containing the scenario label and confidence; scrubbing to 150 updates the label text.
- **Done when:** No numeric savings figure renders anywhere without its inline scenario + confidence (W7); suites green.
- **Depends on:** OHM-044, OHM-045, OHM-046, OHM-048
- **Est:** 1h
- **Win-tag:** W7

---

## Task 9 — `Ohm_Auditor` agent + 6 invocable actions + both doors

### OHM-050 — Build invocables `DiscoverAgenticWork`, `RunSignals`, `EstimateFootprint` (C4/C5/C11)
- **Phase:** Task 9 — Ohm_Auditor agent
- **Status:** Todo
- **Deliverable:** Three UNPREFIXED thin `@InvocableMethod` classes per §S.11: `DiscoverAgenticWork` (blank reportId ⇒ new; persists `graphJson`; callout), `RunSignals` (blank `graphJson` ⇒ reload from `Discovery_Graph_Json__c`, C11), `EstimateFootprint` (`estimate(List<Request>):List<Response>` iterating the **singular** `OhmFootprintService.estimate` per element, C5). Primitives + `summary` NL string only; rich structures as `JSON.serialize` strings.
- **TDD test first:** `OhmInvocableDoorsTest` (T.4.4) — `test_EstimateFootprint_invocable_equalsAura`: invocable and `OhmAuditController.estimateFootprint` return identical bands for the same artifact (C5 one-service-two-doors); each door's JSON-string DTO round-trips via `JSON.deserialize` losslessly with populated `summary`; `RunSignals` blank `graphJson` reloads from `Discovery_Graph_Json__c`.
- **Done when:** Doors tests green; classes contain zero business logic (marshal → service → marshal).
- **Depends on:** OHM-021, OHM-028, OHM-034, OHM-038
- **Est:** 2h
- **Win-tag:** —

### OHM-051 — Build invocables `RecommendImprovements`, `PersistAuditReport`, `CreateRemediationTask` (C12)
- **Phase:** Task 9 — Ohm_Auditor agent
- **Status:** Todo
- **Deliverable:** Three UNPREFIXED invocables per §S.11: `RecommendImprovements` (→ `attachRecommendations`, returns `candidatesJson` + summary), `PersistAuditReport` (`narrativesJson` → `writeAgentNarratives`, returns `recordsUpdated`), `CreateRemediationTask` (primitives `findingId` + `note`; loads the persisted `Finding__c`, builds `RemediationInputDTO`, calls the single `OhmPersistenceService.createRemediationTask`, C12).
- **TDD test first:** `OhmInvocableDoorsTest` — `PersistAuditReport` sets `Agent_Narrative__c` + `Generated_By__c='Agentforce'` on the right findings and `getAuditStatus` then returns narrative-preferred text (hybrid seam end-to-end); `CreateRemediationTask` loads finding → same single service method as the aura door (C12); `RecommendImprovements` JSON round-trip + summary.
- **Done when:** All six doors covered in `OhmInvocableDoorsTest`, green.
- **Depends on:** OHM-032, OHM-035, OHM-036
- **Est:** 2h
- **Win-tag:** —

### OHM-052 — Build the grounded methodology read-only invocable action (W4)
- **Phase:** Task 9 — Ohm_Auditor agent
- **Status:** Todo
- **Deliverable:** A read-only thin `@InvocableMethod` returning the actual `Ohm_Constants`/assumptions JSON via `OhmConstants.load()` (+ `summary`), bound to the `Ohm_Methodology` topic so the agent's methodology defense quotes live constants — no constants copy in any Scope. (Spec gap: C4 lists six action classes and §G.1 gives `Ohm_Methodology` "(none)" with constants inline — W4 (locked, §0.4) overrides both; class name not canonized. See Open Items.)
- **TDD test first:** `OhmInvocableDoorsTest.test_methodologyAction_returnsLiveConstants` — response JSON deserializes to the exact `Ohm_Constants` values (central 0.27 Wh, grid 0.30, water 1.08, soft 500) and the action performs no DML.
- **Done when:** Test green; `Ohm_Methodology` Scope contains zero numeric constants.
- **Depends on:** OHM-016
- **Est:** 1h
- **Win-tag:** W4

### OHM-053 — Author GenAiFunction + GenAiPlugin metadata (C4 bindings, lean scopes)
- **Phase:** Task 9 — Ohm_Auditor agent
- **Status:** Todo
- **Deliverable:** `genAiFunctions/` for all invocables (`Ohm_DiscoverAgenticWork`, `Ohm_RunSignals`, `Ohm_EstimateFootprint`, `Ohm_RecommendImprovements`, `Ohm_PersistAuditReport`, `Ohm_CreateRemediationTask` + the W4 methodology function) each with `<invocationTarget>` = the UNPREFIXED Apex class (C4), no hand-authored inputs/outputs (platform-derived, per §G.1); `genAiPlugins/` for `Ohm_Audit_Orchestration`, `Ohm_Recommendations`, `Ohm_Remediation`, `Ohm_Methodology` — every Scope < 500 tokens (clean on signal c), orchestration Scope includes "Never compute numbers yourself".
- **TDD test first:** Non-code — observable verification (§G.1): Tooling query `SELECT DeveloperName, InvocationTargetType, InvocationTarget FROM GenAiFunctionDefinition WHERE PlannerId IN (SELECT Id FROM GenAiPlannerDefinition WHERE DeveloperName='Ohm_Auditor')` → all rows `InvocationTargetType='apex'` with `InvocationTarget` = unprefixed class names.
- **Done when:** Functions + plugins deploy after classes (two-step push); Tooling verification query returns the expected rows; `TokenEstimator.approxTokens` on each Scope < 500.
- **Depends on:** OHM-050, OHM-051, OHM-052
- **Est:** 2h
- **Win-tag:** W4

### OHM-054 — Deploy `Ohm_Auditor` plannerBundle + Bot/BotVersion, activate, surface in Region B
- **Phase:** Task 9 — Ohm_Auditor agent
- **Status:** Todo
- **Deliverable:** `genAiPlannerBundles/Ohm_Auditor/Ohm_Auditor.genAiPlannerBundle-meta.xml` (lists all 4 plugins; router pinned small/medium — clean on signal b) + `bots/Ohm_Auditor/Ohm_Auditor.bot-meta.xml` + `Ohm_Auditor.botVersion-meta.xml`; deploy order classes → functions → plugins → bundle → bot → activate; embedded panel on `Ohm_Audit` FlexiPage Region B (fallback = standalone Agent Builder Preview per OHM-007 verdict).
- **TDD test first:** Non-code — observable verification: Agent Builder Preview "Audit this org" → planner selects `Ohm_Audit_Orchestration` → `DiscoverAgenticWork` invocable appears in the Apex debug log (§G.1 verification 2).
- **Done when:** Agent active; panel rendered in Region B or fallback documented + footage captured; dogfood invariant holds (Ohm audits `Ohm_Auditor` → zero `LLM_WHERE_DETERMINISTIC` findings on its six apex actions).
- **Depends on:** OHM-053, OHM-006
- **Est:** 2h
- **Win-tag:** W1

### OHM-055 — Log and surface `Ohm_Auditor`'s own action invocations during the run (W6)
- **Phase:** Task 9 — Ohm_Auditor agent
- **Status:** Todo
- **Deliverable:** Each of the invocable doors appends an invocation entry (action name + timestamp) to the run's observable log (via `OhmPersistenceService.updateProgress` stage messages onto `Run_Stage_Message__c`, streamed by `ohmDiscoverAnalyze`'s aria-live log), so the demo can show the agent's own action-invocation log for ~5s beside the discovered inventory + clean scorecard (Headless Hero: runtime observability). (Spec gap: W6 names no canonical mechanism/field — stage-message approach flagged in Open Items.)
- **TDD test first:** `OhmInvocableDoorsTest.test_invocationLogEntries` — invoking `DiscoverAgenticWork` then `RunSignals` leaves stage entries containing each action's name in order on the report.
- **Done when:** Test green; a full agent-driven run produces a visible per-action log; `Ohm_Auditor` appears in the discovered inventory beside the messy fixture with its clean 4-signal scorecard.
- **Depends on:** OHM-050, OHM-051, OHM-043
- **Est:** 1h
- **Win-tag:** W6

### OHM-056 — Run the agent verification smoke: Tooling row check + Preview conversation + insurance footage
- **Phase:** Task 9 — Ohm_Auditor agent
- **Status:** Todo
- **Deliverable:** Executed §G.1 verification checklist: (1) Tooling query asserts the apex-bound action rows; (2) scripted Agent Builder Preview conversation exercising all 4 topics (orchestration run, recommendation phrasing + `PersistAuditReport` write-back, remediation task, methodology defense answering "how did you estimate this?" from the W4 action); (3) recorded insurance footage of the working conversation.
- **TDD test first:** Non-code — observable verification: the scripted conversation transcript shows the planner invoking the expected actions per topic and narrating from `summary` fields only (no invented numbers — narratives numeral-free per W4).
- **Done when:** All three verifications pass; footage catalogued; manual smoke logged in `PROJECT_STATE.md` (§D Task 9).
- **Depends on:** OHM-054, OHM-055
- **Est:** 1h
- **Win-tag:** W1

---

## Task 10 — Accessibility tests (sa11y, both variants)

### OHM-057 — Add the sa11y gate: `toBeAccessible()` on all 12 components in both Calm variants
- **Phase:** Task 10 — a11y tests
- **Status:** Todo
- **Deliverable:** For every one of the 12 LWC components, two `@sa11y/jest` tests (`calmMode=false` and `calmMode=true`) with fully populated fixtures: `await expect(el).toBeAccessible()`; any violation fails the suite.
- **TDD test first:** The 24 sa11y tests ARE the failing tests — written against current markup, then each violation fixed until zero axe violations remain (F9/NFR-2).
- **Done when:** 0 axe violations across all 12 components × both variants (§0.3 Task 10 gate); suite wired into `npm run test:unit`.
- **Depends on:** OHM-040, OHM-041, OHM-042, OHM-043, OHM-044, OHM-045, OHM-046, OHM-047, OHM-048, OHM-049
- **Est:** 2h
- **Win-tag:** —

### OHM-058 — Add targeted a11y assertions axe cannot catch
- **Phase:** Task 10 — a11y tests
- **Status:** Todo
- **Deliverable:** Targeted Jest assertions per §T.5: color+text pairing on `ohmEfficiencyRating` + `ohmUncertaintyBar`; new `stageMessage` lands inside the `aria-live` region; focus lands on the heading at each FSM transition; exactly one `<h1>` + no skipped heading levels across a WELCOME→IMPACT→RECOMMENDATIONS walk; Calm applied before first paint (no flash) and toggle calls `setCalmModePreference` exactly once.
- **TDD test first:** Each listed assertion written failing first (e.g. `test_singleH1AcrossWalk`, `test_focusOnHeadingPerTransition`, `test_noCalmFlashBeforeFirstPaint`), then fixed to green.
- **Done when:** All targeted assertions green alongside the sa11y gate.
- **Depends on:** OHM-057
- **Est:** 2h
- **Win-tag:** —

---

## Task 11 — Polish, UAT, and submission week (W2/W3/W8)

### OHM-059 — Stage the fix→re-audit demo loop (W3)
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** Rehearsable live beat: prepared trimmed-Scope patch for `Ohm_Fixture_LeadTriage` (drops below the soft threshold), applied on camera → re-run audit → `Efficiency_Grade__c` visibly moves (e.g. D→B) with the Wh savings delta; plus the reverse patch to reset the fixture between rehearsals.
- **TDD test first:** Non-code — observable verification: scripted run-through shows grade + `Total_Annual_Energy_Wh__c` change between the two audits on the report list view; timings fit the demo budget.
- **Done when:** Beat executes reliably in under its shot-list budget twice in a row; reset procedure documented.
- **Depends on:** OHM-010, OHM-037, OHM-056
- **Est:** 2h
- **Win-tag:** W3

### OHM-060 — Write the hook + close script with proud fixture disclosure (W2)
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** Demo script: 30s hook (IEA 415 TWh-doubling × agent-adoption stakes), energy-labels-changed-buildings close, and the on-camera fixture disclosure line ("we seeded a deliberately wasteful agent so you can watch Ohm catch it"), stored with the demo assets.
- **TDD test first:** Non-code — observable verification: read-through lands the hook inside 30 seconds and the disclosure beat is explicit, not defensive.
- **Done when:** Script timed, rehearsed once aloud, and versioned alongside the shot list.
- **Depends on:** —
- **Est:** 1h
- **Win-tag:** W2

### OHM-061 — Run the rehearsed Physical UAT (<3:00) + release gate
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** Executed §T.6 script (steps 0–8: Welcome → Start → four-signal findings → Impact bands → scrubber 50→150 → Recommendations → Calm toggle + reload → methodology → remediation task) against seeded fixtures, cold open, timer < 3:00; forced-ERROR degrade check (kill callout — no white screen); results logged in `PROJECT_STATE.md`.
- **TDD test first:** Non-code — the UAT script IS the test: every expected observable in the §T.6 table must match; release gate commands run first and green: `sf apex run test --test-level RunLocalTests --code-coverage` ≥75% org-wide (services ≥90%), `npm run test:unit -- --coverage` ≥80% + 0 sa11y violations.
- **Done when:** Green UAT < 3:00 with all observables met AND the full §D release gate satisfied (user gate: "Have we tested completely?").
- **Depends on:** OHM-056, OHM-058, OHM-059
- **Est:** 2h
- **Win-tag:** —

### OHM-062 — Produce the shot list with per-beat second budgets (W8)
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** Shot list mapping every demo beat (hook, start, discovery log + W6 invocation log ~5s, findings, impact + scrubber, W3 fix→re-audit, Calm beat 15s, methodology defense, close) to a second budget summing < 2:40 rehearsal target.
- **TDD test first:** Non-code — observable verification: dry-run against the timer hits every beat inside its budget.
- **Done when:** Shot list final, budgets sum under target, and it drives OHM-063.
- **Depends on:** OHM-060, OHM-061
- **Est:** 1h
- **Win-tag:** W8

### OHM-063 — Record the one unedited continuous take (W8)
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** Final submission video: one unedited continuous take with visible org clock + auto-refreshing report list view on screen, covering the full shot list including the W3 grade-move beat, W5 Calm beat, and W6 invocation log.
- **TDD test first:** Non-code — observable verification: playback review confirms continuity (no cuts), org clock visible throughout, every shot-list beat present within budget.
- **Done when:** Take approved on review; backup take retained; submitted Sep 6, never Sep 7.
- **Depends on:** OHM-062, OHM-059
- **Est:** 2h
- **Win-tag:** W8

### OHM-064 — Write the RAI Self Check as an artifact-mapping table + Known Limitations (W8)
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** RAI writeup structured as a check→artifact mapping table (each RAI claim mapped to its concrete artifact: cited constants in `Ohm_Constants`, `assumptions` disclosure, numeral-free `Agent_Narrative__c`, restricted picklists, confidence bands, `telemetryBacked=false`) plus an honest Known Limitations section (modeled volume, fixture evidence, sync callout limits).
- **TDD test first:** Non-code — observable verification: every row in the table names a checkable in-org or in-repo artifact; no claim lacks an artifact.
- **Done when:** Table + limitations complete and attached to the submission.
- **Depends on:** OHM-061
- **Est:** 2h
- **Win-tag:** W8

### OHM-065 — Assemble the accessibility evidence pack (W8)
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** A11y evidence pack: NVDA screen-reader clip walking S1→S4 + Calm toggle, sa11y CI output (0 violations, both variants), and the finding→fix→retest log from OHM-057/058.
- **TDD test first:** Non-code — observable verification: NVDA clip demonstrates heading focus per transition, the scrubber's `aria-valuetext`, and the polite live-region announcements.
- **Done when:** Pack assembled and attached to the submission.
- **Depends on:** OHM-057, OHM-058
- **Est:** 2h
- **Win-tag:** W8

### OHM-066 — Perform description surgery: name Headless Hero, and only Headless Hero (W8)
- **Phase:** Task 11 — Polish + UAT + submission
- **Status:** Todo
- **Deliverable:** Submission description rewritten: names **Headless Hero and only Headless Hero** using the WIN-STRATEGY framing verbatim ("pre-production observability — the inspection before the incident"), claims prior art, adds the AgentExchange/packaging paragraph and the callout-arithmetic scalability note.
- **TDD test first:** Non-code — observable verification: description read-through contains the Headless Hero paragraph, zero mentions of other special-award lanes, and the scalability arithmetic.
- **Done when:** Description final in the submission form; reviewed against the WIN-STRATEGY §"Special-award lane" text.
- **Depends on:** OHM-061
- **Est:** 1h
- **Win-tag:** W8

---

**Summary:** 66 tasks · ~96.5 estimated hours (T0 3.5h · T0.5 3h · T1 2h · T2 5h · T3 6.5h · T4 7h · T5 11.5h · T6 6h · T7 5h · T8 19h · T9 11h · T10 4h · T11 13h).
**Critical path:** OHM-005 → OHM-006 → OHM-010 → OHM-014 → OHM-018 → OHM-019 → OHM-020 → OHM-028 → OHM-031 → OHM-034 → OHM-037 → OHM-054 → OHM-061 → OHM-063 (auth gate → agent-surface spike → fixtures → data model → DTO → client → discovery → signals → savings → persistence → pipeline → live agent → UAT → continuous take).
