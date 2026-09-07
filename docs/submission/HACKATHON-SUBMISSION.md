# Dreamforce 2026 — Agents for Good submission answers

Copy-paste ready. Two fields marked **YOUR CALL** need your decision before you submit.

---

## Project Name

Ohm

---

## Problem to solve

Every Agentforce agent burns electricity, carbon and water every time it runs. It reads its instructions, reads its prompts, reasons, and generates an answer, and all of that is compute somebody is paying for in more than dollars.

A lot of that work is necessary. A meaningful share of it is not. A policy pasted six times into a prompt gets re-read on every single request. A prompt asked to produce eight variations when the user wanted one generates seven throwaways. A prompt asked to sort a list and do arithmetic burns inference on work that a few lines of Apex would do exactly, every time, for effectively nothing.

Nobody can see any of this today. Agentforce has no footprint view, no token report, and no way to tell a builder which of their agents is wasteful or what to do about it. Builders are shipping agents blind, at a moment when the number of agents in production is about to grow by orders of magnitude. Waste that is invisible at ten agents becomes an environmental line item at ten thousand.

I wanted a tool that makes that waste visible, tells you exactly what to change, and shows you what you get back for changing it.

---

## Our solution

Ohm is an Agentforce agent that audits Agentforce agents.

It reads the Agent Script bundles you have actually published in your org, along with the prompt templates their actions call, and asks three questions about each one:

- **Input.** Is the model reading more than it needs?
- **Output.** Is it writing more than anyone asked for?
- **Calls.** Is it doing work that plain code should be doing?

Each bundle gets a grade in each category and a modeled environmental footprint: energy, carbon and water per year, plus what you avoid by applying the recommended changes, scaled to whatever request volume you choose.

How it works, end to end, all inside Salesforce:

Ohm discovers the published bundles in the org, then retrieves the exact published source and linked prompt text through the Metadata API using its own External Client App and named credential. Every artifact is pinned by content hash at retrieval. A Prompt Builder template running GPT 5.5 reviews that source and returns findings that quote it directly. Then Apex takes over: it checks every quoted passage against the pinned source, confirms nothing changed during the run, applies fixed rating rules, and saves the whole review in a single transaction. If any quote fails to verify, nothing is saved at all. The model never gets the last word on a grade.

From the saved review, Ohm generates recommendations that each carry three things a builder actually needs: what to change, what must stay intact, and how to validate it. One click turns any recommendation into a standard Salesforce Task, keyed so it can never be duplicated, so the work lands in the same place as the rest of the team's work.

Ohm itself is a published Agentforce agent with five custom Apex actions, so you can just talk to it. Ask which agents waste the most and it ranks them with grades and modeled savings. Ask what to change in one and it gives you the recommendation with what to preserve. Tell it to audit one now, check the run, and have it create the task.

Ohm never changes your agents. It reads, it reviews, it recommends, and it hands the change to a person.

Built with: Agent Script authoring bundles, Prompt Builder (GPT 5.5), the Models API, invocable Apex actions, the Metadata API, an External Client App with client-credentials flow behind a named credential, custom objects, standard Tasks, and a Lightning Web Component app. It is running live in my org today.

I confirm I am my team's authorized representative, our submission is original, compliant with all Official Rules, and all team members are registered for Dreamforce 2026 who also agree to be bound by the official rules.

**YES / I confirm.**

---

## Team Representative

Dominick DeFazio

---

## Did your project address one of the 16 Salesforce Equality Group challenge prompts?

**YOUR CALL — pick one.**

If no (recommended, and honest):

> No. I built Ohm against the environmental sustainability theme rather than one of the 16 Equality Group prompts. The people it serves directly are Agentforce builders and admins, and the beneficiary beyond them is everyone downstream of the energy and water that AI infrastructure consumes, which is not distributed evenly. Data centre siting and water draw fall hardest on communities with the least say in it, so a tool that reduces unnecessary inference is a small equity lever even though I did not design it against a specific prompt.

If you did map it to one, name the prompt and replace the first sentence.

---

## Builder Track: What did the Accessibility Expert Skill find? Walk us through what you fixed, what you kept, and why.

**YOUR CALL — run the Accessibility Expert Skill before submitting and fold its actual findings into this. Everything below is real and verifiable in my repo today.**

I enforce accessibility with tests rather than review. Nineteen of my twenty-eight component test suites assert `toBeAccessible()` from @sa11y/jest, so an inaccessible component fails the build instead of a checklist.

What I fixed:

