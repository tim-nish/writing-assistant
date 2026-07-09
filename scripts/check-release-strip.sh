#!/usr/bin/env sh
# check-release-strip.sh — verify the mechanical release-strip guarantee (Story
# 6.4): release-strip.sh removes EXACTLY _bmad/, _bmad-output/, and
# .claude/skills/bmad-*; leaves a complete, functioning plugin (specs/ + all
# shipped surface intact); and the shipped tree carries no dangling functional
# reference into the removed paths. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

STRIP="$root/scripts/release-strip.sh"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$STRIP" ] && ok "release-strip.sh exists" || { err "release-strip.sh missing"; printf '\nFAILED.\n' >&2; exit 1; }
[ -x "$STRIP" ] && ok "release-strip.sh is executable" || err "release-strip.sh not executable"
sh -n "$STRIP" 2>/dev/null && ok "release-strip.sh parses" || err "release-strip.sh has a syntax error"

# Build a synthetic tree with all three removable classes + content that must survive.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
t="$work/repo"
mkdir -p "$t/_bmad/x" "$t/_bmad-output/y" \
         "$t/.claude/skills/bmad-dev-story" "$t/.claude/skills/bmad-help" \
         "$t/.claude/skills/keep-me" \
         "$t/specs/spec-x" "$t/skills/harvest" "$t/scripts" "$t/config" "$t/.claude-plugin"
echo bmad          > "$t/_bmad/x/a.txt"
echo bmad          > "$t/_bmad-output/y/b.md"
echo bmadskill     > "$t/.claude/skills/bmad-dev-story/SKILL.md"
echo keepskill     > "$t/.claude/skills/keep-me/SKILL.md"
echo spec          > "$t/specs/spec-x/SPEC.md"
echo skill         > "$t/skills/harvest/SKILL.md"
echo script        > "$t/scripts/lint-article"
echo cfg           > "$t/config/user-config.example.yaml"
echo '{}'          > "$t/.claude-plugin/plugin.json"
echo readme        > "$t/README.md"

# 1. --dry-run removes nothing.
"$STRIP" --dry-run --root "$t" >"$work/dry.out" 2>&1
if [ -d "$t/_bmad" ] && [ -d "$t/_bmad-output" ] && [ -d "$t/.claude/skills/bmad-dev-story" ]; then
  ok "--dry-run removes nothing"
else
  err "--dry-run deleted files"
fi
grep -q 'would remove' "$work/dry.out" && ok "--dry-run reports the targets" || err "--dry-run reported nothing"

# 2. Real strip removes exactly the three classes.
"$STRIP" --root "$t" >"$work/run.out" 2>&1
[ ! -e "$t/_bmad" ]        && ok "removed _bmad/" || err "_bmad/ not removed"
[ ! -e "$t/_bmad-output" ] && ok "removed _bmad-output/" || err "_bmad-output/ not removed"
[ ! -e "$t/.claude/skills/bmad-dev-story" ] && [ ! -e "$t/.claude/skills/bmad-help" ] \
  && ok "removed .claude/skills/bmad-*" || err ".claude/skills/bmad-* not removed"

# 3. Everything else survives — a complete, functioning plugin, specs intact.
for keep in ".claude/skills/keep-me/SKILL.md" "specs/spec-x/SPEC.md" \
            "skills/harvest/SKILL.md" "scripts/lint-article" \
            "config/user-config.example.yaml" ".claude-plugin/plugin.json" "README.md"; do
  [ -e "$t/$keep" ] && ok "kept $keep" || err "removed non-BMAD path: $keep"
done

# 4. Idempotent: a second run is a no-op.
"$STRIP" --root "$t" >"$work/again.out" 2>&1
grep -qi 'nothing to remove' "$work/again.out" && ok "second run is a no-op" || err "not idempotent"

# 5. No dangling FUNCTIONAL references into the removed paths in the shipped tree.
#    Scan skills/, config/, .claude-plugin/ and non-tooling scripts for markdown
#    links or path refs pointing into _bmad*/ or .claude/skills/bmad-*.
surface=$(git ls-files -- skills config .claude-plugin scripts README.md \
          | grep -vE 'release-strip\.sh|check-release-strip\.sh|check-skeleton\.sh')
# functional reference = a link target or path token, e.g. ](_bmad, ](./_bmad,
# "_bmad-output/...", .claude/skills/bmad-...  (prose in backticks is not a link).
if printf '%s\n' "$surface" | xargs -r grep -nE \
     '\]\((\./)?(_bmad|\.claude/skills/bmad-)|(src|path|dir|file)[^\n]*_bmad-output/' 2>/dev/null \
     | grep -q .; then
  err "a shipped file has a functional reference into a removed path"
else
  ok "no dangling functional references into removed paths"
fi

# 6. The script targets EXACTLY the three documented classes (mechanical, no judgment).
for cls in '_bmad' '_bmad-output' '.claude/skills/bmad-'; do
  grep -qF "$cls" "$STRIP" && ok "strip targets $cls" || err "strip does not target $cls"
done

if [ "$fail" -eq 0 ]; then
  printf '\nAll release-strip checks passed.\n'; exit 0
else
  printf '\nrelease-strip checks FAILED.\n' >&2; exit 1
fi
