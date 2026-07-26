#!/usr/bin/env sh
# check-consumption-population.sh — a consumption statement names its population
# (Story 18.121, #732). POSIX shell.
#
# Covers: the disclosure instruction requires the population to be named (AC1);
# the motivating phrasing is carried as a worked negative example with its
# reason (AC2); this check exists at all, in lockstep with the prompt step it
# enforces (AC3); nothing here claims the coverage question became answerable
# or introduces an element→Lesson mapping (AC4).
#
# Grep-level by design, matching the repo's other contract-text checks: the
# obligation binds authored prompt wording, not a code path, so the assertion
# is that the wording is present and says the right thing.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] || { err "$SKILL missing"; printf '\nFAILED.\n' >&2; exit 1; }

# The skill is hard-wrapped prose, so a phrase this check looks for routinely
# spans a line break and a line-based grep misses it. Match against a
# whitespace-normalized copy: the obligation is about the wording, not about
# where the author happened to wrap it. (Found the hard way — two assertions
# failed on text that was present.)
flat=$(mktemp); trap 'rm -f "$flat"' EXIT
tr '\n' ' ' < "$SKILL" | tr -s ' ' > "$flat"

# --- AC1: the instruction requires the population to be named. ---------------
grep -qi 'NAMES THE POPULATION it covers' "$flat" \
  && ok "the disclosure instruction requires the population to be named" \
  || err "$SKILL does not require a consumption statement to name its population"

grep -qi 'Never a bare quantifier' "$flat" \
  && ok "a bare quantifier is explicitly refused" \
  || err "$SKILL does not refuse a bare quantifier"

# The rule must reach the surfaces that actually state consumption, not sit in
# one paragraph nothing routes to. The completion summary is the one that
# reaches the owner without opening a run artifact.
grep -q 'names the population it covers' "$flat" \
  && ok "the completion-summary disclosure points at the population rule" \
  || err "the completion summary does not carry the population obligation"

# --- AC2: the motivating phrasing is a worked negative example. --------------
grep -qF 'every core lesson has been consumed' "$flat" \
  && ok "the motivating phrasing is named as forbidden" \
  || err "$SKILL does not carry the motivating phrasing as a negative example"

grep -qi 'disjoint namespaces' "$flat" \
  && ok "the reason is stated (disjoint namespaces), not just the prohibition" \
  || err "the prohibition is stated without its reason"

# A rule the reader cannot apply at the moment of violation is advisory. Require
# at least one concrete compliant example beside the forbidden one.
grep -qE 'story elements this run minted|elements across this project' "$flat" \
  && ok "a compliant wording is shown, not only the forbidden one" \
  || err "no compliant example accompanies the prohibition"

# --- AC4: no capability is claimed, no mapping introduced. -------------------
grep -qi 'adds no capability and no mapping' "$flat" \
  && ok "the rule disclaims new capability and any element->Lesson mapping" \
  || err "the rule does not disclaim capability; it may read as making coverage answerable"

# The join key's ownership is stated elsewhere and must not be contradicted here.
if grep -qiE 'lesson[_-]?slug *[:=]|element→Lesson map|element-to-lesson map' "$flat"; then
  err "$SKILL appears to introduce an element→Lesson mapping (owned by the articles repo)"
else
  ok "no element->Lesson mapping is introduced"
fi

[ "$fail" -eq 0 ] && printf '\nPASSED.\n' || { printf '\nFAILED.\n' >&2; exit 1; }
