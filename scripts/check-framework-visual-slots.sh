#!/usr/bin/env sh
# check-framework-visual-slots.sh — verify each framework declares its visual
# slot(s) (Story 8.1, SPEC-article-visuals CAP-1): F1 one overview diagram; F2
# optional before/after or timeline; F3 one comparison table (required); F4 one
# landscape table or concept map — and that a declined slot is omitted entirely
# with no `[Figure: …]` / placeholder residue. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DIR="skills/draft-article/frameworks"
CONV="$DIR/CONVENTIONS.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 0. Shared convention documents the slot set + the declined-no-residue rule.
[ -f "$CONV" ] && ok "CONVENTIONS.md exists" || { err "CONVENTIONS.md missing"; printf '\nFAILED.\n' >&2; exit 1; }
hasc() { grep -qi -- "$1" "$CONV" && ok "$2" || err "$2 — missing from CONVENTIONS"; }
hasc 'Visual slots'                       "convention documents visual slots"
hasc 'overview diagram'                   "convention: F1 overview diagram"
hasc 'before/after or timeline'           "convention: F2 before/after or timeline"
hasc 'comparison table'                   "convention: F3 comparison table"
hasc 'landscape table or concept map'     "convention: F4 landscape table or concept map"
hasc 'declined slot is omitted entirely\|declined.*omitted' "convention: declined slot omitted entirely"
hasc 'placeholder residue'                "convention: no placeholder residue"

# 1. Each framework declares its own slot + the no-residue rule.
slot() {
  file=$(ls "$DIR"/$1-*.md 2>/dev/null | head -1)
  [ -n "$file" ] && [ -f "$file" ] || { err "$1 framework file missing"; return; }
  grep -qi 'Visual slot' "$file" && ok "$1 declares a visual slot" || err "$1 has no visual slot declaration"
  grep -qi -- "$2" "$file" && ok "$1 slot type: $3" || err "$1 wrong/missing slot type ($3)"
  grep -qi 'omitted entirely' "$file" && grep -qi 'placeholder residue\|Figure' "$file" \
    && ok "$1 declined slot leaves no residue" || err "$1 missing declined-no-residue rule"
}
slot F1 'overview diagram'                "one overview diagram"
slot F2 'before/after or timeline'        "optional before/after or timeline"
slot F3 'comparison table'                "one comparison table (required)"
slot F4 'landscape table or concept map'  "one landscape table or concept map"

# 2. F3's comparison table is marked required.
f3=$(ls "$DIR"/F3-*.md | head -1)
grep -qi 'comparison table.*required\|required' "$f3" && ok "F3 comparison table marked required" \
  || err "F3 does not mark its table required"

if [ "$fail" -eq 0 ]; then
  printf '\nAll framework-visual-slot checks passed.\n'; exit 0
else
  printf '\nframework-visual-slot checks FAILED.\n' >&2; exit 1
fi
