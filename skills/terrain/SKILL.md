---
name: terrain
description: >
  Show the terrain before choosing what to write. Invoke as "show the terrain"
  (also accepted, unchanged: "show the topic map", "what could I write about";
  and "open the brief [<path>]" to re-enter an existing brief at
  compose-the-brief)
  to assemble the derived, bounded ELEMENT SURVEY of the hub — every Lesson
  and Journey an individually selectable Strand, quoting its served
  Gloss rendering — navigate it
  in TWO SCREENS (the served-tag axis, then one member's complete material)
  plus free-form, and hand the owner's chosen direction to the existing
  run mint's --brief path as an ordinary brief-carrying run. The contract it
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
open the brief [<path>]
```

`show the topic map` and `what could I write about` remain accepted triggers —
the rename is owner-facing vocabulary, not a change to what the owner may type
(SPEC-terrain, 2026-07-26 amendment). All three still start at **the workspace
mint**, unchanged.

**`open the brief [<path>]` enters at compose-the-brief** (Story 20.92, #1042).
Re-opening was already a first-class move and the subcommand already shipped;
what was missing was **words that reach it** — every accepted phrase began at
the workspace mint, so
an owner holding a brief had no way in. This adds discovery for the existing
move and no capability: it runs `brief-open`, relays the artifact's
`lifecycle.line`, and walks no screens and loads no corpus. **With no path**
the brief is resolved by the rule stated in [`steps/brief.md`](steps/brief.md);
with no brief anywhere it says so plainly and starts nothing.

**Name the target repository first (#309).** Before reading anything else,
print the resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`.

## Mint the run workspace

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

## How to run — the process sequence (dispatcher)

This file is the **dispatcher** (Story 20.64, #962; the Story 19.3 packaging
pattern, applied here after the breakdown selected the seam): it carries the
process sequence, the one command per step, the relay-and-stop rules, and the
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
  direction** and **stop here**, every Strand is selectable, and stopping is an
  outcome that costs nothing.
- **One invocation, one corpus load.** The map is assembled once, at the map
  assembly; navigation re-presents held state and never re-assembles or
  re-invokes.

| Process | Enter by reading | The one command |
|---|---|---|
| **mint the run workspace** (above; the storage contract) | — (in this file) | `resolve-paths.py new-run --terrain --root <host-repo>` |
| **assemble the map** (what the map carries; the tag and decision-topic axes; the served journey arc and its typed absence) | [`steps/map.md`](steps/map.md) | `terrain_map.py assemble --root <host-repo> > "$WS/map.json"` |
| **the two screens** (Screen 1's axis payload; Screen 2's whole-member listing, group claim, journey markers and set selection; the Full Report over named group ids; navigation over held state; the size switch) | [`steps/screens.md`](steps/screens.md) | `topic-map-directions.py axis --map "$WS/map.json"` then `topic-map-directions.py member --map "$WS/map.json" --tag <member> --axis <tag\|topic>` |
| **compose the brief, then a normal run** (brief composition; set recomposition; the coherence consultant's four rules; the named artifact and its lifecycle; the edit-set iteration loop and its retained compositions; the run mint's handoff) | [`steps/brief.md`](steps/brief.md) | `topic-map-directions.py brief --payloads "$WS/presented-payloads.jsonl" --map "$WS/map.json" --out "$WS/brief.json" --home "$(resolve-paths.py terrain-briefs-dir)"` |
| **the scope statement** (only when the brief carries `gaps`) | [`steps/gap.md`](steps/gap.md) | — (a relay; this step writes nothing anywhere) |

**Routing notes (the dispatcher's whole job):**

- **assemble the map:** exit 3 means no articles repo is resolvable — relay the
  error, which already names the missing declaration, and stop.
- **the two screens:** Screen 1 offers **both** axes (by tag, by topic) and is the
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
- **compose the brief:** free text always wins. A set of two or more returns the
  `consultant` block, whose four rules bind you and may not be traded against
  each other (`steps/brief.md`). The brief is a **named artifact** written to
  `$WS/brief.json` **and to its durable home** (`resolve-paths.py
  terrain-briefs-dir`) under its **stable id** — a digest of its pin and
  composition, so the same Brief is always the same entry, and the home's
  listing IS the enumeration of Briefs (no index file exists). Relay its
  `step.line`, `artifact.line`, `artifact.id` and
  `lifecycle.line` at the gate, and re-open it with `brief-open` when the
  owner returns to it. It is the one artifact this surface **reads back** —
  the owner's decision, not a rendering — and that leaves the View's
  never-read-back rule untouched. **The gate is a LOOP**: offer the edit-set
  option it hands you in `iteration.option` — `+Lxx −Lyy → recompose` — and
  re-run `brief` with `--from <the composition being edited> --out <a new name
  in the same $WS>`. Prior compositions stay visible in
  `iteration.compositions` so the owner compares theses across set variants;
  retention is **within this sitting**, and an edit across workspaces is
  refused (`steps/brief.md`). The sitting then ends at **draft-article's own
  intent gate** — the closed label set, a reason and a nearest fit, payload
  captured — entered, never reimplemented, with a recommended intent grounded
  in the adopted thesis and sources asked with this run's evidence state
  attached. The composed brief is wired into the existing run mint's `--brief`
  path from the artifact rather than retyped, and the run is an ordinary
  brief-carrying run: uniform in BEHAVIOUR, while the provenance record does
  distinguish the producers (#1050).
- **the scope statement:** runs **beside** the draft, never instead of it, and only when
  the brief carries `gaps`. It is a relay — a scope statement over the
  selection plus each member's episode disclosure — and it writes nothing,
  asks nothing, and mints no tracking artifact (#1183).

## Boundaries

- **The map never composes narrative structures.** A Strand names *what* to
  cover — never how the piece is told, ordered, or opened. Structure
  candidates remain the shipped **single proposer's** job downstream
  (SPEC-article-draft-pipeline CAP-4, Story 18.45). A map that starts
  suggesting article shapes has become the second proposer #554/#583 both
  forbid.
- **The map is a view, not a gate.** It never refuses a member on depth, never
  hides consumed material, and never narrows the sources a run may read.
- **Evidence never blocks drafting.** There is no writability verdict left to
  block with: the host-repo episode join and its four verdicts were removed
  (#1183). A selection yields a brief plus each member's episode disclosure,
  and there is no refusal path on evidence anywhere in this flow.
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
