---
id: SPEC-platform-variants
companions: []
sources:
  - ../spec-article-draft-pipeline/SPEC.md   # CAP-4 is the promise this spec elaborates
  # Ratifying owner decision records 2026-07-16 (platform-variant architecture;
  # dev.to/Zenn publishing) are held in the owner's private knowledge hub,
  # retrievable by date + title. Mechanism public, provenance private.
---

> **Canonical contract.** This SPEC elaborates SPEC-article-draft-pipeline CAP-4
> (platform-ready variants) into a full stage contract. Where the two disagree,
> this spec wins for the variant stage; CAP-4's one-line promise remains the
> pipeline-level summary. Source documents in frontmatter are traceability only.
> **Amended 2026-07-18 (triage, #361/#362)**: the projection substrate is the
> **persisted** canonical (`drafts/{slug}.md` at `output.drafts`), never a
> run-workspace intermediate; emission is a **separate post-review invocation**,
> never offered inline during the draft flow; and **review never re-emits** — a
> post-review canonical change marks existing variants stale (CAP-6), and
> re-emission is a fresh explicit publish decision.

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
    requirements, `canonical_url` policy, and `visuals` — the platform's
    diagram-rendering treatment per SPEC-article-visuals CAP-5, e.g. Mermaid
    embedded vs. HTML-comment + render blocker; this enumeration is exhaustive —
    an open-ended packaging block would be an untyped dimension), and
    `distribution_hook` (where the end-pointer points for this audience). The variant stage's signature is
    (canonical draft, profile) → platform file.
  - **success:** Adding a third platform requires writing one profile file and zero
    stage-code changes; a profile with an unresolved placeholder is caught by the
    stage-0 config validation (CAP-5 of the pipeline spec), not discovered at emit
    time; and a profile declaring a publishing-intent key (`mode`, `canonical`,
    `canonicality`, or a `syndication` block) is **rejected at stage 0** with a
    configuration error naming the key and its user-config home — the
    intent/packaging split is unrepresentable in a profile, not conventional
    (ratified 2026-07-16, Epic 16 story review; transcribed per
    SPEC-policy-realignment F5; implemented in Story 16.2).
