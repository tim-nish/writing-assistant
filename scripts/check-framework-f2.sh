#!/usr/bin/env sh
# check-framework-f2.sh — verify the F2 engineering-lessons framework (Story
# 2.3). POSIX shell only.
#
# Checks: exact slot order; the repeatable lesson unit (slots 2-6) is bracketed
# by the `<!-- Lesson unit — … -->` / `<!-- Lesson unit END -->` comment markers
# with Context and the pointer block OUTSIDE it (so neither is duplicated); the
# per-lesson "What actually happened" artifact GATE; the >3-lessons split as a
# DECLINABLE SUGGESTION (CAP-8/#432 demoted it from a hard cap); the mechanism /
# change-cost cues preserved; and reuse of Story 2.1's shared conventions.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

F2="skills/draft-article/frameworks/F2-engineering-lessons.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -qF -- "$1" "$F2"; then ok "$2"; else err "$2 (missing: $1)"; fi; }
absent() { if grep -qF -- "$1" "$F2"; then err "$2 (should be absent: $1)"; else ok "$2"; fi; }
line() { grep -nF -- "$1" "$F2" | head -1 | cut -d: -f1; }

[ -f "$F2" ] && ok "present: $F2" || { err "missing $F2"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Exact section order.
prev=0; order_ok=1
check_order() {
  ln=$(line "$1")
  if [ -z "$ln" ]; then err "section missing: $1"; order_ok=0; return; fi
  if [ "$ln" -le "$prev" ]; then err "out of order: $1 (line $ln after $prev)"; order_ok=0; fi
  prev=$ln
}
check_order "## Frontmatter"
check_order "## {Context}"
check_order "## {What I believed going in}"
check_order "## GATE {What actually happened}"
check_order "the mechanism}"
check_order "what it cost}"
check_order "When this applies to you"
check_order "## GATE {Pointer block}"
[ "$order_ok" -eq 1 ] && ok "slots appear in the exact F2 order"

# 2. Repeatable lesson unit brackets slots 2-6; Context + pointer are OUTSIDE it.
# The unit is delimited by the HTML-comment markers `<!-- Lesson unit — … -->`
# (opening) and `<!-- Lesson unit END -->` (closing) — the opening marker was
# reworded from "Lesson unit START" when the CAP-8 lesson-obligations note
# landed (#432); "CONTENT OBLIGATIONS" is the stable, ASCII-safe anchor for it.
has "CONTENT OBLIGATIONS" "lesson-unit opening marker (<!-- Lesson unit — … -->)"
has "Lesson unit END"   "lesson-unit END marker"
ctx=$(line "## {Context}"); start=$(line "CONTENT OBLIGATIONS")
believed=$(line "## {What I believed going in}"); end=$(line "Lesson unit END")
applies=$(line "When this applies to you"); ptr=$(line "## GATE {Pointer block}")
{ [ "$ctx" -lt "$start" ] && [ "$start" -lt "$believed" ]; } \
  && ok "Context is once, before the repeat region" || err "Context not outside/above the lesson unit"
{ [ "$applies" -lt "$end" ] && [ "$end" -lt "$ptr" ]; } \
  && ok "pointer block is once, after the repeat region" || err "pointer block not outside/below the lesson unit"

# 3. Per-lesson artifact GATE.
grep -c '^## GATE {' "$F2" | grep -qx 2 && ok "exactly two fill-GATEs (What-happened, Pointer)" \
  || err "expected 2 '## GATE {' headings"
has "Each lesson needs its OWN" "per-lesson artifact GATE (enforced per lesson)"
has "WITH the artifact" "what-happened requires a shown artifact"

# 4. >3-lessons rule is authoring guidance (in a comment), not a hard cap.
# CAP-8/#432 demoted it from a hard "split into two articles" rule to a
# DECLINABLE SUGGESTION surfaced as an owner choice — assert the demoted form.
has "DECLINABLE SUGGESTION" ">3 lessons -> declinable split suggestion (CAP-8, #432)"
# the guidance lives inside the HTML comment block, i.e. it is instruction text
grep -q '>3 lessons' "$F2" && ok "the split rule is guidance text, not an enforced cap" \
  || err "missing the >3-lessons guidance text"

# 5. Transferable-value cues preserved verbatim.
has "Root cause, not symptom" "mechanism cue: root cause not symptom"
has "tradeoff you accepted stated plainly" "change/cost cue: state the tradeoff"

# 6. Reuse of shared conventions (no re-implementation, no identity).
has "CONVENTIONS.md" "references shared CONVENTIONS.md"
absent "I write about" "does not inline the shared pointer-block prose"
if grep -qE '^mode:' "$F2"; then err "hardcodes a frontmatter schema (raw 'mode:' line)"; else ok "frontmatter is config-bound"; fi
if grep -qi 'tim-nish' "$F2"; then err "leaks owner identity"; else ok "no owner identity"; fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll F2 framework checks passed.\n'; exit 0
else
  printf '\nF2 framework checks FAILED.\n' >&2; exit 1
fi
