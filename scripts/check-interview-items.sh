#!/usr/bin/env sh
# check-interview-items.sh — verify the interview-item schema validator
# (Story 14.3, SPEC-policy-source-seam CAP-3; seam-formats.md §2).
# POSIX shell + stdlib Python only.
#
# Covers: each rejection class R1-R5 has a fixture the validator fails with
# that class named; a valid item set (generic + tension items) passes; and the
# Stage-2 gate — `draft-pipeline.py interview --items` validates BEFORE triage,
# so an invalid item set halts the stage with no triage output.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VAL="scripts/validate-interview-items.py"
PIPE="scripts/draft-pipeline.py"
FIX="scripts/fixtures/interview-items"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$VAL', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# --- 1. Valid set passes silently ---------------------------------------------
set +e; out=$(python3 "$VAL" "$FIX/valid.json" 2>&1); rc=$?; set -e
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "valid set (generic + 2 tension items) passes silently" \
  || err "valid set: rc=$rc out='$out'"

# --- 2. Each rejection class fails its fixture, naming the class ----------------
expect() { # fixture, class, description
  set +e; msg=$(python3 "$VAL" "$FIX/$1" 2>&1 >/dev/null); rc=$?; set -e
  [ "$rc" -eq 1 ] && printf '%s' "$msg" | grep -q "$2:" \
    && ok "$1 -> $2 ($3)" || err "$1: expected $2, rc=$rc msg='$msg'"
}
expect r1-prefilled-answer.json   R1 "pre-filled owner_answer"
expect r2-tension-without-seed.json R2 "tension item without seed"
expect r2-seed-on-non-tension.json  R2 "policy seed on a non-tension type"
expect r3-bad-pointer.json        R3 "q_a pointer + unpinned pointer"
expect r4-confirmation.json       R4 "confirmation-shaped seeded question"
expect r5-unknown-gap-type.json   R5 "unknown gap_type"

# #299 — whole-surface authoring: a tension raised despite a same-surface
# resolving line must carry it in `seed.companion`, held to the seed's own
# quote+pinned-pointer rule.
set +e; out=$(python3 "$VAL" "$FIX/valid-companion.json" 2>&1); rc=$?; set -e
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "a tension carrying its resolving companion line passes" \
  || err "valid-companion: rc=$rc out='$out'"
expect r3-companion-bad-pointer.json R3 "companion pointer unpinned"

# r3 covers BOTH failure shapes: out-of-whitelist and unpinned.
set +e; msg=$(python3 "$VAL" "$FIX/r3-bad-pointer.json" 2>&1 >/dev/null); set -e
n=$(printf '%s\n' "$msg" | grep -c 'R3:' || true)
[ "$n" -eq 2 ] && ok "R3 catches out-of-whitelist AND unpinned pointers" \
  || err "R3 expected 2 rejections, got $n"

# --- 3. stdin form -------------------------------------------------------------
set +e; printf '[]' | python3 "$VAL" - >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 0 ] && ok "empty set from stdin passes" || err "stdin form rc=$rc"

# --- 4. The Stage-2 gate: validation runs BEFORE triage --------------------------
state='{"stage":"consume","fact_sheet":[],"needs_owner":[]}'
set +e
out=$(printf '%s' "$state" | python3 "$PIPE" interview --framework F1 \
      --items "$FIX/r1-prefilled-answer.json" - 2>"$root/.r1err"); rc=$?
msg=$(cat "$root/.r1err"); rm -f "$root/.r1err"
set -e
[ "$rc" -eq 1 ] && [ -z "$out" ] && printf '%s' "$msg" | grep -q 'R1:' \
  && printf '%s' "$msg" | grep -q 'triage not run' \
  && ok "invalid items halt interview BEFORE triage (no triage output)" \
  || err "gate: rc=$rc out-present=$([ -n \"$out\" ] && echo yes || echo no) msg='$msg'"

set +e
out=$(printf '%s' "$state" | python3 "$PIPE" interview --framework F1 \
      --items "$FIX/valid.json" - 2>/dev/null); rc=$?
set -e
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"policy-seed"' \
  && ok "valid items pass the gate and join the interview (rationale policy-seed)" \
  || err "valid items through interview: rc=$rc"

# without --items, behavior is unchanged (no policy-seed rationale)
out=$(printf '%s' "$state" | python3 "$PIPE" interview --framework F1 - 2>/dev/null)
printf '%s' "$out" | grep -q '"policy-seed"' \
  && err "no-items run leaked a policy-seed rationale" \
  || ok "no --items: interview output unchanged"

if [ "$fail" -eq 0 ]; then
  printf '\nAll interview-item checks passed.\n'; exit 0
else
  printf '\ninterview-item checks FAILED.\n' >&2; exit 1
fi
