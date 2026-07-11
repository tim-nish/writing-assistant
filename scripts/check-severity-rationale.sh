#!/usr/bin/env sh
# check-severity-rationale.sh — verify criterion-anchored severity with a
# rationale field (Story 12.1). POSIX shell.
#
# Covers: every finding's format carries a `Why {severity}: {criterion}` field
# (AC1); review-prompts.md defines the severity criteria table — blocker =
# quality-rubric dimension violation / cold-read Q1-Q2 / config defect; should =
# cold-read Q3-Q4 or non-rubric structure/prose; nit = polish (AC2); and a
# severity without a named criterion is a contract violation, not judgment (AC3).

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

# 0. review-prompts.md exists (plugin-layout).
[ -f "$PROMPTS" ] && ok "review-prompts.md exists" \
  || { err "review-prompts.md missing at $PROMPTS"; printf '\nFAILED.\n' >&2; exit 1; }

# AC1 — the finding format includes the rationale field naming the criterion.
grep -qF 'Why {severity}: {criterion}' "$SKILL" && ok "SKILL finding format carries the Why {severity}: {criterion} field" \
  || err "SKILL finding format missing the rationale field"
grep -qF 'Why {severity}: {criterion}' "$PROMPTS" && ok "review-prompts states the finding format with rationale" \
  || err "review-prompts missing the finding format"

# AC2 — the severity criteria table with the three levels and their criteria.
grep -qi 'severity criteria table' "$PROMPTS" && ok "review-prompts has a severity criteria table" || err "no severity criteria table"
# blocker criterion: rubric dimension violation, cold-read Q1/Q2, or config defect.
grep -qi 'quality-rubric dimension violation' "$PROMPTS" && ok "blocker: quality-rubric dimension violation" || err "blocker rubric criterion missing"
grep -qiE 'Q1 \(claim\).*Q2 \(audience\)|cold-read Q1|Q1 \(claim\)' "$PROMPTS" && ok "blocker: cold-read Q1/Q2 mismatch" || err "blocker cold-read criterion missing"
grep -qi 'configuration defect' "$PROMPTS" && ok "blocker: configuration defect" || err "blocker config criterion missing"
# should: cold-read Q3/Q4 or non-rubric structure/prose.
grep -qiE 'cold-read Q3|Q3 or Q4' "$PROMPTS" && grep -qi 'non-rubric structure/prose' "$PROMPTS" \
  && ok "should: cold-read Q3/Q4 or non-rubric structure/prose" || err "should criterion missing"
# nit: polish.
grep -qi 'nit' "$PROMPTS" && grep -qi 'polish' "$PROMPTS" && ok "nit: polish" || err "nit criterion missing"

# AC3 — a severity without a named criterion is a contract violation.
grep -qi 'contract violation' "$SKILL" && ok "SKILL: severity without a criterion is a contract violation" || err "SKILL missing the contract-violation rule"
grep -qi 'contract violation' "$PROMPTS" && ok "review-prompts: unmapped/omitted severity is a contract violation" || err "review-prompts missing the contract-violation rule"

# The three severities each appear in the table.
for s in blocker should nit; do
  grep -qiE "\*\*$s\*\*" "$PROMPTS" || err "severity level not in the table: $s"
done
ok "all three severity levels are defined in the table"

if [ "$fail" -eq 0 ]; then
  printf '\nAll severity-rationale checks passed.\n'; exit 0
else
  printf '\nseverity-rationale checks FAILED.\n' >&2; exit 1
fi
