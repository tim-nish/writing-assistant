#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/draft-pipeline.py scripts/draft_resume.py
# removal-signal: gate emission is routed through the single emitter Story
#   20.118 (#1114) builds, and the per-run gate-inventory assertion of 20.119
#   covers every gate rather than this one — at that point the ask_emitted and
#   render_control assertions here are the inventory's subject, and what is
#   left (the cmd_stage0 guard) folds into check-checkpoint-resume.sh.
# check-stage0-resume-confirmation.sh — the sitting-boundary gate FIRES rather
# than crashing (Story 20.111, #1119).
#
# WHY THIS EXISTS AT STAGE 0 AND NOT AT THE BUILDER. Story 20.104 (#1082)
# shipped the confirmation shape and it was correct; what was never exercised
# is the path from `_autostart` THROUGH `cmd_stage0`, where the non-resumed
# branch indexed `out["ws"]` — a key the confirmation shape does not carry —
# and raised `KeyError: 'ws'`. A builder-level assertion cannot see that: the
# payload it builds is fine. The defect lives in the caller, so the check has
# to run the caller.
#
# Reachable any time an in-progress run predates the sitting, which is the
# common case rather than an edge one.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$work" <<'PY' || { err "stage-0 resume-confirmation harness did not run"; printf '\nFAILED.\n' >&2; exit 1; }
import importlib.util, json, os, sys
work = sys.argv[1]
sys.path.insert(0, "scripts")
spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
dr = dp._load("draft_resume.py")

report = {}

# 1. The shape itself: no top-level `ws`, which is the premise of the crash.
ws = os.path.join(work, "candidate"); os.makedirs(ws, exist_ok=True)
out = dr.confirmation("20260718T101010-000001", ws,
                      {"next_stage": "harvest"}, "predates the sitting")
report["no_ws_key"] = "ws" not in out
report["flagged"] = out.get("resume_requires_confirmation") is True
report["candidate_ws"] = out.get("candidate_ws") == ws

# 2. The contract states the candidate's id AND age (#1082).
report["states_id"] = out.get("candidate_run_id") == "20260718T101010-000001"
report["states_age"] = isinstance(out.get("age_days"), int)

# 3. The gate declares its render form (Story 20.107) and is within capacity.
item = (out.get("items") or [{}])[0]
render = item.get("render") or {}
report["render_control"] = render.get("control") == "selection"
report["within_capacity"] = 0 < len(item.get("choices") or []) <= 4

# 4. The ask is RECORDED, not merely printed — a gate that leaves no event is
#    the absence-shape #1081 names.
plog = os.path.join(ws, "presented-payloads.jsonl")
rows = []
if os.path.isfile(plog):
    rows = [json.loads(l) for l in open(plog, encoding="utf-8") if l.strip()]
report["ask_emitted"] = any(r.get("gate") == "resume-confirmation" for r in rows)

# 5. THE CRASH ITSELF, asserted against the SHIPPED source rather than a
#    re-implementation of it. An earlier form of this check rebuilt the
#    branch here and passed on the pre-fix tree, because the harness's own
#    `if` short-circuited exactly where the bug was not. What must hold is a
#    property of `cmd_stage0`: the confirmation shape is handled BEFORE
#    anything indexes `out["ws"]`.
src = open("scripts/draft-pipeline.py", encoding="utf-8").read()
guard = 'out.get("resume_requires_confirmation")'
index = '_write_checkpoint(out["ws"]'
gi, ii = src.find(guard), src.find(index)
report["stage0_guards_before_index"] = gi != -1 and ii != -1 and gi < ii
# and the guard RETURNS rather than falling through
between = src[gi:ii] if (gi != -1 and ii != -1 and gi < ii) else ""
report["stage0_guard_returns"] = "return 0" in between

report["no_checkpoint_written"] = not os.path.isfile(
    os.path.join(ws, "checkpoint.json"))

# 6. A checkpoint-less workspace holding an ask log is VISIBLE to the resume
#    scan — the knock-on that orphaned a workspace on the observed run.
report["scan_sees_asklog"] = "presented-payloads.jsonl" in src.split(
    "def _autostart")[1][:4000]

json.dump(report, open(os.path.join(work, "report.json"), "w"))
PY

r="$work/report.json"
for k in no_ws_key flagged candidate_ws states_id states_age render_control \
         within_capacity ask_emitted stage0_guards_before_index \
         stage0_guard_returns no_checkpoint_written scan_sees_asklog; do
  v=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "$r" "$k")
  if [ "$v" = "True" ]; then
    ok "$k"
  else
    case "$k" in
      stage0_guards_before_index)
        err "cmd_stage0 indexes out[\"ws\"] with no resume_requires_confirmation guard ahead of it — the sitting-boundary gate (Story 20.104, #1082) dies with KeyError instead of asking (#1119)" ;;
      stage0_guard_returns)
        err "cmd_stage0 detects the confirmation shape but falls through instead of returning — the gate must STOP the run, not annotate it" ;;
      ask_emitted)
        err "the resume gate left no row in presented-payloads.jsonl — a gate that only prints has no evidence it fired (#1081/#1114)" ;;
      no_checkpoint_written)
        err "a checkpoint was written for a run the owner has not adopted — recording the ask must never attach to the candidate run" ;;
      scan_sees_asklog)
        err "_autostart's resume scan still skips a checkpoint-less workspace holding an ask log, so a retry mints a second run and strands the owner's answers (#1119)" ;;
      states_age)
        err "the confirmation does not state the candidate's AGE, which the #1082 contract requires alongside its id" ;;
      *)
        err "$k" ;;
    esac
  fi
done

if [ "$fail" -eq 0 ]; then
  printf '\nOK: the sitting-boundary gate fires, records its ask, and adopts nothing.\n'
else
  printf '\nstage0 resume-confirmation checks FAILED.\n' >&2
fi
exit "$fail"
