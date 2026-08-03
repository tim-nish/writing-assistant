#!/bin/sh
# check-stop-gate-carrier.sh — the Stop hook asserts an ABSENCE, and never
# blocks on evidence that has not landed (Story 20.151, #1221).
#
# tier: inner
# parallel-safe
# covers: scripts/hooks/stop-gate-carrier.py scripts/gate-inventory.py .claude/settings.json scripts/draft-pipeline.py scripts/resolve-paths.py
# removal-signal: retires when the harness itself guarantees that a declared
#   gate reaches the owner through the selection control — at which point the
#   absence this asserts cannot occur. It does NOT retire because it passes:
#   the class it guards recurred twelve times while every check was green.
#
# WHAT IS ASSERTED, AND WHY EACH CASE EXISTS.
#   1. A gate with a tool call is clean.
#   2. A gate whose payload was EMITTED but never CALLED is a finding — this is
#      the shape the 2026-08-02 run showed (payloads for q8 and depth, no
#      selection event) and the one every prior carrier passed.
#   3. An UNSETTLED transcript asserts NOTHING and does not block. Owner
#      decision 2026-08-02: blocking holds the owner's turn open, so racing the
#      async transcript writer is the one failure this must not have.
#   4. The hook exits 0 on a non-pipeline turn, on unparseable input, and when
#      the auditor cannot run. A hook that takes the session down with it is
#      worse than no hook.
#   5. THE REPRODUCTION (Story 20.156, #1245): the whole chain — checkpoint
#      write, active-run pointer, Stop payload, hook — over the shape of run
#      20260802T142948-588398 exits 2 and names the gate; the carried case
#      exits 0. Cases 1-4 above audited the auditor with a workspace handed to
#      them, which is how a green suite accompanied a hook that could not fire.
#   6. Each evaluated turn records its verdict, and a completed run whose every
#      verdict is cannot-determine is a finding.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

WS=$(mktemp -d)
TR=$(mktemp)
trap 'rm -rf "$WS" "$TR"' EXIT

# A run that reached `probe-entry` and emitted its payload.
python3 - "$WS" <<'PY'
import importlib.util, json, os, sys
ws = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "dg", os.path.join(os.path.dirname(os.path.realpath(__file__)) if False else "scripts", "draft_gates.py"))
dg = importlib.util.module_from_spec(spec); spec.loader.exec_module(dg)
dg.probe_entry_gate(3, ws=ws)
# `gates_reached` IS GONE (Story 20.156, #1245). This fixture used to write it,
# and it was the ONLY writer of that field anywhere in the repository — so the
# check manufactured the input the pipeline never produced and measured itself.
# `next_stage` alone resolves `probe-entry` through the registry, which is the
# join a real run actually has.
json.dump({"next_stage": dg.PROBE},
          open(os.path.join(ws, "checkpoint.json"), "w"))
PY

# --- 1. reached derives from run state, not from a caller ----------------
if python3 "$ROOT/scripts/gate-inventory.py" --audit --ws "$WS" \
     --reached-from-state >/dev/null 2>&1; then
  ok "reached derives from the checkpoint — no caller self-report needed"
else
  err "--reached-from-state did not resolve probe-entry from checkpoint.json"
fi

