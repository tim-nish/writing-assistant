#!/usr/bin/env sh
# check-config-validation.sh — verify Stage-0 configuration validation (Story 7.4,
# CAP-5): before any generation or review, a config carrying an example
# placeholder, a malformed URL (double-slash canonical_url), or a missing required
# key halts with a per-key report naming the file and the fix; a clean config
# passes silently with no later configuration finding. Both skills wire it in as
# their stage 0. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VAL="scripts/validate-config.py"
DRAFT="skills/draft-article/SKILL.md"
REVIEW="skills/review-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$VAL', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root"
cat > "$work/root/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
YAML
cat > "$work/clean.yaml" <<'YAML'
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

V() { python3 "$VAL" --repo-config /dev/null --root "$work/root" "$@"; }

# 1. Clean config -> silent, exit 0.
if out=$(V --global-config "$work/clean.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "clean config passes silently (exit 0, no output)"
else err "clean config not silent/zero (rc=$rc, out='$out')"; fi

# 2. Example placeholders -> halts, names the file.
if out=$(V --global-config config/user-config.example.yaml 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'placeholder' \
   && printf '%s' "$out" | grep -q 'user-config.yaml'; then
  ok "placeholder config halts with a per-key report naming user-config.yaml"
else err "placeholder config not caught (rc=$rc)"; fi

# 3. Malformed URL (trailing-slash canonical_url_base -> double-slash canonical_url).
sed 's#https://ada.dev/articles#https://ada.dev/articles/#' "$work/clean.yaml" > "$work/badurl.yaml"
if out=$(V --global-config "$work/badurl.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'double.slash\|trailing slash'; then
  ok "malformed URL (double-slash canonical_url) halts with a fix"
else err "malformed URL not caught (rc=$rc)"; fi

# 4. Missing required key -> halts, names the key + file.
grep -v 'site_url' "$work/clean.yaml" > "$work/missing.yaml"
if out=$(V --global-config "$work/missing.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'owner.site_url' \
   && printf '%s' "$out" | grep -qi 'missing'; then
  ok "missing required key halts naming the key + file"
else err "missing key not caught (rc=$rc)"; fi

# 5. Both skills wire the validator in as their up-front stage 0.
for f in "$DRAFT" "$REVIEW"; do
  grep -q 'validate-config.py' "$f" && ok "$f wires in validate-config" \
    || err "$f does not run validate-config"
  grep -qi 'per-key report naming the file\|per-key report' "$f" \
    && ok "$f documents the per-key file report" || err "$f missing file-report note"
  grep -qi 'silently' "$f" && ok "$f documents the silent-clean path" \
    || err "$f missing silent-clean note"
done

if [ "$fail" -eq 0 ]; then
  printf '\nAll config-validation checks passed.\n'; exit 0
else
  printf '\nconfig-validation checks FAILED.\n' >&2; exit 1
fi
