#!/usr/bin/env sh
# check-config-resolution.sh — verify the documented user-config resolution
# order and the zero-edit identity guarantee (Story 1.4). POSIX shell + stdlib
# Python only (no PyYAML).
#
# Covers: the resolver parses the shipped example; machine-global loads; a
# repo-local file deep-merges over it (maps recurse, scalars/lists replaced);
# two fully distinct identities resolve to distinct values (the zero-edit proof
# proxy, exercised with a whole second identity, not one field); and the
# empty/no-config path errors rather than inventing a default.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RES="scripts/resolve-user-config.py"
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

# 1. Parses the shipped example (nested maps, block scalar, inline lists).
got=$($PY --global-config config/user-config.example.yaml get owner.site_url)
eq "example: owner.site_url parses" "$got" "https://example.com"
got=$($PY --global-config config/user-config.example.yaml get frontmatter.enums.mode)
eq "example: inline list parses" "$got" '["canonical", "external"]'
$PY --global-config config/user-config.example.yaml get pointer_block.template \
  | grep -q 'I write about {focus_areas}' \
  && ok "example: block scalar template parses" || err "block scalar did not parse"

# --- fixtures -------------------------------------------------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

cat > "$work/global.yaml" <<'YAML'
owner:
  name: "Ada Lovelace"
  site_url: "https://ada.example"
  focus_areas: "analytical engines"
pointer_block:
  newsletter:
    status: coming-soon
YAML

# 2. Machine-global alone resolves.
eq "global: name resolves" \
   "$($PY --global-config "$work/global.yaml" --repo-config /nonexistent get owner.name)" \
   "Ada Lovelace"

# 3. Repo-local override is a DEEP per-key merge (map recurses, scalar replaced,
#    untouched keys retained from global).
cat > "$work/repo.yaml" <<'YAML'
owner:
  site_url: "https://ada.dev"
pointer_block:
  newsletter:
    status: live
YAML
eq "merge: overridden scalar wins (owner.site_url)" \
   "$($PY --global-config "$work/global.yaml" --repo-config "$work/repo.yaml" get owner.site_url)" \
   "https://ada.dev"
eq "merge: untouched sibling retained (owner.name)" \
   "$($PY --global-config "$work/global.yaml" --repo-config "$work/repo.yaml" get owner.name)" \
   "Ada Lovelace"
eq "merge: nested map recurses (newsletter.status)" \
   "$($PY --global-config "$work/global.yaml" --repo-config "$work/repo.yaml" get pointer_block.newsletter.status)" \
   "live"

# 3b. Lists are replaced wholesale, not appended.
cat > "$work/g2.yaml" <<'YAML'
frontmatter:
  schema: [slug, title, date]
YAML
cat > "$work/r2.yaml" <<'YAML'
frontmatter:
  schema: [only]
YAML
eq "merge: list replaced wholesale (not appended)" \
   "$($PY --global-config "$work/g2.yaml" --repo-config "$work/r2.yaml" get frontmatter.schema)" \
   '["only"]'

# 4. Zero-edit proof: a fully distinct SECOND identity yields distinct values
#    from the same engine, no skill/script edits.
cat > "$work/grace.yaml" <<'YAML'
owner:
  name: "Grace Hopper"
  site_url: "https://grace.example"
  focus_areas: "compilers"
YAML
a_name=$($PY --global-config "$work/global.yaml" --repo-config /nonexistent get owner.name)
b_name=$($PY --global-config "$work/grace.yaml"  --repo-config /nonexistent get owner.name)
a_site=$($PY --global-config "$work/global.yaml" --repo-config /nonexistent get owner.site_url)
b_site=$($PY --global-config "$work/grace.yaml"  --repo-config /nonexistent get owner.site_url)
if [ "$a_name" != "$b_name" ] && [ "$a_site" != "$b_site" ]; then
  ok "zero-edit: distinct identity in -> distinct identity out ($a_name vs $b_name)"
else
  err "second identity did not fully differ ($a_name/$a_site vs $b_name/$b_site)"
fi

# 5. Empty path: no config anywhere -> error, no invented default.
set +e
out=$($PY --global-config /nonexistent --repo-config /nonexistent resolved 2>&1); rc=$?
set -e
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no user-config resolved'; then
  ok "empty path errors (no baked-in default identity)"
else
  err "expected an error when no config resolves (rc=$rc)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll config-resolution checks passed.\n'; exit 0
else
  printf '\nconfig-resolution checks FAILED.\n' >&2; exit 1
fi
