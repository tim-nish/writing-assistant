#!/usr/bin/env sh
# check-platform-profiles.sh — verify machine-global platform profiles resolve
# as declarations (Story 16.1, SPEC-platform-variants CAP-2). POSIX sh + stdlib
# Python only.
#
# Covers the story's ACs:
#   AC1  each profile loads from one file under the resolver's repo-config dir,
#        declaring platform/audience/language/packaging/distribution_hook; no
#        path literal in the resolver's callers (it goes through resolve-paths).
#   AC2  the Zenn profile's packaging carries the target directory layout, and
#        the articles repo still owns its record schema (layout is a conformance
#        record, not stored in either working tree beyond this machine-global file).
#   AC3  legacy syndication.variants.* keys produce per-key deprecation pointers;
#        profiles migrate nothing (their fields are new declarations).
#   AC4  intent (canonicality/mode) is unrepresentable in a profile — rejected.
#   AC5  adding a third platform is one file and zero stage-code changes.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RES="scripts/resolve-platform-profiles.py"
PY="python3 $root/$RES"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else err "$1 (got '$2', want '$3')"; fi; }

# 0. Resolver compiles.
if python3 -c "import py_compile; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null; then
  ok "resolver compiles"
else
  err "resolver syntax error"; printf '\nChecks FAILED.\n' >&2; exit 1
fi

# 1. The two shipped example profiles exist.
for f in devto zenn; do
  if [ -f "config/platform-profiles/$f.example.yaml" ]; then
    ok "shipped example profile: $f"
  else
    err "missing config/platform-profiles/$f.example.yaml"
  fi
done

# Fixture: a live profiles dir seeded from the shipped examples (strip .example).
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/pp"
cp config/platform-profiles/devto.example.yaml "$work/pp/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$work/pp/zenn.yaml"

# 2. list resolves both platforms.
got=$($PY list --root "$work" --profiles-dir "$work/pp" | tr '\n' ',' | sed 's/,$//')
eq "list resolves both example profiles" "$got" "devto,zenn"

# 3. AC1: devto declares the required keys; get emits them.
got=$($PY get devto --root "$work" --profiles-dir "$work/pp" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(all(k in d for k in ('platform','audience','language','packaging','distribution_hook')))")
eq "AC1 devto declares all required top-level keys" "$got" "True"
got=$($PY get devto --root "$work" --profiles-dir "$work/pp" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['packaging']['tag_cap'])")
eq "AC1 devto packaging.tag_cap parses as int" "$got" "4"

# 4. AC2: zenn packaging carries the target directory layout.
got=$($PY get zenn --root "$work" --profiles-dir "$work/pp" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['packaging']['layout']['dir'])")
eq "AC2 zenn packaging.layout.dir present" "$got" "articles/"
got=$($PY get zenn --root "$work" --profiles-dir "$work/pp" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['packaging']['visuals'])")
eq "AC2/CAP-5 zenn packaging.visuals present" "$got" "html-comment-blocked"

# 5. AC1 resolver location goes through the path resolver — no literal
#    ~/.config path is composed in the resolver's own body.
if grep -nE '\.config/writing-assistant' "$RES" >/dev/null 2>&1; then
  err "AC1 resolver hardcodes a config path literal (must use resolve-paths.py)"
else
  ok "AC1 resolver composes no config-path literal (uses repo_config_dir)"
fi

# 6. AC5: a third platform is one file, zero code change.
cat > "$work/pp/hashnode.yaml" <<'YAML'
platform: hashnode
audience: en-practitioner
language: en
packaging:
  frontmatter: [title, tags]
  tag_cap: 5
  canonical_url:
    policy: point-to-site
    format: "{base}/{slug}"
  visuals: mermaid-embedded
distribution_hook: newsletter-follow
YAML
got=$($PY list --root "$work" --profiles-dir "$work/pp" | tr '\n' ',' | sed 's/,$//')
eq "AC5 third platform resolves with zero code change" "$got" "devto,hashnode,zenn"
rm "$work/pp/hashnode.yaml"

# 7. AC4: a profile declaring an intent key is rejected.
cat > "$work/pp/intent.yaml" <<'YAML'
platform: intent
audience: en-practitioner
language: en
mode: canonical
packaging:
  frontmatter: [title]
  visuals: mermaid-embedded
distribution_hook: x
YAML
set +e
out=$($PY validate --root "$work" --profiles-dir "$work/pp" 2>&1); rc=$?
set -e
if [ "$rc" -eq 4 ] && printf '%s' "$out" | grep -q "intent.yaml] mode:"; then
  ok "AC4 intent key in a profile is rejected (exit 4)"
else
  err "AC4 intent-key rejection (rc=$rc, out='$out')"
fi
rm "$work/pp/intent.yaml"

# 8. validate: a profile missing a required key is rejected.
cat > "$work/pp/bad.yaml" <<'YAML'
platform: bad
language: en
packaging: {}
distribution_hook: x
YAML
set +e
out=$($PY validate --root "$work" --profiles-dir "$work/pp" 2>&1); rc=$?
set -e
if [ "$rc" -eq 4 ] && printf '%s' "$out" | grep -q "bad.yaml] audience:"; then
  ok "missing required key is rejected (exit 4)"
else
  err "missing-key rejection (rc=$rc, out='$out')"
fi
rm "$work/pp/bad.yaml"

# 9. clean fixture validates cleanly.
set +e
$PY validate --root "$work" --profiles-dir "$work/pp" >/dev/null 2>&1; rc=$?
set -e
eq "clean profiles validate (exit 0)" "$rc" "0"

# 10. AC3: legacy syndication.variants.* keys produce deprecation pointers.
cat > "$work/uc.yaml" <<'YAML'
owner:
  name: X
syndication:
  variants:
    devto:
      canonical_url_base: "https://example.com/articles"
    zenn:
      external_record_max_lines: 20
      body_forbidden: true
YAML
got=$($PY deprecations --root "$work" --global-config "$work/uc.yaml" \
  --repo-config "$work/none.yaml" | grep -c '^deprecated: syndication.variants')
eq "AC3 each legacy variants.* key gets a deprecation pointer" "$got" "3"

# 11. AC3: a config with no legacy keys reports clean.
printf 'owner:\n  name: X\n' > "$work/clean.yaml"
got=$($PY deprecations --root "$work" --global-config "$work/clean.yaml" \
  --repo-config "$work/none.yaml")
eq "AC3 clean config reports no legacy keys" "$got" "ok: no legacy syndication.variants.* keys present"

if [ "$fail" -eq 0 ]; then
  printf 'All platform-profile checks passed.\n'; exit 0
else
  printf '\nChecks FAILED.\n' >&2; exit 1
fi
