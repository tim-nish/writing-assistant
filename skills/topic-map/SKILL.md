---
name: topic-map
description: >
  Show the terrain before choosing what to write. Invoke as "show the topic
  map" (or "what could I write about") to assemble the derived, bounded map of
  topics, subtopics and evidence depth, present ONE screen of candidate
  directions plus free-form, and hand the owner's chosen direction to the
  existing stage-0 --brief path as an ordinary brief-carrying run. The contract
  it fronts is SPEC-topic-map CAP-1/CAP-2/CAP-3; this skill re-implements
  nothing.
---

# Topic map

The article-creation entry point for **"what could I write about?"**. It ends in
a **brief**, not in a second proposer: one screen showing the terrain plus
candidate directions the owner can accept, combine, or override in their own
words, and then an ordinary drafting run.

```
show the topic map [<host-repo>]
```

**Name the target repository first (#309).** Before reading anything else,
print the resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`.

## Step 1 — assemble the map

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map.py assemble --root <host-repo> > "$WS/map.json"
```

The map is **derived, never stored**: it is recomputed from the articles repo
and the shipped consumption view at every invocation, and nothing it writes is
read back. Exit 3 means no articles repo is resolvable — relay the error, which
already names the declaration that is missing, and stop.

Read, but do not re-explain, what it carries: topics, their subtopics, each
subtopic's evidence-density signal and depth estimate, and the coverage
disclosure. **Depth is a signal for the owner's judgment, never a gate** —
thresholds decide what is *surfaced*, never what the owner may pick, and a
consumed subtopic is shown **marked consumed, not hidden**.

If `coverage.complete` is false, say so in one line with the count the
disclosure names: the map read up to its bound and the rest is listed, not
silently dropped.

## Step 2 — one screen

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py payload \
  --map "$WS/map.json" --view "$WS/topic-map-view.md" > "$WS/topic-map.payload.json"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --surface topic-map "$WS/topic-map.payload.json"
```

Present the result **in-conversation** under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md) — **one
screen**, the map plus machine-proposed candidate directions plus a **free-form
response**, and never a second confirmation after they answer. The payload is
**plain text**: no `**bold**`, no backticks, no headings, no Markdown links
(contract (g)). A non-zero exit means the payload is not presentable — fix the
named field and re-validate; a blocked payload is never shown.

The screen always carries, in this order:

- the **candidate directions** the composer derived from the map's own depth
  signals, including at least one **cross-topic combination** when two subtopics
  in different topics share evidence — the "connect these topics along this
  axis" move that is the reason the map exists;
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
- **Above the budget** — the composer writes the terrain to
  `$WS/topic-map-view.md` and the payload becomes a short **summary plus that
  path**. Relay the path as given and let the owner open it; selection is then
  **by index** (`T3.2`) plus a short note about the angle they want, rather
  than by matching a proposed direction string. Free-form and **stop here**
  are offered exactly as above.

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
(SPEC-topic-map CAP-3, amended 2026-07-23, superseding the earlier
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

## Boundaries

- **The map never composes narrative structures.** A candidate names *what* to
  cover and, for a combination, the *axis* connecting two subjects — never how
  the piece is told, ordered, or opened. Structure candidates remain the shipped
  **single proposer's** job downstream (SPEC-article-draft-pipeline CAP-4, Story
  18.45). A map that starts suggesting article shapes has become the second
  proposer #554/#583 both forbid.
- **The map is a view, not a gate.** It never refuses a subtopic on depth, never
  hides consumed material, and never narrows the sources a run may read.
- **Stopping is an outcome.** A sitting that ends at the screen has cost
  nothing and left nothing behind.
- **The View is a rendering, never a record.** Nothing reads it back, no
  decision is stored in it, and it is regenerated whole every invocation. If it
  is ever consulted as an input, the map has grown the stored index CAP-1
  exists to prevent.
