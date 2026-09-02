# SPEC-ohm-v2 — The Fleet Workbench

**Version:** 2.0 · **Date:** 2026-09-02 · **Status:** DRAFT — awaiting sign-off
**Supersedes:** the v1 *experience* layer (single-scroll readout). **Keeps unchanged:** the v1 audit engine — discovery via inline SOQL, the four detectors, `OhmFootprintService`, `OhmSignalService`, `OhmRecommendationService`, `OhmPersistenceService`, `OhmDTO`, and the `Agent_Audit_Report__c` / `Finding__c` objects. This is an **IA/UX rebuild on a working core.**

> Reframe (from the design review): v1 is an *energy label* — it analyzes everything at once and hands back one read-only scorecard with nowhere to go. v2 is a **workbench**: you own a fleet of agentic processes, you **point at one**, see **what's actually inside it** (its call graph, its real instructions, its waste), and **act on that specific process** — then track it over time. Every decision below is from the design interview (2026-09-02).

---

## 1. Information architecture

Four top-level tabs in a dark "Instrument" **app console** (breadcrumbs + persistent context header throughout):

```
┌ Ohm ─────────────────────────────────────────────────────────────┐
│  FLEET   FINDINGS   RECOMMENDATIONS   TRENDS            [Calm ▢]   │
├───────────────────────────────────────────────────────────────────┤
│  Fleet › Lead Concierge › Lead Triage          (context breadcrumb)│
│                                                                    │
│   … active tab body …                                              │
└───────────────────────────────────────────────────────────────────┘
```

- **Fleet** — the home; the list of discovered processes and the drill-down into one.
- **Findings** — cross-fleet backlog of every waste finding, built on Salesforce Tasks.
- **Recommendations** — prioritized quick-wins (savings vs effort).
- **Trends** — footprint and grade over time, org-wide and per-agent.

Methodology (the constants/assumptions) moves from a top tab to an on-demand **"How this is estimated"** popover reachable from any footprint figure (keeps the promise of interrogable numbers without spending a tab).

**Grounding rules (Idea 7):** every screen carries a breadcrumb; the process page shows a context header (process name, domain, grade chip, last-audited); every empty state is an invitation, not a void ("No processes audited yet — pick one and run an audit").

---

## 2. Screens

### 2.1 Fleet (home) — Idea 1, 4

A navigable table of **discovered** processes. Discovery is **cheap** (metadata only — no signals, no footprint), so the fleet loads instantly; the deep audit is **per-target, on demand** (Idea 4 — "pick a target first").

```
FLEET  ┌──────────────────────────────────────────────────────────────────┐
       │ Process              Domain        Topics Actions  Status         │
       ├──────────────────────────────────────────────────────────────────┤
       │ Lead Concierge       Sales           1     1     ⬤ F  82,486 Wh ▸ │
       │ Order Support        Commerce        1     1     ⬤ C  45,648 Wh ▸ │
       │ Service Concierge    Cust. Service   1     1     ⬤ A     —      ▸ │
       │ Ohm Auditor          Internal        4     6     ⬤ A     —      ▸ │
       │ Billing Assistant    Finance         2     3     ○ Not audited  [Audit] │
       └──────────────────────────────────────────────────────────────────┘
       Filter: [domain ▾] [grade ▾]   Sort: [energy ▾]   Search: [______]
```

