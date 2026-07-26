# The Evidence / Consumed / Gloss join

The one place the three joins are written down side by side (Story 18.118,
#725). Each is easy to conflate with the others, and conflating them is what
let two contradictory claims about the same corpus both look true.

The inspection view that renders these is `scripts/inspect-article-join.py`.
It is read-only: it writes nothing to the articles repo and nothing to the hub.

## The three joins

### 1. Evidence — claim-level

The sidecar provenance map is the claim-level grounding record. It addresses
**sentences**, as `P<n>.S<n>[L<line>]`, and each `sourced` / `derived` claim
carries pointers that must resolve to declared fact-sheet entries
(`scripts/verify-provenance.py:16-22`).

The `[L<line>]` anchor is the draft line. That is what makes a *paragraph*-level
view possible at all: a paragraph's section is the nearest preceding heading in
the draft, derived at render time from the draft's own structure. **No new
persisted field is required** — the join key already ships. Anything without an
anchor is reported as unknown, never guessed.

### 2. Consumed — article-level

`consumed:` in `plans/<slug>.md` is the **only** consumption record, keyed by
story-element id, with no second store
(`scripts/write-article-plan.py:115-122`). The derived consumption view holds a
Lesson available iff no live or ever-published item cites it.

`sections:` is the section→element map, and every element it names must be in
`consumed:` (`scripts/write-article-plan.py:124-131`). That is the finest
*structural* granularity the plan schema records: **section**-level, not
paragraph-level.

The design says this join is article-level, and it means it. A `consumed:` entry
asserts that the article drew on the element — never that any identifiable
paragraph did.

### 3. Gloss — hub-side, and not computable from here

The terrain surface matches hub Lesson Evidence pointers against declared
sources under a three-valued verdict with no silent filtering
(`consulted: product-lab@<private-pin>
topics/articles.md:35,44`).

**From the consumer side this leg cannot be computed.** The served lessons index
gives one line per lesson in the declared format

```
- [one_liner](lessons/<slug>.md) — <status> | tags: <t1, t2> | YYYY-MM-DD
```

(`LESSONS.md:9`, consulted 2026-07-26). That line carries **no Evidence
pointers**. The pointers live in the lesson body, which the seam does not serve —
recorded as `SPEC-terrain` OQ3.

So an empty leg (3) is **cannot-determine**, never **absent**. The inspection
view renders it that way and refuses to print "none", because an absence was
never established. This is the same three-valued discipline the terrain spec
applies to its own verdicts, turned on this report.

## The key that does not exist

The three joins share no common identifier, and this is the load-bearing fact.

A story-element id is a **pure function of the cluster's declared membership
anchor** in the fact sheet — casefold, slugify, prefix `el-`
(`scripts/write-article-plan.py:155-178`). The anchor comes from the **host
repository's declared sources**. It is never a hub Lesson slug.

Therefore:

| | population | key | who mints it |
|---|---|---|---|
| Evidence | source pointers | `path:line@sha` | harvest, from declared sources |
| Consumed | story elements | `el-<anchor-slug>` | the run, from fact-sheet cluster anchors |
| Gloss | hub Lessons | `<lesson-slug>` | the hub |

`consumed:` and the hub Lesson pool are **disjoint namespaces**. A run can
truthfully report that every element it selected has been consumed while the
overwhelming majority of hub Lessons have never reached an article — the two
statements quantify over different sets, and no mechanism converts between them.

That is not a defect in either record. It is a missing third element: nothing
maps a story element back to the hub Lesson it expresses, so no surface can
state coverage of the hub Lesson pool by articles. Until such a mapping exists,
any claim of the form "every lesson has been consumed" is scoped to the
elements the run itself minted, and should say so.

## Reading a report

- **Leg (a) `_none_`** — the paragraph is narration. Expected and healthy; a
  draft that grounded every sentence would be a fact sheet.
- **Leg (b) `_cannot-determine_`** — the default, for the reason above. It is
  not a gap in the report; it is the report declining to invent one.
- **Leg (c) `_none_`** on a paragraph that *does* carry pointers — the
  paragraph is grounded in evidence that belongs to no selected element.
  Legitimate for context and framing sections; worth a look anywhere else.
- **`article-level-only`** — the element declared pointers, and no paragraph
  carries any of them. The consumption claim is real but has no prose footprint.
- **`not-attributable`** — the element is in `consumed:` but the plan body
  declares no pointers for it. This is a *parsing* verdict as much as a
  substantive one: the element→evidence mapping lives in the plan's editorial
  prose rather than in a declared field, so a plan that phrases it differently
  lands here. Read it as "the plan does not state this element's evidence in a
  form anything can read", which is itself worth knowing.
