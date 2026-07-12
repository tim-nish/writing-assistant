#!/usr/bin/env sh
# check-quality-gate.sh — verify the mandatory Stage 3→4 quality gate with
# bounded retry (Story 11.4). POSIX shell + stdlib Python.
#
# Covers: the gate is a stage-progression precondition (non-zero exit blocks),
# not an advisory finding (AC1); dimension 4 is checked mechanically (zero
# tokens) and dims 1-3 come from the single-pass judge (AC2); a fact-sheet-
# stitched draft (all sourced, no derived/narration tissue) fails and does not
# reach stage 4 unrevised (AC-final); and the SKILL states the bounded ≤2
# revision cycles re-running BOTH gates, the publish-blocker surface, and the
# NFR12 owner-approved-content protection (AC3/AC4).

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

# A clean, well-mixed draft + map + all-pass judge verdicts.
cat > "$work/good.md" <<'MD'
# The one claim

Structured discovery halved our token bill. We measured it across the suite.
The mechanism was simple. Fewer redundant reads meant fewer prompt tokens.

## Evidence

The bench recorded a 2x drop. That number held across three runs.
MD
cat > "$work/good-map.txt" <<'MAP'
P1.S1: sourced <- fs-1
P1.S2: derived <- fs-1, fs-2
P1.S3: narration
P2.S1: sourced <- fs-3
MAP
printf 'dim1: pass\ndim2: pass\ndim3: pass\n' > "$work/judge-pass.txt"

# AC1/AC2 — clean draft + all dims pass -> gate passes (exit 0).
out=$(python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-pass.txt")
echo "$out" | jget 'd["pass"]' | grep -q True && ok "a clean, well-mixed draft passes the gate" || err "clean draft failed the gate"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-pass.txt" >/dev/null 2>&1 \
  && ok "gate exits 0 on pass" || err "gate non-zero on a passing draft"

# AC1 — a judge fail on any dimension BLOCKS (non-zero exit): it is a precondition.
printf 'dim1: fail — opening states a topic, not a claim\ndim2: pass\ndim3: pass\n' > "$work/judge-fail.txt"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-fail.txt" >/dev/null 2>&1 \
  && err "a failing dimension did not block" || ok "a failing judged dimension blocks stage 4 (precondition)"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-fail.txt" \
  | jget '"dim1" in d["failing_dimensions"]' | grep -q True && ok "names the failing dimension" || err "failing dimension not named"

# AC2 — dimension 4 is mechanical (zero tokens): with NO judge verdicts, dim4
# still evaluates; a stitched-fact-sheet map fails dim4.
cat > "$work/stitch-map.txt" <<'MAP'
P1.S1: sourced <- fs-1
P1.S2: sourced <- fs-2
P1.S3: sourced <- fs-3
MAP
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/stitch-map.txt" --judge "$work/judge-pass.txt" \
  | jget 'd["dimensions"]["dim4"]["verdict"]' | grep -q fail \
  && ok "stitched fact sheet (all sourced, no tissue) fails dimension 4 mechanically" || err "stitched fact sheet passed"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/stitch-map.txt" --judge "$work/judge-pass.txt" >/dev/null 2>&1 \
  && err "stitched fact sheet reached stage 4" || ok "stitched fact sheet does not reach stage 4 unrevised"

# A wall-of-text paragraph fails dim4 mechanically (no judge needed).
python3 -c "print('# t\n\n' + ' '.join('word%d'%i for i in range(200)) + '.')" > "$work/wall.md"
python3 "$DP" quality-gate --draft "$work/wall.md" | jget 'd["dimensions"]["dim4"]["verdict"]' | grep -q fail \
  && ok "a wall-of-text paragraph fails dim4 (mechanical)" || err "wall of text passed dim4"

# SKILL contract: precondition wording, mechanical dim4 + judged dims1-3,
# bounded ≤2 cycles re-running both gates, publish blocker, NFR12.
grep -qi 'stage-progression precondition' "$SKILL" && ok "SKILL: gate is a stage-progression precondition" || err "SKILL missing precondition wording"
grep -qi 'mechanically' "$SKILL" && grep -qi 'single-pass' "$SKILL" && ok "SKILL: dim4 mechanical, dims1-3 single-pass judge" || err "SKILL missing gate composition"
grep -qiE '2 revision cycles|at most 2' "$SKILL" && ok "SKILL: at most 2 revision cycles" || err "SKILL missing the retry bound"
grep -qi 'verify-provenance' "$SKILL" && grep -qi 're-run' "$SKILL" && ok "SKILL: revision re-runs both rubric and verify-provenance" || err "SKILL missing both-gates re-run"
grep -qi 'publish blocker' "$SKILL" && ok "SKILL: surviving failure surfaces as a publish blocker" || err "SKILL missing blocker surface"
grep -qi 'NFR12\|owner-approved content' "$SKILL" && ok "SKILL: owner-approved content never silently altered (NFR12)" || err "SKILL missing NFR12 protection"
# NFR13 extended to the CAP-7 rubric judge (#123): dims 1-3 judged in a fresh
# subagent that never saw the drafting turn, so the drafting context never grades
# its own rubric pass.
grep -qi 'fresh subagent that never saw the drafting turn' "$SKILL" \
  && grep -qi 'never grades its own rubric pass' "$SKILL" \
  && ok "SKILL: CAP-7 rubric judge runs in an isolated subagent (NFR13)" || err "SKILL missing rubric-judge isolation"

if [ "$fail" -eq 0 ]; then
  printf '\nAll quality-gate checks passed.\n'; exit 0
else
  printf '\nquality-gate checks FAILED.\n' >&2; exit 1
fi
