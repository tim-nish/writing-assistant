#!/usr/bin/env sh
# parallel-safe
# covers: config/user-config.example.yaml scripts/lint-article scripts/release-strip.sh
# covers-note (#1321): the derivation also proposed .claude/skills/bmad-*. Those tokens are
#   paths inside the mktemp host tree this check BUILDS, not repo paths it reads; the
#   extractor cannot tell "$t/.claude/skills/..." from a tracked path. Removed at ratification.
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
# The token alternative spans the path with [^[:space:]]* — a path token carries
# no whitespace. It must NOT be [^\n]: POSIX ERE has no \n escape inside a
# bracket expression, so [^\n] reads as "not a backslash and not the letter n",
# which silently let through every reference with an n in the intervening text
# (src=main/_bmad-output/, path=gen/_bmad-output/). Issue #1068.
REFPAT='\]\((\./)?(_bmad|\.claude/skills/bmad-)|(src|path|dir|file)[^[:space:]]*_bmad-output/'

# 5a. Assert the pattern BEFORE trusting it. An inert assertion passes silently,
#     which is the worst failure mode for a publication-boundary guard: green
#     reads as evidence of cleanliness. Probes carry an `n` between the token and
#     _bmad-output/ on purpose — those are exactly the ones [^\n] used to miss.
for probe in 'src=main/_bmad-output/x' 'path=gen/_bmad-output/y' \
             'dir=json/_bmad-output/z' 'file=n/_bmad-output/w' \
             'srcZZZ_bmad-output/q' 'see ](./_bmad/notes.md)'; do
  printf '%s\n' "$probe" | grep -qE "$REFPAT" \
    && ok "reference pattern catches: $probe" \
    || err "reference pattern MISSES a functional reference: $probe"
done
for probe in 'prose about the src file and bmad output, no path' \
             'plain line with no reference at all'; do
  printf '%s\n' "$probe" | grep -qE "$REFPAT" \
    && err "reference pattern false-positives on: $probe" \
    || ok "reference pattern ignores: $probe"
done

if printf '%s\n' "$surface" | xargs -r grep -nE "$REFPAT" 2>/dev/null \
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
