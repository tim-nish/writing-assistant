---
name: review-article
description: >
  Review a framework-complete draft article for publication. Invoke as
  "review article <draft>" to run the fixed pass order: lint → structure →
  prose → cold read, each LLM pass once per draft version, emitting capped
  severity-tagged findings (blocker/should/nit) with no rewrites. The owner is
  the sole arbiter of every finding.
---

# Review article

Take a framework-complete draft from "review requested" to "publishable" with a
fixed, small number of passes:

```
review article <draft>
```

- **draft** — a path to a framework-complete draft (the unit of review is a
  filled draft, never an outline or idea).

## Owner-facing proposals

Arbitration hands each finding to the owner to accept or reject; that
presentation follows the shared
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/owner-facing-proposal-contract.md`): **where** the
finding sits in the article, **why** it is raised, and accept/reject **choices
whose labels state their concrete effect** on the article — never a shorthand
label the owner must decode. This skill references that one convention rather than
defining its own wording.

The design goal is **maximum defect yield per pass** at a fixed, small cost: the
mechanical checks cost zero tokens, each LLM pass runs **once per draft version**
on a cheap-tier model, and the owner arbitrates all findings in a single round.

## Host-repo footprint (leave nothing behind)

Review **writes no files into the host working tree** — findings are reported to
the owner, never saved as artifacts in the repo. If a pass needs to persist
anything (scratch, a findings log), it goes to the run's **workspace outside the
host repo**, resolved by the path resolver
(`docs/storage-architecture.md` D1–D2), never a path you compose yourself:

```
WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run)
```

After a review run the host repo's `git status` shows **nothing new** — no
`scratch/`, no stray intermediate. The plugin's only host-tree footprint across
the whole pipeline is the declared draft products at `output.drafts`.

## Stage 0 — configuration validation

Before any review pass, validate the resolved configuration (CAP-5):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.py
```

It **halts** on any unresolved placeholder, malformed URL (e.g. a double-slash
`canonical_url`), or missing required key with a **per-key report naming the file**
(`user-config.yaml` / `writing-sources.yaml`) and the fix — so a configuration
defect is caught up front, before any review work, never surfaced as a late
article-quality finding. A clean config passes **silently**.

## Fixed pass order

Run the passes in this exact order — **lint → structure → prose → cold read** —
and never reorder them:

1. **Lint** (script, zero tokens)
2. **Structure** (LLM, once per draft version)
3. **Prose** (LLM, once per draft version)
4. **Cold read** (LLM, once per draft version)

**Structure precedes prose** because structural changes (cuts, reordering,
missing sections) invalidate prose feedback — polishing a sentence that a
structural finding later deletes wastes the pass. Each LLM pass runs **exactly
once per draft version**; a pass is not re-run within a cycle. A second full
cycle happens only when a blocker survives arbitration (see *Arbitration*).

## Findings contract

Every LLM pass emits **findings only**, in this exact format, one per line:

```
- [blocker|should|nit] {location}: {issue in one sentence}. Fix: {concrete suggestion in one sentence}.
```

- **Severity** is one of `blocker` (publication-stopping), `should`
  (fix before publishing), or `nit` (optional polish).
- **Capped at 10** findings per pass. If more exist, keep the 10 highest-leverage.
- **Ordered by severity**, and the **single highest-leverage change comes FIRST** —
  each pass leads with the one change that most improves the draft.
- **No rewrites** (never reproduce a rewritten passage), **no praise**, **no
  summary** of the article back to the owner. Output spent on anything but
  findings is wasted.

## Shared reviewer preamble (structure & prose passes)

Both repo-grounded LLM passes open with this framing, filled from the draft:

