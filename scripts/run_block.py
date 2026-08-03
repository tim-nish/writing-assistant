#!/usr/bin/env python3
"""The development BLOCK MODE: stop at a block boundary, re-run one block
against preserved upstream state (Story 20.190, #1332; SPEC-run-record
amendments.md, 2026-08-03, "The block mode adds no record class").

WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT. It is a CONTROL SURFACE over
machinery that already ships — per-block checkpoints with automatic resume
(`skills/draft-article/stages/stage0.md`), the block<->command table
(`skills/draft-article/SKILL.md`), per-block close records carrying
`duration_s` (story 20.187), and the workspace carrier the loop's history
already uses (story 20.189). It adds no pipeline structure, changes nothing
any block DOES, and its whole reason to exist is that a 30-minute run whose
only development loop is "change something upstream, re-run everything,
re-validate the final artifact" is a black box.

IT ADDS NO RECORD CLASS (AC-5), AND THAT IS A LOAD-BEARING PROPERTY. A mode
that needed one would be evidence the amendment's carrier split was wrong. So
it introduces no `event` value, no record field, and no line in
`run-events.jsonl` at all: it READS the journal's own open/close records for
the block, its duration and its verdict, and it WRITES to the run workspace —
which is exactly where clause (c) already puts per-iteration artifacts. Time
rides the record; artifacts and mode state ride the workspace; this consumes
both.

OFF IS OFF (AC-1). The hook `run_record.close_block` calls returns before
doing anything when the mode is not enabled — no file is created, no line is
written, no directory is minted, and the journal a run leaves is the journal
it left before this module existed. The mode is enabled per workspace
(`<ws>/block-mode/state.json`, written by `enable`) or per process
(`WA_BLOCK_MODE=1`), never by default.

THE BOUNDARY SNAPSHOT IS OBSERVED, NEVER ENUMERATED. What block N produced is
not read off a table of block->artifact names — such a table is wrong the day
a block gains an output. It is the DIFFERENCE between the workspace manifest
at block N's close and the manifest at the previous boundary. The same
snapshot carries the `checkpoint.json` content of that boundary, which is what
makes a single-block re-run possible without a rewind rule of its own: restore
the checkpoint block N was entered from and the pipeline's EXISTING resume
re-enters exactly block N.

WHY A RE-RUN INVALIDATES WHAT COMES AFTER (AC-4). A downstream artifact built
on an upstream that has since been superseded is the failure this mode must
not manufacture — a developer who re-runs the fill and then reads yesterday's
verify verdict has been told something false by a tool that was supposed to
make the run legible. So everything the workspace gained or changed after
block N's boundary is MOVED to `<ws>/block-mode/invalidated/<ts>/`, named in
the report with the block that produced it, and preserved rather than deleted:
invalidated is a state, not a shredder.
"""

import datetime
import hashlib
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import run_record  # noqa: E402  (the boundary IS the close record's own)

# Everything this mode writes lives under one directory of the run workspace,
# so the manifest can exclude exactly one path and a `rm -rf` of that path
# leaves an ordinary continuous run behind.
MODE_DIR = "block-mode"
STATE_FILE = "state.json"
STOP_FILE = "stop.json"
INVALID_DIR = "invalidated"
BOUNDARY_PREFIX = "boundary-"

# The per-process switch, for the developer who does not want to mint state in
# a workspace first. Any of these values turns it on; anything else, including
# absence, leaves it off.
ENV = "WA_BLOCK_MODE"
ENV_ON = ("1", "true", "yes", "on")

# The checkpoint is the resume pointer, not an artifact of the block that
# happened to be running: it is RESTORED on a re-run rather than invalidated.
CHECKPOINT = "checkpoint.json"


def mode_dir(ws):
    return os.path.join(ws, MODE_DIR)


