---
id: SPEC-article-restructure
status: deferred            # do not build, plan, or generate stories until the trigger fires
build-trigger: >
  docs/dogfood-findings.md records ≥3 article runs where post-review manual
  editing moved/merged/removed whole sections (not sentence-level edits).
relates:
  - ../spec-article-draft-pipeline/SPEC.md   # restructure is a pipeline re-entry, not a review pass
  - ../spec-article-review/SPEC.md           # explicitly out of review's scope
sources:
  - ../../q_a/q1.md      # dogfooding Q&A round 1, traceability only (file removed 2026-07-16)
  - ../../q_a/a1.md      # dogfooding Q&A round 1, traceability only (file removed 2026-07-16)
---

> **Deferred contract.** This spec exists so the build decision is pre-made and fires mechanically on evidence: the dogfood findings log is the tripwire. Until the `build-trigger` in frontmatter is met, this spec generates no epics, stories, or code.

# Article Restructure

## Why

Review is intent-preserving by contract: findings, not rewrites, within the
author's chosen story. Dogfooding may surface a different need — the author
reads the draft and the *story itself* changes (sections should be reordered,
merged, dropped). Stretching review to cover this would destroy its bounded,
arbitratable-findings property; the correct home is a re-entry into the draft
pipeline with a changed outline. This spec exists now, deferred, so the
build decision is pre-made and fires mechanically on evidence.

## Capabilities

- **CAP-1** (re-brief)
  - **intent:** The author states the new intended story in 1–3 sentences;
    the workflow accepts no other input form (no open-ended editing session).
  - **success:** Every restructure run starts from a recorded re-brief; runs
    without one are refused.
- **CAP-2** (re-outline proposal)
  - **intent:** The workflow emits a proposal table mapping every existing
    section to keep / move / merge / drop / rewrite with rationale —
    findings-style, per SPEC-writing-assistant's owner-facing proposal
    contract; the author arbitrates each row before anything changes.
  - **success:** No section is altered without an approved mapping row; the
    proposal covers 100% of existing sections.
- **CAP-3** (fact-preserving re-fill)
  - **intent:** On approval, a mechanical re-fill rearranges content per the
    mapping, preserving all source-pointed facts and their pointers verbatim;
    newly needed content routes through the gap-interview mechanism (≤5
    questions), never open-ended generation.
  - **success:** Diffing fact-sheet pointers before/after shows zero lost or
    altered source pointers for kept content; all new claims are
    interview-sourced or `[VERIFY]`-marked.

## Constraints

- At most one restructure per draft version (mirrors review's once-per-version
  passes); a second requested restructure halts with "the story is unsettled —
  resolve intent before tooling can help."
- Restructure runs between review cycles, never concurrently with one.
- Consumes framework templates verbatim; a restructure cannot change the
  chosen framework (that is a new article).

## Non-goals

- No prose-quality improvement (review's contract).
- No merge of multiple articles into one, or split into several (new-article
  operations).

## Success signal

On a real draft where the owner's story changed post-review, the restructure
completes in ≤5 minutes of owner attention, the re-filled draft passes
fact-pointer diffing with zero losses, and the owner hands it back to review
instead of manually rebuilding sections.
