#!/usr/bin/env sh
# parallel-safe
# tier: inner — pure stdlib Python over fixtures written into a private mktemp
#   workspace; no network, no shared path, no repo mutation. Measured at
#   adoption (2026-08-02) well under the runner's INNER_MS ceiling.
# covers: scripts/run_record.py specs/spec-run-record/**
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
        exit_code=1, command="quality-gate")

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
