#!/usr/bin/env sh
# check-config-defect-routing.sh — verify review routes configuration defects to
# the publish-blocker bucket, never into the capped article-quality findings, and
# never reports a draft "publishable" while a configuration blocker is open
# (Story 7.6). The zero-token lint pass re-checks configuration as the backstop to
# Story 7.4. POSIX shell.

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

lint=$(awk '/^## Pass 1 — Lint/{f=1} f && /^## / && !/Pass 1/{exit} f{print}' "$SKILL")
gate=$(awk '/Second-cycle gate/{f=1} f{print} /publishable.*until it is fixed|backstop to Story 7.4/{exit}' "$SKILL")
summ=$(awk '/^## Completion summary/{f=1} f{print}' "$SKILL")

hasin() { printf '%s\n' "$1" | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

# 1. Lint pass re-checks configuration as the backstop to Story 7.4.
hasin "$lint" 'validate-config.py'   "lint pass re-runs validate-config (backstop)"
hasin "$lint" 'backstop'             "lint pass framed as the config backstop"
hasin "$lint" 'publish blocker\|publish-blocker' "config defect is a publish blocker"
hasin "$lint" 'capped prose or structure findings' "config defect never routed into capped findings"

# 2. Completion summary routes config defects to the blocker bucket only.
hasin "$summ" 'configuration defect' "completion summary lists configuration defect as a blocker"
hasin "$summ" 'never routed into\|nowhere else' "config defect kept out of prose/structure findings"

# 3. Review does not report publishable while a config blocker is open.
hasin "$gate" 'configuration blocker is still open\|configuration blocker' \
  "publishable gate blocked by an open configuration blocker"
hasin "$gate" 'not.*report' "review does not report publishable with a config blocker"

if [ "$fail" -eq 0 ]; then
  printf '\nAll config-defect-routing checks passed.\n'; exit 0
else
  printf '\nconfig-defect-routing checks FAILED.\n' >&2; exit 1
fi
