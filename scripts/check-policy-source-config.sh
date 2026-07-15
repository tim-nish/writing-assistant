#!/usr/bin/env sh
# check-policy-source-config.sh — verify the `policy_source` config block
# (Story 14.1, SPEC-policy-source-seam CAP-1). POSIX shell + stdlib Python only.
#
# Covers: absent block resolves {"declared": false} with byte-identical
# pipeline behavior (exit 0, no warning); a well-formed block resolves path
# (against the host root); a malformed block (missing path, or a leftover
# track/topics key — removed by Story 13.36, topic selection happens at draft
# time) exits 4 with per-key errors that stage-0 validation relays as
# configuration findings; a well-formed block whose path does not exist is
# NOT a config error (usability is read-time degradation, CAP-6).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RES="scripts/resolve-writing-sources.py"
VAL="scripts/validate-config.py"
PY="python3 $root/$RES"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null \
  && ok "resolver compiles" || { err "resolver syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- 1. Example documents the block ------------------------------------------
EX="config/writing-sources.example.yaml"
grep -q 'policy_source:' "$EX" && ok "example documents policy_source" \
  || err "example missing policy_source block"
grep -q 'track:' "$EX" && err "example still documents the removed track key" \
  || ok "example no longer documents track (removed, Story 13.36)"
grep -qi 'per article at draft time' "$EX" && ok "example points at draft-time topic selection" \
  || err "example missing the draft-time selection note"

# --- 2. Absent block: declared=false, exit 0, no stderr ----------------------
mkdir -p "$work/plain"
cat > "$work/plain/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
YAML
out=$($PY --root "$work/plain" policy-source 2>"$work/e1"); rc=$?
# "silent" means no POLICY warning; the fixture's legacy in-repo placement
# correctly draws the O1 deprecation notice (Story 13.23, #211) — exclude it.
if grep -v '^deprecated:' "$work/e1" | grep -q .; then policy_noise=1; else policy_noise=0; fi
[ "$rc" -eq 0 ] && [ "$out" = '{"declared": false}' ] && [ "$policy_noise" -eq 0 ] \
  && ok "absent block: {\"declared\": false}, exit 0, silent" \
  || err "absent block: got rc=$rc out='$out'"

# --- 3. Well-formed block resolves path (path-only since Story 13.36) ---------
mkdir -p "$work/host" "$work/product-lab"
cat > "$work/host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
policy_source:
  path: ../product-lab        # local checkout
YAML
out=$($PY --root "$work/host" policy-source)
python3 - "$out" "$work/product-lab" <<'PYEOF'
import json, os, sys
d = json.loads(sys.argv[1])
assert d["declared"] is True, d
assert d["path"] == os.path.realpath(sys.argv[2]), d["path"]
assert "track" not in d and "topics" not in d, d
PYEOF
[ $? -eq 0 ] && ok "well-formed block: path resolved against host root (path-only)" \
  || err "well-formed block did not resolve as expected: $out"

# --- 4. Malformed: missing path ------------------------------------------------
mkdir -p "$work/nopath"
cat > "$work/nopath/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path:
YAML
set +e; msg=$($PY --root "$work/nopath" policy-source 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.path' \
  && ok "missing path: exit 4, error names policy_source.path" \
  || err "missing path: rc=$rc msg='$msg'"

# --- 5. Removed keys: leftover track/topics are named errors, never ignored ----
mkdir -p "$work/many"
cat > "$work/many/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path: ../product-lab
  topics: [a.md, b.md]
YAML
set +e; msg=$($PY --root "$work/many" policy-source 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.topics' \
  && printf '%s' "$msg" | grep -qi 'removed' && printf '%s' "$msg" | grep -qi 'delete this line' \
  && ok "leftover topics key: exit 4, named as removed with the fix" \
  || err "leftover topics key: rc=$rc msg='$msg'"

# --- 6. Removed keys: leftover track ---------------------------------------------
mkdir -p "$work/esc"
cat > "$work/esc/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path: ../product-lab
  track: eval-engineering
YAML
set +e; msg=$($PY --root "$work/esc" policy-source 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.track' \
  && printf '%s' "$msg" | grep -qi 'draft-article Stage 2' \
  && ok "leftover track key: exit 4, fix points at draft-time selection" \
  || err "leftover track key: rc=$rc msg='$msg'"

# --- 7. Stage-0 validation relays malformed block as a finding -------------------
cat > "$work/clean-user.yaml" <<'YAML'
owner:
  name: "Ada Lovelace"
  site_url: "https://ada.dev"
  site_name: "ada.dev"
  focus_areas: "compilers, formal methods"
pointer_block:
  template: |
    ---
    *I write about {focus_areas} — more at [{site_name}]({site_url}).*
  newsletter:
    status: coming-soon
    rss_url: "https://ada.dev/rss.xml"
    follow_url: "https://ada.dev/follow"
    capture_url: "https://ada.dev/subscribe"
frontmatter:
  schema: [slug, title, date]
syndication:
  policy:
    en:
      mode: canonical
      variants: [devto]
  variants:
    devto:
      canonical_url_base: "https://ada.dev/articles"
YAML
set +e
msg=$(python3 "$root/$VAL" --root "$work/many" \
      --global-config "$work/clean-user.yaml" --repo-config /dev/null 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] && printf '%s' "$msg" | grep -q 'policy_source.topics' \
  && ok "validate-config reports the malformed block as a stage-0 finding" \
  || err "validate-config missed the malformed block: rc=$rc"

# --- 8. Nonexistent path is NOT a config error (CAP-6 split) ---------------------
mkdir -p "$work/ghost"
cat > "$work/ghost/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
policy_source:
  path: ../does-not-exist
YAML
set +e
msg=$(python3 "$root/$VAL" --root "$work/ghost" \
      --global-config "$work/clean-user.yaml" --repo-config /dev/null 2>&1); rc=$?
set -e
[ "$rc" -eq 0 ] && ok "nonexistent policy path passes stage-0 (degrades at read time)" \
  || err "nonexistent policy path was flagged at stage 0: $msg"

# --- 9. Absent block passes validation unchanged ----------------------------------
set +e
msg=$(python3 "$root/$VAL" --root "$work/plain" \
      --global-config "$work/clean-user.yaml" --repo-config /dev/null 2>&1); rc=$?
set -e
[ "$rc" -eq 0 ] && ok "absent block: stage-0 validation clean (behavior unchanged)" \
  || err "absent block produced findings: $msg"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-source config checks passed.\n'; exit 0
else
  printf '\npolicy-source config checks FAILED.\n' >&2; exit 1
fi
