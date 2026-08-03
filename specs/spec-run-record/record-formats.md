# Run-record formats (companion to SPEC-run-record)

The one artifact this contract governs — `<ws>/run-events.jsonl`, at the path
`_run_events_path` already resolves (`scripts/draft-pipeline.py:2593`). The
field set is the contract; concrete syntax is normative, because the only
declared reader is a machine (SPEC-run-record constraints, D2).

Three record kinds share the file, discriminated by `event` — the block's open
(§1), the block's close (§2), and the sub-unit records a long block emits
between them (§4). Lines written before this contract
(`{"ts","stage","event"[,"note"]}`, `cmd_run_event`,
`scripts/draft-pipeline.py:2597-2611`) are **legacy** and remain readable: a
consumer treats a missing new field as unknown, never as a violation.

## 1. Block-open record

Written by the block's mandatory command on entry (CAP-1, CAP-4).

```json
{
  "ts": "2026-08-02T18:57:10+00:00",
  "block": "probe | interview | fill | quality-gate | verify | complete | start",
  "event": "open",
  "command": "probe.py record",
  "inputs": {"draft_sha256": "<hex64>|null", "cycle": 1}
}
```

`block` is the functional block, named from the block↔command table
(`skills/draft-article/SKILL.md:149-155`); `command` is the mandatory command
that wrote the line, so a record is attributable to its writer without a
lookup. `inputs` carries only what the command already holds at entry.

## 2. Block-close record

Written by the same command at block close, before the block's
`checkpoint.json` write (CAP-4).

```json
{
  "ts": "2026-08-02T19:41:02+00:00",
  "block": "quality-gate",
  "event": "close",
  "status": "ran | ran-partially | did-not-run",
  "verdict": {
    "outcome": "pass | fail | blocked | degraded | n/a",
    "over": {"draft_sha256": "<hex64>", "map_sha256": "<hex64>|null"},
    "detail": "one line naming what was decided"
  },
  "route": ["the branch taken", "the fallback applied", "the degradation"],
  "skipped": [{"step": "per-section evidence-type check", "why": "…"}],
  "duration_s": 812.4,
  "exit": 1
}
```

**Validation (CAP-2, CAP-3).**

- `status` outside the three values → reject. The three are distinct states, not
  a boolean plus a note.
- `status: "ran-partially"` with an empty or absent `skipped` → reject: a
  partial that does not name what it skipped is a `ran` record wearing a label.
- `skipped` non-empty with `status: "ran"` → reject (the collapse CAP-3 exists
  to make unrepresentable).
- A block that produced a verdict, with `verdict` absent or
  `verdict.outcome: "n/a"` → reject. `"n/a"` is reserved for blocks that decide
  nothing; which blocks those are is fixed by the emitting command, not by the
  writer of a given line.
- `verdict.over.draft_sha256` absent where the block decided over a draft →
  reject. The field conforms to the provenance attestation's
  `draft-sha256=<hex64>` (`scripts/verify-provenance.py:213-241`); it is the
  same hash, not a parallel one.
- `route` empty → reject: "how it got there" is the half of the judgment that
  survives when the outcome is later disputed.
- `exit` is the command's own exit status. A non-zero exit still emits
  (CAP-1) — a failed block is the case the record exists for.
- `duration_s` is the block's elapsed seconds, **computed by the emitting
  command from its own open record** — never differenced by a reader, which is
  the reconstruction this contract exists to abolish. A close record whose
  matching open record exists in the same journal and which carries no
  `duration_s` → reject (story 20.187, #1333). The rule is conditional on the
  pairing: an open with no close still means *entered, did not finish*, and a
  close read without its open is not asserted over. Readers stay tolerant
  either way — `read_records` never validates, so a journal written before this
  field is still readable; what rejects is the validator.

An **open with no matching close** is well-formed and means *entered, did not
finish*. It is never repaired by a later writer and never read as absence.

## 3. Reason derivation (CAP-5)

Where a close record states why something did not happen, the value is computed
from the workspace at close, never from an input flag. The governing instance is
the interview block's `consulted:` line (contract:
`skills/draft-article/stages/stage2.md:584-591`; composed at
`scripts/draft-pipeline.py:2842-2848`), whose three states are:

