#!/usr/bin/env sh
# check-user-config-example.sh — verify config/user-config.example.yaml declares
# every identity value a skill needs (CAP-6, Story 1.2) and leaks no real
# identity. Zero dependencies: POSIX shell + grep (no PyYAML — host repos
# guarantee no installed deps, so the example is checked structurally).
#
# It asserts the example carries: owner identity, the full pointer-block
# template + all its variables and the newsletter state, the target-site
# `article` frontmatter schema (both canonical and mode:external shapes), and a
# structured per-language syndication policy — and that all values stay
# placeholders (no shipped real identity).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

f="config/user-config.example.yaml"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

if [ ! -f "$f" ]; then err "missing $f"; printf '\nConfig checks FAILED.\n' >&2; exit 1; fi
ok "present: $f"

# has KEY DESC — assert a literal key/token appears in the example.
has() {
  if grep -q -- "$1" "$f"; then ok "$2"; else err "missing $2 (expected '$1')"; fi
}

# 1. Owner identity.
has 'name:'        'owner.name'
has 'site_url:'    'owner.site_url'
has 'site_name:'   'owner.site_name'
has 'focus_areas:' 'owner.focus_areas'

# 2. Pointer block: template + every variable it consumes + newsletter state.
has 'pointer_block:'   'pointer_block section'
has 'template:'        'pointer_block.template'
for v in '{focus_areas}' '{site_name}' '{site_url}' '{related_line}' '{newsletter_line}' '{counterpart_line}'; do
  has "$v" "pointer-block variable $v"
done
has 'status: coming-soon' 'newsletter.status (state that drives the RSS/capture line)'
has 'ja_counterpart:'     'JA counterpart line'
has 'en_counterpart:'     'EN counterpart line'

# 3. Frontmatter schema: field set + both mode shapes + language enum.
has 'frontmatter:' 'frontmatter section'
for k in slug title date mode language summary topics related; do
  has "- $k" "frontmatter field: $k"
done
has 'canonical'  'frontmatter mode: canonical'
has 'external'   'frontmatter mode: external'
has 'en, ja'     'language enum [en, ja]'
has 'related_keys:' 'related sub-keys (projects/publications/products)'

# 4. Syndication policy: structured, per-language, both platforms.
has 'syndication:'  'syndication section'
has 'policy:'       'syndication.policy'
has 'devto'         'dev.to variant (EN canonical syndication)'
has 'zenn'          'Zenn variant (JA external)'
has 'canonical_url_base:'       'dev.to canonical_url policy'
has 'external_record_max_lines' 'Zenn mode:external record constraint'

# 5. No real identity shipped — the example must stay generic placeholders.
if grep -qiE 'tim-nish|imanishi' "$f"; then
  err "real identity leaked into the shipped example (found tim-nish/imanishi) — keep it in your private config"
else
  ok "no real identity in the shipped example (placeholders only)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll user-config example checks passed.\n'; exit 0
else
  printf '\nUser-config example checks FAILED.\n' >&2; exit 1
fi
