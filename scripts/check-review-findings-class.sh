#!/usr/bin/env sh
# check-review-findings-class.sh — verify the review finding-class contract
# (Story 13.62, SPEC-article-review). POSIX shell + stdlib Python.
#
# Covers: a writing-problem finding (Fix:) passes; a missing-input finding
# ([missing-input] + Upstream: re-harvest|ask) passes and is blocker-eligible;
# the two cross-shapes are rejected (M1 missing-input with only a Fix:, M2
# writing-problem with an Upstream:); a malformed Upstream form is rejected
# (M3); and review-prompts.md documents the class + both formats.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

V="scripts/validate-review-findings.py"
PROMPTS="skills/review-article/review-prompts.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$V', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

pass() { printf '%s\n' "$1" | python3 "$V" >/dev/null 2>&1 && ok "$2" || err "$2 (conforming finding rejected)"; }
rej()  { printf '%s\n' "$1" | python3 "$V" 2>&1 >/dev/null; }

# Conforming: a writing-problem finding with a Fix:.
WP='- [should] Section 2, para 3: the transition is abrupt. Why should: non-rubric structure/prose. Fix: add a bridging sentence.'
pass "$WP" "writing-problem finding (Fix:) passes"

# Conforming: missing-input findings with each Upstream form.
MI1='- [blocker] [missing-input] Section 3 (Evidence): the central claim has no measured result. Why blocker: quality-rubric dimension violation. Upstream: re-harvest bench/results.md'
pass "$MI1" "missing-input finding (Upstream: re-harvest) passes"
MI2='- [blocker] [missing-input] Section 4: the tradeoff is asserted with no episode behind it. Why blocker: quality-rubric dimension violation. Upstream: ask which decision this cost you the most'
pass "$MI2" "missing-input finding (Upstream: ask) passes"

# M1 — a [missing-input] finding carrying only a prose Fix: is rejected.
BADMI='- [blocker] [missing-input] Section 3: no evidence for the claim. Why blocker: quality-rubric dimension violation. Fix: reword it more carefully.'
rej "$BADMI" | grep -q 'M1:' && ok "M1: [missing-input] with only a Fix: is rejected" || err "M1 not caught"

# M2 — a writing-problem finding (no marker) carrying an Upstream: is rejected.
BADWP='- [should] Section 2: the flow is off. Why should: non-rubric structure/prose. Upstream: re-harvest something'
rej "$BADWP" | grep -q 'M2:' && ok "M2: writing-problem with an Upstream: is rejected" || err "M2 not caught"

# M3 — a [missing-input] Upstream: that is neither re-harvest nor ask.
BADFORM='- [blocker] [missing-input] Section 3: gap. Why blocker: quality-rubric dimension violation. Upstream: go find more stuff'
rej "$BADFORM" | grep -q 'M3:' && ok "M3: malformed Upstream form is rejected" || err "M3 not caught"

# A block mixing conforming + one violation reports the violation and fails.
BLOCK="$WP
$BADMI"
printf '%s\n' "$BLOCK" | python3 "$V" >/dev/null 2>&1 && err "a block with a violation exited 0" \
  || ok "a findings block is a hard gate (non-zero on any violation)"

# Non-finding lines pass through untouched (prose around the findings).
printf 'Structural pass findings:\n\n%s\n' "$WP" | python3 "$V" >/dev/null 2>&1 \
  && ok "non-bullet prose lines pass through" || err "prose lines tripped the validator"

# review-prompts.md documents the class and both formats.
grep -qi 'writing-problem vs missing-input' "$PROMPTS" && ok "review-prompts documents the finding class" || err "class not documented"
grep -qF 'Upstream: re-harvest' "$PROMPTS" && grep -qF '[missing-input]' "$PROMPTS" \
  && ok "review-prompts documents the missing-input format (marker + Upstream:)" || err "missing-input format not documented"
grep -qi 'blocker-eligible' "$PROMPTS" && ok "review-prompts states missing-input is blocker-eligible" || err "blocker-eligibility not stated"

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-findings-class checks passed.\n'; exit 0
else
  printf '\nreview-findings-class checks FAILED.\n' >&2; exit 1
fi
