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

Screen 2 is composed in **two calls**, and the SCRIPT emits the screen you
relay (Story 20.66, #976/#977). The first call gives you the sections and the
claim inputs; the second returns the finished screen.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py member \
  --map "$WS/map.json" --tag <member> --axis <tag|topic> \
  > "$WS/terrain-member.json"
```

Compose one `in common:` claim per section from `background.inputs`, exactly as
described below. Then ask for the screen itself, passing those claims back:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py member \
  --map "$WS/map.json" --tag <member> --axis <tag|topic> \
  --claims '{"G1":"<your claim for G1>", ...}' \
  > "$WS/terrain-screen.json"
```

**Relay the returned `listing` as one block, unchanged.** It already carries
the group ids, your claims, every Strand's served rendering, its deterministic
context line, any absence marks, and the count. **Do not retype, re-fit,
shorten or re-quote an individual Strand row** — not to fit a line, not to
read better, not for any reason. The rows are the script's output and yours to
pass on, not to author.

Why the flow is shaped this way rather than trusting a careful relay: rows
were always deterministic, and a hand-relay still reworded a headline between
two groups and dropped a `no-journey` mark from an expanded row (#976, #977).
The instruction to relay faithfully had nothing standing at the layer where it
breaks, so composition moved into the script instead. `check-terrain-relay-fidelity.sh`
asserts the property over the script'"'"'s own output.

**If a group has no single commonality you can state, pass `null` for it**
(`{"G12": null}`). The screen then says so plainly — that the composer looked
and found no one denominator — and the group renders exactly as placed.
This is a **self-report**, not a judgement the machine makes about your
sentence, and it changes nothing about the grouping: no Strand is moved,
reordered or dropped because of it. Reach for it instead of stretching a
claim into an enumeration; a list of things the members separately are is not
a commonality, and saying so is more use to the owner than a sentence that
trails off (#980).

A group you omit entirely is stated as absent — never invented. That is a
different state from `null`: omitted means you did not compose one, `null`
means you did and there was none.

**Do not resize a group to make its claim easier to write.** Group sizes come
from the ratified 20%-of-placements bound; a member cap was proposed and
declined on measurement (#980).

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

**The owner may pull a FULL REPORT for named group ids (SPEC-terrain CAP-3,
added 2026-07-30, #938).** When they want to judge whether a grouping actually
makes sense, they name group ids from the screen and read each group whole:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py report \
  --map "$WS/map.json" --tag <member> --groups "G1,G3" \
  --claims '{"G1":"<the claim you composed for G1, verbatim>", ...}'
```

Relay the returned `report` **as given**. Each named group renders separately,
in the order asked, keyed by its screen id — never flattened into a union,
because a union destroys the boundary being judged. Each group shows its
existing claim first, then every member Strand's full served rendering. Pass
back the claims you already composed: this path **carries** them verbatim and
**never recomposes** — recomposition belongs to subset selection (#937) and is
not reachable from here. A group whose claim you do not pass states the
absence rather than having one invented.

The report is **inspection only**: nothing is selected, no brief is composed,
and the standing exits stay where they are. It relays **whole** even past the
screen budget — a stated exception, bounded by the owner's own pointers, since
it covers exactly the groups named and never the whole member. It renders from
the invocation's held state and `map.json`; the written View file is never read
back, here or anywhere. Group ids are per-screen and per-pin, so the report
restates the pin and each id's definition — `G2` alone is unreadable one
invocation later.

The deterministic context line does **not** sit on the row here (CAP-3 as
amended 2026-07-31, #987): placement, origin pin and attestation are collected
in a **footnote block at the end of the report**, out of the reading flow and
none of them dropped. That is a property of this surface only — the selection
screens above keep the line on the row, which is where placement is
navigation.

**Selection is a SET (SPEC-terrain CAP-3, added 2026-07-30, #937).** The owner
may name **several** Strand indexes, and the brief is composed from exactly
that set — exploring is how they decide what to write about, not a detour
ending in free text. Pass them as a list or as one comma-separated string; no
named index is dropped or collapsed to the first, and an index that resolves
to nothing refuses the whole selection rather than quietly shrinking it.
Sections stay **presentation-only**: the set is per-Strand multi-select, never
group-select.

**A GROUP ID MAY BE TYPED — it expands into its members (SPEC-terrain CAP-3,
added 2026-07-31, #996).** The owner reads a Full Report and composes from
what they read there, group ids included: `G4` expands to that group's member
Strand indexes **at the screen that defined it**, and from that moment only
the members exist. Mixed input composes by **expand-then-set-arithmetic** —
`G4 + L26, minus L48` (`minus` subtracts every id after it until the next
`+`) — all of it resolved **before the brief exists**. The composed brief
records **the member indexes and the pins, never a G-id**: a group id is
per-screen and per-pin, so a rendering is still not an address. The result is
indistinguishable from the same set typed member by member, which is the test
that this is typing convenience and not a new address kind — so this is **not**
group-select, and grouping still gates nothing. Never key anything else on a
G-id: recommending "other Lessons from the same group" is expressly declined,
because it would make a semantic act depend on one invocation's presentation
grouping.

Record the answer against the `ask_id` the validator returned, with the **pin
the listing shows**:

```
printf '%s' '{"index":"L3","note":"<the owner'\''s angle, their words>","pin":"<the listing'\''s pin>"}' \
  | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --answer <ask_id>
```

For a set, `index` carries them all — `{"index":["L3","L7","E2.1"], …}` or
`{"index":"L3, L7, E2.1", …}`.

**When the selection names a group id, record the screen it was read at too** —
`"member":"<the member>","axis":"tag|topic"` (plus `substrate`/`grouping` when
the screen used a non-default one). A G-id names members only on the screen
that minted it, so one submitted with no screen recorded, or one that screen
did not define, is **refused with the reason named** — exactly as a stale
index is, and never re-resolved against some other grouping.

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
