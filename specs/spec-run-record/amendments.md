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

> **Amended 2026-08-03 (triage, #1388) — block-mode rerun invalidates by UPSTREAM-BASIS MEMBERSHIP, not by position relative to N's close; the correct helper already existed and the predicate simply did not call it.** Observed re-running the `quality-gate` block of run `20260803T142748-813020`: `--plan` listed three files and omitted the six the block itself produced — `provenance-ledger.tsv`, `provenance-verdicts.txt`, `judge-worklist.txt` and the three `worklist-*.txt`. The surviving ledger held 86 all-pass rows written by the malformed judge round #1374/#1375 were filed for, so the fresh round would have been graded against its own superseded output. That is the exact failure the mode's docstring says it exists to prevent, one level in.
>
> **Root cause, located at triage rather than inferred from the report.** `record_boundary()` snapshots the workspace **at a block's close** (`scripts/run_block.py:203-211@dea2af3`), so block N's own boundary manifest **contains N's outputs by construction**. `downstream_of()` set its kept-set from `boundary_of(ws, block)` — N's own close boundary — and therefore skipped every artifact N produced, on a sha match. The escaped files were not an oversight in a list; they were guaranteed by the choice of basis. `downstream_of()`'s own docstring asserted the opposite (*"Computed against block N's own boundary manifest, so N's outputs … are not in it"*), which is **false against the shipped snapshot point** — the docstring is the defect's clearest statement, not its defence.
>
> **The fix reuses what was already there.** `upstream_boundary(ws, block)` — *"the most recent boundary of a block that PRECEDES `block` in the run's order"* — already existed at `scripts/run_block.py:327-333@dea2af3` and was already called to populate the plan's `upstream.through_block` field, which is why the report truthfully read `fill` while the invalidation set was computed against `quality-gate`. The two halves of one mode were reading two different bases. Nothing new is built: the invalidation predicate is restated over the boundary before N, `checkpoint.json` stays excepted as it already is, and everything absent from or changed against that manifest moves aside.
>
> **`record-formats.md` carried the same split and is corrected in the same change.** Its drift clause was already stated over *"the manifest snapshotted at the boundary before N"* while its invalidation clause read *"everything the workspace gained or changed after N's boundary"* — an ordering predicate. One contract, two bases, with the code mirroring the prose exactly. Both clauses now name the same basis, which is the point: the spec sentence is the defect's origin and not merely its documentation.
>
> **What is NOT changed.** AC-4's preservation semantics stand whole — invalidated is a state and not a shredder, and the widened set still **moves** rather than deletes. The upstream-drift refusal is untouched. The resume-pointer restore is untouched.
>
> **Alternatives declined.** *Enumerating N's own outputs* and adding them to the invalidation set is the individual-prohibition shape: it handles the six observed files and leaves the next artifact written mid-block to escape for the identical reason, and it would leave `record-formats.md:302@dea2af3` still saying something false. *Restoring changed files' content from the boundary* — making the re-run hermetic rather than merely clean — was considered and declined as unbuildable against today's format without first confirming that boundaries store content rather than only hashes; it also overshoots what #1388 reports.
>
> **Family note, and it is uncomfortable.** This is a fifth instance of the class filed as #1395 the same day — a carrier whose declared reach exceeds its delivered reach — and it sits **inside** one of that issue's four members. Here the declaration is a docstring rather than a spec line, which is precisely why no check caught it: nothing asserts that a docstring's claim about a predicate matches the predicate.
>
> **What would overturn this:** a legitimate workflow that hand-places an artifact into the workspace mid-block and expects it to survive a re-run of that block. It would now be moved to `invalidated/<ts>/` — recoverable, but moved. No such workflow is known; if one appears the answer is an explicit carve-out naming it, never a return to the ordering predicate. Delivery: story 20.208.
