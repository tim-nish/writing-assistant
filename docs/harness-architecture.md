# Article-quality harness — architecture decision

**Status:** accepted (owner, 2026-07-11; derivation rule owner-set on review) · **Date:** 2026-07-11
**Drives:** amendments to SPEC-article-draft-pipeline, SPEC-article-review,
SPEC-writing-assistant
**Evidence:** `docs/dogfood-findings.md` — 2026-07-11 "pipeline outcome
(article quality)" (blocker) and "design tension: quality gating vs.
provenance-first drafting" (friction)

This document resolves the design tension recorded on 2026-07-11 and defines
the mandatory article-quality harness the owner directed. It is a decision
record, not a spec: per SPEC-writing-assistant's adopted-contract constraint,
the behavioral changes decided here land as spec amendments (§ Consequences),
and implementation follows those specs.

---

## Context

Two findings, taken together, define the problem:

1. **The blocker:** a draft can pass every existing gate — provenance,
   structure/prose review, arbitration — and still not read as a coherent
   explanatory article. Drafting optimizes claim safety only; review quality
   findings are advisory; no explicit quality standard exists.
2. **The tension:** a naive quality gate deadlocks against the provenance
   contract. Quality demands synthesis — narrative arc, connective reasoning,
   calibrated explanation — which *generates sentences no single source
   pointer covers*. Stage 3's contract ("copy facts, don't summarize them
   into new claims"; `[VERIFY]` on anything unsupported) forbids exactly
   that. Prose good enough for the quality gate accumulates undischargeable
   `[VERIFY]` markers; prose clean enough for the provenance gate reads as a
   stitched fact sheet.

The findings entry names the crux: *at what granularity does provenance
attach?* A quality harness, a provenance contract, and a claim/narration
boundary are one design problem, not three. This document decides all three
together.

---

## Decisions

### D1 — Provenance attaches at claim level; synthesis is legal at paragraph level

Every **sentence** in a draft belongs to exactly one of three provenance
classes:

| Class | Definition | Provenance obligation |
|---|---|---|
| **Sourced claim** | Asserts something traceable to one fact-sheet entry or interview answer | Carries that pointer (unchanged from today) |
| **Derived claim** | Asserts something synthesized *from* ≥2 sourced claims — a topic sentence, a summary, a restatement across facts | Carries **inherited provenance**: the pointers of every input it draws on. Legal only within the derivation rule below; exceeding it makes the sentence an inferred claim → `[VERIFY]` |
| **Narration** | Asserts nothing checkable: transitions, signposting, framing, restatement of an adjacent sourced claim, reader-directed explanation of structure | None — no pointer, no marker |

**Derivation rule (owner-set, 2026-07-11):** a derived claim may
**compress, combine, or restate** its named source claims, but must not
introduce new **causality, significance, evaluation, comparison, intent, or
scope**. The three permitted operations are information-preserving or
information-reducing; the six forbidden categories are exactly the ways a
synthesis can assert *more* than its inputs. A sentence that commits any of
the six is not a derived claim — it is an inferred claim and takes
`[VERIFY]` (or, if the addition is genuinely the owner's judgment, it routes
to the interview, the pipeline's existing channel for significance and
opinion).

| Forbidden addition | Smell example (inputs: "A took 40ms", "B took 90ms") |
|---|---|
| Causality | "A is faster **because of** its cache layout" |
| Significance | "the **most important** result was A's latency" |
| Evaluation | "A performed **well**" |
| Comparison | "A **outperformed** B" — even arithmetic comparison asserts a comparability the inputs may not support |
| Intent | "we chose A **to avoid** B's overhead" |
| Scope | "A is **always** faster" / "**in all workloads**" |

("A took 40ms and B took 90ms in the benchmark" — a pure combination —
remains a legal derived claim carrying both pointers.)

This replaces the binary today (sourced-or-`[VERIFY]`) that made connective
tissue illegal. The quality harness's demand for synthesis is satisfied by
classes 2 and 3; the provenance guarantee ("zero unmarked invented claims",
CAP-3 of the draft pipeline) is preserved because *claims* — sourced or
derived — still trace to fact-sheet entries, and anything beyond them still
takes `[VERIFY]`.

Stage 3's drafting rule is amended accordingly, from
*"copy facts, don't summarize them into new claims"* to:

> Copy facts into sourced claims. Derived claims are permitted only as
> explicit syntheses over named fact-sheet inputs and inherit those
> pointers; a derived claim may compress, combine, or restate its inputs
> but must not introduce new causality, significance, evaluation,
> comparison, intent, or scope — a sentence that does is an inferred claim
> and takes `[VERIFY]`. Narration carries no assertion and needs no
> pointer, bounded by the falsifiability test (D2).

