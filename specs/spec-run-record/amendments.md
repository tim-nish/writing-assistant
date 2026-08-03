# SPEC-run-record — ratified amendments, 2026-08-03 onward

Companion to `SPEC.md` (its ratification block already names this file): the
dated, ratified amendment blockquotes of this spec. **New amendments append
here, newest-last** — `SPEC.md` carries the pointer, never the blocks.

> **Amended 2026-08-03 (triage, #1332 / #1333 / #1334) — development
> instrumentation binds to the BLOCK, and it splits by carrier: time rides the
> record, artifacts ride the workspace, and the block mode consumes both
> without introducing a record class.** The three issues were triaged as one
> coupled decision because each of them, taken alone, fixes the unit
> differently: #1333 wants per-block duration, #1334 wants per-iteration
> artifacts, #1332 wants a re-entry point. A unit fixed three times is three
> units.
>
> **What binds, and where.** (a) **`duration_s` on the close record.** Each
> block's close record carries the elapsed seconds computed by the emitting
> command from its own open record — not by a reader differencing two `ts`
> values, which is the reconstruction this spec exists to abolish. A close
> record whose matching open record exists and whose `duration_s` is absent is
> **invalid**, the same clause shape CAP-2 already applies to `verdict`
> (`record-formats.md:52-56@21ddd82`); legacy records stay readable under the standing
> missing-field-is-unknown rule (`record-formats.md:9-11@21ddd82`). (b) **Sub-unit
> records inside long blocks**, emitted at the boundaries the long blocks
> already checkpoint (`progress --done <unit>`) — so the instrument reuses the
> existing boundary rather than inventing a second one, and minutes 2 through
> 38 of a fill stop being unobservable. (c) **Per-iteration artifacts of a
> bounded improvement loop live in the run workspace**, never in
> `run-events.jsonl`: the loop's record carries its delta and its verdict, and
> the artifact it graded is addressed by hash from there.
>
> **Why the split rather than one carrier.** A duration is a *judgment about
> the block* and CAP-2 already owns exactly that class — "the record carries the
> JUDGMENT, not the occurrence" (`SPEC.md:84-90@21ddd82`). A 40-minute draft snapshot is
> not a judgment; putting it in the event stream would make a machine-read
> journal carry payloads it was never sized for, and the format-change lesson
> then applies at its worst — the population that gains the field is the
> population whose parse changes. The declined alternative is recorded because
> it was genuinely available: extend the record for all three, one unit and one
> validator. It loses on that same lesson, not on effort.
>
> **The loop contract binds by PROPERTY, never by enumeration.** Any repeated
> act that regenerates an artifact against a verdict is a bounded improvement
> loop, whatever it is called and wherever it lives; the contract attaches to
> that property so a loop added tomorrow is covered on the day it is written.
> This **amends the standing overwrite** at
> `skills/draft-article/stages/gate.md:151@21ddd82` ("every cycle here is an
> overwrite") for loops only: the cycle still overwrites the working artifact,
> and it now leaves the superseded version addressable. What is deliberately
> NOT changed: the two-cycle bound, the delta re-grade, and the ledger carry —
> all three are what make the loop converge, and none of them is a history
> mechanism.
>
> **The block mode adds no record class (#1332).** Stopping at block
> boundaries and re-running a single block against preserved upstream state is
> a **control surface over machinery that already ships** — per-block
> checkpoints, automatic resume, and (after this amendment) per-block records
> with durations and per-iteration artifacts. It is opt-in; the continuous
> no-stop run stays the default and is byte-identical. A block mode that
> needed a new record class would be evidence the split above was wrong.
>
> **What would overturn this amendment:** production runs proving unable to
> pay the sub-unit emission cost — if per-section records measurably slow the
> fill, (b) narrows to the development mode and (a) stands alone, which is the
> sidecar alternative arriving through the front door rather than being
> guessed at now.
>
> Delivery: stories 20.187 (duration + validator), 20.188 (sub-unit timing),
> 20.189 (the loop contract), 20.190 (the block mode control surface).
