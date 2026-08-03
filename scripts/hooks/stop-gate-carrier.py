#!/usr/bin/env python3
"""Stop hook: a gate that was due leaves tool-call evidence, or the turn is
blocked (Story 20.151, #1221).

WHY THIS EXISTS AT THIS LAYER, WHICH IS THE WHOLE POINT.
`specs/spec-writing-assistant/SPEC.md:76` recorded on 2026-07-28 that the
failing layer is "the agent's own composition step, WHICH THIS PRODUCT DOES NOT
OWN", and concluded that the carrier must stop at the composed artifact. The
premise nobody checked was the factual one: no `.claude/settings.json` existed
in this repository, so that conclusion described a harness with no observation
point. It is a file this repository owns and commits. The amendment of
2026-08-02 (#1221/#1222/#1225) bounds the ruling on exactly that ground, and
this file is the carrier it licenses.

Twelve issues (#226 -> #1206) shipped carriers that each bound a layer UPSTREAM
of the one that fails. Every one of them passed while the owner read prose.
This one runs outside the model.

WHAT IT ASSERTS — AN ABSENCE, AND NOTHING ELSE.
For a turn at which a declared gate was due, an `AskUserQuestion` tool-use
event exists in the transcript for that gate. That is it. It does not read
reply prose, does not classify text, and does not judge wording — those are
the payload layer's job (stories 20.152, 20.153) and the relay limit #1176
records still stands. What this removes is the last way to reach the owner
without leaving evidence.

THREE-VALUED, BY OWNER DECISION 2026-08-02.
The harness writes the transcript asynchronously and its docs say the file
"may lag the in-memory conversation". Blocking is expensive — it holds the
owner's turn open — so a read that raced the writer must never block. If the
transcript has not caught up, this reports CANNOT-DETERMINE and lets the turn
end. It fails toward silence, never toward a wrong block.

The cost is stated rather than hidden: coverage is "settled turns", not "all
turns", and the thing to watch is the cannot-determine RATE. A rising rate
means the evidence is being missed, and it is visible in the transcript output
rather than inferred from a suspiciously clean pass rate.

EXIT CODES ARE THE HARNESS'S, NOT OURS. Exit 2 blocks the turn and feeds
stderr back to the model; exit 0 lets it end. Anything this hook cannot do
safely exits 0 — a hook that crashes must not take the session with it.

IT NOW HAS A SUBJECT, WHICH IT DID NOT (Story 20.156, #1245/#1247).
Everything above shipped and could never fire: the subject was resolved from
`WA_RUN_WS` or `payload["cwd_run_ws"]` — an environment variable with no
writer anywhere in this repository and a field the harness does not supply —
so `ws` was always None and every turn returned 0 at the "not a pipeline turn"
branch. Both are DELETED rather than kept as fallbacks: a fallback with no
writer is the defect, not the safety net. The subject is now the pointer the
checkpoint write leaves at `<state-root>/<cwd-key>/active-run.json`, resolved
from the Stop payload's documented `cwd` alone.

A CRASH IS REPORTED AS A CRASH, NEVER AS A VERDICT (#1336).
A real finding and an exception both leave the auditor at a non-zero exit, and
this file read only the exit code — so a `KeyError` in `gate-inventory` reached
the owner three turns running, worded as a confirmed policy breach ("the ask
reached the owner as prose"), pointing the debugger at gate rendering when the
fact was a traceback. The discriminator is that a finding prints its verdict
object BEFORE exiting non-zero and a crash prints none (`audit_outcome`). A
crashed audit now says so, names the exception, records `cannot-determine`
beside a crash signature, and EXITS 0 — an audit that could not run has
determined nothing, and holding the turn open on it is the three-consecutive-
stops loop itself. A repeating crash identifies as repeating rather than
re-presenting as a fresh finding, because a hook that cries the same wolf every
turn trains the owner to skip real findings.

AND IT RECORDS WHAT IT DECIDED, PER TURN. `cannot-determine` was named as the
thing to watch and given no watcher — a rate written to a stream nobody reads.
Every evaluated turn now appends its verdict to the run workspace, so a run
that completes having determined nothing on any turn is a FINDING (a chain
that always fails toward silence is indistinguishable from no hook at all,
and this file spent a full cycle being exactly that).
"""

import datetime
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
INVENTORY = os.path.join(HERE, "..", "gate-inventory.py")

