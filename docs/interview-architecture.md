# Stage-2 interview — architecture decision

**Status:** accepted (owner, 2026-07-11; skip semantics revised on review) · **Date:** 2026-07-11
**Drives:** amendments to SPEC-article-draft-pipeline (CAP-2,
`pipeline-stages.md`), SPEC-writing-assistant (owner-facing proposal
contract)
**Evidence:** `docs/dogfood-findings.md` — 2026-07-11 "draft-article run
(Stage 2 gap interview, F1 on the `papers` repo)" (both findings + what
worked); 2026-07-10 "cross-cutting (interview & review UX)" and
"draft-article run (gap interview)" entries

This document closes the last of the four 2026-07-11 finding clusters at the
architecture level: recommended answers, the harvest→interview de-dup
boundary with diagnostics, and the selective interview flow — the final
design cycle before implementation epics are cut.

---

## Context

The dogfooded Stage-2 run failed the owner three ways at once:

1. All five questions were answerable from declared repo material — the
   pipeline spent the scarce owner-attention budget on extraction, the exact
   inversion the SPEC's premise warns against — and nothing in run state
   could attribute *why* those questions survived de-dup.
2. Answers were collected as free-form text (`q1: <answer>`), violating the
   owner-facing proposal contract's selective flow.
3. The prompt shipped damaged: a missing Effect line and several fields
   truncated mid-sentence — nothing validated the assembled prompt before it
   reached the owner.

And one thing worked: asked to answer the questions from repository
knowledge, the assistant produced a source-groundable candidate for every
one — confirmed by the owner as the interaction Stage 2 must lead with.

**The unifying observation:** the de-dup gap and the recommended-answer
requirement are the same boundary seen from two sides. Both reduce to one
question asked per candidate interview question: *what can the fact sheet
say about this?* The design below makes that boundary explicit, exhaustive,
and recorded.

---

## Decisions

### D1 — Every candidate question is triaged into exactly one of three outcomes

Question generation runs against the harvest output only — the fact sheet
and the NEEDS-OWNER list, both already source-pointed. Reading beyond them
is harvesting, and harvest is stage 1's contract (CAP-2's declared-sources
discipline is not re-litigated here). Per candidate question:

