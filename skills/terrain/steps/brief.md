# Step 3 — the brief, then a normal run

**Read this file on entry to Step 3 of [`../SKILL.md`](../SKILL.md)** — never up
front, and never because the skill was merely invoked. It carries this step's
operating detail verbatim; the dispatcher carries the sequence and the
commands.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py brief \
  --payloads "$WS/presented-payloads.jsonl" --map "$WS/map.json" \
  --out "$WS/brief.json"
```

## The brief is a NAMED ARTIFACT with a visible lifecycle

**Added 2026-07-31** (SPEC-terrain CAP-3, #994). The brief used to arrive as a
chat continuation, so the owner could not tell when a brief began existing,
where it lived, or how to return to one. Three things are now on the surface,
and the command returns all three — **relay them, never paraphrase**:

- **the named step** (`step.line`) — the act that produced the brief, so the
  owner refers to it rather than to "the message above";
- **the artifact path** (`artifact.line`) — `--out` writes the composed brief
  to `$WS/brief.json`. `$WS` came from the path resolver in Step 0 and is
  **outside every working tree**; nothing is written into the host repo, and
  the artifact is the owner's route back to what this step decided;
- **the lifecycle** (`lifecycle.line`) — `composed → inspected → adopted`,
  with the current state legible. It is `composed` the moment the artifact is
  written; a composition that records the owner's adopted candidate (`claim`
  in the answer) is `adopted` in the same act (#1208).

**Re-opening is a first-class move, and this artifact is the one thing the
terrain surface reads back:**

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py brief-open \
  [--at "$WS/brief.json"] [--state inspected|adopted]
```

### The named trigger: `open the brief [<path>]` (Story 20.92, #1042)

The move above already shipped; what was missing was **words that reach it**.
Every accepted invocation phrase began at Step 0, so an owner holding a brief
had no way to Step 3. `open the brief [<path>]` is that way in — **discovery
for the existing move, not a new capability.** A diff that adds capability here
has exceeded the story.

It runs `brief-open`, relays the returned `lifecycle.line`, and **walks no
screens and loads no corpus**. The lifecycle is exactly what `brief-open`
already performs: forward-only, no new transition, no new state.

**With no path, the resolution rule is stated and deterministic** — never a
heuristic the owner cannot predict:

1. the **newest terrain run workspace** (run ids are timestamps, so the newest
   sorts last; the `latest` shorthand is a symlink and is skipped);
2. inside it, the artifact named **`brief.json`**.

A workspace may also hold recompositions from the edit-set loop under their own
names. Those are **named, never guessed between**. And when no brief exists
anywhere, the trigger **says so plainly** — it does not fall through to Step 0
and it composes nothing.

**The cross-workspace boundary is preserved, and it is the criterion most at
risk here.** Opening and inspecting a brief from an earlier workspace
**succeed** — opening is not editing. Any **edit-set or recompose** move
reached from that opened brief still hits the existing refusal, unchanged and
with its existing message: retention is within this sitting, and an edit across
workspaces would be the cross-invocation store the never-read-back rule
forbids. Relaxing that refusal to make the trigger convenient would take a
decision this story was not given.

**The standing exits are offered**, as at any other gate on this surface — the
open returns them in `opened.exits`. An entry into the surface that left the
owner with no way onward would be a side door out of it.

**This does not weaken the never-read-back rule, and the difference is the
point.** A View is a *rendering* regenerated per invocation — nothing reads it
back, and deleting it loses nothing, because it recomposes from the map. The
brief is *the owner's decision*, which nothing can recompose. Re-opening it is
the requirement, not a cache; no rendering is cached across invocations.

`--state` records the transition the return represents, and the lifecycle
moves **forward only** — a rewind is refused, because a brief the owner
already adopted is not un-adopted by looking at it again.

