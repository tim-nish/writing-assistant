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

# --- Automatic resume (Story 13.12) — autostart picks the workspace ----------
# Sandboxed state root + a git host repo so resolve-paths resolves hermetically.
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
export XDG_STATE_HOME="$work/state"
AUTO() { python3 "$DP" autostart --root "$host"; }

# 1. No runs yet -> resumed=false, fresh run at harvest (the AC4 no-false-resume path).
out=$(AUTO)
echo "$out" | jget 'd["resumed"]' | grep -q False && ok "autostart: no run -> resumed=false (fresh)" || err "autostart false-resumed with no run"
echo "$out" | jget 'd["next_stage"]' | grep -q harvest && ok "autostart: fresh run starts at harvest" || err "fresh autostart not at harvest"
ws1=$(echo "$out" | jget 'd["ws"]')
[ -d "$ws1" ] && ok "autostart: minted a real workspace dir" || err "autostart workspace missing"

# 2. An in-progress checkpoint in that run -> autostart auto-resumes it.
printf '{"stage":"consume","next_stage":"interview"}' | python3 "$DP" checkpoint --ws "$ws1" - >/dev/null
out=$(AUTO)
echo "$out" | jget 'd["resumed"]' | grep -q True && ok "autostart: in-progress run -> resumed=true (automatic)" || err "autostart did not auto-resume"
echo "$out" | jget 'd["next_stage"]' | grep -q interview && ok "autostart: resumes at the recorded next_stage" || err "autostart resumed at wrong stage"
[ "$(echo "$out" | jget 'd["ws"]')" = "$ws1" ] && ok "autostart: reuses the in-progress workspace (no new run)" || err "autostart minted a new run instead of resuming"

# 3. Marking the run done -> autostart does NOT resume it (starts fresh).
printf '{"stage":"variants","next_stage":"done"}' | python3 "$DP" checkpoint --ws "$ws1" - >/dev/null
out=$(AUTO)
echo "$out" | jget 'd["resumed"]' | grep -q False && ok "autostart: a done run is not resumed (fresh run)" || err "autostart resumed a completed run"
[ "$(echo "$out" | jget 'd["ws"]')" != "$ws1" ] && ok "autostart: a fresh run gets a new workspace after done" || err "autostart reused the done run's workspace"
unset XDG_STATE_HOME

# --- Sub-stage progress (Story 13.83, #388) ---------------------------------
WS2="$work/ws2"; mkdir -p "$WS2"
# Recording progress on a fresh workspace keeps the run in that stage.
python3 "$DP" progress --ws "$WS2" --stage harvest --done srcA srcB >/dev/null \
  && ok "progress: records units on a fresh workspace" || err "progress failed on fresh workspace"
out=$(python3 "$DP" resume --ws "$WS2")
echo "$out" | jget 'd["next_stage"]' | grep -q harvest && ok "progress: run stays at the in-progress stage" || err "progress moved next_stage"
echo "$out" | jget 'd["progress"]["harvest"]["done"]' | grep -q "srcA" \
  && ok "progress: resume returns the recorded units" || err "resume missing progress units"
# Idempotent per unit; merge preserves existing checkpoint state.
printf '{"stage":"start","next_stage":"harvest","run_state":{"framework":"F2"}}' | python3 "$DP" checkpoint --ws "$WS2" - >/dev/null
python3 "$DP" progress --ws "$WS2" --stage harvest --done srcA srcC >/dev/null
out=$(python3 "$DP" resume --ws "$WS2")
n=$(echo "$out" | jget 'len(d["progress"]["harvest"]["done"])')
[ "$n" = "2" ] && ok "progress: idempotent per unit (srcA not duplicated)" || err "progress duplicated a unit (count=$n)"
echo "$out" | jget 'd["run_state"]["framework"]' | grep -q F2 \
  && ok "progress: merge preserves run_state in the checkpoint" || err "progress clobbered run_state"
# A completed stage's checkpoint clears its sub-stage progress; later progress
# for a passed stage is refused.
printf '{"stage":"consume","next_stage":"interview"}' | python3 "$DP" checkpoint --ws "$WS2" - >/dev/null
python3 "$DP" resume --ws "$WS2" | grep -q '"progress"' \
  && err "stage completion did not clear sub-stage progress" || ok "progress: stage completion clears sub-stage progress"