- **CAP-3 (emission is per publish decision)** (amended 2026-07-18, #361/#362;
  amended 2026-07-22, #582 — cross-language targets route through adaptation)
  - **intent:** Variants are emitted on an explicit owner choice, presented
    in-conversation per the CAP-6 interaction contract (#226) — in a **separate
    post-review invocation** consuming the persisted, reviewed canonical: "emit
    dev.to variant / emit Zenn variant / both / stop here." The choice is never
    offered inline during the draft flow, the pipeline never auto-emits all
    configured platforms, and **no stage re-emits a variant implicitly** — when
    the canonical changes after emission (e.g. review-applied edits), existing
    variants are marked stale (CAP-6) and re-emission waits for a fresh explicit
    publish decision.
    **A cross-language target is never offered as a direct projection (amended
    2026-07-22, #582).** A declared platform whose profile `language` differs
    from the source canonical's `language` is **not** among the emit choices;
    it is presented as **"adapt first"** — the route through
    SPEC-canonical-adaptation to a derived canonical in that language, which
    then emits as a same-reader variant with no retarget trigger. The
    mixed-language projection was never a *design*; it was what the screen
    happened to offer when nothing filtered by language, and the #574 artifact
    (a JA-profile variant carrying an English title, headings, and body) is
    what that produced. This changes only what is **offered by default**: the
    owner may still emit such a variant deliberately, and the shipped
    `language-mismatch` publish blocker (CAP-4 lint, added 2026-07-22 per #574)
    remains the backstop that keeps the outcome visible rather than silent.
    Same-language targets are offered exactly as before.
  - **success:** A run whose owner publishes only on dev.to this week leaves no
    Zenn file anywhere; the choice and its outcome appear in the completion
    summary; a review run that edits the canonical leaves the variant files
    untouched and the staleness check reporting them stale. **An EN canonical
    with `zenn` (a `language: ja` profile) declared presents "adapt first" for
    Zenn and no direct-projection option; the same canonical's dev.to option is
    unchanged; a JA canonical derived from it offers Zenn normally, as pure
    packaging.**
- **CAP-4 (variant projection, with one bounded judgment step)**
  - **intent:** A variant is a projection of the canonical draft: claims, evidence,
    provenance, and section structure are carried over unchanged — a variant never
    introduces a claim the canonical draft (and its provenance map) does not
    contain. Whether a variant gets the single judgment step is a **deterministic
    comparison of declared fields** (OQ1 resolution — owner decision record
    2026-07-16, lede-retarget trigger; **amended 2026-07-18, #363** — the
    free-text-vs-slug comparison made the no-touchpoint branch unreachable):
    the canonical draft's frontmatter declares its `audience_id`, `language`,
    and `register`; the profile declares its own; **the trigger compares
    `audience_id`, `language`, and `register` deterministically** — inequality
    on any triggers exactly one judgment step. `audience_id` is a **stable,
    machine-readable compatibility identifier** drawn from the installed
    profiles' audience vocabulary, declared by the owner at draft time (with
    the backlog/draft-start audience answer) and stored in **both** the
    article plan and the canonical draft; it is **never re-inferred at
    emission** and it **never replaces** the owner-authored free-text
    `audience` (the named reader), which continues to serve prose, the
    quality gate, and judges unchanged. Both fields are pipeline-internal:
    populated at draft time (a backlog-less draft declares them at draft
    start), validated for presence by stage-0/the quality gate, and
    **stripped by variant packaging** — published variant frontmatter and the
    user-config site schema never carry them. The judgment step is **re-targeting
    the lede and framing to the profile's named reader** (for Zenn/JA: the named
    JP reader, です/ます register); equality on all three compared fields means
    pure packaging with no proposal. The trigger is never agent judgment over content. This
    re-targeted material is presented to the owner as a proposal under the
    owner-facing proposal contract (approve / modify / replace), inside the
    existing ≤10-minute attention budget — it is the variant's only owner
    touchpoint.
    **Scope of "language surface" (amended 2026-07-22, #574):** the re-targeted
    material is the **lede**; the body — claims, evidence, section headings —
    carries over unchanged, so a **cross-language variant is a mixed-language
    artifact by design** (a JA-profile projection of an EN canonical ships an EN
    body). This is not a defect to be translated away — auto-translation would
    introduce claims the canonical provenance map does not contain — but it is
    never left silent: CAP-5's `language-mismatch` check makes the consequence
    visible in the publish-blocker bucket, and the owner decides.
  - **success:** Diffing a variant against the canonical draft shows changes only
    in frontmatter/packaging, language surface, and the re-targeted lede/framing;
    `verify-provenance` run on the variant finds no claim absent from the
    canonical provenance map; the owner saw at most one proposal per variant —
    exactly one iff `audience_id`/`language`/`register` mismatched, zero
    otherwise (a same-reader EN→dev.to emission fires no touchpoint).
- **CAP-5 (variant checks are lint-sized, never a second review)**
  - **intent:** The full review (SPEC-article-review) and the quality gate (CAP-7)
    run on the canonical draft only. An emitted variant gets a **mechanical
    platform lint** — profile-declared frontmatter schema, tag cap, TL;DR
    placement, canonical-URL well-formedness, です/ます consistency for `ja`,
    **`language-mismatch` — a body whose script ratio does not match the
    profile's declared `language` (amended 2026-07-22, #574)**, the
    `packaging.visuals` treatment applied, and profile target directories
    existing in the `output.drafts` destination repo —
    plus the CAP-4 lede proposal above. No structure, prose, or cold-read pass
    re-runs per variant.
    The `language-mismatch` check is a **publish blocker, never a refusal** — the
    owner may publish a mixed-language variant knowingly; what the check forbids
    is the outcome being invisible. It is distinct from the です/ます check, which
    polices register *within* Japanese prose and therefore passes clean on a body
    with no Japanese at all.
  - **success:** Emitting a variant from a reviewed canonical draft consumes zero
    LLM review passes beyond the single lede-re-targeting step; a seeded packaging
    defect (e.g. 5 tags where the profile caps 4) is reported by the lint with
    file/line; a `language: ja` profile's variant carrying an English body reports
    exactly one `language-mismatch` publish blocker.

## Constraints

- **One canonical draft, variants are views** (owner policy: a fully derivable
  artifact enters the architecture as a projection over its substrate, not a
  stored entity with independent life). A variant is never edited to say
  something the canonical draft does not; a wanted change routes to the canonical
  draft first, then variants are re-emitted. Stale-variant detection: a variant
  whose source canonical draft has changed since emission is a publish blocker
  (CAP-6 bucket), not a silent inconsistency.
- **Profiles carry the platform, code carries none** (owner policy: repo-specific
  and platform-specific assumptions live in declaration files, enforced by an
  "add a fresh platform" gate).
- Profile placement follows the machine-global config rule (#211): resolved via
  the path resolver, with the same migration/deprecation behavior as
  `writing-sources.yaml`.
- Emission choices, the lede proposal, and stale-variant blockers all surface
  through the existing CAP-6 completion-summary and in-conversation interaction
  contract — this spec adds no new report format.
- Intermediates (profile resolution log, lint output) live in the run workspace
  (`$WS`); only the variant files land at the `output.drafts` destination — an
  external articles repo by default, never required to be inside the host repo
  (plugin-layout) — and nothing else lands anywhere (footprint invariant).
- Inherited from the pipeline spec unchanged: no invented evidence; attention
  budget ≤10 minutes per article including all variant touchpoints; validator
  convergence (#206) applies to the platform lint — the lint's rejectable forms
  each have a sanctioned emitting path (e.g. the profile itself states the tag
  cap the packaging step reads).

## Working-note slim profile (ratified 2026-07-16; implementation unordered)

Transcribed per SPEC-policy-realignment F2 from the owner's content-architecture
decision: **working notes are writing-assistant products.** A working-note draft
(SPEC-article-frameworks, working-note framework: 4 fixed blocks) is its own
small canonical draft, and this variant stage emits its **email and web-archive
renderings via packaging profiles** — the same declared-profile machinery as
every platform, no new mechanism. The pairing is a **slim pipeline profile**: no
5-question interview and a lighter quality gate, because the issue's contract is
"assembly <1hr" and the full pipeline's attention budget is mis-sized for it.
Ratified constraints binding the implementation whenever it is ordered:

- Sources are the active repos' recent activity **plus the owner's policy recall
  surface read via the existing policy-source seam mechanics — read-only,
  pinned, lessons first**; the hub's **Q&A history archive is never a harvest
  source** (promotion to the recall surface is the only path).
- **Published text carries public repository links only.**
- **Destination (amended 2026-07-24, #653):** the email and web-archive
  renderings land in the destination repo's **`newsletter/` section** — a
  distinct section with its own light schema, separate from the article
  backlog (different layer/lifecycle), web-archived so SEO accrues to the owned
  domain (`consulted: product-lab@90877fa4e77e1353b527a76607ed2ea06daf2b27
  topics/articles.md:61,66`). This is a **fourth permitted destination write
  surface** recorded in SPEC-writing-assistant (#653) — *not* the drafts
  variant surface of the "Intermediates" clause above, whose "only the variant
  files land at `output.drafts` … and nothing else lands anywhere" now reads
  against that extended surface. Emission still uses the same declared-profile
  machinery; only the destination section differs.

This section recorded the contract; **the build is ordered by #653
(2026-07-24)**, which added the destination write-surface amendment above and
closes the SPEC-policy-realignment F2 drift (the working-note/newsletter
constraints were "nowhere in this repo" until this amendment).

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

- ~~Does the dev.to variant need any lede re-targeting step at all when the
  canonical draft is already written for the dev.to reader, or is it pure
  packaging?~~ **Resolved 2026-07-16 (owner decision record, lede-retarget
  trigger):** the assumption is confirmed
  and made mechanical — the trigger is a deterministic comparison of declared
  `audience`/`language` (canonical draft frontmatter vs profile); mismatch on
  either ⇒ exactly one lede proposal, match ⇒ pure packaging (CAP-4). A
  `lede_retarget: auto|always|never` profile field was **declined**: no existing
  platform needs an override, the field creates contradictory-declaration states
  (audience differs + `never`) that stage-0 validation would have to police, and
  the escape hatches already exist (modify/replace at the proposal gate; editing
  the canonical draft). Reopen trigger: a real platform needing framing changes
  with no audience/language delta — that demand adds the field as a
  backward-compatible profile extension.
- ~~Where does the Zenn-synced repo's directory layout requirement live — in the
  Zenn profile's `packaging`, or in the (still-to-be-created) articles repo's own
  config?~~ **Resolved 2026-07-16 (owner decision):** the Zenn target directory
  layout belongs in the Zenn platform profile's `packaging` block in the
  machine-global writing-assistant configuration, resolved through the standard
  path resolver — never hardcoded in stage code and never stored in either
  repository's working tree. The articles repository still owns the schema of
  the stored article records. **Precedence declaration (owner decision record
  2026-07-16, layout authority):** the profile's layout entry is a
  *conformance record* of the platform's sync contract, never an authority over
  any repository — the **`output.drafts` destination repo's actual directory
  structure is authoritative, checked by existence**: on mismatch the
  destination repo wins and the profile is the defect. The platform lint
  (CAP-5) checks that every profile target directory exists in the
  `output.drafts` destination repo (never the host repo — the harvested repo is
  not the delivery target). Moving the layout declaration repo-side happens on
  a demand trigger: a second tool consuming it.
- ~~(Added 2026-07-16, cross-spec consistency check.) The legacy
  `syndication.policy` / `syndication.variants.*` keys overlap what profiles now
  declare.~~ **Resolved 2026-07-16 (owner decision record, syndication-key
  split):** the boundary is *facts about a platform* vs *facts about the owner*,
  and — stated baldly — **zero current `syndication.variants.*` keys are
  profile-shaped**. Per-key routing: `devto.canonical_url_base` is an owner
  value (intent boundary) and re-homes in user config's owner block;
  `zenn.external_record_max_lines`/`body_forbidden` are the owner-site record's
  schema (site-record decision, SPEC-article-draft-pipeline) and re-home in a
  user-config site-record schema block. **Profiles migrate nothing — their
  fields are new declarations**, and profiles must stay reusable by a different
  owner without modification (a profile never embeds publishing strategy). Each
  legacy key deprecates as its user-config re-routing lands (#211 migration
  treatment), and profile-wins precedence applies only to fields profiles
  actually declare. User config also keeps `syndication.policy` — the
  per-language canonical/external decision — because canonicality is a
  relationship across the whole publication topology, not an attribute of any
  one platform: keeping it in one place makes "exactly one canonical per
  language" structural instead of a cross-profile validation. The change
  drivers differ too: packaging changes when a platform changes its rules;
  publishing intent changes when the owner's strategy changes. Not a split in
  authority — user config decides publishing intent, the profile renders that
  decision in the platform's required format (frontmatter `mode` continues to
  source from `syndication.policy`).
