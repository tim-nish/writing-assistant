---
name: terrain
description: >
  Show the terrain before choosing what to write. Invoke as "show the terrain"
  (also accepted, unchanged: "show the topic map", "what could I write about")
  to assemble the derived, bounded ELEMENT SURVEY of the hub — every Lesson
  and Journey an individually selectable article idea, quoting its served
  Gloss rendering and carrying its visible writability verdict — present ONE
  screen of candidate directions plus free-form, and hand the owner's chosen
  direction to the existing stage-0 --brief path as an ordinary brief-carrying
  run. The contract it fronts is SPEC-terrain CAP-1/CAP-2/CAP-3 as pivoted
  2026-07-27 (#799); this skill re-implements nothing.
---

# Terrain

The article-creation entry point for **"what could I write about?"**. It ends in
a **brief**, not in a second proposer, and it **opens with the element
survey** (the stance-3 pivot, #799): the typed elements — hub Lessons and
Journeys — are the primary, individually selectable article-idea units. N
elements are N distinct selectable ideas. The former subtopic clusters remain
on the surface as a **derived, secondary grouping** that never gates what is
selectable, and the flow no longer opens by clustering.

```
show the terrain [<host-repo>]
```

`show the topic map` and `what could I write about` remain accepted triggers —
the rename is owner-facing vocabulary, not a change to what the owner may type
(SPEC-terrain, 2026-07-26 amendment).

**Name the target repository first (#309).** Before reading anything else,
print the resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`.

## Step 0 — mint the run workspace

Everything this flow writes is an **intermediate**, never a product: the map,
the payload, the recorded answer. They go to the run's **workspace outside the
host repo** (`docs/storage-architecture.md` D1/D2), never into the host working
tree. Mint one before anything below uses `$WS`:

```
WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run --root <host-repo>)
```

**The path resolver owns every storage path** — this skill composes none of
them itself. Skipping this step does not fail loudly: `$WS` simply resolves to
whatever the surrounding shell happens to hold, which is how a real invocation
wrote its intermediates into a harness scratchpad (#611).

## Step 1 — assemble the map

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map.py assemble --root <host-repo> > "$WS/map.json"
```

The map is **derived, never stored**: it is recomputed from the articles repo
and the shipped consumption view at every invocation, and nothing it writes is
read back. Exit 3 means no articles repo is resolvable — relay the error, which
already names the declaration that is missing, and stop.

Read, but do not re-explain, what it carries: the **elements** — every hub
Lesson and every served Journey rendering, each its own selectable idea, each
quoting the served `gloss:` / `journey_gloss:` rendering (the plain-language
text the hub ratified at its distill gate — **never the recall one-liner**;
where the rendering is not being served the map says so, `gloss.reason`, and
you relay the disclosure rather than substituting other text) — plus the
subtopic clusters as the derived, secondary grouping, each cluster's
evidence-density signal and depth estimate, and the coverage disclosure.
**Depth is a signal for the owner's judgment, never a gate** — thresholds
decide what is *surfaced*, never what the owner may pick, and a consumed
element or subtopic is shown **marked consumed, not hidden**.

If `coverage.complete` is false, say so in one line with the count the
disclosure names: the map read up to its bound and the rest is listed, not
silently dropped.

**Subtopic names belong to the articles repo.** A declared `subtopic:` (or
`cluster:`) in backlog frontmatter names the cluster; everything undeclared
falls to the derived **path family**, and each cluster records which basis
named it. The repo is authoritative — a cluster disagreeing with a declared
name is this tool's defect, not the repo's — and nothing is cached: the
declaration is re-read every invocation, so the mismatch check is
recomputation, never reconciliation.

If `subtopic_defects` is non-empty, relay each entry in one line: the item, the
key, and the reason. A declaration the map cannot honour is a **configuration
defect in the articles repo, named** — never a silent fall-back to derivation.

**Usability verdict per candidate (the topic↔evidence join, #669; enforced on
every element, #799).** Each item AND each element carries a `usability`
verdict resolving whether the target repo can *evidence* it, and the map's
`needs_recording` list is the join's product. The verdict is **surfacing,
never a filter and never a refusal**: every element appears whatever its
verdict says, every element stays selectable, and selecting an unmatched one
yields the gap disclosure plus its tracking artifact (Step 4) while the draft
proceeds. A flow that refuses to draft on a missing-Evidence verdict is the
defect this pivot removed (owner ruling, #799):

- **matched** — a declared source (for a hub lesson, a `journey:` entry carrying
  its slug — #671) resolves into the read boundary → offer as **draft-ready**,
  evidence pre-located. The verdict carries the pointers `checked` (audited).
- **episodic-unrecorded** — a hub lesson no declared source carries → it appears
  in `needs_recording` as a **NEEDS-RECORDING task** naming the lesson slug, the
  episode, and the target `journey:` file. **Present this list — never silently
  filter to matched**: the unusable topic IS the map's product, a named backfill
  worklist (recording an episode there makes the next harvest match it — the
  flywheel).
- **no-episode** — a hub lesson with no locatable episode: **still selectable
  and still drafted** — offered on the **owner-attributed framing tier** (the
  Story 17.1 attribution tier: a framing contribution, not sourced claims),
  stated as such. The seam serves index lines and renderings, not lesson
  bodies, so the map cannot mechanically tell `no-episode` from
  `episodic-unrecorded` (cannot-determine); it defaults an unmatched hub
  lesson to `episodic-unrecorded` and leaves the `no-episode` call to the
  owner at offer.

The join **locates** evidence, it never **supplies** it: no hub line becomes a
SOURCE pointer, and every offer stays a proposal the owner ratifies.

## Step 2 — one screen

```
VIEW=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py topic-map-view --root <host-repo>)
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py payload \
  --map "$WS/map.json" --view "$VIEW" > "$WS/topic-map.payload.json"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --surface topic-map "$WS/topic-map.payload.json"
```

**The View is the one artifact this flow does not put in the workspace.** It is
written for the owner to *open and read*, so it lands at a fixed path in the
`output.drafts` **destination repository** — the repo they work in — resolved
by the path resolver and never composed here. Exit 3 means no destination is
declared; relay the error, which names the fix. The directory is self-ignoring,
so the destination repo never reports the View as untracked. Everything else
(map, payload, answer) stays in `$WS`.

Present the result **in-conversation** under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md) — **one
screen**, the map plus machine-proposed candidate directions plus a **free-form
response**, and never a second confirmation after they answer. The payload is
**plain text**: no `**bold**`, no backticks, no headings, no Markdown links
(contract (g)). A non-zero exit means the payload is not presentable — fix the
named field and re-validate; a blocked payload is never shown.

The screen always carries, in this order:

- the **candidate directions**, opening with the **elements** — every Lesson
  (`L<n>`) and Journey (`J<n>`) an individually pickable idea quoting its
  served rendering, its writability verdict visible on the row — then at least
  one **cross-topic combination** when two subtopics in different topics share
  evidence, then the demoted cluster directions;
- **name your own direction or combination axis** — offered **every time**, not
  only on rejection. The owner's own wording is a first-class outcome;
- **stop here** — also first-class: nothing is drafted, no brief is recorded,
  and the map is recomputed fresh next time.

Record the answer against the returned `ask_id`:

```
printf '%s' '<answer JSON>' | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --answer <ask_id>
```

### The size switch — a large map gets a View file

**One screen does not scale.** Past the composer's declared screen budget, a
20+-subtopic terrain collapsed into a handful of options hides exactly what the
map exists to show. So the composer switches on the map's own size, and the
skill does not decide anything here — it just passes `--view` and relays what
comes back:

- **At or under the budget** — the flow above, unchanged. No View file is
  written and no path appears on the screen.
- **Above the budget** — the composer writes the terrain to the resolver-owned
  `$VIEW` path and the payload becomes a short **summary plus that
  path**. Relay the path as given and let the owner open it; selection is then
  **by index** (`L3`, `J1`, `E2.1`, or `T3.2`) plus a short note about the
  angle they want, rather than by matching a proposed direction string.
  Free-form and **stop here** are offered exactly as above. A 100-element
  terrain is always above the budget — the View **is** the element survey.

Record an indexed answer with the **pin the View header shows**, alongside the
owner's note:

```
printf '%s' '{"index":"T3.2","note":"<the owner'\''s angle, their words>","pin":"<the View'\''s pin>"}' \
  | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --answer <ask_id>
```

The pin is not bookkeeping. Indexes are **stable within a pin**, not across
repo states, so an index chosen against a View that has since gone stale is
**refused with the mismatch named** rather than re-resolved — re-run the map
and choose from the fresh View. Free text still always wins; if the owner
writes their own direction, that is the brief and no index is consulted.

This is the one case where the map hands the owner **an artifact to open**
(SPEC-terrain CAP-3, amended 2026-07-23, superseding the earlier
in-conversation-only reading for this branch only). The View is at the same
status as a debug dump: a **fixed path**, **fully regenerated** on every
invocation, and **never read back** by any code path. Deleting it loses
nothing — re-run the map.

## Step 3 — the brief, then a normal run

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py brief \
  --answer "$WS/answer.json" --map "$WS/map.json"
```

The outcome is a **brief in the owner's words**. Free text always wins;
machine-proposed wording becomes the brief only when the owner selected it —
by matching a direction or by naming its **index** — and then it is
**owner-adopted wording**, never a tool-invented scope. For an indexed
selection the brief is the subtopic's coverage wording **plus the owner's
note verbatim**; from here it is one ordinary brief string and nothing downstream
can tell it from one the owner typed.

Hand it to the **existing** stage-0 `--brief` path — the one shipped in Story
18.24 (#505), unchanged:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <framework> <sources...> \
  --brief "<the brief>" --root <host-repo>
```

From here the run is **an ordinary brief-carrying run**: the brief maps to
story-element clusters, seeds the argument-plan thesis candidate, and directs
harvest emphasis within the declared sources, exactly as it does for a brief the
owner typed unaided. There is no new entry pipeline, and nothing downstream can
tell the two apart.

## Step 4 — the gap artifact (only when the brief carries `gap`)

When the selected element's verdict was `episodic-unrecorded` or `no-episode`,
the `brief` output carries a `gap` block. **The draft still proceeds — this
step runs beside it, never instead of it.** Do both:

1. **Relay the disclosure** (`gap.disclosure`) in one or two lines: what the
   verdict means and, for `no-episode`, that the draft is offered on the
   owner-attributed framing tier, stated as such.
2. **Create the NEEDS-RECORDING tracking artifact in the target repo** from
   `gap.needs_recording`: append `entry` as a list item under a
   `## NEEDS-RECORDING` heading in the declared journey doc (`target_file`,
   creating the heading if absent) — or, when the owner prefers, open a GitHub
   Issue in `target_repo` carrying the same content. This is the one write
   this flow makes outside the run workspace and the View, and it is what
   turns a gap into a discharged backfill: recording the episode there makes
   the next run match it (the flywheel).

A `cannot-determine` gap is relayed as its disclosure alone — an absence is
asserted only where it was established, so no recording task is minted from a
lookup that did not look.

## Boundaries

- **The map never composes narrative structures.** A candidate names *what* to
  cover and, for a combination, the *axis* connecting two subjects — never how
  the piece is told, ordered, or opened. Structure candidates remain the shipped
  **single proposer's** job downstream (SPEC-article-draft-pipeline CAP-4, Story
  18.45). A map that starts suggesting article shapes has become the second
  proposer #554/#583 both forbid.
- **The map is a view, not a gate.** It never refuses a subtopic on depth, never
  hides consumed material, and never narrows the sources a run may read.
- **Evidence never blocks drafting.** The writability verdict surfaces at
  selection and decides what the selection *yields* (evidence pre-located, or
  a gap disclosure plus its tracking artifact) — never whether the element
  appears and never whether the draft runs. There is no refusal path on
  evidence anywhere in this flow.
- **Clusters never gate.** The subtopic grouping is a derived, secondary view
  of the same material; nothing is selectable only through a cluster, and no
  cluster's shape limits which elements the owner may pick.
- **Stopping is an outcome.** A sitting that ends at the screen has cost
  nothing and left nothing behind.
- **The View is a rendering, never a record.** Nothing reads it back, no
  decision is stored in it, and it is regenerated whole every invocation. If it
  is ever consulted as an input, the map has grown the stored index CAP-1
  exists to prevent.
