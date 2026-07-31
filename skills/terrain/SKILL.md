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
the payload, the recorded answer. They go to the run's **workspace under the
machine state root** — never into the host working tree, and never into a
working tree at all (owner ruling — 2026-07-30, narrowing 2026-07-28;
`docs/storage-architecture.md` D1/D2). **The View is the one exception**: it is
opened by a human, so it lands in the writing-assistant repository. Mint the
workspace before anything below uses `$WS`:

```
WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run --terrain --root <host-repo>)
```

**The path resolver owns every storage path** — this skill composes none of
them itself. Skipping this step does not fail loudly: `$WS` simply resolves to
whatever the surrounding shell happens to hold, which is how a real invocation
wrote its intermediates into a harness scratchpad (#611).

**Relay the workspace path once, as `Run workspace: <path>`**, in the same
register as the host-repo line above. The intermediates now sit outside every
working tree, so the path is the owner's only route back to what a run wrote —
an exit that names none of its state leaves a question no later query answers
(#935).

## How to run — the step sequence (dispatcher)

This file is the **dispatcher** (Story 20.64, #962; the Story 19.3 packaging
pattern, applied here after the breakdown selected the seam): it carries the
step sequence, the one command per step, the relay-and-stop rules, and the
standing boundaries — and **nothing else**. Each step's full operating detail
lives in its companion under [`steps/`](steps/); **on entry to a step, read
exactly that step's file** and execute it. No companion is read because the
skill was invoked. Normative history and contracts live in `specs/` — the
step files cite them and restate nothing.

**Relay-and-stop rules that bind every step:**

- **Relay, never paraphrase.** A payload, a listing, a disclosure line or a
  validator error is relayed **as given**; a non-zero exit is relayed with the
  named fix and the run stops. A blocked payload is never shown.
- **Nothing is decided for the owner.** Every screen offers **name your own
  direction** and **stop here**, every Strand stays selectable whatever its
  verdict says, and stopping is an outcome that costs nothing.
- **One invocation, one corpus load.** The map is assembled once, in Step 1;
  navigation re-presents held state and never re-assembles or re-invokes.

| Step | Enter by reading | The one command |
|---|---|---|
| **Step 0 — mint the run workspace** (above; the storage contract) | — (in this file) | `resolve-paths.py new-run --terrain --root <host-repo>` |
| **Step 1 — assemble the map** (what the map carries; the tag and decision-topic axes; the usability verdict and `needs_recording`) | [`steps/map.md`](steps/map.md) | `terrain_map.py assemble --root <host-repo> > "$WS/map.json"` |
| **Step 2 — two screens** (Screen 1's axis payload; Screen 2's whole-member listing, group claim, journey markers and set selection; the Full Report over named group ids; navigation over held state; the size switch) | [`steps/screens.md`](steps/screens.md) | `topic-map-directions.py axis --map "$WS/map.json"` then `topic-map-directions.py member --map "$WS/map.json" --tag <member> --axis <tag\|topic>` |
| **Step 3 — the brief, then a normal run** (brief composition; set recomposition; the coherence consultant's four rules; the named artifact and its lifecycle; the stage-0 handoff) | [`steps/brief.md`](steps/brief.md) | `topic-map-directions.py brief --payloads "$WS/presented-payloads.jsonl" --map "$WS/map.json" --out "$WS/brief.json"` |
| **Step 4 — the gap artifact** (only when the brief carries `gap`) | [`steps/gap.md`](steps/gap.md) | — (a relay plus one write into the target repo) |

**Step routing notes (the dispatcher's whole job):**

- **Step 1:** exit 3 means no articles repo is resolvable — relay the error,
  which already names the missing declaration, and stop.
- **Step 2:** Screen 1 offers **both** axes (by tag, by topic) and is the
  owner's first choice; picking a member leads to Screen 2, and there is no
  third screen. Above the screen budget, Screen 2 becomes a summary plus a
  **View** file path — the composer switches on size and the skill decides
  nothing (`steps/screens.md`). Selection is by Strand index and may be a
  **set**; a group id may be **typed** and expands into its members at the
  screen that defined it, with `G4 + L26, minus L48` resolved before the brief
  exists and no G-id ever recorded (`steps/screens.md`). Naming group ids as
  an **inspection** is the `report` subcommand —
  the Full Report relays those groups whole, selects nothing, and never
  recomposes a claim (`steps/screens.md`).
- **Step 3:** free text always wins. A set of two or more returns the
  `consultant` block, whose four rules bind you and may not be traded against
  each other (`steps/brief.md`). The brief is a **named artifact** written to
  `$WS/brief.json`: relay its `step.line`, `artifact.line` and
  `lifecycle.line` at the gate, and re-open it with `brief-open` when the
  owner returns to it. It is the one artifact this surface **reads back** —
  the owner's decision, not a rendering — and that leaves the View's
  never-read-back rule untouched. The composed brief is handed to the existing
  stage-0 `--brief` path and the run is an ordinary brief-carrying run.
- **Step 4:** runs **beside** the draft, never instead of it, and only when
  the brief carries `gap`. A `cannot-determine` gap is relayed as its
  disclosure alone.

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
