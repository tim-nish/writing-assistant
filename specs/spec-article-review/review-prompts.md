# Review prompts and rubric (companion to SPEC-article-review)

## Lint checklist (CAP-1 — script, zero tokens)

- Frontmatter parses and conforms to the `article` schema (`docs/content-guide.md`): required fields, enum values, `mode`/body rules.
- Title ≤ 70 chars and contains a claim verb (heuristic: warn if title is a bare noun phrase).
- Pointer block present (site URL `tim-nish.dev` appears in the final section).
- Heading density: no gap > ~250 words between headings.
- All links resolve (HTTP 200/301) or are flagged.
- No `[VERIFY]` markers remain (pipeline stage-4 exit criterion re-checked).

## Shared reviewer preamble (CAP-2/CAP-3)

> You are a senior engineer skimming {dev.to | Zenn}. You give an article 60 seconds
> to earn a full read; your time is scarce and your standards are high.
> The intended reader: {audience from the article's interview answer #5}.
> You have repo access — when the draft states a fact about the project, check it
> against the sources before flagging or passing it.
>
> Output findings only. Never rewrite passages. Never praise. Never summarize the
> article back. Cap at 10 findings, ordered by severity, and state the single
> highest-leverage change FIRST.
>
> Finding format:
> `- [blocker|should|nit] {section/paragraph}: {issue in one sentence}. Fix: {concrete suggestion in one sentence}.`

## Structural pass rubric (CAP-2)

Check, in order:

1. Does the first 3 sentences state the problem or result (hook), with zero credentials/throat-clearing?
2. Is there exactly one idea? (Two ideas → recommend the split point.)
3. Does every section advance that idea? Name sections to cut or merge.
4. Is anything load-bearing missing for the stated audience? (evidence, limits, quickstart per the framework used)
5. Is the order the reader's order (problem → solution → evidence), not the author's chronology?
6. Framework conformance: do the GATE slots (evidence, pointer block) contain real content, not placeholders?

## Prose pass rubric (CAP-3)

1. Claims hedged into mush ("might", "could potentially") where evidence exists — tighten.
2. Jargon the stated audience won't know, used unexplained.
3. Sentences > ~30 words doing two jobs — split points.
4. Passive/agent-less statements about decisions ("it was decided") — restore the actor.
5. Paragraphs whose load-bearing sentence is buried — name it so the author can bold or lead with it.
6. EN drafts by a non-native author: flag unidiomatic phrasing, but do not sand off voice — opinions stay opinionated.

## Cold-read rubric (CAP-4 — run with NO project context)

Give the model only the draft, then ask:

1. In one sentence, what is this article's claim?
2. Who is it for?
3. At which paragraph did you first get confused, and why?
4. What did the author assume you already knew?
5. Would you read past the first screen? Why/why not?
6. What would you do after reading it?

Compare answers to the author's intent (interview answers #2/#5). Mismatch on Q1 or Q2 = blocker; Q3/Q4 hits = should-fix.

## Arbitration round (owner)

- Walk findings top-down; accept/reject each; apply accepted fixes yourself or via one targeted edit instruction per finding.
- A finding rejected is rejected — do not re-litigate it in a later pass.
- Second full cycle only if a blocker survived (e.g. cold-read claim mismatch after fixes).

## Model routing

| Pass | Model tier | Grounding |
|---|---|---|
| Lint | none (script) | — |
| Structure | Sonnet class | repo access |
| Prose | Sonnet class (Haiku acceptable) | repo access |
| Cold read | any cheap model | **none — context-free by design** |

Drafting uses the strongest available model (see SPEC-article-draft-pipeline): one good draft + cheap bounded reviews beats a cheap draft + expensive rescue cycles.