# The per-turn verdict log, in the run workspace it is about.
VERDICT_FILE = "stop-gate-verdicts.jsonl"

CANNOT_DETERMINE = "cannot-determine"


def _budget():
    """The turn budget module, loaded defensively (Story 20.153, #1225).

    The hook MEASURES the budget and never defines it — the rule lives in
    `turn_budget.py` and stands whether or not this hook runs.
    """
    try:
        spec = importlib.util.spec_from_file_location(
            "turn_budget", os.path.join(HERE, "..", "turn_budget.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:
        return None


def _resolver():
    """The path resolver, loaded defensively. D1: no other file composes a
    state path, so the pointer's location is asked of this one."""
    try:
        spec = importlib.util.spec_from_file_location(
            "resolve_paths", os.path.join(HERE, "..", "resolve-paths.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:
        return None


def _fresh(written_at, now=None):
    """Is a pointer stamped `written_at` about THIS sitting?

    STALENESS IS ANSWERED BY THE STAMP, AND ONLY BY IT. The alternative — take
    the newest workspace — is inadmissible for the reason `_run_workspace`
    states below, so a pointer whose stamp does not parse is not-fresh
    (cannot-determine, which here means silence) rather than trusted.

    The boundary is the CALENDAR DAY, which is not a threshold picked to make
    this pass: it is the same rule `draft_resume.predates_sitting` already
    declares for "did this run begin in the current sitting", stated there as
    the coarsest honest reading of a recorded time. A run left open overnight
    must not audit tomorrow's unrelated turns.
    """
    try:
        stamp = datetime.datetime.fromisoformat(str(written_at))
    except (TypeError, ValueError):
        return False
    now = now or datetime.datetime.now(stamp.tzinfo)
    return stamp.date() == now.date()


def _run_workspace(payload):
    """The run workspace this turn belongs to, or None.

    Resolved from the pointer the pipeline's checkpoint write leaves for the
    session's `cwd`, never guessed by scanning for the newest directory:
    picking "the most recent workspace" would silently audit a different run
    than the one that is speaking, and a wrong-run block is indistinguishable
    at the owner's screen from a real one.

    `cwd` is the whole input. It is documented Stop-payload content, which is
    the property the two deleted predecessors lacked — and a resolution that
    depends on nothing else cannot be broken by an invocation path forgetting
    to export something.
    """
    rp = _resolver()
    cwd = payload.get("cwd")
    if rp is None or not cwd:
        return None
    try:
        rec = rp.read_active_run(cwd)
    except Exception:
        return None
    if not rec or not _fresh(rec.get("written_at")):
        return None
    ws = rec.get("ws")
    return ws if ws and os.path.isdir(ws) else None


def _settled_from(stdout):
    """The auditor's `tool_call_settled`, or None.

    The auditor prints its BOUND around the JSON — deliberately, so a reader
    cannot take the verdict without the limit — so this decodes the first JSON
    object in the stream rather than assuming the whole stream is one. A
    stdout this cannot read yields None, which records as cannot-determine.
    """
    text = stdout or ""
    i = text.find("{")
    if i < 0:
        return None
    try:
        obj, _ = json.JSONDecoder().raw_decode(text[i:])
    except ValueError:
        return None
    return obj.get("tool_call_settled") if isinstance(obj, dict) else None


def _audit_json(stdout):
    """The auditor's own JSON verdict, or None when it printed none.

    THIS IS THE CRASH DISCRIMINATOR (#1336). A real finding always prints its
    verdict object before exiting non-zero (`gate-inventory.main` prints the
    JSON, then its BOUND, then returns 1); a crash raises out of `main`, so it
    exits non-zero having printed no JSON at all. Both were read here as
    "returncode != 0", which is how a KeyError came to reach the owner worded
    as a confirmed policy breach.
    """
    text = stdout or ""
    i = text.find("{")
    if i < 0:
        return None
    try:
        obj, _ = json.JSONDecoder().raw_decode(text[i:])
    except ValueError:
        return None
    return obj if isinstance(obj, dict) else None


def audit_outcome(returncode, stdout, stderr):
    """`("crash", signature)` | `("finding", None)` | `(None, None)`.

    The whole crash-vs-verdict decision, in one pure function so it can be
    exercised without a crashing auditor to hand — the alternative was an
    environment override whose only writer would have been the fixture, which
    is the dead-input shape this repository refuses.
    """
    if returncode == 0:
        return None, None
    if _audit_json(stdout) is None:
        return "crash", crash_signature(stderr)
    return "finding", None


def crash_report(signature, prior_repeats):
    """The owner-facing line for a crashed audit.

    Composed here rather than at the call site so the repetition rider and the
    wording are asserted together: the message must never carry the
    missed-gate accusation, and a repeat must say so.
    """
    again = (f" — same crash as the previous turn (x{prior_repeats + 1})"
             if prior_repeats else "")
    return (f"gate audit crashed: {signature}{again} — no verdict this turn. "
            f"Nothing is asserted about gates; fix the auditor, not the gates.")


def crash_signature(stderr):
    """One line identifying WHICH crash this is, for the repetition rider.

    The last non-empty line of a Python traceback is the exception type and
    message, which is stable across turns for a deterministic crash and
    different for a different one — so counting consecutive equal signatures
    counts a repeating crash without ever comparing tracebacks in full.
    """
    lines = [ln.strip() for ln in (stderr or "").splitlines() if ln.strip()]
    if not lines:
        return "no stderr from the audit"
    return lines[-1][:200]


def prior_consecutive_crashes(ws, signature):
    """How many of the immediately preceding recorded turns crashed the same way.

    Read BEFORE this turn's row is appended, so the count the owner sees is
    "this is the Nth in a row" rather than an off-by-one. A different
    signature, or any non-crash turn, ends the streak: a repeating crash is
    the thing worth naming, not a crash-prone run in general.
    """
    n = 0
    for row in reversed(read_verdicts(ws)):
        if row.get("crash") != signature:
            break
        n += 1
    return n


def _record_verdict(ws, payload, subject_found, settled, result, crash=None):
    """Append this turn's verdict to the run workspace (Story 20.156).

    Append-only JSONL: one line per evaluated turn, so the RATE is countable
    afterwards rather than inferred from a pass rate. Never fatal — a hook
    that took the session down over its own bookkeeping would be a worse
    version of the defect it is recording.
    """
    try:
        row = {"at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
               "session_id": payload.get("session_id"),
               "subject-found": subject_found,
               "settled": settled,
               "result": result}
        if crash:
            # Recorded BESIDE `result`, never instead of it: a crashed turn is
            # a cannot-determine turn, so the all-indeterminate run finding
            # keeps firing over it. The signature is what makes repetition
            # countable (#1336).
            row["crash"] = crash
        with open(os.path.join(ws, VERDICT_FILE), "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
    except Exception:
        pass


def read_verdicts(ws):
    """The recorded verdicts for a run, oldest first ([] when none)."""
    rows = []
    try:
        with open(os.path.join(ws, VERDICT_FILE), encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if isinstance(row, dict):
                    rows.append(row)
    except OSError:
        return []
    return rows


def run_verdict_finding(ws):
    """The finding for a COMPLETED run that determined nothing, else None.

    The case this names is precisely today's: a chain whose every input is
    dead evaluates every turn and asserts nothing on any of them, and its
    output is indistinguishable from a clean run. So a completed run whose
    every recorded verdict is `cannot-determine` is reported as a finding — an
    all-indeterminate audit is evidence about the AUDITOR, not about the run.

    A run with no recorded verdicts at all is NOT this finding: that is the
    hook never having run, which is a different defect and is not silently
    folded into this one.
    """
    state = {}
    try:
        with open(os.path.join(ws, "checkpoint.json"), encoding="utf-8") as f:
            state = json.load(f) or {}
    except (OSError, ValueError):
        return None
    if not isinstance(state, dict) or state.get("next_stage") != "done":
        return None
    rows = read_verdicts(ws)
    if not rows or not all(r.get("result") == CANNOT_DETERMINE for r in rows):
        return None
    return (f"finding: run {os.path.basename(ws)} completed with all "
            f"{len(rows)} recorded Stop-hook turn(s) at {CANNOT_DETERMINE} — "
            f"the gate carrier asserted nothing about this entire run, so a "
            f"clean gate record here is unevidenced. Check that the "
            f"transcript path and the run pointer reached the hook.")


def main():
    # `--run-finding <ws>`: the READER of what the hook recorded, for a
    # sitting-opening surface to call. It is a QUERY — it prints the finding
    # when there is one and exits 0 either way, because "this run determined
    # nothing" is something to say at an opening, not a check to fail.
    #
    # WHOSE OPENING CONSUMES IT IS UNRESOLVED (Story 20.156, story question 2,
    # answered cannot-determine at triage and still cannot-determine here): no
    # sitting-opening surface exists in this repository, and the commands that
    # do open sittings (`/triage-gh`, `/spec-sitting`, `/ship-cycle`) live in
    # `claude-toolkit`. The finding is COMPUTED here rather than invented into
    # a surface that does not exist.
    if len(sys.argv) > 1:
        if sys.argv[1] == "--run-finding" and len(sys.argv) == 3:
            note = run_verdict_finding(sys.argv[2])
            if note:
                print(note)
            return 0
        sys.stderr.write(
            "usage: stop-gate-carrier.py            (Stop hook; payload on stdin)\n"
            "       stop-gate-carrier.py --run-finding <ws>\n")
        return 0

    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        # No parseable hook input: assert nothing, block nothing.
        return 0

    ws = _run_workspace(payload)
    if not ws:
        # Not a pipeline turn at all — the overwhelming majority. Silence here
        # is correct: this hook has no subject, which is different from having
        # a subject and finding it clean.
        return 0

    cmd = [sys.executable, INVENTORY, "--audit", "--ws", ws,
           "--reached-from-state"]
    transcript = payload.get("transcript_path")
    if transcript:
        cmd += ["--transcript", transcript]
        marker = payload.get("last_assistant_message")
        if marker:
            # Opaque settledness token only — see gate-inventory.read_tool_calls.
            cmd += ["--settle-marker", marker]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        # The auditor could not run. That is a cannot-determine, not a finding.
        _record_verdict(ws, payload, True, None, CANNOT_DETERMINE)
        return 0

    # WHAT THIS TURN ACTUALLY DETERMINED, recorded before anything is returned.
    # `tool_call_settled` is the auditor's own three-valued answer: None = not
    # asked (no transcript), False = asked and the file had not caught up.
    # Neither is a pass, and neither may be recorded as one.
    settled = _settled_from(proc.stdout)
    # A CRASH IS NOT A VERDICT (#1336). The auditor printing no verdict object
    # while exiting non-zero is an exception, not a finding — and reporting it
    # as one points the debugger at gate rendering when the fact is a
    # traceback. A diagnostic must not require the health of the thing it
    # diagnoses in order to report honestly.
    outcome, signature = audit_outcome(proc.returncode, proc.stdout, proc.stderr)
    crashed = outcome == "crash"
    repeats = prior_consecutive_crashes(ws, signature) if crashed else 0
    if crashed:
        result = CANNOT_DETERMINE
    elif outcome == "finding":
        result = "finding"
    elif settled is True:
        result = "clean"
    else:
        result = CANNOT_DETERMINE
    _record_verdict(ws, payload, True, settled, result, crash=signature)

    # THE VOLUME MEASUREMENT (Story 20.153, #1225), reported and never blocking.
    # `SPEC.md:80` records that this repository cannot constrain the relay
    # layer's WORDING. Volume is not wording — a line count is mechanical — so
    # the budget is measurable here even though the register is not. It is a
    # REPORT: a turn is never blocked for being long, because the cost of a
    # wrong block (holding the owner's turn) exceeds the cost of a long turn.
    tb = _budget()
    if tb is not None and not tb.debug_enabled():
        over, n = tb.over_budget(payload.get("last_assistant_message"))
        if over:
            sys.stderr.write(
                f"note: this turn carried {n} owner-facing lines against a "
                f"budget of {tb.TURN_LINE_BUDGET} outside the gate payload. "
                f"Detail belongs in the run workspace behind one pointer "
                f"line.\n")

    if crashed:
        # SAYS WHAT HAPPENED, AND BLOCKS NOTHING. Exit 0: an audit that could
        # not run has determined nothing, so holding the turn open on it is
        # the three-consecutive-stops loop #1336 reports. The repetition rider
        # is the second half — a hook that cries the same wolf every turn
        # trains the owner to skip real findings.
        sys.stderr.write(crash_report(signature, repeats) + "\n")
        return 0

    if proc.returncode == 0:
        return 0

    # A real finding. stderr goes back to the model as the reason it may not
    # stop, naming the gate so the next turn can present it through the
    # control rather than narrating it again.
    sys.stderr.write(
        "A declared gate was due this turn and no AskUserQuestion tool call "
        "carries it, so the ask reached the owner as prose.\n"
        "Present it through the selection control, quoting its emitted "
        "payload.\n\n" + (proc.stderr or proc.stdout or "").strip() + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
