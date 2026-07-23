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
    subject); per subtopic, an **evidence-density signal** (count of distinct
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
  - **the View file.** A *rendering* of one invocation, at the same status as
    `--emit-debug`: written to a fixed path, fully regenerated on every
    invocation, and **never read back as an input** — grep-assertable, like
    the existing derived-never-stored check. It carries per subtopic: stable
    ID, topic, depth glance, evidence-pointer list, lesson-seed names, and
    consumed marks — enough to distinguish 20+ directions and to answer
    CAP-2's "why this depth?" from the same counts. Deleting it loses nothing.
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
  - **success:** A sitting that starts at the map ends with a normal
    brief-carrying run; grepping the map implementation for structure
    composition finds none; the map screen offers free-form alongside its
    options every time; a small map behaves exactly as shipped; a >budget map
    produces the View plus summary, is byte-regenerated per invocation, and no
    code path reads the View back.
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

- **OQ1 — subtopic clustering authority.** Whether subtopic clusters are
  computed per invocation (pure derivation, may vary run to run) or proposed
  once and recorded as backlog frontmatter (stable names, but a stored
  vocabulary to maintain — the articles repo would own it, per "the repo's
  schema is the API"). Start pure-derived; promote to recorded frontmatter on
  observed instability.
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