### D2 — The claim/narration boundary is the falsifiability test

The findings warn that the boundary "is exactly where invented assertions
hide," so it must be an operational test, not a vibe:

- **Falsifiability test:** *Could a reviewer with access to all declared
  sources mark this sentence false?* If yes, it is a claim (sourced,
  derived, or `[VERIFY]`). If no, it is narration.
- **Deletion probe (tie-breaker):** delete the sentence. If any reader
  belief *about the subject matter* changes, it was a claim; if only the
  flow degrades, it was narration.

> **Amended 2026-07-12 (triage #123).** "Independent of the drafting context"
> is operationalized: the `verify-provenance` judge runs in a **subagent that
> never saw the drafting turn**, and the D3 CAP-7 rubric judge (dimensions 1–3)
> inherits the same isolation — the drafting context grades neither its own
> claim/narration boundary nor its own rubric pass. See NFR13 and CAP-7 in
> SPEC-article-draft-pipeline.

Sentences that smuggle assertions into connective form ("this naturally led
to a 3× speedup", "as every practitioner knows") fail the falsifiability
test and are claims regardless of their rhetorical dress.

**Enforcement is adversarial, not self-reported.** The drafting agent
classifies its own sentences (cheaply, as it writes), but classification is
verified by an independent check that does not share the drafting context:
a `verify-provenance` pass walks every narration-classed sentence and
applies the falsifiability test; any narration sentence that asserts a
checkable proposition is a gate failure. This mirrors the cold-read
principle already in SPEC-article-review: the agent that produced the text
never grades its own boundary.

**Mechanics:** classification lives in a **sidecar provenance map**
(per-paragraph: sentence → class → pointers), not inline in the draft — the
draft body stays clean for variants and review. `[VERIFY]` markers remain
inline exactly as today; `verify-markers --count → 0` is untouched as
Stage 4's exit criterion.

### D3 — The quality gate sits at Stage 3→4 and is a stage-progression gate

Placement rationale:

- **Before the owner, not after.** Stage 4 spends the owner's ~4-minute
  verification budget; that budget must land on a draft that already reads
  as an article. Quality retries cost AI wall-clock, which the pipeline
  explicitly does not constrain ("wall-clock time is unconstrained").
- **Like `verify-markers`, not like a review finding.** The gate is a
  precondition on stage progression: Stage 3 does not complete until the
  gate passes. This is the owner's directive verbatim — a gate, not an
  advisory finding — and it is why the harness lives in the draft pipeline,
  not in review.
- **Review remains the second net, now with teeth.** In SPEC-article-review,
  structure/prose findings that map to a rubric dimension (D4) are
  **blocker-eligible**: a finding demonstrating a rubric violation blocks
  the "publishable" verdict, exactly as configuration blockers already do.
  This simultaneously answers the severity-model transparency finding: a
  finding is a blocker *because it names the rubric criterion it violates*
  (or a cold-read Q1/Q2 mismatch, or a config defect) — the rationale field
  the findings contract was missing.

### D4 — The quality standard is a fixed four-dimension rubric, mechanically assisted

The rubric is defined once, versioned in the plugin (a skill asset, like the
framework templates), and applied by the gate. Dimensions, from the blocker
finding's own root-cause list:

1. **Narrative arc.** The article advances one claim; every section
   advances it (section-level deletion probe: removing a section must leave
   a hole in the argument, not just less text). The arc is stated — the
   draft's first section commits to the claim the cold read must later
   recover.
2. **Paragraph flow.** One idea per paragraph, topic sentence first;
   consecutive paragraphs connect (the connective tissue D1 just made
   legal). No orphan facts: a fact-sheet entry appears inside an argument,
   never as a standalone bullet dressed as prose.
3. **Explanation calibration.** Every repo-internal term, project name, or
   acronym is introduced before first load-bearing use, calibrated to the
   audience the framework's hook slot names. (This is the drafting-side
   counterpart of the cold read's missing-context check.)
4. **Readability mechanics.** Zero-token, lint-class checks: sentence- and
   paragraph-length distributions, heading density (already in review lint),
   fact-sheet-quote density per section (a stitched fact sheet shows up as
   wall-to-wall sourced claims with no narration/derived tissue — the
   provenance map from D2 makes this measurable for free).

**Gate composition:** dimension 4 is mechanical (extends the existing
zero-token lint). Dimensions 1–3 are judged by **one single-pass LLM rubric
judge** per gate attempt — cheap-tier, findings-format output (pass/fail per
dimension + the failing locations), no rewritten text. Single-pass keeps
faith with review's token-economy constraints ("no multi-agent adversarial
review as the default"); the adversarial element is the independent
`verify-provenance` check (D2), which is scoped and cheap.

**Exemplar calibration (input task, not a blocker to speccing):** the owner
directed studying trusted agents/plugins that consistently produce
high-quality technical articles. That study calibrates the rubric's
thresholds and judge prompt with exemplar excerpts; it does not change the
four dimensions or the gate mechanics decided here. It is scheduled as a
research task feeding the rubric asset, so spec amendments need not wait on
it.

### D5 — Bounded retry loop, then surface — never silent iteration

On gate failure, Stage 3 revises against the specific failing dimensions and
re-runs the gate. Bounds:

- **≤2 rubric-driven revision cycles** per draft. The existing pipeline
  principle ("a section needing more than one rewrite routes back to a new
  interview question, never into open-ended editing") extends to the
  harness: if the gate still fails after two revisions, the failure is
  surfaced to the owner as a **publish blocker** in the completion summary
  (CAP-6 bucket), with the failing dimensions and locations — not silently
  retried, not silently waived.
- Every revision re-runs **both** gates — quality rubric *and*
  `verify-provenance` — because revision for readability is precisely where
  unmarked claims would otherwise re-enter. A revision that fixes flow by
  inventing a transition-claim fails provenance, not quality; the deadlock
  is broken by D1's classes, not by relaxing either gate.

---

## The deadlock, re-examined

The 2026-07-11 tension entry described the failure mode: quality-passing
prose accumulates undischargeable `[VERIFY]` markers because "transitions
and framing have no source." Under D1/D2 that sentence class is narration —
it never needed a source, so it never takes a marker. The marker burden
falls only on genuine assertions, which either trace to the fact sheet
(sourced/derived) or genuinely need owner verification (`[VERIFY]`, as
today). Conversely, fact-sheet-stitched prose now *fails the quality gate*
(dimension 2/4: no connective tissue, orphan facts), so the provenance-safe
escape hatch that produced the blocker artifact is closed. Each gate closes
the other's escape route; the provenance classes are what make it possible
for both to be satisfiable at once.

---

## Consequences — spec amendments this decision drives

| Spec | Amendment |
|---|---|
| **SPEC-article-draft-pipeline** | New CAP: mandatory quality gate at Stage 3→4 (rubric + mechanical checks + bounded retry, D3–D5). CAP-3 amended: three provenance classes and the sidecar provenance map replace the binary sourced-or-`[VERIFY]` rule (D1). Constraints: drafting rule rewording (D1), falsifiability test + independent `verify-provenance` (D2), retry bound + blocker surfacing (D5). `pipeline-stages.md`: gate row between stages 3 and 4; provenance-map format section. |
| **SPEC-article-review** | Constraint amendment: rubric-mapped structure/prose findings are blocker-eligible and block "publishable" (D3). Findings format gains a **rationale field** naming the criterion that sets the severity — resolving the severity-model finding. `review-prompts.md`: severity criteria table (blocker = rubric violation / cold-read Q1–Q2 / config; should-fix = cold-read Q3–Q4 / non-rubric structure-prose; nit = polish). |
| **SPEC-writing-assistant** | CAP-3's success criterion gains the quality clause: "…zero unmarked invented claims **and the draft passes the article-quality gate**." Rubric asset noted in `plugin-layout.md` alongside the framework templates. |

Out of scope here (separate findings, separate fixes): plugin footprint
(config/intermediate-output locations), Stage-2 recommended answers and the
harvest→interview de-dup diagnostic.

---

## Open questions

1. **Classifier reliability.** Does `verify-provenance` check every
   narration sentence or a risk-weighted sample? Full walk is the safe
   default for v1; measure cost during dogfooding before considering
   sampling.
2. **Derived-claim coverage validation.** Pointer resolution is mechanical
   (each derived claim's pointers resolve to fact-sheet entries). The
   exceed-check is now a closed checklist — the derivation rule's six
   forbidden categories (causality, significance, evaluation, comparison,
   intent, scope) — so `verify-provenance` tests each derived claim against
   six named categories rather than open-ended judgment. Remaining
   question: per-category verdicts from one pass, or is a single
   any-category-violated verdict reliable enough?
3. **Rubric thresholds.** Dimension-4 numeric bounds (sentence/paragraph
   length, quote density) await the exemplar study; ship v1 with
   conservative defaults and tune from dogfood runs.
4. **Where the provenance map lives.** Sidecar file next to the draft vs.
   the run's workspace — interacts with the plugin-footprint finding
   (intermediate outputs polluting the host repo); decide both together.
   **Answered 2026-07-11:** the run workspace —
   `docs/storage-architecture.md` D2.
