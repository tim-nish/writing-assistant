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

## Step 1 — assemble the map

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/terrain_map.py assemble --root <host-repo> > "$WS/map.json"
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

**Decision/reversal Strands (E rows) have their own axis** (Story 20.25,
#860; SPEC-terrain CAP-2 as amended 2026-07-28). Screen 1 offers **two**
axes: **by tag** over Lessons and Journeys, and **by topic** over decisions
and reversals. A decision line's topic *is* its shard key, so nothing is
joined or derived for either. Relay both listings — an E row is reached
under its topic, not hunted for under a tag and never given one.

The two vocabularies **overlap by name** (a name can be both a served tag
and a served decision topic, holding different material), so always carry
the axis word with the member when you present or resolve a choice. A
Strand belonging to neither axis appears in the **outside-both disclosure
line**; relay that line as given.

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

**Screen 1 — the two axes: where do you want to look?** This is the owner's
first choice, offered before any material is shown. Both listings are offered
together, each member carrying its axis word; selecting either leads to the
same Screen 2, and there is no third screen:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py axis \
  --map "$WS/map.json" > "$WS/terrain-axis.json"
python3 -c 'import json,sys; json.dump(json.load(open(sys.argv[1]))["payload"], open(sys.argv[2],"w"))' \
  "$WS/terrain-axis.json" "$WS/topic-map.payload.json"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --surface topic-map "$WS/topic-map.payload.json"
```

**The words the screen uses are defined for the owner, one step away.**
Screen 1's fields are budgeted, so *you* are the carrier: when you present it,
point at [`docs/owner-terms.md`](../../docs/owner-terms.md) — the reader-facing
codebook for the first-class terms this surface uses (**brief**, **Strand**).
Point at it; never restate a definition in your own words, which is how N
paraphrases drift from one contract. If the owner asks what a term means,
the codebook is the answer, not the implementation.

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
  --map "$WS/map.json" --tag <member> --axis <tag|topic> \
  > "$WS/terrain-member.json"
```

Relay the returned `listing` as given: **all** of the member's Strands, whole,
in presentation-only sections, each Strand quoting its served rendering with
its deterministic context line, and the count disclosed.

**The group claim (machine-composed, marked — SPEC-terrain CAP-2 as
amended 2026-07-29, #888).** Before relaying, compose for each section one or
two sentences stating **what its Strands have in common** from the returned
`background.inputs` claims — the group's reason for existing, in plain
language (Tsurezure may be consulted; record any consult per the provenance
rule). Render it directly under the section title, prefixed
`in common:`, and declare the authoring class **once for the screen** — a
single preamble sentence above the sections, e.g. *"Every `in common:` line
below is machine-composed at render time from the served claims."* Repeating
`(machine-composed)` on each line carries nothing per line and costs attention
on every one; the declaration is owed once per surface, not once per line
(CAP-2 as amended 2026-07-30, #936). Mark a line individually only when a
screen **mixes** composed and quoted lines of the same visual class — and then
mark the **minority** class, because that is where the reader's default is
wrong. Say what they share, not what sits behind
them: this line is the germ of a Thesis, and "background" invited reading it
as decoration. It is a **group claim** — never a fact-sheet claim, which is a
different object with a provenance class (`docs/owner-terms.md`).
The `background.rules` bind you as the composer: the prose asserts only that
commonality and never substitutes for a Strand's own text; every Strand stays
exactly once and selectable — you never omit, merge, rank, or gate one; and
when the gateway is unavailable or you skip composition, **say so** and
relay the deterministic titles — a silent skip is the defect a stated
absence is not.

**Journey presence is marked by ABSENCE, and the screen states its denominator
(SPEC-terrain CAP-2 as amended 2026-07-30, #933/#934).** Relay both as given —
neither is yours to compose. A row carrying an arc says nothing about it in its
context line (the arc itself is displayed below the row, as always); a row
whose Lesson has **no** paired journey record carries `· no-journey`. The
listing's coverage line — *n of m Strands carry journey material* — is what
those markers are a fraction of, so it is relayed **above** the sections, never
dropped as boilerplate: at 93% coverage the markers are rare, and a rare marker
with no denominator reads as a defect in the row rather than a fact about the
corpus. Never assert that a member carries no journey material — the
denominator says how much it carries, and only the served records can say none.

Selection is by
Strand index (`L3`, `E2.1`) plus a short note about the angle; free-form
and **stop here** stay on the table exactly as on Screen 1. There is no `J`
index: a Journey is an arc on its lesson's row, so selecting the Lesson carries
the arc with it (#871, and its minting code was removed in #933).

**Selection is a SET (SPEC-terrain CAP-3, added 2026-07-30, #937).** The owner
may name **several** Strand indexes, and the brief is composed from exactly
that set — exploring is how they decide what to write about, not a detour
ending in free text. Pass them as a list or as one comma-separated string; no
named index is dropped or collapsed to the first, and an index that resolves
to nothing refuses the whole selection rather than quietly shrinking it.
Sections stay **presentation-only**: the set is per-Strand multi-select, never
group-select. Naming a group id (`G2`) as a *selection* is refused with the
distinction stated — `G` addresses **inspection**, selection is by Strand
index — because a selectable group would make grouping a gate.

Record the answer against the `ask_id` the validator returned, with the **pin
the listing shows**:

```
printf '%s' '{"index":"L3","note":"<the owner'\''s angle, their words>","pin":"<the listing'\''s pin>"}' \
  | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --answer <ask_id>
```

For a set, `index` carries them all — `{"index":["L3","L7","E2.1"], …}` or
`{"index":"L3, L7, E2.1", …}`.

The pin is not bookkeeping. Indexes are **stable within a pin**, not across
repo states, so an index chosen against a stale listing is
**refused with the mismatch named** rather than re-resolved — re-run the map
and pick from the fresh screens. Free text still always wins; if the owner writes their own
direction, that is the brief and no index is consulted.

### Navigation — one invocation, one corpus load, held state

**A grouping you can reach but not leave is a dead end**, and this surface has
no back button. So navigation is in-invocation and runs over **held state**
(SPEC-terrain CAP-3 as amended 2026-07-29, #892):

- **One invocation = one corpus load.** Assemble the map once, at the start.
  Every deterministic substrate join comes from that one assembly. A judged
  substrate (journey similarity) is computed **lazily**, on first use of the
  view that needs it, and then **held for the rest of the invocation**.
- **"Back" and "switch substrate" RE-PRESENT held state.** Never recompute,
  never re-assemble, never re-invoke `/terrain`. This is a correctness rule
  and not a speed one: a second run of a judged substrate can return a
  different grouping, which would make the owner's own history unstable —
  they would go back and find a different screen than the one they left.
- **The screen carries summaries; the path carries the whole view.** Print
  compact group summaries — the derived title, the member ids, the counts.
  Write the complete rendering of the **current** view to the per-invocation
  path:

  ```
  VIEW=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py topic-map-view --root <host-repo>)
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py view \
    --map "$WS/map.json" --tag <member> --out "$VIEW"
  ```

  Neither half alone is the requirement: ~50 Strands reprinted per view is
  unreadable, and a view living only in a file is uninspectable at the moment
  of selection. **The split is the requirement.**
- **The file is never read back.** It is a rendering of one invocation
  addressed by path, regenerated every time, with no identity anything else
  refers to. In-invocation memory is fine — it is not storage. **A
  cross-invocation view cache is forbidden.**
- **Every screen carries the standing exits**, without exception: switch
  substrate, back to the member list, name your own direction, stop here. A
  screen missing one is the dead end this whole section exists to remove.

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
never a tool-invented scope. For a single indexed selection the brief is the
Strand's served wording **plus the owner's note verbatim**; from here it is
one ordinary brief string and nothing downstream can tell it from one the
owner typed.

**For a SET, the claim is recomposed over exactly the selected members**
(#937). The command returns `recomposition.claims` — the served claims of
those members and **nothing else**, so the scope cannot widen past what the
owner pointed at — together with `members` (each member's served gloss and
cite) and `pins` (the terrain invocation and the hub commit). Compose the
in-common claim from those inputs and present it as a **machine-composed
proposal beside free-form override**, marked per the once-per-surface rule.
The owner's wording, if they supply any, **is** the brief and the proposal is
discarded. To record an adopted claim instead of the deterministic wording,
pass it back as `claim` in the answer.

**The brief gate may carry a coherence CONSULTANT (SPEC-terrain CAP-3, added
2026-07-30, #939).** When a set of two or more is selected the command returns
a `consultant` block: the `subject` (the selected members with their cites),
the **complete, unranked** `substitution_candidates` pool (every unselected
Strand at this pin), and `rules` — four rules that bind you and that you may
not trade against each other:

1. **Nothing is adopted silently.** Whatever you produce reaches the owner as
   a proposal with free-form override. They decide; nothing enters the brief
   without them adopting it.
2. **Every claim cites served material at the pin.** Naming a Strand or a
   group means citing its served rendering or claim at this pin. Introduce
   nothing that is not in the served corpus there.
3. **Incoherence and uncertainty are both stated.** If the set cannot support
   one thesis, say so plainly instead of composing around it. If you are
   unsure, disclose the uncertainty rather than emitting a confident
   structure.
4. **Substitutions enumerate their candidates.** Proposing to replace a
   Strand means listing the candidates you considered — never reducing them
   to one best swap, and never ranking them and surfacing only the strongest.
   Adding unselected material is admissible **only** because nothing is
   hidden; ranking would narrow the set, which is what the owner's having
   selected does and you do not.

The assessment itself is deliberately **not a fixed procedure** — a narrow
mechanism would keep reporting success for satisfying its own steps while
failing what the owner wanted. Judge freely; the four rules are what is
frozen. The consultant **never runs before a selection**: with nothing
selected it has no subject, and running early would make it a scope
originator rather than a consultant.

The recorded brief carries its **member set**, and that is not bookkeeping:
the completeness invariant follows the set into drafting — every selected
Strand placed or its omission disclosed — so a brief with no members recorded
would make omission silent. Every member's writability gap is disclosed in
`gaps`, not just the first one's.

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
