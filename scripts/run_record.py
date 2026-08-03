#!/usr/bin/env python3
"""The run record: its format, its validator, and the append site the block
commands call (Story 20.180, #1298; SPEC-run-record CAP-2/CAP-3, companion
`specs/spec-run-record/record-formats.md` §1-§2).

WHY THIS IS A MODULE AND NOT MORE OF THE MONOLITH. `scripts/draft-pipeline.py`
sits at 5,374 lines against a ratchet of 5,344 + 1% (`check-skill-budget.sh`),
and the sanctioned remedy for that file is the per-stage command-module split,
which is a spec decision. Absorbing the record's compose/validate/append logic
into it would spend the last of that headroom on work that has its own spec
carrier. So the format lives here, stdlib-only, and the pipeline gains call
sites only.

WHAT THIS MODULE REFUSES TO LET A CALLER EXPRESS. Two shapes, both of which the
2026-08-02 run produced or would have produced:

  * an OCCURRENCE without a JUDGMENT — "the block ran" with nothing about what
    it concluded, over which artifact, by which route (CAP-2); and
  * a PARTIAL run wearing a clean label — `status: "ran"` over a block that
    silently skipped a sub-obligation, or `ran-partially` that never names
    which one (CAP-3).

Both are rejected by `validate()` with a reason of their own, and the reason is
the product: a validator that says "invalid" says nothing a debugger can act on.

THE HASH IS NOT A PARALLEL ONE. `draft_sha256()` DELEGATES to
`scripts/verify-provenance.py` (`:213-241` is the attestation parser it belongs
to) rather than restating `hashlib.sha256(...).hexdigest()`. A record and an
attestation for the same draft therefore agree by construction and not by two
authors having written the same line twice. `over_from_attestation()` builds the
record's `verdict.over` straight out of `parse_attestation`'s own return value,
which is the same joint from the other end.

LEGACY LINES ARE UNKNOWN, NEVER INVALID. Journals written before this contract
carry `{"ts","stage","event"}` (`cmd_run_event`, `draft-pipeline.py:2602-2616`).
`classify()` names them `legacy` and `validate()` returns no reasons for them:
the readers `_read_run_events`/`_cost_proxies` keep parsing exactly what they
parsed before, and a missing new field is an absence of information rather than
a violation (SPEC-run-record constraints).

AN OPEN WITH NO CLOSE IS WELL-FORMED. It means *entered, did not finish* — the
state the motivating run was in when it stopped at the quality gate. Nothing
here repairs it, and `block_states()` reports it as its own state rather than
folding it into absence or into a synthesized failure.

CLI: `run_record.py validate <path|->` validates a journal, one reason per
offending line on stderr, exit 1 if any. Emission is a library call, not a
subcommand — the whole point of the contract is that emission is a side effect
of a block command running, never a step someone remembers to invoke.
"""

import datetime
import json
import os
import re
import sys

# The functional blocks, named from the block<->command table
# (`skills/draft-article/SKILL.md:149-155`). A record naming anything else is
# not attributable to a writer, which is the property `block` exists for.
BLOCKS = ("start", "probe", "interview", "fill", "quality-gate", "verify",
          "complete")

# CAP-3: three distinct states, not a boolean plus a note.
STATUSES = ("ran", "ran-partially", "did-not-run")

# `n/a` is reserved for blocks that decide nothing; which blocks those are is
# fixed here (by the emitting command's contract), never by the writer of a
# given line — record-formats.md §2.
OUTCOMES = ("pass", "fail", "blocked", "degraded", "n/a")

# Blocks that decide NOTHING. Everything else is verdict-producing, so a close
# record from it with no verdict is invalid rather than empty (CAP-2).
NON_VERDICT_BLOCKS = ("start",)

# Blocks that decide OVER A DRAFT. Their verdict must name the draft hash it
# decided over; `probe` and `interview` precede any draft existing, so the
# field is genuinely inapplicable there rather than merely missing.
DRAFT_DECIDING_BLOCKS = ("fill", "quality-gate", "verify", "complete")

HEX64 = re.compile(r"^[0-9a-f]{64}$")

# The block whose close IS the run's close. Its record carries the loop report
# (story 20.189, #1334; record-formats.md §5) — the one place a reader learns
# what every bounded improvement loop of the run cost and whether it converged.
RUN_CLOSING_BLOCK = "complete"

EVENT_OPEN = "open"
EVENT_CLOSE = "close"
# The sub-unit record (story 20.188, #1341; record-formats.md §4). Emitted at
# the boundary the long blocks ALREADY checkpoint — `progress --done <unit>` —
# so the instrument reuses that boundary rather than inventing a second one.
EVENT_UNIT = "unit"

# What a sub-unit's `duration_s` was measured FROM, carried on the record so a
# reader never has to guess which boundary the number spans:
#   `open` — the block's own open record (this is the block's first unit);
#   `unit` — the previous sub-unit record of the same block;
#   `run`  — the journal's last record, because the block has NO open record
#            yet (the fill's mandatory command opens the block at its close).
#            Such a unit is attributable but is NOT inside the block's own
#            open/close span, so the §4 accounting rule is not asserted over it.
SINCE = ("open", "unit", "run")


# --- paths, hashes -----------------------------------------------------------

def run_events_path(ws):
    """The one journal path, unmoved (`_run_events_path`,
    `draft-pipeline.py:2598-2599`). One path, one format, more writers."""
    return os.path.join(ws, "run-events.jsonl")