> You are a senior engineer skimming {dev.to | Zenn}. You give an article 60
> seconds to earn a full read; your time is scarce and your standards are high.
> The intended reader: {audience from the article's interview answer #5}.
> You have repo access — when the draft states a fact about the project, check it
> against the sources before flagging or passing it.
>
> Output findings only. Never rewrite passages. Never praise. Never summarize the
> article back. Cap at 10 findings, ordered by severity, and state the single
> highest-leverage change FIRST.

## Model routing

Each pass uses the cheapest tier that can do its job, with the grounding it needs:

| Pass | Model tier | Grounding |
|---|---|---|
| Lint | none (script) | — |
| Structure | Sonnet class | repo access |
| Prose | Sonnet class (Haiku acceptable) | repo access |
| Cold read | any cheap model | **none — context-free by design** |

Drafting (SPEC-article-draft-pipeline) uses the strongest available model; review
uses cheap bounded passes — one good draft plus cheap reviews beats a cheap draft
plus expensive rescue cycles.

## Pass 1 — Lint (zero tokens)

Run the mechanical lint before any model:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/lint-article <draft>
```

It checks frontmatter conformance to the config `article` schema, title length +
claim verb, pointer-block presence, heading density, dead links, and residual
`[VERIFY]` markers — reporting each with `path:line` and consuming **no LLM
tokens**. Fix every lint defect before spending a model pass; a draft with
`[VERIFY]` markers is not review-ready.

**Configuration backstop (CAP-5, Story 7.4).** The lint pass also re-runs the
stage-0 configuration validation as a zero-token backstop:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.py
```

Any configuration defect it reports — an unresolved placeholder, a malformed URL,
or config-caused frontmatter invalidity — is a **publish blocker**: it routes to
the completion summary's publish-blocker bucket (Story 7.5), **never** into the
capped prose or structure findings lists. Configuration is not an article-quality
finding.

## Pass 2 — Structure

Structural review (cuts, reordering, missing/redundant sections) on a
**Sonnet-class model with repo access**, run **once per draft version**. Open with
the shared reviewer preamble, then apply this rubric **in order** — the structural
defects it catches (a deleted section, a reordered argument) would invalidate any
prose feedback, which is why this pass runs before prose.

Check, in order:

1. **Hook** — do the first 3 sentences state the problem or the result, with
   zero credentials or throat-clearing? If they warm up instead, flag it.
2. **One idea** — is there exactly one idea? Two ideas → recommend the split
   point (and that the second becomes its own article).
3. **Section relevance** — does every section advance that one idea? Name the
   sections to cut or merge; a section that does not earn its place is a finding.
4. **Missing load-bearing content** — is anything the stated audience needs
   absent (evidence, limits, quickstart — per the framework used)?
5. **Reader-order** — is the order the reader's (problem → solution → evidence),
   not the author's chronology? A **misplaced section** (e.g. evidence before the
   claim it supports) gets a corresponding finding naming where it should move.
6. **GATE-slot conformance** — do the framework's mandatory GATE slots (the
   **evidence** slot and the **pointer block**) hold real content, not `{slot}`
   placeholders or *(prompt)* text?

Emit findings in the standard contract format (severity, location, issue, fix),
capped at 10, highest-leverage change first. **No rewrites** — name the structural
change; the owner applies it.

## Pass 3 — Prose

Prose review (clarity, tone, hedging, jargon) on a **Sonnet/Haiku-class model with
repo access**, run **once per draft version** — and **only after the structural
pass is settled**, because a structural change would invalidate prose feedback.
Open with the shared reviewer preamble, then apply this rubric:

