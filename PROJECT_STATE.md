# PROJECT_STATE.md — Ohm (source of truth)

**Product:** Ohm — agentic AI sustainability auditor (LWC guided experience + Agentforce agent underneath).
**Hackathon:** Agentforce for Good, Dreamforce 2026, Builder Track, Earthforce prompt. **GOAL: WIN.**
**Deadline:** submit **Sep 6** (hard close Sep 7, 5:00 PM PT). Showdown Sep 16.
**Org:** `ohm` — EPIC OrgFarm (00Daj000013wTtpEAE), Enterprise, API v67.0, expires Oct 7 (post-hackathon, non-blocking).

## Current phase
**Backlog — COMPLETE, awaiting final gate** ("Ready to implement?")

| Phase | Status | Artifact |
|---|---|---|
| 1. Requirements | ✅ Approved (reframed v2: guided auditor experience) | `docs/requirements/REQUIREMENTS-ohm.md` |
| — Capability spike | ✅ Done — GO; Agentforce **enabled by us** (Playwright terms + metadata deploy + 4 PSLs); discovery surfaces confirmed | `docs/design/SPIKE-ohm.md` |
| 2. Design | ✅ Approved | `docs/design/DESIGN-ohm.md` |
| 3. Spec | ✅ Approved (incl. win amendments W1–W8) | `docs/specs/SPEC-ohm.md` (C0–C13 canon locked) |
| 4. Backlog | ✅ Written (66 tasks, ~96.5h est), gate pending | `docs/backlog/BACKLOG-ohm.md` |
| 5. Execute (TDD) | Not started | — |
| 6. Physical UAT | Not started | UAT script in SPEC §T.6 |
| 7. Document/submit | Not started | Submission checklist in CONCEPT-BRIEF |

## Side artifacts
- `docs/design/SKILLS-SHORTLIST-ohm.md` — top-10 tools/skills research (DX MCP, GenAiPlannerBundle, sa11y, …)
- `docs/design/WIN-STRATEGY-ohm.md` — judge-panel result: **69.5/100 as originally planned → ~78 with amendments W1–W8** (now locked into SPEC §0.4). Target: 2nd/3rd podium + **Headless Hero** (name it and only it). Key finding: original cut order sacrificed the award thesis; F10 + F9 are now spine, agent spike moved to day 1.

## Build order (SPEC §0.3 as amended by §0.4)
Task 0 auth gate (BLOCKING) → **0.5 agent-surface spike (W1)** → 1 smoke deploy → 2 fixtures → 3 data model → 4 discovery → 5 signals (a,c protected) → 6 footprint → 7 persistence → 8 LWC spine (incl. Calm Mode W5, provenance W7) → 9 agent full build (W4 grounded methodology, W6 dogfood staging) → 10 a11y → 11 polish/UAT (W3 fix→re-audit beat, W2 hook). **Never cut:** Welcome, Impact, Recommendations, agent, F10 methodology, F9 Calm Mode.

## Key facts for any session resume
- All `sf` CLI calls via **PowerShell tool** (Bash can't invoke sf). `sf org display` output = secret.
- Agentforce IS enabled; org is **empty** — fixtures are Task 2.
- Canonical contracts live in SPEC §0.2 (C0–C13); they override any conflicting text.
- Tooling self-callout via Named Credential `Ohm_Self` is **Task 0 and blocking** — HTTP 200 on `GenAiPlannerDefinition` query = pass (row count irrelevant).

## Blockers
None. (Task 0 is the first risk to retire in Execute.)

_Last updated: 2026-09-01 — after spec synthesis + canon reconciliation._