| Outcome | When | What the owner sees |
|---|---|---|
| **Suppressed** | Fact-sheet entries fully cover the question's information need | Nothing — the question never reaches the owner |
| **Recommended** | Fact-sheet / NEEDS-OWNER entries provide a groundable candidate answer — including recorded owner judgments in sources (a dev log noting what surprised them *is* a sourced owner statement) | The question, with the source-pointed recommended answer as the default choice |
| **Open** | Neither — genuinely owner-only knowledge | The question, with bullet free-text as the primary input (the proposal contract's existing allowance for owner-only knowledge) |

The dogfooded failure (five answerable questions asked blank) becomes
structurally impossible to ship silently: material coverage either
suppresses the question or surfaces as its recommended answer.

NEEDS-OWNER re-raises are always **recommended**, never open: the
recommended answer is the unconfirmed claim itself, presented for
confirm/deny — the claim's context is the grounding.

### D2 — Recommended answers: approve / modify / replace, with provenance dispositions

Each **recommended** question presents choices per the owner-facing proposal
contract (effect-stating labels), minimally:

- **Approve** — the recommended answer becomes the interview answer
  verbatim, *keeping its source pointers*;
- **Modify** — the owner edits the recommended answer; the edit is the
  owner's contribution on top of the grounding;
- **Replace** — the owner supplies their own bullet; the recommendation is
  discarded;
- **Skip** — the question goes unanswered; the interview engine records
  only the disposition and never decides the effect (owner-set,
  2026-07-11). What a skip *means* is the target framework slot's declared
  contract — omit the slot, defer the decision, accept the recommended
  answer later, fill with `[VERIFY]`-marked inference, or raise a publish
  blocker — and the skip choice's label states that slot's declared effect,
  per the proposal contract. The engine captures owner intent; the
  framework contract determines the consequence.

**Provenance of dispositions** (integrates with the harness decision,
`docs/harness-architecture.md` D1): an interview answer records its
disposition. An *approved* answer carries its source pointers — downstream
it grounds sourced claims exactly like a fact-sheet entry. *Modified* and
*replaced* answers are interview-sourced (owner judgment), the pointer class
that already exists. Recommendation generation is a **view over harvest
output** — it can introduce no new unsourced material by construction, so
Stage 2 needs no separate provenance gate.

This is the budget inversion the owner required: approving a grounded
answer costs seconds; owner typing is reserved for the **open** outcome and
the modify/replace paths — the originality the pipeline cannot manufacture.

### D3 — The interview journal makes the boundary attributable from run state

Stage 2 writes an **interview journal** to the run workspace
(`docs/storage-architecture.md` D2) recording every triage verdict:

```
Q1: asked   outcome=recommended  rationale=owner-judgment      rec<-fs-22,fs-31  disposition=approved
Q2: asked   outcome=recommended  rationale=needs-owner-reraise rec<-no-17        disposition=modified
Q3: asked   outcome=open         rationale=topic-absent                          disposition=answered
Q6: suppressed                   covered-by=fs-08,fs-12
```

- Every **asked** question records why it survived (`topic-absent` |
  `needs-owner-reraise` | `owner-judgment`), its recommendation's grounding
  pointers (when recommended), and the owner's disposition.
- Every **suppressed** question records the covering entries.

This is the diagnostic the findings demanded: when Stage 2 misbehaves — a
question asked that sources could answer, or a question suppressed that
should not have been — the failure is attributable from the journal (harvest
scope gap vs. de-dup miss vs. triage error) instead of being discovered by
the owner mid-interview. Line format is illustrative; the contract is the
recorded fields, not the syntax.

### D4 — Selective presentation is the contract, and payloads are validated before the owner sees them

Two engine-wide additions to the owner-facing proposal contract
(SPEC-writing-assistant), since review arbitration and Stage-4 verification
share the same failure modes:

1. **Selective presentation is the primary interaction model.** Every
   proposal surface presents choice-based selective prompts; free-form text
   entry appears only as the input mode for owner-only knowledge (D1's
   *open* outcome, and the modify/replace paths). Collecting answers as
   free-form text where choices are mandated (the `q1: <answer>` run) is a
   contract violation, not a presentation preference.
2. **Payload integrity validation.** The assembled prompt payload is
   validated mechanically before presentation: every item carries its
   Where / Why / Effect fields, non-empty and untruncated. Content must fit
   its field's display budget **by authorship** (write shorter), never by
   clipping — a payload that exceeds its budget is re-authored, and a
   validator failure blocks presentation the way `verify-markers` blocks
   stage progression. Both damaged-context defects from the dogfood run
   (missing Effect line, mid-sentence truncation) are seeded test cases.

---

## Consequences — spec amendments this decision drives

| Spec | Amendment |
|---|---|
| **SPEC-article-draft-pipeline** | CAP-2 reworked: three-outcome triage over harvest output (D1); surviving questions presented selectively with recommended answers and approve/modify/replace/skip dispositions (D2); interview journal in the run workspace as the boundary diagnostic (D3). Success criteria gain: a question fully covered by the fact sheet never reaches the owner; every asked question's survival rationale is attributable from the journal. |
| **`pipeline-stages.md`** | Stage-2 row updated (selective prompts, recommended answers, journal output). Interview-question-bank section gains the triage rule and recommendation derivation. New "Interview journal (stage 2)" section with the recorded fields. Interview answers noted as carrying disposition + pointers (provenance integration). |
| **SPEC-writing-assistant** | Owner-facing proposal contract gains (d) selective presentation as the primary interaction model and (e) payload integrity validation (D4) — engine-wide, inherited by review arbitration and Stage-4 verification without restating. |
| **SPEC-article-frameworks** | New constraint: each framework slot declares the effect of a skipped interview input feeding it (omission, deferral, accept-later, `[VERIFY]` inference, or publish blocker); the interview engine records only the disposition (D2). Per-slot values are template content, authored with the templates. |

Not amended: SPEC-article-review (inherits D4 through the spine contract it
already references); harvest contracts (D1 deliberately builds on harvest
output as-is — scope gaps become *attributable*, not silently fixed).

---

## Open questions

1. **Triage judge cost.** Suppression and recommendation derivation are one
   cheap LLM pass over fact sheet + question bank; is per-question
   grounding-coverage confidence worth recording in the journal for later
   tuning, or is the three-outcome verdict enough signal?
2. **Prompt-mechanism budgets.** Field display budgets (D4.2) depend on the
   presentation mechanism's real limits; the validator's constants belong
   with the implementation, not this contract — but the seeded-defect tests
   are contractual.

(A third question — engine-default skip semantics — was resolved during
review: there is no engine default; see D2. Per-slot values are authored
with the framework templates.)