python3 "$DP" progress --ws "$WS2" --stage harvest --done srcD 2>&1 | grep -q 'points past it' \
  && ok "progress: refuses a stage the run has completed" || err "progress accepted a passed stage"
printf '{"stage":"variants","next_stage":"done"}' | python3 "$DP" checkpoint --ws "$WS2" - >/dev/null
python3 "$DP" progress --ws "$WS2" --stage fill --done s1 2>&1 | grep -q 'cannot reopen' \
  && ok "progress: refuses to reopen a done run" || err "progress reopened a done run"

# --- Stage-3 per-section progress (Story 13.84, #388) -----------------------
WS3="$work/ws3"; mkdir -p "$WS3"
# After the interview completes (next_stage: fill), fill sections record.
printf '{"stage":"interview","next_stage":"fill","run_state":{"framework":"F2"}}' | python3 "$DP" checkpoint --ws "$WS3" - >/dev/null
python3 "$DP" progress --ws "$WS3" --stage fill --done scope the-map >/dev/null \
  && ok "fill: sections record against next_stage=fill" || err "fill progress refused mid-stage"
out=$(python3 "$DP" resume --ws "$WS3")
echo "$out" | jget 'd["progress"]["fill"]["done"]' | grep -q 'the-map' \
  && ok "fill: resume lists completed sections" || err "resume missing fill sections"
echo "$out" | jget 'd["run_state"]["framework"]' | grep -q F2 \
  && ok "fill: run_state survives section recording" || err "fill progress clobbered run_state"
# Stage-3 completion clears fill progress.
printf '{"stage":"provenance","next_stage":"quality-gate"}' | python3 "$DP" checkpoint --ws "$WS3" - >/dev/null
python3 "$DP" resume --ws "$WS3" | grep -q '"progress"' \
  && err "stage-3 completion did not clear fill progress" || ok "fill: stage completion clears section progress"

# SKILL wires per-section fill recording (13.84): unit = section + provenance.
grep -q 'Per-section progress recording' "$SKILL" && grep -q 'stage fill' "$SKILL" \
  && ok "SKILL documents per-section fill recording (13.84)" || err "SKILL missing fill progress contract"
grep -q 'never recorded before both writes land' "$SKILL" \
  && ok "SKILL orders draft+map writes before the section boundary" || err "SKILL missing section write-first rule"
grep -q 'reuse the persisted draft and map' "$SKILL" \
  && ok "SKILL resume reuses persisted sections (no regeneration)" || err "SKILL missing fill resume-skip"
grep -q 'appended per section as the fill progresses' "$SKILL" \
  && ok "SKILL provenance map maintained incrementally" || err "provenance map still stage-end-only"

# SKILL documents sub-stage progress; harvest SKILL states the write-first rule.
grep -q 'Sub-stage progress' "$SKILL" && grep -q 'progress --ws' "$SKILL" \
  && ok "SKILL documents sub-stage progress recording (13.83)" || err "SKILL missing sub-stage progress"
grep -qi 'artifacts are durably written' "$SKILL" \
  && ok "SKILL states the artifacts-before-recording order" || err "SKILL missing write-first rule"
HSKILL="skills/harvest/SKILL.md"
grep -q 'progress --ws' "$HSKILL" && grep -q 'progress.harvest.done' "$HSKILL" \
  && ok "harvest SKILL wires per-source progress + resume skip" || err "harvest SKILL missing progress contract"
grep -qi 'sheet write comes first' "$HSKILL" \
  && ok "harvest SKILL orders sheet-append before recording" || err "harvest SKILL missing append-first order"

# SKILL documents the durability contract.
grep -qi 'checkpoint' "$SKILL" && grep -qi 'resume from the last completed' "$SKILL" \
  && ok "SKILL documents checkpoint/resume durability" || err "SKILL missing durability contract"
grep -qi 'resumption is .*automatic\|automatic, not opt-in' "$SKILL" && grep -qi 'autostart' "$SKILL" \
  && ok "SKILL wires automatic resume via autostart (Story 13.12)" || err "SKILL missing automatic-resume/autostart"
grep -qi 'never re-runs a completed stage' "$SKILL" && ok "SKILL states resume never re-runs a completed stage" || err "SKILL missing idempotent-resume note"

if [ "$fail" -eq 0 ]; then
  printf '\nAll checkpoint/resume checks passed.\n'; exit 0
else
  printf '\ncheckpoint/resume checks FAILED.\n' >&2; exit 1
fi
