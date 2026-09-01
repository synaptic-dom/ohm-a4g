# Requirements: Ohm — Agentic AI Sustainability Auditor

**Phase:** 1 — Requirements
**Status:** DRAFT (v2, reframed) — awaiting approval gate ("Requirements complete?")
**Author:** Dom (solo)
**Date:** 2026-09-01 (Sep 1 checkpoint)
**Supersedes:** the "self-receipting chat agent" framing in `CONCEPT-BRIEF.md`.
**Deadline:** Sep 7, 2026, 5:00 PM PT (hard close). Target submit: Sep 6.

---

## 1. Product in one line

**Ohm is an agentic auditor for your org's AI.** It welcomes you into a guided
experience, discovers *every* piece of agentic work in a Salesforce org, analyzes and
documents each one, gives a readout of its efficiency, estimated usage, and impact on
the planet, and then hands back specific ideas to make those systems leaner.

> The agent that watches the agents. Discover → Analyze → Impact readout → Recommend.

## 2. Shape of the app (confirmed decisions)

- **Surface:** a **Lightning app page built from LWC** — a guided, screen-based experience, not a chat panel.
- **Engine:** **hybrid** — an **Agentforce agent underneath** performs the discover / analyze / recommend reasoning; the LWC screens are the experience shell on top. (This keeps it a genuine *Agentforce* build — Builder Track premise — and makes "watches the agents" literally true.)
- **Audit target:** **real agentic work in the provisioned org**, via metadata reads. Seeded/fixture systems are a fallback only if metadata access is limited.
- **Feature reset:** planetary-impact estimate is the **heart**. The old per-answer receipt, running org tally, and high-resistance twin are **dropped as core**. **Calm Mode / accessibility rides along** as an experience mode.

## 3. The experience (screens)

| Screen | Name | What happens |
|--------|------|--------------|
| **S1** | **Welcome / entry** | AI-native greeting orients the user and invites them to begin. "Let's find out what your org's AI is costing the planet." Single clear CTA to start the audit. |
| **S2** | **Discover & analyze** | The agentic auditor scans the org, finds all agentic systems, and documents each — visible progress as it works. |
| **S3** | **Impact readout** | Per-system and org-wide: an **efficiency rating**, **estimated usage**, and **estimated planetary impact** (energy / water / CO₂e) with uncertainty bands. |
| **S4** | **Recommendations** | **Specific, concrete** efficiency-improvement ideas per system, each with an estimated savings figure. Optionally persist a recommendation as a task. |

## 4. What counts as "agentic work" (discovery scope)

Ohm should discover, at minimum:
1. **Agentforce agents** (planner/bot bundles, topics, actions).
2. **Prompt Builder templates** (GenAI prompt templates).
3. **Flows that invoke prompts / generative steps.**
4. **Einstein generative features** where discoverable via metadata.

*Depends on metadata API read access — see Risk R1.*

## 5. Scope (MoSCoW)

| ID | Capability | Priority | Notes |
|----|-----------|----------|-------|
| F1 | **Welcome experience** (S1) LWC | **MUST** | Sets the frame; first thing judges see. |
| F2 | **Discovery** of agentic work from real org metadata (S2) | **MUST** | Protected core. Fixture fallback per Risk R1. |
| F3 | **Per-system analysis + documentation** — four waste signals | **MUST** | Signals: LLM-where-deterministic, model right-sizing, instruction bloat, redundant call patterns. |
| F4 | **Impact readout** (S3) — efficiency rating + estimated usage + energy/water/CO₂e with uncertainty | **MUST** | The sustainability heart. Backed by `EstimateFootprint`. |
| F5 | **Recommendations** (S4) — specific improvement ideas + estimated savings | **MUST** | The prompt's "empower action" clause. |
| F6 | **Agentforce agent** powering discover/analyze/recommend | **MUST** | The hybrid requirement — makes it an Agentforce build. |
| F7 | **Persist audit as records** — `Agent_Audit_Report__c` per system | **SHOULD** | Judges exploring the org find real artifacts. |
| F8 | **Create remediation task** from a recommendation | **SHOULD** | One-click assess→act. |
| F9 | **Calm Mode / accessibility mode** — persistent per-user preference | **SHOULD** | Accessibility award lane; nearly free. |
| F10 | **"How do you estimate this?"** methodology defense in-experience | **SHOULD** | Responsible-AI lane + estimation-credibility mitigation. |
| F11 | **LWC visual polish** — charts, sparkline, receipt-card styling | **COULD** | Baseline screens are MUST (F1–F5); this is refinement. |

