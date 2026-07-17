# Article-quality rubric

<!-- rubric-version: 1 -->

The fixed quality standard a draft must meet at the Stage 3→4 gate
(SPEC-article-draft-pipeline CAP-7; `docs/harness-architecture.md` D4).
"Readable" is **this rubric**, not whatever an agent happens to produce.

This is a **versioned plugin asset**: exemplar-derived threshold tuning edits
**this file** (bump `rubric-version` above), never the specs. Four dimensions,
each with an **operational check** — a test with a definite verdict, not a vibe.
Dimensions 1–2 are judged by one single-pass cheap-tier rubric judge;
dimensions 3 and 4 are mechanical (zero tokens — dimension 3 became a
deterministic scan on 2026-07-17, #305). A draft **passes** only when every
dimension passes.

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

## Dimension 3 — Explanation calibration (deterministic; amended 2026-07-17, #305)

Every **repo-internal term, project name, or acronym** is **introduced at or
before its first load-bearing use**, calibrated to the audience the framework's
**hook slot** names (the drafting-side counterpart of the cold read's
missing-context check). This dimension is a **closed scan over repo
vocabulary**, not open-ended judgment: the drafting side and the gate apply the
same written rule below, and a verdict carries the **complete** violation set —
never one violation per pass.

- **Operational check — term-introduced-at-or-before-first-use:** for each
  registered term, find its first load-bearing use; an introduction (below) must
  stand at or before it. A term used load-bearingly with no introduction is a
  **fail**, naming the term and the line. *(Renamed from
  term-introduced-**before**-first-use on 2026-07-17, #305: an inline appositive
  gloss AT the point of use is now explicitly sufficient — the reader never meets
  the term unexplained, and the old name implied a placement rule the rubric
  never actually settled. That ambiguity is what four revision cycles kept
  re-litigating.)*

**Introduction contract — each form is explicitly sufficient or insufficient:**

- **Sufficient:** a defining sentence or one-time gloss *preceding* the first
  load-bearing use; an **inline appositive gloss at the point of first
  load-bearing use** (the reader never meets the term unexplained); an
  abbreviation **expanded with its gloss** at first use.
- **Insufficient / neutral:** a **heading** occurrence is neither an
  introduction nor a load-bearing use — it triggers nothing and satisfies
  nothing; a **diagram label** IS a load-bearing use and requires a prose
  introduction before the diagram; a bare **expansion of an already-introduced
  base term** (e.g. "de-dup" → "de-duplication check") never re-promotes the
  term to unintroduced.

**The gated inventory is a contract, not a convenience list (#305).** The scan
gates exactly the vocabulary registered in
[`internal-vocabulary.json`](internal-vocabulary.json) — so a `dim3: pass` means
*nothing in the registered inventory was uncalibrated*, and the gate stamps
`dim3_inventory` (version + counts) beside the verdict to keep that scope
visible. **Registration is mandatory:** introducing a new internal stage name,
framework ID, marker, diagram label, or pipeline term means registering it in
the same change. `check-internal-vocabulary.sh` derives the families that have a
canonical machine source — framework IDs (`FRAMEWORK_PRIORITY`), pipeline stage
names (`next_stage` vocabulary), and the owner-facing markers — and **fails**
when one is unregistered, so those cannot drift out of the gate unnoticed. Prose
nouns have no such source: for them the inventory is the source of truth, and
adding one is a reviewed edit. Bare words that collide with ordinary English are
registered in their unambiguous compound form (`framework fill`, not `fill`),
because a gate that flags ordinary prose is worse than the gap it closes.

**Verdict rules:**

- The scan enumerates every repo-internal term and its first load-bearing use;
  a verdict names **all** violations (term + line) in one pass. Re-running the
  scan on unchanged text yields the identical verdict.
- Calibration is audience-relative, entered **once as data**: terms the
  ratified audience answer marks as known form a per-run allowlist and are
  excluded from the scan — never re-judged per pass. The check is
  *unintroduced-and-unknown-to-this-audience*, not *every term*.
- After one revision addresses the complete reported set, a later verdict may
  add a violation **only** for vocabulary the revision itself introduced.

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
