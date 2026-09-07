# Ohm technical completeness review

Reviewed September 6, 2026, against GitHub `main` at `038b5a0`, after fast-forwarding the local checkout. This review covers the current Fleet Workbench implementation; the original concept brief has been superseded in several areas.

**Assessment:** substantial working implementation, with unfinished audit data collection, incorrect impact accounting, and gaps in the remediation lifecycle. The `PROJECT_STATE.md` statement that code work is done is stronger than the code supports.

**Live-test follow-up:** after this source review, created `ohm-audit-lab` and published three external Salesforce recipes. Existing Apex tests pass **125/125**; new acceptance checks pass **1/10**. All three public agents return A/100 with zero discovered topics/actions despite populated platform relationships. Actual instruction-source access and a substring-based false positive are additional confirmed gaps. See [the demo-prioritized fix plan and evidence](../testing/DEMO-FIX-PLAN-2026-09-06.md), which supersede the source-only verification limits and implementation order below. One direct Models API request also succeeded; a complete browser/edit/re-audit rehearsal remains unverified.

## Verification and limits

- Read Apex discovery, detectors, footprint calculations, persistence, controller, assistant, permission sets, LWC routes and workflows, and relevant tests/specifications.
- Installed locked dependencies with `npm ci`. All **23 Jest suites / 161 tests passed**.
- No authenticated `ohm` org is available on this machine. Apex tests, deployed permissions, and live browser behavior were not independently rerun. Previously claimed Apex coverage and demo results are repository documentation, not fresh verification.
- Recomputed the checked-in waste fixture's footprint using its XML text and the JSON constants. This was a static calculation, not execution of Apex.
- No application code was changed. This document records confirmed source-level defects and clearly identified product completeness gaps.

## 1. High — Footprint totals measure flagged findings rather than the process

The audit calculates a footprint only for findings. Report energy is a roll-up of those findings, so a process with no findings has zero reported energy even when it continues making model calls. Multiple findings concerning the same inference can also count its cost more than once.

The checked-in waste fixture illustrates the problem: the current model gives **82,486.35 Wh/year**, with **52,921.35 Wh/year** estimated savings from reducing the instruction budget to 500 tokens. The same model retains **29,565 Wh/year** at that budget. If the trim removes all findings, the report instead falls to zero, overstating the before/after improvement.

Evidence: [per-finding calculation](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:192), [report roll-up](/Users/dom/Documents/ohm-a4g/force-app/main/default/objects/Agent_Audit_Report__c/fields/Total_Annual_Energy_Wh__c.field-meta.xml:5), [within-budget findings omitted](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/InstructionBloatDetector.cls:56).

Completion requires a process baseline independent of findings, distinct avoidable-waste estimates, and combined savings calculations that handle overlapping fixes. Actual usage collection is also absent: every audit uses the same assumed **109,500 calls/year**, and the engine explicitly marks results as non-telemetry-backed. That limitation is acceptable for a scenario model if the UI clearly exposes it.

## 2. High — Discovery depends on demo naming conventions

Per-process discovery assigns topics and actions by matching words in their developer names to a planner's name. It does this even though the query selects relationship fields. Unmatched components are dropped; ambiguous names are resolved by a heuristic rather than verified ownership. Two planners sharing a key can force a full-name fallback that no child name matches.

Consequently, ordinary agents with independently named or shared components can have incomplete or incorrect inventories and call graphs. The current fixture layout does not establish general fleet support.

Evidence: [name-based matching](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmDiscoveryService.cls:241), [collision fallback](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmDiscoveryService.cls:225), [topic filtering](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmDiscoveryService.cls:402), [action filtering](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmDiscoveryService.cls:425).

Completion requires authoritative relationships where available, an explicit mapping/import mechanism where unavailable, and visible warnings for unassigned or ambiguous components.

## 3. High — Missing detector evidence can produce confident results

Model discovery never populates `boundModel`. The redundant-call detector skips agents with empty graph data. The grading service gives 100/A when there are no findings, without distinguishing complete coverage from missing evidence or detector failure. An A therefore does not establish that all four checks passed.

