#!/usr/bin/env sh
# parallel-safe
# tier: inner — pure stdlib Python over fixtures written into a private mktemp
#   workspace; no network, no shared path, no repo mutation. Measured at
#   adoption (2026-08-02) well under the runner's INNER_MS ceiling.
# covers: scripts/run_record.py specs/spec-run-record/** scripts/draft-pipeline.py
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
