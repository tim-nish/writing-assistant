---
name: terrain
description: >
  Show the terrain before choosing what to write. Invoke as "show the terrain"
  (also accepted, unchanged: "show the topic map", "what could I write about")
  to assemble the derived, bounded ELEMENT SURVEY of the hub — every Lesson
  and Journey an individually selectable Strand, quoting its served
  Gloss rendering and carrying its visible writability verdict — navigate it
  in TWO SCREENS (the served-tag axis, then one member's complete material)
  plus free-form, and hand the owner's chosen direction to the existing
  stage-0 --brief path as an ordinary brief-carrying run. The contract it
  fronts is SPEC-terrain CAP-1/CAP-2/CAP-3 as amended through 2026-07-27
  (#799, #803, #844); this skill re-implements nothing.
---

# Terrain

The article-creation entry point for **"what could I write about?"**. It ends in
a **brief**, not in a second proposer, and it **navigates in two screens over
the served gloss tag** (the #803 resolution): **Screen 1** offers the axis —
every served tag with its Strand count — as the owner's first choice of where
to look; **Screen 2** shows the chosen member's complete material, every hub
Lesson and Journey an individually selectable Strand. N Strands are N distinct
selectable ideas. Navigation replaces filtering: nothing decides for the owner
what appears, and nothing is withheld. (The former subtopic clustering was
abandoned, not tuned — #809; its narration is gone from this flow, and this
skill proposes no machine-derived combinations: naming a combination is the
owner's free-form move.)

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
coverage disclosure. The per-member Strand count on Screen 1 is **the only
depth affordance** — a cue for choosing where to look, never a gate — and a
consumed Strand is shown **marked consumed, not hidden**.

If `coverage.complete` is false, say so in one line with the count the
disclosure names: the map read up to its bound and the rest is listed, not
silently dropped.

**Reachability of decision/reversal Strands (E rows) — a known property, not
a surprise.** A Strand's axis membership comes from its served gloss tags; a
decision or reversal Strand that joins no gloss entry carries an empty tag
list, so it appears in the **untagged-disclosure line**, not under any axis
member. When you present Screen 1, that line is where such Strands live —
relay it as given; do not hunt for them under a member or invent a tag.

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

## Step 2 — two screens

**Screen 1 — the axis: where do you want to look?** This is the owner's first
choice, offered before any material is shown:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py axis \
  --map "$WS/map.json" > "$WS/terrain-axis.json"
python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))["payload"], open(sys.argv[2],"w"))' \
  "$WS/terrain-axis.json" "$WS/topic-map.payload.json"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --surface topic-map "$WS/topic-map.payload.json"
```

Present the validated payload **in-conversation** under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md): every
served tag listed deterministically with its Strand count — the count is a cue
for choosing where to look, never a gate — plus the untagged-disclosure line
when it applies (see Step 1). The payload is **plain text**: no `**bold**`, no
backticks, no headings, no Markdown links (contract (g)). A non-zero exit
means the payload is not presentable — fix the named field and re-validate; a
blocked payload is never shown.

Screen 1 always also offers:

- **name your own direction** — offered **every time**, not only on rejection.
  The owner's own wording is a first-class outcome, including a combination
  of subjects in their words (this skill proposes no machine-derived
  combinations);
- **stop here** — also first-class: nothing is drafted, no brief is recorded,
  and the map is recomputed fresh next time.

**Screen 2 — the chosen member's complete material.** When the owner picks a
member on Screen 1:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py member \
  --map "$WS/map.json" --tag <member> > "$WS/terrain-member.json"
```

Relay the returned `listing` as given: **all** of the member's Strands, whole,
in presentation-only sections, each Strand quoting its served rendering with
its deterministic context line, and the count disclosed.

**Section background (machine-composed, marked — SPEC-terrain CAP-2 as
amended 2026-07-27, #850).** Before relaying, compose for each section one or
two sentences of shared background from the returned `background.inputs`
claims — what connects the section's Strands, in plain language (Tsurezure
may be consulted; record any consult per the provenance rule). Render it
directly under the section title, prefixed `background (machine-composed):`.
The `background.rules` bind you as the composer: the prose is background
only and never substitutes for a Strand's own text; every Strand stays
exactly once and selectable — you never omit, merge, rank, or gate one; and
when the gateway is unavailable or you skip composition, **say so** and
relay the deterministic titles — a silent skip is the defect a stated
absence is not. Selection is by
Strand index (`L3`, `J1`, `E2.1`) plus a short note about the angle; free-form
and **stop here** stay on the table exactly as on Screen 1. Record the answer
against the `ask_id` the validator returned, with the **pin the listing
shows**:

```
printf '%s' '{"index":"L3","note":"<the owner'\''s angle, their words>","pin":"<the listing'\''s pin>"}' \
  | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --answer <ask_id>
```

The pin is not bookkeeping. Indexes are **stable within a pin**, not across
repo states, so an index chosen against a stale listing is
**refused with the mismatch named** rather than re-resolved — re-run the map
and pick from the fresh screens. Free text still always wins; if the owner writes their own
direction, that is the brief and no index is consulted.

### The size switch — an over-budget member gets a View file

**The screen budget is measured over one axis member's Screen 2, not over the
whole terrain** (SPEC-terrain size switch, re-based 2026-07-27, #803):
two-screen navigation shrinks the overload condition without removing it,
because a single tag can still hold many Strands. The composer switches on
size; the skill decides nothing here — it relays what comes back:

- **At or under the budget** — the Screen 2 flow above, unchanged. No View
  file is written and no path appears on the screen.
- **Above the budget** — the screen becomes a short **summary plus the path
  of a View file**, rendered by the composer:

  ```
  VIEW=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py topic-map-view --root <host-repo>)
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py view \
    --map "$WS/map.json" --out "$VIEW"
  ```

  The View is written for the owner to *open and read* in the `output.drafts`
  destination repository — the one artifact this flow does not put in the
  workspace. Relay the path as given; selection is **by index** plus a short
  note, recorded exactly as on Screen 2, and the above-budget branch proposes
  **no less** than the small one. Exit 3 means no destination is declared;
  relay the error, which names the fix.

The View is at the same status as a debug dump: a **fixed path**, **fully
regenerated** on every invocation, and **never read back** by any code path.
Deleting it loses nothing — re-run the map.

## Step 3 — the brief, then a normal run

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py brief \
  --payloads "$WS/presented-payloads.jsonl" --map "$WS/map.json"
```

The outcome is a **brief in the owner's words**. Free text always wins;
machine-proposed wording becomes the brief only when the owner selected it —
by naming a Strand's **index** — and then it is **owner-adopted wording**,
never a tool-invented scope. For an indexed selection the brief is the
Strand's served wording **plus the owner's note verbatim**; from here it is
one ordinary brief string and nothing downstream can tell it from one the
owner typed.

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

- **The map never composes narrative structures.** A Strand names *what* to
  cover — never how the piece is told, ordered, or opened. Structure
  candidates remain the shipped **single proposer's** job downstream
  (SPEC-article-draft-pipeline CAP-4, Story 18.45). A map that starts
  suggesting article shapes has become the second proposer #554/#583 both
  forbid.
- **The map is a view, not a gate.** It never refuses a member on depth, never
  hides consumed material, and never narrows the sources a run may read.
- **Evidence never blocks drafting.** The writability verdict surfaces at
  selection and decides what the selection *yields* (evidence pre-located, or
  a gap disclosure plus its tracking artifact) — never whether the element
  appears and never whether the draft runs. There is no refusal path on
  evidence anywhere in this flow.
- **Sections never gate.** Screen 2's sectioning is presentation only — a
  permutation of the member's complete material; nothing is selectable only
  through a section, and no section's shape limits which Strands the owner
  may pick.
- **Stopping is an outcome.** A sitting that ends at the screen has cost
  nothing and left nothing behind.
- **The View is a rendering, never a record.** Nothing reads it back, no
  decision is stored in it, and it is regenerated whole every invocation. If it
  is ever consulted as an input, the map has grown the stored index CAP-1
  exists to prevent.
