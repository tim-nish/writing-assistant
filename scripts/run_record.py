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

EVENT_OPEN = "open"
EVENT_CLOSE = "close"


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


def close_record(block, status, route, verdict=None, skipped=None,
                 exit_code=0, command=None, ts=None):
    """The block-close record (record-formats.md §2), written at block close —
    before the block's `checkpoint.json` write (CAP-4), by the block's own
    command, whatever its exit status.

    Nothing here defaults `status` or `route`: a default would be this module
    guessing the judgment on the emitter's behalf, which is the failure the
    contract exists to remove. Both are positional and required.
    """
    rec = {"ts": ts or _now(), "block": block, "event": EVENT_CLOSE,
           "status": status,
           "route": list(route) if route is not None else [],
           "skipped": [dict(s) for s in (skipped or [])],
           "exit": exit_code}
    if command is not None:
        rec["command"] = command
    if verdict is not None:
        rec["verdict"] = verdict
    return rec


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
         draft_sha256=None, map_sha256=None, status=None):
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
                       ("map_sha256", map_sha256)):
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
    _PENDING.update({
        "ws": ws, "block": block, "command": command,
        "judgment": {"outcome": None, "detail": None, "status": None,
                     "route": [], "skipped": [],
                     "draft_sha256": None, "map_sha256": None}})
    return append(ws, open_record(block, command, inputs=inputs))


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
    return append(p["ws"], close_record(
        block, status, j["route"] or [p["command"]],
        verdict=verdict(outcome, j["draft_sha256"], j["map_sha256"], detail),
        skipped=skipped, exit_code=exit_code, command=p["command"]))


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
    return out


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
    order, opens, closes = [], {}, {}
    for rec in records:
        kind = classify(rec)
        if kind not in (EVENT_OPEN, EVENT_CLOSE):
            continue
        block = rec.get("block")
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
                    "closes": len(closes.get(block, []))})
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


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) == 2 and argv[0] == "validate":
        return _cmd_validate(argv[1])
    sys.stderr.write("usage: run_record.py validate <path|->\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
