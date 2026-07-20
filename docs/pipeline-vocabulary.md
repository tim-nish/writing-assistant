# Pipeline vocabulary and data flow

A reader's map of the draft-article pipeline: what each working term means and
where information is narrowed, discarded, or routed as it flows from source
material to a publishable draft. This page is **derived from the current
implementation and the ratified specs, not inferred** — where a rule is
normative it points at the contract that owns it rather than restating it
(duplicated normative text would drift). The canonical contracts are
[`specs/spec-article-draft-pipeline/SPEC.md`](../specs/spec-article-draft-pipeline/SPEC.md)
and its companion
[`pipeline-stages.md`](../specs/spec-article-draft-pipeline/pipeline-stages.md).

## The stages

`draft article <type> from <sources>` runs a fixed sequence:

```
stage 0        harvest        gap interview     framework fill    verify        complete
(invocation) → (fact sheet) → (owner answers) → (Stage 3 draft) → (provenance) → (canonical + plan)
```

- **Stage 0 — invocation.** Validates configuration and classifies the source
  tokens (path / glob / commit-range); emits the run-state harvest consumes.
- **Stage 1 — harvest.** Builds the **fact sheet** — candidate claims each
  carrying a resolvable source pointer (see the nine-KIND vocabulary below).
- **Stage 2 — gap interview.** At most five questions covering only what the
  sources cannot answer; answers return as owner input for Stage 3.
- **Stage 3 — fill.** Populates the framework's slots from the fact sheet and
  the interview answers, classifying every sentence in a provenance map.
- **Verify.** An independent `verify-provenance` check and the Stage 3→4
  quality gate.
- **Complete.** Durably writes the two declared products: the canonical draft
  at `output.drafts` and the article plan at `plans/<slug>.md`.

## Stage 3 — the fill stage

Stage 3 is where source facts and owner judgment become prose. Its contract is
CAP-3 of the pipeline spec.

**Stage 3 opens with an argument-plan sub-step (#440/#434).** Before filling any
slot, it composes an explicit **argument plan** — thesis, arc, per-section
content intents — from the fact sheet (including the narrative kinds) and the
interview, then fills **from that plan**, so the article is an argument rather
than a framework skeleton stitched from fact-sheet prose. A framework governs
each section's **content obligations, not a literal heading skeleton** — a
multi-lesson article is one arc, not the skeleton repeated per lesson. The plan
is a run-workspace intermediate, owner-visible; at completion the plan-record
`plans/<slug>.md` projects the thesis/arc from it. The Stage 3→4 quality gate
fails stitched-fact-sheet and per-lesson-skeleton drafts **before** review.

- **Inputs:** the fact sheet (Stage 1) and the interview answers (Stage 2).
- **Outputs:** a slot-filled draft with schema-conformant frontmatter, plus a
  **sidecar provenance map** classifying every body sentence.
- **Restrictions — the three provenance classes** (every claim-classed
  sentence must trace to a pointer, an interview answer, inherited pointers, or
  a `[VERIFY]` marker):
  - **sourced** — carries a fact-sheet or interview pointer.
  - **derived** — compresses, combines, or restates ≥2 named sourced claims and
    inherits their pointers. Introducing new **causality, significance,
    evaluation, comparison, intent, or scope** makes it *inferred*, not derived.
  - **narration** — asserts nothing checkable (the **falsifiability test**: no
    reviewer with source access could mark it false) and needs no pointer.
  - An assertion that exceeds all of the above carries an inline `[VERIFY]`
    marker; the pipeline never silently asserts.
- **Copy, don't summarize.** A sourced claim copies the verbatim source text
  behind its pointer rather than paraphrasing it, so the pointer always
  resolves to what the sentence says. The drafting agent never grades its own
  claim/narration boundary — `verify-provenance` runs in an isolated subagent
  (NFR13).

## The closed nine-KIND fact-sheet vocabulary

Every fact-sheet entry declares exactly one **KIND** from a **closed set** of
nine (`pipeline-stages.md`) — five atomic kinds plus four **narrative** kinds
(added 2026-07-20, #438):

| KIND | Means |
|---|---|
| `result` | An outcome the work produced. |
| `decision` | A choice made, with its rationale where recorded. |
| `number` | A measured or counted quantity. |
| `quote` | Verbatim source text (may span consecutive physical lines). |
| `event` | Something that happened at a point in time (a release, a fix). |
| `chronology` | An ordered sequence of events — a timeline. |
| `motivation` | The *why*: the problem/gap, or free-standing decision rationale. |
| `cost` | A recorded price or tradeoff paid. |
| `reversal` | A superseded position (a struck decision, a Declined line). |

The four narrative kinds admit **pointer-backed** narrative material and may use
a multi-line span pointer like `quote`. Anything that does not fit one of these
nine KINDs cannot enter the fact sheet — it routes elsewhere (below).

## Where information is narrowed, discarded, or routed

The pipeline deliberately loses material at each boundary; knowing where keeps
its output auditable.

- **Harvest → fact sheet.** Only source-pointable material becomes a fact-sheet
  entry. Facts the harvester wants but cannot source go to a **`NEEDS-OWNER`**
  list, never into the draft unmarked.
- **Owner-judgment dimensions route off the sheet.** Owner judgment —
  **surprise, significance, tradeoff, warning, opinion** — is not source-checkable,
  so it routes to `NEEDS-OWNER` and reaches the draft (if at all) through the
  **interview**, the gate between evidence and prose. **Pointer-backed narrative
  material** (chronology, problem statements, motivation, failure/cost, reversals)
  is different: since #438 it **does** enter the fact sheet, under the four
  narrative KINDs above — the interview stays the judgment gate, but the
  narrative *evidence* is now harvestable rather than routed off.
- **Interview → draft.** An **approved** recommended answer keeps its source
  pointers and grounds sourced claims like a fact-sheet entry; **modified** or
  **replaced** answers become interview-sourced material.
- **Policy source absent → generic mode.** When the host repo declares no
  `policy_source` (or the gateway is unavailable), the policy-seam steps
  **degrade to generic**: no tension questions are seeded and no policy
  influence is recorded — the pipeline runs unchanged otherwise. The policy
  source is an enhancer, never a dependency.

## See also

- [`specs/spec-article-draft-pipeline/SPEC.md`](../specs/spec-article-draft-pipeline/SPEC.md)
  — the canonical pipeline contract (CAP-1…CAP-7).
- [`specs/spec-article-draft-pipeline/pipeline-stages.md`](../specs/spec-article-draft-pipeline/pipeline-stages.md)
  — the stage table, fact-sheet entry format, provenance map, and quality gate.
- [`docs/interview-architecture.md`](interview-architecture.md) — the Stage-2
  interview decision.
- [`docs/harness-architecture.md`](harness-architecture.md) — the
  article-quality harness (provenance classes and the quality gate).