1. **Unwarranted hedging** — claims softened into mush ("might", "could
   potentially") where the evidence actually supports the stronger statement;
   tighten them.
2. **Unexplained jargon** — terms the stated audience will not know, used without
   a gloss.
3. **Overlong sentences** — sentences over ~30 words doing two jobs; name the
   split point.
4. **Agent-less decision statements** — passive constructions that hide who acted
   ("it was decided", "the approach was changed"); restore the actor.
5. **Buried load-bearing sentences** — paragraphs whose key sentence is buried in
   the middle; name it so the owner can lead with or emphasize it.
6. **Non-native phrasing** — for EN drafts by a non-native author, flag
   unidiomatic phrasing, **but do not sand off voice** — opinions stay
   opinionated; flatten the phrasing, not the stance.

Emit findings in the standard contract format (severity, location, issue, fix),
capped at 10, highest-leverage change first. **No rewrites** — name the prose
issue and a one-line fix; the owner edits.

## Pass 4 — Cold read

A read by **any cheap model given ONLY the draft** — **no repo access, no project
context, no interview answers** — so it simulates the actual reader and surfaces
missing-context defects the repo-grounded passes cannot see. Do **not** paste the
sources or the prior findings into this pass; that would defeat it. Ask the model
the reader rubric:

1. In one sentence, what is this article's **claim**?
2. **Who is it for**?
3. At which paragraph did you **first get confused**, and why?
4. What did the author **assume you already knew**?
5. Would you **read past the first screen**? Why / why not?
6. What would you **do after** reading it?

**Then compare the cold-read answers to the author's intent** — the article's
interview answers **#2 (the point/claim)** and **#5 (the intended audience)**:

- A **mismatch on Q1 (claim) or Q2 (audience)** is a **blocker** — the draft does
  not communicate its own claim or reader, which unexplained repo-internal context
  typically causes.
- **Q3 (confusion) and Q4 (assumed knowledge)** hits are **should-fixes**.
- Q5/Q6 answers inform severity but are not themselves findings.

Emit findings in the standard contract format, capped at 10, highest-leverage
first, no rewrites. This is the final pass; its findings feed arbitration.

## Arbitration

After lint, structure, prose, and cold read have run, collect their findings into
one list and hand it to the owner. The **owner is the sole arbiter**.

**Present each finding under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md):** show
**where** it sits in the article (the finding's `{location}`), **why** it is
raised (its one-sentence issue), and accept/reject choices whose labels state
their **concrete effect on the article** — *accept* → "apply the fix to the
article", *reject* → "leave the article unchanged" — never a bare accept/reject
the owner must decode. This is a presentation wrapper only: it **does not change**
the capped (≤10), severity-tagged findings **format** from *Findings contract*.

**The single arbitration round.** Walk the findings **top-down, once**:

- **Accept or reject each finding** — no finding is skipped and none is
  **auto-applied**. Apply an accepted fix yourself, or via **one targeted edit
  instruction per finding**; never open-ended rewriting.
- **A rejected finding is rejected.** Do **not** re-litigate it in a later pass or
  a second cycle — the decision stands.
- The round is **top-down and single-pass**: the highest-leverage findings (which
  each pass placed first) are arbitrated before the nits.

**Second-cycle gate.** After the round:

- If a **blocker-severity finding survived** the fixes (the canonical case: a
  cold-read **claim/audience mismatch** still present after edits), trigger
  **exactly one additional full cycle** — lint → structure → prose → cold read
  again on the new draft version. **One** — the workflow never loops unbounded.
- **Otherwise the draft is publishable.** No surviving blocker ⇒ done — **unless a
  configuration blocker is still open**, in which case review does **not** report
  the draft "publishable" until it is fixed (the zero-token lint pass re-checks
  configuration as the backstop to Story 7.4).

**Per-pass model routing (recap).** Each pass runs on the tier and grounding in
the *Model routing* table above: **lint** is the zero-token script; **structure**
and **prose** run on a **Sonnet-class model with repo access** so claims are
checked against the sources; **cold read** runs on **any cheap model, context-free
by design**. The second cycle, if triggered, uses the same routing.

## Completion summary

End every review run with the shared
[**completion summary**](../completion-summary.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/completion-summary.md`): the three labelled buckets
— **informational notes**, **publish blockers**, **optional cleanup** — then an
explicit **next step** (e.g. "apply the accepted findings, then re-run review" or
"the draft is publishable"). A surviving blocker-severity finding, an unresolved
`[VERIFY]` marker, an unrendered figure, or a **configuration defect**
(placeholder, malformed URL, config-caused frontmatter invalidity) goes under
**publish blockers** and nowhere else — a config defect is never routed into the
capped prose/structure findings lists. Because review works on an **article body**, the informational
bucket includes a **reading-time estimate**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/reading-time.py --language <en|ja> <draft>
```
