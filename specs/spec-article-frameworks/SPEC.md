---
id: SPEC-article-frameworks
companions:
  - article-frameworks.md
  - ../../../website/docs/content-guide.md  # external: site-specific schema; its details move into user config during the plugin port (SPEC-writing-assistant CAP-6)
sources:
  - ../../../website/q_a/2/question.md  # external: website repo (sibling checkout), traceability only
  - ../../../website/q_a/2/answer.md    # external: website repo (sibling checkout), traceability only
---

> **Vendored copy.** Adopted verbatim from the website repo (`website/_bmad-output/specs/spec-article-frameworks/`, 2026-07-09) per SPEC-writing-assistant; this copy is now the canonical version for this project. Repo-internal references (`docs/…`, `q_a/…`, `content/articles/`, spec §-numbers) refer to the website repo.

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Article Frameworks

## Why

A pain to solve: the owner writes self-branding technical articles for dev.to (EN) and Zenn (JA) but cannot design article structure from scratch, which stalls publishing — currently the single bottleneck on visibility (q_a/1 finding: artifact quality far exceeds artifact visibility). Fill-in frameworks make article quality structural instead of inspiration-dependent, the same design move the site already made with its schema-driven content layer. One framework per article category; the category set mirrors `docs/website-architecture-spec.md` §9 seeding genres.

## Capabilities

- **CAP-1**
  - **intent:** Author selects the framework matching the article's category (project-introduction, engineering-lessons, evaluation-methodology, research-survey) and fills its slots to obtain a structurally complete draft, without designing structure.
  - **success:** Filling every slot of any framework yields a draft that needs no section-level reorganization in a structural editorial review.
- **CAP-2**
  - **intent:** Every framework emits YAML frontmatter conforming to the `article` schema documented in `docs/content-guide.md` (canonical and external modes).
  - **success:** A filled framework's frontmatter passes the site's build validation (AC-4) when dropped into `content/articles/` unchanged.
- **CAP-3**
  - **intent:** Frameworks encode the editorial gate as mandatory slots — an evidence slot (AP-10: the piece must require the owner's logs/numbers/scars) and a pointer-block slot (spec §3 invariant: every artifact ends with the domain + capture links).
  - **success:** A framework with an unfilled evidence or pointer-block slot is unambiguously identifiable as not-publishable by inspection of the marked slots.

## Constraints

- Templates are plain markdown files in the repo, usable by hand or by an agent; this spec introduces no runtime tooling (automation belongs to SPEC-article-draft-pipeline).
- Language-neutral: the same skeleton serves EN articles (site-canonical, syndicated to dev.to) and JA articles (Zenn-canonical, indexed as `mode: external`) per AP-6/AP-11.
- Category set is fixed to the four above; a category outside spec §9's sanctioned genres (e.g. generic tutorials) must not get a framework.
- **Length is an outcome, not a target** (added 2026-07-10, `q_a/a1.md` Q2): frameworks bound structure — every slot filled, no slot padded — and never define or optimize toward a word count. Platform hard limits, where they exist, are validation (publish blockers), not optimization targets.
- **Visual slots** (added 2026-07-10): each framework's expected visuals — F1 one overview diagram, F2 optional before/after or timeline, F3 one comparison table (required), F4 one landscape table or concept map — are defined by SPEC-article-visuals CAP-1; a declined slot is omitted entirely, never left as a placeholder.

## Non-goals

- No generic-tutorial or listicle framework — banned by AP-10.
- No product-validation framework yet — deferred until a product record reaches `validating` (Phase 3).
- No drafting automation, no review workflow — separate specs.
- Not a CMS: no editing UI, no storage beyond markdown files in git.

## Success signal

The owner produces a publishable draft by filling one framework end-to-end and the resulting file passes both the editorial checklist in `docs/content-guide.md` and build validation without restructuring. Structure is never designed from scratch for any article in the four categories again.

## Assumptions

- The category set from `q_a/2/answer.md` §1 is accepted by the owner; adding a category later is additive (one new template file), non-breaking.

## Open Questions

- Where should the templates be installed for day-to-day authoring: `docs/article-frameworks/` in this repo, or as assets of the drafting skill from SPEC-article-draft-pipeline?
