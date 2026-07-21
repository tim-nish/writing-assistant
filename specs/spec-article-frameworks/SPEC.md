---
id: SPEC-article-frameworks
companions:
  - article-frameworks.md
  - ../../../website/docs/content-guide.md  # external: site-specific schema; its details move into user config during the plugin port (SPEC-writing-assistant CAP-6)
sources:
  # Originating private site repo, decision round (traceability only).
  - ../../docs/interview-architecture.md # 2026-07-11 Stage-2 interview decision behind the per-slot skip-semantics constraint
---

> **Vendored copy.** Adopted verbatim from the originating private site repo (2026-07-09) per SPEC-writing-assistant; this copy is now the canonical version for this project. Bare repo-internal references (`docs/…`, `content/articles/`, archive rounds, spec §-numbers) refer to that originating repo.

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

> **Amended 2026-07-19 (triage, #413/#414)** per /triage-gh on the Tanuki F54/F56 findings: slot fill gains a **type dimension** — each framework section declares the minimum evidence TYPE it needs (see the Constraints bullet), CAP-3's success criterion covers a slot filled *below* its declared type, and enforcement (fail-closed at the stage 3→4 boundary, routing through the missing-input repair route) is SPEC-article-draft-pipeline's contract.

# Article Frameworks

## Why

A pain to solve: the owner writes self-branding technical articles for dev.to (EN) and Zenn (JA) but cannot design article structure from scratch, which stalls publishing — currently the single bottleneck on visibility (ratified owner finding: artifact quality far exceeds artifact visibility). Fill-in frameworks make article quality structural instead of inspiration-dependent, the same design move the site already made with its schema-driven content layer. One framework per article category; the category set mirrors `docs/website-architecture-spec.md` §9 seeding genres.

## Capabilities

- **CAP-1**
  - **intent:** Author selects the framework matching the article's category (project-introduction, engineering-lessons, evaluation-methodology, research-survey) and fills its slots to obtain a structurally complete draft, without designing structure.
  - **success:** Filling every slot of any framework yields a draft that needs no section-level reorganization in a structural editorial review.
- **CAP-2**
  - **intent:** Every framework emits YAML frontmatter conforming to the `article` schema documented in `docs/content-guide.md` (canonical and external modes).
  - **success:** A filled framework's frontmatter passes the site's build validation (AC-4) when dropped into `content/articles/` unchanged.
- **CAP-3**
  - **intent:** Frameworks encode the editorial gate as mandatory slots — an evidence slot (AP-10: the piece must require the owner's logs/numbers/scars) and a pointer-block slot (spec §3 invariant: every artifact ends with the domain + capture links).
  - **success:** A framework with an unfilled evidence or pointer-block slot — or a slot filled **without its declared minimum evidence type** (amended 2026-07-19, #414: textual fill with unrelated factual material, e.g. thresholds or config values in an Evidence slot, is not fill) — is unambiguously identifiable as not-publishable by inspection of the marked slots and their declarations.
- **CAP-4** *(added 2026-07-21 per /triage-gh on the F2 narrative-structure finding, #503)*
  - **intent:** A framework's **narrative structure is owner editorial intent per artifact, never a hardened tool default** (hub 2026-07-20 D2). At plan time the argument-plan sub-step proposes **2–3 candidate structures** for the selected elements — for F2: sibling-lessons (the current default), chronological journey, single-incident deep thread, thematic braid — each with a one-line rationale grounded in the selected elements' evidence kinds (chronology-rich clusters suggest journey; one dominant incident suggests deep thread). The owner picks, or counter-proposes free-form under the proposal contract. **Combining multiple selected elements into one narrative thread is a supported structure** — composition, not selection: element selection and its CAP-9 disclosure (SPEC-article-draft-pipeline) are unchanged. Generation still owns coherence: whichever structure is chosen, the draft must pass the existing Stage 3→4 gate (dim1 narrative arc; the #434 skeleton-variation rules this satisfies), and review never reconstructs structure.
  - **success:** An F2 run's plan presents ≥2 candidate structures with element-grounded rationales and the owner's pick drives Stage-3 composition; selecting the single-thread structure yields one narrative with the elements as beats rather than one section each; a run never hardens into a single default shape; every chosen structure passes the gate.

## Constraints

- Templates are plain markdown files in the repo, usable by hand or by an agent; this spec introduces no runtime tooling (automation belongs to SPEC-article-draft-pipeline).
- Language-neutral: the same skeleton serves EN articles (site-canonical, syndicated to dev.to) and JA articles (Zenn-canonical, indexed as `mode: external`) per AP-6/AP-11.
- Category set is fixed to the four above **plus the ratified working-note category** (amended 2026-07-16 — see the working-note entry under Open Questions for its contract); a category outside spec §9's sanctioned genres (e.g. generic tutorials) must not get a framework.
- **Length is an outcome, not a target** (added 2026-07-10, prior dogfooding round Q2): frameworks bound structure — every slot filled, no slot padded — and never define or optimize toward a word count. Platform hard limits, where they exist, are validation (publish blockers), not optimization targets.
- **Visual slots** (added 2026-07-10): each framework's expected visuals — F1 one overview diagram, F2 optional before/after or timeline, F3 one comparison table (required), F4 one landscape table or concept map — are defined by SPEC-article-visuals CAP-1; a declined slot is omitted entirely, never left as a placeholder.
- **Per-section minimum evidence type** (added 2026-07-19, #414): each framework section/slot declares the minimum evidence TYPE required to fulfill its editorial purpose — `episode | example | measurement | none` — authored with the templates exactly like skip semantics (per-slot values are template content). An Evidence slot (CAP-3/AP-10) declares at least one concrete episode, example, or observed result; thresholds, config values, or policy numbers alone never satisfy it. The declaration is contract, the check is the pipeline's: SPEC-article-draft-pipeline enforces it fail-closed at the stage 3→4 boundary and routes absence through its missing-input repair route — this spec introduces no runtime tooling (Constraints, unchanged).
- **Skip semantics per slot** (added 2026-07-11, `docs/interview-architecture.md` D2): each framework slot fed by an interview question declares the effect of a skipped input — omit the slot, defer the decision, accept the recommended answer later, fill with `[VERIFY]`-marked inference, or raise a publish blocker. The interview engine records only the skip disposition; the slot's declared contract determines the consequence, and the skip choice's label states it. Per-slot values are template content, authored with the templates.

## Non-goals

- No generic-tutorial or listicle framework — banned by AP-10.
- No product-validation framework yet — deferred until a product record reaches `validating` (Phase 3).
- No drafting automation, no review workflow — separate specs.
- Not a CMS: no editing UI, no storage beyond markdown files in git.

## Success signal

The owner produces a publishable draft by filling one framework end-to-end and the resulting file passes both the editorial checklist in `docs/content-guide.md` and build validation without restructuring. Structure is never designed from scratch for any article in the four categories again.

## Assumptions

- The category set from the ratified owner decision §1 is accepted by the owner; adding a category later is additive (one new template file), non-breaking.

## Open Questions

- ~~Owner proposal (2026-07-16) — a fifth, lightweight "working-note"
  framework.~~ **RATIFIED 2026-07-16 (owner decision record: content
  architecture; transcribed per SPEC-policy-realignment F2).** Working notes
  **are** writing-assistant products: the owner's newsletter issues (4 fixed
  blocks: one lesson / one number / published-links / what-I'm-building) are
  produced by this pipeline as their own small canonical draft, with the
  variant stage emitting email + web-archive renderings via packaging profiles
  (slim-profile contract: SPEC-platform-variants, "Working-note slim profile").
  Shape: a working-note framework (the 4 blocks as slots) paired with a **slim
  pipeline profile** — no 5-question interview, a lighter quality gate —
  because the issue's contract is "assembly <1hr" and the full pipeline's
  attention budget is mis-sized for it. **Ratified constraints (verbatim,
  binding on the implementation whenever it is ordered):**
  (1) sources are the active repos' recent activity **plus the owner's policy
  recall surface read via the existing policy-source seam mechanics —
  read-only, pinned, lessons first**; (2) the policy hub's **Q&A history
  archive is never a harvest source** — promotion to the recall surface is the
  only path by which hub content becomes harvestable; (3) **published text
  carries public repository links only**. Implementation timing stays free —
  this ratification orders no build; adding the F5 template file is additive
  and non-breaking (Assumptions).

  **Fill — narrative-arc sourcing (2026-07-19, #425; owner decision record
  2026-07-19).** The working note's **one-lesson block is told as an arc**,
  sourced from the recall surface via the seam, lessons-first (constraints
  (1)–(3) above unchanged — never the batch history):
  - **Selection inputs:** lessons whose body carries a `## Journey` section
    (original framing → actual question → what moved it, with an `origin:`
    marker), plus topic-thread **Declined** lines and struck-through
    **superseded** decision lines — the surface's native reversal records.
  - **Structure mapping** (the arc onto the one-lesson block): *misconception*
    = the Journey's original framing / superseded position; *turning point* =
    "what moved it"; *evidence* = the lesson's **public Evidence pointers
    only**; *abstraction* = the lesson one-liner.
  - **Origin marker:** a Journey may be hub-native or backfilled
    (`origin: reconstructed <date>`); both are valid sources, but the marker
    is **surfaced to the owner at selection time**.
  Guarantees (1)–(3) hold unchanged, and the slim-profile scrub runs the
  publication-boundary lint + the dated provenance convention for anything
  touching private hub content (SPEC-platform-variants, "Working-note slim
  profile"). This fills the sourcing detail only; the F5 four-block shape and
  the slim profile are unchanged.

- ~~Where should the templates be installed for day-to-day authoring: `docs/article-frameworks/` in this repo, or as assets of the drafting skill from SPEC-article-draft-pipeline?~~ **Resolved 2026-07-16 (owner decision record, template placement):** the F1–F4 templates live **only** as assets of the drafting skill (`skills/draft-article/frameworks/`) — implementation assets consumed by the skill, single canonical source bundled with the plugin. `docs/article-frameworks/` holds lightweight **pointers only**: framework name, one-line description, canonical asset path — never template content (the templates are already human-readable Markdown; the problem is discoverability, not readability). No generated documentation views and no regeneration machinery unless a future need arises that opening the canonical asset cannot satisfy (e.g. synthesized cross-framework comparison tables).
