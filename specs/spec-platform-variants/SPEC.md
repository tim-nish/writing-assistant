---
id: SPEC-platform-variants
companions: []
sources:
  - ../spec-article-draft-pipeline/SPEC.md   # CAP-4 is the promise this spec elaborates
  - ~/work/product-lab/q_a/2026-07-16-micro-platform-variant-architecture/answer.md  # external: owner policy hub, ratifying decision record, traceability only
  - ~/work/product-lab/q_a/2026-07-16-micro-devto-zenn-publishing/answer.md          # external: owner policy hub, companion decision record, traceability only
---

> **Canonical contract.** This SPEC elaborates SPEC-article-draft-pipeline CAP-4
> (platform-ready variants) into a full stage contract. Where the two disagree,
> this spec wins for the variant stage; CAP-4's one-line promise remains the
> pipeline-level summary. Source documents in frontmatter are traceability only.

# Platform Variants

## Why

The pipeline serves two publication platforms today (dev.to, Zenn) and must not pay
for that twice. The failure modes this spec exists to prevent: running the interview
per platform (collects the same owner judgment twice and lets the two articles'
claims drift); reviewing whole variants per platform (duplicates the capped
single-pass review design); hardcoding platform knowledge in stage code (makes the
third platform a code change); and emitting variants nobody is about to publish
(stale artifacts that must later be reconciled against a moved canonical draft).
The architecture: **everything up to and including the canonical draft is
platform-agnostic and runs once; platforms are declared profiles consumed only by
the final variant stage; variants are projections of the canonical draft, emitted
per publish decision.**

## Capabilities

- **CAP-1 (shared substrate)**
  - **intent:** Harvest, the gap interview, framework fill, verification, and the
    stage 3→4 quality gate run exactly once per article, with no platform parameter
    anywhere in their contracts. The canonical draft (plus its provenance map and
    interview journal) is the single entity all variants project from.
  - **success:** Producing both a dev.to and a Zenn variant of one article invokes
    harvest once and asks the owner one interview (≤5 questions total, not per
    platform); grepping stages 0–3 for platform identifiers finds none.
