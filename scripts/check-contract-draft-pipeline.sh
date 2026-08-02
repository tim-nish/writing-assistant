#!/usr/bin/env sh
# parallel-safe
# covers: skills/draft-article/SKILL.md skills/draft-article/stages/complete.md skills/draft-article/stages/gate.md skills/draft-article/stages/stage0.md skills/draft-article/stages/stage1.md skills/draft-article/stages/stage2.md skills/draft-article/stages/stage3.md skills/draft-article/stages/stage4.md
# check-contract-draft-pipeline.sh — verify the draft pipeline applies the
# owner-facing proposal contract (Story 7.2) at its two owner decision points:
# the Stage 2 gap interview and the Stage 4 verification pass. Each must show
# section context + a current-content preview, a rationale, and choices whose
# labels state their concrete effect on the article — answerable from repository
# knowledge alone. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"
__DA_ALL="${TMPDIR:-/tmp}/da-skill-all.$$.md"
cat skills/draft-article/SKILL.md skills/draft-article/stages/stage0.md skills/draft-article/stages/stage1.md skills/draft-article/stages/stage2.md skills/draft-article/stages/stage3.md skills/draft-article/stages/gate.md skills/draft-article/stages/stage4.md skills/draft-article/stages/complete.md > "$__DA_ALL"


SKILL="$__DA_ALL"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "draft-article SKILL.md exists" \
  || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

# Section extractors (from a heading to the next '## ').
sec() { awk -v h="$1" '$0 ~ h {f=1} f && $0 ~ /^## / && $0 !~ h {exit} f {print}' "$SKILL"; }
s2=$(sec '^## Gap interview')
s4=$(sec '^## Verification')

# Whitespace-collapsed match: a contract phrase that wraps across source lines
# ("repository\nknowledge alone") must still anchor — line-based grep rotted
# red the moment prose re-wrapped (#190).
hasin() { printf '%s\n' "$1" | tr '\n' ' ' | tr -s ' ' | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

# The gap interview under the contract.
hasin "$s2" 'owner-facing-proposal-contract'        "gap interview references the shared contract"
hasin "$s2" 'outline'                               "gap interview shows where the section sits (outline context)"
hasin "$s2" 'preview of the current section'        "gap interview shows a preview of the current section"
hasin "$s2" 'concrete effect'                       "gap interview choices state their concrete effect"
# Anchor on the CURRENT disposition labels (Story 10.3 replaced the old
# drop-the-section examples); both alternatives are live label text (#190).
hasin "$s2" 'adopt this answer as written\|discard this and use my own' "gap interview choices are effect-labelled (not shorthand)"
hasin "$s2" 'repository knowledge alone'            "gap interview answerable from repository knowledge alone"

# Verification items under the contract, effect-named choices.
hasin "$s4" 'owner-facing-proposal-contract'        "verification references the shared contract"
hasin "$s4" 'concrete effect on the article'        "verification choices state their concrete effect"
hasin "$s4" 'keep the claim, marked as an unmeasured estimate' "verification 'keep as unmeasured estimate' choice is effect-named"
hasin "$s4" 'remove the claim from the article'     "verification 'remove the claim' choice is effect-named"
hasin "$s4" 'repository knowledge alone'            "verification answerable from repository knowledge alone"

if [ "$fail" -eq 0 ]; then
  printf '\nAll contract-in-draft-pipeline checks passed.\n'; exit 0
else
  printf '\ncontract-in-draft-pipeline checks FAILED.\n' >&2; exit 1
fi
