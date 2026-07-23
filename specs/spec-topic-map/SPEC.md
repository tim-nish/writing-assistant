---
id: SPEC-topic-map
companions: []
sources:
  - ../spec-article-draft-pipeline/SPEC.md   # CAP-9 / the coverage brief and structure proposer this map feeds
  - ../spec-article-plan/SPEC.md             # plan/backlog surfaces the map reads
  # Ratifying owner decision: direct owner demand 2026-07-22 ("a topic map seems
  # essential for routine use"), explicitly superseding the browse-entry-point
  # demand-trigger deferral of 2026-07-22 (hub record; staged for distill).
  # Mechanism public, provenance private.
---

> **Canonical contract.** This SPEC introduces the **topic map**: a read-only,
> derived overview of what the owner *could* write about — topics, their
> subtopic clusters, how much evidence each holds, and how deep an article each
> could carry — presented at the article-creation entry point so the owner can
> steer the free-form story direction (the coverage brief) from an informed
> view, including combining topics along an owner-named axis. **Provenance
> note:** the browsable candidate-story list was deliberately deferred
> (2026-07-22) behind a demand trigger (≥3 sittings where the owner cannot name
> a story and rejects Quick Start). The owner overrode that deferral by direct
> demand the same day, after the first real free-form sitting failed for
> exactly the anticipated reason — no overview to steer by. Per that earlier
> decision's own design note, the free-form entry point's usage is the evidence
> for what this map must contain: it exists to *feed* the brief, not to replace
> it.

# Topic Map

## Why

The free-form story direction (brief → brief-informed structure candidates →
one selection gate, Stories 18.24/18.26/18.45–18.47) assumes the owner can
name the story they want. The first real sitting showed the assumption's limit:
without an overall view of which topics exist, which subtopics live under them,
how much material each holds, and how deep each could support an article, the
owner cannot compose an effective brief — and cannot see cross-topic
combinations ("connect these two topics along this axis") at all. The failure
modes this spec prevents: the owner steering blind (briefs that under- or
over-reach the available evidence); a stored topic index that drifts from repo
reality (every stored-flag design this portfolio has tried has been declined in
favour of derived views); and a second story proposer growing beside the
shipped one (18.45's single-proposer invariant).

The architecture: **the map is a derived, read-only view assembled at
invocation from state that already exists — never stored, never a new
authority; its output is an informed owner, and the owner's chosen direction
flows into the existing brief/structures path unchanged.**

## Capabilities

- **CAP-1 (derived view, never stored state)**
  - **intent:** The map is recomputed at each invocation from authoritative
    sources, enumerated as declared **source families**:
    - **articles-items** — the articles repo (backlog items with
      status/track/evidence pointers, drafts, published set);
    - **hub-lessons** — the hub's Lesson corpus as its **index lines**, served
      through the shipped policy seam (`read-policy-source.py read --only
      LESSONS.md`, the gateway's `lessons_index`: every index line at its true
      line number). Each index line is one lesson seed. *Lesson bodies and
      per-Lesson files are out of scope here — see OQ3.*
    - **host-sources** — the host repo's **declared writing sources**, from the
      single enumerator (`resolve-writing-sources.py files`), read at
      frontmatter/heading level only.

    Plus the track↔topic mapping in per-repo config (articles repo owns track
    names, hub owns topic names, mapping is consumer config under declared
    precedence — ratified 2026-07-21), and the Lesson-consumption derived view
    (a Lesson is available iff no live or ever-published item cites it —
    ratified 2026-07-22). No map file is
    written for later reuse; a persisted copy in the run workspace is a debug
    artifact, never an input. *(Families widened 2026-07-23 — see the
    provenance note under CAP-4.)*
  - **success:** Two invocations straddling a repo change differ exactly where
    the repo changed; deleting the run workspace loses nothing; no new stored
    index exists anywhere.

- **CAP-2 (map content — depth signals, not just names)**
  - **intent:** Per topic, the map shows: its subtopic clusters (grouped from
    backlog items, unconsumed Lessons, and evidence pointers sharing a
    subject — under OQ1's declared precedence as closed 2026-07-23: a
    declared `subtopic:` key in the articles repo names the cluster, and a
    **path-family** derivation is the fallback for undeclared items, with
    each cluster disclosing which basis named it); per subtopic, an
    **evidence-density signal** (count of distinct
    evidence pointers, unconsumed Lessons citing it, backlog items and their
    status) and a **depth estimate** — what the material supports today
    (seed-only / short note / full article / article series), derived from the
    density signal by declared thresholds, presented as a signal for the
    owner's judgment and never as a gate (thresholds gate surfacing, never
    what the owner may pick). Already-consumed material is shown as consumed,
    not hidden — the owner may still pick it at the free-form entry.
  - **success:** For any subtopic shown, the owner can ask "why this depth?"
    and the map answers with its pointer counts; a subtopic with rich material
    and one with a lone seed are visibly different at a glance.