def _read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def _write_json(path, obj):
    """Atomic write — an interrupted snapshot must never be resumable from."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)
    return path


# --- the switch (AC-1) -------------------------------------------------------

def enabled(ws=None):
    """True only when the developer asked for it — per process or per workspace.

    Every other entry point in this module is gated on this, and the gate is
    checked BEFORE anything is created: an off run's workspace never acquires
    a `block-mode/` directory, which is what makes AC-1 assertable by looking
    at the workspace rather than by trusting a code path.
    """
    if os.environ.get(ENV, "").strip().lower() in ENV_ON:
        return True
    if not ws:
        return False
    return bool((_read_json(os.path.join(mode_dir(ws), STATE_FILE)) or {})
                .get("enabled"))


def enable(ws):
    _write_json(os.path.join(mode_dir(ws), STATE_FILE),
                {"enabled": True, "since": run_record._now()})
    return True


def disable(ws):
    """Turn the mode off, leaving every boundary snapshot in place — the
    history of a development session is not the switch's to discard."""
    path = os.path.join(mode_dir(ws), STATE_FILE)
    if os.path.isfile(path):
        _write_json(path, {"enabled": False, "since": run_record._now()})
    return not enabled(ws)


# --- the workspace manifest: observed, never enumerated ----------------------

def _sha256(path):
    """The file's bytes, hashed. NOT `run_record.draft_sha256` on purpose:
    that is the provenance attestation's hash of a DRAFT's text, and a
    workspace manifest covers artifacts of every kind, including ones no
    attestation ever names. Borrowing it here would claim a join that does not
    hold."""
    h = hashlib.sha256()
    try:
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
    except OSError:                                        # pragma: no cover
        return None
    return h.hexdigest()


def manifest(ws):
    """`{relative path: sha256}` for every ARTIFACT in the run workspace.

    Two exclusions, each for its own reason. This mode's own directory, so a
    snapshot never contains its predecessors and the series stays linear in
    the workspace rather than quadratic. And the JOURNAL — `run-events.jsonl`
    is the record carrier, not an artifact of any block: it is append-only and
    grows at every boundary by construction, so comparing it would report
    drift on every run and the one signal this manifest exists to carry would
    be permanently drowned. What the journal says is read from the journal,
    through `run_record`.
    """
    out = {}
    journal = os.path.basename(run_record.run_events_path(ws))
    for base, dirs, files in os.walk(ws):
        if os.path.relpath(base, ws).split(os.sep)[0] == MODE_DIR:
            dirs[:] = []
            continue
        for fn in files:
            rel = os.path.relpath(os.path.join(base, fn), ws)
            if rel == journal:
                continue
            sha = _sha256(os.path.join(ws, rel))
            if sha is not None:
                out[rel] = sha
    return out


# --- the boundary snapshot ---------------------------------------------------

def boundaries(ws):
    """Every recorded boundary of this workspace, in the order they closed."""
    d = mode_dir(ws)
    try:
        names = sorted(f for f in os.listdir(d)
                       if f.startswith(BOUNDARY_PREFIX) and f.endswith(".json"))
    except OSError:
        return []
    out = [_read_json(os.path.join(d, n)) for n in names]
    return sorted([b for b in out if isinstance(b, dict)],
                  key=lambda b: b.get("n", 0))


def _boundary_path(ws, n, block):
    safe = "".join(c if c.isalnum() or c in "._-" else "-" for c in str(block))
    return os.path.join(mode_dir(ws), "%s%03d-%s.json" % (BOUNDARY_PREFIX, n, safe))


