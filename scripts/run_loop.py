#!/usr/bin/env python3
"""The bounded improvement loop's history: per-iteration artifacts, the
iteration's delta, and the loop report the run's close carries (Story 20.189,
#1334; SPEC-run-record amendments.md, 2026-08-03, clause (c) and the
loop-contract paragraphs; companion `specs/spec-run-record/record-formats.md`
§5).

WHAT A BOUNDED IMPROVEMENT LOOP IS, AND WHY NOTHING HERE ENUMERATES ONE.
**Any repeated act that regenerates an artifact against a verdict** is one —
whatever it is called and wherever it lives. The contract attaches to that
PROPERTY, so a loop written tomorrow is covered on the day it is written and
nothing in this module, its validator half, or the record format names a loop.
`loop` is an opaque id chosen by the caller; an unrecognised one is a loop this
module has not met yet, never an invalid one. The quality gate's revision cycle
is merely the first consumer (`skills/draft-article/stages/gate.md`), and if it
were the only shape this module could express, the contract would be that
gate's history rather than the loop contract.

THE CARRIER SPLIT IS THE WHOLE POINT (AC-5). A 40-minute draft snapshot is not
a judgment, and `run-events.jsonl` is a machine-read journal sized for
judgments. So the artifact rides the WORKSPACE — content-addressed under
`<ws>/loop/<loop>/<sha256>` — and the RECORD carries only the hash, the delta,
and (from the close record it rides on) the verdict. `iteration_record_fields`
refuses to compose a record carrying artifact TEXT at all, so the split cannot
be violated by a caller who means well.

WHAT THIS DOES NOT CHANGE. The two-cycle bound, the delta re-grade, and the
ledger carry are what make a loop converge; none of them is a history
mechanism, and none of them is touched here (amendments.md, 2026-08-03: "What
is deliberately NOT changed"). This module adds HISTORY to a loop that already
terminates — never a third cycle. It reads the journal and writes files beside
it; it never re-runs, re-grades, or re-orders anything.

WHAT SURVIVES AN OVERWRITE. The revision cycle still overwrites the working
artifact — the standing rule at `skills/draft-article/stages/gate.md` is amended
FOR LOOPS ONLY, and only in that the superseded version stays addressable. A
loop that preserved nothing left its failing locations and verdicts and nothing
else, which is why a 40-minute run that produced a poor draft cost another full
run to correct.
"""

import datetime
import difflib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import run_record  # noqa: E402  (the iteration rides the block's own close)

# Per-iteration artifacts live HERE, under the run workspace — never in the
# journal (amendments.md 2026-08-03, clause (c)).
LOOP_DIR = "loop"

# The loop report's three outcomes. `in-flight` is the loop equivalent of the
# open-with-no-close state the contract already refuses to repair: an iteration
# that opened and never closed is reported as such, never folded into a
# churn verdict it did not earn.
OUTCOMES = ("converged", "churned", "in-flight")

# Keys a caller might reach for to smuggle the artifact into the record. The
# refusal is by NAME and by SIZE (below), because the carrier split is not a
# style preference — it is what keeps the journal parseable.
CONTENT_KEYS = ("content", "text", "artifact", "artifact_text", "body", "draft")

# The longest string any iteration field may carry. A delta is a summary; a
# summary this long is a payload wearing a summary's label.
MAX_FIELD_CHARS = 500

_SECTION = re.compile(r"^#{1,6}\s+(.*\S)\s*$")


# --- the workspace half: the artifact, addressed by hash ---------------------

def loop_dir(ws, loop):
    """`<ws>/loop/<loop>` — where one loop's superseded artifacts live."""
    return os.path.join(ws, LOOP_DIR, re.sub(r"[^A-Za-z0-9._-]", "-", loop))


def artifact_path(ws, loop, sha256, ext=".md"):
    return os.path.join(loop_dir(ws, loop), sha256 + ext)


def preserve(ws, loop, text, ext=".md"):
    """Write `text` under its own hash and return `(sha256, path)`.

    CONTENT-ADDRESSED, so preserving the same artifact twice is a no-op and an
    iteration that changed nothing cannot masquerade as a new snapshot. The
    hash is `run_record.draft_sha256` — the attestation's hash, not a parallel
    one — so a preserved artifact and the verdict that graded it name the same
    string by construction.

    Returns `(sha256, None)` when the file could not be written: preservation
    degrades exactly as emission does, and never fails the loop it observes.
    """
    sha = run_record.draft_sha256(text)
    if not ws or not os.path.isdir(ws):
        return sha, None
    path = artifact_path(ws, loop, sha, ext)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if not os.path.isfile(path):
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
        return sha, path
    except OSError as e:                                   # pragma: no cover
        sys.stderr.write("run-loop: could not preserve iteration artifact: %s\n" % e)
        return sha, None


