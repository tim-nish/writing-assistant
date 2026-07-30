# Step 2 — two screens

**Read this file on entry to Step 2 of [`../SKILL.md`](../SKILL.md)** — never up
front, and never because the skill was merely invoked. It carries this step's
operating detail verbatim; the dispatcher carries the sequence and the
commands.

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
