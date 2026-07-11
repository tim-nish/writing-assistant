# Dogfood findings

Running log of observations from dogfooding the writing-assistant plugin on real
material. Records **what worked** (so we don't regress it) and **usability
issues** (candidates for later fixes). This log only *records* findings — fixes
are tracked separately and are not applied here.

Each run is a dated section. Newest at the top. Issues carry a rough severity
(`friction` / `papercut` / `blocker`) so they can be triaged later.

---

## 2026-07-11 — design tension: quality gating vs. provenance-first drafting

**Scope:** cross-cutting — the interaction between the mandatory article-quality
harness (requested in the "pipeline outcome" entry below) and the pipeline's
provenance contracts. Recorded not as a run observation but as a **structural
conflict surfaced by triaging this date's findings together** — valuable as a
research question in its own right.

### Design tension (record for future research)

- **[friction] A strict quality harness and the provenance rules pull the
  drafting stage in opposite directions.** The quality harness demands
  synthesis: narrative arc, connective reasoning between facts, paragraph flow,
  explanation calibrated to the reader — all of which *generate new sentences
  that no single source pointer covers*. Stage 3's claim-safety contract
  demands the opposite: "copy facts, don't summarize them into new claims",
  verbatim interview answers, and a `[VERIFY]` marker on anything a source does
  not fully support. Enforced together naively, the two gates deadlock: prose
  good enough to pass the quality gate accumulates `[VERIFY]` markers it cannot
  discharge (transitions and framing have no source), while prose clean enough
  to pass the provenance gate reads as a stitched fact sheet — the exact
  blocker recorded below.
  - **The open design question:** at what granularity does provenance attach?
    Claim-level provenance with paragraph-level synthesis (connective tissue is
    "authorial voice", not claims, and needs no marker) is the obvious
    candidate — but it requires a *definition* of which sentences are claims
    versus narration, and that boundary is exactly where invented assertions
    hide. A quality harness, a provenance contract, and a claim/narration
    classifier are therefore one design problem, not three.
  - **Why this is research-worthy beyond this repo:** any system that generates
    trustworthy long-form text from sourced facts (survey generation,
    grounded report writing, RAG-based authoring) faces the same
    faithfulness-vs-fluency trade-off; a workable granularity rule plus a
    gating harness here is a reusable result, not a plugin patch.

---

## 2026-07-11 — pipeline outcome (article quality)

**Scope:** the quality of the final drafted article itself, after a full
draft-article + review-article cycle.

### Usability issues

- **[blocker] The generated article is still difficult to understand as an
  article.** Despite passing the pipeline — provenance gates, structure and
  prose review passes, arbitration — the output does not read as a coherent,
  explanatory technical article. Tagged blocker because the artifact fails the
  pipeline's core promise (a publishable draft), even though no stage halted.
  Root causes, from the current contracts:
  - **Drafting optimizes provenance only.** Every Stage-3 constraint is about
    claim safety — source pointers, verbatim interview answers, "copy facts,
    don't summarize them into new claims", `[VERIFY]` markers. Nothing
    constrains narrative arc, paragraph flow, or explanatory quality; the
    copy-don't-synthesize rule actively pushes the draft toward fact-sheet
    prose stitched into a framework skeleton.
  - **Review quality findings are advisory, not gating.** The only findings
    that block are cold-read claim/audience mismatches (and configuration
    blockers); structure and prose findings land as should-fix/nit, and "no
    surviving blocker ⇒ publishable" lets a hard-to-read article exit review.
  - **No explicit quality standard exists.** The pipeline has validators for
    facts, markers, frontmatter, and config, but no rubric or exemplar
    standard for what a good technical article looks like — so "readable" is
    whatever the drafting and reviewing agents happen to produce.

  Requested fix direction (owner): study trusted agents and plugins that
  consistently produce high-quality reports and technical articles, then
  design and **make mandatory an article-quality harness** for the drafting
  pipeline — every generated article must meet a clear standard for
  readability, structure, and explanatory quality **before it can proceed**
  (a gate on stage progression, like `verify-markers --count → 0`, not an
  advisory finding).

---

## 2026-07-11 — review-article run (severity model)

**Scope:** the `review-article` workflow's severity classification
(blocker / should-fix / nit) as experienced during arbitration.

### Usability issues

- **[friction] Review severity rationale is not explicit enough.** The review
  correctly classifies findings into **blocker**, **should-fix**, and **nit**,
  but it does not explain *why* each finding belongs to that severity level
  according to a consistent review contract. During arbitration, some
  classifications (for example, F2) are immediately understandable, while
  others (for example, F1) are less obviously distinguished from a should-fix.
  This makes it difficult to verify whether severity is being assigned
  consistently across different reviews or is simply the reviewing agent's
  judgment. Root cause: the findings contract defines the three levels only as
  one-phrase glosses (`skills/review-article/SKILL.md` — "publication-stopping"
  / "fix before publishing" / "optional polish"), and only the cold-read pass
  has operational criteria (Q1/Q2 mismatch = blocker, Q3/Q4 = should-fix); the
  other passes assign severity by unstated judgment, and the finding format
  (`[severity] {location}: {issue}. Fix: {suggestion}`) has no field carrying
  the rationale. The review contract should make the severity criteria explicit
  enough that an owner can understand and audit why a finding is a blocker
  rather than a should-fix or nit. The goal is not to justify every individual
  finding in detail, but to make the severity model itself transparent,
  consistent, and reproducible across review runs.

---

## 2026-07-11 — plugin footprint on the target repository

**Scope:** where the pipeline's configuration and intermediate artifacts land
when the plugin runs against a host repo (observed dogfooding against `papers`).

### Usability issues

- **[friction] Plugin configuration leaks into the target repository.**
  `writing-sources.yaml` currently lives in the target repository's root — by
  contract, not by accident: `scripts/resolve-writing-sources.py` hardcodes
  `SOURCES_FILE = "writing-sources.yaml"` resolved against the host repo root,
  and `skills/harvest/SKILL.md` reads "the host repo's `writing-sources.yaml`".
  This is plugin configuration rather than project source, so requiring it in
  the host repository unnecessarily couples the repository to the tool and
  leaves plugin-specific files behind. The configuration should live outside
  the target repository (e.g. alongside `user-config.yaml`, keyed by repo path)
  or otherwise avoid permanently modifying the host project's root.

- **[friction] Intermediate outputs are written into the target repository.**
  Harvest writes intermediate artifacts (for example,
  `scratch/harvest-YYYY-MM-DD.md`) into the target repository. Root cause: the
  harvest skill validates the harvest document (`validate-fact-sheet.py`,
  `validate-needs-owner.py`) but **never specifies where to write it**, so the
  executing agent defaults to the target's working tree. These files are
  implementation details of the writing pipeline rather than project assets, so
  they unnecessarily dirty the working tree and increase the risk of accidental
  commits. Intermediate outputs should be stored outside the target repository
  or in an isolated cache/workspace that does not pollute the host project —
  and the location should be a stated contract, not an agent default.

---

## 2026-07-11 — draft-article run (Stage 2 gap interview, F1 on the `papers` repo)

**Scope:** the `draft-article` pipeline's Stage 2 bounded gap interview, dogfooded
against a real target repo (`papers`), plus an owner-directed exercise where the
assistant produced recommended answers to the five interview questions.

### Usability issues

- **[friction] Stage 2 asked questions answerable from reachable repository
  material — a gap between harvest and the interview.** All five interview
  answers could be grounded verbatim in the target repo's own files
  (`README.md`, `docs/dogfood-findings.md`): q1's "surprise" and q4's
  "tradeoff cost" are literally recorded in the target's dogfood findings
  (missing-year and duplicate-citekey incidents; the facts/judgments-split
  rationale). The interview is specified to ask **only what sources cannot
  answer**, so either (a) harvest's scope missed `docs/` in the target repo, or
  (b) the fact sheet covered it but the synonym-set semantic de-dup failed to
  suppress the questions. Either way the run spent scarce owner-attention
  budget on questions the pipeline could have answered itself — the exact
  inversion the SPEC's premise warns against (human minutes spent on
  extraction, the step AI does better). The harvest→Stage-2 boundary needs a
  diagnostic: for each asked question, record *why* it survived de-dup (topic
  not in fact sheet vs. NEEDS-OWNER re-raise), so this failure is attributable
  from run state instead of discovered by the owner mid-interview.

