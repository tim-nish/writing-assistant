# SPEC — review-article owner-facing UX (draft picker, reject-only arbitration, editor's assessment)

**Status: RATIFIED (2026-07-15, owner, via /triage-gh on #229) — decomposed into stories 13.31–13.33.**
Origin: owner feedback after reviewing the QSB F1 draft. The review engine
(fixed pass order, findings contract, severity criteria) is sound; the three
owner-facing surfaces around it — invocation, arbitration, completion — cost
more attention than they should.

## Problem

1. **Invocation requires a resolver-internal path.** The draft lives under
   the machine-global run workspace whose layout is resolver-internal by
   design (D2) — yet the owner must type that path by hand to start a
   review.
2. **Arbitration is O(findings) owner work.** The owner selects every
   accepted fix across multiple checkbox groups. In practice (QSB run:
   12/12 accepted) acceptance is the overwhelming default; the interaction
   should cost attention only for exceptions.
3. **The completion summary reports edits, not editing.** After arbitration
   the owner gets a change list; the valuable artifact is an editorial
   judgment — how the review strengthened the article's argument.
4. **The liked interaction pattern is unpinned.** The consolidated
   numbered-findings list (de-duplicated across passes, vote counts,
   ranked) followed by a selection UI was agent discretion; the owner wants
   it fixed.

## Capabilities

- **CAP-1 — draft picker.** `review article` takes a host repo (or nothing;
  cwd's git top-level), not a draft path. The plugin enumerates candidate
  drafts through the resolver — run workspaces holding a framework-complete
  `draft.md`, plus emitted variants at `output.drafts` — and presents a
  picker with metadata per draft: title, article type (intent label, never
  the internal ID), created/updated time, and pipeline status read from the
  checkpoint (in-progress / complete / reviewed). One draft → confirm and
  proceed; a direct draft path keeps working as the expert bypass.
- **CAP-2 — pinned arbitration presentation.** The arbitration round opens
  with the consolidated findings list: de-duplicated across passes, each
  finding numbered, severity-tagged, location-anchored, carrying its
  one-sentence issue and fix, with cross-pass agreement noted (votes).
  Ranked blockers → should → nit, highest-leverage first. This presentation
  is contract; the findings format itself (SPEC-article-review) is
  unchanged.
- **CAP-3 — reject-only arbitration.** Ordinary findings (lint, structure,
  prose, cold-read; every severity) default to ACCEPTED. The owner is asked
  once: "these N findings will be applied — deselect any to reject"
  (multiSelect; empty selection = apply all). Exceptions that stay
  explicit:
  - **policy-contradiction findings** keep the three-way choice (fix
    article / position moved / dismiss) — no safe default exists: a
    flagged reversal may be correct, and defaulting to "fix article" would
    auto-align the article to policy, which SPEC-policy-consistency-pass
    forbids; defaulting to "dismiss" would bury the tension the seam
    exists to surface.
  - a finding whose fix would alter owner-approved content (NFR12) is
    asked explicitly, never defaulted.
  A rejected finding is rejected — the single-round, no-relitigation rule
  is unchanged.
- **CAP-4 — editor's assessment.** The completion summary's informational
  bucket leads with a concise editorial verdict (~3–5 sentences): what the
  review did to the article's argument and reader experience — which
  defect class most threatened the stated audience's trust, what the
  highest-leverage change bought, what the article now does that it
  did not before. The change list is demoted to reference below it.
  The assessment cites finding numbers, not rewritten prose; no praise
  padding — it is a verdict, not a compliment.

## Constraints

- CAP-1 lists; it never auto-picks. Zero drafts found → report where the
  pipeline would have put one and point at draft-article.
- CAP-3 changes the *interaction*, not the contract: every finding still
  receives an explicit recorded disposition (accepted-by-default is
  recorded as accepted); the journal/summary remain complete.
- CAP-4 adds no new pass and no new model spend beyond the summary the
  run already writes.
