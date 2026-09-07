# Ohm — demo script

*[Overview, strip at the top]*

Hi, I'm Dom DeFazio, and this is Ohm.

Every time an agent runs, it reads its instructions, reads its prompts, and generates an answer. That's compute. Compute is electricity, carbon, and water. A lot of that work is necessary. A surprising amount of it isn't, and right now nobody can see which is which.

Ohm can. It reads the agents you've published in Agentforce, finds the work that doesn't need to happen, and shows you exactly what you get back when you fix it.

This org has four test Agent Script bundles. Ohm has already reviewed all of them. Apply the changes it found and, at three hundred requests a day, this fleet saves about thirty-two kilowatt-hours a year, thirty percent of everything it burns, plus the carbon and water that go with it.

*[click 10k]*

Turn the volume up to ten thousand requests a day and you're saving over a megawatt-hour a year. Same four agents. Same changes.

*[Bundles]*

Here's how it thinks. Ohm asks three questions about every agent. Is the model reading more than it needs? Is it writing more than anyone asked for? Is it doing work that plain code should be doing? Input. Output. Calls.

*[open a bundle, ratings]*

Open any agent and you get three grades, and right above them, what this agent stops costing when you fix it. A grade of A means it's clean. B means there's a change worth making. C means it's blowing through its budget.

*[Review this change]*

Click the recommendation and Ohm puts you on the exact lines of the published source it's talking about. What to change. What has to stay intact. How to test it. Nothing vague, nothing you have to go hunt for.

*[Ask]*

Ask Ohm anything about it and it answers in plain language, grounded in this source and this review.

*[Recommendations, Create task, Open task]*

Then it becomes work. Every recommendation in the org lands in one place. One click and it's a real Salesforce task with the evidence attached, so a builder owns it and the team can track it to done.

*[Re-audit]*

Ship the fix, hit re-audit, and Ohm pulls the new published source and grades it again, live. The numbers move when your agents move.

*[How it works tab]*

So that's what it does. Here's how it works.

Ohm is one hundred percent native Salesforce. It discovers every published Agent Script bundle in the org, then retrieves the exact published source and every prompt template those bundles call, through the Metadata API with its own connected app and named credential. Every artifact is pinned by hash, so a review can never drift from the source it's about.

The reviewer is a Prompt Builder template running GPT 5.5, called straight from Apex. It reads the source and returns findings with exact quotes. Then Apex takes over: it checks every quote against the pinned source, confirms nothing has changed since retrieval, applies the rating rules, and saves the whole review in one transaction. If anything fails to verify, nothing is saved.

Recommendations are generated from that saved review, and tasks are standard Salesforce tasks keyed to the review so they never duplicate. The footprint engine turns source tokens into energy, carbon, and water and scales with request volume. Ask Ohm runs on the Models API, also on GPT 5.5. The whole front end is Lightning Web Components, and the whole thing deploys as one package: Apex, LWC, one custom object family, one prompt template.

Agents for good should mean agents that do their job with less. Less energy, less carbon, less water. Same results. Ohm is built on Agentforce, for Agentforce, and it's running in this org right now.

I'm Dom. Thanks for watching.