- **CAP-3 (presentation and the combination move)**
  - **intent:** The map is presented **in-conversation** under the owner-facing
    proposal contract — one screen, the map plus machine-proposed candidate
    directions (including at least one cross-topic combination when the
    evidence supports one) plus a free-form response where the owner names
    their own direction or combination axis. The outcome is a **brief**: the
    owner's chosen direction, in the owner's words (machine-proposed text the
    owner accepts becomes owner-adopted wording), handed to the existing
    stage-0 `--brief` path. **No second proposer:** the map never composes
    narrative structures — structure candidates remain the shipped proposer's
    job downstream.
  - **size switch (amended 2026-07-23).** One screen does not scale: past a
    **screen budget** (~7 candidates) a large terrain collapses into a handful
    of options and the map stops showing what it exists to show.
    - **At or under the budget:** the flow above, unchanged. This branch is
      the shipped behaviour and must not regress.
    - **Above the budget:** the screen becomes a short **summary** plus the
      path of a **View file** the owner opens, and selection happens by
      **index** rather than by matching a proposed direction string.
    - **The above-budget branch proposes no less than the small one (amended
      2026-07-23, #632).** The size switch changes *where* the terrain is
      presented, never *whether* the map proposes. So the View **leads with
      candidate directions** — the same derived directions and cross-topic
      combinations CAP-3's intent declares, which the large branch already
      derives unbounded (every subtopic a candidate, the strongest combination
      per distinct axis) — before any terrain detail. A branch that shows the
      terrain and hides the directions inverts the switch's purpose, and it
      would put the owner in front of a raw machine artifact to answer from,
      which the human-gate presentation contract forbids. The directions are
      the ones already derived: the View **reuses** them and derives nothing
      of its own, so the no-second-proposer boundary is untouched — directions
      name what to cover and along which axis, never narrative structure.
  - **the View file.** A *rendering* of one invocation, at the same status as
    `--emit-debug`: written to a fixed path, fully regenerated on every
    invocation, and **never read back as an input** — grep-assertable, like
    the existing derived-never-stored check. It carries, in this order: the
    **candidate directions** above (with the subtopic indexes each names), a
    compact **one-line-per-subtopic summary**, and only then per-subtopic
    detail — stable ID, topic, depth glance, an **evidence summary**,
    lesson-seed names, and consumed marks — enough to distinguish 20+
    directions and to answer CAP-2's "why this depth?" from the same counts.
    Deleting it loses nothing.
  - **the View is a human surface, so it is budgeted (amended 2026-07-23,
    #633/#634).** The View is written for the owner to read, and the
    machine-readable form of everything on it already exists in the run's
    `map.json`. Duplicating that form into the human artifact is what turns
    the View into a log file, so:
    - **Evidence renders as a summary:** the count of distinct pointers, plus
      the pointers **aggregated per source file** (`path ×N`) and capped at a
      declared constant, with the remainder disclosed as a count — never
      silently truncated. Line-granular pointers are machine provenance: the
      full enumeration, with line numbers and per-line shas, stays in
      `map.json`; the View header already carries the pin, which is what
      reproducibility needs.
    - **Depth renders as the level plus the counts it was derived from** —
      "full article: 24 evidence pointer(s), 3 unconsumed lesson(s), 2 live
      item(s)" — because CAP-2's success clause promises exactly that the
      owner can ask "why this depth?" and be answered from those counts. What
      does **not** reach the surface is the **unmet-threshold predicate**
      ("the next level needs `evidence_pointers` 24 < 25"): that is the
      estimator's promotion rule, meaningful to the estimator and not to an
      owner choosing what to write. It stays in `map.json`, where the depth
      harness asserts it — so this is a rendering rule, and the estimate's
      explainability as recorded is unchanged.
    - **Every View line carries a display budget**, and each per-subtopic
      block a line cap, the same convention the screen payload's fields
      already follow: a list renders one item per line, clipped, capped, with
      an explicit `+N more` remainder. A fallback or placeholder state is
      named to the owner as **prose that states the remedy**, never as a bare
      internal enum value in a headline position.
  - **where the View lives (amended 2026-07-23, #611).** "A fixed path" is
    **the `output.drafts` destination repository**, at a resolver-owned,
    host-qualified path — not a per-run workspace directory. The View is
    written for the owner to *open and read*, and a human-facing artifact
    belongs in the repository the human works in, while machine
    intermediates, caches and resumable state stay in machine-state
    directories. A per-run path is not a fixed path: it moves every
    invocation, so nothing the owner opened during a sitting can be reopened
    later.
    - It joins the destination repo's write surface as the **second
      regenerated NON-GATING view**, beside `INDEX.md` — the same class, on
      the same terms: fully regenerated per invocation, never read back,
      never gating any decision, and **named exhaustively** in the footprint
      check (`docs/storage-architecture.md` D1). The class is stated
      narrowly on purpose: "human-facing" is not a general exemption from the
      footprint invariant, and each member of the surface is enumerated.
    - The path resolves through the path resolver like every other plugin
      storage path; no skill, script or prompt composes it.
    - CAP-1's properties are unchanged and remain the binding constraints:
      deleting the View loses nothing, no code path reads it back, and no
      stored index comes into existence. Only the location moves.
  - **stable indexes and the indexed hand-off.** Every subtopic in the map
    (and View) carries a stable ID (e.g. `T3.2`) from a deterministic ordering
    (topics sorted, subtopics ranked as today), **stable within a pin**; the
    View header carries the map's pin, so a selection made against a stale map
    is **refused with the pin mismatch named**, never silently re-resolved.
    Cross-pin stability stays OQ1's escape hatch (promote cluster names to
    recorded frontmatter on observed instability) — out of scope, but the ID
    scheme must not preclude it. Selection is `{index, note}`: the composed
    brief is the subtopic's coverage wording plus **the owner's note
    verbatim**. **Free text always wins**, and an adopted index is
    owner-adopted wording under the shipped rule. The composed brief goes into
    the **existing** stage-0 `--brief` path — no new entry pipeline, and
    downstream cannot tell an indexed selection from a typed brief. The note
    reaches the structure proposer only as brief text, so the single-proposer
    invariant is untouched.
  - **coverage wording is owner-readable by construction (amended 2026-07-23,
    #637).** A candidate's wording becomes the owner's brief the moment they
    adopt it, so **no internal placeholder state may appear in a direction
    string or in a composed brief** — not `(unclustered)`, not `(untracked)`,
    not an empty name. Where a cluster carries no usable name, the wording
    **describes what the cluster contains** rather than naming a subject the
    repo never declared: "cover the not-yet-clustered items under
    `<topic>`", not "cover `(unclustered)`". This is a constraint on the
    *derivation*, not on the rendering: fixing it only where the View prints
    would leave the adopted brief carrying the enum, which is the actual
    defect. The articles repo still owns subject *names* (OQ1) — this governs
    only the wording the tool composes when the repo named nothing.
  - **success:** A sitting that starts at the map ends with a normal
    brief-carrying run; grepping the map implementation for structure
    composition finds none; the map screen offers free-form alongside its
    options every time; a small map behaves exactly as shipped; a >budget map
    produces the View plus summary, is byte-regenerated per invocation, and no
    code path reads the View back. **A >budget View's first screenful presents
    pickable candidate directions — not terrain detail — and no View line
    exceeds its display budget**; grepping the View for a raw pointer
    enumeration or for threshold arithmetic finds none.
  - **provenance (2026-07-23, owner ruling):** this supersedes CAP-3's
    original in-conversation-only reading — "never a path or artifact for the
    owner to open" — for the >budget branch only, by direct owner demand after
    a 20+-subtopic terrain was presented as a two-option screen. The
    alternative that preserved the clause literally (full terrain as
    conversation text, indexes typed into free-form) was offered and declined.
    Mechanism public, provenance private, as with the 2026-07-22 override.

- **CAP-4 (bounded assembly, disclosed per family)**
  - **intent:** The map is assembled from **index and frontmatter surfaces**
    — backlog frontmatter, INDEX files, Lesson index lines, declared-source
    frontmatter/headings, evidence-pointer lists — never a full-body fan-out
    over article prose or the hub's history, and **never a drafting-stage
    extraction pass**: harvest's per-source budgeted extraction is a cost the
    map does not pay, so "show me the terrain" stays index-scale.
    Enumeration is **per family** (CAP-1), and disclosure names its own
    denominator: the coverage manifest lists **which source families were
    enumerated** and **which declared families were not**, alongside the
    per-surface read/skipped lists. When a declared corpus exceeds the read
    bound, the map discloses the exclusion (which surfaces were not read)
    rather than silently narrowing — the same coverage-disclosure convention
    harvest uses. **"Complete" is complete over a named denominator**: a
    coverage claim that does not name the families it covers is the defect
    this clause exists to prevent.
  - **success:** Map assembly cost scales with index size, not corpus body
    size; an over-bound invocation's output names what it skipped; the closed
    accounting (`read + skipped == matched`) holds **per family**; a reader of
    the manifest can tell which families a "complete" claim covers and which
    declared families it does not.
  - **provenance (2026-07-23, owner ruling):** CAP-1's source list and CAP-4's
    index-and-frontmatter-only wording were widened by direct owner demand
    after the first large-corpus invocation returned 2 topics / 2 subtopics
    with an honest "coverage complete" — true over the wrong corpus, because
    enumeration reached only the articles repo's own items. The widening is
    deliberately **index-level and consumer-side**: no gateway grant is
    required and no harvest pass is invoked, so the cost promise above
    survives the corpus growing. Mechanism public, provenance private, as with
    the 2026-07-22 deferral override.

## Open questions

- **OQ1 — subtopic clustering authority. CLOSED 2026-07-23 (#614).**
  *Original question:* whether subtopic clusters are computed per invocation
  (pure derivation, may vary run to run) or proposed once and recorded as
  backlog frontmatter (stable names, but a stored vocabulary to maintain —
  the articles repo would own it, per "the repo's schema is the API"). The
  original answer was: start pure-derived; promote to recorded frontmatter on
  observed instability.
  **Trigger amended.** The promotion trigger read *observed instability*
  (names moving between pins). The failure actually observed at corpus scale
  is **degeneracy**: a 147-subtopic map whose clusters were stable and
  useless — one subtopic per file, because the derivation's fallback is an
  evidence-pointer *file stem* and host-source items cite only themselves.
  Stable-but-degenerate is a distinct failure from unstable, and it is
  equally disqualifying, so the trigger now names both.
  **Resolution — both mechanisms, under declared precedence:**
  - **The articles repo owns subtopic names.** A declared `subtopic:` (or
    `cluster:`) key in backlog frontmatter is authoritative, consistent with
    "the article repo is separate permanently; the repo's frontmatter schema
    is the API, the tool never owns state" and with the ratified
    track↔topic vocabulary-ownership split. A declared name that a cluster
    disagrees with is the tool's defect, never the repo's.
  - **The derivation is the fallback, and must be good.** Undeclared items
    still cluster, by **path family** rather than by file stem — the corpus
    cannot be annotated in one sitting, and a map that stays degenerate until
    a backfill completes fails the owner for the whole interval. The
    derivation invents no stored state: it is recomputed per invocation and
    recorded nowhere, so CAP-1 is untouched.
    **"Good" governs the WORDING too (2026-07-23, #637), not only the
    clustering.** A cluster the derivation could not name still has to be
    describable to the owner, because its coverage wording becomes their brief
    on adoption (see CAP-3's owner-readable-wording clause). An internal
    placeholder reaching that wording is the tool's defect, never the repo's —
    the same rule this section already states for a declared name a cluster
    disagrees with.
  - **The basis is disclosed.** Each cluster states whether its name is
    `declared` or derived, so the owner can always tell which authority
    produced it — the mismatch check is recomputation, never reconciliation,
    and no vocabulary is cached on the tool side.
  Cross-pin ID stability (CAP-3) now has its escape hatch in the declared
  key, exactly as that clause anticipated.
- **OQ2 — relationship to a "decide for me" entry point.** *(Restated
  2026-07-22, triage #583.)* **`unverified — no such surface ships today`:**
  "Quick Start" names no capability, skill, script, or contract in this
  repository — the term appears only in this spec. The original phrasing read
  as a binding to an existing entry point, which would be an unverified
  inference, so the question is restated at the altitude it actually sits at:
  **should a machine-selected "decide for me" entry point exist at all**, and
  if one is ever built, does it absorb, feed, or sit beside the map? The two
  answer different questions ("decide for me" vs "show me the terrain"), and
  side-by-side entry points sharing CAP-1's assembly remains the leaning — but
  nothing here may be written as though the counterpart exists. **This spec
  binds only to surfaces that ship**: CAP-3's outcome is handed to the
  **existing stage-0 `--brief` path** (`skills/draft-article/SKILL.md`, owner
  coverage brief, Story 18.24 / #505), and CAP-1 reads the shipped
  `track_topics` config mapping (`scripts/resolve-writing-sources.py`, #525).

- **OQ3 — Lesson bodies are unservable, so depth from a Lesson is coarse.**
  *(Raised 2026-07-23 with the CAP-1 widening.)* CAP-1's `hub-lessons` family
  reads **index lines only**, because the policy seam's read scope is
  code-enforced to `GLOSSARY.md`, `LESSONS.md` and ≤2 `topics/*.md`
  (`scripts/read-policy-source.py:101`, `:286`), and that boundary is enforced
  server-side by the gateway's grant table as well (`:21-22`) — per-Lesson
  files are structurally unreadable *and* unservable from here. Consequently a
  richer per-Lesson signal (notably the `## Journey` marker the working-note
  workflow selects on) **cannot be read consumer-side today**, and nothing in
  this spec may be written as though it can. Obtaining it would require a
  hub-side grant change, which is the hub's decision and not this repository's
  to make (gateway read-only, grants hub-owned). Open: whether to request that
  grant, or to accept index-line seeds as the permanent shape and let depth
  from lessons stay coarse.

- **OQ4 — is the map's unit a subtopic cluster or a typed element?** *(Raised
  2026-07-23 with #631; deliberately left open by that issue's resolution.)*
  #631 asks for the map's unit to become a **typed element** — `lesson |
  failure-retro | reversal | decision | thinking`, each with a one-line
  summary, the situation it was recorded in, a consumed mark, and 1–3 evidence
  pointers — grouped by situation or by similar meaning, rather than the
  path-family subtopic cluster CAP-2 declares and OQ1 closed. The rendering
  half of that direction was resolved above (the View leads with directions,
  and is budgeted); **the unit itself was not**, for a reason that is a fact
  about the substrate rather than a preference:
  - CAP-4's declared families are exactly `articles-items`, `hub-lessons` and
    `host-sources` (`scripts/topic-map.py:153-155`), and `hub-lessons` is one
    seed per `LESSONS.md` **index line** (`:328-335`). Nothing this repository
    can read records a **reversal**, a **decision with its why**, or
    **thinking-at-the-time** as a typed record. Three of the five proposed
    element types are therefore not projectable today.
  - Reaching them means widening the policy seam's read scope, which is
    **hub-side ratification, not a map-side change** — the same boundary OQ3
    documents, and #631 states this itself.
  So the unit question is blocked on the same upstream decision as OQ3, and
  adopting the element unit before that grant exists would write this spec as
  though it can read what it cannot. Open: whether to request the grant (with
  OQ3, as one hub-side ask), or to keep the subtopic cluster as the permanent
  unit and treat typed elements as a projection the hub itself would have to
  serve. Until this closes, #631 stays open against it.
