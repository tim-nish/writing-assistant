#!/usr/bin/env sh
# parallel-safe
# tier: full — end-to-end probe invocations over a fixture host repo (#913)
# covers: scripts/probe.py skills/draft-article/**
# grep-binding: file-set (#1325) — the resume-contract sentence and the
#   harvest-consume denial read the skill's whole file set (SKILL.md + stages/
#   companions); 'next_stage: probe' is a state-field token, durable wherever
#   it sits in that set.
# removal-signal: stage 1 stops being probe (a later amendment replaces or
#   folds it), at which point these assertions have no subject and retire with
#   the stage.
# check-probe.sh — probe is the stage-1 CONFIGURATION AND PERMISSION CHECK
# (Story 20.154, #1224; was a feasibility verdict + anchors + coverage ledger
# at Story 20.146, #1210).
#
# WHAT CHANGED AND WHY THE OLD ASSERTIONS ARE GONE RATHER THAN RELAXED. The
# 2026-08-02 amendment (#1224) retires the verdict, the anchors and the
# coverage ledger together: `stage1.md` demanded "anchors, never an extraction
# pass" AND a ledger accounting for every declared source, which cannot both
# hold, and the second read 168 files to certify an empty result. Assertions
# about a verdict that no longer exists have no subject — keeping them
# weakened would be worse than deleting them, because a check nobody can fail
# still reads as coverage.
#
# THE TIME BUDGET IS ASSERTED HERE, not hoped for: #1224 observed that no
# performance budget existed anywhere and the only cost language was relative
# ("a fraction of harvest's cost"), which bounds nothing once harvest is gone.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

PR="$root/scripts/probe.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$PR', doraise=True)" \
  && ok "probe compiles" || { err "probe syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host/docs"
git -C "$host" init -q
printf 'one\ntwo\nthree\n' > "$host/docs/a.md"
git -C "$host" add -A
git -C "$host" -c user.email=t@t -c user.name=t commit -qm seed
sha=$(git -C "$host" rev-parse --short HEAD)
printf 'sources:\n  - path: docs\n' > "$host/writing-sources.yaml"
WS="$work/ws"; mkdir -p "$WS"

# --- the permission check: three questions and no fourth (AC1, AC3) ---------
python3 "$PR" check --root "$host" > "$work/check.json"
python3 - "$work/check.json" <<'PY' && ok "check: the declaration resolves and every granted root is readable" || err "the permission check does not report the grant"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["stage"] == "probe", d
assert d["ok"] is True, d
assert d["declared"], d
assert d["unreadable"] == [], d
# NO verdict, NO anchors, NO coverage ledger — the three the amendment retires.
for gone in ("verdict", "anchors", "coverage", "reasons"):
    assert gone not in d, f"{gone!r} survives in the probe result: {d}"
PY

# --- the time budget is a CONTRACT (AC2) ------------------------------------
python3 - "$work/check.json" <<'PY' && ok "check: completes inside the declared stage-1 time budget" || err "the permission check exceeded its declared budget"
import importlib.util, json, sys
d = json.load(open(sys.argv[1]))
spec = importlib.util.spec_from_file_location("probe", "scripts/probe.py")
probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
assert d["budget_s"] == probe.TIME_BUDGET_S, (d, probe.TIME_BUDGET_S)
assert d["elapsed_s"] <= probe.TIME_BUDGET_S, d
assert d["over_budget"] is False, d
PY

# --- no enumeration: probe does not walk the declared files (AC3) -----------
grep -q "enumerate_files" "$PR" \
  && err "probe still enumerates declared files — that is the cost #1224 removes,
      and examine is where reading now happens, per claim" \
  || ok "probe enumerates no files: no surface pass, no anchor hunt"
grep -q "def surface" "$PR" \
  && err "probe still exposes a surface subcommand — the coverage denominator
      is retired with the ledger that needed it" \
  || ok "the surface subcommand is gone with the ledger it fed"

# --- an unreadable grant is the ONE thing that stops the run (AC1) ----------
mkdir -p "$host/secret"
printf 'sources:\n  - path: docs\n  - path: secret\n' > "$host/writing-sources.yaml"
chmod 000 "$host/secret" 2>/dev/null || true
if [ -r "$host/secret" ]; then
  ok "SKIPPED: unreadable-grant case (running as a user that bypasses mode bits)"
else
  python3 "$PR" record --ws "$WS" --root "$host" >/dev/null 2>&1 \
    && err "a grant the run cannot read was accepted" \
    || ok "refused: a granted source that cannot be read stops the run, named"
fi
chmod 755 "$host/secret" 2>/dev/null || true
printf 'sources:\n  - path: docs\n' > "$host/writing-sources.yaml"

# --- record routes onward, because there is no verdict left to stop on ------
python3 "$PR" record --ws "$WS" --root "$host" > "$work/rec.json"
python3 - "$work/rec.json" "$WS" <<'PY' && ok "record: routes to interview and writes no verdict to the checkpoint" || err "record did not route, or left a verdict behind"
import json, sys, os
d = json.load(open(sys.argv[1])); ws = sys.argv[2]
assert d["next_stage"] == "interview", d
cp = json.load(open(os.path.join(ws, "checkpoint.json")))
assert cp["next_stage"] == "interview", cp
# The key is REMOVED, not blanked: a key carrying "no verdict" reads as a
# verdict to every consumer that tests for its presence.
assert "probe_verdict" not in cp, cp
PY

WS2="$work/ws2"; mkdir -p "$WS2"
python3 "$PR" record --ws "$WS2" --root "$host" --framework working-note > "$work/rec2.json"
python3 - "$work/rec2.json" <<'PY' && ok "record: the slim profile still routes past the interview" || err "the slim profile lost its routing"
import json, sys
assert json.load(open(sys.argv[1]))["next_stage"] == "fill"
PY

# --- checkpoint/resume contract is declared (AC4) ----------------------------
# The skill is SKILL.md plus its stages/ companions; the contract is declared
# wherever in that set it sits (#1322/#1325), so the assertion reads the set
# rather than one file.
grep -rq "Checkpoint/resume contract" skills/draft-article/ \
  && ok "the skill declares probe's checkpoint/resume contract" \
  || err "stage 1 declares no resume contract — an interruptible stage without one is a gap"
grep -rq "next_stage: probe" skills/draft-article/ \
  && ok "...naming where an interrupted probe resumes" || err "...that names no resume point"

# --- stage wiring: the mint points at probe, no consume step at stage 1 ------
python3 - <<'PY' && ok "the stage-0 mint routes a fresh run to probe" || err "the fresh-run mint does not point at probe"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
state, code = dp._run_state("F2", ["docs/"], None)
assert state["next_stage"] == "probe", state
PY
grep -rq "consume <harvest-doc>" skills/draft-article/ \
  && err "the skill still instructs consuming a harvest document" \
  || ok "no stage instructs consuming a harvest document (#1182)"

[ "$fail" -eq 0 ] && printf '\nAll probe checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