# --- 2. a SETTLED transcript WITH the tool call is clean ------------------
MARK="turn-marker-alpha"
cat > "$TR" <<PY
{"message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"gate":"probe-entry"}}]}}
{"message":{"content":[{"type":"text","text":"$MARK"}]}}
PY
if python3 "$ROOT/scripts/gate-inventory.py" --audit --ws "$WS" \
     --reached-from-state --transcript "$TR" --settle-marker "$MARK" \
     >/dev/null 2>&1; then
  ok "a gate carrying an AskUserQuestion tool call audits clean"
else
  err "a gate WITH tool-call evidence was reported as a gap"
fi

# --- 3. a SETTLED transcript WITHOUT the tool call is a FINDING -----------
cat > "$TR" <<PY
{"message":{"content":[{"type":"text","text":"Say the word and I'll run probe."}]}}
{"message":{"content":[{"type":"text","text":"$MARK"}]}}
PY
if python3 "$ROOT/scripts/gate-inventory.py" --audit --ws "$WS" \
     --reached-from-state --transcript "$TR" --settle-marker "$MARK" \
     >/dev/null 2>&1; then
  err "an emitted-but-never-called gate audited CLEAN — this is the exact
      shape #1221 reports and every prior carrier passed"
else
  ok "an emitted-but-never-called gate is a finding"
fi

# --- 4. an UNSETTLED transcript asserts nothing and does not block --------
# Same prose-only transcript, but the marker is absent: the file has not caught
# up. This must NOT be reported as a gap.
OUT=$(python3 "$ROOT/scripts/gate-inventory.py" --audit --ws "$WS" \
        --reached-from-state --transcript "$TR" \
        --settle-marker "a-marker-the-transcript-does-not-carry" 2>&1) && rc=0 || rc=$?
if [ "${rc:-0}" -eq 0 ]; then
  ok "an unsettled transcript asserts nothing — cannot-determine, never a block"
else
  err "an unsettled transcript BLOCKED: $OUT — this races the async writer and
      holds the owner's turn open on evidence that simply had not landed"
fi

# --- 5. the hook never takes the session down ----------------------------
for input in '{"session_id":"x","transcript_path":"/nonexistent","cwd":"/tmp"}' 'not json' ''; do
  if printf '%s' "$input" | python3 "$ROOT/scripts/hooks/stop-gate-carrier.py" >/dev/null 2>&1; then
    :
  else
    err "the Stop hook exited non-zero on input it cannot act on: $input"
  fi
done
ok "the Stop hook exits 0 on non-pipeline, unparseable, and empty input"

# --- 6. the carrier is actually installed --------------------------------
if [ -f "$ROOT/.claude/settings.json" ] && \
   grep -q 'stop-gate-carrier' "$ROOT/.claude/settings.json"; then
  ok ".claude/settings.json registers the Stop hook — the carrier is committed,
      which is the whole basis for the 2026-08-02 bounding of SPEC.md:76"
else
  err ".claude/settings.json does not register the hook — a carrier nothing
      invokes is exactly the advisory rule this story replaces"
fi

# === 7. THE REPRODUCTION TEST (Story 20.156, #1245) ======================
# Everything above audits the AUDITOR with a workspace handed to it. This drives
# the WHOLE CHAIN the way a real turn does — pipeline checkpoint write, pointer,
# Stop payload, hook, exit code — over the shape of run 20260802T142948-588398:
# a due gate, an emitted payload, and no AskUserQuestion event. That run's turns
# all closed cleanly, which is the acceptance criterion the thirteenth cycle
# never had. If this passes while a real run still lets an un-carried gate
# close, the fixture is what the class defeats and the amendment says so.
REPRO=$(mktemp -d); SESSCWD=$(mktemp -d); STATE=$(mktemp -d)
trap 'rm -rf "$WS" "$TR" "$REPRO" "$SESSCWD" "$STATE"' EXIT
RWS="$REPRO/20260802T142948-588398"; mkdir -p "$RWS"
RP="python3 $ROOT/scripts/resolve-paths.py"

# The run emits its probe-entry payload and checkpoints into `probe`, through
# the pipeline's own checkpoint command — the writer AC-1 adds, not a fixture.
python3 - "$RWS" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("dg", os.path.join("scripts", "draft_gates.py"))
dg = importlib.util.module_from_spec(spec); spec.loader.exec_module(dg)
dg.probe_entry_gate(3, ws=sys.argv[1])
PY
( cd "$SESSCWD" && printf '{"next_stage": "probe"}' | \
  XDG_STATE_HOME="$STATE" python3 "$ROOT/scripts/draft-pipeline.py" \
    checkpoint --ws "$RWS" - >/dev/null )

PTR=$(XDG_STATE_HOME="$STATE" $RP active-run-pointer --cwd "$SESSCWD")
if XDG_STATE_HOME="$STATE" python3 - "$PTR" "$RWS" <<'PY'
import json, os, sys
rec = json.load(open(sys.argv[1]))
assert rec["ws"] == os.path.realpath(sys.argv[2]), rec
assert rec["next_stage"] == "probe", rec
assert rec["written_at"], rec
PY
then
  ok "the checkpoint write leaves {ws, next_stage, written_at} at
      <state-root>/<cwd-key>/active-run.json — the subject has a WRITER"
else
  err "no active-run pointer after a stage transition: the hook has no subject,
      which is the state in which thirteen cycles of gates closed un-carried"
fi

# The payload carries ONLY documented Stop fields — `cwd` is the whole subject
# resolution, which is the property `WA_RUN_WS` and `cwd_run_ws` never had.
hook_turn() {  # $1=transcript $2=marker -> sets rc/HOOKERR
  HOOKERR=$(printf '{"session_id":"repro-1","transcript_path":"%s","cwd":"%s",
      "permission_mode":"default","hook_event_name":"Stop",
      "last_assistant_message":"%s"}' "$1" "$SESSCWD" "$2" \
    | XDG_STATE_HOME="$STATE" python3 "$ROOT/scripts/hooks/stop-gate-carrier.py" \
        2>&1 >/dev/null) && rc=0 || rc=$?
}

RTR=$(mktemp); trap 'rm -rf "$WS" "$TR" "$REPRO" "$SESSCWD" "$STATE" "$RTR"' EXIT
RMARK="repro-turn-marker"

# 7a. The failing shape: the ask reached the owner as PROSE.
cat > "$RTR" <<PY
{"message":{"content":[{"type":"text","text":"I'll probe the repo — say the word."}]}}
{"message":{"content":[{"type":"text","text":"$RMARK"}]}}
PY
hook_turn "$RTR" "$RMARK"
if [ "${rc:-0}" -eq 2 ] && printf '%s' "$HOOKERR" | grep -q 'probe-entry'; then
  ok "REPRODUCTION: a due gate with no AskUserQuestion event BLOCKS the turn
      (exit 2) and names probe-entry on stderr"
else
  err "the reproduction turn exited ${rc:-0} (want 2) — the carrier still cannot
      fire on the shape run 20260802T142948-588398 actually had.
      stderr: $HOOKERR"
fi

# 7b. The settled-clean case: the gate was CARRIED, so the turn ends.
cat > "$RTR" <<PY
{"message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"gate":"probe-entry"}}]}}
{"message":{"content":[{"type":"text","text":"$RMARK"}]}}
PY
hook_turn "$RTR" "$RMARK"
if [ "${rc:-0}" -eq 0 ]; then
  ok "the settled-clean case exits 0 — a carried gate is not blocked"
else
  err "a gate WITH its tool call blocked the turn (exit ${rc:-0}): $HOOKERR"
fi

# 7c. Every evaluated turn recorded its verdict into the run workspace.
if python3 - "$RWS/stop-gate-verdicts.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(rows) == 2, rows
assert [r["result"] for r in rows] == ["finding", "clean"], rows
assert all(r["subject-found"] and r["settled"] is True for r in rows), rows
PY
then
  ok "each evaluated turn records subject-found / settled / result into the run
      workspace — the cannot-determine rate finally has a watcher"
else
  err "the per-turn verdict record is missing or wrong: an indeterminate chain
      is indistinguishable from a clean one without it"
fi

# 7d. A completed run that determined NOTHING is a finding.
DEAD="$REPRO/20260802T000000-000000"; mkdir -p "$DEAD"
printf '{"next_stage": "done"}' > "$DEAD/checkpoint.json"
printf '{"result": "cannot-determine"}\n{"result": "cannot-determine"}\n' \
  > "$DEAD/stop-gate-verdicts.jsonl"
OUT=$(python3 "$ROOT/scripts/hooks/stop-gate-carrier.py" --run-finding "$DEAD")
printf '%s' "$OUT" | grep -q 'cannot-determine' \
  && ok "an all-indeterminate completed run is surfaced as a finding" \
  || err "an all-indeterminate completed run produced no finding: $OUT"
OUT=$(python3 "$ROOT/scripts/hooks/stop-gate-carrier.py" --run-finding "$RWS")
[ -z "$OUT" ] \
  && ok "a run that determined something is NOT reported as the finding" \
  || err "a determined run was reported as all-indeterminate: $OUT"

# --- 8. A CRASH IN THE AUDIT REPORTS AS A CRASH (#1336) ----------------------
# The defect: a real finding and an exception both leave the auditor at a
# non-zero exit, so a KeyError reached the owner worded as a confirmed policy
# breach ("the ask reached the owner as prose") on three consecutive stops.
# The discriminator is that a finding prints its verdict object first and a
# crash prints none. Asserted over the decision function rather than through a
# stand-in auditor: an environment override whose only writer is a fixture is
# the dead-input shape this repository refuses.
if python3 - "$ROOT" <<'PYEOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location(
    "hook", os.path.join(sys.argv[1], "scripts", "hooks", "stop-gate-carrier.py"))
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)

