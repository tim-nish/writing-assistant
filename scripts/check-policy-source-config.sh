#!/usr/bin/env sh
# check-policy-source-config.sh — verify the `policy_source` config block
# (Story 14.1, SPEC-policy-source-seam CAP-1 as amended 2026-07-18, #366:
# presence toggle, no filesystem path — Story 13.73). POSIX shell + stdlib
# Python only.
#
# Covers: absent block resolves {"declared": false} with byte-identical
# pipeline behavior (exit 0, no warning); a well-formed block is the presence
# toggle `enabled: true` and resolves {"declared": true} with NO path ever
# reported; the toggle write/read round-trip through the re-shaped
# set-policy-source (no PATH argument; --disable removes the block); a
# malformed block — the RETIRED `path` key (13.73, migration notice), a
# missing/unreadable `enabled` value, or a leftover track/topics key (removed
# by Story 13.36) — exits 4 with per-key errors that stage-0 validation
# relays as configuration findings; a bare `enabled: true` block validates
# clean at stage 0 (gateway usability is read-time degradation, CAP-6).

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
grep -q 'enabled: true' "$EX" && ok "example shows the presence toggle" \
  || err "example missing the enabled: true toggle"
sed -n '/policy_source:/,$p' "$EX" | grep -q '^#\?\s*path:' \
  && err "example still documents the retired path key" \
  || ok "example no longer documents a hub path (retired, Story 13.73)"
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

# --- 3. Well-formed block: presence toggle, {"declared": true}, NO path ------
mkdir -p "$work/host"
cat > "$work/host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
policy_source:
  enabled: true               # presence toggle (13.73)
YAML
out=$($PY --root "$work/host" policy-source)
[ "$out" = '{"declared": true}' ] \
  && ok "well-formed toggle: {\"declared\": true}, no path ever reported" \
  || err "toggle did not resolve as expected: $out"
printf '%s' "$out" | grep -q 'path' && err "getter leaked a path key" || :

# enabled: false — declared false, exit 0 (not an error; same as absent)
mkdir -p "$work/off"
cat > "$work/off/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  enabled: false
YAML
out=$($PY --root "$work/off" policy-source 2>/dev/null)
[ "$out" = '{"declared": false}' ] \
  && ok "enabled: false — {\"declared\": false}, exit 0" \
  || err "enabled: false mishandled: $out"

# --- 4. Toggle write/read round-trip via the re-shaped writer ----------------
XDG_CONFIG_HOME="$work/xdg"; export XDG_CONFIG_HOME
mkdir -p "$work/rt"
printf '[{"path": "."}]' | $PY set-sources --root "$work/rt" >/dev/null 2>&1
out=$($PY set-policy-source --root "$work/rt" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = '{"declared": true}' ] \
  && [ "$($PY --root "$work/rt" policy-source 2>/dev/null)" = '{"declared": true}' ] \
  && ok "set-policy-source (no path argument) writes the toggle; getter round-trips" \
  || err "toggle round-trip: rc=$rc out='$out'"
g=$(find "$work/xdg" -name writing-sources.yaml | head -1)
grep -q 'enabled: true' "$g" && ! grep -q '^  path:' "$g" \
  && ok "written block is the toggle — no path key on disk" \
  || err "written block malformed: $(cat "$g")"
# a stray positional PATH is a usage error, never a silent write
if $PY set-policy-source ../product-lab --root "$work/rt" >/dev/null 2>&1; then
  err "set-policy-source still accepts a PATH argument (retired, 13.73)"
else
  ok "set-policy-source refuses a PATH argument (retired, 13.73)"
fi
# --disable removes the block entirely
out=$($PY set-policy-source --disable --root "$work/rt" 2>/dev/null)
[ "$out" = '{"declared": false}' ] && ! grep -q 'policy_source' "$g" \
  && [ "$($PY --root "$work/rt" policy-source 2>/dev/null)" = '{"declared": false}' ] \
  && ok "set-policy-source --disable removes the block" \
  || err "--disable did not remove the block: $out"
unset XDG_CONFIG_HOME

# --- 5. RETIRED path key: exit 4, named error with migration notice ----------
mkdir -p "$work/legacy"
cat > "$work/legacy/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path: ../product-lab        # legacy pre-13.73 block
YAML
set +e; msg=$($PY --root "$work/legacy" policy-source 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.path' \
  && printf '%s' "$msg" | grep -qi 'retired' \
  && printf '%s' "$msg" | grep -q 'enabled: true' \
  && printf '%s' "$msg" | grep -qi 'gateway owns the hub location' \
  && ok "legacy path key: exit 4, retired-key error with migration notice" \
  || err "legacy path key: rc=$rc msg='$msg'"

# --- 5b. Empty block (no enabled key): exit 4, names the toggle --------------
mkdir -p "$work/bare"
cat > "$work/bare/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
YAML
set +e; msg=$($PY --root "$work/bare" policy-source 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.enabled' \
  && ok "declared block without enabled: exit 4, names the required toggle" \
  || err "bare block: rc=$rc msg='$msg'"

# --- 6. Removed keys: leftover track/topics are named errors, never ignored ----
mkdir -p "$work/many"
cat > "$work/many/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  enabled: true
  topics: [a.md, b.md]
YAML
set +e; msg=$($PY --root "$work/many" policy-source 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.topics' \
  && printf '%s' "$msg" | grep -qi 'removed' && printf '%s' "$msg" | grep -qi 'delete this line' \
  && ok "leftover topics key: exit 4, named as removed with the fix" \
  || err "leftover topics key: rc=$rc msg='$msg'"

mkdir -p "$work/esc"
cat > "$work/esc/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  enabled: true
  track: eval-engineering
YAML
set +e; msg=$($PY --root "$work/esc" policy-source 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.track' \
  && printf '%s' "$msg" | grep -qi 'draft-article Stage 2' \
  && ok "leftover track key: exit 4, fix points at draft-time selection" \
  || err "leftover track key: rc=$rc msg='$msg'"

# --- 7. Stage-0 validation relays malformed blocks as findings -----------------
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

# The retired path key is a stage-0 per-key finding with the migration notice.
set +e
msg=$(python3 "$root/$VAL" --root "$work/legacy" \
      --global-config "$work/clean-user.yaml" --repo-config /dev/null 2>&1); rc=$?
set -e
[ "$rc" -ne 0 ] && printf '%s' "$msg" | grep -q 'policy_source.path' \
  && printf '%s' "$msg" | grep -qi 'retired' \
  && ok "validate-config relays the retired path key with its migration notice" \
  || err "validate-config missed the retired path key: rc=$rc"

# --- 8. Bare enabled toggle validates clean (gateway usability is read-time) ---
set +e
msg=$(python3 "$root/$VAL" --root "$work/host" \
      --global-config "$work/clean-user.yaml" --repo-config /dev/null 2>&1); rc=$?
set -e
[ "$rc" -eq 0 ] && ok "bare enabled: true block passes stage-0 (gateway checked at read time)" \
  || err "toggle block was flagged at stage 0: $msg"

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
