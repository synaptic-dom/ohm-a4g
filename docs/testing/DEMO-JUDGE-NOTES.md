# Ohm — judge notes and verified facts (September 7 evening)

Companion to the demo script. Not for narration.

## Before recording

- Hard-refresh twice. Start on Overview, selector on 300, scrolled to the top.
- Confirm the strip figures match the table below. Every spoken number says "about".
- Keep Ask Ohm on the saved-review explanation; do not request a draft on camera.
- If the live re-audit fails with "Reviewer evidence does not match", it refused a review it couldn't verify. Start it once more; never claim it finished if it hasn't.

## Expected on-screen figures at 300 requests a day

| Bundle | Input | Output | Calls | Avoided a year | Footprint a year |
| --- | --- | --- | --- | --- | --- |
| Customer Support | C | A | A | 19.2 kWh, 51% | 37.8 kWh |
| Sales Follow-up | A | B | A | 4.43 kWh, 19% | 22.8 kWh |
| Schedule Planning | A | A | B | 6.09 kWh, 25% | 24.5 kWh |
| Efficient Schedule Desk (control) | A | A | A | none recommended | 23.0 kWh |
| All four | | | | 31.9 kWh, 30%, 9.58 kg CO2e, 34.5 L water | 108 kWh |

At 10k requests a day the fleet figure is about 1.06 MWh avoided a year.

## If a judge asks

- **Is the energy measured?** No. Nothing in the platform reports watt-hours. Ohm models energy from source tokens using published per-prompt figures plus grid and water factors, and lists every one next to the number. What is measured is tokens: 372 to 137 input tokens per request for the biggest fix, on GPT 5.5.
- **Where do the constants come from?** Energy per 500-token prompt 0.27 Wh, band 0.24 to 0.30, Epoch AI 2025 median for GPT-4o-class models. Grid 0.30 g CO2e per Wh, band 0.125 to 0.475. Water 1.08 mL per Wh, band 0.8 to 1.4. Confidence labeled Low, methodology 1.0.
- **Why 300 a day?** The model's own scenario, 50 sessions times 6 turns. The selector lets you name any volume and see the number scale.
- **Who reviews?** Salesforce Prompt Builder on GPT 5.5. Apex verifies every quoted passage against the retrieved published source and applies fixed rating rules. A review whose quotes don't match is rejected atomically.
- **Does Ohm change my agents?** Never. It reads published source through a same-org connection, recommends, and creates a Task. People change and publish source.
- **Why Service agents?** The trial org isn't licensed for the Employee Agent template. Ohm reads planner definitions regardless of type.
- **Is the control cheating?** The reviewer didn't know it was a control. It earned straight A's from the evidence and the app recommended nothing.
- **What's Model Fit?** A fourth category the reviewer records but the UI hides because there is no model-quality evidence yet.

## Receipts

- App deploy `0Afaj00000jW4o9CAC`, 283/283 tests. Footprint feature `0Afaj00000jWHtRCAW`, 285/285 tests, plus LWC follow-ups `0Afaj00000jWBGACA4` and `0Afaj00000jWIZNCA4`. Jest 27 suites, 217 tests.
- Current saved reviews: Support `a00aj00003WVlczAAD`, Sales `a00aj00003WVl59AAD`, Schedule Planning `a00aj00003WVl5AAAT`, Schedule Desk `a00aj00003WVl57AAD`. Reviewer `sfdc_ai__DefaultGPT55`. Verified in `docs/testing/results/2026-09-07/event-org/review-results-gpt55.json`.
- Measured tokens: `docs/testing/results/2026-09-07/event-org/measured-tokens-gpt55.json`. Evals: `docs/testing/results/2026-09-07/event-org/evals-gpt55/`.