def record_boundary(ws, close_rec):
    """Snapshot the workspace at a block's close, and report the boundary.

    The report's three facts — the block, its duration, its verdict — are read
    off the close record that has just been appended (AC-2). Nothing is
    recomputed and nothing is stored twice: the record is the authority for
    the judgment, and this snapshot is the authority for the workspace state
    that judgment was reached over.
    """
    n = len(boundaries(ws)) + 1
    block = close_rec.get("block")
    snap = {"n": n, "block": block, "ts": close_rec.get("ts"),
            "duration_s": close_rec.get("duration_s"),
            "status": close_rec.get("status"),
            "verdict": close_rec.get("verdict"),
            "manifest": manifest(ws),
            # The resume pointer AS IT STOOD when this block closed — i.e. the
            # state the NEXT block would be entered from. Restoring the
            # PREVIOUS boundary's copy is what re-enters this block.
            "checkpoint": _read_json(os.path.join(ws, CHECKPOINT))}
    _write_json(_boundary_path(ws, n, block), snap)
    return snap


def next_block(block):
    """The block the continuous run would enter next, or None at the end."""
    try:
        i = run_record.BLOCKS.index(block)
    except ValueError:
        return None
    return run_record.BLOCKS[i + 1] if i + 1 < len(run_record.BLOCKS) else None


def stop_notice(ws, snap):
    """What the run stopped at, in the terms a developer stops FOR (AC-2)."""
    v = snap.get("verdict") or {}
    nxt = next_block(snap.get("block"))
    return {"stopped_at": snap.get("block"), "n": snap.get("n"),
            "at": snap.get("ts"),
            "duration_s": snap.get("duration_s"),
            "status": snap.get("status"),
            "verdict": {"outcome": v.get("outcome"), "detail": v.get("detail")},
            "next_block": nxt,
            "not_entered": ("block mode is on: %r is NOT entered until you "
                            "say so" % (nxt,)) if nxt else
                           "this was the run's terminal block",
            "rerun": "python3 scripts/run_block.py rerun %s %s"
                     % (ws, snap.get("block"))}


def _format_notice(notice):
    dur = notice.get("duration_s")
    return ("block mode: STOPPED at block %r after %s — %s, verdict %s (%s). "
            "%s. Re-run this block alone with: %s\n"
            % (notice["stopped_at"],
               "%.1fs" % dur if isinstance(dur, (int, float)) else "unknown",
               notice.get("status"),
               (notice.get("verdict") or {}).get("outcome"),
               (notice.get("verdict") or {}).get("detail"),
               notice.get("not_entered"), notice.get("rerun")))


def after_close(ws, close_rec):
    """THE HOOK, called from `run_record.close_block` once the close record is
    durable. A no-op returning None when the mode is off (AC-1).

    Never raises and never fails the block it observes: a development control
    surface that can break a production run is not opt-in in any sense that
    matters.
    """
    try:
        if not ws or not enabled(ws) or not os.path.isdir(ws):
            return None
        if run_record.classify(close_rec) != run_record.EVENT_CLOSE:
            return None
        snap = record_boundary(ws, close_rec)
        notice = stop_notice(ws, snap)
        _write_json(os.path.join(mode_dir(ws), STOP_FILE), notice)
        sys.stderr.write(_format_notice(notice))
        return notice
    except Exception as e:                                 # pragma: no cover
        sys.stderr.write("run-block: block mode degraded: %s\n" % e)
        return None


# --- re-running one block (AC-3, AC-4) ---------------------------------------

def boundary_of(ws, block):
    """The most recent recorded boundary of `block`, or None."""
    matches = [b for b in boundaries(ws) if b.get("block") == block]
    return matches[-1] if matches else None


def _pos(block):
    """Where a block sits in the run's own order (`run_record.BLOCKS`).

    Ordering by block POSITION, not by boundary recency, is what makes the
    mode survive its own use: once block N has been re-run, the newest
    boundary in the workspace is N's second one and the boundary physically
    before it is a DOWNSTREAM block's from the first pass. A recency rule
    would then call that downstream boundary "upstream" and report drift on
    every artifact the re-run correctly invalidated.
    """
    try:
        return run_record.BLOCKS.index(block)
    except ValueError:
        return -1


