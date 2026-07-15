#!/usr/bin/env sh
# check-stage0-fold.sh — verify the folded Stage-0 command (Story 13.13):
# config validation + framework check + workspace autostart in ONE invocation,
# halting on the first problem, preserving each check's diagnostics, and never
# minting a workspace on a bad config/framework. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
export XDG_STATE_HOME="$work/state"

ws_count() { find "$work/state" -type d -path '*/runs/*' 2>/dev/null | wc -l; }

# 1. Bad config (no writing-sources.yaml) -> halt, verbatim report, no run_state,
#    no workspace minted.
if out=$(python3 "$DP" stage0 F2 specs/ --root "$host" 2>"$work/err"); then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] && ok "stage0 halts non-zero on a bad config" || err "stage0 did not halt on bad config"
grep -q 'configuration validation failed' "$work/err" && ok "stage0 relays validate-config's report verbatim" || err "stage0 lost the config report"
[ -z "$out" ] && ok "stage0 prints no run_state JSON on a bad config" || err "stage0 emitted run_state on a bad config"
[ "$(ws_count)" -eq 0 ] && ok "no workspace minted on a bad config" || err "workspace minted despite bad config"

# Make the config clean for the remaining cases.
printf 'sources:\n  - path: .\n' > "$host/writing-sources.yaml"

# 2. Bad framework -> exit 2, nothing started, still no workspace.
if out=$(python3 "$DP" stage0 F9 specs/ --root "$host" 2>"$work/err"); then rc=0; else rc=$?; fi
[ "$rc" -eq 2 ] && ok "stage0 rejects an invalid framework (exit 2)" || err "stage0 did not reject bad framework"
grep -q 'invalid article type' "$work/err" && ok "stage0 names the invalid article type" || err "article-type error not reported"
grep -q 'introduce the project' "$work/err" && ok "invalid-type error lists intent labels" || err "error does not list intent labels"
[ "$(ws_count)" -eq 0 ] && ok "no workspace minted on a bad framework" || err "workspace minted despite bad framework"

# 2b. Intent label resolves to the same framework as its F-id alias
#     (SPEC-draft-article-ux CAP-1, Story 13.27) — closed mapping, no fuzz.
out=$(python3 "$DP" stage0 "share engineering lessons" specs/ --root "$host")
echo "$out" | jget 'd["run_state"]["framework"]' | grep -q F2 \
  && ok "intent label 'share engineering lessons' resolves to F2" \
  || err "intent label did not resolve to F2"
if python3 "$DP" stage0 "share lessons" specs/ --root "$host" >/dev/null 2>&1; then
  err "fuzzy intent label accepted — mapping must be closed"
else
  ok "near-miss intent label rejected (closed mapping)"
fi

# 3. Clean config + framework -> one JSON with config_ok, run_state, and a workspace.
out=$(python3 "$DP" stage0 F2 specs/ --root "$host")
echo "$out" | jget 'd["config_ok"]' | grep -q True && ok "stage0 reports config_ok on a clean config" || err "config_ok missing/false"
echo "$out" | jget 'd["run_state"]["framework"]' | grep -q F2 && ok "stage0 carries the run_state (framework F2)" || err "run_state missing"
echo "$out" | jget 'd["resumed"]' | grep -q False && ok "stage0 mints a fresh run when none is in progress" || err "stage0 false-resumed"
ws=$(echo "$out" | jget 'd["ws"]'); [ -d "$ws" ] && ok "stage0 returns a real workspace dir" || err "stage0 workspace missing"

# 4. Fold is real: on a second invocation with an in-progress checkpoint, stage0
#    resumes it rather than minting a new run.
printf '{"stage":"consume","next_stage":"interview"}' | python3 "$DP" checkpoint --ws "$ws" - >/dev/null
out=$(python3 "$DP" stage0 F2 specs/ --root "$host")
echo "$out" | jget 'd["resumed"]' | grep -q True && ok "stage0 auto-resumes an in-progress run" || err "stage0 did not resume"
echo "$out" | jget 'd["next_stage"]' | grep -q interview && ok "stage0 resumes at the recorded next_stage" || err "stage0 resumed at wrong stage"
unset XDG_STATE_HOME

# 5. SKILL wires Stage 0 as one folded call.
grep -qi 'draft-pipeline.py stage0' "$SKILL" && grep -qi 'one call\|single invocation\|one turn' "$SKILL" \
  && ok "SKILL wires the folded stage0 (Story 13.13)" || err "SKILL does not wire the folded stage0"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage0-fold checks passed.\n'; exit 0
else
  printf '\nstage0-fold checks FAILED.\n' >&2; exit 1
fi