def _verify_provenance():
    """The attestation module, loaded by path because its filename is hyphenated.

    Returns None when it cannot be loaded — the caller falls back rather than
    failing a run, per the seam's degradation discipline.
    """
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                        "verify-provenance.py")
    if not os.path.isfile(path):
        return None
    try:
        spec = importlib.util.spec_from_file_location("_wa_verify_provenance",
                                                      path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:                                    # pragma: no cover
        return None


def draft_sha256(draft_text):
    """The attestation's hash, not a second one modelled on it.

    Delegates to `verify-provenance.draft_sha256` so the record and the
    `attestation: draft-sha256=<hex64>` header for the same draft cannot drift
    apart. The fallback exists only so a workspace missing that script degrades
    instead of failing a block.
    """
    mod = _verify_provenance()
    if mod is not None and hasattr(mod, "draft_sha256"):
        return mod.draft_sha256(draft_text)
    import hashlib                                       # pragma: no cover
    return hashlib.sha256(draft_text.encode("utf-8")).hexdigest()


def over_from_attestation(verdicts_text, map_sha256=None):
    """Build a close record's `verdict.over` from a verdicts file's own header.

    The join CAP-2 asks for, taken from the side that already exists: whatever
    `parse_attestation` read is what the record carries. Returns None when the
    text carries no attestation header — the caller fails closed on that
    exactly as `verify-provenance` does, rather than recording a null hash as
    though it were a decision.
    """
    mod = _verify_provenance()
    if mod is None or not hasattr(mod, "parse_attestation"):
        return None                                      # pragma: no cover
    draft_hash = mod.parse_attestation(verdicts_text)[0]
    if draft_hash is None:
        return None
    return {"draft_sha256": draft_hash, "map_sha256": map_sha256}


def is_hex64(value):
    return isinstance(value, str) and bool(HEX64.match(value))


def _now():
    return (datetime.datetime.now(datetime.timezone.utc)
            .isoformat(timespec="seconds"))


# --- composition -------------------------------------------------------------

def verdict(outcome, draft_sha256=None, map_sha256=None, detail=""):
    """One close record's judgment: what was decided, over what, in one line."""
    return {"outcome": outcome,
            "over": {"draft_sha256": draft_sha256, "map_sha256": map_sha256},
            "detail": detail}


def open_record(block, command, inputs=None, ts=None):
    """The block-open record (record-formats.md §1), written on entry.

    `command` is the mandatory command that wrote the line, so a record is
    attributable to its writer without a lookup.
    """
    return {"ts": ts or _now(), "block": block, "event": EVENT_OPEN,
            "command": command, "inputs": dict(inputs or {})}


def duration_between(open_ts, close_ts):
    """Elapsed seconds between two record timestamps, or None if either is
    unusable.

    Computed BY THE EMITTING COMMAND from its own open record (story 20.187,
    #1333) — a reader differencing two `ts` values is the reconstruction this
    spec exists to abolish, so the number is written once, at the boundary that
    knows it, and never derived downstream.
    """
    try:
        a = datetime.datetime.fromisoformat(open_ts)
        b = datetime.datetime.fromisoformat(close_ts)
    except (TypeError, ValueError):
        return None
    return round((b - a).total_seconds(), 3)


def close_record(block, status, route, verdict=None, skipped=None,
                 exit_code=0, command=None, ts=None, duration_s=None,
                 iteration=None, loop_report=None):
    """The block-close record (record-formats.md §2), written at block close —
    before the block's `checkpoint.json` write (CAP-4), by the block's own
    command, whatever its exit status.

    Nothing here defaults `status` or `route`: a default would be this module
    guessing the judgment on the emitter's behalf, which is the failure the
    contract exists to remove. Both are positional and required.

    `iteration` and `loop_report` are the bounded improvement loop's history
    (story 20.189, #1334; record-formats.md §5) — composed by `run_loop.py`,
    carried here. Both are OPTIONAL and both are metadata about an artifact
    that lives in the workspace: the record never carries the artifact itself.
    """
    rec = {"ts": ts or _now(), "block": block, "event": EVENT_CLOSE,
           "status": status,
           "route": list(route) if route is not None else [],
           "skipped": [dict(s) for s in (skipped or [])],
           "exit": exit_code}
    if command is not None:
        rec["command"] = command
    if duration_s is not None:
        rec["duration_s"] = duration_s
    if verdict is not None:
        rec["verdict"] = verdict
    if iteration is not None:
        rec["iteration"] = iteration
    if loop_report:
        rec["loop_report"] = loop_report
    return rec


def unit_record(block, unit, duration_s=None, since=None, batch=None,
                command=None, ts=None):
    """One sub-unit record (record-formats.md §4), written at the boundary the
    long block already checkpoints.

    `unit` is the SAME token `progress --done` takes — not a normalisation of
    it — so the checkpoint's `progress.<stage>.done` list and this stream join
    without a translation table.

    `batch` is set only when one `progress` call recorded several units at
    once: the boundary cannot separate them, so the interval is shared evenly
    and the record SAYS SO rather than presenting a share as a measurement.
    """
    rec = {"ts": ts or _now(), "block": block, "event": EVENT_UNIT,
           "unit": unit}
    if duration_s is not None:
        rec["duration_s"] = duration_s
        rec["since"] = since
    if batch is not None and batch > 1:
        rec["batch"] = batch
    if command is not None:
        rec["command"] = command
    return rec


def last_boundary(ws, block):
    """`(ts, since)` — the boundary a sub-unit of `block` is measured from.

    Inside the block's own open/close span that is the block's open record, or
    the latest sub-unit recorded after it. A block with no open record in the
    journal falls back to the journal's LAST record (`since: "run"`): the
    fill's mandatory command opens the block at fill close, so section units
    are recorded while the block is genuinely unopened, and a real elapsed
    interval that names what it spans beats a null. `(None, None)` for an
    empty journal — nothing to measure from, so nothing is written.
    """
    open_ts = None
    since = None
    last_ts = None
    for rec in read_records(ws):
        ts = rec.get("ts")
        if ts:
            last_ts = ts
        if rec.get("block") != block:
            continue
        kind = classify(rec)
        if kind == EVENT_OPEN:
            open_ts, since = ts, "open"
        elif kind == EVENT_CLOSE:
            open_ts, since = None, None
        elif kind == EVENT_UNIT and open_ts is not None:
            open_ts, since = ts, "unit"
    if open_ts is not None:
        return open_ts, since
    return (last_ts, "run") if last_ts else (None, None)


def emit_units(ws, stage, units, command="progress"):
    """Emit one sub-unit record per NEWLY recorded unit (CAP-1 for sub-units).

    Called from `progress`'s one write path with the units that call actually
    added, so a re-recorded unit — the command is idempotent per unit — emits
    nothing a second time. A `stage` that is not a block of the block<->command
    table emits nothing at all: the instrument follows the existing checkpoint
    boundary, it never creates one (story 20.188 AC-3).

    NEVER raises and never fails the caller's own write: emission is a side
    effect of a boundary that has already happened.
    """
    units = [u for u in (units or []) if _nonempty_str(u)]
    if not ws or stage not in BLOCKS or not units:
        return []
    try:
        anchor, since = last_boundary(ws, stage)
        elapsed = duration_between(anchor, _now()) if anchor else None
        share = (round(elapsed / len(units), 3)
                 if elapsed is not None else None)
        out = []
        for unit in units:
            rec = unit_record(stage, unit, duration_s=share, since=since,
                              batch=len(units), command=command)
            append(ws, rec)
            out.append(rec)
        return out
    except Exception as e:                               # pragma: no cover
        sys.stderr.write("run-record: sub-unit emission degraded: %s\n" % e)
        return []


def sub_units(records, block=None):
    """Every sub-unit record in the stream, in order, optionally one block's.

    The reader half of AC-2: after an interrupted block, the units that
    completed are read straight off this list. The one in flight has no record
    and is NEVER synthesized from the gap — an absent unit reads as *not
    recorded done*, which is exactly what the checkpoint boundary means.
    """
    return [r for r in records
            if classify(r) == EVENT_UNIT
            and (block is None or r.get("block") == block)]


def skip(step, why):
    """One named sub-obligation that did not run, and why (CAP-3).

    A `ran-partially` record carrying an unnamed skip is rejected, so this is
    the only shape that makes the partial state expressible at all.
    """
    return {"step": step, "why": why}


# --- per-block emission: the record as a SIDE EFFECT of running (CAP-1) ------
#
# THE SHAPE IS `probe.py record`'s. That command cannot run without writing
# `probe.json`; from here on, no block command can run without writing its own
# open and close records. The dispatcher is the only caller of `emit_block`, so
# there is no second invocation to skip and nothing for an agent to remember —
# which is the whole repair, because the defect being fixed is that emission
# used to be an agent act (SPEC-run-record, Why).
#
# UNCONDITIONAL ON EXIT STATUS. A command that returns non-zero, raises, or
# exits still closes, carrying its own `exit` and a `fail` outcome. A failed
# block is the case the record exists for: the observed run stopped at the
# quality gate and left nothing behind.
#
# WHY MODULE STATE AND NOT A PARAMETER. A command fixes its own judgment where
# it concludes it (`note`), often deep inside its body. Threading a record
# object through every frame would make emission a parameter every caller has
# to remember to pass, which is the same defect one layer down.

# The block<->command table (`skills/draft-article/SKILL.md:149-155`), read as
# the machine mapping it always was: subcommand -> block. `probe` is keyed by
# its own script (`probe.py record`), which passes its block explicitly.
BLOCK_OF_COMMAND = {
    "stage0": "start",
    "interview": "interview",
    "provenance": "fill",
    "quality-gate": "quality-gate",
    "verify": "verify",
    "complete": "complete",
}

# The fill's fan-out legs (`skills/draft-article/stages/fan-out.md`), each
# keyed by the artifact it leaves in the run workspace. The fill's one
# mandatory command is `provenance`, which closes the WHOLE fill block and
# cannot observe the legs running beside it — but their artifacts land in the
# workspace it is closing over, so a leg that left none is a DERIVED skip
# (CAP-3 named, CAP-5 derived) rather than a silence inside a clean `ran`.
FILL_LEGS = (
    ("isolated provenance judging", "provenance-verdicts",
     "no `provenance-verdicts*` artifact in the workspace at fill close — the "
     "judging must have passed before the fill completes (fan-out.md §5)"),
    ("per-claim examine", "examination-pins.txt",
     "no `examination-pins.txt` ledger in the workspace at fill close "
     "(examine.md: a claim must be enumerable to be examined)"),
)

# The judgment the RUNNING command has fixed about itself, between
# `open_block` and `close_block`.
_PENDING = {}


def _load(name):
    """Load a sibling script by path (their filenames are hyphenated).

    Returns None when it cannot be loaded — the caller degrades rather than
    failing a block, per the seam's standing degradation discipline.
    """
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), name)
    if not os.path.isfile(path):
        return None
    try:
        spec = importlib.util.spec_from_file_location(
            "_wa_" + re.sub(r"\W", "_", name), path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:                                    # pragma: no cover
        return None


def workspace_of(args):
    """`(workspace, how it was resolved)` for the running block command.

    `--ws` where the command declares one; else the `WS` the skill exports;
    else the resolver's OWN active-run pointer (`resolve-paths.read_active_run`,
    the Stop hook's subject) — never a scan for the newest workspace, which
    that resolver forbids in the same breath it writes the pointer. A `None`
    workspace means there is no journal to write to, and the block then runs
    unrecorded rather than failing: emission never fails a run.
    """
    ws = getattr(args, "ws", None) or os.environ.get("WS")
    source = "--ws/WS"
    if not ws:
        rp = _load("resolve-paths.py")
        rec = rp.read_active_run() if rp is not None else None
        ws = (rec or {}).get("ws")
        source = "active-run pointer"
    return (ws, source) if ws and os.path.isdir(ws) else (None, source)


def file_sha256(path):
    """The attestation hash of a file, or None for stdin / an unreadable path."""
    if not path or path == "-" or not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            return draft_sha256(fh.read())
    except OSError:                                      # pragma: no cover
        return None


def note(outcome=None, detail=None, route=None, skipped=None,
         draft_sha256=None, map_sha256=None, status=None, iteration=None):
    """The running command fixes what its own close record will say (CAP-2).

    The wrapper guarantees a record EXISTS; only the command knows what it
    concluded, so nothing here is inferred from a return code the command
    could not distinguish. `route` and `skipped` ACCUMULATE (a block gets
    where it got by more than one step); everything else is last-wins. A call
    outside a block is a no-op, so no command is coupled to being wrapped.
    """
    if not _PENDING:
        return
    j = _PENDING["judgment"]
    for key, value in (("outcome", outcome), ("detail", detail),
                       ("status", status), ("draft_sha256", draft_sha256),
                       ("map_sha256", map_sha256), ("iteration", iteration)):
        if value is not None:
            j[key] = value
    if route is not None:
        j["route"].extend([route] if isinstance(route, str) else list(route))
    j["skipped"].extend(list(skipped or []))


def derived_skips(ws, block):
    """Sub-obligations the WORKSPACE says did not happen (CAP-3 over CAP-5).

    Derived from what the workspace holds at close, never from an input flag.
    Only the fill has them today — see `FILL_LEGS`.
    """
    if block != "fill":
        return []
    try:
        present = os.listdir(ws)
    except OSError:                                      # pragma: no cover
        return []
    return [skip(step, why) for step, prefix, why in FILL_LEGS
            if not any(f.startswith(prefix) for f in present)]


def open_block(ws, block, command, inputs=None):
    """Enter a block: write the open record and arm its close."""
    _PENDING.clear()
    rec = open_record(block, command, inputs=inputs)
    _PENDING.update({
        "ws": ws, "block": block, "command": command,
        # The open record's own timestamp, held so the close computes its
        # duration from the boundary it actually entered at (story 20.187).
        "opened_ts": rec["ts"],
        "judgment": {"outcome": None, "detail": None, "status": None,
                     "route": [], "skipped": [], "iteration": None,
                     "draft_sha256": None, "map_sha256": None}})
    return append(ws, rec)


def close_block(exit_code=0):
    """Write the armed block's close record (record-formats.md §2).

    Called by the block's own command immediately BEFORE it writes
    `checkpoint.json` (CAP-4 — see `before_checkpoint`), and by `emit_block`
    as the backstop for a command that returned or raised without getting
    that far. IDEMPOTENT: the second call is a no-op, so the ordering call
    never doubles the record.
    """
    if not _PENDING:
        return None
    p = dict(_PENDING)
    _PENDING.clear()
    j, block = p["judgment"], p["block"]
    skipped = j["skipped"] + derived_skips(p["ws"], block)
    status = j["status"] or ("ran-partially" if skipped else "ran")
    outcome = j["outcome"] or ("pass" if exit_code == 0 else "fail")
    if status == "did-not-run":
        outcome = "n/a"
    detail = j["detail"] or "%s exited %d" % (p["command"], exit_code)
    rec = close_record(
        block, status, j["route"] or [p["command"]],
        verdict=verdict(outcome, j["draft_sha256"], j["map_sha256"], detail),
        skipped=skipped, exit_code=exit_code, command=p["command"],
        iteration=j.get("iteration"),
        # The RUN's close carries the loop report (story 20.189 AC-3): every
        # bounded improvement loop the run ran, how many iterations it took,
        # what each changed, and whether it converged or churned. DERIVED from
        # the journal's own iteration records at the last block's close — a
        # reading of durable records, never a second source of truth.
        loop_report=(loop_report_for(p["ws"])
                     if block == RUN_CLOSING_BLOCK else None))
    # The open ts is normally in hand from `open_block`; a close written by a
    # process that did not open the block (a resumed run) falls back to the
    # journal's own last matching open. Neither path differences timestamps at
    # READ time — both compute here, at the boundary, and write the number.
    opened = p.get("opened_ts") or last_open_ts(p["ws"], block)
    dur = duration_between(opened, rec["ts"]) if opened else None
    if dur is not None:
        rec["duration_s"] = dur
    reason = append(p["ws"], rec)
    _block_mode(p["ws"], rec)   # opt-in stop at this boundary; off = no-op
    return reason


def _block_mode(ws, rec):
    """The development block mode's boundary hook (story 20.190, #1332).

    A NO-OP unless the developer enabled the mode for this workspace, which is
    what keeps the production run byte-identical: the mode writes nothing to
    this journal in either state — it READS this record for the block, its
    duration and its verdict, and everything it stores rides the WORKSPACE,
    exactly where the amendment's carrier split already puts artifacts. That
    is why it adds no record class, which the amendment names as the test of
    whether the split was right.
    """
    try:
        import run_block
        return run_block.after_close(ws, rec)
    except Exception:                                      # pragma: no cover
        return None                     # a control surface never fails a run


_RUN_LOOP = []


def _run_loop():
    """`run_loop.py`, or None. The loop's history is ITS module (story 20.189);
    this module carries the fields and asks it for the shape, so neither half
    restates the other. A missing module degrades to no report.

    Memoised: `validate()` asks per line, and re-execing a module per journal
    line would make the validator's cost quadratic in the journal.
    """
    if not _RUN_LOOP:
        here = os.path.dirname(os.path.realpath(__file__))
        if here not in sys.path:
            sys.path.insert(0, here)
        try:
            import run_loop as mod                         # the ordinary path
        except ImportError:                                # pragma: no cover
            mod = _load("run_loop.py")
        _RUN_LOOP.append(mod)
    return _RUN_LOOP[0]


def loop_report_for(ws):
    """The run's loop report, derived from the journal. `None` on any failure —
    a run never fails because its history could not be summarised."""
    mod = _run_loop()
    if mod is None or not ws:
        return None
    try:
        return mod.loop_report(read_records(ws)) or None
    except Exception:                                      # pragma: no cover
        return None


def last_open_ts(ws, block):
    """The `ts` of the most recent unclosed open record for `block`, or None.

    Used only when the closing process did not open the block (a resumed run):
    the pairing is by block and recency, which is the same pairing
    `validate_lines` asserts over a stream.
    """
    open_ts = None
    for rec in read_records(ws):
        if rec.get("block") != block:
            continue
        if classify(rec) == EVENT_OPEN:
            open_ts = rec.get("ts")
        elif classify(rec) == EVENT_CLOSE:
            open_ts = None
    return open_ts


def before_checkpoint():
    """CAP-4's ordering, in one call at the one checkpoint write path.

    The close record is durable BEFORE `checkpoint.json` is written, so no
    resumable state exists with no record behind it: a kill between the two
    leaves a record with no checkpoint, never the reverse. A no-op when the
    checkpoint is not being written from inside a block — the agent-invoked
    `checkpoint` command, whose block command already closed and exited.
    """
    return close_block(0)


def emit_block(fn, args, block=None, command=None):
    """Run one block command with its records as a side effect (CAP-1)."""
    command = command or getattr(args, "cmd", None)
    block = block or BLOCK_OF_COMMAND.get(getattr(args, "cmd", None))
    ws, ws_source = workspace_of(args)
    if block is None or ws is None:
        return fn(args)
    draft_hash = file_sha256(getattr(args, "draft", None))
    inputs = {"ws_source": ws_source}
    if draft_hash:
        inputs["draft_sha256"] = draft_hash
    for key in ("cycle", "framework", "profile", "slug"):
        if getattr(args, key, None) is not None:
            inputs[key] = getattr(args, key)
    open_block(ws, block, command, inputs=inputs)
    note(draft_sha256=draft_hash,
         map_sha256=file_sha256(getattr(args, "map", None)))
    code = 1
    try:
        code = fn(args) or 0
        return code
    except SystemExit as e:                              # pragma: no cover
        code = e.code if isinstance(e.code, int) else 1
        raise
    finally:
        close_block(code)


def emit_start(ws, command, route, detail, exit_code=0, inputs=None):
    """The `start` block, which MINTS the workspace it records into.

    Its open record cannot precede its own mint checkpoint — there is nowhere
    for the journal to live until `stage0` has resolved `$WS` — so both
    records are written the moment the workspace exists, at the end of the
    block. This is the one structural exception to open-at-entry, and it is
    named here rather than hidden: every block after `start` records on entry.
    """
    if not ws or not os.path.isdir(ws):
        return None
    append(ws, open_record("start", command, inputs=inputs))
    return append(ws, close_record(
        "start", "ran", route, exit_code=exit_code, command=command,
        verdict=verdict("pass" if exit_code == 0 else "fail", detail=detail)))


def emit_stage0(out, framework=None, target=None):
    """`emit_start` for stage0, composing its route and detail from the block's
    own output so the call site stays one line in an already-ratcheted file.
    """
    return emit_start(
        out.get("ws"), "stage0",
        ["config validated", "framework accepted",
         "resumed" if out.get("resumed") else "workspace minted"],
        "run may begin: next_stage=%s" % out.get("next_stage"),
        inputs={"framework": framework, "target": target})


# --- classification and validation -------------------------------------------

def classify(rec):
    """`open` | `close` | `legacy` | `unknown`.

    A line with no `block` but a `stage` is a pre-contract line: legacy, and
    readable. `unknown` is for a line this contract has no opinion about — it
    is not an error either, because the file is append-only and shared.
    """
    if not isinstance(rec, dict):
        return "unknown"
    if "block" not in rec and "stage" in rec:
        return "legacy"
    event = rec.get("event")
    if event == EVENT_OPEN and "block" in rec:
        return EVENT_OPEN
    if event == EVENT_CLOSE and "block" in rec:
        return EVENT_CLOSE
    if event == EVENT_UNIT and "block" in rec:
        return EVENT_UNIT
    return "unknown"


def _nonempty_str(v):
    return isinstance(v, str) and v.strip() != ""


def _validate_open(rec):
    reasons = []
    if rec.get("block") not in BLOCKS:
        reasons.append(
            "open record names block %r, which is not one of the block<->command "
            "table's blocks (%s)" % (rec.get("block"), ", ".join(BLOCKS)))
    if not _nonempty_str(rec.get("command")):
        reasons.append(
            "open record carries no `command` — the record must name the "
            "mandatory command that wrote it, so it is attributable without a "
            "lookup (record-formats.md §1)")
    inputs = rec.get("inputs", {})
    if not isinstance(inputs, dict):
        reasons.append("open record's `inputs` is not an object")
    else:
        ds = inputs.get("draft_sha256")
        if ds is not None and not is_hex64(ds):
            reasons.append(
                "open record's inputs.draft_sha256 is %r, not the attestation's "
                "lowercase hex64 (`draft-sha256=<hex64>`, "
                "verify-provenance.py:213-241)" % (ds,))
    return reasons


def _validate_unit(rec):
    """The sub-unit record's own shape (record-formats.md §4)."""
    reasons = []
    if rec.get("block") not in BLOCKS:
        reasons.append(
            "sub-unit record names block %r, which is not one of the "
            "block<->command table's blocks (%s)"
            % (rec.get("block"), ", ".join(BLOCKS)))
    if not _nonempty_str(rec.get("unit")):
        reasons.append(
            "sub-unit record carries no `unit` id — the id is the SAME token "
            "`progress --done` takes, and without it the record cannot be "
            "joined to the checkpoint's own done list (record-formats.md §4)")
    dur = rec.get("duration_s")
    if dur is not None:
        if not isinstance(dur, (int, float)) or isinstance(dur, bool):
            reasons.append("sub-unit `duration_s` is %r, not a number of seconds"
                           % (dur,))
        elif dur < 0:
            reasons.append("sub-unit `duration_s` is negative (%r)" % (dur,))
        if rec.get("since") not in SINCE:
            reasons.append(
                "sub-unit carries a `duration_s` and `since` is %r — a duration "
                "that does not name the boundary it was measured from is a "
                "number a reader has to reconstruct, which is the "
                "reconstruction this contract abolishes (one of %s)"
                % (rec.get("since"), " | ".join(SINCE)))
    batch = rec.get("batch")
    if batch is not None and (not isinstance(batch, int) or isinstance(batch, bool)
                              or batch < 2):
        reasons.append(
            "sub-unit `batch` is %r — it is set only when ONE recording "
            "boundary covered several units (an integer of 2 or more), and it "
            "declares the duration to be an even share rather than a "
            "measurement" % (batch,))
    return reasons


def _validate_close(rec):
    reasons = []
    block = rec.get("block")
    if block not in BLOCKS:
        reasons.append(
            "close record names block %r, which is not one of the "
            "block<->command table's blocks (%s)" % (block, ", ".join(BLOCKS)))

    status = rec.get("status")
    if status not in STATUSES:
        reasons.append(
            "status is %r — the three states are %s, and they are distinct "
            "states rather than a boolean plus a note (CAP-3)"
            % (status, " / ".join(STATUSES)))

    skipped = rec.get("skipped", [])
    if not isinstance(skipped, list):
        reasons.append("`skipped` is not a list")
        skipped = []
    else:
        for entry in skipped:
            if not (isinstance(entry, dict) and _nonempty_str(entry.get("step"))
                    and _nonempty_str(entry.get("why"))):
                reasons.append(
                    "a `skipped` entry does not name both the sub-obligation "
                    "(`step`) and why it was skipped (`why`) — %r (CAP-3)"
                    % (entry,))

    if status == "ran-partially" and not skipped:
        reasons.append(
            "status is `ran-partially` with an empty or absent `skipped` — a "
            "partial that does not name what it skipped is a `ran` record "
            "wearing a label (CAP-3, record-formats.md §2)")
    if status == "ran" and skipped:
        reasons.append(
            "status is `ran` with a non-empty `skipped` — this is the collapse "
            "of partial into clean that CAP-3 exists to make unrepresentable; "
            "the status is `ran-partially`")

    route = rec.get("route")
    if not (isinstance(route, list) and route
            and all(_nonempty_str(step) for step in route)):
        reasons.append(
            "`route` is empty or absent — how the block got there is the half "
            "of the judgment that survives when the outcome is later disputed "
            "(CAP-2, record-formats.md §2)")

    exit_code = rec.get("exit")
    if exit_code is not None and not isinstance(exit_code, int):
        reasons.append("`exit` is %r, not the command's own integer exit status"
                       % (exit_code,))

    reasons.extend(_validate_verdict(rec, block, status))
    # The bounded improvement loop's history (story 20.189, record-formats.md
    # §5). Delegated whole: the loop module owns that shape, and a validator
    # that restated it would be the second copy the split exists to avoid. A
    # record carrying neither field validates exactly as it did before — this
    # adds history, never a precondition.
    mod = _run_loop()
    if mod is not None:
        reasons.extend(mod.validate_iteration(rec))
        reasons.extend(mod.validate_loop_report(rec))
    return reasons


def _validate_verdict(rec, block, status):
    """The CAP-2 half: a block that produced a verdict must carry it.

    A `did-not-run` block produced no verdict, so nothing is required of it
    beyond the shape — that is the state's whole meaning.
    """
    reasons = []
    ran = status in ("ran", "ran-partially")
    produces_verdict = block in BLOCKS and block not in NON_VERDICT_BLOCKS
    v = rec.get("verdict")

    if v is None:
        if ran and produces_verdict:
            reasons.append(
                "block %r produced a verdict and the record carries none — "
                "\"the block ran\" without \"what it concluded\" is the "
                "occurrence-only record CAP-2 makes invalid, not empty" % (block,))
        return reasons

    if not isinstance(v, dict):
        return ["`verdict` is not an object"]

    outcome = v.get("outcome")
    if outcome not in OUTCOMES:
        reasons.append("verdict.outcome is %r — not one of %s"
                       % (outcome, " | ".join(OUTCOMES)))
    elif outcome == "n/a" and ran and produces_verdict:
        reasons.append(
            "verdict.outcome is `n/a` on block %r, which decides something — "
            "`n/a` is reserved for blocks that decide nothing, and which those "
            "are is fixed by the emitting command (record-formats.md §2)"
            % (block,))

    over = v.get("over", {})
    if not isinstance(over, dict):
        reasons.append("verdict.over is not an object")
        over = {}
    ds = over.get("draft_sha256")
    if ran and block in DRAFT_DECIDING_BLOCKS:
        if ds is None:
            reasons.append(
                "block %r decided over a draft and verdict.over.draft_sha256 is "
                "absent — the record cannot name the artifact it judged, so the "
                "verdict is unattached (CAP-2)" % (block,))
        elif not is_hex64(ds):
            reasons.append(
                "verdict.over.draft_sha256 is %r, not the attestation's "
                "lowercase hex64 — it is the SAME hash as "
                "`attestation: draft-sha256=<hex64>` "
                "(verify-provenance.py:213-241), not a parallel one" % (ds,))
    elif ds is not None and not is_hex64(ds):
        reasons.append("verdict.over.draft_sha256 is %r, not lowercase hex64"
                       % (ds,))
    ms = over.get("map_sha256")
    if ms is not None and not is_hex64(ms):
        reasons.append("verdict.over.map_sha256 is %r, not lowercase hex64"
                       % (ms,))
    return reasons


def validate(rec):
    """Every reason this record is not well-formed, in order; empty means valid.

    Legacy and unknown lines return no reasons: an older line missing the new
    fields is UNKNOWN, never a violation (SPEC-run-record constraints).
    """
    kind = classify(rec)
    if kind == EVENT_OPEN:
        common = _validate_common(rec)
        return common + _validate_open(rec)
    if kind == EVENT_CLOSE:
        common = _validate_common(rec)
        return common + _validate_close(rec)
    if kind == EVENT_UNIT:
        common = _validate_common(rec)
        return common + _validate_unit(rec)
    return []


def _validate_common(rec):
    if not _nonempty_str(rec.get("ts")):
        return ["record carries no `ts` timestamp"]
    return []


def validate_lines(lines):
    """[(lineno, kind, [reasons])] over an iterable of raw journal lines.

    A line that is not JSON is reported as such rather than skipped: the reader
    tolerates it (`_read_run_events` continues past it), but a check that
    silently agreed would be the contract's own blind spot.
    """
    out = []
    for i, raw in enumerate(lines, 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except json.JSONDecodeError as e:
            out.append((i, "unparseable", ["line is not valid JSON: %s" % e]))
            continue
        out.append((i, classify(rec), validate(rec)))
    return _with_pairing_reasons(lines_records(out, lines), out)


def lines_records(out, lines):
    """The parsed records behind `validate_lines`' rows, in the same order."""
    recs = []
    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            recs.append(json.loads(raw))
        except json.JSONDecodeError:
            recs.append(None)
    return recs


def _with_pairing_reasons(recs, rows):
    """Stream-level reasons — the ones a single record cannot carry.

    `duration_s` is the first of them (story 20.187, #1333): a close record
    whose matching OPEN record exists in this stream and which carries no
    duration is invalid, because the emitting command had everything it needed
    to write one. The rule is deliberately conditional on the pairing — an
    open record with no close still means *entered, did not finish*, and a
    close with no open (a stream read from the middle) is not asserted over.
    READERS stay tolerant either way: `read_records` and the pipeline's own
    reader never validate, so a legacy journal is still readable — this is the
    validator, and what it asserts is the contract.
    """
    open_seen = {}
    inside = {}
    for idx, rec in enumerate(recs):
        if not isinstance(rec, dict):
            continue
        block = rec.get("block")
        kind = classify(rec)
        if kind == EVENT_OPEN:
            open_seen[block] = True
            inside[block] = []
        elif kind == EVENT_UNIT:
            # Only units INSIDE the block's own open/close span are accounted
            # against it. A unit recorded while the block has no open record
            # (`since: "run"`) is attributable but spans an interval the block
            # never owned, so asserting over it would manufacture a defect.
            if open_seen.get(block) and isinstance(
                    rec.get("duration_s"), (int, float)):
                inside.setdefault(block, []).append(rec["duration_s"])
        elif kind == EVENT_CLOSE:
            rows[idx][2].extend(_unit_accounting(block, rec,
                                                 inside.pop(block, [])))
            # A loop report is a READING of the stream's own iteration records
            # (story 20.189 AC-3), so one that disagrees with the stream is a
            # reconstruction — the same stream-level shape `duration_s` uses.
            if rec.get("loop_report") is not None:
                mod = _run_loop()
                if mod is not None:
                    rows[idx][2].extend(
                        mod.report_pairing_reasons(recs, rec))
            if open_seen.get(block) and rec.get("duration_s") is None:
                rows[idx][2].append(
                    "close record for block %r has a matching open record and "
                    "no `duration_s` — the elapsed seconds are computed by the "
                    "emitting command from its own open record, never "
                    "differenced by a reader (record-formats.md §2)" % (block,))
            elif rec.get("duration_s") is not None and not isinstance(
                    rec["duration_s"], (int, float)):
                rows[idx][2].append(
                    "`duration_s` is %r, not a number of seconds"
                    % (rec["duration_s"],))
            open_seen[block] = False
    return rows


def _unit_accounting(block, close, durations):
    """The sub-unit accounting rule (story 20.188 AC-4, record-formats.md §4).

    The sub-unit durations recorded inside a block are bounded by the block's
    own `duration_s`. An accounting that exceeds its block is a DEFECT — the
    sub-units are being measured from a boundary outside the block, or the
    block's own duration is wrong — and it is asserted, not written off as
    rounding. The tolerance is only the rounding the emitter itself performs
    (3 decimals, once per record), so it can never absorb a real excess.
    """
    total = round(sum(durations), 6)
    block_dur = close.get("duration_s")
    if not durations or not isinstance(block_dur, (int, float)):
        return []
    if total <= block_dur + 0.001 * max(1, len(durations)):
        return []
    return ["the %d sub-unit records inside block %r sum to %gs, which EXCEEDS "
            "the block's own duration_s of %gs — a sub-unit accounting larger "
            "than the block it sits in is a defect, not a rounding note "
            "(record-formats.md §4)" % (len(durations), block, total, block_dur)]


# --- reading and appending ---------------------------------------------------

def read_records(ws):
    """Every parseable line of the journal, in order. Mirrors
    `_read_run_events`'s tolerance deliberately: same file, same reader
    behaviour, so this module never disagrees with the pipeline about what the
    journal contains."""
    path = run_events_path(ws)
    if not os.path.isfile(path):
        return []
    out = []
    with open(path, encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln:
                continue
            try:
                out.append(json.loads(ln))
            except json.JSONDecodeError:
                continue
    return out


def append(ws, rec):
    """Append one record. NEVER raises, and never blocks the block's own work.

    Returns the degradation reason as a string, or None on success — "emission
    never fails a run" (SPEC-run-record constraints), so a caller logs the
    return value and carries on. Validation is NOT performed here on purpose: a
    malformed record is a defect the validator catches at check time, and a
    write that silently dropped a record would destroy the one signal the
    journal exists to carry.
    """
    try:
        with open(run_events_path(ws), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec) + "\n")
        return None
    except OSError as e:
        reason = "run-record: could not append to %s: %s" % (
            run_events_path(ws), e)
        sys.stderr.write(reason + "\n")
        return reason


def block_states(records):
    """Per block, in order of first appearance: what the journal says happened.

    States: the close record's own `ran` / `ran-partially` / `did-not-run`, or
    `entered-not-finished` for an open with no close. That last one is a
    FINDING, not a gap to repair — it is exactly the state the run that stopped
    at the quality gate was in, and reading it as absence is what made a
    three-line journal indistinguishable from a complete account.
    """
    order, opens, closes, units = [], {}, {}, {}
    for rec in records:
        kind = classify(rec)
        if kind not in (EVENT_OPEN, EVENT_CLOSE, EVENT_UNIT):
            continue
        block = rec.get("block")
        if kind == EVENT_UNIT:
            # A sub-unit does not by itself make a block appear in this list:
            # the states below are states of the OPEN/CLOSE pair, and a block
            # known only by its units has entered nothing yet.
            units.setdefault(block, []).append(rec.get("unit"))
            continue
        if block not in order:
            order.append(block)
        if kind == EVENT_OPEN:
            opens.setdefault(block, []).append(rec)
        else:
            closes.setdefault(block, []).append(rec)
    out = []
    for block in order:
        last_close = closes.get(block, [])[-1:] or [None]
        close = last_close[0]
        if len(opens.get(block, [])) > len(closes.get(block, [])):
            state = "entered-not-finished"
        elif close is not None:
            state = close.get("status")
        else:
            state = "closed-without-open"
        out.append({"block": block, "state": state, "close": close,
                    "opens": len(opens.get(block, [])),
                    "closes": len(closes.get(block, [])),
                    # The units this block recorded done. On an
                    # `entered-not-finished` block these are exactly what
                    # survived the interruption; the unit in flight is absent
                    # because it was never recorded, and absence is read as
                    # *not done*, never repaired into a synthetic entry.
                    "units": units.get(block, [])})
    return out


# --- CLI ---------------------------------------------------------------------

def _cmd_validate(path):
    text = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    results = validate_lines(text.splitlines())
    bad = [(n, k, rs) for n, k, rs in results if rs]
    counts = {}
    for _, kind, _rs in results:
        counts[kind] = counts.get(kind, 0) + 1
    if not bad:
        print(json.dumps({"stage": "run-record-validate", "result": "PASS",
                          "lines": len(results), "kinds": counts}, indent=2))
        return 0
    sys.stderr.write("run-record: FAIL\n")
    for lineno, kind, reasons in bad:
        for reason in reasons:
            sys.stderr.write("  line %d (%s): %s\n" % (lineno, kind, reason))
    return 1


def cmd_run_event(args):
    """Append one run-journal event (Story 19.8, #742), NARROWED to the events
    no block command can observe from inside itself — an agent-side retry, a
    subagent spawn (SPEC-run-record, Story 20.181). A block's own start and end
    are emitted by the block's own command at block close, and are no longer
    anyone's to remember. Deterministic append through the one append site.

    Lives here rather than in `draft-pipeline.py` because it is journal code and
    this is the journal's module — the sanctioned remedy for that file's ratchet
    is moving code into the module it already has, never raising the ratchet.
    """
    rec = {"ts": _now(), "stage": args.stage, "event": args.event}
    if args.note:
        rec["note"] = args.note
    append(args.ws, rec)
    print(json.dumps({"stage": "run-event", "recorded": rec}))
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) == 2 and argv[0] == "validate":
        return _cmd_validate(argv[1])
    sys.stderr.write("usage: run_record.py validate <path|->\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())


# --- CAP-5: reasons derived from the workspace, never read off a flag --------

POLICY_SURFACE_NAMES = ("policy-surface.txt", "policy-surface.filtered.txt")


def policy_surface_read(ws):
    """True when the run's workspace HOLDS evidence the policy surface was read.

    A zero-byte artifact is not a read: `policy-surface.filtered.txt` can
    legitimately be empty, and an empty file proves nothing about consumption.
    """
    if not ws:
        return False
    return any(os.path.isfile(os.path.join(ws, n))
               and os.path.getsize(os.path.join(ws, n)) > 0
               for n in POLICY_SURFACE_NAMES)


def consulted_reason(explicit, ws=None, fallback_path=None):
    """The `consulted: none (<reason>)` reason, in THREE states (#1289).

    An explicit degradation reason is the reader's own evidence, so it outranks
    the artifact test. Otherwise a policy-surface artifact in the workspace
    proves the source was configured AND read — the empty seed map is then an
    EDITORIAL fact ("no seeds authored"), not a configuration one. Only its
    absence licenses `policy_source unset`, which the run this repairs recorded
    beside a 57,885-byte surface.

    `fallback_path` covers a missing `--ws`: the journal's own input sits IN the
    run workspace, so its directory is the same evidence, and a forgotten flag
    must not restore the false record.
    """
    if explicit:
        return explicit
    if not ws and fallback_path not in (None, "-"):
        ws = os.path.dirname(os.path.abspath(fallback_path))
    return ("policy surface read; no seeds authored" if policy_surface_read(ws)
            else "policy_source unset")


def cost_proxies(ws):
    """Workspace-derivable cost proxies (#742). Output-token totals live in
    harness transcripts this run cannot see, so the block is expressed over
    what the workspace records: wall time, retries, judge rounds, subagents.
    Substrate honesty: each proxy names its basis, and an absent basis reads
    as absent, never as zero-cost."""
    events = read_records(ws)
    ts = []
    for e in events:
        try:
            ts.append(datetime.datetime.fromisoformat(e["ts"]))
        except (KeyError, ValueError):
            pass
    elapsed_min = round((max(ts) - min(ts)).total_seconds() / 60) if len(ts) >= 2 else None
    retries = sum(1 for e in events if e.get("event") == "retry")
    # A gate close record IS a judge round, observed rather than remembered
    # (20.181) — so the fallback stops being what a live run reports.
    judge_rounds = sum(1 for e in events if e.get("event") == "judge-round"
                       or (e.get("event") == "close"
                           and e.get("block") == "quality-gate"))
    subagents = sum(1 for e in events if e.get("event") == "subagent")
    jr_basis = "run-events.jsonl (judge-round events / quality-gate records)"
    if judge_rounds == 0:
        # Fallback basis: the judge artifact files the run wrote.
        judge_rounds = len([f for f in os.listdir(ws) if f.startswith(
            ("provenance-verdicts", "rubric-verdicts"))]) if os.path.isdir(ws) else 0
        jr_basis = "verdict artifact files (no judging recorded in the journal)"
    return {"elapsed_minutes": elapsed_min, "stage_retries": retries,
            "judge_rounds": judge_rounds, "subagents": subagents,
            "judge_rounds_basis": jr_basis,
            "events_recorded": len(events),
            "basis": "run-events.jsonl" + ("" if events else " (absent — proxies limited to judge artifacts)")}