def read_preserved(ws, loop, sha256, ext=".md"):
    """The preserved artifact's text, or None — the read half of AC-2.

    This is what "remains addressable by hash from the run workspace" means
    operationally: a later reader holding only the record's hash can get the
    bytes back without the loop having been re-run.
    """
    path = artifact_path(ws, loop, sha256, ext)
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


# --- the record half: the delta -----------------------------------------------

def _sections(text):
    return [m.group(1) for m in (_SECTION.match(ln) for ln in text.splitlines())
            if m]


def delta(before, after, from_sha256=None):
    """What one iteration CHANGED, as a summary a record can carry.

    Never the diff itself: a diff is the artifact again, and the artifact has
    its own carrier. `basis` names what the summary was computed over, so a
    reader is never left guessing whether an empty delta means "nothing
    changed" or "nothing to compare against" — the two states the first
    iteration and a no-op iteration would otherwise collapse into.
    """
    if before is None:
        return {"from": from_sha256,
                "basis": ("first iteration of this loop — no predecessor "
                          "artifact to compare against"),
                "changed": None}
    added = removed = 0
    for ln in difflib.ndiff(before.splitlines(), after.splitlines()):
        if ln.startswith("+ "):
            added += 1
        elif ln.startswith("- "):
            removed += 1
    before_secs, after_secs = _sections(before), _sections(after)
    touched = sorted(set(before_secs) ^ set(after_secs))
    return {"from": from_sha256,
            "basis": "line diff against the preserved predecessor artifact",
            "changed": bool(added or removed),
            "lines_added": added, "lines_removed": removed,
            "sections_changed": touched[:20]}


def iteration_record_fields(loop, n, artifact_sha256, delta_summary):
    """The `iteration` object a close record carries (record-formats.md §5).

    REFUSES the artifact. A caller handing it content under any name, or an
    over-long string under any name, gets a `ValueError` here rather than a
    journal line no reader was sized for — the carrier split enforced where the
    record is composed, not only where it is validated.
    """
    for key in CONTENT_KEYS:
        if key in (delta_summary or {}):
            raise ValueError(
                "iteration delta carries %r — per-iteration ARTIFACTS live in "
                "the run workspace and are addressed by hash from the record; "
                "the journal carries the judgment (amendments.md 2026-08-03, "
                "clause (c))" % (key,))
    for key, value in (delta_summary or {}).items():
        if isinstance(value, str) and len(value) > MAX_FIELD_CHARS:
            raise ValueError(
                "iteration delta field %r is %d characters — a delta is a "
                "summary, and a summary that long is the artifact in the "
                "journal by another route" % (key, len(value)))
    return {"loop": loop, "n": n, "artifact_sha256": artifact_sha256,
            "delta": dict(delta_summary or {})}


def iterations(records, loop=None):
    """Every iteration carried by the stream's close records, in order.

    The iteration rides the block's own CLOSE record — the record that already
    carries the verdict the iteration was graded against — so there is no
    fourth record kind and no second place to look.
    """
    out = []
    for rec in records:
        it = rec.get("iteration") if isinstance(rec, dict) else None
        if not isinstance(it, dict):
            continue
        if loop is not None and it.get("loop") != loop:
            continue
        if run_record.classify(rec) != run_record.EVENT_CLOSE:
            continue
        out.append((rec, it))
    return out


def record_iteration(ws, loop, n, artifact_text, ext=".md"):
    """The ONE call a loop's consumer makes, at the point it grades.

    Preserves the artifact being graded, computes the delta against the
    previous iteration's preserved artifact, and arms the running block's close
    record with both (`run_record.note`). The verdict is already the close
    record's own, so the iteration is a graded regeneration by construction
    rather than by a caller remembering to attach one.

    NEVER raises and never fails the loop it observes — history is a side
    effect of an iteration that has already happened.
    """
    if not ws or not os.path.isdir(ws):
        # No workspace means no journal to record into AND nowhere to preserve
        # to. The loop runs unrecorded rather than failing — the same shape
        # `run_record.workspace_of` states for the block record itself.
        return None
    try:
        sha, _path = preserve(ws, loop, artifact_text, ext)
        prev = iterations(run_record.read_records(ws), loop)
        prev_sha = prev[-1][1].get("artifact_sha256") if prev else None
        # A predecessor whose hash EQUALS this one is read back all the same:
        # the delta then reports `changed: false`, which is the no-op iteration
        # stated rather than inferred from a missing comparison.
        before = read_preserved(ws, loop, prev_sha, ext) if prev_sha else None
        fields = iteration_record_fields(loop, n, sha,
                                         delta(before, artifact_text, prev_sha))
        run_record.note(iteration=fields)
        return fields
    except Exception as e:                                 # pragma: no cover
        sys.stderr.write("run-loop: iteration history degraded: %s\n" % e)
        return None


