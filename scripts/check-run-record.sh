#!/usr/bin/env sh
# parallel-safe
# tier: inner — pure stdlib Python over fixtures written into a private mktemp
#   workspace; no network, no shared path, no repo mutation. Measured at
#   adoption (2026-08-02) well under the runner's INNER_MS ceiling.
# covers: scripts/run_record.py scripts/run_loop.py scripts/run_block.py
#   specs/spec-run-record/**
#   scripts/draft-pipeline.py
#   scripts/probe.py scripts/draft_variants.py skills/draft-article/SKILL.md
#   skills/draft-article/stages/fan-out.md skills/draft-article/stages/stage3.md
#   skills/draft-article/stages/gate.md
# grep-binding: token — the skill greps match run-event command strings
#   across the skill's file set (SKILL.md + stages/*.md), already set-wide.
# removal-signal: the run record acquires a declared JSON schema enforced at
#   the write site by every block command (so a malformed record cannot reach
#   the file at all), or `run-events.jsonl` stops being the journal
#   SPEC-run-record governs. This check asserts by hand exactly what such a
#   write-site enforcement would assert, and retires with whichever lands
#   first.
# check-run-record.sh — the run record's FORMAT and its VALIDATOR (Story
# 20.180, #1298; SPEC-run-record CAP-2/CAP-3, companion record-formats.md
# §1-§2).
#
# WHAT IS ASSERTED, AND WHY IT IS ASSERTED ON BEHAVIOUR. Every rejection class
# in record-formats.md §2 is exercised through the module's own validator and
# the failing fixture must be rejected WITH ITS OWN REASON — not merely
# rejected. A validator that says "invalid" for six different defects has told
# a debugger nothing, and the defect this whole contract exists to fix is
# precisely a record that says something without saying what.
#
# Key-presence assertions are deliberately absent: `grep -q 'ran-partially'`
# over the module would pass against a file that mentions the string in a
# comment. Each class is built as a record and run through the code path a
# block command will run it through.
#
# THE LEGACY HALF IS AN ASSERTION ABOUT THE OLD READERS, NOT THE NEW ONE. A
# pre-contract journal is fed to `draft-pipeline.py`'s own `_read_run_events`
# and `_cost_proxies` and their output is compared against what those functions
# produced before this contract existed. The contract's constraint is that an
# older line missing the new fields is LEGACY, never invalid; a check that only
# asked the new validator would never notice the old readers breaking.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

M="scripts/run_record.py"
[ -f "$M" ] || { err "$M is absent — the record's format and validator have no module (Story 20.180 AC-1)"; }

# --- AC-1: the record's logic is NOT in the monolith --------------------------
if [ -f "$M" ]; then
  if grep -qE '^\s*(def +(validate|close_record|open_record|block_states)\b|STATUSES *=)' scripts/draft-pipeline.py; then
    err "scripts/draft-pipeline.py carries the record's compose/validate logic — it belongs in $M; the monolith gains call sites only (Story 20.180 AC-1)"
  else
    ok "the record's compose/validate/append logic lives in $M, not in the 5.3k-line monolith (AC-1)"
  fi
  if grep -nE '^(import|from) ' "$M" | grep -vE '^[0-9]+:(import|from) (argparse|datetime|hashlib|importlib|json|os|re|sys)\b' >/dev/null 2>&1; then
    err "$M imports outside the standard library — scripts/ is stdlib-only (repo convention, SPEC-run-record constraints)"
  else
    ok "$M is stdlib-only"
  fi
fi

WS=$(mktemp -d) || { err "mktemp failed"; exit 1; }
trap 'rm -rf "$WS"' EXIT INT TERM

# --- AC-2 / AC-3 / AC-5: the validator, class by class ------------------------
python3 - "$WS" <<'PY' || fail=1
import json, subprocess, sys, os
sys.path.insert(0, "scripts")
import run_record as R

ws = sys.argv[1]
bad = []
def need(cond, msg):
    if not cond:
        bad.append(msg)

H = R.draft_sha256("the draft this run decided over")

def wellformed():
    return R.close_record(
        "quality-gate", "ran-partially",
        ["cycle 2 of the quality gate", "evidence sub-check unavailable"],
        verdict=R.verdict("fail", H, detail="cycle 2 failed on section 3"),
        skipped=[R.skip("per-section evidence-type check",
                        "the harness that runs it was unavailable")],
        exit_code=1, command="quality-gate", duration_s=812.4)

# --- the well-formed record passes -------------------------------------------
need(R.validate(wellformed()) == [],
     "a well-formed close record was rejected: %r" % (R.validate(wellformed()),))
need(R.classify(wellformed()) == "close", "a close record does not classify as `close`")

# --- every rejection class in record-formats.md §2 (AC-2) --------------------
DELETE = object()

def mutate(**kw):
    r = wellformed()
    for k, v in kw.items():
        if v is DELETE:
            r.pop(k, None)
        else:
            r[k] = v
    return r

CLASSES = {
    "status outside the three values":
        mutate(status="partial"),
    "ran-partially with empty skipped":
        mutate(skipped=[]),
    "non-empty skipped with status ran":
        mutate(status="ran"),
    "a verdict-producing block with verdict absent":
        mutate(verdict=DELETE, skipped=DELETE, status="ran"),
    "a draft-deciding block with verdict.over.draft_sha256 absent":
        mutate(verdict=R.verdict("fail", None, detail="cycle 2 failed")),
    "empty route":
        mutate(route=[]),
}

# absent `skipped` is the same class as empty `skipped` (a partial that names
# nothing), asserted here rather than in CLASSES so the distinct-reason
# requirement below is not asked to separate two spellings of one defect.
need(R.validate(mutate(skipped=DELETE)) != [],
     "`ran-partially` with the `skipped` key absent entirely was ACCEPTED")

# --- `duration_s` is a STREAM-level rule, so it is asserted over a stream ----
# (story 20.187, #1333). A close paired with an open and carrying no duration
# is rejected; the same close read WITHOUT its open is not asserted over, and
# an open with no close stays well-formed.
_open = R.open_record("quality-gate", "quality-gate", {"draft_sha256": H, "cycle": 2})
_nodur = {k: v for k, v in wellformed().items() if k != "duration_s"}
_rows = R.validate_lines([json.dumps(_open), json.dumps(_nodur)])
need(any(r[2] for r in _rows),
     "a close record paired with its open and carrying no `duration_s` was ACCEPTED")
need(any("duration_s" in x for r in _rows for x in r[2]),
     "the missing-duration rejection does not name `duration_s`")
_lone = R.validate_lines([json.dumps(_nodur)])
need(not any(r[2] for r in _lone),
     "a close record read WITHOUT its open was asserted over — the rule is "
     "conditional on the pairing")
_openonly = R.validate_lines([json.dumps(_open)])
need(not any(r[2] for r in _openonly),
     "an open record with no close was rejected — it means `entered, did not finish`")
_badtype = dict(wellformed()); _badtype["duration_s"] = "812s"
need(any(r[2] for r in R.validate_lines([json.dumps(_open), json.dumps(_badtype)])),
     "a non-numeric `duration_s` was ACCEPTED")

reasons_seen = {}
for label, rec in CLASSES.items():
    reasons = R.validate(rec)
    need(reasons != [], "the %s class was ACCEPTED — %r" % (label, rec))
    reasons_seen[label] = " | ".join(reasons)

