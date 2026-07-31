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
  written.

**Re-opening is a first-class move, and this artifact is the one thing the
terrain surface reads back:**

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/topic-map-directions.py brief-open \
  --at "$WS/brief.json" [--state inspected|adopted]
```

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
hand-off below is byte-for-byte the same string it always was — **nothing
downstream can tell that terrain wrote an artifact.**

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
angle — survives an edit they did not restate, disclosed as inherited; an
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
