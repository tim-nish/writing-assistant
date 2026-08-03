# Article-quality rubric

<!-- rubric-version: 2 -->

The fixed quality standard a draft must meet at the fill→verify gate
(SPEC-article-draft-pipeline CAP-7; `docs/harness-architecture.md` D4).
"Readable" is **this rubric**, not whatever an agent happens to produce.

This is a **versioned plugin asset**: exemplar-derived threshold tuning edits
**this file** (bump `rubric-version` above), never the specs. Five dimensions,
each with an **operational check** — a test with a definite verdict, not a vibe.
Dimensions 1–2 and 5 are judged by one single-pass cheap-tier rubric judge;
dimensions 3 and 4 are mechanical (zero tokens — dimension 3 became a
deterministic scan on 2026-07-17, #305). A draft **passes** only when every
dimension passes — and dimension 5 is **conditional**, which is stated as an
explicit `n/a` verdict with its reason rather than an absent line, because an
absent line cannot be told apart from one nobody ran.

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
- **Stitched fact sheet fails (strengthened 2026-07-20, #440/#434).** A draft
  that reads as fact-sheet prose stitched into the framework skeleton — no
  argument, sections that merely list evidence — **fails**: it does not advance
  one claim, it enumerates. (The mechanical stitched-fact-sheet signature is a
  zero-token backstop; this dimension catches the interpretive case the
  mechanical check cannot.)
- **Per-lesson skeleton repetition fails (#434).** A multi-lesson article that
  reproduces the framework's section skeleton **verbatim per lesson** (the same
  heading set repeated) is a list, not an arc — **fail**. One arc: shared
  context, distinct and *varied* lesson sections, one synthesis. (A mechanical
  detector flags an identical heading repeated ≥3×; this dimension owns the
  varied-structure judgment.)
  **A CONTRACT-MANDATED heading is EXEMPT from this judgement (#1377).** A
  framework's `[EVIDENCE: …]` slot heading recurs once per unit *by contract* —
  F2's `What actually happened` is keyed on by the evidence gate, and renaming
  it is the `section-not-found` failure class. The two rules as written admitted
  no compliant output: a three-lesson deep-dive had to repeat that heading to
  clear one gate and had to not repeat it to clear this one. The mandated set is
  **derived from the framework assets**, never hand-listed. Everything else is
  judged exactly as before — the variation requirement over non-mandated
  structure is unchanged.
  **Beat order and heading strings are different properties (#1398).** This
  judgement, and the mechanical detector beside it, measure heading **strings**:
  an identical heading set repeated per unit fails (mandated set exempt, above).
  A constant **beat order** rendered under distinct headings is *not* skeleton
  repetition — and for `arc: thematic-braid` it is the **satisfying form**: the
  braid's "one shape seen three times" is shown by same-order beats under
  per-unit headings, never by verbatim heading sets. This clause binds every
  consumer of the rubric, including review's structure pass (which consults this
  file): a structure finding demanding "the same subsection skeleton" of a braid
  contradicts it — the compliant demand is *same beat order, distinct headings*.
  Escalation, recorded at adoption (2026-08-03): if a braid under this clause
  still collides between the fill→verify gate and review, the fix is arc-aware
  evaluation reading the plan's recorded `arc:` — never a widening of this
  exemption.
- **Plan-conformance (#440).** When the run composed an argument plan
  (`$WS/argument-plan.md`: thesis, arc, section intents), the draft must
  **advance that thesis** — a section that does not serve the planned thesis, or
  that fills its slot with a single under-evidenced sentence, **fails**. This
  makes skeleton drafts fail the fill→verify gate **before** review; review is a
  second net.

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

**This obligation is depth-blind (Story 20.169, #1285).** The CAP-8 depth/scope
directive moves how much material an article carries; it is **not** a register or
difficulty setting and **never** relaxes this dimension. A run that answered
`deep-dive` owes exactly the same introduction at first load-bearing use as one
that answered `note` — the audience the hook slot names is the only calibration
input. (The depth ask was reworded to say so, because a run read "how deep should
this go" as permission to leave repo-internal terms unexplained; the permission
never existed, here or anywhere.)

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

## Dimension 5 — Both ends realize the plain-register commitment (judged; added 2026-08-04, #1412)

Both ends of the article realize the Brief's plain-register commitment
(#1411) **semantically — never as the same sentence.**

- **Operational check — recoverability, per end:** after reading the opening
  alone, can the reader state the committed claim? After reading the close
  alone, can they? Each end is a separate verdict against the **adopted
  commitment**, and the judge is handed that commitment and the two end
  sections — **never a target sentence, because none exists.**
- **A string match is the ANTI-check.** Identical or near-identical thesis
  sentences at open and close **fail** this dimension. The commitment is a
  proposition, not a template slot; a draft that pastes one sentence at both
  ends has rebuilt the fixed-template shape the structure ruling (#1410)
  removed, and it fails here even though both ends "carry" the claim.
- **The close composes the simplified Strand renderings.** The closing
  restatement places the committed renderings or **discloses omissions by
  name** — the standing cover-counted-in-placements requirement, applied at
  the close.
- **Realization form is not this dimension's.** Whether the opening is a
  complete simple statement, a leading question, or a failure-case entry is
  decided by the adopted **structure** (#1410). This dimension asserts only
  that whatever realization was chosen carries the committed claim.
- **Conditional, and its absence is a DISCLOSURE.** A run whose Brief carries
  no plain-register commitment has nothing to realize: the dimension emits
  `dim5: n/a — no plain-register commitment on the brief` and the draft may
  still pass. That is a fact about the brief, never a gap and never a silent
  skip — the verdict record carries the line either way.

## Dimension separation — length is dimension 4's, flow is dimensions 1–2's (#349, Story 13.66)

Dimensions 4 (mechanical) and 1–2 (LLM-judged) must not double-count the same
edit, or a fix for one re-triggers the other and revision oscillates (the
observed dim4 sentence-split re-triggering a dim1/dim2 finding):

- **Dimension 4 owns length and vocabulary distribution** — sentence length,
  paragraph length, heading density, sourced-claim density. These are the
  mechanical, zero-token concerns.
- **Dimensions 1–2 own only the interpretive concerns** — narrative arc,
  one-idea-per-paragraph, connective tissue, orphan facts. A dim1/dim2 finding
  **must cite a narrative or flow defect**, never a sentence- or
  paragraph-*length* artifact that dimension 4 already governs.
- **A sentence split or merge performed to satisfy dimension 4 is neutral for
  dimensions 1–2.** Splitting a >40-word sentence into two shorter ones, or
  merging two fragments, is a length edit — dimensions 1–2 do not raise a new
  finding solely because a sentence was split or joined. (Dimension 4's
  paragraph "wall of text" check *cross-references* dimension 2 as a hint, but
  the length threshold is dimension 4's verdict, not a second dim2 finding.)

This separation is what makes the two-cycle delta re-check (#349) converge: a
cycle that fixes a dim4 length threshold cannot manufacture a fresh dim1/dim2
interpretive finding on the same text.
