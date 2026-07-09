# Article frameworks (companion to SPEC-article-frameworks)

Four fill-in templates, one per sanctioned category. Conventions used by all four:

- `{slot}` = fill-in; *(prompt)* = what the slot must answer; lengths are targets, not limits.
- **GATE** marks a mandatory editorial-gate slot (CAP-3). A draft with an unfilled GATE slot is not publishable.
- Frontmatter follows the `article` schema in `docs/content-guide.md`. EN canonical pieces use `mode: canonical` (+ `syndication:` for dev.to); JA pieces published on Zenn use `mode: external` on the site and this template's body ships to Zenn via repo-sync.
- Every framework ends with the same **pointer block** (spec §3 invariant), template at the bottom of this file.
- Title rule (all categories): the title states the article's one specific claim, not its topic.

---

## F1 — Project introduction

**Use when:** introducing a project you built (OSS, benchmark, tool).
**GATE (entry):** the project has a tagged release or equivalent shipped artifact. No release → write F2 lessons instead; save the introduction for launch.

```markdown
---
slug: {introducing-project-slug}
title: "{Claim-shaped title: what the project makes possible, not its name alone}"
date: {YYYY-MM-DD}
mode: canonical            # or external if JA-on-Zenn
language: {en|ja}
summary: >
  {≤240 chars: problem + what the project does about it}
topics: [{kebab-case}]
related: { projects: [{project-slug}], publications: [], products: [] }
---

## {The problem}                                    (~120 words)
{(Describe the pain as the READER experiences it. Your project is not
mentioned yet. A reader with this problem must think "yes, that's me".)}

## {Why existing options fall short}                (~100 words)
{(Name 1–2 real alternatives and be fair to them — the gap you fill,
not a strawman. Fairness here is a credibility signal.)}

## {What I built}                                   (~150 words + 1 demo)
{(One-paragraph definition in plain language, then ONE concrete demo:
code block, screenshot, or command + output. Show, don't enumerate features.)}

## {The design decision that matters}               (~150 words)
{(The one non-obvious decision — e.g. "why JAX-native" — and what it COST.
A decision with no tradeoff stated reads as marketing.)}

## GATE {Evidence}                                  (~100 words + 1 figure/table)
{(A result, benchmark number, or worked example produced by the real system.
This slot empty = article not publishable (AP-10).)}

## {Limits and roadmap}                             (~80 words)
{(What it does NOT do, honestly. Highest-trust section for a technical reader.)}

## {Try it}                                         (3 steps max)
{(Install → minimal run → where to go next. Link repo/leaderboard/datasets.)}

## GATE {Pointer block}
{(See shared template below.)}
```

---

## F2 — Engineering lessons

**Use when:** sharing lessons, design decisions, failure findings from development.
**GATE (entry):** at least one real surprise/failure with an artifact you can show (log excerpt, diff, measurement).

```markdown
---
slug: {lesson-slug}
title: "{The lesson as a claim, e.g. 'Structured discovery halved our token bill'}"
date: {YYYY-MM-DD}
mode: canonical
language: {en|ja}
summary: >
  {≤240 chars: the lesson + the evidence type behind it}
topics: [{kebab-case}]
related: { projects: [{project-slug}], publications: [], products: [] }
---

## {Context}                                        (~100 words)
{(What you were building and why; link the project record. Only enough
context to make the lesson intelligible — this is not the project intro.)}

<!-- Lesson unit: repeat slots 2–6 for up to 3 lessons. >3 lessons = 2 articles. -->

## {What I believed going in}                       (~60 words)
{(The reasonable-sounding assumption. Readers must recognize themselves in it.)}

## GATE {What actually happened}                    (~120 words + artifact)
{(The surprise, WITH the artifact: log excerpt, diff, number, screenshot.
This slot empty = article not publishable (AP-10).)}

## {Why — the mechanism}                            (~120 words)
{(Root cause, not symptom. This is the transferable part; be precise.)}

## {What I changed, and what it cost}               (~100 words)
{(The fix or decision, with the tradeoff you accepted stated plainly.)}

## {When this applies to you — and when it doesn't} (~80 words)
{(Generalize with boundaries. Scoping the lesson honestly beats overselling it.)}

## GATE {Pointer block}
```

