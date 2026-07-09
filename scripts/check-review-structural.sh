#!/usr/bin/env sh
# check-review-structural.sh — verify the structural pass rubric (Story 5.3):
# the six-point rubric (hook, single idea, section relevance, missing
# load-bearing content, reader-order, GATE-slot conformance), Sonnet-class +
# repo grounding, once-per-version, standard findings format, and explicit
# handling of a misplaced section. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/review-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "review-article SKILL.md exists" || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

# Isolate the Structure pass section (from its heading to the next pass heading).
sec=$(awk '/^## Pass 2 — Structure/{f=1} f&&/^## Pass 3/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "structural pass section present" || { err "Pass 2 section missing"; printf '\nFAILED.\n' >&2; exit 1; }

has() { printf '%s\n' "$sec" | grep -qi "$1" && ok "$2" || err "$2 — missing"; }

has 'Sonnet-class model with repo access' "runs on Sonnet-class with repo access"
has 'once per draft version'              "runs once per draft version"
has 'hook'                                "rubric: hook (problem/result up front)"
has 'one idea'                            "rubric: exactly one idea"
has 'section relevance\|sections to cut'  "rubric: section relevance (cut/merge)"
has 'missing load-bearing\|load-bearing content' "rubric: missing load-bearing content"
has 'reader-order\|reader.s'              "rubric: reader-order not author chronology"
has 'GATE-slot conformance\|GATE slots'   "rubric: GATE-slot conformance"
has 'misplaced section'                   "explicitly handles a misplaced section"
has 'no rewrites'                         "no rewrites (name the change only)"

# Standard findings contract referenced by this pass.
printf '%s\n' "$sec" | grep -qi 'standard contract format\|standard format\|findings' \
  && ok "emits standard-format findings" || err "standard findings format not referenced"

if [ "$fail" -eq 0 ]; then
  printf '\nAll structural-pass checks passed.\n'; exit 0
else
  printf '\nstructural-pass checks FAILED.\n' >&2; exit 1
fi
