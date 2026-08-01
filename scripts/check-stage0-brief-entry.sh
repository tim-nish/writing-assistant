#!/usr/bin/env sh
# parallel-safe
# tier: full — end-to-end stage0 invocations over a fixture host repo (#913)
# covers: scripts/draft-pipeline.py scripts/draft_brief.py
# removal-signal: the brief-carrying entry path is retired, or resume
#   candidacy moves wholly into draft_resume.py and its own check asserts the
#   same-brief predicate — at that point this file duplicates it and goes.
# check-stage0-brief-entry.sh — a brief-carrying stage-0 entry resumes only a
# run minted from the SAME brief (amended 2026-08-02, #1207).
#
# THE INCIDENT: on 2026-08-01 the terrain handoff completed with a freshly
# adopted brief, and workspace autostart resumed a 5h03m-old run carrying a
# DIFFERENT thesis — then the resume-confirmation gate fired AFTER the resume.
# The ratified automatic-resume default was designed for a COLD invocation and
# the handoff path inherited it unexamined. Identity is the recorded brief pin,
# never text similarity; the mismatch branch is `--fresh`'s exact semantics
# applied by data, and cold invocations are untouched.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
printf 'sources:\n  - path: .\n' > "$host/writing-sources.yaml"
export XDG_STATE_HOME="$work/state"

# 1. Mint run A from brief X; it checkpoints its brief with a pin.
outA=$(python3 "$DP" stage0 F2 specs/ --root "$host" --brief "brief X: the terrain thesis")
wsA=$(echo "$outA" | jget 'd["ws"]')
runA=$(echo "$outA" | jget 'd["run_id"]')
python3 - "$wsA" <<'PY' && ok "a minted run's checkpoint records its brief with a content pin (#1207)" || err "the minted run's checkpoint carries no brief pin — the same-brief branch has nothing to read"
import json, sys
b = json.load(open(sys.argv[1] + "/checkpoint.json")).get("brief") or {}
assert b.get("pin", "").startswith("sha256:"), b
PY

# 2. A different-brief entry mints fresh: run A skipped as fresh_skipped with
#    its fresh_note, nothing deleted, no owner keystroke.
outB=$(python3 "$DP" stage0 F2 specs/ --root "$host" --brief "brief Y: something else entirely")
echo "$outB" | jget 'd["resumed"]' | grep -q False \
  && ok "a different-brief entry does not resume the in-progress run" \
  || err "a different-brief entry resumed a run minted from another brief"
echo "$outB" | jget 'd["fresh_skipped"]' | grep -q "$runA" \
  && ok "...the skipped run is returned as fresh_skipped" \
  || err "the skipped run id is not reported as fresh_skipped"
echo "$outB" | jget 'd["fresh_note"]' | grep -q "different brief" \
  && ok "...with a fresh_note naming the same-brief-only cause" \
  || err "the fresh_note does not say the run was minted from a different brief"
[ -f "$wsA/checkpoint.json" ] \
  && ok "...and nothing is deleted: run A stays resumable" \
  || err "run A's checkpoint is gone — the skip deleted state"

# 3. The SAME brief resumes the newest same-brief run, with the disclosure.
runB=$(echo "$outB" | jget 'd["run_id"]')
outC=$(python3 "$DP" stage0 F2 specs/ --root "$host" --brief "brief Y: something else entirely")
echo "$outC" | jget 'd["resumed"]' | grep -q True \
  && ok "a same-brief entry resumes the run minted from that brief" \
  || err "a same-brief entry failed to resume its own run"
echo "$outC" | jget 'd["run_id"]' | grep -q "$runB" \
  && ok "...and it is the run minted from that brief" \
  || err "the resumed run is not the one minted from the same brief"
echo "$outC" | jget 'd["resume_disclosure"]' | grep -q "$runB" \
  && ok "...with the turn-one resume disclosure intact (Story 19.10)" \
  || err "the same-brief resume lost its turn-one disclosure"

# 4. A cold invocation (no --brief) is unchanged: it resumes the newest
#    in-progress run unconditionally, exactly as before.
outD=$(python3 "$DP" stage0 F2 specs/ --root "$host")
echo "$outD" | jget 'd["resumed"]' | grep -q True \
  && ok "a cold invocation still resumes the newest in-progress run" \
  || err "the cold path changed — it must stay byte-identical"
echo "$outD" | jget 'd["run_id"]' | grep -q "$runB" \
  && ok "...the newest, with no brief filtering applied" \
  || err "the cold path did not pick the newest in-progress run"

# 5. `autostart` carries the same contract as the folded stage0.
outE=$(python3 "$DP" autostart --root "$host" --brief "brief Z: a third direction")
echo "$outE" | jget 'd["resumed"]' | grep -q False \
  && ok "autostart --brief applies same-brief-only too" \
  || err "autostart --brief resumed a run minted from another brief"
echo "$outE" | jget 'd["fresh_note"]' | grep -q "different brief" \
  && ok "...with the same-brief-only fresh_note" \
  || err "autostart's fresh_note does not name the cause"

[ "$fail" -eq 0 ] && printf '\nAll stage0 brief-entry checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
