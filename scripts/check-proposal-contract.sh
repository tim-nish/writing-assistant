#!/usr/bin/env sh
# parallel-safe
# covers: skills/owner-facing-proposal-contract.md
# check-proposal-contract.sh — verify the owner-facing proposal contract is
# captured ONCE as a shared, referenceable convention (Story 7.1,
# SPEC-writing-assistant). The asset must state its three required elements
# (where / why / concrete-effect choices), forbid shorthand labels, and require
# a first-time owner to answer from repository knowledge alone; and both the
# draft-article and review-article skills must reference this single convention
# rather than restating their own wording. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

CONTRACT="skills/owner-facing-proposal-contract.md"
DRAFT="skills/draft-article/SKILL.md"
REVIEW="skills/review-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 0. The shared asset exists.
[ -f "$CONTRACT" ] && ok "shared contract asset exists ($CONTRACT)" \
  || { err "shared contract asset missing ($CONTRACT)"; printf '\nFAILED.\n' >&2; exit 1; }

has() { if grep -qi -- "$1" "$CONTRACT"; then ok "$2"; else err "$2 — missing from contract"; fi; }

# 1. States the three required elements.
has 'where'            "(a) states WHERE the item lands"
has 'preview'          "(a) requires a preview of current content when one exists"
has 'why'              "(b) states WHY it is being asked"
has 'concrete effect'  "(c) choices state their concrete effect on the artifact"

# 2. Forbids shorthand + repository-knowledge-alone test.
has 'shorthand'                 "forbids shorthand labels"
has 'repository knowledge alone' "first-time owner answers from repository knowledge alone"

# 2b. Extended contract (Story 10.1): selective presentation + payload validation.
has 'selective presentation'    "(d) selective presentation is the primary interaction model"
has 'free-form text'            "(d) free-form text only for owner-only knowledge"
has 'validate-proposal-payload.py' "(e) references the payload validator"
has 'untruncated'               "(e) requires present, non-empty, untruncated fields"

# 2c. (h) a question is answerable from itself (Story 20.137, #1177). MECHANICAL
# ONLY: whether a given ask carries enough explanation is a judgment and rides
# the human gate — see the clause's closing paragraph. What is checkable here is
# that the clause is STATED where composers read it, since a rule absent from the
# one shared convention binds nothing. This adds no denial list; the defect this
# clause names is an ABSENT explanation, which no token list can express.
has 'without ever being coined' "(h) binds the LEAKED case, not only coining"
has 'heading name'              "(h) names the leak sources — heading name"
has 'enum value'                "(h) names the leak sources — enum value"
has 'field name'                "(h) names the leak sources — field name"
has 'never needs internal vocabulary to answer' \
                                "(h) the Why section carries the explanation the term needs"
has 'codebook the owner must go and read is NOT a discharge' \
                                "(h) a codebook is not a discharge — the obligation sits at composition"
has "effect on the OWNER'S WORLD" \
                                "(h) options state their effect on the owner's world, not their internal form"

# 2d. The clause's own benchmark must survive as concrete option text, not as a
# claim that concrete option text is required. A worked pair is what a composer
# copies; the rule alone is what the failing ask already satisfied on paper.
if grep -q 'nothing is written to your files' "$CONTRACT" \
   && grep -q 'edits your working tree' "$CONTRACT"; then
  ok "(h) carries the worked benchmark pair, stated as effects on the owner's world"
else
  err "(h) states the rule without the worked benchmark pair — a composer has nothing to copy"
fi

# 3. Both skills reference the single convention (not their own wording).
ref() {
  file=$1; label=$2
  if grep -q 'owner-facing-proposal-contract.md' "$file"; then
    ok "$label references the shared contract"
  else
    err "$label does not reference the shared contract"
  fi
}
[ -f "$DRAFT" ]  && ref "$DRAFT"  "draft-article skill"  || err "draft-article SKILL.md missing"
[ -f "$REVIEW" ] && ref "$REVIEW" "review-article skill" || err "review-article SKILL.md missing"

if [ "$fail" -eq 0 ]; then
  printf '\nAll proposal-contract checks passed.\n'; exit 0
else
  printf '\nproposal-contract checks FAILED.\n' >&2; exit 1
fi