- **CAP-2 (platform profiles are declarations, not code)**
  - **intent:** Each platform is one declaration file — a **platform profile** —
    resolved through the path resolver alongside the machine-global repo config
    (SPEC-writing-assistant #211 placement), never a host-repo file and never a
    constant in stage code. A profile declares: `platform` id, `audience` (the one
    named reader for this platform's variant), `language` (`ja` implies です/ます
    consistency), `packaging` (frontmatter schema, tag cap, TL;DR placement, cover
    requirements, `canonical_url` policy), and `distribution_hook` (where the
    end-pointer points for this audience). The variant stage's signature is
    (canonical draft, profile) → platform file.
  - **success:** Adding a third platform requires writing one profile file and zero
    stage-code changes; a profile with an unresolved placeholder is caught by the
    stage-0 config validation (CAP-5 of the pipeline spec), not discovered at emit
    time.
- **CAP-3 (emission is per publish decision)**
  - **intent:** Variants are emitted on an explicit owner choice, presented
    in-conversation per the CAP-6 interaction contract (#226) — e.g. after the
    canonical draft passes the quality gate: "emit dev.to variant / emit Zenn
    variant / both / stop here." The pipeline never auto-emits all configured
    platforms.
  - **success:** A run whose owner publishes only on dev.to this week leaves no
    Zenn file anywhere; the choice and its outcome appear in the completion
    summary.
- **CAP-4 (variant projection, with one bounded judgment step)**
  - **intent:** A variant is a projection of the canonical draft: claims, evidence,
    provenance, and section structure are carried over unchanged — a variant never
    introduces a claim the canonical draft (and its provenance map) does not
    contain. Cross-language / cross-audience variants additionally get exactly one
    judgment step: **re-targeting the lede and framing to the profile's named
    reader** (for Zenn/JA: the named JP reader, です/ます register). This
    re-targeted material is presented to the owner as a proposal under the
    owner-facing proposal contract (approve / modify / replace), inside the
    existing ≤10-minute attention budget — it is the variant's only owner
    touchpoint.
  - **success:** Diffing a variant against the canonical draft shows changes only
    in frontmatter/packaging, language surface, and the re-targeted lede/framing;
    `verify-provenance` run on the variant finds no claim absent from the
    canonical provenance map; the owner saw exactly one proposal for the variant.
- **CAP-5 (variant checks are lint-sized, never a second review)**
  - **intent:** The full review (SPEC-article-review) and the quality gate (CAP-7)
    run on the canonical draft only. An emitted variant gets a **mechanical
    platform lint** — profile-declared frontmatter schema, tag cap, TL;DR
    placement, canonical-URL well-formedness, です/ます consistency for `ja` —
    plus the CAP-4 lede proposal above. No structure, prose, or cold-read pass
    re-runs per variant.
  - **success:** Emitting a variant from a reviewed canonical draft consumes zero
    LLM review passes beyond the single lede-re-targeting step; a seeded packaging
    defect (e.g. 5 tags where the profile caps 4) is reported by the lint with
    file/line.

## Constraints

- **One canonical draft, variants are views** (owner policy: a fully derivable
  artifact enters the architecture as a projection over its substrate, not a
  stored entity with independent life — product-lab lesson
  `derivable-artifact-is-a-view-not-a-noun`). A variant is never edited to say
  something the canonical draft does not; a wanted change routes to the canonical
  draft first, then variants are re-emitted. Stale-variant detection: a variant
  whose source canonical draft has changed since emission is a publish blocker
  (CAP-6 bucket), not a silent inconsistency.
- **Profiles carry the platform, code carries none** (owner policy: repo-specific
  and platform-specific assumptions live in declaration files, enforced by an
  "add a fresh platform" gate — product-lab lesson
  `portable-plugin-config-not-code`).
- Profile placement follows the machine-global config rule (#211): resolved via
  the path resolver, with the same migration/deprecation behavior as
  `writing-sources.yaml`.
- Emission choices, the lede proposal, and stale-variant blockers all surface
  through the existing CAP-6 completion-summary and in-conversation interaction
  contract — this spec adds no new report format.
- Intermediates (profile resolution log, lint output) live in the run workspace
  (`$WS`); only the variant files land in the host repo at `output.drafts`
  (footprint invariant).
- Inherited from the pipeline spec unchanged: no invented evidence; attention
  budget ≤10 minutes per article including all variant touchpoints; validator
  convergence (#206) applies to the platform lint — the lint's rejectable forms
  each have a sanctioned emitting path (e.g. the profile itself states the tag
  cap the packaging step reads).

## Non-goals

- No publishing (unchanged from the pipeline spec): the owner pushes to dev.to /
  the Zenn-synced repo.
- No translation memory or bilingual alignment tooling — the JA variant is a
  re-targeted projection, not a tracked translation pair.
- No per-platform review rubric: article quality has one definition (the canonical
  rubric); platforms differ in packaging and audience, not in what "good" means.
- No automatic simultaneous emission of all configured platforms.

## Success signal

The owner takes one canonical draft to published-on-both-platforms with: one
harvest, one interview, one full review, one lede-re-targeting decision for the
Zenn variant, zero manual reformatting on either platform, and — a month later —
no variant that silently disagrees with its canonical draft.

## Open Questions

- Does the dev.to variant need any lede re-targeting step at all when the
  canonical draft is already written for the dev.to reader, or is it pure
  packaging (current assumption: pure packaging; CAP-4's judgment step applies
  only when the profile's `audience`/`language` differ from the canonical
  draft's)?
- Where does the Zenn-synced repo's directory layout requirement live — in the
  Zenn profile's `packaging`, or in the (still-to-be-created) articles repo's own
  config?