---

## F3 — Evaluation & benchmark methodology

**Use when:** writing about how to measure — benchmark design, agent evaluation, leakage, reproducibility.
**GATE (entry):** a measurement you actually ran.

```markdown
---
slug: {methodology-slug}
title: "{The measurement question or its answer, e.g. 'How do you know your agent got better?'}"
date: {YYYY-MM-DD}
mode: canonical
language: {en|ja}
summary: >
  {≤240 chars: the measurement problem + your method}
topics: [{kebab-case}]
related: { projects: [{benchmark-project-slug}], publications: [], products: [] }
---

## {The measurement question}                       (~100 words)
{(The question practitioners actually have, phrased as they'd ask it.)}

## {Why the naive approach fails}                   (~150 words + demo)
{(DEMONSTRATE the failure — a leaked scenario, a variance plot — don't assert it.)}

## {The method}                                     (~200 words + sketch)
{(Design principle first, implementation sketch second. WHAT the method
guarantees and why, before HOW it's coded.)}

## GATE {What it caught}                            (results table/figure + ~100 words)
{(Real results from running it. This slot empty = article not publishable.)}

## {What this measurement cannot tell you}          (~80 words)
{(Scope the metric's validity. For an evaluation audience this section IS the credential.)}

## {Reproduce it}                                   (links + ~50 words)
{(Code, dataset, leaderboard. A methodology article without reproduction links
undercuts its own thesis.)}

## GATE {Pointer block}
```

---

## F4 — Research survey

**Use when:** low-cadence reputation-anchor surveys (e.g. signature methods).
**GATE (entry):** you have read the primary papers, and a related preprint/repo of yours exists or is imminent (spec §6.2 paper+code pairing).

```markdown
---
slug: {survey-slug}
title: "{Field + angle, e.g. 'Signature methods for market data: a field guide'}"
date: {YYYY-MM-DD}
mode: canonical
language: {en|ja}
summary: >
  {≤240 chars: scope + who it's for}
topics: [{kebab-case}]
related: { projects: [], publications: [{your-preprint-slug}], products: [] }
---

## {Scope and audience}                             (~80 words)
{(What's covered, what's excluded, who this is for, and the as-of date —
surveys age; dating them keeps them citable.)}

## {The map}                                        (table or diagram + ~100 words)
{(A taxonomy of approaches. The map is the artifact readers bookmark.)}

<!-- Branch unit: repeat for each taxonomy branch. -->
## {Branch: core idea / key papers / when to use / open problems}   (~150 words each)
{(Per branch: the idea in 2 sentences, 2–4 key papers, the practical
'use this when', and what's unsolved.)}

## GATE {My take}                                   (~150 words)
{(Where the field goes and what YOU are building on it — the owner-evidence
slot that keeps a survey within AP-10. Link your preprint/repo.)}

## {Reading list}
{(The papers, ordered by 'read this first', one-line annotations.)}

## GATE {Pointer block}
```

---

## Shared pointer block (all frameworks; spec §3 invariant)

```markdown
---
*I write about {focus areas} — more at [tim-nish.dev](https://tim-nish.dev).*
*{Related: [{project/publication title}]({url on tim-nish.dev})}*
*{Newsletter/RSS line per current `newsletter.status`: coming-soon → RSS + follow links; live → capture link.}*
{JA counterpart exists → "日本語版は Zenn にあります: {url}" / EN counterpart exists → link it.}
```

Syndication notes:

- dev.to copy: full text, frontmatter `canonical_url:` pointing to the site page (add/repoint after the site can host canonical articles).
- Zenn: JA canonical via repo-sync; the site gets a 20-line `mode: external` record (body forbidden, AC-4).