There is also a direct contradiction in the unknown-model path: the detector emits an informational finding described as having no savings, but recommendation generation converts it into “The bound model is larger than this task requires,” recommends SMALL, and calculates savings. With default assumptions, that becomes **14,782.5 Wh/year** despite the original model being unknown.

Evidence: [absent model binding](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmDiscoveryService.cls:125), [missing graph skipped](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/RedundantCallDetector.cls:22), [no-findings A](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmSignalService.cls:65), [unknown-model finding](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/ModelRightSizingDetector.cls:34), [unconditional recommendation](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmRecommendationService.cls:28), [assumed multiplier savings](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmFootprintService.cls:100).

Completion requires per-detector coverage states, no positive savings claim without its required evidence, and grade handling for incomplete audits. A separate registry defect also needs correction: GPT4/OMNI/4O matching precedes MINI/NANO, so `sfdc_ai__DefaultGPT4OmniMini` is classified LARGE. See [classification order](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/ModelRegistry.cls:61).

## 4. High — Findings do not survive re-audits correctly

The worklist chooses the latest report by examining finding records, rather than report records. A new clean report has no finding records, so it cannot displace the prior report: resolved problems can remain in Findings and Recommendations.

If a problem remains, the new audit inserts a new finding. Its previous status, owner, due date, and task association are not carried forward. The worklist displays the new Open/unassigned instance while the existing Task remains attached to an older finding.

Evidence: [latest report inferred from findings](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:370), [new findings inserted every audit](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmPersistenceService.cls:75), [status/task read from new row](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:426).

Task status synchronization is incomplete as well: the read query omits `Task.Status`, and setting a finding back to Open does not reopen its completed Task. See [Task read](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:435) and [status write](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:483).

Completion requires stable issue identities across audit snapshots, preserved task ownership/lifecycle, and explicit reconciliation when an issue disappears.

## 5. High — Org Trends can invent savings by comparing different agents

With no fleet-wide reports, Org Trends takes the latest report for each planner and presents those different agents as successive points in one time series. It then subtracts the last point from the first and labels a positive result “realized savings.” Auditing Agent A at 80,000 Wh/year and Agent B at 10,000 Wh/year can therefore display 70,000 Wh of savings without any improvement to either agent.

If fleet-wide reports exist, newer per-process audits do not update that org series; they only update the separate grade histories.

Evidence: [fallback mixes planner reports](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:650), [first-minus-last savings](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:829), [user-facing claim](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmTrends/ohmTrends.html:148).

Completion requires comparable org snapshots over time, consistent scope, and a distinction between modeled improvement and measured realized savings.

## 6. High — Long instruction rewrites silently lose source material

The assistant truncates the selected instructions to 8,000 characters before asking the model to rewrite them. It presents a draft without disclosing that suffix rules were excluded, and calculates the “before” size from the truncated source. Rules beyond the cutoff cannot be reliably preserved by this flow.

Evidence: [source truncation](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAssistantService.cls:247), [draft uses truncated input](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAssistantService.cls:416), [before-size calculation](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAssistantService.cls:107).

Completion requires preserving the full source, accurate original counts, and either a complete-input rewrite strategy or a clear refusal/partial-result state when the source exceeds the supported limit.

## 7. High for non-admin rollout — Shipped permission sets omit Apex class access

`Ohm_App_Access` grants app/tab visibility; `Ohm_Data_Access` grants object/field permissions. Neither grants Apex class access to `OhmAuditController`, the entry point used throughout the LWC app. Assigning these sets alone does not make the app functional for a non-admin whose profile lacks that access.