**What this changes about composition: nothing.** Selection at the screen
composes the brief and that is ratified. This is surfacing only, and the
hand-off below is byte-for-byte the same string it always was — **no drafting
BEHAVIOUR changes because terrain wrote an artifact** (the plan's provenance
record does note which producer ran, #1050).

The outcome is a **brief in the owner's words**. Free text always wins;
machine-proposed wording becomes the brief only when the owner selected it —
by naming a Strand's **index** — and then it is **owner-adopted wording**,
never a tool-invented scope. For a single indexed selection the brief is the
Strand's served wording **plus the owner's note verbatim**; from here it is
one ordinary brief string, and downstream BEHAVIOUR is identical to a brief
the owner typed (the provenance record still distinguishes them, #1050).

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

## The gate proposes 2–3 CANDIDATE THESES, not one

**Added 2026-07-31** (SPEC-terrain CAP-3, #995). One thesis was composed per
selection and the gate offered adopt, narrow, or restart — so every upstream
step was free-form reading and free-form typing, and the owner **designed the
article from scratch in chat**. The intended shape is **article design as a
sequence of selections**: a thesis chosen from candidates, then a structure,
and onward.

**Compose the candidates yourself. Nothing already computes them.** The
command returns `candidate_theses` with `composed: false`, and that is literal:
it carries the composition **inputs** (`inputs` — each member's served gloss
and cite), the complete set they are composed over (`over`), the pin, and the
`requirements` your output must satisfy. The consultant block is *not* this
material — it computes a subject list and an unranked substitution pool and
nothing else. **The brief string is not a thesis either**: until a candidate is
adopted it is a `thesis.state: candidates-pending` **coverage statement** over
the members. Relay `thesis.line` so the owner is not left reading a
semicolon-joined list as your reading of their set.

**PUT THE CANDIDATES THROUGH THE CARRIER (Story 20.122, #1135).** You compose
them; presenting them is a GATE and goes through the declared builder:

```
draft_gates.gate("thesis", where=…, why=…, choices=[…], ws=<run ws>)
```

This gate is the one the 2026-08-01 run caught: three candidates plus free
text — inside the control's four-option capacity — rendered as a prose bullet
list, with **no payload in `presented-payloads.jsonl` at all**. The gate id is
declared in `draft_gates.GATES` and `payload()` refuses an undeclared one, so
the call cannot exist without the entry that makes it auditable.

**The requirements bind you and you may not trade them against each other:**

1. **Every candidate is composed over the same complete selected set.** They
   are alternative *readings* of one set, never a narrowing of it. A candidate
   that silently drops a selected Strand is the failure this exists to catch.
2. **Every candidate places every selected Strand or discloses the omission**
   by name, with its reason. Completeness is a **cover counted in placements**.
3. **Every placement cites the Strand's served rendering at this pin.**
   Nothing from outside the served corpus enters a candidate.
4. **Never rank-and-trim.** What is barred is ranking *coupled with*
   discarding: offering the strongest while dropping the rest is the narrowing
   the owner's own selection already did. **Ranking itself is not barred** —
   see requirement 6, which requires the comparison this clause was misread as
   forbidding.
5. **Free text wins**, here as everywhere — the owner's own thesis is the
   brief, and every candidate is discarded when they write one.
6. **Offer a RECOMMENDATION beside the candidates** — never instead of any of
   them. It is machine-**proposed** and never machine-final; it **names the
   axes** it assessed on and **states what would overturn it**; and rank
   confers no default: no candidate is trimmed, hidden, reordered away or
   abbreviated for having ranked lower. Every candidate still arrives whole.

**The axes to reach for** — named defaults, not requirements: **redundancy**
(do two candidates say the same thing in different words), **consistency**
(does a candidate hold together across the Strands it places), and **distinct
Strand relationships** (does it read the set through a relation the others do
not). These are the owner's own three and they are where to start; they are
deliberately *not* frozen into the requirements, so a candidate set whose real
differences lie elsewhere is assessed on those instead. Say which axes you
used, at the gate, whichever they were.

The assessment itself is again **not a fixed procedure**: what is frozen is
what must be TRUE of the candidates that arrive — including that a
recommendation arrives at all — never how you arrive at them. A narrow
mechanism would keep reporting success for satisfying its own steps while
failing what the owner wanted, which is why the axes above are a starting
point rather than a checklist.

**Cost of that choice, stated rather than discovered:** because the axes are
declared per sitting rather than frozen, recommendations are guaranteed to be
*legible* — you can always see what a pick was judged on — but they are **not
yet comparable across sittings**. If cross-run comparability turns out to be
what is needed, the axes get frozen and the "not a fixed procedure" guard is
re-scoped to the consultant where it was earned.

**Then run the count — it is not optional, and it runs AFTER composition:**

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py cover \
  --composed "$WS/candidates.json" --from "$WS/brief.json"
```

Write the composed candidates as `{"kind": "candidate-theses", "over": [...],
"pin": ..., "candidates": [{"thesis", "places", "omits": [{"index", "why"}],
"grounds": [{"index", "cite"}]}]}` — the shape the command hands you in
`candidate_theses.answer`. **A composer that cannot omit in principle can still
omit in fact**, so the count reads what you emitted, never what you composed
from. A refusal returns the **whole** proposal to you — never one candidate
while the rest go on, which would be the map choosing.

To record the owner's chosen candidate, pass it back as `claim` in the answer:
it supersedes the coverage statement and is pinned to this same member set.

## A large selection may be proposed as k article-scoped groups

**Added 2026-07-31** (SPEC-terrain CAP-3, #988). Reviewing fifteen Strands as
one undifferentiated set is harder than it looks, and such a set is often
really *k* coherent theses. Where the selection is large enough the command
returns `partition_proposal` — the same machinery applied to a **partition**
rather than to one set, with the same inputs, the same pin, and its own
`requirements`. Relay `line` and offer it under the **proposal contract**:
**approve / modify / decline**, and **never a silent restructure**.

**It must not filter.** Every selected Strand lands in some proposed group. The
owner may drop members and **only explicitly** — record such a drop as
`{"index", "why", "by": "owner"}`. A Strand that belongs in two groups is
placed in both: this is a cover, and forcing a tie-break would be the map
deciding which relationship the owner may see. Verify with the **same** `cover`
command, over `{"kind": "partition", "over": [...], "groups": [{"label",
"members", "thesis"}], "dropped": [...]}`.

**k accepted briefs feed the drafting backlog — one run at a time, never k
simultaneous publishes.** Compose one brief per approved group by running
`brief` again with that group's members as the selection and its own `--out`
in this same workspace, so each brief is pinned to the subset it was composed
over. `cover` returns the `backlog` block with that order and those commands.

**This is not subdividing an oversized group on the serving screens** (#980).
That is pre-selection presentation refinement bound by the terrain invariants;
this is post-selection and bound by the proposal contract. The licence here is
that the owner **already narrowed, at selection** — so nothing may propose over
an unselected population.

## The gate is a LOOP over the member set

**Added 2026-07-31** (SPEC-terrain CAP-3, #997). The gate used to offer adopt,
narrow, or *go back to Screen 2 and pick differently* — so an owner developing
a thesis by trying members had to leave the gate and lose the composition.
**Offer the edit-set option class alongside the existing options**, exactly as
the command hands it to you in `iteration.option` (`label`, `effect`, the
`editable` set, the answer form). Relay `iteration.line` so the owner sees
where in the loop they are.

The owner's edit is `+L12 −L3` — what CHANGES, signed. Submit it as the
answer's `edit` (or `add`/`drop` lists) and run the **same** command with the
composition being edited named by `--from`:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py brief \
  --answer <answer> --map "$WS/map.json" \
  --from "$WS/brief.json" --out "$WS/brief-2.json"
```

The artifact's identity is its **path**, so each recomposition is a new name
in the **same** `$WS` — that is all the loop needs.

**What the loop does not change is most of it.** A set change is a **gate
event, not a refresh**: the claim recomposes over exactly the edited set and
is pinned to it, which is the recomposition described above, reached rather
than repeated. Pin discipline is unchanged — a missing or mismatched pin is
refused, and so is an edit to a composition pinned elsewhere. **Nothing is
re-ranked or filtered by an edit**: the owner names what changes, so dropping a
member that is not in the set and adding one already in it are both refused
with the current set stated, rather than absorbed as no-ops.

**Prior compositions stay visible** in `iteration.compositions` — each with its
claim, its member set, its pins and the edit that produced it. Relay them so
the owner **compares theses across set variants** instead of remembering them.

**Retention is WITHIN-SITTING, and that is not a technicality.** The chain
lives in this run workspace's own brief artifacts; an edit whose `--from` and
`--out` are in different workspaces is **refused**. A new invocation mints a
new `$WS` at Step 0 and therefore starts with an empty chain — nothing is
carried across invocations, which is exactly what keeps this comparison clear
of the cross-invocation cache the never-read-back rule forbids.

**Free text still wins here as everywhere.** Owner wording beside an edit
becomes the brief and the edit is never resolved. And the note — the owner's
own words — survives an edit they did not restate, disclosed as inherited; an
adopted **claim** does not, because a claim belongs to the set it was composed
over.

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
would make omission silent. Every member's episode disclosure travels in
`gaps`, not just the first one's.

## The end of the sitting: ask what they are writing

The boundary where terrain ends and drafting begins is a **gate the owner
answers**, not a command with placeholders they have to decode. That gate
already ships — draft-article's **intent gate** (`skills/draft-article/SKILL.md`,
"No article type given?", Story 19.13, #758): the closed set of intent labels,
each offered with a reason and a nearest fit, the payload validated and captured
before presenting. **Nothing new is built here. Run that gate.**

**Do not introduce a second gate, a second label set, or a second question
shape.** If you find yourself writing out intent options in this step, you have
reimplemented the gate instead of entering it.

**Supply a recommended intent, grounded in the adopted thesis.** The thesis's
own shape is the evidence — what it reads the selected set AS is what picks
the label. Choose from the gate's own closed set (it is enumerated there and
deliberately not restated here, so one copy exists) and say which part of the
thesis grounds the pick. It stays a **recommendation**: nothing is pre-selected and the full label set is offered, exactly as the gate already
requires.

**Ask for sources with this run's evidence state attached.** A terrain-originated
run knows something a cold run does not: the members' evidence state, from the
brief's own `gaps`. So name the candidate sources you actually know about —
a member whose gap carries a served arc names the material that arc came from —
instead of an unqualified placeholder. The owner may still name any paths, globs or ranges
freely, and **sources remain the owner's input**: the brief directs harvest
emphasis *within* the sources they declare and never widens scope.

**Show what is still theirs to decide, and where (Story 20.130, #1146/#1112).**
The owner's report on the 2026-08-01 sitting was *"I understand that the Brief
was created, but I do not know what happens next"*. Render the map:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/gate-inventory.py --pending \
  --answered <the gate ids this sitting already answered>
```

Relay its lines **as given** — it is derived from the gate registry, so a
decision that moves stages moves here with it, and a hand-written list would be
a conformance copy with no precedence rule. It names the never-asked decision
too, with its reason: an absence that reads as *later* and one that reads as
*never* are different facts, and the owner who expected a gate and saw none can
otherwise only conclude the pipeline decided it silently.

**What the owner never sees at this boundary:** the word "framework", a
bare angle-bracket sources placeholder, the raw pipeline command, or the
absolute state-directory path the brief artifact sits at. Those are stage vocabulary and
machine addresses. Coining an owner-facing term obliges a reader-facing
definition in the same act, and "framework" was never owed one here.

**Then hand off, with `--brief` wired from the artifact — never retyped.** The
brief string comes from the artifact this step already wrote; the owner does not
copy it, and neither do you. Capture the answered gate's payload per the gate's
own contract, then run the **existing** run-mint `--brief` path, unchanged since
Story 18.24 (#505):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <the intent the owner chose> <the sources they named> \
  --brief "$WS/brief.json" \
  --root <host-repo>
```

**`--brief` takes the artifact ITSELF, and that is the whole arc carrier**
(Story 20.91, #1044). `--brief` has accepted a FILE since Story 18.24 (#505),
and the run mint reads a JSON **brief record** — the brief string, plus the selected
members and their journey arcs — by its shape alone. So the string it uses is
the one this step composed, unchanged, and the **arcs travel with it**: the
selected Strands' served arcs cross as declared source material at the recorded
pin, **beside** the host-repo sources and never in place of them. There is no
second argument and no second hand-off. Nothing on the owner's surface changes,
and the extraction one-liner is gone because the pipeline reads the file.

**The sitting does not end on that command. It ends on a GATE (Story 20.136,
#1176).** Staging the run is not the same as running probe, and the ask that
decides which happens is an owner decision like every other one here:

```
draft_gates.probe_entry_gate(<declared source count>, ws=<run ws>)
```

Print what it returns through the selection UI. **Do not compose this ask.**
The observed 2026-08-01 sitting ended with *"Say the word and I'll run
harvest"* — chat prose, answered in free text, with no ask row anywhere, on a
sitting that had put every earlier decision through the carrier. It read as
covered because every declared gate had emitted; the gate that had not been
declared was the one that leaked. The id is `probe-entry`, declared in
`draft_gates.GATES`, and the builder carries the two branches (run probe now
/ stop with the brief kept) with the free-text channel intact.

**Point at the brief; do not restate it.** Whichever branch the owner takes,
the reply names the artifact and its path rather than re-narrating its members,
its thesis or its gaps back at them. A restatement is free composition, which
is the surface nothing downstream can police; a pointer leaves nothing to
compose.

The coupling direction is unchanged by this: the run mint recognises a **format**,
never a producer. It does not detect, name, import or resolve terrain, and it
cannot tell this record from one the owner wrote by hand.

From here the run is **an ordinary brief-carrying run**: the brief maps to
story-element clusters, seeds the argument-plan thesis candidate, and directs
harvest emphasis within the declared sources, exactly as it does for a brief the
owner typed unaided. There is no new entry pipeline.

**The uniformity is of BEHAVIOUR, and that scope is the point.** Downstream
behaviour is identical — the run is byte-identical whichever way the brief
arrived, and **nothing in drafting branches on which producer ran**. The
coupling runs one way only: terrain → the gate → the run mint. Drafting neither
imports, resolves, nor detects terrain state, and inverting that direction
would breach the entry-agnosticism this clause protects.

What is **not** uniform is the **provenance record**: a plan does distinguish
an owner-typed brief from a terrain-adopted one (#1050). Recording where
something came from is not the same as behaving differently because of it — so
the older unscoped phrasing, which said downstream could not tell the two apart
at all, is retired here rather than qualified nearby. Left unscoped it would
make this text contradict what the plan writes.
