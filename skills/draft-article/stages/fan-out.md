<!-- stages/fan-out.md — draft-article stage companion (Story 20.164, #1248/#1259).
     Loaded from the fill whenever more than one machine-paced unit of it
     is runnable at once. Not a pipeline stage of its own: this file carries the
     SCHEDULING of fill work that already exists — it introduces no step, no
     gate, and no new artifact class. It lives beside stage3.md rather than
     inside it because stage3.md is at its packaging ratchet, and because
     scheduling is a separable concern from what each unit does. -->

## Fan-out — the fill's machine-paced work runs concurrently

Wall time in the fill should track the **slowest** independent unit, not their
sum. Four kinds of work inside the fill are independent, and this file states
how each is dispatched and joined. **Nothing here changes what any unit does**
— the examine contract is [`examine.md`](examine.md)'s, the judging contract is
[`stage3.md`](stage3.md)'s, the visual-set contract is [`stage3.md`](stage3.md)'s
`### Visual-set plan`, and the gate is [`gate.md`](gate.md)'s. Only the
*schedule* is here.

**Out of scope by ratification, stated so nothing is claimed for it.**
Owner-paced gates are out of scope — their duration is owner attention and no
parallelism buys it back — and probe is out of scope at its ≤5s ceiling.

---

### 1. Enumerate the claims once the plan exists

Once the **argument plan and the section intents exist** (the fill's opening
sub-step), the claims that need repository grounding are **already stated** —
each section intent names its content obligation and the evidence type behind
it. Enumerate exactly those claims, up front, and give each an **id**:

```
$WS/examination-worklist.tsv     # one line per claim, in claim order
<claim-id>\t<the concrete claim, one sentence>\t<the section intent it serves>
```

The id is lowercase `[a-z0-9-]`, unique in the file, and stable for the run —
it becomes `--claim-id`, the examination record's filename
(`$WS/examinations/<claim-id>.json`), and the join's `--order`. Ids are what
made concurrency safe at all: without them the record name was the claim
slugged and truncated, so two long claims sharing a prefix overwrote each other
(#1248, story 20.162).

### 2. THE TRIGGER IS UNCHANGED — this is the load-bearing constraint

**Every read is still triggered by a stated claim that exists BEFORE the read.**
Only the scheduling changes. The enumeration is a list of claims the plan
**already asserts**; it is never widened to *claims we might need*, *claims a
section like this usually needs*, or *anchors worth having on hand*. That
widening is a stockpile — it is harvest returning under a new name, and it is
refused by the owner's ratified reading-pattern ruling (2026-08-02, #1248).

The mechanical tell, checkable from the record alone: **every id in the
worklist resolves to a section intent, and every examination record's claim is
a sentence the draft goes on to assert.** An examination whose claim you cannot
point at in the plan is one you should not have run. If enumerating feels like
it is *generating* claims rather than *reading them off the plan*, stop — the
plan is under-specified, and the repair is the plan, not a wider read.

**Claims that emerge mid-fill stay inline.** A claim you discover while writing
section 4 gets one ordinary examination at that moment, exactly as today — no
flags, no worklist entry, no batching, and above all **no deferral of the
writing until a second fan-out round**. The fan-out is an optimisation over
claims that were already knowable; it is not a phase, and there is no rule that
a claim must be enumerable to be examined.

### 3. Dispatch the examinations concurrently, join once

Each examination is a separate `examine.py` process. They share nothing: three
distinct claims read the same repository read-only and write only their own
record. Dispatch them **concurrently** — background processes in one shell, or
one tool call per claim issued in a single batch — each carrying its id, its
index, and `--defer-ledger`:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/examine.py --root <host-repo> --ws "$WS" \
  --claim "<the claim>" --claim-id <id> --claim-index <n> --defer-ledger \
  [--scope "$WS/brief.json"] [--member <strand-index>] [--anchor …]
```

`--defer-ledger` suppresses the per-examination ledger write. **Derive the
ledger once, at the join**, in worklist order:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/examine.py --ws "$WS" --derive-ledger \
  --order "$(cut -f1 "$WS/examination-worklist.tsv" | paste -sd,)"
```

The ledger is **derived, never appended** (#1248, story 20.162), so
`$WS/examination-pins.txt` is **byte-identical** whether the examinations ran
one after another or at once — that identity, not absence-of-crash, is the
acceptance. A single examination needs neither flag and derives the ledger
itself.

**Results are consumed as sections are written.** Do not wait for the whole
fan-out before writing the first section: a section whose claims' records have
landed can be written while the rest are still running. The per-section
progress boundary (`draft-pipeline.py progress --ws "$WS" --stage fill --done
<section-slug>`) is unchanged, and so is its rule — a section is recorded only
after both its prose and its provenance lines land.

**Coverage is per examination, and the fan-out does not merge it.** Each
record's `searched`/`skipped` split stands on its own; an unreachable source in
one examination is *cannot-determine* for that claim only, never an absence
claim for the run ([`examine.md`](examine.md) §Coverage is reported, never
implied). A failed dispatch is a **missing record**, and a missing record is not
an empty result: re-run that one examination, never fill the gap from another
claim's material.

### 4. The provenance judge shards

The narration/derived/sourced worklist that `verify-provenance --list-*`
emits is a flat list of positions. Split it into **K shards** and spawn **one
isolated judge subagent per shard** with the harness Task tool — each as
isolated from the drafting context as today's single judge is (NFR13): it sees
only its shard's sentences and the pins they cite, never the drafting
rationale, the interview, or your reasons for each classification.

**Each shard returns ONE ATTESTED FILE — never a concatenation.** This is
story 20.163's emission contract, and it is the only part of the judging that
the fan-out changes. Instruct each shard verbatim to open its own file with:

```
attestation: draft-sha256=<hex64>      # the SAME hash, echoed from the hand-off
graded: <only the positions in THIS shard's hand-off>
```

then its failure verdicts, or nothing when it found no violation. Collect the
shards as **repeated flags**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/verify-provenance.py \
  --map "$WS/provenance-map.txt" --draft <draft> \
  --fact-sheet "$WS/examination-pins.txt" \
  --judge-findings "$WS/provenance-verdicts-1.txt" \
  --judge-findings "$WS/provenance-verdicts-2.txt"
```

Coverage is checked over the **union** of the shards' `graded:` sets, so the
shards must **partition** the worklist — an unassigned position is an ungraded
position and fails closed (exit 3), exactly as before. **Any hash disagreement
fails the whole gate**: a shard attesting to a different draft is a stale shard,
and stale is "not judged", never "judged clean". **Never `cat` the shards
together** — two attestation headers inside one file is refused by name, because
a concatenation is precisely the shape the attestation exists to close.

Everything else about the judge is unchanged: the anchored hand-off and the
echo check (#304), `--list-sourced` attribution grading (#672), the delta
re-grade's `--prior-verdicts` (itself repeatable when the prior cycle was
sharded), and **every revision cycle re-spawns every shard** — after any edit
the draft hash moves and no shard's attestation survives it.

**Sharding is optional and K is a judgment.** One shard is the shipped
single-file case and stays valid. Shard when the worklist is large enough that
one judge's pass dominates the gate's wall time; do not shard a ten-position
worklist into five subagents, where spawn cost exceeds the work.

### 5. The visual-set work runs beside the judging

The **visual-set plan and its proposals** depend on the draft and the argument
plan. The **provenance judging** depends on neither — it reads the draft, the
map, and the pins. So the two are independent, and they run **concurrently**:
start the judge shards and carry on with the visual-set plan rather than
blocking on the verdicts.

They **join at the quality gate**, which is where both are already required:
approved visuals are inserted into the draft the gate reads, and the judging
must have PASSED before the fill completes. The join rule is therefore the
gate's own precondition, unchanged — see [`gate.md`](gate.md).

**The owner-paced half of the visual set does not speed up.** The plan's
ratification and each proposal's two steps are owner decisions; what runs beside
the judging is the machine-paced part — composing the plan, validating it
(`validate-visual-set.py`), and writing the visual source into `$WS/visuals/`.
Nothing here reorders a gate, batches two owner questions into one, or presents
a visual before the validator accepts it.

### 6. Report the win honestly

Record the fan-out in the run journal so the completion summary's cost block has
a basis (`draft-pipeline.py run-event --ws "$WS" --stage fill --event subagent
--note "<what was dispatched>"`).

**A timing claim names what it measured, and what it did not.** The fan-out
touches **machine-paced units of the fill only**. Never report — or imply — an
improvement in:

- **owner-paced gates** — the structure choice, the visual-set ratification,
  each visual proposal, the interview. Their duration is owner attention;
  concurrency buys none of it back, and this story does not touch them.
- **model composition time** — writing the argument plan, the sections, and the
  provenance map. That is the same work in the same context, whatever else runs
  beside it.
- **probe**, which is out of scope at its ≤5s ceiling.

A report that quotes end-to-end wall clock without that split is a claim about
gates and composition this change never earned. State the measured units, name
the excluded ones, and let the total stand as a total.