# each class must be rejected with a reason OF ITS OWN, not a shared "invalid"
for a in reasons_seen:
    for b in reasons_seen:
        if a < b:
            need(reasons_seen[a] != reasons_seen[b],
                 "the %r and %r classes are rejected with the SAME reason — a "
                 "validator that cannot tell a debugger which defect it found "
                 "has replaced one silence with another" % (a, b))

# --- the reasons reach STDERR through the CLI (AC-2) --------------------------
jl = os.path.join(ws, "rejects.jsonl")
with open(jl, "w", encoding="utf-8") as fh:
    for rec in CLASSES.values():
        fh.write(json.dumps(rec) + "\n")
p = subprocess.run([sys.executable, "scripts/run_record.py", "validate", jl],
                   capture_output=True, text=True)
need(p.returncode == 1, "the validator CLI exited %d over a file of rejects" % p.returncode)
need(p.stderr.strip() != "", "the validator CLI wrote no reason to stderr")
need(p.stdout.strip() == "", "the validator CLI wrote a PASS line while rejecting")

okfile = os.path.join(ws, "ok.jsonl")
with open(okfile, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(R.open_record("quality-gate", "quality-gate",
                                      {"draft_sha256": H, "cycle": 2})) + "\n")
    fh.write(json.dumps(wellformed()) + "\n")
p = subprocess.run([sys.executable, "scripts/run_record.py", "validate", okfile],
                   capture_output=True, text=True)
need(p.returncode == 0, "a well-formed journal was rejected by the CLI: %s" % p.stderr)

# --- AC-3: the verdict hash IS the attestation's ------------------------------
sys.path.insert(0, "scripts")
import importlib.util
spec = importlib.util.spec_from_file_location("vp", "scripts/verify-provenance.py")
vp = importlib.util.module_from_spec(spec); spec.loader.exec_module(vp)
text = "a draft whose hash both surfaces must agree on"
need(R.draft_sha256(text) == vp.draft_sha256(text),
     "run_record.draft_sha256 and verify-provenance.draft_sha256 disagree — the "
     "record carries a PARALLEL hash, which is what AC-3 forbids")
att = "attestation: draft-sha256=%s\ngraded: P1.S1\n" % vp.draft_sha256(text)
over = R.over_from_attestation(att)
need(over is not None and over["draft_sha256"] == vp.parse_attestation(att)[0],
     "verdict.over built from an attestation does not carry parse_attestation's hash")
built = R.close_record("verify", "ran", ["owner verification"],
                       verdict={"outcome": "pass", "over": over, "detail": "verified"})
need(R.validate(built) == [],
     "a record whose `over` came straight from an attestation failed validation: %r"
     % (R.validate(built),))
# hex64 discipline: the attestation's own, not a look-alike
need(R.validate(mutate(verdict=R.verdict("fail", vp.draft_sha256(text).upper()))) != [],
     "an uppercase hash was accepted — the field conforms to the attestation's "
     "lowercase hex64, not to any 64 characters")
need(R.validate(mutate(verdict=R.verdict("fail", "deadbeef"))) != [],
     "a short hash was accepted where hex64 is required")

# --- AC-5: an open with no close is well-formed and reads as entered ---------
op = R.open_record("quality-gate", "quality-gate", {"draft_sha256": H, "cycle": 2})
need(R.validate(op) == [], "an open record was rejected: %r" % (R.validate(op),))
states = R.block_states([R.open_record("fill", "provenance"),
                         R.close_record("fill", "ran", ["single pass"],
                                        verdict=R.verdict("pass", H, detail="filled")),
                         op])
by_block = {s["block"]: s["state"] for s in states}
need(by_block.get("quality-gate") == "entered-not-finished",
     "an open with no close does not read as entered-not-finished: %r" % (by_block,))
need(by_block.get("fill") == "ran", "a closed block does not read from its close record")
# and nothing repairs it
need(R.block_states([op])[0]["close"] is None,
     "block_states synthesized a close record for an open that has none")

# --- CAP-3: `did-not-run` and `n/a` stay expressible -------------------------
dnr = R.close_record("verify", "did-not-run", ["owner declined verification"],
                     verdict=R.verdict("n/a", detail="nothing was decided"))
need(R.validate(dnr) == [], "a did-not-run record was rejected: %r" % (R.validate(dnr),))
start = R.close_record("start", "ran", ["workspace minted"],
                       verdict=R.verdict("n/a", detail="decides nothing"))
need(R.validate(start) == [],
     "the non-verdict block `start` was required to carry a verdict: %r" % (R.validate(start),))

# --- emission never fails a run ----------------------------------------------
need(R.append(ws, wellformed()) is None, "append to a writable workspace reported a failure")
import contextlib, io
with contextlib.redirect_stderr(io.StringIO()) as degraded:   # the one logged line
    unwritable = R.append(os.path.join(ws, "no", "such", "dir"), wellformed())
need(unwritable is not None, "append to an unwritable path returned success")
need(degraded.getvalue().strip() != "",
     "a failed append logged nothing — degradation is one logged line, not silence")
need(len(R.read_records(ws)) == 1, "the appended record did not round-trip")

if bad:
    for b in bad:
        sys.stderr.write("FAIL: %s\n" % b)
    sys.exit(1)
print("ok:   every record-formats.md §2 rejection class fails with a reason of its own; "
      "a well-formed record passes (AC-2)")
print("ok:   the verdict hash IS the provenance attestation's, under its hex64 discipline (AC-3)")
print("ok:   an open with no close is well-formed and reads as entered-not-finished (AC-5)")
PY

# --- SUB-UNIT RECORDS (Story 20.188, #1341; record-formats.md §4) ------------
# Driven through `draft-pipeline.py progress` — the boundary the long blocks
# ALREADY checkpoint — so what is asserted is that the instrument rides that
# boundary, never that a call site exists somewhere.
python3 - "$WS" <<'PY' || fail=1
import contextlib, importlib.util, io, json, os, sys, time
sys.path.insert(0, "scripts")
import run_record as R

spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)

ws = os.path.join(sys.argv[1], "subunit")
os.makedirs(ws, exist_ok=True)
bad = []
def need(cond, msg):
    if not cond:
        bad.append(msg)

