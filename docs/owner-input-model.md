# The owner-input model

How the owner's requirements, opinions, and material get into a draft — in one
place, so no one has to reverse-engineer it from the skill files. Derived from
the implementation and specs; the normative contracts are
[`specs/spec-article-draft-pipeline/SPEC.md`](../specs/spec-article-draft-pipeline/SPEC.md)
(the interview, CAP-2; provenance, CAP-3) and
[`skills/draft-article/SKILL.md`](../skills/draft-article/SKILL.md).

## The channel is the gap interview — not hand-editing afterward

The pipeline harvests **facts** from the sources; the owner supplies **judgment**
and **requirements**. The single designed place for that owner input is the
**Stage-2 gap interview**. Post-hoc hand-editing of the finished draft outside
the pipeline is **not** the intended workflow — it produces prose with no
provenance and no quality re-check. During dogfooding an owner assumed manual
insertion was the path precisely because the channel was not surfaced; it now
is (the interview says so when it opens).

## What the owner can put in, and how it lands

| Owner input | Enters the interview as | Reaches the draft as |
|---|---|---|
| Opinion, thesis, arc, stakes, a belief or reversal | an `open` (owner-only) item | an **owner-attributed prose span** — a paragraph classified `sourced` with a paragraph-granularity question-id pointer (Story 17.1) |
| A checkable requirement or fact the owner knows | an `open` or NEEDS-OWNER item | a **sourced / derived** claim carrying its interview pointer |
| A free-form constraint, emphasis, or correction | a **first-class** interview item (not only a source-gap answer) | applied at Stage 3 per its kind (span or claim) |

Owner judgment is never source-checkable and must not be — the falsifiability
contract holds; an attributed prose span asserts the owner's view, attributed to
the answer that carries it, not a fact a reviewer could mark false.

## Budget and overflow

Owner input rides the interview's **≤5-question budget** and its journal. A
requirement that exceeds a single run's budget is **recorded for the next
invocation** (a NEEDS-OWNER-style carry-over), never silently dropped.

## The run tells you what it applied

At completion, the summary states — in its informational bucket — **where owner
input landed** (which answers reached the draft and how) and **where the owner
is still expected to hand-write** (an owner-authored slot, or a
`[VERIFY]`/NEEDS-OWNER item awaiting owner knowledge). Hand-editing, when it is
needed at all, is a **named remaining step**, not an unspoken default. See the
completion-summary contract:
[`skills/completion-summary.md`](../skills/completion-summary.md).

## See also

- [`pipeline-vocabulary.md`](pipeline-vocabulary.md) — Stage 3 and the
  provenance classes owner input is classified into.
- [`docs/interview-architecture.md`](interview-architecture.md) — the Stage-2
  interview decision.