### 5.1 Out of scope (cut from the brief)
- Self-receipting of Ohm's own chat replies; running org tally; high-resistance twin agent.
- General carbon Q&A / mock sustainability dataset.
- Net Zero Cloud integration.
- Any pre-Aug-28 code (New Work Only) or non-solo assistance.

### 5.2 Cut order (if schedule collapses)
1. **Degrade first:** F11 polish → F10 methodology → F9 Calm Mode → F8 tasks → F7 record persistence.
2. **Discovery fallback:** real-org live discovery (F2) → seeded fixture systems if metadata access blocked.
3. **Never cut (demo spine):** S1 Welcome, S3 Impact readout (F4), S4 Recommendations (F5), and the Agentforce agent (F6).

## 6. Data requirements
- **`Agent_Audit_Report__c`** — per discovered system: name/type, efficiency rating, estimated usage, energy/water/CO₂e (with band), findings across the four signals, timestamp.
- **Recommendation / remediation task** — what to change, estimated savings, link to report (F8).
- **Calm Mode preference** — per-user field, persisted across sessions (F9).

## 7. Acceptance criteria
- **AC-F1:** Loading the app shows a welcome screen that orients the user and offers a single clear "start audit" action.
- **AC-F2:** Running discovery against the provisioned org returns a list of real agentic systems (≥ the Agentforce agents present); each is documented (name, type, key attributes). Bulk-safe metadata reads.
- **AC-F3:** Each discovered system receives an analysis scoring it on the four waste signals, with human-readable documentation of what was found.
- **AC-F4:** For each system and org-wide, the readout shows an efficiency rating, estimated usage, and energy/water/CO₂e as ranges derived from published research + per-model constants. `EstimateFootprint` is unit-tested against known inputs; Apex coverage ≥ 75% (target higher).
- **AC-F5:** For each finding, the recommendations screen shows a specific change and an estimated savings figure.
- **AC-F6:** Discovery/analysis/recommendation reasoning is executed by an Agentforce agent (not hard-coded UI logic), invoked from the experience.
- **AC-F7:** Completing an audit creates persistent `Agent_Audit_Report__c` records (one per system), explorable in the org.
- **AC-F8:** From a recommendation, a single action creates a task record with change description, savings estimate, and report link.
- **AC-F9:** Enabling Calm Mode once yields low-stimulation, screen-reader-structured, color-independent output on every subsequent visit without re-requesting.
- **AC-F10:** Asking how an estimate is derived returns the methodology (research basis, assumptions, uncertainty).
- **AC-Demo:** The spine (Welcome → Discover/analyze → Impact readout → Recommendations) is demonstrable live within a 3-minute window of the 5-minute video.

## 8. Non-functional requirements
- **NFR-1 (Bulkification):** All Apex bulk-safe; no SOQL/DML in loops; governor-limit conscious.
- **NFR-2 (Accessibility):** Baseline accessibility on every screen; no meaning by color alone; content structured for screen readers.
- **NFR-3 (Responsible AI):** Every impact figure carries uncertainty; methodology interrogable live and shipped as a document with sensitivity analysis.
- **NFR-4 (Practices what it preaches):** The auditor itself uses deterministic routing where no LLM is needed, small model to classify, large only to synthesize, concise outputs.
- **NFR-5 (Performance):** The experience should complete a demo-scale audit fast enough to fit the 3-minute window (may pre-warm / stage where a live scan is slow).

## 9. Risks
- **R1 — Metadata access for discovery (critical).** Discovering real agentic work (agents, prompt templates, flows, Einstein) needs metadata API reads; scope/availability in the provisioned org is unverified. *Fallback: seeded fixture systems + export-based discovery.*
- **R2 — No org provisioned yet (critical, blocking).** As of Sep 1, no org exists. Provisioning + Agentforce enablement + CLI auth is the prerequisite for all of F1–F10 and the **first task after Requirements**.
- **R3 — Estimation credibility.** Mitigated by full-rigor methodology, uncertainty bands, and in-experience "how do you estimate this?".
- **R4 — Timeline.** ~5 working days to hard close; cut order (§5.2) assumed in effect from the start.

## 10. Definition of Done (Requirements phase)
- [ ] Reframed concept, screens, and scope confirmed by Dom.
- [ ] Acceptance criteria agreed as testable.
- [ ] Gate: "Requirements complete?" → approved → proceed to Design (`docs/design/DESIGN-ohm.md`), whose **first task is resolving R2 (org provisioning)**.
