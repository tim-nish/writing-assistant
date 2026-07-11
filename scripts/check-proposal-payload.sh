#!/usr/bin/env sh
# check-proposal-payload.sh — verify payload integrity validation blocks a
# damaged proposal prompt before presentation (Story 10.1, contract (e)).
# POSIX shell + stdlib Python.
#
# Covers: a clean payload passes; a payload with a MISSING Effect line is
# blocked (dogfood seeded defect 1); a field truncated mid-sentence is blocked
# (dogfood seeded defect 2); an over-budget field is blocked (re-author, never
# clip); and the block is a non-zero exit, like verify-markers gating a stage.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

V="$root/scripts/validate-proposal-payload.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
# blocks JSON MSG : expect non-zero exit
blocks() { printf '%s' "$1" | python3 "$V" >/dev/null 2>&1 && err "$2 (payload was NOT blocked)" || ok "$2"; }
passes() { printf '%s' "$1" | python3 "$V" >/dev/null 2>&1 && ok "$2" || err "$2 (clean payload was blocked)"; }

python3 -c "import py_compile; py_compile.compile('$V', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

CLEAN='{"items":[{"where":"Section 2 (Evidence)","why":"the key result is not stated","choices":[{"label":"approve","effect":"keep the section as drafted"},{"label":"modify","effect":"rewrite the section from your answer"}]}]}'
passes "$CLEAN" "clean payload is presentable"

# Seeded defect 1: a choice with a missing Effect line.
NOEFFECT='{"items":[{"where":"Section 2","why":"the key result is not stated","choices":[{"label":"approve"}]}]}'
blocks "$NOEFFECT" "missing Effect line blocks presentation"

# Seeded defect 2: a field truncated mid-sentence (ellipsis).
TRUNC='{"items":[{"where":"Section 2","why":"the key result is not stated and the","choices":[{"label":"approve","effect":"keep the section as drafted…"}]}]}'
blocks "$TRUNC" "mid-sentence truncation (ellipsis) blocks presentation"

# Empty field blocks.
EMPTY='{"items":[{"where":"","why":"x","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$EMPTY" "empty Where field blocks presentation"

# No choices at all blocks (selective presentation requires options).
NOCHOICES='{"items":[{"where":"Section 2","why":"the key result is not stated","choices":[]}]}'
blocks "$NOCHOICES" "a proposal with no choices blocks presentation"

# Over-budget field blocks (must be re-authored shorter, never clipped).
LONG=$(python3 -c "print('x'*300)")
OVER='{"items":[{"where":"'"$LONG"'","why":"y","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$OVER" "over-budget field blocks (re-author, do not clip)"

if [ "$fail" -eq 0 ]; then
  printf '\nAll proposal-payload checks passed.\n'; exit 0
else
  printf '\nproposal-payload checks FAILED.\n' >&2; exit 1
fi
