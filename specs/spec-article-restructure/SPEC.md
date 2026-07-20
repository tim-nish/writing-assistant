---
id: SPEC-article-restructure
status: deferred            # do not build, plan, or generate stories until the trigger fires
build-trigger: >
  docs/dogfood-findings.md records ≥3 article runs where post-completion manual
  editing revised the landed draft — either a STRUCTURAL change (moved/merged/
  removed whole sections) or an OWNER-INPUT revision (new requirements,
  opinions, or source pointers folded in), not sentence-level copy edits. Each
  recorded occurrence names its kind (structural | owner-input) so the ≥3
  composition is visible when the trigger fires.
relates:
  - ../spec-article-draft-pipeline/SPEC.md   # restructure is a pipeline re-entry, not a review pass
  - ../spec-article-review/SPEC.md           # explicitly out of review's scope
sources:
  # Prior dogfooding review round (private; records removed 2026-07-16), traceability only.
---

> **Deferred contract.** This spec exists so the build decision is pre-made and fires mechanically on evidence: the dogfood findings log is the tripwire. Until the `build-trigger` in frontmatter is met, this spec generates no epics, stories, or code.

> **Amended 2026-07-20 (#433)** per the owner decision record 2026-07-19 (article-writing workflow gaps): scope is widened to absorb **non-structural owner-input revision** — feeding new requirements, opinions, or source pointers into a landed draft — as the **same pipeline re-entry**, never a parallel workflow. #433 is this spec's **un-deferral vehicle**. The re-brief (CAP-1) accepts an owner-input revision brief; the fact-preserving re-fill (CAP-3) re-runs **verification and the quality rubric** on the affected sections; the build-trigger now counts post-completion hand-edits of **both** kinds, each occurrence naming its kind. Still **deferred** — the build fires only when the trigger's ≥3-occurrence count is met.

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
  - **intent:** The author states, in 1–3 sentences, either the **new intended
    story** (a structural re-brief) or an **owner-input revision brief** — the
    new requirements, opinions, or source pointers to fold into the existing
    draft (#433). The workflow accepts no other input form (no open-ended
    editing session); an owner-input brief changes what the draft *says*, not
    necessarily its section structure.
  - **success:** Every revision run — structural or owner-input — starts from a
    recorded re-brief; runs without one are refused.
- **CAP-2** (re-outline proposal)
  - **intent:** The workflow emits a proposal table mapping every existing
    section to keep / move / merge / drop / rewrite with rationale —
    findings-style, per SPEC-writing-assistant's owner-facing proposal
    contract; the author arbitrates each row before anything changes.
  - **success:** No section is altered without an approved mapping row; the
    proposal covers 100% of existing sections.
- **CAP-3** (fact-preserving re-fill)
  - **intent:** On approval, a mechanical re-fill rearranges content per the
    mapping (structural revision) and/or folds the owner-input brief's new
    material into the affected sections (#433), preserving all source-pointed
    facts and their pointers verbatim; newly needed content routes through the
    gap-interview mechanism (≤5 questions), never open-ended generation. The
    affected sections then **re-run verification and the quality rubric** — a
    revision is never handed back unchecked, closing the exact gap the observed
    hand-editing workaround left open (no provenance, no rubric re-check).
  - **success:** Diffing fact-sheet pointers before/after shows zero lost or
    altered source pointers for kept content; all new claims are
    interview-sourced or `[VERIFY]`-marked; the affected sections pass the same
    verification + rubric gate a fresh draft does.

## Constraints

- At most one restructure per draft version (mirrors review's once-per-version
  passes); a second requested restructure halts with "the story is unsettled —
  resolve intent before tooling can help."
- Restructure runs between review cycles, never concurrently with one.
- Consumes framework templates verbatim; a restructure cannot change the
  chosen framework (that is a new article).

## Non-goals

- No prose-quality improvement (review's contract) — an owner-input revision
  folds in new material and re-checks it; it is not a copyedit pass.
- No merge of multiple articles into one, or split into several (new-article
  operations).
- **Not** a second, parallel revision workflow: non-structural owner-input
  revision (#433) is absorbed **here** as the same re-entry, never built
  alongside restructure.

## Success signal

On a real draft where the owner's story changed post-review, the restructure
completes in ≤5 minutes of owner attention, the re-filled draft passes
fact-pointer diffing with zero losses, and the owner hands it back to review
instead of manually rebuilding sections.
