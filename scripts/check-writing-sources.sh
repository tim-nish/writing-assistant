#!/usr/bin/env sh
# check-writing-sources.sh — verify the writing-sources schema/example and the
# draft-location resolver (Story 1.3). POSIX shell + stdlib Python only.
#
# Covers: the example declares sources[{path,include?}] + output.drafts; the
# resolver returns output.drafts, exits 3 when it is undeclared (no hardcoded
# default), writes the key back preserving comments and idempotently, resolves
# paths against the host-repo root, and enforces the CAP-2 read boundary.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

EX="config/writing-sources.example.yaml"
RES="scripts/resolve-writing-sources.py"
PY="python3 $root/$RES"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -q -- "$1" "$2"; then ok "$3"; else err "missing $3 (expected '$1' in $2)"; fi; }

# --- 0. Resolver compiles ---------------------------------------------------
if python3 -c "import py_compile,sys; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null; then
  ok "resolver compiles ($RES)"
else
  err "resolver has a syntax error ($RES)"; printf '\nChecks FAILED.\n' >&2; exit 1
fi

# --- 1. Example schema ------------------------------------------------------
[ -f "$EX" ] && ok "present: $EX" || err "missing $EX"
has 'sources:'   "$EX" 'sources list'
has '- path:'    "$EX" 'source path entry'
has 'path: .'    "$EX" 'host-repo entry (path: .)'
has 'include:'   "$EX" 'optional include globs'
has 'output:'    "$EX" 'output section'
has 'drafts:'    "$EX" 'output.drafts key'

# --- behavioral fixtures ----------------------------------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/host/sub" "$work/research-notes/notes" "$work/other-repo"

# 2. draft-location returns the declared value.
cat > "$work/host/writing-sources.yaml" <<'YAML'
# my sources
sources:
  - path: .
  - path: ../research-notes
    include: ["notes/**"]
output:
  # where drafts go
  drafts: articles/drafts/
YAML
got=$($PY --root "$work/host" draft-location)
[ "$got" = "articles/drafts/" ] && ok "draft-location returns declared value" \
  || err "draft-location returned '$got', expected 'articles/drafts/'"

# 2b. --root works AFTER the subcommand too (the form the SKILLs document, #138):
#     `resolve-writing-sources.py <cmd> --root <host>` must not error.
# stdout only: the fixture uses legacy in-repo placement, which (correctly)
# emits the O1 deprecation notice on stderr (Story 13.23, #211).
after=$($PY draft-location --root "$work/host" 2>/dev/null)
[ "$after" = "articles/drafts/" ] \
  && ok "--root accepted AFTER the subcommand (matches the documented invocation, #138)" \
  || err "--root after the subcommand failed: '$after'"
# every subcommand accepts --root in that position (no 'unrecognized arguments').
for c in draft-location sources is-declared files; do
  case "$c" in is-declared) extra=".";; *) extra="";; esac
  $PY "$c" $extra --root "$work/host" >/dev/null 2>&1
  [ $? -ne 2 ] && ok "subcommand '$c' accepts --root after it" \
    || err "subcommand '$c' rejects --root after it (argparse code 2)"
done

# 3. Missing output.drafts -> exit 3 (prompt), no fallback.
cat > "$work/host2.yaml" <<'YAML'
sources:
  - path: .
YAML
mkdir -p "$work/host2"; mv "$work/host2.yaml" "$work/host2/writing-sources.yaml"
set +e; $PY --root "$work/host2" draft-location >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 3 ] && ok "undeclared output.drafts exits 3 (asks, no default)" \
  || err "expected exit 3 for missing output.drafts, got $rc"

# 4. Write-back: preserves comments, is consent-gated (only on set), idempotent.
$PY --root "$work/host2" set-draft-location "out/drafts/" >/dev/null
grep -q '^sources:' "$work/host2/writing-sources.yaml" && ok "write-back preserved existing content/comments" \
  || err "write-back clobbered the file"
got=$($PY --root "$work/host2" draft-location)
[ "$got" = "out/drafts/" ] && ok "second resolution reads written key silently" \
  || err "post-write draft-location returned '$got'"
before=$(cat "$work/host2/writing-sources.yaml")
$PY --root "$work/host2" set-draft-location "out/drafts/" >/dev/null
after=$(cat "$work/host2/writing-sources.yaml")
[ "$before" = "$after" ] && ok "re-writing the same value is a no-op (idempotent)" \
  || err "set-draft-location was not idempotent"

# 5. Update in place preserves the value's own comment line above it.
$PY --root "$work/host" set-draft-location "new/loc/" >/dev/null
grep -q '# where drafts go' "$work/host/writing-sources.yaml" && ok "inline comment above the key preserved on update" \
  || err "update dropped the key's comment"
got=$($PY --root "$work/host" draft-location)
[ "$got" = "new/loc/" ] && ok "update replaced the value" || err "update left value '$got'"

# 6. CAP-2 boundary + host-root path resolution.
$PY --root "$work/host" is-declared "sub/file.md"  && ok "declared: file under host root (path: .)" \
  || err "file under host root should be declared"
set +e
$PY --root "$work/host" is-declared "../other-repo/x.md" >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -ne 0 ] && ok "CAP-2: undeclared sibling repo is rejected" \
  || err "undeclared sibling must not be declared"
$PY --root "$work/host" is-declared "../research-notes/notes/a.md" && ok "declared: listed sibling checkout" \
  || err "listed sibling should be declared"

# 7. Negative invariant: the resolver has no hardcoded 'drafts/' default path.
if grep -F 'drafts/' "$RES" >/dev/null 2>&1; then
  err "resolver contains a literal 'drafts/' path (possible hardcoded default): $(grep -nF 'drafts/' "$RES" | head -2 | tr '\n' ' ')"
else
  ok "no hardcoded 'drafts/' default in the resolver"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll writing-sources checks passed.\n'; exit 0
else
  printf '\nwriting-sources checks FAILED.\n' >&2; exit 1
fi