def drive(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = dp.main(list(argv))
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
    return code, out.getvalue(), err.getvalue()

# The fill block is entered, then units are recorded at the progress boundary.
R.open_block(ws, "fill", "provenance")
code, _o, _e = drive("progress", "--ws", ws, "--stage", "fill",
                     "--done", "why-the-seam-exists")
need(code == 0, "the progress boundary itself failed: %s" % _e)
time.sleep(1.05)      # so the second unit's interval is measurable, not 0.0
drive("progress", "--ws", ws, "--stage", "fill", "--done", "what-it-costs")

recs = R.read_records(ws)
units = R.sub_units(recs, "fill")

# --- AC-1: one record per recorded unit, carrying the id and its duration ----
need([u["unit"] for u in units] == ["why-the-seam-exists", "what-it-costs"],
     "the progress boundary did not emit one sub-unit record per unit, in "
     "order, under the unit's own id: %r" % (units,))
need(all(isinstance(u.get("duration_s"), (int, float)) for u in units),
     "a sub-unit record carries no duration: %r" % (units,))
need(all(u.get("since") in R.SINCE for u in units),
     "a sub-unit duration does not name the boundary it was measured from: %r"
     % (units,))
need(units[0]["since"] == "open" and units[1]["since"] == "unit",
     "the first unit is not measured from the block's open, or the second is "
     "not measured from the first: %r" % ([u.get("since") for u in units],))
need(units[1]["duration_s"] >= 1.0,
     "the second unit's duration did not span the real interval between the "
     "two boundaries: %r" % (units[1],))

# the unit id is the SAME token `progress --done` takes — no translation table
ck = json.load(open(os.path.join(ws, "checkpoint.json"), encoding="utf-8"))
need(ck["progress"]["fill"]["done"] == [u["unit"] for u in units],
     "the checkpoint's done list and the sub-unit stream do not join on the "
     "same token: %r vs %r" % (ck["progress"]["fill"]["done"], units))

# --- AC-1: at that boundary and NEVER a second one --------------------------
before = len(R.sub_units(R.read_records(ws)))
drive("progress", "--ws", ws, "--stage", "fill", "--done", "why-the-seam-exists")
need(len(R.sub_units(R.read_records(ws))) == before,
     "re-recording an already-done unit emitted a SECOND sub-unit record — "
     "`progress` is idempotent per unit and so is its instrument (AC-1)")

# --- AC-2: an interrupted block is attributable, the in-flight unit is not ---
# The block is never closed: this is exactly the run that died mid-fill.
states = {s["block"]: s for s in R.block_states(R.read_records(ws))}
need(states["fill"]["state"] == "entered-not-finished",
     "the interrupted fill does not read as entered-not-finished: %r"
     % (states["fill"],))
need(states["fill"]["units"] == ["why-the-seam-exists", "what-it-costs"],
     "the units that completed before the interruption are not attributable "
     "from the stream: %r" % (states["fill"],))
need("the-one-in-flight" not in json.dumps(R.read_records(ws)),
     "a unit that was never recorded done appears in the journal — the "
     "in-flight unit must never be invented (AC-2)")
rows = R.validate_lines([json.dumps(r) for r in R.read_records(ws)])
need([n for n, _k, rs in rows if rs] == [],
     "the interrupted journal does not pass its own validator: %r" % (rows,))
need(any(k == "unit" for _n, k, _rs in rows),
     "sub-unit records do not classify as `unit`: %r" % (rows,))

# --- AC-3: a block that records NO sub-stage progress emits no unit records --
aws = os.path.join(sys.argv[1], "atomic")
os.makedirs(aws, exist_ok=True)
R.open_block(aws, "probe", "probe.py record")
R.note(outcome="pass", detail="configuration read", route="probe")
R.close_block(0)
need(R.sub_units(R.read_records(aws)) == [],
     "a block that records no sub-stage progress emitted sub-unit records — "
     "the instrument follows the existing boundary, it does not create one "
     "(AC-3)")
# and the stage token of a non-block emits nothing even when progress is called
need(R.emit_units(aws, "harvest", ["a-batch"]) == [],
     "a stage that is not a block of the block<->command table emitted a "
     "sub-unit record (AC-3)")

# --- AC-4: the sub-unit accounting is BOUNDED by the block's own duration ----
def stream(unit_durations, block_duration):
    op = R.open_record("fill", "provenance")
    out = [op]
    for i, d in enumerate(unit_durations):
        out.append(R.unit_record("fill", "s%d" % i, duration_s=d,
                                 since="open" if i == 0 else "unit"))
    out.append(R.close_record(
        "fill", "ran", ["single pass"], command="provenance",
        verdict=R.verdict("pass", R.draft_sha256("d"), detail="filled"),
        duration_s=block_duration))
    return R.validate_lines([json.dumps(r) for r in out])

okrows = stream([120.0, 300.5, 60.25], 900.0)
need([n for n, _k, rs in okrows if rs] == [],
     "a sub-unit accounting INSIDE its block's duration was rejected: %r"
     % (okrows,))
badrows = stream([600.0, 400.0], 900.0)
reasons = [r for _n, _k, rs in badrows for r in rs]
need(reasons, "a sub-unit accounting that EXCEEDS its block's own duration_s "
              "was ACCEPTED — that is a defect, not a rounding note (AC-4)")
need(any("EXCEEDS" in r or "exceed" in r.lower() for r in reasons),
     "the over-accounting rejection does not say what it found: %r" % (reasons,))
# rounding alone never trips it: three records rounded at 3 decimals
need([n for n, _k, rs in stream([300.0, 300.0, 300.001], 900.0) if rs] == [],
     "the emitter's own 3-decimal rounding was reported as an over-accounting")
# a unit outside any open span is attributable but not asserted over
outside = [R.unit_record("fill", "s0", duration_s=5000.0, since="run"),
           R.open_record("fill", "provenance"),
           R.close_record("fill", "ran", ["single pass"], command="provenance",
                          verdict=R.verdict("pass", R.draft_sha256("d"),
                                            detail="filled"),
                          duration_s=10.0)]
need([n for n, _k, rs in R.validate_lines([json.dumps(r) for r in outside])
      if rs] == [],
     "a unit recorded OUTSIDE the block's open/close span was accounted "
     "against it — the rule is conditional on the span, exactly as §2's is")

# --- the §4 shape rejects, each with its own reason --------------------------
CLASSES = {
    "no unit id": {"ts": "t", "block": "fill", "event": "unit"},
    "unknown block": R.unit_record("harvest", "s0"),
    "duration with no since": {"ts": "t", "block": "fill", "event": "unit",
                               "unit": "s0", "duration_s": 3.0},
    "non-numeric duration": {"ts": "t", "block": "fill", "event": "unit",
                             "unit": "s0", "duration_s": "3s", "since": "open"},
    "batch of one": {"ts": "t", "block": "fill", "event": "unit",
                     "unit": "s0", "batch": 1},
}
seen = {}
for label, rec in CLASSES.items():
    rs = R.validate(rec)
    need(rs != [], "the %s class was ACCEPTED — %r" % (label, rec))
    seen[label] = " | ".join(rs)
for a in seen:
    for b in seen:
        if a < b:
            need(seen[a] != seen[b],
                 "the %r and %r sub-unit classes are rejected with the SAME "
                 "reason" % (a, b))

if bad:
    for b in bad:
        sys.stderr.write("FAIL: %s\n" % b)
    sys.exit(1)
print("ok:   the progress boundary emits one sub-unit record per recorded unit, "
      "under the same token, and never a second one (20.188 AC-1)")
print("ok:   an interrupted block's completed units are attributable and the "
      "in-flight one is not invented (20.188 AC-2)")
print("ok:   a block that records no sub-stage progress emits no sub-unit "
      "records (20.188 AC-3)")
print("ok:   a sub-unit accounting exceeding its block's own duration_s is "
      "rejected, and rounding alone is not (20.188 AC-4)")
PY

# --- BOUNDED IMPROVEMENT LOOPS (Story 20.189, #1334; record-formats.md §5) ---
# Driven through the dispatcher's own `quality-gate` cycles — the first CONSUMER
# of the loop contract — plus a fabricated loop id no code has ever heard of,
# because the contract binds by PROPERTY and a check that only exercised the
# gate would be asserting the gate's history instead of the contract.
python3 - "$WS" <<'PY' || fail=1
import contextlib, importlib.util, io, json, os, sys
sys.path.insert(0, "scripts")
import run_record as R
import run_loop as L

spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)

ws = os.path.join(sys.argv[1], "loop")
os.makedirs(ws, exist_ok=True)
bad = []
def need(cond, msg):
    if not cond:
        bad.append(msg)

