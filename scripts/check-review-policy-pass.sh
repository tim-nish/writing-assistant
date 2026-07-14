#!/usr/bin/env sh
# check-review-policy-pass.sh — verify the policy-consistency review pass
# (Story 15.1, SPEC-policy-consistency-pass CAP-1/CAP-2/CAP-5).
# POSIX shell + stdlib Python only.
#
# Covers: the fixed pass order gains policy consistency between prose and cold
# read; the pass section prescribes the seam reader as the only policy access,
# quote-vs-quote findings with the policy-contradiction criterion and NO Fix
# field, the ≤10 cap, and emit-nothing-on-no-conflict; the severity criteria
# table carries the policy-contradiction row (default should, never blocker
# alone); and the cold read is never shown the policy surface.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/review-article/SKILL.md"
PROMPTS="skills/review-article/review-prompts.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# Whitespace-collapsed contains (wrap-proof, per #190).
hasin() { printf '%s\n' "$1" | tr '\n' ' ' | tr -s ' ' | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

# --- 1. Pass order: lint, structure, prose, policy consistency, cold read -----
order=$(grep -nEi '^[0-9]+\. \*\*(Lint|Structure|Prose|Policy consistency|Cold read)\*\*' "$SKILL" \
  | sed -E 's/.*\*\*([A-Za-z ]+)\*\*.*/\1/' | tr 'A-Z' 'a-z' | tr '\n' ',')
[ "$order" = "lint,structure,prose,policy consistency,cold read," ] \
  && ok "pass order: lint → structure → prose → policy consistency → cold read" \
  || err "pass order wrong: '$order'"
grep -qi 'cold.*read.*stays last' "$SKILL" || grep -qi 'before the cold' "$SKILL" \
  && ok "cold read stays last (isolation rationale stated)" \
  || err "isolation rationale missing"

# --- 2. Pass section: seam reader, quote-vs-quote, no Fix field ---------------
sec=$(awk '/^## Pass 4 — Policy consistency/{f=1} f&&/^## Pass 5/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "policy-consistency pass section present" \
  || { err "Pass 4 policy section missing"; printf '\nFAILED.\n' >&2; exit 1; }
hasin "$sec" 'read-policy-source.py'            "pass reads via the seam reader only"
hasin "$sec" 'once per draft version'           "pass runs once per draft version"
hasin "$sec" 'file:line@commit'                 "policy quote carries file:line@commit"
hasin "$sec" 'policy-contradiction'             "findings name the policy-contradiction criterion"
hasin "$sec" 'no .Fix:. field\|No .Fix:. field' "no Fix field — the pass proposes no diffs"
hasin "$sec" 'never blocker alone'              "should by default, never blocker alone"
hasin "$sec" 'emits nothing'                    "no-conflict draft emits nothing"
hasin "$sec" 'Cap at 10'                        "findings capped at 10"
hasin "$sec" 'skipped'                          "absent/unusable source skips the pass"
hasin "$sec" 'Never show this pass'             "policy surface never shown to the cold read"

# --- 3. Severity criteria table row --------------------------------------------
grep -q 'policy-contradiction' "$PROMPTS" && ok "severity table carries policy-contradiction" \
  || err "severity table missing policy-contradiction row"
prow=$(grep 'policy-contradiction' "$PROMPTS" | head -1)
printf '%s' "$prow" | grep -qi 'never blocker alone' \
  && ok "policy-contradiction: never blocker alone" \
  || err "policy-contradiction row lacks the never-blocker rule"

# --- 4. Findings-contract exception + arbitration collect ----------------------
grep -qi 'Policy-consistency findings carry no .Fix:. field' "$SKILL" \
  && ok "findings contract states the no-Fix exception" \
  || err "findings-contract exception missing"
grep -qi 'policy consistency, and cold read' "$SKILL" \
  && ok "arbitration collects the policy pass's findings" \
  || err "arbitration collect line not updated"

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-policy-pass checks passed.\n'; exit 0
else
  printf '\nreview-policy-pass checks FAILED.\n' >&2; exit 1
fi
