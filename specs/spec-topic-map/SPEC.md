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
    sources: the articles repo (backlog items with status/track/evidence
    pointers, drafts, published set), the track↔topic mapping in per-repo
    config (articles repo owns track names, hub owns topic names, mapping is
    consumer config under declared precedence — ratified 2026-07-21), and the
    Lesson-consumption derived view (a Lesson is available iff no live or
    ever-published item cites it — ratified 2026-07-22). No map file is
    written for later reuse; a persisted copy in the run workspace is a debug
    artifact, never an input.
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
  - **success:** A sitting that starts at the map ends with a normal
    brief-carrying run; grepping the map implementation for structure
    composition finds none; the map screen offers free-form alongside its
    options every time.

- **CAP-4 (bounded assembly)**
  - **intent:** The map is assembled from **index and frontmatter surfaces**
    — backlog frontmatter, INDEX files, Lesson metadata, evidence-pointer
    lists — never a full-body fan-out over article prose or the hub's history.
    When a declared corpus exceeds the read bound, the map discloses the
    exclusion (which surfaces were not read) rather than silently narrowing —
    the same coverage-disclosure convention harvest uses.
  - **success:** Map assembly cost scales with index size, not corpus body
    size; an over-bound invocation's output names what it skipped.

## Open questions

- **OQ1 — subtopic clustering authority.** Whether subtopic clusters are
  computed per invocation (pure derivation, may vary run to run) or proposed
  once and recorded as backlog frontmatter (stable names, but a stored
  vocabulary to maintain — the articles repo would own it, per "the repo's
  schema is the API"). Start pure-derived; promote to recorded frontmatter on
  observed instability.
- **OQ2 — Quick Start relationship.** Whether the map absorbs, feeds, or sits
  beside the machine-selected Quick Start candidates. They answer different
  questions ("decide for me" vs "show me the terrain"); leaning side-by-side
  entry points sharing CAP-1's assembly.
