#!/usr/bin/env sh
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

SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "draft-article SKILL.md exists" \
  || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

# Section extractors (from a heading to the next '## ').
sec() { awk -v h="$1" '$0 ~ h {f=1} f && $0 ~ /^## / && $0 !~ h {exit} f {print}' "$SKILL"; }
s2=$(sec '^## Stage 2')
s4=$(sec '^## Stage 4')

hasin() { printf '%s\n' "$1" | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

# Stage 2 — gap interview under the contract.
hasin "$s2" 'owner-facing-proposal-contract'        "stage 2 references the shared contract"
hasin "$s2" 'outline'                               "stage 2 shows where the section sits (outline context)"
hasin "$s2" 'preview of the current section'        "stage 2 shows a preview of the current section"
hasin "$s2" 'concrete effect'                       "stage 2 choices state their concrete effect"
hasin "$s2" 'drop the section from the article\|keep the section' "stage 2 choices are effect-labelled (not shorthand)"
hasin "$s2" 'repository knowledge alone'            "stage 2 answerable from repository knowledge alone"

# Stage 4 — verification items under the contract, effect-named choices.
hasin "$s4" 'owner-facing-proposal-contract'        "stage 4 references the shared contract"
hasin "$s4" 'concrete effect on the article'        "stage 4 choices state their concrete effect"
hasin "$s4" 'keep the claim, marked as an unmeasured estimate' "stage 4 'keep as unmeasured estimate' choice is effect-named"
hasin "$s4" 'remove the claim from the article'     "stage 4 'remove the claim' choice is effect-named"
hasin "$s4" 'repository knowledge alone'            "stage 4 answerable from repository knowledge alone"

if [ "$fail" -eq 0 ]; then
  printf '\nAll contract-in-draft-pipeline checks passed.\n'; exit 0
else
  printf '\ncontract-in-draft-pipeline checks FAILED.\n' >&2; exit 1
fi