def drive(*argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = dp.main(list(argv))
        except SystemExit as e:
            code = e.code if isinstance(e.code, int) else 1
    return code, out.getvalue(), err.getvalue()

FM = "---\naudience: the maintainer\naudience_id: maintainer\n---\n\n"
CYCLE1 = FM + "## A section\n\nOne short sentence about the thing.\n"
CYCLE2 = FM + "## A section\n\nOne short sentence about the thing.\n\n" \
              "## What it costs\n\nA second sentence, added by the revision.\n"
draft = os.path.join(ws, "draft.md")
mp = os.path.join(ws, "map.txt")
with open(mp, "w", encoding="utf-8") as fh:
    fh.write("P1.S1[L8]: narration\n")

def write(text):
    with open(draft, "w", encoding="utf-8") as fh:   # THE OVERWRITE, in place
        fh.write(text)

# Two cycles of the gate, the second overwriting the first's draft in place.
write(CYCLE1)
sha1 = R.draft_sha256(CYCLE1)
drive("quality-gate", "--ws", ws, "--draft", draft, "--map", mp,
      "--profile", "slim", "--cycle", "1")
write(CYCLE2)
sha2 = R.draft_sha256(CYCLE2)
drive("quality-gate", "--ws", ws, "--draft", draft, "--map", mp,
      "--profile", "slim", "--cycle", "2")

recs = R.read_records(ws)
its = L.iterations(recs, "quality-gate")

# --- AC-2: the superseded artifact is addressable by hash, and the record ----
#           carries its delta beside the verdict it was graded against.
need(len(its) == 2,
     "two gate cycles left %d iteration record(s) — a loop that preserves "
     "nothing leaves only its verdicts, which is the defect" % (len(its),))
if len(its) == 2:
    (rec1, it1), (rec2, it2) = its
    need(it1["artifact_sha256"] == sha1 and it2["artifact_sha256"] == sha2,
         "the iteration records do not name the drafts actually graded: %r"
         % ([it1.get("artifact_sha256"), it2.get("artifact_sha256")],))
    need(L.read_preserved(ws, "quality-gate", sha1) == CYCLE1,
         "the draft cycle 2 OVERWROTE is not recoverable by hash from the run "
         "workspace — the superseded artifact did not survive its cycle (AC-2)")
    need(it2["delta"].get("from") == sha1 and it2["delta"].get("changed") is True
         and it2["delta"].get("lines_added", 0) > 0,
         "cycle 2's record does not carry a delta naming what it superseded and "
         "what changed: %r" % (it2.get("delta"),))
    need(isinstance(rec2.get("verdict"), dict)
         and rec2["verdict"].get("outcome") in R.OUTCOMES,
         "the iteration record carries no verdict — a loop regenerates an "
         "artifact AGAINST a verdict: %r" % (rec2.get("verdict"),))
    need(it1["delta"].get("from") is None
         and "first iteration" in it1["delta"].get("basis", ""),
         "cycle 1's delta does not say it had no predecessor, so 'nothing "
         "changed' and 'nothing to compare' are indistinguishable: %r"
         % (it1.get("delta"),))
    need(not R.validate(rec2),
         "the emitted iteration record does not satisfy the validator: %r"
         % (R.validate(rec2),))

# --- AC-5: the artifact rides the WORKSPACE, never run-events.jsonl ----------
journal = open(R.run_events_path(ws), encoding="utf-8").read()
need("A second sentence, added by the revision." not in journal,
     "the draft's text reached run-events.jsonl — per-iteration artifacts live "
     "in the run workspace, and the journal carries the judgment (AC-5)")
need(os.path.isfile(L.artifact_path(ws, "quality-gate", sha1)),
     "the preserved artifact is not at <ws>/loop/<loop>/<sha256>.md (AC-5)")
try:
    L.iteration_record_fields("l", 1, sha1, {"basis": "b", "content": CYCLE1})
    need(False, "a caller could compose an iteration carrying the ARTIFACT — "
                "the carrier split is not enforced where records are composed")
except ValueError:
    pass

# --- AC-1: the contract binds by PROPERTY — an unheard-of loop is covered ----
R.open_block(ws, "verify", "verify")
L.record_iteration(ws, "some-future-loop-nobody-enumerated", 1,
                   "an artifact of a loop written tomorrow\n", ext=".txt")
R.note(outcome="fail", detail="graded", route="fixture",
       draft_sha256=R.draft_sha256("x" * 3))
R.close_block(1)
future = L.iterations(R.read_records(ws), "some-future-loop-nobody-enumerated")
need(len(future) == 1 and not R.validate(future[0][0]),
     "a loop this codebase has never heard of is not covered — the contract "
     "binds by PROPERTY (any repeated act regenerating an artifact against a "
     "verdict), never by an enumerated list (AC-1): %r" % (future,))
need("some-future-loop" not in open("scripts/run_loop.py", encoding="utf-8").read(),
     "the fixture's loop id appears in the module — it must be unknown to it")
for src in ("scripts/run_loop.py",):
    text = open(src, encoding="utf-8").read()
    need("quality-gate" not in text.split('"""')[2],
         "%s names the quality gate in its CODE — the gate is the first "
         "CONSUMER of the loop contract, never its definition (AC-1)" % (src,))

# --- AC-3: the run's close carries the loop report ---------------------------
R.open_block(ws, "complete", "complete")
R.note(outcome="pass", detail="done", route="fixture",
       draft_sha256=R.draft_sha256(CYCLE2))
R.close_block(0)
run_close = [r for r in R.read_records(ws)
             if r.get("event") == "close" and r.get("block") == "complete"][-1]
report = run_close.get("loop_report")
need(isinstance(report, list) and report,
     "the run's close carries no loop report (AC-3): %r" % (run_close,))
if isinstance(report, list) and report:
    gate = [e for e in report if e["loop"] == "quality-gate"]
    need(len(gate) == 1 and gate[0]["iterations"] == 2
         and len(gate[0]["changes"]) == 2,
         "the report does not state the gate loop's iteration count with what "
         "EACH changed: %r" % (gate,))
    need(gate and gate[0]["outcome"] == "converged",
         "a loop whose last iteration PASSED is not reported as converged: %r"
         % (gate,))
    need(not R.validate(run_close),
         "the emitted loop report does not satisfy the validator: %r"
         % (R.validate(run_close),))

# CHURN is the other half of AC-3, and it must NAME its shape. Driven through
# the same pure function the run's close uses, over the three churn shapes.
def churn(*outcomes, **kw):
    recs, prev = [], None
    for i, o in enumerate(outcomes, 1):
        sha = kw.get("sha") or ("%064x" % i)
        recs.append({"ts": "t", "block": "quality-gate", "event": "close",
                     "status": "ran", "verdict": {"outcome": o, "over": {}},
                     "iteration": {"loop": "x", "n": i, "artifact_sha256": sha,
                                   "delta": {"basis": "b", "from": prev,
                                             "changed": kw.get("changed", True)}}})
        prev = sha
    return L.loop_report(recs)[0]

bound = churn("fail", "fail")
need(bound["outcome"] == "churned" and "bound" in bound.get("why", ""),
     "a loop that reached its bound without a pass is not reported as churned "
     "with that reason (AC-3): %r" % (bound,))
revisit = churn("fail", "fail", sha="b" * 64)
need(revisit["outcome"] == "churned" and "re-graded" in revisit.get("why", ""),
     "a loop that returned to an artifact it had left is not named as an "
     "oscillation (AC-3): %r" % (revisit,))
noop = churn("fail", "fail", changed=False)
need(noop["outcome"] == "churned" and "changing nothing" in noop.get("why", ""),
     "a cycle spent changing nothing is not named as such (AC-3): %r" % (noop,))
inflight = L.loop_report([{"ts": "t", "block": "quality-gate", "event": "close",
                           "status": "ran", "iteration": {
                               "loop": "x", "n": 1, "artifact_sha256": "a" * 64,
                               "delta": {"basis": "first"}}}])[0]
need(inflight["outcome"] == "in-flight",
     "an iteration whose block carries no outcome was repaired into a churn "
     "verdict it did not earn (AC-3): %r" % (inflight,))

# --- every §5 rejection class fails with a REASON OF ITS OWN -----------------
def close(**kw):
    rec = {"ts": "t", "block": "quality-gate", "event": "close", "status": "ran",
           "route": ["r"], "exit": 0,
           "verdict": {"outcome": "fail",
                       "over": {"draft_sha256": "a" * 64}, "detail": "d"}}
    rec.update(kw)
    return rec

IT = {"loop": "x", "n": 1, "artifact_sha256": "a" * 64, "delta": {"basis": "b"}}
def it(**kw):
    d = dict(IT); d.update(kw); return d

for label, rec, phrase in [
    ("an iteration with no loop id", close(iteration=it(loop="")), "`loop` id"),
    ("an iteration whose n is not 1-based", close(iteration=it(n=0)), "`n` is"),
    ("an iteration that cannot name its artifact",
     close(iteration=it(artifact_sha256="nope")), "artifact_sha256"),
    ("an iteration with no delta", close(iteration=it(delta=None)), "`delta`"),
    ("a delta with no basis", close(iteration=it(delta={})), "`basis`"),
    ("a later iteration naming no predecessor",
     close(iteration=it(n=2)), "wearing a label"),
    ("an iteration carrying the artifact itself",
     close(iteration=it(delta={"basis": "b", "content": "the draft"})),
     "NEVER in run-events.jsonl"),
    ("an iteration with no verdict",
     close(iteration=it(), verdict=None), "AGAINST A VERDICT"),
    ("a report whose count disagrees with its own changes",
     close(loop_report=[{"loop": "x", "iterations": 3, "outcome": "converged",
                         "changes": [{"n": 1}]}]), "disagrees with itself"),
    ("a report with an outcome that is neither",
     close(loop_report=[{"loop": "x", "iterations": 1, "outcome": "fine",
                         "changes": [{"n": 1}]}]), "CONVERGED or CHURNED"),
    ("an unexplained churn label",
     close(loop_report=[{"loop": "x", "iterations": 1, "outcome": "churned",
                         "changes": [{"n": 1}]}]), "no `why`"),
]:
    reasons = R.validate(rec)
    need(any(phrase in r for r in reasons),
         "%s was not rejected with its own reason (looked for %r): %r"
         % (label, phrase, reasons))

# The STREAM-level rule: a report that disagrees with the journal it summarises.
lines = [json.dumps({"ts": "t", "block": "quality-gate", "event": "close",
                     "status": "ran", "route": ["r"], "exit": 0,
                     "verdict": {"outcome": "fail",
                                 "over": {"draft_sha256": "a" * 64},
                                 "detail": "d"},
                     "iteration": it()}),
         json.dumps(close(block="complete", loop_report=[
             {"loop": "x", "iterations": 4, "outcome": "converged",
              "changes": [{"n": i} for i in range(4)]}]))]
rows = R.validate_lines(lines)
need(any("the report is DERIVED from the journal" in r
         for _n, _k, rs in rows for r in rs),
     "a loop report claiming more iterations than the stream holds was not "
     "caught at the stream level: %r" % (rows,))

# --- AC-4: the bound, the delta re-grade and the ledger carry are UNCHANGED --
code, out, _e = drive("quality-gate", "--ws", ws, "--draft", draft, "--map", mp,
                      "--profile", "slim", "--cycle", "3")
blocked = json.loads(out)
need(code == 1 and blocked["action"] == "publish-blocker"
     and blocked["publishable"] is False,
     "the two-cycle bound no longer blocks a third cycle — this story adds "
     "HISTORY, never a third cycle (AC-4): %r" % (blocked,))
judge = os.path.join(ws, "judge.txt")
with open(judge, "w", encoding="utf-8") as fh:
    fh.write("dim1: fail Section 9\ndim2: pass\n")
code, out, _e = drive("quality-gate", "--ws", ws, "--draft", draft, "--map", mp,
                      "--judge", judge, "--cycle", "2",
                      "--prior-locations", "Section 2")
graded = json.loads(out)
need(graded["dimensions"]["dim1"]["verdict"] == "pass"
     and graded["delta_recheck"]["suppressed_new_interpretive"],
     "the second-cycle delta re-grade no longer suppresses a fresh interpretive "
     "finding — preserved history changed the loop's behaviour (AC-4): %r"
     % (graded.get("delta_recheck"),))

if bad:
    for b in bad:
        sys.stderr.write("FAIL: %s\n" % b)
    sys.exit(1)
print("ok:   an overwritten iteration artifact stays addressable by hash and its "
      "record carries the delta beside the verdict (20.189 AC-2)")
print("ok:   the artifact rides the workspace and never run-events.jsonl, and a "
      "record composed with artifact content is refused (20.189 AC-5)")
print("ok:   a loop id no code enumerates is covered — the contract binds by "
      "property (20.189 AC-1)")
print("ok:   the run's close carries the loop report: count, what each changed, "
      "converged or churned with its reason (20.189 AC-3)")
print("ok:   the two-cycle bound and the delta re-grade behave exactly as before "
      "(20.189 AC-4)")
print("ok:   every record-formats.md §5 rejection class fails with a reason of its "
      "own, and a report disagreeing with its stream is caught at stream level")
PY

# --- DEVELOPMENT BLOCK MODE (Story 20.190, #1332) ----------------------------
# The amendment's own test of the carrier split: a block mode that needed a new
# record class would be evidence the split was wrong. So the assertions below
# are as much about what the journal does NOT gain as about what the mode does
# — the off path is compared record-for-record against a run with the hook
# neutralised, and the ON path is compared against the OFF path.
python3 - "$WS" <<'PY' || fail=1
import contextlib, io, json, os, sys
sys.path.insert(0, "scripts")
import run_record as R
import run_block as B

os.environ.pop(B.ENV, None)     # the per-process switch must not leak in here
bad = []
def need(cond, msg):
    if not cond:
        bad.append(msg)

SEQ = (("probe", "probe.json"), ("interview", "interview.json"),
       ("fill", "draft.md"), ("quality-gate", "gate-verdicts.txt"))

def drive(ws, block, artifact=None):
    """One block, in CAP-4's order: the close record lands, THEN the block's
    own checkpoint write. The mode's re-entry depends on that order, so the
    fixture must reproduce it rather than assume it."""
    R.open_block(ws, block, "cmd-" + block)
    if artifact:
        with open(os.path.join(ws, artifact), "w", encoding="utf-8") as fh:
            fh.write(block + " output\n")
    R.note(outcome="pass", detail="did " + block, route=block,
           draft_sha256=(R.draft_sha256("a draft")
                         if block in R.DRAFT_DECIDING_BLOCKS else None))
    err = io.StringIO()
    with contextlib.redirect_stderr(err):     # the mode's own notice, captured
        R.close_block(0)
    with open(os.path.join(ws, "checkpoint.json"), "w", encoding="utf-8") as fh:
        json.dump({"next_stage": B.next_block(block) or "done"}, fh)
    return err.getvalue()

def mint(name, seq=SEQ):
    ws = os.path.join(sys.argv[1], "blockmode-" + name)
    os.makedirs(ws, exist_ok=True)
    with open(os.path.join(ws, "checkpoint.json"), "w", encoding="utf-8") as fh:
        json.dump({"next_stage": "probe"}, fh)
    return ws

def tree(ws):
    out = []
    for base, _dirs, files in os.walk(ws):
        for fn in files:
            out.append(os.path.relpath(os.path.join(base, fn), ws))
    return sorted(out)

def normalised(ws):
    """Records with the two timing fields dropped — everything a run's journal
    says, minus what differs between any two executions of the same run."""
    out = []
    for rec in R.read_records(ws):
        out.append({k: v for k, v in rec.items()
                    if k not in ("ts", "duration_s")})
    return out

# --- AC-1: OFF is byte-identical to a run with no block mode at all -----------
# `control` runs with the hook itself replaced, i.e. exactly the code path that
# existed before this story. `off` runs the real hook with the mode not
# enabled. A difference in either the journal or the workspace is the mode
# having changed production behaviour.
control = mint("control")
real_hook = R._block_mode
R._block_mode = lambda ws, rec: None
try:
    for block, artifact in SEQ:
        drive(control, block, artifact)
finally:
    R._block_mode = real_hook
off = mint("off")
off_said = [drive(off, block, artifact) for block, artifact in SEQ]
need(off_said == ["", "", "", ""],
     "an OFF run said something about block mode: %r (AC-1)" % (off_said,))

need(normalised(off) == normalised(control),
     "with the mode OFF the journal differs from a run with the hook removed "
     "entirely — the mode is opt-in and production behaviour is unchanged "
     "(AC-1):\n  off=%r\n  control=%r" % (normalised(off), normalised(control)))
need(tree(off) == tree(control),
     "with the mode OFF the run workspace differs from a run with the hook "
     "removed: %r vs %r (AC-1)" % (tree(off), tree(control)))
need(not os.path.exists(B.mode_dir(off)),
     "an OFF run minted the mode's own directory — the gate is checked before "
     "anything is created, which is what makes AC-1 assertable from the "
     "workspace rather than from a code path")
need(B.after_close(off, R.read_records(off)[-1]) is None,
     "the hook did work with the mode off — it must return before touching "
     "anything (AC-1)")
need(B.enabled(off) is False and B.rerun(off, "fill")["ok"] is False,
     "a re-entry worked without the mode having been asked for — opt-in means "
     "the control surface is absent until enabled (AC-1)")
need("opt-in" in " ".join(B.rerun(off, "fill")["reasons"]),
     "the off-path refusal does not say why it refused")
# and the per-process switch is a switch, not a default
os.environ[B.ENV] = "1"
need(B.enabled(mint("envprobe")) is True, "the %s switch does not turn the "
     "mode on" % B.ENV)
os.environ.pop(B.ENV)

# --- AC-2: the mode stops at the boundary and reports block/duration/verdict --
on = mint("on")
B.enable(on)
said = {block: drive(on, block, artifact) for block, artifact in SEQ}
need("STOPPED at block 'fill'" in said["fill"]
     and "verdict pass" in said["fill"]
     and "'quality-gate' is NOT entered" in said["fill"],
     "the boundary stop was not reported where the developer is looking — the "
     "block, its verdict and the block being withheld reach the command's own "
     "stderr (AC-2): %r" % (said["fill"],))

closes = {r["block"]: r for r in R.read_records(on)
          if R.classify(r) == R.EVENT_CLOSE}
for snap in B.boundaries(on):
    close = closes[snap["block"]]
    notice = B.stop_notice(on, snap)
    need(notice["stopped_at"] == close["block"],
         "the stop notice names a different block than the close record: %r"
         % (notice,))
    need(notice["duration_s"] == close.get("duration_s")
         and isinstance(close.get("duration_s"), (int, float)),
         "the stop notice's duration is not the close record's own — the "
         "record carries the time and the mode READS it, it does not "
         "recompute one (AC-2): %r vs %r" % (notice, close.get("duration_s")))
    need(notice["verdict"]["outcome"] == close["verdict"]["outcome"]
         and notice["verdict"]["detail"] == close["verdict"]["detail"],
         "the stop notice does not report the block's verdict: %r" % (notice,))
stop = json.load(open(os.path.join(B.mode_dir(on), B.STOP_FILE),
                     encoding="utf-8"))
need(stop["stopped_at"] == "quality-gate" and stop["next_block"] == "verify",
     "the last boundary's stop record does not say where the run stopped and "
     "which block is NOT entered: %r" % (stop,))
need("NOT entered" in stop["not_entered"] and stop["rerun"],
     "the stop record does not state that the next block is withheld, or "
     "offers no way back in: %r" % (stop,))

# --- AC-5: being ON adds NO record and NO field ------------------------------
need(normalised(on) == normalised(off),
     "turning the mode ON changed the journal — the mode introduces no record "
     "class and no record field; everything it stores rides the workspace "
     "(AC-5, amendments.md 2026-08-03):\n  on=%r\n  off=%r"
     % (normalised(on), normalised(off)))
need(all(R.classify(r) in (R.EVENT_OPEN, R.EVENT_CLOSE, R.EVENT_UNIT)
         for r in R.read_records(on)),
     "a record written under the mode does not classify as one of the three "
     "kinds record-formats.md declares (AC-5)")
rows = R.validate_lines([json.dumps(r) for r in R.read_records(on)])
need([n for n, _k, rs in rows if rs] == [],
     "a journal written under the mode fails the record validator: %r" % (rows,))

# --- AC-3: a re-run of block N consumes blocks 1..N-1 unchanged --------------
before_up = {rel: B._sha256(os.path.join(on, rel))
             for rel in ("probe.json", "interview.json")}
before_recs = len(R.read_records(on))
report = B.rerun(on, "fill")
need(report["ok"] and report["applied"],
     "re-running a completed block was refused: %r" % (report["reasons"],))
need(report["upstream"]["through_block"] == "interview"
     and report["upstream"].get("unchanged") is True,
     "the re-run does not name the preserved upstream it consumed: %r"
     % (report["upstream"],))
need(all(B._sha256(os.path.join(on, rel)) == sha
         for rel, sha in before_up.items()),
     "a re-run of the fill CHANGED an upstream artifact — blocks 1..N-1 are "
     "consumed unchanged (AC-3)")
need(len(R.read_records(on)) == before_recs,
     "the re-entry itself wrote to the journal — it re-runs nothing, so it "
     "records nothing (AC-3/AC-5)")
need(report.get("reran_upstream") is False,
     "the re-entry does not state that it ran nothing upstream: %r" % (report,))
ck = json.load(open(os.path.join(on, "checkpoint.json"), encoding="utf-8"))
need(ck["next_stage"] == "fill",
     "the resume pointer was not restored to the state block `fill` was "
     "entered from — the re-run would enter some other block (AC-3): %r"
     % (ck,))
per_block = {}
for r in R.read_records(on):
    per_block[r.get("block")] = per_block.get(r.get("block"), 0) + 1
drive(on, "fill", "draft.md")     # the developer's actual single-block re-run
after = {}
for r in R.read_records(on):
    after[r.get("block")] = after.get(r.get("block"), 0) + 1
need(after["fill"] == per_block["fill"] + 2,
     "the single-block re-run did not record its own open and close: %r" % (after,))
need(all(after[b] == per_block[b] for b in ("probe", "interview")),
     "an upstream block ran again during a single-block re-run of the fill — "
     "nothing upstream re-runs (AC-3): %r vs %r" % (after, per_block))
need(B.upstream_drift(on, "fill") == [],
     "after the re-run the preserved upstream no longer verifies: %r"
     % (B.upstream_drift(on, "fill"),))

# a re-run against a CHANGED upstream refuses, naming the file
with open(os.path.join(on, "probe.json"), "a", encoding="utf-8") as fh:
    fh.write("edited upstream\n")
refused = B.rerun(on, "fill")
need(not refused["ok"] and any("probe.json" in r for r in refused["reasons"]),
     "a re-run against a CHANGED upstream was allowed, or refused without "
     "naming what changed: %r" % (refused,))

# --- AC-4: what comes after N is invalidated, never silently retained --------
need(not os.path.exists(os.path.join(on, "gate-verdicts.txt")),
     "the quality gate's artifact survived a re-run of the fill in place — a "
     "downstream artifact built on a superseded upstream is the failure this "
     "mode must not manufacture (AC-4)")
item = [i for i in report["invalidated"] if i["path"] == "gate-verdicts.txt"]
need(item and item[0]["produced_by"] == "quality-gate",
     "the invalidation report does not name the downstream artifact and the "
     "block that produced it: %r" % (report["invalidated"],))
need(item and os.path.isfile(os.path.join(on, item[0]["moved_to"])),
     "the invalidated artifact was destroyed rather than set aside — "
     "invalidated is a state, not a shredder: %r" % (item,))
need(os.path.isfile(os.path.join(on, "draft.md")),
     "the re-run invalidated the block's OWN output — only what comes AFTER "
     "block N is superseded (AC-4)")
need(all("interview.json" != i["path"] for i in report["invalidated"]),
     "an UPSTREAM artifact was invalidated: %r" % (report["invalidated"],))

# --- the module is stdlib-only, like its siblings ----------------------------
import re as _re
src = open("scripts/run_block.py", encoding="utf-8").read()
extra = [ln for ln in src.splitlines()
         if _re.match(r"^(import|from) ", ln)
         and not _re.match(r"^(import|from) (datetime|hashlib|json|os|re|shutil"
                           r"|sys|run_record)\b", ln)]
need(not extra, "scripts/run_block.py imports outside the standard library: %r"
     % (extra,))

if bad:
    for b in bad:
        sys.stderr.write("FAIL: %s\n" % b)
    sys.exit(1)
print("ok:   with block mode OFF the journal and the workspace are identical to "
      "a run with the hook removed entirely (20.190 AC-1)")
print("ok:   a closed block reports its block, its own recorded duration and its "
      "verdict, and names the block it is withholding (20.190 AC-2)")
print("ok:   re-running one block consumes blocks 1..N-1 unchanged, re-runs "
      "nothing upstream, and refuses when the upstream has changed (20.190 AC-3)")
print("ok:   a re-run invalidates what was built after block N, naming it and "
      "the block that produced it, and preserving it (20.190 AC-4)")
print("ok:   the mode adds no record class and no record field — the ON journal "
      "equals the OFF journal (20.190 AC-5)")
PY

# --- AC-4: the OLD readers are unchanged over a pre-contract journal ----------
python3 - "$WS" <<'PY' || fail=1
import importlib.util, json, os, sys
sys.path.insert(0, "scripts")
import run_record as R

ws = os.path.join(sys.argv[1], "legacy")
os.makedirs(ws, exist_ok=True)
legacy = [
    {"ts": "2026-08-02T18:57:10+00:00", "stage": "probe", "event": "start"},
    {"ts": "2026-08-02T19:02:44+00:00", "stage": "probe", "event": "end"},
    {"ts": "2026-08-02T19:24:03+00:00", "stage": "interview", "event": "end",
     "note": "consulted: none (policy_source unset)"},
]
with open(os.path.join(ws, "run-events.jsonl"), "w", encoding="utf-8") as fh:
    for rec in legacy:
        fh.write(json.dumps(rec) + "\n")

spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)