# --- the loop report the run's close carries (AC-3) ---------------------------

def loop_report(records):
    """One entry per loop the run ran: how many iterations, what each changed,
    and whether the loop CONVERGED or CHURNED.

    Derived from the journal at the run's close — it is a reading of records
    that are already durable, never a second source of truth. A loop whose last
    iteration passed converged; anything else churned, and the report NAMES the
    churn shape rather than leaving "churned" as an unexplained label. An
    iteration whose block never closed is `in-flight`: the same
    entered-did-not-finish state the contract refuses to repair elsewhere.
    """
    by_loop, order = {}, []
    for rec, it in iterations(records):
        loop = it.get("loop")
        if loop not in by_loop:
            by_loop[loop] = []
            order.append(loop)
        by_loop[loop].append((rec, it))
    report = []
    for loop in order:
        entries = by_loop[loop]
        changes, seen = [], {}
        revisits = []
        for rec, it in entries:
            v = rec.get("verdict") or {}
            sha = it.get("artifact_sha256")
            n = it.get("n")
            if sha in seen:
                revisits.append((seen[sha], n))
            elif sha is not None:
                seen[sha] = n
            changes.append({"n": n, "artifact_sha256": sha,
                            "delta": it.get("delta", {}),
                            "outcome": v.get("outcome"),
                            "block": rec.get("block")})
        last = changes[-1]
        why = None
        if last["outcome"] == "pass":
            outcome = "converged"
        elif last["outcome"] is None:
            outcome, why = "in-flight", (
                "the last iteration's block carries no verdict outcome — it "
                "entered and did not finish, and that is not repaired into a "
                "churn verdict it did not earn")
        else:
            outcome = "churned"
            if revisits:
                why = ("iteration %s re-graded an artifact already graded at "
                       "iteration %s — the loop returned to a version it had "
                       "left" % (revisits[-1][1], revisits[-1][0]))
            elif last["delta"].get("changed") is False:
                why = ("the last iteration re-graded an artifact identical to "
                       "its predecessor — a cycle was spent changing nothing")
            else:
                why = ("the loop terminated on a %r verdict: the bound was "
                       "reached before the artifact passed"
                       % (last["outcome"],))
        entry = {"loop": loop, "iterations": len(changes), "changes": changes,
                 "outcome": outcome}
        if why:
            entry["why"] = why
        report.append(entry)
    return report


# --- validation (the shape the journal's validator asserts, §5) ---------------

def validate_iteration(rec):
    """Every reason this close record's `iteration` is not well-formed."""
    it = rec.get("iteration")
    if it is None:
        return []
    if not isinstance(it, dict):
        return ["`iteration` is not an object"]
    reasons = []
    if not (isinstance(it.get("loop"), str) and it["loop"].strip()):
        reasons.append(
            "iteration carries no `loop` id — the contract binds by PROPERTY "
            "(any repeated act that regenerates an artifact against a verdict), "
            "and the id is what makes a given loop's history joinable "
            "(record-formats.md §5)")
    n = it.get("n")
    if not isinstance(n, int) or isinstance(n, bool) or n < 1:
        reasons.append("iteration `n` is %r, not the 1-based iteration number"
                       % (n,))
    sha = it.get("artifact_sha256")
    if not run_record.is_hex64(sha):
        reasons.append(
            "iteration `artifact_sha256` is %r, not the attestation's lowercase "
            "hex64 — the hash IS the address of the preserved artifact under "
            "`<ws>/loop/<loop>/`, so a record that cannot name it has lost the "
            "artifact the iteration graded (AC-2)" % (sha,))
    d = it.get("delta")
    if not isinstance(d, dict):
        reasons.append("iteration carries no `delta` object — an iteration "
                       "record without its delta is an occurrence record "
                       "(CAP-2 one level down)")
        d = {}
    elif not (isinstance(d.get("basis"), str) and d["basis"].strip()):
        reasons.append(
            "iteration delta names no `basis` — a delta whose basis a reader "
            "has to guess cannot distinguish 'nothing changed' from 'nothing "
            "to compare against' (record-formats.md §5)")
    if isinstance(n, int) and n >= 2 and not d.get("from"):
        reasons.append(
            "iteration %r is not the first of its loop and its delta names no "
            "`from` predecessor hash — a later iteration that cannot name what "
            "it superseded is a first iteration wearing a label" % (n,))
    for key in CONTENT_KEYS:
        if key in it or key in d:
            reasons.append(
                "iteration carries %r — per-iteration ARTIFACTS live in the run "
                "workspace and NEVER in run-events.jsonl; the record carries "
                "the hash (amendments.md 2026-08-03, clause (c))" % (key,))
    for key, value in list(it.items()) + list(d.items()):
        if isinstance(value, str) and len(value) > MAX_FIELD_CHARS:
            reasons.append(
                "iteration field %r is %d characters — the journal carries the "
                "judgment, not the payload" % (key, len(value)))
    ran = rec.get("status") in ("ran", "ran-partially")
    v = rec.get("verdict")
    if ran and not isinstance(v, dict):
        reasons.append(
            "the record carries an `iteration` and no `verdict` — a bounded "
            "improvement loop regenerates an artifact AGAINST A VERDICT, so an "
            "iteration with no verdict is not an iteration of one (AC-2)")
    return reasons


