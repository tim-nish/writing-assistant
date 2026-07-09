#!/usr/bin/env sh
# check-review-skill.sh — verify the review-article skill scaffold (Story 5.2):
# the fixed pass order (lint → structure → prose → cold read), once-per-version
# execution, the strict findings contract, the lint (pass-1) wiring, and model
# routing. POSIX shell.

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
grep -q '^name: review-article$' "$SKILL" && ok "declares name: review-article" || err "name frontmatter missing"

# Fixed pass order: lint → structure → prose → cold read, in that sequence.
order=$(grep -nEi '^[0-9]+\. \*\*(Lint|Structure|Prose|Cold read)\*\*' "$SKILL" \
  | sed -E 's/.*\*\*([A-Za-z ]+)\*\*.*/\1/' | tr 'A-Z' 'a-z' | tr '\n' ',')
[ "$order" = "lint,structure,prose,cold read," ] \
  && ok "fixed pass order is lint → structure → prose → cold read" \
  || err "pass order wrong or incomplete: '$order'"

grep -qi 'structure precedes prose' "$SKILL" \
  && ok "documents why structure precedes prose" || err "structure-before-prose rationale missing"
grep -qi 'once per draft version' "$SKILL" \
  && ok "states each LLM pass runs once per draft version" || err "once-per-version rule missing"

# Findings contract: exact format + constraints.
grep -qF -- '[blocker|should|nit] {location}: {issue' "$SKILL" \
  && ok "findings format is the strict contract" || err "findings format missing/wrong"
grep -qi 'capped at 10' "$SKILL" && ok "caps findings at 10" || err "cap-at-10 missing"
grep -qiE 'highest-leverage change (comes )?FIRST' "$SKILL" \
  && ok "requires highest-leverage change first" || err "highest-leverage-first missing"
if grep -qiE 'never rewrite|no rewrites' "$SKILL" \
   && grep -qiE 'never praise|no praise' "$SKILL" \
   && grep -qiE 'never summarize|no summary' "$SKILL"; then
  ok "forbids rewrites, praise, and summary"
else
  err "rewrite/praise/summary prohibition missing"
fi

# Pass-1 lint wiring.
grep -q 'scripts/lint-article' "$SKILL" \
  && ok "wires pass 1 to scripts/lint-article" || err "lint-article wiring missing"
grep -qi 'no LLM' "$SKILL" && ok "notes lint spends zero tokens" || err "zero-token note missing"

# Model routing: structure/prose on Sonnet-class + repo access; cold read cheap & context-free.
grep -qi 'Sonnet class' "$SKILL" && ok "routes structure/prose to Sonnet-class" || err "Sonnet routing missing"
grep -qi 'context-free' "$SKILL" && ok "cold read is context-free by design" || err "cold-read context-free note missing"

# Owner as sole arbiter.
grep -qi 'owner is the sole arbiter' "$SKILL" \
  && ok "owner is the sole arbiter" || err "owner-arbiter statement missing"

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-skill checks passed.\n'; exit 0
else
  printf '\nreview-skill checks FAILED.\n' >&2; exit 1
fi