bad = []
events = dp._read_run_events(ws)
if events != legacy:
    bad.append("_read_run_events no longer returns the pre-contract lines verbatim: %r" % (events,))
p = dp._cost_proxies(ws)
if p["events_recorded"] != 3 or p["elapsed_minutes"] != 27 or p["basis"] != "run-events.jsonl":
    bad.append("_cost_proxies output changed over a pre-contract journal: %r" % (p,))
if p["stage_retries"] != 0 or p["subagents"] != 0:
    bad.append("_cost_proxies proxy counts changed: %r" % (p,))

for rec in legacy:
    if R.classify(rec) != "legacy":
        bad.append("a pre-contract line classifies as %r, not `legacy`" % R.classify(rec))
    if R.validate(rec) != []:
        bad.append("a pre-contract line was REJECTED — an older line missing the new "
                   "fields is unknown, never invalid: %r" % (R.validate(rec),))

if bad:
    for b in bad:
        sys.stderr.write("FAIL: %s\n" % b)
    sys.exit(1)
print("ok:   a pre-contract journal reads unchanged through _read_run_events/_cost_proxies, "
      "and the validator calls those lines legacy rather than failing them (AC-4)")
PY

# --- EMISSION (Story 20.181, CAP-1/CAP-3/CAP-4) -------------------------------
# The block sequence is driven with ZERO `run-event` calls, through the
# dispatcher the skill invokes, and the journal is read back. Everything here is
# behaviour: no grep for a call site would notice a wrapper that swallowed the
# record, and a call site is not the property — "a block that ran has logged" is.
python3 - "$WS" <<'PY' || fail=1
import contextlib, importlib.util, io, json, os, sys
sys.path.insert(0, "scripts")
import run_record as R

spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)

ws = os.path.join(sys.argv[1], "emit")
os.makedirs(ws, exist_ok=True)
draft = os.path.join(ws, "draft.md")
with open(draft, "w", encoding="utf-8") as fh:
    fh.write("---\naudience: the maintainer\naudience_id: maintainer\n---\n\n"
             "## A section\n\nOne short sentence about the thing.\n")
mp = os.path.join(ws, "map.txt")
with open(mp, "w", encoding="utf-8") as fh:
    fh.write("P1.S1[L8]: narration\n")

bad = []
def need(cond, msg):
    if not cond:
        bad.append(msg)

def drive(*argv):
    """Run one block command exactly as the dispatcher does."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = dp.main(list(argv))
        except SystemExit as e:                 # argparse
            code = e.code if isinstance(e.code, int) else 1
    return code

# --- CAP-1: one open and one close per block that ran, zero `run-event` calls -
drive("provenance", "--ws", ws, "--map", mp, "--draft", draft)
gate_code = drive("quality-gate", "--ws", ws, "--draft", draft, "--map", mp,
                  "--profile", "slim")
drive("verify", "--ws", ws, draft)

records = R.read_records(ws)
need(records, "the block sequence was driven and the journal is EMPTY — emission "
              "is not a side effect of running (CAP-1)")
need(not any(r.get("event") in ("start", "end", "judge-round") for r in records),
     "a narrowed `run-event` event reached the journal without anyone calling it")
states = {s["block"]: s for s in R.block_states(records)}
for block in ("fill", "quality-gate", "verify"):
    s = states.get(block)
    need(s is not None and s["opens"] == 1 and s["closes"] == 1,
         "block %r did not write exactly one open and one close: %r" % (block, s))
need([n for n, _k, rs in R.validate_lines(
        [json.dumps(r) for r in records]) if rs] == [],
     "the emitted journal does not pass its own validator: %r"
     % (R.validate_lines([json.dumps(r) for r in records]),))

# every close carries the JUDGMENT, over the SAME hash the attestation uses
H = R.draft_sha256(open(draft, encoding="utf-8").read())
for block in ("fill", "quality-gate", "verify"):
    close = states[block]["close"]
    need(close["verdict"]["over"]["draft_sha256"] == H,
         "block %r decided over a different hash than the draft's own (CAP-2)" % block)
    need(close["verdict"]["detail"].strip() != "",
         "block %r closed with an empty detail" % block)
    need(close["route"], "block %r closed with an empty route" % block)

# --- CAP-1: a NON-ZERO exit still records ------------------------------------
broken = os.path.join(ws, "broken-map.txt")
with open(broken, "w", encoding="utf-8") as fh:
    fh.write("this is not a provenance entry\n")
before = len(R.read_records(ws))
code = drive("provenance", "--ws", ws, "--map", broken, "--draft", draft)
after = R.read_records(ws)
need(code != 0, "the failing fixture did not fail — the AC is about a non-zero exit")
need(len(after) == before + 2,
     "a block that EXITED NON-ZERO did not write its open and its close — the "
     "failed block is the case the record exists for (CAP-1)")
failed = [r for r in after if r.get("event") == "close" and r.get("block") == "fill"][-1]
need(failed["exit"] == code and failed["verdict"]["outcome"] == "fail",
     "the failing close does not carry its own exit and a failing outcome: %r" % (failed,))

# --- CAP-3: the partial state is PRODUCED, not merely expressible ------------
gate = states["quality-gate"]["close"]
need(gate["status"] == "ran-partially",
     "the slim-profile gate, which waives its dim1-2 judge, closed as %r — a "
     "partial that reports clean is the collapse CAP-3 exists to prevent"
     % (gate["status"],))
need(any("dim1" in s["step"] for s in gate["skipped"]),
     "the gate's `ran-partially` does not NAME the waived sub-obligation: %r"
     % (gate["skipped"],))
need("evidence" not in json.dumps(gate["skipped"]),
     "the gate named the per-section evidence-type check — that repair is #1288's "
     "and this story does not touch it")

# --- CAP-4: the record is durable BEFORE the checkpoint ----------------------
ows = os.path.join(sys.argv[1], "order")
os.makedirs(ows, exist_ok=True)
seen, real_append = {}, R.append
def spy(w, rec):
    seen[rec.get("event")] = os.path.isfile(os.path.join(w, "checkpoint.json"))
    return real_append(w, rec)
R.append = spy
try:
    R.open_block(ows, "fill", "provenance")
    dp._write_checkpoint(ows, {"next_stage": "quality-gate"})
finally:
    R.append = real_append
need(seen.get("close") is False,
     "the block's close record was written when a checkpoint ALREADY existed — "
     "the ordering CAP-4 states is reversed, and a kill between the two would "
     "leave resumable state with no record behind it")
need(os.path.isfile(os.path.join(ows, "checkpoint.json")),
     "the checkpoint was not written at all — the fixture proves nothing")
need([r for r in R.read_records(ows) if r.get("event") == "close"],
     "no close record landed before the checkpoint write")

# --- AC-6: the cost block's judge-round basis is no longer the fallback -------
p = dp._cost_proxies(ws)
need(p["judge_rounds"] >= 1,
     "a gate that ran is not counted as a judge round: %r" % (p,))
need("fallback" not in p["judge_rounds_basis"] and "verdict artifact" not in p["judge_rounds_basis"],
     "the cost block still reports the verdict-FILE fallback as its basis after a "
     "gate recorded its own round: %r" % (p["judge_rounds_basis"],))

if bad:
    for b in bad:
        sys.stderr.write("FAIL: %s\n" % b)
    sys.exit(1)
print("ok:   the block sequence driven with ZERO run-event calls writes one open and "
      "one close per block, and a non-zero exit still records (CAP-1)")
print("ok:   a block whose sub-obligation was waived closes `ran-partially` and NAMES it (CAP-3)")
print("ok:   the close record is durable BEFORE the checkpoint write (CAP-4)")
print("ok:   a gate that ran is a counted judge round, so the verdict-file fallback is "
      "no longer the reported basis (Story 20.181 AC-6)")
PY

# --- AC-4: `run-event` is narrowed, and the prose stopped asking --------------
if grep -qE '"--event", required=True, choices=\("retry", "subagent"\)' scripts/draft-pipeline.py; then
  ok "run-event accepts only the events no block command can observe from inside itself (AC-4)"
else
  err "run-event still accepts a block's own start/end (or the choices moved) — the block's start and end are the block command's to write (SPEC-run-record constraints)"
fi
if grep -qE 'run-event .*--event (start|end|judge-round)' skills/draft-article/SKILL.md skills/draft-article/stages/*.md; then
  err "skill prose still asks an agent to record a block's own start/end with run-event — the surface that depends on remembering is the defect (AC-4)"
else
  ok "no skill prose asks an agent to record a block's own start or end (AC-4)"
fi
grep -q -- '--event subagent' skills/draft-article/stages/fan-out.md \
  || err "the fan-out's `--event subagent` basis was neither preserved nor re-homed (AC-4)"

# --- CAP-1: every DOCUMENTED block invocation passes --ws, by construction ----
# `run_record.workspace_of` falls back to $WS and then to the resolver's
# active-run pointer, so an omitted `--ws` ships INERT rather than broken — the
# shape that would have shipped story 20.182 dead (stage2.md) and recurred in
# #1306 (review-article/phases/passes.md) and #1313 (stage3.md, gate.md). Assert
# the flag at each documented call site so a fourth omission is a red check.
ws_flag_miss=0
for f in skills/draft-article/SKILL.md skills/draft-article/stages/stage3.md \
         skills/draft-article/stages/gate.md; do
  for cmd in provenance quality-gate verify; do
    # A bare `draft-pipeline.py <cmd>` in backticks is a NOUN (a table row
    # naming the command), not a call site; only a form with arguments after it
    # is an invocation, so the trailing space/continuation is required.
    miss=$(grep -nE "draft-pipeline\.py ${cmd}( |\\\\)" "$f" | grep -v -- '--ws' || true)
    if [ -n "$miss" ]; then
      ws_flag_miss=1
      err "$f documents \`$cmd\` without --ws — that block would reach its workspace by resolver fallback, not by construction (CAP-1, #1313): $miss"
    fi
  done
done
if [ "$ws_flag_miss" -eq 0 ]; then
  ok "every documented provenance/quality-gate/verify invocation passes --ws (CAP-1, #1313)"
fi

# --- AC-6: the spec carrier this check answers to still exists ---------------
for f in specs/spec-run-record/SPEC.md specs/spec-run-record/record-formats.md; do
  [ -f "$f" ] || err "$f is absent — this check's contract carrier is gone (AC-6)"
done
[ "$fail" -eq 0 ] && ok "the SPEC-run-record carrier and its record-formats companion are present"

if [ "$fail" -eq 0 ]; then
  printf '\nAll run-record checks passed.\n'; exit 0
else
  printf '\nrun-record checks FAILED.\n' >&2; exit 1
fi
