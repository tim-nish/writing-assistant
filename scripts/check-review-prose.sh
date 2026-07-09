#!/usr/bin/env sh
# check-review-prose.sh — verify the prose pass rubric (Story 5.4): the six-point
# rubric (unwarranted hedging, unexplained jargon, overlong sentences, agent-less
# decision statements, buried load-bearing sentences, non-native phrasing without
# flattening voice), runs after structure, Sonnet/Haiku-class + repo grounding,
# once-per-version, standard findings format. POSIX shell.

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

sec=$(awk '/^## Pass 3 — Prose/{f=1} f&&/^## Pass 4/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "prose pass section present" || { err "Pass 3 section missing"; printf '\nFAILED.\n' >&2; exit 1; }

has() { printf '%s\n' "$sec" | grep -qi "$1" && ok "$2" || err "$2 — missing"; }

has 'Sonnet/Haiku-class'                        "runs on Sonnet/Haiku-class with repo access"
has 'once per draft version'                    "runs once per draft version"
has 'after the structural'                      "runs after the structural pass"
has 'hedging'                                   "rubric: unwarranted hedging"
has 'jargon'                                    "rubric: unexplained jargon"
has 'overlong sentences\|over ~30 words\|30 words' "rubric: overlong sentences"
has 'agent-less\|restore the actor'             "rubric: agent-less decision statements"
has 'buried load-bearing\|load-bearing sentence' "rubric: buried load-bearing sentence"
has 'non-native'                                "rubric: non-native phrasing"
has 'do not sand off voice\|not the stance'     "preserves voice (does not flatten stance)"
has 'no rewrites'                               "no rewrites"

if [ "$fail" -eq 0 ]; then
  printf '\nAll prose-pass checks passed.\n'; exit 0
else
  printf '\nprose-pass checks FAILED.\n' >&2; exit 1
fi
