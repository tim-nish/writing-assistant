# Dogfood findings

Running log of observations from dogfooding the writing-assistant plugin on real
material. Records **what worked** (so we don't regress it) and **usability
issues** (candidates for later fixes). This log only *records* findings — fixes
are tracked separately and are not applied here.

Each run is a dated section. Newest at the top. Issues carry a rough severity
(`friction` / `papercut` / `blocker`) so they can be triaged later.

---

## 2026-07-10 — review-article run

**Scope:** the `review-article` workflow and pipeline-wide configuration validation.

### Usability issues

- **[friction] Configuration placeholders should be validated before article
  generation.** The review completed successfully and reported the draft as
  publishable, but only at the very end surfaced unresolved configuration
  placeholders — a `canonical_url` with a double slash and the default
  pointer-block site name. These are **configuration** problems, not
  article-quality issues. The pipeline should validate required configuration
  values **before** generating or reviewing the article, reporting placeholder
  values, malformed URLs, and obvious configuration mistakes early in the
  workflow. Separating article quality from publishing configuration would reduce
  confusion and prevent users from reaching the end of the pipeline only to
  discover avoidable configuration problems.

---

## 2026-07-10 — cross-cutting (interview & review UX)

**Scope:** synthesis across the `draft-article` gap interview and the
`review-article` stages — a pattern spanning several individual findings below.

### Usability issues

- **[friction] Gap interview and review questions need usability validation, not
  just content validation.** Across dogfooding, many questions required
  understanding the *generated article* rather than simply answering from the
  *repository*. Several prompts assumed the user already understood:
  - where the referenced section appears in the article,
  - why the question was being asked,
  - what effect each choice would have on the final article, and
  - whether enough context had been shown to make an informed decision.

  The workflow appears to optimize for *collecting answers*, but there is little
  evidence that the usability of the questions themselves has been evaluated. The
  interview and review stages should be reviewed from a UX perspective:
  - Is the intent of every question immediately obvious?
  - Is enough article context shown before asking for a decision?
  - Can a first-time user answer confidently without already knowing the
    generated draft?
  - Does each choice clearly explain its effect on the article?

  The goal of the workflow is to help users write articles from repository
  knowledge alone. If users must already understand the generated article to
  answer the questions, the workflow creates unnecessary cognitive load and
  partially defeats that goal. (The section-context, approval-consequence, and
  completion-summary findings below are concrete instances of this pattern.)

---

## 2026-07-10 — draft-article run (completion summary)

**Scope:** the `draft-article` pipeline's end-of-run completion summary.

### Usability issues

- **[friction] Completion summary mixes successful output with required manual
  actions.** The summary's "Before you publish" section actually blends
  unresolved issues and configuration problems together with informational notes.
  A clearer distinction between
  - informational notes,
  - publish blockers (must be resolved before publishing), and
  - optional cleanup

  would make the end of the pipeline easier to understand — right now the user
  has to sort each item into the right bucket themselves.

---

## 2026-07-10 — draft-article run (gap interview)

**Scope:** the `draft-article` pipeline's Stage 2 bounded gap interview.

### Usability issues

- **[friction] Article section context is missing during the gap interview.**
  Interview questions such as _"The 'Why existing options fall short'
  section..."_ assume the user already knows the article structure. As a
  first-time user, it was not clear that "Why existing options fall short" was
  the title of a generated article section rather than a general question. The
  interview should explicitly show:
  - where this section appears in the article outline,
  - why this question is being asked, and
  - a short preview of the current section before asking the user to approve,
    modify, or delete it.

  As worded, the interview requires the user to infer the article structure,
  creating unnecessary cognitive load.

- **[friction] Approval prompts should state the consequence of each choice
  explicitly.** Some approval questions are understandable only after inferring
  the article-generation logic. For example, _"Keep as an honest estimate"_ is
  ambiguous on first read — it does not state what will actually happen to the
  article. Each choice should instead describe its concrete effect, e.g.:
  - _Keep the "1–2k notes" claim, explicitly marked as an unmeasured design
    estimate._
  - _Remove the "1–2k notes" claim from the article._

  In general, every approval choice should describe the resulting article change
  rather than relying on a shorthand label, so the user's decision is unambiguous.

---

## 2026-07-10 — harvest run

**Scope:** standalone `harvest` against a host repo with sources declared in
`writing-sources.yaml`.

### What worked

- **Source scoping honored.** Harvest respected `writing-sources.yaml` and
  scanned **only** the declared sources — no undeclared repo or path was read
  (CAP-2 behavior held).
- **Every fact commit-pinned and validated.** All extracted facts on the fact
  sheet carried a resolvable, commit-pinned SOURCE and passed the fact-sheet
  validation; no entry landed without a source.
- **NEEDS-OWNER surfaced the right claims.** The NEEDS-OWNER mechanism correctly
  partitioned unsupported or unverifiable candidate claims off the fact sheet and
  onto the NEEDS-OWNER list, so nothing unsourceable slipped through unmarked.

### Usability issues

- **[friction] First-time setup was harder than expected.** Getting to a first
  successful run took more effort than anticipated. Two specific confusions:
  - The distinction between **`user-config.yaml`** (owner identity, machine-global)
    and **`writing-sources.yaml`** (per-repo sources + draft location) was not
    obvious from the README — which file holds what, and where each resolves.
  - The purpose of the **syndication / frontmatter** configuration was unclear;
    the README doesn't make plain what it drives or why it's needed before a run.
- **[papercut] Harvest completion is a dead end.** The completion message reports
  results and then stops. It should suggest the next step — e.g. reviewing the
  emitted fact sheet, or running `draft-article` — so the user isn't left
  guessing how to continue the pipeline.
