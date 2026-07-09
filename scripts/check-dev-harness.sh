#!/usr/bin/env sh
# check-dev-harness.sh — verify the local-skill development harness (Story 1.5).
# POSIX shell only.
#
# Proves, against a throwaway plugin fixture + host repo (so the real repo is
# untouched): symlink-mode loads skills into a host's .claude/skills without
# copying and with no manifest present; bundled assets resolve through the
# symlink; unlink is surgical; re-link is idempotent and won't clobber a real
# skill. Also checks the README documents the dev commands (a tested contract)
# and that any real SKILL.md uses ${CLAUDE_SKILL_DIR} rather than cwd-coupled
# asset paths.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DL="scripts/dev-link.sh"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 0. Script parses.
if sh -n "$DL" 2>/dev/null; then ok "dev-link.sh parses"; else err "dev-link.sh syntax error"; fi

# 1. plugin-dir command works with NO manifest present (additive packaging).
[ ! -f .claude-plugin/plugin.json ] && ok "no plugin.json yet (harness must work without it)" \
  || ok "plugin.json present (harness must still work)"
sh "$DL" plugin-dir-cmd | grep -q -- '--plugin-dir' \
  && ok "plugin-dir-cmd prints a --plugin-dir invocation" || err "plugin-dir-cmd output wrong"

# --- fixtures: a fake plugin + a fake host repo -----------------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fx="$work/plugin"; host="$work/host"
mkdir -p "$fx/skills/draft-article/frameworks" "$fx/skills/harvest" "$host"
# a real skill with a bundled asset, and NO .claude-plugin/ manifest at all
printf -- '---\nname: draft-article\ndescription: test\n---\nUse ${CLAUDE_SKILL_DIR}/frameworks/F1.md\n' \
  > "$fx/skills/draft-article/SKILL.md"
printf 'F1 asset body\n' > "$fx/skills/draft-article/frameworks/F1.md"
printf -- '---\nname: harvest\ndescription: test\n---\nbody\n' > "$fx/skills/harvest/SKILL.md"

run() { DEV_LINK_PLUGIN_ROOT="$fx" sh "$root/$DL" "$@"; }

# 2. link creates symlinks (not copies) with the manifest absent.
run link "$host" >/dev/null
if [ -L "$host/.claude/skills/draft-article" ] && [ -L "$host/.claude/skills/harvest" ]; then
  ok "link creates symlinks in host .claude/skills"
else
  err "link did not create symlinks"
fi
# It must be a link back to the fixture, not a copied file tree.
if [ "$(readlink "$host/.claude/skills/draft-article")" = "$fx/skills/draft-article" ]; then
  ok "symlink points back to the plugin (no files copied in)"
else
  err "symlink target wrong (files may have been copied)"
fi

# 3. SKILL.md and bundled asset resolve THROUGH the symlink (registration path).
[ -f "$host/.claude/skills/draft-article/SKILL.md" ] \
  && ok "SKILL.md readable through the symlink (skill would register)" \
  || err "SKILL.md not reachable through symlink"
[ -f "$host/.claude/skills/draft-article/frameworks/F1.md" ] \
  && [ "$(cat "$host/.claude/skills/draft-article/frameworks/F1.md")" = "F1 asset body" ] \
  && ok "bundled asset resolves through the symlink (\${CLAUDE_SKILL_DIR} path)" \
  || err "bundled asset not reachable through symlink"

# 4. status reflects linked state; unlink is surgical; fixture untouched.
run status "$host" | grep -q '^linked   draft-article' && ok "status reports linked" || err "status wrong"
run unlink "$host" >/dev/null
[ ! -e "$host/.claude/skills/draft-article" ] && ok "unlink removes the symlink" || err "unlink left a link"
[ -f "$fx/skills/draft-article/SKILL.md" ] && ok "unlink left the plugin fixture intact" || err "unlink damaged the plugin"

# 5. Re-link is idempotent and refuses to clobber a real (non-symlink) skill.
run link "$host" >/dev/null; run link "$host" >/dev/null
[ -L "$host/.claude/skills/harvest" ] && ok "re-link is idempotent" || err "re-link broke"
run unlink "$host" >/dev/null
mkdir -p "$host/.claude/skills/harvest"        # a pre-existing REAL skill dir
printf 'real\n' > "$host/.claude/skills/harvest/SKILL.md"
run link "$host" 2>/dev/null || true
if [ ! -L "$host/.claude/skills/harvest" ] && [ "$(cat "$host/.claude/skills/harvest/SKILL.md")" = "real" ]; then
  ok "link refuses to clobber a pre-existing non-symlink skill"
else
  err "link clobbered a real skill dir"
fi

# 6. README documents the dev commands (a tested contract, not illustration).
for token in 'claude --plugin-dir' 'dev-link.sh' 'CLAUDE_SKILL_DIR'; do
  grep -q -- "$token" README.md && ok "README documents: $token" || err "README missing: $token"
done

# 7. Convention guard on real tracked SKILL.md (vacuous until Epics 3-5 land):
#    bundled-asset references must use \${CLAUDE_SKILL_DIR} and never couple to
#    cwd or a hardcoded plugin path.
skills=$(git ls-files -- 'skills/**/SKILL.md' 2>/dev/null || true)
if [ -z "$skills" ]; then
  ok "convention guard — no SKILL.md files yet (vacuously clean)"
else
  bad=0
  for f in $skills; do
    if grep -Eq '\$\(pwd\)|/workspaces/|\.\./(frameworks|scripts)' "$f"; then
      err "SKILL.md couples to cwd/hardcoded path: $f"; bad=1
    fi
    if grep -Eq '(frameworks/|review-prompts\.md|scripts/)' "$f" && ! grep -q 'CLAUDE_SKILL_DIR' "$f"; then
      err "SKILL.md references bundled assets without \${CLAUDE_SKILL_DIR}: $f"; bad=1
    fi
  done
  [ "$bad" -eq 0 ] && ok "convention guard — SKILL.md files use \${CLAUDE_SKILL_DIR}, no cwd coupling"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll dev-harness checks passed.\n'; exit 0
else
  printf '\ndev-harness checks FAILED.\n' >&2; exit 1
fi
