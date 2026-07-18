#!/usr/bin/env sh
# check-framework-f3.sh — verify the F3 evaluation/benchmark-methodology
# framework (Story 2.4). POSIX shell only.
#
# Checks: exact slot order (question → naive-failure → method → what-it-caught →
# limits → reproduce → pointer); the "What it caught" GATE demands a real
# table/figure (not prose/[VERIFY]); the naive-failure demo and the results GATE
# are cross-referenced to the same measurement; the reproduce slot requires
# resolvable links; the limits slot is mandatory; and reuse of Story 2.1's
# shared conventions with no baked-in identity.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

F3="skills/draft-article/frameworks/F3-evaluation-methodology.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -qF -- "$1" "$F3"; then ok "$2"; else err "$2 (missing: $1)"; fi; }
absent() { if grep -qF -- "$1" "$F3"; then err "$2 (should be absent: $1)"; else ok "$2"; fi; }
line() { grep -nF -- "$1" "$F3" | head -1 | cut -d: -f1; }

[ -f "$F3" ] && ok "present: $F3" || { err "missing $F3"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Exact section order.
prev=0; order_ok=1
check_order() {
  ln=$(line "$1")
  if [ -z "$ln" ]; then err "section missing: $1"; order_ok=0; return; fi
  if [ "$ln" -le "$prev" ]; then err "out of order: $1 (line $ln after $prev)"; order_ok=0; fi
  prev=$ln
}
check_order "## Frontmatter"
check_order "## {The measurement question}"
check_order "## {Why the naive approach fails}"
check_order "## {The method}"
check_order "## GATE {What it caught}"
check_order "## {What this measurement cannot tell you}"
check_order "## {Reproduce it}"
check_order "## GATE {Pointer block}"
[ "$order_ok" -eq 1 ] && ok "slots appear in the exact F3 order"

# 2. Entry GATE precondition + exactly two fill-GATEs.
has "GATE (entry)" "entry GATE present (an evaluation you actually ran)"
# Story 13.86 (#389): the GATE accepts observed results, not only measured
# numbers — but still refuses an evaluation you did not run.
has "evaluation you actually ran and its observed result" \
  "entry GATE keys on an evaluation you ran + observed result (13.86)"
has "need not be a benchmark number" "entry GATE admits qualitative results"
has "counted instances" "entry GATE names the qualitative result forms"
has "an evaluation you did not run" "entry GATE still refuses no-run subjects"
has "this is a survey (F4)" "no-run redirect to F4 unchanged"
grep -c '^## GATE {' "$F3" | grep -qx 2 && ok "exactly two fill-GATEs (What-it-caught, Pointer)" \
  || err "expected 2 '## GATE {' headings"

# 3. Results GATE requires a real table/figure, not prose/[VERIFY].
has "results table/figure" "results GATE annotated as table/figure"
has "Real results from running it" "results GATE cue: real results"
has "placeholder does NOT satisfy" "results GATE rejects prose/[VERIFY] placeholder"
# 13.86: qualitative rows satisfy the slot, pinned like sourced claims.
has "whether quantitative or not" "results GATE admits qualitative observed results"
has "caught-defect episodes" "results GATE names qualitative row forms"
has "pinned like any sourced claim" "qualitative rows carry pins"
has "Prose-only" "prose-only still refused alongside [VERIFY]"

# 4. Naive-failure demo and results are cross-referenced to one measurement.
has "DEMONSTRATE the failure" "naive-failure slot demonstrates (not asserts)"
has "SAME measurement" "results GATE cross-references the naive-failure measurement"

# 5. Reproduce slot requires resolvable links, not prose promises.
has "Code, dataset, leaderboard" "reproduce slot names code/dataset/leaderboard"
has "must resolve" "reproduce links must resolve (not prose promises)"
has "placeholder link blocks completion" "empty/placeholder link blocks completion"

# 6. Limits slot mandatory.
has "What this measurement cannot tell you" "limits slot present"
has "omits its limits is not" "limits slot marked mandatory"

# 7. Reuse of shared conventions; generic engine (no identity).
has "CONVENTIONS.md" "references shared CONVENTIONS.md"
absent "I write about" "does not inline the shared pointer-block prose"
if grep -qE '^mode:' "$F3"; then err "hardcodes a frontmatter schema (raw 'mode:' line)"; else ok "frontmatter is config-bound"; fi
if grep -qi 'tim-nish' "$F3"; then err "leaks owner identity"; else ok "no owner identity / repo names"; fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll F3 framework checks passed.\n'; exit 0
else
  printf '\nF3 framework checks FAILED.\n' >&2; exit 1
fi