TB = ('Traceback (most recent call last):\n'
      '  File "gate-inventory.py", line 219, in audit\n'
      '    r["gate"] for r in rows\n'
      "KeyError: 'gate'\n")

# The observed shape: non-zero exit, traceback, NO verdict object.
outcome, sig = h.audit_outcome(1, "", TB)
assert outcome == "crash", outcome
assert sig == "KeyError: 'gate'", sig

# A real finding prints its verdict first, and stays a finding.
found, _ = h.audit_outcome(1, '{"ok": false, "missing": ["thesis"]}\nBOUND: ...',
                           "error: reached but never emitted: ['thesis']")
assert found == "finding", found
assert h.audit_outcome(0, '{"ok": true}', "")[0] is None

# The message says crash, names the exception, and never carries the verdict.
msg = h.crash_report(sig, 0)
assert "gate audit crashed" in msg, msg
assert "KeyError" in msg, msg
assert "prose" not in msg, msg
assert "x2" not in msg, msg

# The rider: a repeat identifies as one, and the count climbs.
assert "same crash as the previous turn (x2)" in h.crash_report(sig, 1)
assert "(x4)" in h.crash_report(sig, 3)

# Counted from the recorded rows, and a different signature ends the streak.
import json, tempfile
ws = tempfile.mkdtemp()
with open(os.path.join(ws, "stop-gate-verdicts.jsonl"), "w") as f:
    for _ in range(3):
        f.write(json.dumps({"result": "cannot-determine", "crash": sig}) + "\n")