def upstream_boundary(ws, block):
    """The most recent boundary of a block that PRECEDES `block` in the run's
    order — the preserved state of blocks 1..N-1, which a re-run of N consumes
    and never regenerates."""
    p = _pos(block)
    prior = [b for b in boundaries(ws) if _pos(b.get("block")) < p]
    return prior[-1] if prior else None


def upstream_drift(ws, block):
    """Every reason the preserved upstream is NOT what block N consumed.

    A re-run against a CHANGED upstream is not this mode's job — it is an
    ordinary re-run of the upstream too, and doing it silently would produce
    exactly the superseded-basis defect AC-4 exists to prevent, one direction
    up. So drift is reported by file, with what changed, and the re-run
    refuses.
    """
    up = upstream_boundary(ws, block)
    if up is None:
        return []
    cur = manifest(ws)
    reasons = []
    for rel, sha in sorted((up.get("manifest") or {}).items()):
        if rel == CHECKPOINT:
            continue          # the resume pointer is restored, not compared
        if rel not in cur:
            reasons.append("upstream artifact %r (present at block %r's close) "
                           "is gone from the workspace" % (rel, up.get("block")))
        elif cur[rel] != sha:
            reasons.append("upstream artifact %r changed since block %r closed "
                           "— re-running %r alone would build on an upstream "
                           "the preserved state no longer describes"
                           % (rel, up.get("block"), block))
    return reasons


def _producer(ws, rel, block):
    """Which DOWNSTREAM block's boundary holds `rel` — the attribution that
    makes an invalidation report actionable. None when no recorded boundary
    holds it, which is the honest answer for an artifact some step wrote
    without a boundary ever closing over it."""
    p = _pos(block)
    holders = [b.get("block") for b in boundaries(ws)
               if _pos(b.get("block")) > p and rel in (b.get("manifest") or {})]
    return holders[-1] if holders else None


def downstream_of(ws, block):
    """What the workspace gained or changed AFTER block N closed.

    Computed against block N's own boundary manifest, so N's outputs (which N
    is about to rewrite) are not in it, and an artifact a later block merely
    read is not either.
    """
    target = boundary_of(ws, block)
    if target is None:
        return []
    kept = target.get("manifest") or {}
    out = []
    for rel, sha in sorted(manifest(ws).items()):
        if rel == CHECKPOINT or (rel in kept and kept[rel] == sha):
            continue
        producer = _producer(ws, rel, block)
        out.append({"path": rel,
                    "produced_by": producer,
                    "why": ("built after block %r closed%s — a re-run of %r "
                            "supersedes the upstream it was built on"
                            % (block,
                               " by block %r" % producer if producer else
                               " by a step with no recorded boundary",
                               block))})
    return out