- **[friction] Interview presentation violated the owner-facing proposal
  contract, twice over.** The Stage-2 prompt (1) collected answers as
  free-form text ("reply with a bullet answer per question, `q1: <answer>`")
  with no effect-labeled choices — the selective flow the contract mandates —
  and (2) shipped **damaged context**: q3 had no Effect line at all, and the
  q2/q4/q5 Where/Effect texts were truncated mid-sentence ("the article is
  not  sheet only offers…", "for a techn", "srs/engineers…"). The contract's
  wording exists in `skills/owner-facing-proposal-contract.md`, but nothing in
  `skills/draft-article/SKILL.md` states *how* to present choices (e.g. a
  selective prompt mechanism), and nothing validates the assembled prompt text
  before it reaches the owner — so both drift and truncation shipped silently.

### What worked

- **Repo-grounded recommended answers are producible — and are the interaction
  the owner actually wants.** Asked to answer the five questions from
  repository knowledge, the assistant produced a source-groundable candidate
  answer for every one (e.g. q2: "101/101 papers drained across 8 `/sync`
  batches, ~15 papers/~9 min each, zero invented metadata" — from the target's
  dogfood log). The owner confirmed this is the required skill: Stage 2 should
  present each surviving question **with a repo-grounded recommended answer as
  the default choice** (approve it / modify it / replace it with the owner's
  own bullet), rather than a blank free-text field. This both restores the
  selective flow and reserves owner typing for genuinely owner-only knowledge
  — the recommended answer is the AI's best repo-derived draft; the owner's
  edit on top of it is the originality the pipeline cannot manufacture.

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
