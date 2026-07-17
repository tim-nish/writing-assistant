---
id: SPEC-article-visuals
status: accepted            # accepted 2026-07-10; promoted per dogfood evidence
amends:
  - ../spec-article-draft-pipeline/SPEC.md   # narrows its non-goal "No image/figure generation"
  - ../spec-article-frameworks/SPEC.md       # adds visual slots to framework conventions
sources:
  # Prior dogfooding review round (private; records removed 2026-07-16), traceability only.
---

> **Canonical contract.** This SPEC is the complete contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.
> **Amended 2026-07-16 (platform profiles)** per SPEC-platform-variants: CAP-5's per-platform rendering divergence (Mermaid embedded vs. HTML-comment + render blocker) is **declared in each platform profile's `packaging`**, not fixed per platform in stage code or in this spec — the dev.to/Zenn behaviors CAP-5 names are the contents of those two profiles. The rendering *outcomes* CAP-5 requires are unchanged; a third platform gets its visual handling from its own profile with zero stage-code changes.

# Article Visuals

## Why

Skim-heavy platforms (dev.to, Zenn) evaluate an article's shape before its
argument; one well-placed structural visual materially improves completion.
Today the pipeline reuses repo diagrams when they exist (good) but is
forbidden from producing anything else, so articles whose repos lack diagrams
ship visually bare, and the owner hand-writes image-generation prompts —
mechanical work the assistant should absorb. Diagrams are claims: this spec
extends the plugin's existing sourcing discipline (source pointers, `[VERIFY]`,
owner arbitration) to visual content rather than inventing a parallel regime.

## Capabilities

- **CAP-1** (framework visual slots)
  - **intent:** Each framework declares expected visuals as slots: F1 one
    overview diagram; F2 optional before/after or timeline; F3 one comparison
    table (required); F4 one landscape table or concept map. A declined slot
    is omitted entirely, never left as a placeholder.
  - **success:** A produced draft's visuals match the framework's declared
    slots; a draft with a declined slot contains no placeholder residue.
- **CAP-2** (proposal, not insertion; amended 2026-07-17, #311)
  - **intent:** During framework fill, the pipeline proposes each slot visual
    — and at most 2 opportunistic extras — as an arbitratable item per
    SPEC-writing-assistant's owner-facing proposal contract: rationale,
    preview (Mermaid source, table, or figure spec), and choices stating
    their concrete effect on the article. The author approves, modifies, or
    declines. When a ratified visual-set plan exists (CAP-2a), individual
    proposals follow it.
  - **success:** No visual enters a draft without an explicit approval; every
    proposal shows rationale + preview + concrete-effect choices.
- **CAP-2a** (visual-set planning; added 2026-07-17, #311 — owner-approved)
  - **intent:** Before any individual visual proposal, the pipeline proposes
    the article's visual set as a whole — one owner-ratified item under the
    proposal contract — enumerating: **how many** visuals (0..cap; zero is a
    valid plan, never padded), and per member its **communicative role** (what
    part of the argument it carries), **required elements**
    (nodes/relationships/rows the role demands), **format** (the CAP-4
    table-vs-diagram rule and fallback ladder applied per member),
    **placement** (framework slot or section), and **per-element evidence
    pointers** (commit-pinned or interview-answer ids, per CAP-3; unsupported
    elements route to `[VERIFY]`/NEEDS-OWNER). The plan recommends multiple
    visuals only when distinct parts of the argument materially benefit —
    the step makes the set deliberate, never larger. Total planned members ≤
    the declared slot + 2 opportunistic extras (CAP-2's cap stands; the plan
    proposes within it, never raises it). The owner ratifies, modifies
    (add/remove/re-role members within the cap, without re-litigating
    approved members), or declines; declining the whole plan degrades to the
    per-slot flow, and a declined member leaves no placeholder residue.
  - **success:** A run presents the set-level proposal before the first
    individual visual proposal; a plan exceeding the cap is refused; a
    zero-visual plan completes with no residue and no padding; per-visual
    machinery downstream (CAP-2/3/4, the no-rendering constraint) is
    observably unchanged.
- **CAP-3** (sourced visuals)
  - **intent:** Every element of a proposed visual is source-pointed like a
    fact-sheet entry or the proposal carries `[VERIFY]`; unverifiable
    structural claims route to NEEDS-OWNER, same partition rule as prose.
  - **success:** Auditing any approved diagram element leads to a source
    pointer, an interview answer, or a `[VERIFY]` marker; no exceptions.
- **CAP-4** (fallback ladder)
  - **intent:** When no repo visual fits, generate in strict order: Mermaid →
    figure spec (elements, relations, emphasis, caption) → copy-paste-ready
    image-generation prompt derived from the figure spec (incl. "no embedded
    text" guidance and aspect ratio) → ASCII (simple structures only). A bare
    `[Figure: …]` placeholder is never emitted.
  - **success:** Every non-reused visual in a draft is one of: Mermaid source,
    figure spec, image-gen prompt block, or ASCII; zero bare placeholders.
- **CAP-5** (platform-variant rendering)
  - **intent:** Stage-5 variants handle divergence: the Zenn variant embeds
    Mermaid directly; the dev.to variant carries Mermaid/figure-spec in an
    HTML comment plus an explicit publish-blocker line ("render to image
    before publishing") in the completion summary's blocker bucket
    (SPEC-article-draft-pipeline CAP-6).
  - **success:** The Zenn variant renders its diagrams with zero manual work;
    the dev.to variant's completion summary lists each unrendered figure as a
    publish blocker.

## Constraints

- Proposing visual *source* (Mermaid, figure specs, prompts) is in scope;
  *rendering* images is not — no bundled mermaid-cli or image tooling (no-JS
  constraint; rendering is owner tooling, per SPEC-article-draft-pipeline).
- Prefer markdown tables over diagrams whenever content is comparative rather
  than topological.
- Mermaid only; no PlantUML (rendering-server/Java dependency).
- Proposals obey the owner-facing proposal contract (SPEC-writing-assistant):
  show where in the outline the visual lands, why it is proposed, and what
  each choice does to the article.

## Non-goals

- No image rendering or hosting; no calls to image-generation APIs.
- No per-article visual style system; captions and alt text only.
- No retrofitting visuals into already-published articles.

## Success signal

A dogfooded F1 article on a repo with no usable diagrams ships with one
approved overview visual (Mermaid on Zenn, blocker-flagged image for dev.to),
every diagram element source-pointed, and the owner spent under a minute per
visual decision.
