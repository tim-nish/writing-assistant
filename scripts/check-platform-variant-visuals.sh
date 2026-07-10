#!/usr/bin/env sh
# check-platform-variant-visuals.sh — verify platform variants handle visual
# rendering divergence (Story 8.5, SPEC-article-visuals CAP-5): the Zenn variant
# embeds Mermaid source directly (native render, zero manual work); the dev.to
# variant carries the Mermaid/figure-spec in an HTML comment and lists each
# unrendered figure as a publish blocker in the completion-summary blocker bucket
# (Story 7.5). POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "draft-article SKILL.md exists" \
  || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

sec=$(awk '/^### Visual rendering per platform/{f=1} f && /^#{2,3} / && !/Visual rendering per platform/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "platform visual-rendering subsection present" \
  || { err "subsection missing"; printf '\nFAILED.\n' >&2; exit 1; }

hasin() { printf '%s\n' "$1" | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

# Zenn: embeds Mermaid directly, zero manual work.
hasin "$sec" 'Zenn'                       "names the Zenn variant"
hasin "$sec" 'embeds the Mermaid source directly\|embeds.*Mermaid' "Zenn embeds Mermaid source directly"
hasin "$sec" 'natively\|zero manual work' "Zenn renders natively / zero manual work"

# dev.to: HTML comment + publish-blocker listing in the 7.5 blocker bucket.
hasin "$sec" 'dev.to'                     "names the dev.to variant"
hasin "$sec" 'HTML comment'               "dev.to carries the source in an HTML comment"
hasin "$sec" 'publish.blocker\|publish-blocker bucket\|blocker bucket' "dev.to lists unrendered figures as publish blockers"
hasin "$sec" 'unrendered figure'          "each unrendered figure is blocker-listed"
hasin "$sec" 'Story 7.5\|CAP-6\|completion summary' "blocker goes in the 7.5 completion-summary bucket"

# Figure-spec (non-Mermaid) handled in both variants.
hasin "$sec" 'figure-spec\|figure spec'   "figure-spec visuals handled per platform too"

if [ "$fail" -eq 0 ]; then
  printf '\nAll platform-variant-visual checks passed.\n'; exit 0
else
  printf '\nplatform-variant-visual checks FAILED.\n' >&2; exit 1
fi
