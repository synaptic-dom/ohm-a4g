# Demo: retrieve, review, improve

OHM audits **published Agent Script bundles**, including active prompt-template text referenced by their actions. The Salesforce Prompt Builder reviewer assesses instruction meaning and agent setup. Apex verifies evidence and assigns four independent ratings. Standalone prompts, legacy agents, Flow implementations and Apex implementations remain outside the audit scope.

Use scratch alias **ohm-audit-lab**, expiring **September 13, 2026**:

```sh
sf org open --target-org ohm-audit-lab --path '/lightning/n/Ohm_Audit?c__scope=agentScript'
```

The four demo bundles are `ActionDefinitions_v1`, `ActionChaining_v1`, `PromptTemplateActions_v1` and `Ohm_Weather_Demo_v4`. The prior retrieval baselines were preserved while fresh environmental reviews were added. Published agents were not replaced or reset.

## Suggested demo sequence

1. **Fleet:** introduce the four published bundles. Read their Input, Output, Model and Calls ratings independently. An older report without the Salesforce review says **Review not run**.
2. **Prompt Template Actions → Re-audit:** show application-driven source retrieval, version verification and the Salesforce review. Retrieval can take a minute or more. Leaving the page or refreshing resumes the same queued run.
3. **Efficiency review:** explain the four categories and their environmental consequences. A means no supported material issue in the available source; B is an improvement candidate; C is a defined rule violation; Unrated means required evidence is missing. A known model name does not prove model suitability.
4. **Instruction and prompt reviews:** expand **Generate Personalized Schedule**. Its current **Calls B** opportunity recommends evaluating code for overlap checks, minimum free-time gaps and chronological ordering while keeping the model responsible for presentation. Show the exact quoted constraints, retrieved source identity, character count and approximate tokens. Read what to preserve and how to validate the change. The linked prompt belongs to this bundle; it is not a separate audit target.
5. **Bundle setup recommendations:** show any cross-instruction or configuration issues with their evidence. **Bundle structure** displays agent/topic/action ownership. It is not a runtime execution trace.
6. **Ask OHM:** ask it to explain the saved ratings or recommendations. This answer reads the accepted review without another model call. A draft instruction change is a separate, explicit action that still needs review.
7. **Improve and re-audit:** apply and publish an approved change manually in Salesforce, then re-audit. OHM checks the new publication and linked prompts before accepting the result. Preserve required behavior and test it; shorter text alone is not success.

## Talk track

“Salesforce reviews the meaning of the prompts and the visible agent setup. Code computes the facts, checks exact source quotes and assigns the ratings. The environmental categories explain where unnecessary input, output, model capacity or calls could increase compute. These are supported recommendations to validate, not measurements of energy saved.”

For the schedule prompt, preserve the resort activities, chronological order, absence of overlaps, minimum gaps and guest booking invitation. Source token counts are approximate, not actual runtime usage. Crossing a soft review budget alone does not establish unnecessary text or downgrade the new category rating.

## Evidence and limits

The new review appears first. Existing size detectors and modeled footprint estimates remain under **Supporting evidence**. Their older overall Incomplete label reflects missing execution evidence and is separate from the four category ratings.

Model quality evaluation, runtime call frequency and output-token telemetry remain unavailable. Model fit can therefore remain Unrated even when other source categories are assessed. Never claim measured energy, water or carbon savings from these ratings.

See [review implementation and validation](ENVIRONMENTAL-REVIEW-2026-09-07.md), [retrieval evidence](LIVE-RETRIEVAL-2026-09-07.md), and [connection setup](LIVE-SOURCE-SETUP.md). Fresh live review results and test evidence are recorded under [environmental review results](results/2026-09-07/environmental-review/).

## Repeating setup

- The Salesforce reviewer template must be active, and the user running the audit needs **Execute Prompt Templates** through the standard Prompt Template User permission set.
- Live retrieval uses the existing External Client App, Named Credential and encrypted External Credential. Local source imports are not part of this demo.
- A failed generation, invalid response or changed publication stops the audit and preserves previous completed results. Resolve the reported issue before retrying.
- The reset script `scripts/testing/refresh-demo-data.py` remains available with its scoped backup and plan check; no further reset is needed for this demo.
