#!/usr/bin/env sh
# check-contract-review-arbitration.sh — verify review arbitration presents each
# finding under the owner-facing proposal contract (Story 7.3): location, why it
# is raised, and accept/reject choices stating their concrete effect on the
# article — consistent with Story 7.1 and WITHOUT changing the existing capped,
# severity-tagged findings format. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/review-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "review-article SKILL.md exists" \
  || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

arb=$(awk '/^## Arbitration/{f=1} f && /^## / && !/^## Arbitration/{exit} f{print}' "$SKILL")
fnd=$(awk '/^## Findings contract/{f=1} f && /^## / && !/^## Findings contract/{exit} f{print}' "$SKILL")

hasin() { printf '%s\n' "$1" | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

# Arbitration applies the contract.
hasin "$arb" 'owner-facing-proposal-contract' "arbitration references the shared contract"
hasin "$arb" 'where.*it sits\|where.*sits in the article' "each finding shows WHERE it sits"
hasin "$arb" 'why.*it is\|why.*raised'        "each finding shows WHY it is raised"
hasin "$arb" 'concrete effect on the article' "accept/reject choices state their concrete effect"
hasin "$arb" 'apply the fix'                  "accept choice is effect-named"
hasin "$arb" 'leave the article unchanged'    "reject choice is effect-named"

# Presentation wrapper only — the capped, severity-tagged format is unchanged.
hasin "$arb" 'does not change'                "notes it does not change the findings format"
hasin "$fnd" 'Capped at 10'                   "findings format still capped at 10"
hasin "$fnd" 'blocker'                        "findings format still severity-tagged (blocker/should/nit)"

if [ "$fail" -eq 0 ]; then
  printf '\nAll contract-in-arbitration checks passed.\n'; exit 0
else
  printf '\ncontract-in-arbitration checks FAILED.\n' >&2; exit 1
fi
