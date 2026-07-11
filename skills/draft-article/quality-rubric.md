# Article-quality rubric

<!-- rubric-version: 1 -->

The fixed quality standard a draft must meet at the Stage 3→4 gate
(SPEC-article-draft-pipeline CAP-7; `docs/harness-architecture.md` D4).
"Readable" is **this rubric**, not whatever an agent happens to produce.

This is a **versioned plugin asset**: exemplar-derived threshold tuning edits
**this file** (bump `rubric-version` above), never the specs. Four dimensions,
each with an **operational check** — a test with a definite verdict, not a vibe.
Dimensions 1–3 are judged by one single-pass cheap-tier rubric judge; dimension
4 is mechanical (zero tokens). A draft **passes** only when every dimension
passes.

## Dimension 1 — Narrative arc

The article advances **one claim**, and every section advances it.

- **Operational check — section-level deletion probe:** remove a section. If
  its removal leaves a **hole in the argument** (a later section now references
  something unestablished, or the claim is no longer supported), the section
  earns its place. If removal leaves only *less text* — the argument still
  stands — the section is a digression: **fail**, naming the section.
- **The arc is stated:** the draft's **first section commits to the one claim**
  the cold read must later recover. A draft whose opening states a topic, not a
  claim, fails this dimension.

## Dimension 2 — Paragraph flow

- **One idea per paragraph, topic sentence first:** each paragraph's first
  sentence states its point; the rest support it. A paragraph carrying two ideas
  is split; a paragraph whose point arrives last is reordered.
- **Consecutive paragraphs connect:** the connective tissue that the three
  provenance classes make legal (`docs/harness-architecture.md` D1) — a derived
  or narration sentence linking one paragraph's conclusion to the next's premise.
- **No orphan facts:** a fact-sheet entry appears **inside an argument**, never
  as a standalone bullet dressed as prose. An orphan fact — a sourced sentence
  that no surrounding sentence sets up or draws a consequence from — is a
  **fail**, naming its location.

## Dimension 3 — Explanation calibration

Every **repo-internal term, project name, or acronym** is **introduced before
its first load-bearing use**, calibrated to the audience the framework's **hook
slot** names (the drafting-side counterpart of the cold read's missing-context
check).

- **Operational check — term-introduced-before-first-use:** for each such term,
  find its first load-bearing use; a one-time gloss, expansion, or defining
  sentence must precede it. A term used load-bearingly before it is introduced
  is a **fail**, naming the term and the line.
- Calibration is audience-relative: a term the stated audience already knows
  needs no gloss; the check is *unintroduced-and-unknown-to-this-audience*, not
  *every term*.

## Dimension 4 — Readability mechanics (mechanical, zero tokens)

Lint-class distribution checks; no model judgment. Thresholds are **conservative
v1 defaults**, tuned here from dogfood/exemplar runs (Open question 3):

- **Sentence length:** flag when the mean sentence length exceeds **30 words**,
  or when **>25%** of sentences exceed **40 words**.
- **Paragraph length:** flag a paragraph exceeding **8 sentences** or **160
  words** (a wall of text — likely >1 idea, cross-checks dimension 2).
- **Heading density:** flag a section whose body exceeds **~400 words** with no
  subheading (already a review-lint check); flag a document with **zero**
  section headings.
- **Quote/sourced-claim density per section:** using the sidecar provenance map,
  flag a section whose sentences are **>70% `sourced`** with **no `derived` or
  `narration` tissue** — the mechanical signature of a **stitched fact sheet**
  (the blocker artifact `docs/harness-architecture.md` closes).

A metric crossing its threshold is a dimension-4 **fail**, reported with the
location and the measured value.
