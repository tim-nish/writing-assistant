#!/usr/bin/env sh
# check-sourced-visuals.sh — verify every element of a proposed visual is sourced
# like a prose claim (Story 8.3, SPEC-article-visuals CAP-3): each element is
# source-pointed like a fact-sheet entry or the proposal carries `[VERIFY]`; an
# unsourceable structural claim routes to NEEDS-OWNER (the same partition rule as
# prose), never into an unmarked diagram element. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "draft-article SKILL.md exists" \
  || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

sec=$(awk '/^### Sourced visuals/{f=1} f && /^#{2,3} / && !/Sourced visuals/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "Sourced visuals subsection present" \
  || { err "Sourced visuals subsection missing"; printf '\nFAILED.\n' >&2; exit 1; }

hasin() { printf '%s\n' "$1" | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

hasin "$sec" 'per element\|per-element'      "sourcing applied per element"
hasin "$sec" 'source-pointed'                "element is source-pointed like a fact-sheet entry"
hasin "$sec" 'fact-sheet entry'              "sourced like a fact-sheet entry"
hasin "$sec" 'VERIFY'                        "unverified element carries a [VERIFY] marker"
hasin "$sec" 'NEEDS-OWNER'                   "unsourceable structural claim routes to NEEDS-OWNER"
hasin "$sec" 'same partition rule as prose'  "same partition rule as prose"
hasin "$sec" 'never.*unmarked\|unmarked diagram element' "never an unmarked diagram element"

if [ "$fail" -eq 0 ]; then
  printf '\nAll sourced-visual checks passed.\n'; exit 0
else
  printf '\nsourced-visual checks FAILED.\n' >&2; exit 1
fi
