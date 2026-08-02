#!/bin/sh
# check-stop-gate-carrier.sh — the Stop hook asserts an ABSENCE, and never
# blocks on evidence that has not landed (Story 20.151, #1221).
#
# tier: inner
# parallel-safe
# covers: scripts/hooks/stop-gate-carrier.py scripts/gate-inventory.py .claude/settings.json
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
json.dump({"next_stage": "probe", "gates_reached": ["probe-entry"]},
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

[ "$fail" -eq 0 ] || { echo; echo "stop-gate-carrier checks FAILED."; exit 1; }
echo
echo "stop-gate-carrier checks passed."
