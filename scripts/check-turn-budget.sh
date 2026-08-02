#!/bin/sh
# check-turn-budget.sh — an owner-facing turn carries one status line and the
# decision payload (Story 20.153, #1225).
#
# tier: inner
# parallel-safe
# covers: scripts/turn_budget.py scripts/hooks/stop-gate-carrier.py
# removal-signal: retires when the harness itself bounds owner-facing turn
#   volume, at which point measuring it here is redundant. It does NOT retire
#   because it passes — the rule's whole value is that it stays true as new
#   relay surfaces are added, and those are exactly what nobody re-checks.
#
# WHY VOLUME IS MEASURABLE WHERE REGISTER WAS NOT. `SPEC.md:80` records that
# this repository cannot constrain the relay layer absolutely; that argument is
# about WORDING, which requires judgment. A line count does not. So the rule is
# declared in `turn_budget.py` and measured by story 20.151's Stop hook — the
# one place a turn demonstrably ends.
#
# WHAT IS ASSERTED:
#   1. the budget is DECLARED WITH ITS MEASUREMENT, not asserted as a number;
#   2. the debug channel is OFF by default and opt-in per sitting;
#   3. an unreasoned owner-facing line is UNREPRESENTABLE, not merely caught;
#   4. the volume finding REPORTS and never blocks — the cost of a wrong block
#      exceeds the cost of a long turn;
#   5. the rule stands without the hook, so the hook defines nothing.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
run() { (cd "$ROOT" && python3 - "$@"); }

# --- 1. the number carries its measurement -------------------------------
if grep -q 'MEASURED, 2026-08-02' "$ROOT/scripts/turn_budget.py" \
   && grep -q 'TURN_LINE_BUDGET' "$ROOT/scripts/turn_budget.py"; then
  ok "the budget is declared with the measurement it came from — a threshold
      with no evidence behind it is re-argued at every sitting"
else
  err "TURN_LINE_BUDGET carries no measurement; it is an asserted number"
fi

# --- 2. the debug channel is off by default ------------------------------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("tb", "scripts/turn_budget.py")
tb = importlib.util.module_from_spec(s); s.loader.exec_module(tb)
off = not tb.debug_enabled({})
on = tb.debug_enabled({tb.DEBUG_ENV: "1"})
sys.exit(0 if (off and on) else 1)
PY
then
  ok "the debug channel is OFF by default and opt-in for the sitting"
else
  err "the debug channel is not off by default"
fi

# --- 3. an unreasoned line cannot be built -------------------------------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("tb", "scripts/turn_budget.py")
tb = importlib.util.module_from_spec(s); s.loader.exec_module(tb)
try:
    tb.essential_with_reason("Stage 2 is complete.", "")
except ValueError:
    sys.exit(0)
sys.exit(1)
PY
then
  ok "an owner-facing line with no stated reason is unrepresentable — the
      constrain move, not a lint over text already composed"
else
  err "a line with no reason was accepted; clause 3 is advisory only"
fi

# --- 4. blank lines are layout, not volume -------------------------------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("tb", "scripts/turn_budget.py")
tb = importlib.util.module_from_spec(s); s.loader.exec_module(tb)
# Two real lines separated by blanks is within budget; the budget must not
# punish readability, which is the opposite of its purpose.
sys.exit(0 if tb.count_lines("a\n\n\nb") == 2 else 1)
PY
then
  ok "blank lines do not count — the budget bounds volume, not formatting"
else
  err "blank lines count toward the budget"
fi

# --- 5. the volume finding never blocks the turn -------------------------
OUT=$(printf '%s' '{"session_id":"x","cwd":"/tmp","last_assistant_message":"1\n2\n3\n4\n5\n6\n7\n8"}' \
      | python3 "$ROOT/scripts/hooks/stop-gate-carrier.py" 2>&1) && rc=0 || rc=$?
if [ "${rc:-0}" -eq 0 ]; then
  ok "an over-budget turn is reported, never blocked — a wrong block costs the
      owner their turn, a long turn costs them scrolling"
else
  err "an over-budget turn BLOCKED (exit $rc): $OUT"
fi

# --- 6. the rule stands without the hook ---------------------------------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("tb", "scripts/turn_budget.py")
tb = importlib.util.module_from_spec(s); s.loader.exec_module(tb)
# turn_budget must not import the hook: the hook MEASURES the rule and the
# rule must survive the hook being absent or disabled.
src = open("scripts/turn_budget.py").read()
sys.exit(1 if "stop-gate-carrier" in src or "hooks" in src else 0)
PY
then
  ok "the budget is defined independently of the hook — the hook measures it
      and defines nothing"
else
  err "turn_budget.py depends on the hook; the rule would vanish with it"
fi

[ "$fail" -eq 0 ] || { echo; echo "turn-budget checks FAILED."; exit 1; }
echo
echo "turn-budget checks passed."