- **Row before audit (Idea 4 consequence):** name, domain, #topics, #actions, status **"Not audited yet"**, and an **Audit** button. No grade/energy until run.
- **Row after audit:** grade chip (hot→cool), org-annualized energy, click ▸ to open the process.
- Sort/filter/search across the fleet. A slim summary strip on top (fleet grade, total energy, # audited / # discovered) — the old aggregate readout, demoted to a header.

### 2.2 Process page — Idea 2, 5, 6 + assistant

Opened from a Fleet row. **Centerpiece = the call graph** (Idea 2). Node click → **instruction inspector with waste highlighted** (Idea 5). Process-specific fix CTAs (Idea 6). A per-process **AI assistant** panel (the Ohm_Auditor agent).

```
Fleet › Lead Concierge                                    ⬤ F · Sales · audited 2m ago
┌──────────────────────────────── call graph ────────────────┐ ┌── inspector ───────┐
│                                                             │ │ Lead Triage (topic)│
│      (Lead Concierge)                                       │ │ ⚠ Instruction bloat│
│           │                                                 │ │ High · 1,300 tok   │
│      ┌────┴─────┐                                           │ │ excess 800 over 500│
│   ⚠ Lead Triage   Classify Lead Tier                        │ │────────────────────│
│      │  (bloated)     (apex · ok)                           │ │ INSTRUCTIONS       │
│   (highlighted red node)                                    │ │ "You are the Lead  │
│                                                             │ │  Triage… ▓▓▓▓▓▓▓▓▓ │  ← excess
│                                                             │ │  ▓▓▓ friendly, pro-│    highlighted
│                                                             │ │  fessional…"       │
│                                                             │ │────────────────────│
│                                                             │ │ [Trim instructions]│
│                                                             │ │ [Downsize model]   │
│                                                             │ │ [Replace w/ Flow]  │
└─────────────────────────────────────────────────────────────┘ └────────────────────┘
┌── Ask Ohm (assistant) ────────────────────────────────────────────────────────────┐
│ ▸ Why is this wasteful?   ▸ Draft the trimmed instructions   [ ask… ]              │
└───────────────────────────────────────────────────────────────────────────────────┘
```

- **Graph:** agent → topics → actions; wasteful nodes flagged (amber/red), clean nodes quiet. Node = topic or action.
- **Inspector (node click):** the node's real `Scope`/instructions with the **excess tokens highlighted inline**, token count, bound model, `InvocationTargetType`, the finding, severity, and the fix.
- **CTAs (Idea 6):** **Trim instructions** (opens the text with the suggested trim, apply), **Downsize / swap model**, **Replace with Flow/Apex**. (Creating a tracked Task happens from Findings; re-audit lives in the fix loop §2.6.)
- **Assistant (per-process):** the `Ohm_Auditor` Agentforce agent, grounded in this process's data — "why is this wasteful?", "draft the trimmed instructions". Embedded Agentforce panel if it renders in-region ([UNCONFIRMED] — see risks); fallback is a custom chat LWC calling the agent's actions.

### 2.3 Findings — Idea 8 (native Task backlog)

A **full worklist built on the Salesforce Task object** (your call: "use task object btw but full worklist"). Each finding can be promoted to a Task with **owner + due date + status**; the tab is the team backlog.

```
FINDINGS  Open ▾   Severity ▾   Agent ▾   Sort: savings ▾
┌────────────────────────────────────────────────────────────────────────────┐
│ ⬤High  Lead Triage      Instruction bloat   saves 52,921 Wh  @Dom   Due 9/5 │
│ ⬤Med   Order Help       Instruction bloat   saves 16,083 Wh  —      [Assign]│
│ ✓Applied  …                                                                  │
└────────────────────────────────────────────────────────────────────────────┘
```

- **Status pipeline (via Task.Status + a Finding status):** Open → Accepted → Dismissed → Applied.
- **Assignment + due:** native `Task.OwnerId` + `Task.ActivityDate`. Reuses the existing `CreateRemediationTask` action; extends it into a two-way worklist (read Task state back onto the finding, update from the list).
- Filter by status/severity/agent; sort by savings/severity. Row → jumps to the owning process node.

### 2.4 Recommendations — quick-wins

The prioritized-fixes view: findings ranked by **savings ÷ effort**, grouped into "quick wins" (high savings / low effort) first. Each card carries the same three fix CTAs and a "create task" that lands in Findings.

### 2.5 Trends — Idea 10 (built now)

Org-wide and per-agent **footprint + grade over time**, sourced from the `Agent_Audit_Report__c` history (each audit is a datapoint).

```
TRENDS
  Org energy (Wh/yr)         ╭─╮
     ▁▃▅▇█▆▄▂  ← per audit    │ │  per-agent grade history: Lead Concierge  F F D … A
  Realized savings: 69,004 Wh across 3 applied fixes
```

- Org energy trendline across audits; per-agent grade history sparkbars; "realized savings" from applied fixes.
- Requires per-process audit records be **timestamped and tagged with their target** (§4).

### 2.6 Fix loop — Idea 9 (before/after diff)

Applying a fix + re-auditing that one process opens a dedicated **before/after diff view**:

```
BEFORE / AFTER — Lead Triage
  Instructions   5,400 chars ▓▓▓▓▓▓▓▓ →  380 chars ▓            (diff shown)
  Grade          F  →  A
  Energy         82,486 Wh/yr  →  0 Wh/yr        (−82,486)
  [Keep] [Revert]
```

- Old vs trimmed instructions (text diff), old vs new footprint side-by-side, the delta. Keep or revert. A new Trends datapoint drops on save.

---

## 3. Component inventory (LWC)

New / reworked, all in the dark workbench system:

| Component | Role | From v1 |
|---|---|---|
| `ohmApp` | Tab shell, routing, breadcrumb, context header, Calm context | new (replaces `ohmAuditExperience` FSM) |
| `ohmFleetTable` | Fleet list, filter/sort/search, per-row Audit | new |
| `ohmProcessPage` | Process detail layout (graph + inspector + assistant) | new |
| `ohmCallGraph` | The agent→topic→action graph, waste-flagged nodes | new |
| `ohmNodeInspector` | Instructions w/ highlighted excess, metrics, fix CTAs | new (absorbs receipt bits) |
| `ohmFindingsWorklist` | Task-backed backlog: status/assignee/due, filters | new |
| `ohmRecommendations` | Quick-wins ranked | reworked from v1 |
| `ohmTrends` | Trendlines + per-agent grade history | new |
| `ohmDiffView` | Before/after fix comparison | new |
| `ohmAssistant` | Per-process Ohm_Auditor agent panel | new |
| `ohmImpactReceipt`, `ohmEfficiencyRating`, `ohmUncertaintyBar`, `ohmVolumeScrubber`, `ohmMethodologyPanel`, `ohmCalmModeToggle` | reused as sub-components (footprint display, grade chip, methodology popover, calm) | **carry over** |

Design tokens, the amber-waste / teal-efficient semantics, tabular-mono data, and Calm Mode all carry over from v1.

---

## 4. Backend changes (Apex + data)

The engine carries over; the **entry points** change from "audit the whole org once" to "list the fleet cheaply, audit one target deeply, track over time."

**`OhmDiscoveryService`**
- Split `discover()` into: `listFleet()` → cheap: query `GenAiPlannerDefinition` + counts of child `GenAiPluginDefinition`/`GenAiFunctionDefinition` per planner (no signals, no footprint). Returns `List<ProcessSummaryDTO>` (name, domain, topicCount, actionCount).
- `discoverProcess(Id plannerDefId)` → deep: the existing tree build, scoped to one planner's subtree.

**`OhmAuditController`** (new/changed `@AuraEnabled`)
- `getFleet() : List<ProcessSummaryDTO>` — the Fleet table, joined with the latest audit result per process (grade/energy) where one exists.
- `auditProcess(Id plannerDefId) : Id` — deep audit of ONE process → signals + footprint for that subtree → persists a **process-scoped** `Agent_Audit_Report__c`. Returns the report Id.
- `getProcessDetail(Id plannerDefId) : ProcessDetailDTO` — graph + nodes + per-node findings/instructions for the process page.
- `getFindings(filters) : List<FindingDTO>` and `updateFinding(...)` / `assignFinding(...)` — the worklist, reading/writing the linked `Task` (owner, due, status).
- `getTrends(Id plannerDefId?) : TrendDTO` — time series from report history.
- `getDiff(Id beforeReportId, Id afterReportId) : DiffDTO` — before/after.
- Keep: `getCalmModePreference` / `setCalmModePreference`, `estimateFootprint`.

**Data model**
- `Agent_Audit_Report__c` gains **`Target_Type__c`** (Fleet | Process) and **`Target_Planner_Api_Name__c`** / **`Target_Planner_Id__c`** so a report can be scoped to one process → per-process trend = reports for that target over time. (Existing org-wide fields still work for a "Fleet" target.)
- `Finding__c` gains **`Finding_Status__c`** (Open/Accepted/Dismissed/Applied) mirrored to its `Task`; `Remediation_Task_Id__c` already exists. The worklist reads the `Task`'s `OwnerId`/`ActivityDate`/`Status`.
- No new objects required; Trends is a query over report history; before/after is two reports for the same target.

**Discovery cost note:** `listFleet()` must stay bulk-safe (a couple of SOQL, counts via aggregate) so the fleet loads instantly even for large orgs; the expensive per-node work only runs in `auditProcess`.

---

## 5. Visual direction

Dark **Instrument workbench** across the whole app (your call). The v1 tokens carry over: panel `#0E1518`, card `#16232A`, ink `#EAF2F0`, **filament amber `#FFB24C` = waste/energy**, **cool teal `#4FD1C5` = efficient/savings**, hot `#FF6B4A` = high severity, tabular-mono for all data. New surfaces (tables, tabs, graph) inherit these; the graph uses amber/teal to color nodes by waste. One signature per screen; everything else quiet. Calm Mode inverts the whole console to the light, color-independent treatment, exactly as v1.

---

## 6. What carries over unchanged (do NOT rebuild)
The four detectors, `OhmSeverity`, `TokenEstimator`, `ModelRegistry`, `VolumeProvider`, `OhmFootprintService` (bands + savings), `OhmSignalService.rate()` (grade), `OhmRecommendationService`, `OhmDTO` core types, `Ohm_Constants`, `Agent_Audit_Report__c` + `Finding__c` (extended, not replaced), and the seeded fleet fixtures. 99 Apex tests / 90% coverage stay green; new methods add tests.

---

## 7. Build sequence (proposed waves)
1. **Backend split** — `listFleet()` + `auditProcess(plannerId)` + process-scoped reports + data-model fields; tests. (Unblocks everything.)
2. **App shell + Fleet tab** — `ohmApp` tabs/breadcrumb + `ohmFleetTable` with per-row Audit. Deploy, verify a process audits from the list.
3. **Process page** — `ohmProcessPage` + `ohmCallGraph` + `ohmNodeInspector` (instructions + highlight + fix CTAs).
4. **Findings (Tasks) + Recommendations** — the Task-backed worklist + quick-wins.
5. **Trends + Before/after diff.**
6. **Assistant** — the Ohm_Auditor per-process panel (embedded or fallback chat).
7. **UI QA pass** (the adversarial vision review, like v1) + verify.

---

## 8. Risks / open items
- **Embedded Agentforce panel in-region** is [UNCONFIRMED] (same as v1). Fallback: a custom chat LWC that invokes the agent's actions. The assistant is Wave 6, so it doesn't block the core.
- **Graph rendering** — an agent→topic→action graph in LWC (SVG or a light lib). Fixtures are small, so layout is simple; large orgs need virtualization (defer).
- **"Trim instructions" applying a change** — writing a trimmed `Scope` back to a `GenAiPlugin` needs a metadata write (deploy) or Agent Builder; may be an assisted "here's the trim, apply in Builder" rather than a one-click org write ([UNCONFIRMED] whether we can deploy the edit from Apex). Decide during Wave 3.
- **Per-process re-audit + Trends** assume process-scoped reports; the data-model fields in §4 must land in Wave 1.

---

## 9. Definition of done (spec phase)
- [ ] Blueprint + screens confirmed by Dom.
- [ ] The three [UNCONFIRMED] risks acknowledged (assistant embed, graph lib, trim-write).
- [ ] Gate: "v2 spec approved? Start Wave 1?" → build.
