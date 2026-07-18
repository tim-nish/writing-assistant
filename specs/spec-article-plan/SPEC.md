---
id: SPEC-article-plan
status: accepted
date: 2026-07-17
issue: 310
relates:
  - ../spec-writing-assistant/SPEC.md    # footprint invariant; output.drafts destination
  - ../spec-article-index/SPEC.md        # deferred index becomes a derived view over plans
  - ../spec-article-draft-pipeline/SPEC.md
sources:
  # Owner decision record — 2026-07-17 (issue #310): storage, terminology, and
  # the articles-repo boundary. Consulted positions are recorded there; the hub
  # pointer stays private (publication boundary, #211).
---

> Canonical contract. Skills and scripts reference this spec and never restate
> its wording.

# Article Plan

## Why

A completed run produces exactly the editorial decisions a later run wants —
ratified claim, audience, dispositioned answers, section plan, visual
decisions, unresolved items — and strands them in a disposable per-run
workspace. Engineering-lessons articles are inherently serial; without a plan
record a later run cannot tell whether it is continuing, filling, updating, or
repeating. The plan is the `outlined`-stage artifact of the articles-repo
lifecycle (seed→evidenced→outlined→drafted→review→published), given a defined
shape. The vocabulary is **"article plan"** everywhere — spec, skill, file
naming; "skeleton" appears nowhere.

## Capabilities

- **CAP-1** (plan record as draft companion)
  - **intent:** At run completion the pipeline emits an article plan at
    `plans/<slug>.md` in the articles repository — a deterministic projection
    of artifacts the run already produced (journal, editorial anchor, answers,
    visual decisions, unresolved items), with **no new owner interaction**. It
    records editorial decisions — intent, audience, claim, evidence clusters,
    open questions, visual plan — with pointers; every evidence reference is a
    commit-pinned pointer or an interview-answer id, never prose evidence.
  - **success:** A completed run leaves exactly one schema-conforming plan
    beside its draft; regenerating it from the same run artifacts is
    byte-identical; no prompt was shown to produce it.
- **CAP-2** (schema-enforced writer; amended 2026-07-18, #363: the optional
  field set gains `audience_id` — the stable machine-readable audience
  compatibility identifier declared at draft time and stored in both the plan
  and the canonical draft (SPEC-platform-variants CAP-4); it never replaces
  the free-text `audience` and is never re-inferred downstream)
  - **intent:** The plan writer validates fail-closed with per-key
    diagnostics (same posture as the sanctioned config writers): `kind:
    article-plan` present and constant; `slug` equals the filename stem;
    required/optional fields per the frontmatter contract; **forbidden
    fields** refused — everything the canonical draft or variants own
    (`title`, `summary`, `topics`, `language`, `published`,
    `variants_emitted`, `canonical_url`), machine-state content (checkpoint,
    journal, provenance-map data), draft-lifecycle statuses, and free-text
    `evidence:` lists. A plan written to any path other than `plans/<slug>.md`
    is refused.
  - **success:** Fixtures assert refusal of: slug/filename mismatch, each
    forbidden field, prose evidence, an unpinned pointer, and a non-`plans/`
    path.
- **CAP-3** (consultation at draft start)
  - **intent:** A new run against the same articles repository reads existing
    plans read-only and proposal-shaped: it may surface "article Y covered X —
    link instead of re-explaining", "lesson Z has new evidence since `<sha>`",
    and continue/fill/update/new recommendations — each ratified by the owner
    under the proposal contract, none auto-applied.
  - **success:** A run over a repo with prior plans presents plan-grounded
    proposals the owner can decline with zero friction; a declined proposal
    leaves no residue.

- **CAP-4** (policy-conformance gate; added 2026-07-18, #365)
  - **intent:** After the plan is generated, every **policy-seeded decision**
    it records is validated against the **same pinned policy result** the run
    consulted (the seam's served surface at the run's pin, SPEC-policy-source-seam
    CAP-7) **and** the authoritative user config. The plan records the
    consulted **pin and configVersion**, and a **conformance status** —
    `conformant` / `open` / `conflict` / `stale` (`stale`: the pin or
    configVersion has moved since consultation and a consulted line changed).
    A decision that reverses a served ratified line is conformant **only as a
    proposed policy change** (its staging candidate exists, CAP-4 of the seam
    spec) — never by treating the reversal as current policy. The gate writes
    nothing to the policy hub.
  - **success:** Replaying the 2026-07-18 run yields a plan whose status is
    `conflict` (records-only anchor vs `syndication.policy` EN-canonical) —
    the contradiction is machine-visible in the plan instead of shipping
    silently; a plan whose consulted pin moved re-validates to `stale`;
    fixtures cover all four statuses.

## Constraints

- **Never harvest input, never evidence.** The articles repo is the authorized
  article workspace (declared `output.drafts` destination), not a declared
  harvest source: harvest excludes `plans/`, and the provenance gate rejects
  any claim grounded only in an article plan (`kind: article-plan` is the
  machine-checkable no-facts marker). A reused idea reaching a new draft
  carries provenance from **current** evidence — a fresh pin or interview
  disposition — never a bare plan reference.
- **Machine state stays out.** Journal, checkpoint, and provenance-map data
  never land in the articles repository; the plan writer emits only the plan
  file. Nothing is written to the host source repository at any point in the
  plan's lifecycle.
- **Schema-less destination fallback.** A draft destination without the
  articles-repo schema falls back to user-scoped state (keyed by repo + slug,
  draft association intact) **without** creating a `plans/` directory in the
  non-conforming destination.
- **The repo's schema is the API.** The plan is owner-co-owned; the tool never
  owns state in the articles repository and never writes outside the schema.

## Non-goals

- No prose scaffold: the plan records decisions and pointers, never draft
  bodies.
- No new owner interaction at emission; consultation proposals ride existing
  proposal surfaces.
- No second index: SPEC-article-index, when its build trigger fires, is a
  derived view over plans (one line per plan) — never a parallel record.
