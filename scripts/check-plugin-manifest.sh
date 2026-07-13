#!/usr/bin/env sh
# check-plugin-manifest.sh — verify the plugin manifest (Story 6.1):
# .claude-plugin/plugin.json is valid JSON declaring name/version/description/
# author, names the three exposed skills, and the packaging is additive — the
# three skill directories exist for Claude Code's skills/ auto-discovery and no
# skill content is required to change. POSIX shell + stdlib Python (json).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

MANIFEST=".claude-plugin/plugin.json"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$MANIFEST" ] && ok "plugin.json exists" || { err "plugin.json missing"; printf '\nFAILED.\n' >&2; exit 1; }

# Valid JSON + required/expected fields via stdlib json.
python3 - "$MANIFEST" <<'PY'
import json, sys, re
m = json.load(open(sys.argv[1]))
assert m.get("name") == "writing-assistant", f'name={m.get("name")!r}'
assert re.fullmatch(r"\d+\.\d+\.\d+", m.get("version", "")), f'version={m.get("version")!r}'
assert isinstance(m.get("description"), str) and m["description"].strip(), "description missing"
assert isinstance(m.get("author"), dict) and m["author"].get("name"), "author.name missing"
kw = m.get("keywords", [])
for skill in ("draft-article", "review-article", "harvest"):
    assert skill in kw, f"manifest does not name skill {skill!r} in keywords"
# Stay generic: no site-identity proxy leaks into packaging metadata.
assert "tim-nish.dev" not in json.dumps(m), "site-identity proxy leaked into plugin.json"
PY
if [ $? -eq 0 ]; then
  ok "plugin.json is valid JSON with name/version/description/author + skill names"
else
  err "plugin.json failed field validation"
fi

# Skills are auto-discovered from skills/<name>/SKILL.md — the plugin exposes
# three skill slots. All three directories must exist (declared surface).
for s in draft-article review-article harvest; do
  [ -d "skills/$s" ] && ok "skill directory skills/$s/ present" || err "skills/$s/ missing"
done

# The skills implemented on the default branch are discoverable now; the
# review-article SKILL.md ships via the Epic 5 stack.
for s in draft-article harvest; do
  [ -f "skills/$s/SKILL.md" ] && ok "skills/$s/SKILL.md discoverable" || err "skills/$s/SKILL.md missing"
done

# Additive packaging: adding the manifest (Story 6.1) must not delete or empty
# any skill's SKILL.md. The original guard froze the whole skills/ tree against
# `main`, which turned a one-time "this commit changes no skill file" assertion
# into a standing gate that blocked every later skill edit (F36). Assert the
# real invariant instead — the three declared skills still ship a non-empty
# SKILL.md — so skills can evolve while packaging stays additive.
for s in draft-article review-article harvest; do
  if [ -s "skills/$s/SKILL.md" ]; then
    ok "packaging additive: skills/$s/SKILL.md still present and non-empty"
  else
    err "packaging regression: skills/$s/SKILL.md missing or empty"
  fi
done

if [ "$fail" -eq 0 ]; then
  printf '\nAll plugin-manifest checks passed.\n'; exit 0
else
  printf '\nplugin-manifest checks FAILED.\n' >&2; exit 1
fi
