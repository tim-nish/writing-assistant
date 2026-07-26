---
id: SPEC-article-revise
status: accepted            # un-deferred 2026-07-26 (#728) — see superseded-trigger
workflow: revise-article
superseded-trigger: >
  SUPERSEDED 2026-07-26 (#728) by direct owner demand — the count was never
  met and is not claimed to have been. Original text, preserved so nothing
  later reads as though it fired: "docs/dogfood-findings.md records ≥3 article
  runs where post-completion manual editing revised the landed draft — either a
  STRUCTURAL change (moved/merged/removed whole sections) or an OWNER-INPUT
  revision (new requirements, opinions, or source pointers folded in), not
  sentence-level copy edits. Each recorded occurrence names its kind
  (structural | owner-input) so the ≥3 composition is visible when the trigger
  fires." What survives unstruck is the trigger's SUBSTANCE — the revision need
  observed in real use rather than anticipated — which the owner's three named
  recurring cases satisfy. See the 2026-07-26 amendment for the precedent this
  supersession follows.
relates:
  - ../spec-article-draft-pipeline/SPEC.md   # revision is a pipeline re-entry, not a review pass
  - ../spec-article-review/SPEC.md           # explicitly out of review's scope
  - ../spec-article-plan/SPEC.md             # CAP-1/CAP-3 — the plan Revise reconstructs context from
sources:
  # Prior dogfooding review round (private; records removed 2026-07-16), traceability only.
---

> **Accepted contract.** This spec was deferred behind a mechanical tripwire from its creation until 2026-07-26, when the tripwire's **count** was superseded by direct owner demand (#728). The frontmatter preserves the original trigger text rather than deleting it, because the distinction between *met* and *superseded* is the whole point: this spec does **not** claim its ≥3 occurrences were recorded. They were not.

> **Amended 2026-07-20 (#433)** per the owner decision record 2026-07-19 (article-writing workflow gaps): scope is widened to absorb **non-structural owner-input revision** — feeding new requirements, opinions, or source pointers into a landed draft — as the **same pipeline re-entry**, never a parallel workflow. #433 is this spec's **un-deferral vehicle**. The re-brief (CAP-1) accepts an owner-input revision brief; the fact-preserving re-fill (CAP-3) re-runs **verification and the quality rubric** on the affected sections; the build-trigger now counts post-completion hand-edits of **both** kinds, each occurrence naming its kind. Still **deferred** — the build fires only when the trigger's ≥3-occurrence count is met. *(The deferral in that last sentence was lifted 2026-07-26; see below.)*

> **Amended 2026-07-26 (triage, #728)** per /triage-gh. The workflow is named
> **Revise** (`revise-article`), this spec is **un-deferred**, and a **light
> tier** is added. Recorded in the open, in this order, because the ground
> matters more than the outcome:
>
> **1. The un-deferral is a SUPERSESSION, not a firing.** At the moment of this
> amendment `docs/dogfood-findings.md` recorded **zero** post-completion
> revision occurrences — its newest entry was dated 2026-07-11 and none
> mentioned restructure or #433. The ≥3 count was not met, and no text in this
> spec may later be read as claiming it was. The served surface is explicit
> that shortcuts are not available here: *"SPEC-article-restructure itself stays
> deferred behind its own mechanical tripwire (≥3 whole-section post-review edit
> runs), **which is not declared fired by analogy**"* (`consulted:
> hub@<private-pin> topics/articles.md:79`).
> So the count is **superseded** instead, on the precedent the same surface
> supplies for exactly this move: the browsable-candidate-list trigger count was
> *"**SUPERSEDED 2026-07-23** by direct owner demand after one sitting"*, with
> *"the trigger's **substance** — the need observed, not assumed"* surviving
> unstruck (`topics/articles.md:70@<private-pin>`). Applied here, the substance is
> satisfied: the owner reports the three cases below as **recurring in real
> use**, not as anticipated kinds.
> **What this costs, stated rather than hidden:** a tripwire superseded on
> testimony is a tripwire that did less work than it promised, and this is the
> second such supersession in this family. The mitigation is that it is written
> down as a supersession, which leaves the next one arguable; disguising it as a
> satisfied count would not.
>
> **2. The three live cases, mapped onto the capabilities.**
> **(a) a necessary diagram was not included** → owner-input revision brief
> (CAP-1) routing through the visual pipeline (SPEC-article-visuals slots and
> fallback ladder), then variant staleness (SPEC-platform-variants CAP-6). Full
> tier.
> **(b) a paragraph's content is judged unsuitable** → owner-input brief plus
> CAP-3 fact-preserving re-fill: the affected section re-fills via the bounded
> gap interview, the provenance map is rebuilt, and verification plus the
> quality rubric re-run on the affected sections. Full tier.
> **(c) a section title is not incorrect but the owner wants it changed** →
> **light tier** (CAP-2, below). This was the open design question the issue
> raised, and it is settled here rather than carried forward: a cosmetic edit
> does not warrant a proposal table over 100% of sections, and leaving it
> expensive is what produced the hand-editing workaround this spec exists to
> end.
>
> **3. Tier-independent invariants.** The light tier narrows *what is proposed*,
> never *what is guaranteed*. All of the following bind at **every** tier, and a
> future tier that trades any of them is not a tier of this workflow:
> a recorded re-brief (CAP-1); owner arbitration of every row that changes
> anything; the provenance map rebuilt over affected spans; the quality rubric
> re-checked on affected sections; variants marked stale; and hand-back to
> Review as a **new draft version**, whose once-per-version passes re-arm.
>
> **4. The boundary, restated.** **Review never revises; Revise never reviews.**
> A completed Revise hands a new draft version back to Review, and the
> post-arbitration re-entry machinery (persist canonical, rebuild provenance,
> mark variants stale) binds Revise's output identically to any other draft
> version.
>
> **5. Naming.** "Restructure" survives **only** as the name of the structural
> re-brief *kind* (CAP-1's first input form). It is no longer the name of the
> workflow, the spec, or the directory.

# Article Revise

## Why

Review is intent-preserving by contract: findings, not rewrites, within the
author's chosen story. Dogfooding may surface a different need — the author
reads the draft and the *story itself* changes (sections should be reordered,
merged, dropped). Stretching review to cover this would destroy its bounded,
arbitratable-findings property; the correct home is a re-entry into the draft
pipeline with a changed outline. This spec existed deferred from its creation
until 2026-07-26 so the build decision was pre-made; it is now open (#728), on
the supersession recorded above rather than on the trigger having fired.

The need is no longer hypothetical. Three situations recur after a
CanonicalDraft has been reviewed — a necessary diagram was omitted, a
paragraph's content is judged unsuitable, a section title the owner simply
wants changed — and each of them currently has exactly one available response:
edit the landed draft by hand, which is precisely the path that leaves no
provenance and no rubric re-check. Revise exists to make those three cases
cheap enough that the workaround stops being the rational choice.

## Capabilities

- **CAP-1** (re-brief)
  - **intent:** The author states, in 1–3 sentences, either the **new intended
    story** (a structural re-brief) or an **owner-input revision brief** — the
    new requirements, opinions, or source pointers to fold into the existing
    draft (#433). The workflow accepts no other input form (no open-ended
    editing session); an owner-input brief changes what the draft *says*, not
    necessarily its section structure.
  - **session-start context (2026-07-26, #728).** A Revise sitting begins by
    reconstructing the writing context from **`plans/<slug>.md`**
    (SPEC-article-plan CAP-1/CAP-3) — the intent, audience, claim, evidence
    clusters, dispositioned answers, visual decisions and unresolved items the
    completed run projected. The re-brief is stated *against* that
    reconstruction, so a revision is never briefed blind against a draft whose
    reasoning the session cannot see. **The plan is read, never rewritten**:
    Revise is not a plan-editing surface.
    **Sufficiency is under test, not assumed** (#727): whether the plan schema
    carries enough to support this reconstruction has never been verified, and
    a cold-session reconstruction test is the vehicle. Gaps that test finds are
    **plan-schema work, not Revise work** — this clause binds to the plan as the
    declared source of context regardless of what the test concludes about its
    completeness.
  - **success:** Every revision run — structural or owner-input, at any tier —
    starts from a recorded re-brief; runs without one are refused.
- **CAP-2** (re-outline proposal — two tiers)
  - **intent (full tier):** The workflow emits a proposal table mapping every
    existing section to keep / move / merge / drop / rewrite with rationale —
    findings-style, per SPEC-writing-assistant's owner-facing proposal
    contract; the author arbitrates each row before anything changes. This is
    the **default** tier and the tier every structural re-brief takes.
  - **intent (light tier, 2026-07-26, #728):** A re-brief that names a **single
    target** and asks for a change local to it emits a **single-row proposal**
    for that target only — single-target brief → single-row proposal → apply →
    **scoped** re-verify over the affected span. The motivating case is a
    section-title change: not incorrect, simply not what the owner wants.
  - **which tier, decided mechanically.** The light tier is available iff the
    re-brief names one target and the change does not move, merge, drop or
    re-fill any section. Anything touching content, structure, or more than one
    target is the full tier. The tier is **derived from the brief, never
    chosen by the tool for convenience**, and the chosen tier is stated to the
    owner before the proposal.
  - **what the light tier does NOT narrow.** The 100%-coverage clause is scoped
    to the full tier because it is a property of *structural* proposals — its
    job is that no section is silently restructured. It was never a guarantee
    about titles. Everything in the tier-independent invariants list still
    binds: recorded re-brief, owner arbitration of the row, provenance rebuilt
    over the affected span, rubric re-checked on the affected section, variants
    marked stale, hand-back to Review as a new version.
  - **success:** No section is altered without an approved mapping row. At the
    full tier the proposal covers 100% of existing sections; at the light tier
    it covers the named target, and the sections it does not name are
    provably untouched by the applied change.
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

- **Tier-independent invariants (2026-07-26, #728).** The following bind at
  every tier; a tier that trades any of them is not a tier of this workflow —
  a recorded re-brief (CAP-1); owner arbitration of every row that changes
  anything; the provenance map rebuilt over affected spans; the quality rubric
  re-checked on affected sections; variants marked stale
  (SPEC-platform-variants CAP-6); and hand-back to Review as a **new draft
  version**, whose once-per-version passes re-arm.
- At most one **full-tier** revision per draft version (mirrors review's
  once-per-version passes); a second requested full-tier revision halts with
  "the story is unsettled — resolve intent before tooling can help." The
  **light tier is not counted against that limit** — it alters no structure, so
  repeated light revisions carry no unsettled-story signal — but each one still
  produces a new draft version and hands back to Review.
- Revision runs between review cycles, never concurrently with one.
- Consumes framework templates verbatim; a revision cannot change the
  chosen framework (that is a new article).
- **Review never revises; Revise never reviews.** Review stays findings-only
  and once-per-version (SPEC-article-review); revision is a pipeline re-entry
  producing a new draft version. Neither borrows the other's contract.

## Non-goals

- No prose-quality improvement (review's contract) — an owner-input revision
  folds in new material and re-checks it; it is not a copyedit pass.
- No merge of multiple articles into one, or split into several (new-article
  operations).
- **Not** a second, parallel revision workflow: non-structural owner-input
  revision (#433) is absorbed **here** as the same re-entry, never built
  alongside it. The light tier (CAP-2) is a **tier of this workflow**, not a
  parallel one, which is why its invariants are the same invariants.
- No auto-applied edits at any tier — the tool proposes, the owner decides.
- No open-ended editing session: CAP-1's 1–3 sentence brief stands per tier.

## Success signal

On a real draft where the owner's story changed post-review, the full-tier
revision completes in ≤5 minutes of owner attention, the re-filled draft passes
fact-pointer diffing with zero losses, and the owner hands it back to review
instead of manually rebuilding sections.

For the light tier the signal is narrower and sharper: on a section-title
change the owner wants but does not consider a correction, the revision
completes in **one screen and one arbitration**, and the owner stops reaching
for the hand-edit. If light-tier revisions are still routinely hand-edited
instead, the tier has failed and its shape is the thing to revisit — not the
invariants it holds.
