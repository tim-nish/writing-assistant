#!/usr/bin/env sh
# check-story-element-selection.sh — verify CAP-9 story-element selection: the
# element model (evidence cluster + stable id) and the #428 disclosure-only rule
# (Story 18.8, SPEC-article-draft-pipeline CAP-9 added 2026-07-20, umbrella #428).
# POSIX shell + stdlib only. No implementation of consumption (#430/18.9) or the
# named pin (#431/18.10) is asserted here — those are separate stories.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/draft-article/SKILL.md"
SUMMARY="skills/completion-summary.md"
F2="skills/draft-article/frameworks/F2-engineering-lessons.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

for f in "$SKILL" "$SUMMARY" "$F2"; do
  [ -f "$f" ] || { err "missing file: $f"; }
done
[ "$fail" -eq 0 ] || { printf '\nstory-element-selection checks FAILED (missing files).\n' >&2; exit 1; }

# These are hard-wrapped prose files: a load-bearing phrase can straddle a line
# break, and markdown bold markers sit mid-phrase. Normalize each file to a
# single space-joined, marker-stripped stream so a phrase match is wrap-immune.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
norm "$SKILL"   > "$work/skill.txt";   SKILL="$work/skill.txt"
norm "$SUMMARY" > "$work/summary.txt"; SUMMARY="$work/summary.txt"
norm "$F2"      > "$work/f2.txt";      F2="$work/f2.txt"

# --- 1. The element model is defined in the SKILL --------------------------------
grep -qi 'story element' "$SKILL" && grep -qi 'evidence cluster' "$SKILL" \
  && ok "SKILL defines the story element as an evidence cluster" \
  || err "SKILL missing the story-element / evidence-cluster model"

grep -qiE 'declared,? deterministic' "$SKILL" \
  && ok "SKILL: cluster membership is a declared, deterministic rule" \
  || err "SKILL missing the deterministic-membership rule"

grep -qi 'never a taste judgment' "$SKILL" \
  && ok "SKILL: membership is never a taste judgment" \
  || err "SKILL missing the not-a-taste-judgment invariant"

# --- 2. Identity: the id is authority, the pointer set is derived payload ---------
grep -qi 'stable id' "$SKILL" \
  && ok "SKILL: each element carries a stable id" \
  || err "SKILL missing the stable-id property"

grep -qi 'id is identity' "$SKILL" && grep -qi 'derived payload' "$SKILL" \
  && ok "SKILL: id is identity, the evidence-pointer set is derived payload" \
  || err "SKILL missing the id-is-identity / pointer-set-is-payload relation"

grep -qi 'pointer drift' "$SKILL" && grep -qi 'never changes identity' "$SKILL" \
  && ok "SKILL: pointer drift on re-harvest never changes identity" \
  || err "SKILL missing the drift-preserves-identity rule"

# Story 18.35/#529: the "stable id" is not merely asserted — it is DERIVED by a
# concrete, reproducible rule the SKILL documents and a helper implements.
grep -qi 'element-id' "$SKILL" && grep -qiE 'declared membership anchor|membership anchor' "$SKILL" \
  && ok "SKILL: the stable id is derived from the declared membership anchor (element-id)" \
  || err "SKILL asserts stability but gives no reproducible id-derivation rule"
# The helper reproduces byte-identically and is anchor-keyed (identity == anchor).
W="$root/scripts/write-article-plan.py"
python3 - "$W" <<'PYEOF' && ok "element-id helper: derivation is reproducible and anchor-keyed" || err "element-id helper is not deterministic"
import json, subprocess, sys
W = sys.argv[1]
def eid(a):
    return json.loads(subprocess.run([sys.executable, W, "element-id", a],
                      capture_output=True, text=True).stdout)["elements"][0]["id"]
assert eid("Weak driver") == eid("Weak driver") == "el-weak-driver"   # reproducible
assert eid("weak-driver") == eid("el-weak-driver") == "el-weak-driver"  # spellings reconcile
assert eid("kill switch") != eid("weak driver")                       # distinct anchors, distinct ids
PYEOF

# --- 3. Selection is upstream of the argument plan, and disclosure-only ----------
grep -qi 'upstream of the argument plan' "$SKILL" \
  && ok "SKILL: selection is upstream of the argument plan (CAP-3/#440)" \
  || err "SKILL missing the upstream-of-argument-plan ordering"

grep -qi 'disclosure' "$SKILL" \
  && grep -qiE 'changes .*nothing|nothing about what gets selected|base selection behavior' "$SKILL" \
  && ok "SKILL: #428 is disclosure-only — the base selection behavior is unchanged" \
  || err "SKILL missing the disclosure-only invariant"

# --- 4. Disclosure lands in BOTH the interview journal and completion summary -----
# In the journal section, per selected element, the rule that selected it.
grep -qi 'per selected story element' "$SKILL" \
  && grep -qi 'the rule that selected it' "$SKILL" \
  && ok "SKILL journal records, per selected element, the rule that selected it" \
  || err "SKILL journal missing the per-element selection-rule disclosure"

# The completion summary repeats it.
grep -qi 'story element' "$SUMMARY" \
  && grep -qiE 'selected|selection' "$SUMMARY" \
  && ok "completion summary discloses which elements were selected and why" \
  || err "completion summary missing the per-element selection disclosure"

grep -qi 'disclosure' "$SUMMARY" \
  && ok "completion summary states it is disclosure, not a decision" \
  || err "completion summary missing the disclosure-only note"

# --- 5. F2 names lessons as story elements with a stable id ----------------------
grep -qi 'story element' "$F2" && grep -qi 'stable id' "$F2" \
  && ok "F2 names each lesson as a story element with a stable id" \
  || err "F2 missing the lesson-is-a-story-element note"

# --- 6. Scope guard: 18.8 does not implement consumption (#430) or the pin (#431).
# The model may reference them as forward hooks, but the disclosure story must not
# claim to record consumption or resolve a named pin. This keeps the story files'
# supersedes boundaries honest.
if grep -qiE 'records? .*consumed .*by id|consumption .*(recorded|exclusion) (in|is)' "$SUMMARY"; then
  err "completion summary appears to implement consumption (#430) — that is story 18.9"
else
  ok "scope: completion summary does not implement consumption (#430/18.9)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll story-element-selection checks passed.\n'; exit 0
else
  printf '\nstory-element-selection checks FAILED.\n' >&2; exit 1
fi