def rerun(ws, block, apply=True):
    """Re-run one block against preserved upstream state.

    This does NOT execute the block — executing is the pipeline's, through the
    resume path it already has. What it does is make a single-block re-entry
    correct: verify the upstream is byte-for-byte what block N consumed
    (AC-3), invalidate everything downstream (AC-4), and restore the resume
    pointer to the state block N was entered from, so the existing resume
    enters exactly N and re-runs nothing before it.

    `apply=False` returns the same report having changed nothing — the plan a
    developer reads before agreeing to it.
    """
    report = {"stage": "run-block-rerun", "ws": ws, "block": block,
              "applied": False, "ok": False,
              "upstream": None, "invalidated": [], "checkpoint_restored": False,
              "reasons": []}
    if not enabled(ws):
        report["reasons"].append(
            "block mode is not enabled for this workspace — it is opt-in, and "
            "a re-entry that worked without being asked for would be the "
            "production path changing shape (AC-1). Enable it with: "
            "python3 scripts/run_block.py enable %s" % ws)
        return report
    target = boundary_of(ws, block)
    if target is None:
        report["reasons"].append(
            "no recorded boundary for block %r — a block can be re-run alone "
            "only from a boundary this mode observed closing; the recorded "
            "boundaries are %r"
            % (block, [b.get("block") for b in boundaries(ws)]))
        return report
    up = upstream_boundary(ws, block)
    report["upstream"] = {
        "through_block": up.get("block") if up else None,
        "files": len(up.get("manifest") or {}) if up else 0,
        "basis": ("the workspace manifest snapshotted at block %r's close"
                  % up.get("block")) if up else
                 ("block %r is the first recorded boundary — there is no "
                  "preserved upstream to consume" % block)}
    drift = upstream_drift(ws, block)
    if drift:
        report["reasons"] = drift + [
            "the upstream is not the state block %r consumed, so this is not a "
            "single-block re-run — re-run the changed block instead" % block]
        return report
    report["invalidated"] = downstream_of(ws, block)
    if not apply:
        report["ok"] = True
        return report
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S")
    dest_root = os.path.join(mode_dir(ws), INVALID_DIR, stamp)
    for item in report["invalidated"]:
        src = os.path.join(ws, item["path"])
        dest = os.path.join(dest_root, item["path"])
        try:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.move(src, dest)
            item["moved_to"] = os.path.relpath(dest, ws)
        except OSError as e:                               # pragma: no cover
            report["reasons"].append(
                "could not invalidate %r: %s" % (item["path"], e))
    if report["invalidated"]:
        _write_json(os.path.join(dest_root, "invalidated.json"),
                    {"block": block, "at": run_record._now(),
                     "items": report["invalidated"]})
    # THE RESUME POINTER BLOCK N WAS ENTERED FROM IS N'S OWN SNAPSHOT, and
    # that is CAP-4's doing rather than a coincidence: a block's close record
    # is durable BEFORE its checkpoint write (`run_record.before_checkpoint`),
    # so at the instant N closed the workspace still held the checkpoint that
    # ENTERS N. Restoring it verbatim re-enters exactly N through the resume
    # path the pipeline already has — this mode neither computes a next_stage
    # nor keeps a block->stage table that would be wrong the day one moves.
    if target.get("checkpoint") is not None:
        _write_json(os.path.join(ws, CHECKPOINT), target["checkpoint"])
        report["checkpoint_restored"] = True
    else:
        report["reasons"].append(
            "block %r closed with no checkpoint in the workspace — there is no "
            "recorded resume pointer to restore, so re-enter the block by "
            "invoking its own command directly" % (block,))
    report["applied"] = True
    report["ok"] = not report["reasons"]
    report["upstream"]["unchanged"] = True
    report["reran_upstream"] = False
    return report


# --- CLI ---------------------------------------------------------------------

def _print(obj):
    print(json.dumps(obj, indent=2, sort_keys=True))
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) == 2 and argv[0] == "enable":
        enable(argv[1])
        return _print({"stage": "run-block", "ws": argv[1], "enabled": True})
    if len(argv) == 2 and argv[0] == "disable":
        disable(argv[1])
        return _print({"stage": "run-block", "ws": argv[1], "enabled": False})
    if len(argv) == 2 and argv[0] == "status":
        ws = argv[1]
        return _print({"stage": "run-block", "ws": ws, "enabled": enabled(ws),
                       "boundaries": [{"n": b.get("n"), "block": b.get("block"),
                                       "duration_s": b.get("duration_s"),
                                       "verdict": b.get("verdict")}
                                      for b in boundaries(ws)],
                       "last_stop": _read_json(
                           os.path.join(mode_dir(ws), STOP_FILE))})
    if len(argv) >= 3 and argv[0] == "rerun":
        report = rerun(argv[1], argv[2], apply="--plan" not in argv[3:])
        _print(report)
        return 0 if report["ok"] else 1
    sys.stderr.write(
        "usage: run_block.py enable|disable|status <ws>\n"
        "       run_block.py rerun <ws> <block> [--plan]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
