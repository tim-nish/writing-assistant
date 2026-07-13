#!/usr/bin/env sh
# check-review-starter.sh — verify the review-article starter template (Story 13.16):
# a copyable draft with schema-valid frontmatter + the mandatory pointer block that
# passes lint-article UNCHANGED, and a skill that points readers at it. POSIX shell.
#
# The mechanical heart is the round-trip: the shipped template, linted against the
# example config, is clean — so the template is authoritative, not aspirational.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

TPL="skills/review-article/starter-article.md"
SKILL="skills/review-article/SKILL.md"
LINT="scripts/lint-article"
RUC="scripts/resolve-user-config.py"
EXAMPLE="config/user-config.example.yaml"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 1. The template exists and carries frontmatter + the pointer block.
[ -f "$TPL" ] && ok "starter template present: $TPL" \
  || { err "missing $TPL"; printf '\nFAILED.\n' >&2; exit 1; }
head -1 "$TPL" | grep -q '^---$' && ok "template opens with frontmatter" || err "no frontmatter block"
for field in slug title date mode language summary topics related; do
  grep -q "^$field:" "$TPL" && ok "frontmatter has $field" || err "frontmatter missing $field"
done
grep -q 'example.com' "$TPL" && ok "carries a pointer block (site link present)" \
  || err "pointer block missing (no site link)"

# 2. Authoritative: the template lints CLEAN, unchanged, against the example config.
CFG=$(python3 "$RUC" --global-config "$EXAMPLE" resolved) \
  || { err "could not resolve example config"; CFG=""; }
if [ -n "$CFG" ]; then
  if printf '%s' "$CFG" | python3 "$LINT" --config-json - "$TPL" >/dev/null 2>&1; then
    ok "template passes lint-article unchanged (schema + pointer block clean)"
  else
    err "template does NOT lint clean:"
    printf '%s' "$CFG" | python3 "$LINT" --config-json - "$TPL" >&2 || true
  fi
fi

# 3. The skill points readers at the starter template as the way to begin.
grep -q 'starter-article.md' "$SKILL" && ok "SKILL.md references the starter template" \
  || err "SKILL.md does not point at starter-article.md"
grep -qi 'starter template' "$SKILL" && ok "SKILL.md documents the starter template as the way to begin" \
  || err "SKILL.md lacks starter-template guidance"

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-starter checks passed.\n'; exit 0
else
  printf '\nreview-starter checks FAILED.\n' >&2; exit 1
fi
