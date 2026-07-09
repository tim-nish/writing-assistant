#!/usr/bin/env sh
# check-review-arbitration.sh — verify owner arbitration & the second-cycle gate
# (Story 5.6): a single top-down accept/reject round, no auto-applied edits, no
# re-litigation of rejected findings, exactly one additional full cycle only when
# a blocker survives (else publishable), and the per-pass model routing recap.
# POSIX shell.

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

sec=$(awk '/^## Arbitration/{f=1} f{print}' "$SKILL")
[ -n "$sec" ] && ok "arbitration section present" || { err "Arbitration section missing"; printf '\nFAILED.\n' >&2; exit 1; }

has() { printf '%s\n' "$sec" | grep -qi "$1" && ok "$2" || err "$2 — missing"; }

# Single-round, owner-arbitrated, no auto-apply, no re-litigation.
has 'owner is the sole arbiter'                     "owner is the sole arbiter"
has 'accept or reject each finding\|accept.*reject' "accept/reject each finding"
has 'top-down'                                      "single top-down round"
has 'no finding is\|not.*auto-applied\|never.*rewrit' "no finding auto-applied"
has 'rejected finding is rejected\|do.*not.*re-litigate\|re-litigate' "rejected findings not re-litigated"

# Second-cycle gate: exactly one, only if a blocker survived; else publishable.
has 'blocker-severity finding survived\|blocker.*surviv' "second cycle only if a blocker survived"
has 'exactly one additional full cycle'             "exactly one additional full cycle"
has 'never loops unbounded\|One —\|never loop'      "never loops unbounded"
has 'otherwise the draft is publishable\|publishable' "otherwise the draft is publishable"

# Per-pass model routing recap.
has 'zero-token script\|lint.*script'               "lint is the zero-token script"
has 'Sonnet-class model with repo access\|Sonnet-class' "structure/prose Sonnet-class + repo access"
has 'context-free'                                  "cold read context-free"

if [ "$fail" -eq 0 ]; then
  printf '\nAll arbitration checks passed.\n'; exit 0
else
  printf '\narbitration checks FAILED.\n' >&2; exit 1
fi
