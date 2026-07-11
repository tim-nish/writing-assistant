#!/usr/bin/env sh
# check-rubric-mapped-gate.sh — verify rubric-mapped findings gate "publishable"
# (Story 12.2). POSIX shell.
#
# Covers: a structure/prose finding that maps to a quality-rubric dimension is
# blocker-eligible (AC1); an open rubric-mapped blocker (or a configuration
# blocker) means review does NOT report the draft "publishable" (AC2); and the
# criteria a rubric-mapped blocker names are the Epic-11 rubric dimensions
# (AC3, tying to Story 12.1).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/review-article/SKILL.md"
PROMPTS="skills/review-article/review-prompts.md"
RUBRIC="skills/draft-article/quality-rubric.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# AC1 — rubric-mapped structure/prose findings are blocker-eligible.
grep -qi 'blocker-eligible' "$SKILL" && ok "SKILL: rubric-mapped findings are blocker-eligible" || err "SKILL missing blocker-eligibility"
grep -qi 'maps to a quality-rubric dimension' "$SKILL" && ok "SKILL: mapping to a rubric dimension is the eligibility test" || err "SKILL missing the rubric-mapping test"
grep -qi 'second net' "$SKILL" && ok "SKILL: review is a real second net, not advisory" || err "SKILL missing the second-net framing"

# AC2 — an open rubric-mapped blocker (or config blocker) blocks "publishable".
grep -qiE 'open rubric-mapped blocker.*configuration blocker|rubric-mapped blocker or a configuration blocker' "$SKILL" \
  && ok "SKILL: open rubric-mapped or config blocker ⇒ not publishable" || err "SKILL missing the not-publishable gate"
grep -qi 'does .*not.* report the draft "publishable"\|not.*report the draft "publishable"' "$SKILL" \
  && ok "SKILL: withholds the publishable verdict on an open blocker" || err "SKILL missing publishable withholding"
# a surviving rubric-mapped blocker triggers the bounded second cycle.
grep -qi 'rubric-mapped structure/prose blocker' "$SKILL" && ok "SKILL: a rubric-mapped blocker triggers the second cycle" || err "SKILL missing rubric blocker in the second-cycle gate"
# and it surfaces in the publish-blocker bucket.
grep -qi 'rubric-mapped structure/prose blocker' "$SKILL" && ok "SKILL: rubric-mapped blocker surfaces under publish blockers" || err "rubric blocker not in publish-blocker bucket"

# AC3 — the criteria are the four Epic-11 rubric dimensions (via Story 12.1).
for dim in 'narrative arc' 'paragraph flow' 'explanation calibration' 'readability mechanics'; do
  grep -qi "$dim" "$SKILL" || grep -qi "$dim" "$PROMPTS" || err "rubric dimension not referenced as a blocker criterion: $dim"
done
ok "the four rubric dimensions are the rubric-mapped blocker criteria"
grep -qi 'blocker-eligible' "$PROMPTS" && ok "review-prompts states rubric-dimension blocker-eligibility" || err "review-prompts missing blocker-eligibility anchor"
# the rubric asset the dimensions come from exists (Epic 11).
[ -f "$RUBRIC" ] && ok "quality-rubric.md (dimension source) is present" || err "quality-rubric.md missing"

if [ "$fail" -eq 0 ]; then
  printf '\nAll rubric-mapped-gate checks passed.\n'; exit 0
else
  printf '\nrubric-mapped-gate checks FAILED.\n' >&2; exit 1
fi