assert h.prior_consecutive_crashes(ws, sig) == 3
assert h.prior_consecutive_crashes(ws, "ValueError: other") == 0
with open(os.path.join(ws, "stop-gate-verdicts.jsonl"), "a") as f:
    f.write(json.dumps({"result": "clean"}) + "\n")
assert h.prior_consecutive_crashes(ws, sig) == 0, "a clean turn must end the streak"
PYEOF
then
  ok "a crashed audit reports AS a crash, names its exception, never carries the
      missed-gate verdict, and a repeat identifies itself as repeating"
else
  err "the crash-vs-verdict split does not hold: an exception can still reach
      the owner worded as a confirmed policy breach (#1336)"
fi

# A crashed turn is a cannot-determine turn, so the all-indeterminate run
# finding still fires over a run of nothing but crashes.
CRASHED="$REPRO/20260803T000000-000000"; mkdir -p "$CRASHED"
printf '{"next_stage": "done"}' > "$CRASHED/checkpoint.json"
printf '{"result":"cannot-determine","crash":"KeyError: 1"}\n{"result":"cannot-determine","crash":"KeyError: 1"}\n' \
  > "$CRASHED/stop-gate-verdicts.jsonl"
OUT=$(python3 "$ROOT/scripts/hooks/stop-gate-carrier.py" --run-finding "$CRASHED")
printf '%s' "$OUT" | grep -q 'cannot-determine' \
  && ok "a run whose every turn crashed surfaces as an all-indeterminate run —
      evidence about the auditor, which is exactly what it is" \
  || err "a run of crashes produced no all-indeterminate finding: $OUT"

[ "$fail" -eq 0 ] || { echo; echo "stop-gate-carrier checks FAILED."; exit 1; }
echo
echo "stop-gate-carrier checks passed."
