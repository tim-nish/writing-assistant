#!/usr/bin/env sh
# check-checkpoint-resume.sh — verify per-stage checkpoint + resume (Story 13.5).
# POSIX shell + stdlib Python. A run that stops after stage N resumes from N+1
# rather than restarting; the checkpoint is atomic, idempotent, and lives in the
# run workspace, never the host tree.

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
WS="$work/ws"; mkdir -p "$WS"

# A fresh workspace with no checkpoint resumes at stage 1 (harvest), not started.
out=$(python3 "$DP" resume --ws "$WS")
echo "$out" | jget 'd["resumed"]' | grep -q False && ok "no checkpoint -> resumed=false (fresh run)" || err "fresh workspace not reported as unstarted"
echo "$out" | jget 'd["next_stage"]' | grep -q harvest && ok "fresh run resumes at stage 1 (harvest)" || err "fresh run did not point at harvest"

# Checkpoint a stage's output state (carries next_stage), then resume from it.
printf '{"stage":"consume","next_stage":"interview","fact_sheet":[]}' > "$work/state.json"
python3 "$DP" checkpoint --ws "$WS" "$work/state.json" | grep -q 'next_stage=interview' \
  && ok "checkpoint records the stage's next_stage" || err "checkpoint did not record next_stage"
[ -f "$WS/checkpoint.json" ] && ok "checkpoint lands in the run workspace" || err "checkpoint file not written to \$WS"
out=$(python3 "$DP" resume --ws "$WS")
echo "$out" | jget 'd["resumed"]' | grep -q True && ok "checkpointed run -> resumed=true" || err "checkpointed run not resumable"
echo "$out" | jget 'd["next_stage"]' | grep -q interview \
  && ok "resume returns the next stage (does not re-run the completed one)" || err "resume did not skip the completed stage"

# Idempotent: checkpointing the same state twice yields an identical file.
python3 "$DP" checkpoint --ws "$WS" "$work/state.json" >/dev/null
h1=$(cat "$WS/checkpoint.json")
python3 "$DP" checkpoint --ws "$WS" "$work/state.json" >/dev/null
[ "$h1" = "$(cat "$WS/checkpoint.json")" ] && ok "checkpoint is idempotent (same state -> identical file)" || err "checkpoint not idempotent"

# A later stage overwrites the checkpoint so resume advances.
printf '{"stage":"provenance","next_stage":"quality-gate"}' | python3 "$DP" checkpoint --ws "$WS" - >/dev/null
python3 "$DP" resume --ws "$WS" | jget 'd["next_stage"]' | grep -q quality-gate \
  && ok "checkpoint advances as stages complete (stdin form)" || err "checkpoint did not advance"

# Fail-closed: state without next_stage is rejected (not a resumable checkpoint).
printf '{"stage":"consume"}' | python3 "$DP" checkpoint --ws "$WS" - 2>&1 | grep -q 'no .next_stage' \
  && ok "reject: state without next_stage is not a valid checkpoint" || err "state without next_stage accepted"

# SKILL documents the durability contract.
grep -qi 'checkpoint' "$SKILL" && grep -qi 'resume from the last completed' "$SKILL" \
  && ok "SKILL documents checkpoint/resume durability" || err "SKILL missing durability contract"
grep -qi 'never re-runs a completed stage' "$SKILL" && ok "SKILL states resume never re-runs a completed stage" || err "SKILL missing idempotent-resume note"

if [ "$fail" -eq 0 ]; then
  printf '\nAll checkpoint/resume checks passed.\n'; exit 0
else
  printf '\ncheckpoint/resume checks FAILED.\n' >&2; exit 1
fi