- **Charts and diagrams were the hardest problem.** My environmental figures and architecture diagrams are inline SVG, which is invisible to a screen reader by default. Every diagram now carries `role="img"`, a `<title>`, and a full sentence `aria-label` that states what the picture actually says. The footprint band meter announces "Modeled footprint 37.8 kWh a year against a 42.0 kWh high estimate; 19.2 kWh avoided by applying the recommended changes" rather than being a decorative bar.
- **Tab navigation was mouse-only.** The app's four tabs now implement the full tablist pattern: arrow keys move between tabs, Home and End jump to the ends, `aria-selected` and roving `tabindex` are managed, and the panel takes focus on navigation so keyboard users are not stranded at the top of the page.
- **Focus was getting lost after asynchronous work.** After an Ask Ohm answer returned, focus was dropped, so a keyboard user had to tab from the top again. The composer now takes focus back after every turn.
- **The volume selector was a set of unlabeled buttons.** It is now a labeled group with `aria-pressed` on each option, so the current selection is announced rather than only shown in green.
- **Colour was carrying meaning alone.** Grades were distinguishable by colour tone. Every grade and status now states itself in text as well.

What I kept and why:

- **I kept the dark theme.** I checked it against contrast requirements rather than dropping it. Body text and every figure sit above 4.5:1, and the accent green on dark panel is used for large text and non-text indicators that meet 3:1.
- **I kept the entrance animation but made it conditional.** Nine stylesheets carry a `prefers-reduced-motion` block that disables all animation and transition. Motion is a nicety, and it turns itself off for anyone who asked it to.
- **I kept disclosure widgets rather than flattening the page.** Assumptions, source evidence, and bundle structure are native `<details>` elements, which are keyboard and screen-reader native, instead of custom accordions I would have had to make accessible myself.

The honest gap: I have not run a screen reader end to end on a real device, and automated assertions catch roughly half of what a manual audit would. That is the next thing I would do.

---

## Builders Track: What did the RAI Self Check find? Walk us through how you addressed bias, fairness, and transparency.

**YOUR CALL — run the RAI Self Check before submitting and fold its actual findings into this. The design decisions below are real and visible in the running app.**

Ohm's whole risk surface is one thing: an LLM grading someone's work, where a wrong or invented judgement damages trust and wastes a builder's time. Nearly every design decision follows from that.

**Transparency.**

- **The model does not get the last word.** GPT 5.5 reviews the source and returns findings that must quote it. Apex then verifies every quoted passage against the hash-pinned source it retrieved, confirms nothing changed mid-run, applies fixed rating rules, and saves atomically. A review whose evidence does not verify is rejected in full and nothing is written. This fired for real during my final test run, and the retry succeeded, which is exactly the behaviour I wanted.
- **Every environmental number says what it is.** Every figure in the app carries a "Modeled, not measured" badge, because nothing in the platform reports actual watt-hours. One click lists every constant behind the number with its uncertainty band and its source. I considered simply printing a big savings number and rejected it, because a claim you cannot defend is worse than no claim.
- **I separated what is measured from what is modeled.** Token counts come from the platform's own usage response and are measured. Energy, carbon and water are modeled from those tokens using published figures. I never blur the two.
- **Uncertainty is shown, not hidden.** Every footprint figure displays its low-to-high range, and confidence is explicitly labelled Low.

**Fairness and bias.**

- **I tested for the failure mode that matters: a reviewer that finds problems everywhere.** I built a control bundle that does the same job correctly, with Apex doing the logic and the prompt only doing the wording, and put it in front of the reviewer without telling it that it was a control. It earned straight A grades and generated no recommendations. A reviewer that cannot say "this is fine" is worthless, and this is how I check mine can.
- **Absence of evidence is not a bad grade.** There is a fourth review category, Model Fit, for which I have no reliable evidence, so it returns Unrated and is hidden from the interface entirely rather than being turned into a score. Unrated stays Unrated.
- **Grades come from fixed rules, not model vibes.** The model supplies the interpretation and the quote. Apex maps that to A, B or C by deterministic rule, so the same evidence always produces the same grade.
- **The recommendations are conservative by construction.** Every one names what must stay intact and how to validate the change, because a "make it shorter" suggestion that quietly breaks a rule is the real harm here, not verbosity.

**Human in the loop, permanently.**

Ohm has no write path to your agents. It cannot edit source, cannot publish, cannot deploy. The only record it writes is a Task, and a person makes the change, tests it, and publishes it. I built a draft-rewrite feature and deliberately left it as a proposal that has to be copied out by hand.

The honest gap: my reviewer has been validated against four controlled bundles, not a broad corpus, so I cannot yet make a claim about its consistency across the full variety of real agents.

