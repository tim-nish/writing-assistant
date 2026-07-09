#!/usr/bin/env sh
# check-framework-f1.sh — verify the F1 project-introduction framework (Story
# 2.2). POSIX shell only.
#
# Checks: exact slot order (the "no reorganization" AC), the entry GATE as a
# selection precondition (routes to F2) distinct from the fill-GATEs, the
# Evidence + Pointer GATE markers, the anti-marketing prompt cues preserved
# verbatim, and reuse of Story 2.1's shared conventions (no re-implemented
# frontmatter schema or pointer prose).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

F1="skills/draft-article/frameworks/F1-project-introduction.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -qF -- "$1" "$F1"; then ok "$2"; else err "$2 (missing: $1)"; fi; }
absent() { if grep -qF -- "$1" "$F1"; then err "$2 (present but should not be: $1)"; else ok "$2"; fi; }

[ -f "$F1" ] && ok "present: $F1" || { err "missing $F1"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Exact section order (load-bearing for the no-reorganization AC).
prev=0; order_ok=1
check_order() {
  ln=$(grep -nF -- "$1" "$F1" | head -1 | cut -d: -f1)
  if [ -z "$ln" ]; then err "section missing: $1"; order_ok=0; return; fi
  if [ "$ln" -le "$prev" ]; then err "section out of order: $1 (line $ln after $prev)"; order_ok=0; fi
  prev=$ln
}
check_order "## Frontmatter"
check_order "## {The problem}"
check_order "## {Why existing options fall short}"
check_order "## {What I built}"
check_order "## {The design decision that matters}"
check_order "## GATE {Evidence}"
check_order "## {Limits and roadmap}"
check_order "## {Try it}"
check_order "## GATE {Pointer block}"
[ "$order_ok" -eq 1 ] && ok "slots appear in the exact F1 order (problem→…→pointer)"

# 2. Entry GATE is a precondition (routes to F2), distinct from the fill-GATEs.
has "GATE (entry)" "entry GATE present"
grep -q 'F2' "$F1" && ok "entry GATE routes to F2 when no shipped artifact" || err "entry GATE does not route to F2"
gates=$(grep -cE '^## GATE \{' "$F1" || true)
[ "$gates" -eq 2 ] && ok "exactly two fill-GATE headings (Evidence, Pointer)" \
  || err "expected 2 '## GATE {' headings, found $gates (entry GATE must not be a body slot)"

# 3. Anti-marketing prompt cues preserved verbatim.
has "mentioned yet" "problem cue: project not mentioned yet"
has "what it COST" "decision cue: state its cost"
has "reads as marketing" "decision cue: no-tradeoff = marketing"
has "produced by the real system" "evidence cue: result from the real system"
has "ONE concrete demo" "built cue: exactly one demo"
has "Show, don't enumerate" "built cue: show don't enumerate"

# 4. Reuse of shared conventions, not an F1-local re-implementation.
has "CONVENTIONS.md" "references shared CONVENTIONS.md"
absent "I write about" "does not inline the shared pointer-block prose"
if grep -qE '^mode:' "$F1"; then err "hardcodes a frontmatter schema (raw 'mode:' line)"; else ok "frontmatter is config-bound (no hardcoded schema block)"; fi
if grep -qi 'tim-nish' "$F1"; then err "leaks owner identity"; else ok "no owner identity (config-bound)"; fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll F1 framework checks passed.\n'; exit 0
else
  printf '\nF1 framework checks FAILED.\n' >&2; exit 1
fi
