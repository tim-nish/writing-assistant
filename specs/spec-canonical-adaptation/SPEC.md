---
id: SPEC-canonical-adaptation
companions: []
sources:
  - ../spec-platform-variants/SPEC.md          # variants stay pure packaging; this spec supplies the matching canonical
  - ../spec-article-draft-pipeline/SPEC.md     # the draft flow that produces the source canonical
  # Ratifying owner decision (two-canonical architecture: one draft flow, one EN
  # canonical, adaptation as an explicit per-language derivation step) is held in
  # the owner's private knowledge hub, 2026-07-22 conversation record; staged for
  # distill. Mechanism public, provenance private.
---

> **Canonical contract.** This SPEC introduces the **adaptation step**: a
> standalone, owner-gated invocation that derives a target-language canonical
> (first target: Japanese) from a reviewed English canonical. It exists to keep
> SPEC-platform-variants honest: variants are *projections* and must stay pure
> packaging, so a platform whose reader differs in language/audience/register
> gets its own **derived canonical** first, and then emits as a same-reader
> variant with no retarget trigger. Where this spec and SPEC-platform-variants
> disagree about the adaptation step, this spec wins; the variant stage's own
> contract is untouched.

# Canonical Adaptation (EN canonical → JA canonical)

## Why

The first real cross-language emission (2026-07-22, `tanuki-engineering-lessons`
→ Zenn) produced a spec-conformant but unpublishable artifact: an approved
Japanese lede over an English title, English headings, and an English body, on a
platform whose profile names a ja-practitioner reader (writing-assistant#574).
The variant contract is "projection, not rewrite" — correctly, because claims
must not drift per platform — so adaptation depth cannot live in the variant
stage. The failure modes this spec prevents: asking the lede-retarget mechanism
to do adaptation work (mixed-language publishes); running the draft flow twice
from source material (forks claim discovery and verification, lets the two
articles' claims drift); and translating mechanically (a JA reader gets an EN
article's structure and framing with Japanese words on it).

The architecture: **the draft flow runs once and produces one source canonical
that owns the claims; adaptation is a separate, per-article, owner-gated
derivation that re-decides how the story is told for a named target reader; the
derived canonical is a first-class canonical the existing variant machinery
consumes with zero changes.**

```
source material ──draft flow──▶ EN canonical ──emit──▶ devto variant   (pure packaging)
                                    │
                                    │ adapt (this spec: owner-gated, per-article)
                                    ▼
                               JA canonical ──emit──▶ zenn variant     (pure packaging)
```

## Capabilities

- **CAP-1 (standalone post-review derivation, owner-gated per article)**
  - **intent:** Adaptation is a separate invocation in the same family as
    `emit variants` — never a stage of the draft flow, never fired implicitly by
    emission. Input is the **persisted, reviewed** source canonical at
    `<output.drafts>/<slug>.md` (zero `[VERIFY]` markers, resolved
    `audience`/`audience_id`); a run-workspace copy is refused with the
    `complete` remedy, exactly as the variant stage refuses one. Whether an
    article gets a JA canonical at all is a per-article owner decision at this
    invocation's gate — there is no standing "always adapt" rule.
  - **success:** No draft-flow stage and no emission path invokes adaptation;
    an article the owner never chose to adapt has no derived canonical anywhere;
    the invocation over an unreviewed or marker-carrying draft aborts naming the
    remedy.

- **CAP-2 (claims invariant — adaptation re-decides telling, never truth)**
  - **intent:** The derived canonical introduces **no claim absent from the
    source canonical** and drops no load-bearing claim silently; the evidence
    set is fixed. Everything else is free: structure, section order, payoff
    position, framing, register, title. This is the same invariant the
    lede-retarget proposal already carries, widened to the whole artifact.
  - **success:** A claims-conformance check (source canonical vs derived
    canonical) reports additions as defects; a deliberate omission is declared
    in the adaptation record (CAP-3), never implicit.

- **CAP-3 (the adaptation proposal — one gate, per-article depth)**
  - **intent:** The invocation composes an **adaptation plan** and presents it
    under the owner-facing proposal contract — one screen, machine-proposed
    plan plus free-form response, never raw-artifact homework. The plan states,
    per the target profile's named reader: the re-founded opening (what context
    this reader lacks or already has), the structural mapping (which sections
    move, merge, or reorder — e.g. payoff-first for JA tech-article norms vs
    the EN incident-led narrative), register (です/ます for `ja`), terminology
    treatment (technical terms kept in English/established katakana, never
    force-translated), the re-composed title, and any declared omission.
    Adaptation depth varies per article — a how-to may map nearly 1:1, an
    incident narrative may restructure — so the plan is proposed fresh each
    time; only the invariants (register, terminology convention, CAP-2) are
    standing rules.
  - **success:** The gate's options are approve / modify / stop, each stating
    its concrete effect on the artifact; the owner's answer is recorded in the
    run workspace; no derived canonical is written before the answer.

- **CAP-4 (the derived canonical is a first-class canonical with recorded
  ancestry)**
  - **intent:** The output is persisted at the resolved `output.drafts` as
    `{slug}.ja.md` with full canonical frontmatter: its own `slug`
    (`{slug}.ja`), `mode: canonical`, `language: ja`, the target
    `audience`/`audience_id`, and an **ancestry pin**
    `adapted_from: <source slug>@<source hash>` recording the source
    canonical's content hash — the same hash convention the variant trailer
    uses (sha256 over content without trailer), spelled to reuse the
    articles-repo plans' existing `pin: <repo>@<sha>` idiom rather than
    inventing a second ancestry convention (ratified 2026-07-23; `consulted:
    product-lab@e9d11071 topics/articles.md:22, GLOSSARY.md:14`). It carries
    its own `canonical-sha256` trailer like any canonical. It is eligible for
    review as a canonical; claim *verification* does not re-run (claims are
    inherited under CAP-2), review scope is language/framing quality plus
    claims-conformance against the source.
  - **success:** `emit variants` accepts the derived canonical by slug with
    zero special-casing; review-article runs over it; the ancestry pin
    resolves to an existing source canonical and hash or a lint names the
    defect.

- **CAP-5 (staleness chains through the derivation)**
  - **intent:** Editing the source canonical marks the derived canonical
    **stale** (recorded hash ≠ current source hash) — a publish blocker for the
    derived canonical *and everything downstream of it*. Re-adaptation is a
    fresh owner decision through this invocation, never an implicit re-run and
    never an in-place edit; the derived canonical's own variants use the
    existing `variant-staleness` mechanism against the derived canonical
    unchanged. The chain is: EN canonical edit → JA canonical stale → its Zenn
    variant stale-by-inheritance.
  - **success:** A staleness check over a derivation whose source moved reports
    the derived canonical and its variants in the blocker bucket with the
    hash pair; a fresh adaptation records the new source hash and clears it.

- **CAP-6 (no per-language code path)**
  - **intent:** `ja` is the first target, not a special case: the target
    reader, language, and register come from the same platform-profile /
    declared-target data the variant stage already consumes — adding a second
    adaptation target is declaration, not stage code. The invocation's
    signature is (source canonical, target declaration) → derived canonical.
  - **success:** Grepping the adaptation implementation for a hardcoded
    language branch finds none beyond register defaults already declared in
    profile data.

## Open questions

- **OQ1 — target declaration source.** Whether the adaptation target is named
  by pointing at a platform profile (zenn.yaml already declares
  audience/language) or by a dedicated adaptation-target declaration. Leaning
  profile-pointer (no new declaration type) but the profile is packaging-scoped
  by ratified decision (intent vs packaging, 2026-07-16) — resolve at
  implementation with that boundary in view.
- **OQ2 — review depth for derived canonicals.** Whether the full 9-axis rubric
  or a reduced language/framing + claims-conformance pass applies. CAP-4 sets
  the floor; the ceiling is an owner decision at first real use.