---

## Builder Track: What's your agent's current error rate, and what would "good" look like?

I track three different things, because "error rate" means different things for a reviewer than it does for a chatbot.

**Ratings saved without verified evidence: zero.** This is the number that actually matters. Verification is a gate rather than a report, so an unverifiable finding cannot reach the database. Across every audit I have run, no rating has ever been persisted without its quoted source matching the retrieved published source.

**Atomic rejections: one run out of nine, about 11 percent.** That single failure was the reviewer citing evidence that did not match the pinned source, and the system correctly threw the entire review away rather than saving a partial one. A retry succeeded. I class this as correct behaviour rather than a defect, but it is a real cost in latency, and I would want it under 5 percent.

**Conversational accuracy of the Ohm agent itself: both evaluation cases passed at 5 out of 5.** Using Salesforce's agent evaluation framework with an LLM judge, I asked it which agents waste the most and what to change in a specific one. It ranked the bundles correctly with real grades and real modeled figures, volunteered that the figures are modeled rather than measured, and returned the actual saved recommendation with what to preserve and how to validate. No invented numbers.

**Behavioural evaluation of the agents under test: seven of eight cases passed.** The single failure is the interesting one. A prompt asked to do scheduling arithmetic kept an overlapping activity it should have excluded, while the Apex-backed version got it right. When I moved that prompt to a stronger model, the same case passed. That is not a bug in Ohm; it is the evidence for Ohm's entire Calls category. Prompt arithmetic is model-dependent and quietly fragile. Code is not.

What "good" looks like:

- Zero unverified ratings saved, permanently. This is non-negotiable and currently holds.
- Atomic rejection rate under 5 percent, reached by tightening the quoting instructions rather than by relaxing verification. I will never trade verification for a nicer number.
- Grade stability: the same bundle audited twice with unchanged source should produce identical category grades. I have observed this across re-audits but have not measured it at a sample size worth quoting, and that is the next test I would build.
- Recommendation precision measured by builders: the share of recommendations a real builder judges worth acting on. I would target 80 percent and I have no honest number for it today, because four synthetic bundles are not a sample.

The thing I would most want a skeptical judge to look at is the control bundle. Any tool can find problems. Mine is built to be provably capable of finding none.

---

## AI systems consume significant energy and resources. How did you consider the environmental impact of your solution?

This is the entire product, so I had to hold myself to it twice: in what Ohm does for your agents, and in what Ohm costs to run.

**What Ohm does for your agents.**

Ohm exists to remove unnecessary inference. Across the four test bundles in my org, applying the changes it found avoids roughly 30 percent of their modeled annual energy, along with the associated carbon and water. The largest single fix was a support prompt that repeated its policy six times: stating it once cuts about half of that agent's footprint. I measured that one directly at the token level, where the same request dropped from 372 input tokens to 137, a 63 percent reduction in what the model has to read on every single call, forever.

The Calls category has the most leverage. Every time work moves out of a prompt and into Apex, that inference does not happen at all. It is not a smaller model or a shorter prompt; it is zero tokens, and it is also more correct, which my evaluation runs demonstrated.

**What Ohm costs to run.**

I was deliberate about not being a hypocrite:

- **One model call per audit.** The entire review of a bundle and all its linked prompts is a single generation. No chained calls, no speculative retries, and no agentic loop burning tokens to think about thinking.
- **Explaining a saved review costs nothing.** When you ask Ohm why something was rated the way it was, the answer is assembled deterministically from the review already on disk. No model call. The most common interaction in the product is free.
- **Listing, ranking and scaling are pure Apex.** The footprint numbers, the volume rescaling, the recommendations list and the fleet ranking are arithmetic on saved data. Changing the request volume from 300 to 100,000 does not call a model.
- **Discovery and retrieval never call a model.** Finding your bundles and fetching their source is Metadata API and SOQL.
- **I fail fast rather than retrying.** An audit that cannot verify its evidence stops. It does not re-prompt, and it does not burn a second generation trying to get a better answer.
- **Nothing runs on a schedule.** There is no background job re-auditing your org nightly. Audits happen when a human asks for one.

**How I talk about it.**

Nothing in the Salesforce platform, or from the model providers, reports actual energy consumption per request. So I model it, from measured token counts, using published per-prompt energy figures with grid and water factors, and I say "Modeled, not measured" on every single figure with every constant one click away. I could have printed a bigger, rounder, more impressive number. I think the credibility of a sustainability tool is the product, and overclaiming would have cost me more than the headline was worth.