def validate_loop_report(rec):
    """Every reason this close record's `loop_report` is not well-formed."""
    report = rec.get("loop_report")
    if report is None:
        return []
    if not isinstance(report, list):
        return ["`loop_report` is not a list"]
    reasons = []
    for entry in report:
        if not isinstance(entry, dict):
            reasons.append("a `loop_report` entry is not an object: %r" % (entry,))
            continue
        if not (isinstance(entry.get("loop"), str) and entry["loop"].strip()):
            reasons.append("a `loop_report` entry names no `loop`: %r" % (entry,))
        changes = entry.get("changes")
        if not isinstance(changes, list) or not changes:
            reasons.append(
                "loop %r reports no `changes` — the report's obligation is what "
                "EACH iteration changed, and a count without them is the "
                "occurrence-only shape again (AC-3)" % (entry.get("loop"),))
            changes = []
        if entry.get("iterations") != len(changes):
            reasons.append(
                "loop %r reports %r iterations and carries %d change entries — "
                "a report that disagrees with itself is worse than no report"
                % (entry.get("loop"), entry.get("iterations"), len(changes)))
        if entry.get("outcome") not in OUTCOMES:
            reasons.append(
                "loop %r reports outcome %r — a terminated loop CONVERGED or "
                "CHURNED (one of %s), and the distinction is the report's "
                "reason for existing (AC-3)"
                % (entry.get("loop"), entry.get("outcome"), " | ".join(OUTCOMES)))
        if entry.get("outcome") == "churned" and not entry.get("why"):
            reasons.append(
                "loop %r is reported `churned` with no `why` — an unexplained "
                "churn label tells the next run nothing it can act on"
                % (entry.get("loop"),))
    return reasons


def report_pairing_reasons(records, report_rec):
    """The stream-level half: the report must agree with the stream it summarises.

    A loop report is a READING of iteration records that are already durable.
    One that claims more or fewer iterations than the stream holds is a
    reconstruction, which is the failure this whole contract exists to abolish
    — so it is asserted at the stream level, where a single record cannot see
    it (the same shape story 20.187's `duration_s` pairing pass uses).
    """
    report = report_rec.get("loop_report")
    if not isinstance(report, list):
        return []
    counts = {}
    for _rec, it in iterations(records):
        counts[it.get("loop")] = counts.get(it.get("loop"), 0) + 1
    reasons = []
    for entry in report:
        if not isinstance(entry, dict) or "loop" not in entry:
            continue
        seen = counts.get(entry["loop"], 0)
        if entry.get("iterations") != seen:
            reasons.append(
                "the loop report claims %r iterations of loop %r and the stream "
                "holds %d iteration record(s) — the report is DERIVED from the "
                "journal at the run's close, never composed beside it "
                "(record-formats.md §5)"
                % (entry.get("iterations"), entry["loop"], seen))
    return reasons


def _cmd_report(ws):
    print(json.dumps({"stage": "run-loop-report", "ws": ws,
                      "at": datetime.datetime.now(datetime.timezone.utc)
                      .isoformat(timespec="seconds"),
                      "loops": loop_report(run_record.read_records(ws))},
                     indent=2))
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) == 2 and argv[0] == "report":
        return _cmd_report(argv[1])
    sys.stderr.write("usage: run_loop.py report <ws>\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
