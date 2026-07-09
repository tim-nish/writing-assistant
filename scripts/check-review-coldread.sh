#!/usr/bin/env sh
# check-review-coldread.sh — verify the cold-read pass (Story 5.5): context-free
# (draft only, no repo/project context), the six-question reader rubric, the
# comparison to interview answers #2/#5, and the severity mapping (claim/audience
# mismatch = blocker; confusion/assumed-knowledge = should-fix). POSIX shell.

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

sec=$(awk '/^## Pass 4 — Cold read/{f=1} f&&/^## Arbitration/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "cold-read pass section present" || { err "Pass 4 section missing"; printf '\nFAILED.\n' >&2; exit 1; }

has() { printf '%s\n' "$sec" | grep -qi "$1" && ok "$2" || err "$2 — missing"; }

# Context-free by design.
has 'ONLY the draft\|only the draft'          "runs on the draft only"
has 'no repo access\|no project context'      "no repo/project context"
has 'any cheap model'                         "runs on any cheap model"

# Six-question reader rubric.
has 'claim'                                   "rubric Q1: the claim"
has 'who is it for\|audience'                 "rubric Q2: who is it for"
has 'first get confused\|first.*confus'       "rubric Q3: first confusion point"
has 'assume you already knew\|assumed.*knew'  "rubric Q4: assumed knowledge"
has 'read past the first screen'              "rubric Q5: read past first screen"
has 'do after'                                "rubric Q6: next action"

# Comparison to interview answers and severity mapping.
has 'interview answers'                       "compares to the author's interview answers"
has '#2'                                       "references interview answer #2 (claim)"
has '#5'                                       "references interview answer #5 (audience)"
has 'blocker'                                 "claim/audience mismatch = blocker"
has 'should-fix'                              "confusion/assumed-knowledge = should-fix"

if [ "$fail" -eq 0 ]; then
  printf '\nAll cold-read checks passed.\n'; exit 0
else
  printf '\ncold-read checks FAILED.\n' >&2; exit 1
fi