| state | workspace evidence | recorded reason |
|---|---|---|
| no source configured | no policy-surface artifact in `$WS` | `none (policy_source unset)` |
| source read, zero seeds survived | a policy-surface artifact exists in `$WS` **and** the seed→question map is empty | `none (policy surface read; no seeds authored)` |
| source configured, unreachable | the reader's own degradation reason, carried explicitly (`--policy-note`, `scripts/draft-pipeline.py:5141`) | `none (policy_source unavailable: <reason>)` |

The third row is authoritative where present — an explicit degradation reason is
evidence, not a flag, and outranks the artifact test. The second row is the
state run `20260802T185710-622820` had and could not express; the first row is
what it reported instead.

Wording is illustrative; the **discrimination** is normative. A run whose
workspace holds a policy surface may never record the first row.

## 4. Sub-unit record

Written inside a **long block**, at the boundary that block already
checkpoints — `draft-pipeline.py progress --ws "$WS" --stage <stage> --done
<unit>`, the sub-stage progress recording that is already declared to be the
durability boundary (`skills/draft-article/stages/stage0.md:546-563@5b5dcba`).
The instrument **follows** that boundary and never creates one: a block that
records no sub-stage progress emits no sub-unit records, which is why the probe
— atomic at `probe.py record` — stays silent here (amendments.md, 2026-08-03,
clause (b)).

```json
{
  "ts": "2026-08-02T19:11:38+00:00",
  "block": "fill",
  "event": "unit",
  "unit": "why-the-seam-exists",
  "duration_s": 214.7,
  "since": "unit",
  "batch": 2,
  "command": "progress"
}
```

- `unit` is **the same token `progress --done` takes**, unnormalised, so the
  checkpoint's `progress.<stage>.done` list and this stream join without a
  translation table. A record without it is rejected.
- `duration_s` is the elapsed seconds since the previous boundary, computed by
  the emitting command — the same discipline §2 states, one level down.
- `since` names **which** boundary that was: `open` (the block's own open
  record — this is its first unit), `unit` (the previous sub-unit of this
  block), or `run` (the journal's last record, because the block has no open
  record yet — the fill's mandatory command opens the block at fill close, so
  section units are genuinely recorded outside the span). A `duration_s` with
  no `since` is rejected: a duration whose span a reader has to reconstruct is
  the reconstruction this contract abolishes.
- `batch` appears only when one `progress` call recorded **several** units. The
  boundary cannot separate them, so the interval is shared evenly and the
  record says so — a share presented as a measurement would be the same
  invention the contract refuses elsewhere.
- The record kind is emitted **once per unit, at the unit's own recording**.
  `progress` is idempotent per unit, and a re-recorded unit adds nothing, so it
  emits nothing.

**The accounting rule (stream level).** The sub-unit records lying **between a
block's open and its close** sum to no more than that close's own `duration_s`.
A sub-unit accounting larger than the block it sits in is a **defect** — the
units are being measured from a boundary outside the block, or the block's own
duration is wrong — and the validator says so; it is never written off as
rounding. The only slack allowed is the emitter's own 3-decimal rounding, once
per record. Units recorded with `since: "run"`, outside any open span, are
attributable but are **not** asserted over — the same conditional-on-pairing
shape §2's `duration_s` rule uses.

**An interrupted block reads off this stream directly.** The units that
completed are the records present; the unit in flight has none, because the
recording *is* the boundary and a half-written unit is never marked done. That
absence reads as *not done* and is never repaired into a synthetic entry
(`block_states`' `units`, `sub_units`).