Evidence: [app permission set](/Users/dom/Documents/ohm-a4g/force-app/main/default/permissionsets/Ohm_App_Access.permissionset-meta.xml:2), [data permission set](/Users/dom/Documents/ohm-a4g/force-app/main/default/permissionsets/Ohm_Data_Access.permissionset-meta.xml:2). Salesforce explicitly requires profile or permission-set access to an `@AuraEnabled` class: [Secure Apex Classes](https://developer.salesforce.com/docs/platform/lwc/guide/apex-security).

Completion requires a deployable permission package and verification with a representative non-admin user. This review does **not** infer a CRUD/FLS bypass from missing explicit user-mode clauses; the repository uses API 67.0 and current Salesforce documentation changes the default behavior at that version.

## 8. Medium — The fix workflow stops at advice, copy, and Task creation

Inspector fix buttons open recommendation text and offer a Task. Ask Ohm offers a copyable draft. There is no target-specific Builder handoff, apply operation, or Keep/Revert implementation. The spec permits manual application as a fallback, so this is a product completeness gap rather than proof that a promised automatic API is broken.

The diff has a separate correctness gap: instruction snapshots exist only on bloat findings. When a successful trim removes the finding, the AFTER instructions disappear. With multiple bloated nodes, selecting one snapshot per report can also compare different artifacts.

Evidence: [fix CTA handler](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmNodeInspector/ohmNodeInspector.js:227), [copy draft](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmAskAssistant/ohmAskAssistant.js:160), [diff loads finding-only snapshots](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:730).

Completion requires a clear handoff to the exact editable artifact, verification after the external change, and report-level snapshots keyed by artifact independent of whether it still has findings.

## 9. Medium — Footprint transparency components are disconnected from v2

The current app mounts the v2 route tree. Existing water/CO2, uncertainty, methodology, and volume controls remain in older components but are not reachable through these routes. Users see central annual energy figures without the promised explanation of assumptions or an adjustable usage scenario.

Evidence: [current app routes](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmApp/ohmApp.html:47), [old volume/readout components](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmImpactReadout/ohmImpactReadout.html:29), [old methodology entry](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmImpactReadout/ohmImpactReadout.html:54).

Completion requires wiring the explanation and uncertainty into the current screens. Passing tests for unreachable components does not establish that these features ship in the workbench.

## 10. Medium — The team backlog supports only initial self-assignment

The worklist hardcodes the current user when assigning. Once any owner is present, it hides the assignment/due-date form and labels the task “Yours,” even for another owner. Tasks created from Recommendations already have an owner, leaving no workbench path to add their due date or reassign them. Findings and recommendation cards also lack the specified navigation to the owning process/node.

Evidence: [current-user assignment](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmFindingsWorklist/ohmFindingsWorklist.js:235), [assigned state](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmFindingsWorklist/ohmFindingsWorklist.js:106), [controls hidden once assigned](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmFindingsWorklist/ohmFindingsWorklist.html:116).

Completion requires editable owner/due fields, correct ownership labels, and navigation from an issue to its audited artifact.

## 11. Medium — Calm Mode does not complete the accessibility behavior

The preference persists and colors change, but the new assistant still animates its thinking dots and spinner. Its Calm overrides do not disable those animations, and the v2 styles do not implement the reduced-motion behavior promised in the spec. The assistant request path also does not use the saved preference to change answer structure or reading level.

Evidence: [thinking animation](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmAskAssistant/ohmAskAssistant.css:231), [Calm color overrides](/Users/dom/Documents/ohm-a4g/force-app/main/default/lwc/ohmAskAssistant/ohmAskAssistant.css:379), [assistant entry point](/Users/dom/Documents/ohm-a4g/force-app/main/default/classes/OhmAuditController.cls:772).

Completion requires applying the preference to motion and response presentation, then checking the actual interactive screens with reduced motion and assistive technology.

## Suggested implementation order

1. Correct footprint baselines, coverage/unknown states, and Org Trends before relying on the numbers.
2. Fix issue identity across re-audits, clean-audit reconciliation, and Task synchronization.
3. Make discovery portable beyond the fixtures; complete model/runtime evidence integration.
4. Fix long-input rewriting and retain comparable artifact snapshots through successful remediation.
5. Finish non-admin setup, the manual fix handoff, methodology access, team editing, and Calm behavior.

Add regression coverage around these concrete transitions. Existing tests largely establish individual calculations and UI states; they do not establish the full audit → assign → change → re-audit → reconcile workflow. Several Apex integration tests require the pre-existing `Ohm_Waste_Demo` fixture with `SeeAllData=true`, so the passing result recorded in project state also depends on the prepared org.
