#!/usr/bin/env bash
# Story 18.117 (#722, #719) — a seeded platform profile is a conformance copy
# of the shipped example, so it carries a mechanical mismatch check.
#
# The invariant under test: seeding refuses to overwrite an owner-edited
# profile, so a load-bearing declaration the example gains later never reaches
# an existing installation. `validate` reports those missing declarations
# REPORT-ONLY and PRESENCE-ONLY — values stay the owner's.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ppdir="$work/profiles"; edir="$work/examples"
mkdir -p "$ppdir" "$edir"

# A minimal example carrying every required key plus a nested block the seeded
# copy will lack — this stands in for "the example gained a declaration".
cat > "$edir/demo.example.yaml" <<'YAML'
platform: demo
audience: demo-reader
language: en
packaging:
  frontmatter: [title]
  tag_cap: 4
  layout:
    repo: articles
    dir: demo/
    identity_from_basename: true
    basename:
      rule: slug-dots-to-hyphens
distribution_hook: demo-follow
YAML

validate() {
  python3 "$root/scripts/resolve-platform-profiles.py" validate \
    --profiles-dir "$ppdir" --examples-dir "$edir" --root "$work" 2>"$work/err"
}

# --- 1. a seeded profile is stamped -------------------------------------
python3 "$root/scripts/resolve-platform-profiles.py" seed demo \
  --profiles-dir "$ppdir" --examples-dir "$edir" --root "$work" >/dev/null 2>&1
if grep -q "^seed_version: [0-9a-f]\{12\}$" "$ppdir/demo.yaml"; then
  ok "seed writes a seed_version stamp"
else
  err "seed must write a seed_version stamp"
fi

# --- 2. a freshly seeded profile has no drift ---------------------------
validate; rc=$?
[ "$rc" -eq 0 ] || err "validate must exit 0 on a freshly seeded profile (got $rc)"
if [ -s "$work/err" ]; then
  err "a freshly seeded profile must report no drift"
else
  ok "a freshly seeded profile reports no drift"
fi

# --- 3. the example gains a declaration; the seeded copy has not --------
# Inserted INSIDE the packaging block — appending at EOF would attach the key
# to nothing and the test would pass vacuously.
sed -i 's/^  tag_cap: 4$/  tag_cap: 4\n  visuals: mermaid-embedded/' \
  "$edir/demo.example.yaml"
grep -q "^  visuals: mermaid-embedded$" "$edir/demo.example.yaml" \
  || err "fixture guard: the example edit did not apply"
validate; rc=$?
[ "$rc" -eq 0 ] \
  && ok "drift NEVER changes the exit code (report-only)" \
  || err "drift must not change the exit code (got $rc)"
grep -q "packaging.visuals" "$work/err" \
  && ok "the gained declaration is reported by key path" \
  || err "the gained declaration must be reported ($(cat "$work/err"))"
grep -q "your edits are untouched" "$work/err" \
  && ok "the note states that owner edits are untouched" \
  || err "the note must state that owner edits are untouched"

# --- 4. VALUES are the owner's; only PRESENCE is compared ---------------
sed -i 's/  tag_cap: 4/  tag_cap: 99/' "$ppdir/demo.yaml"
validate
grep -q "tag_cap" "$work/err" \
  && err "a differing VALUE must never be reported (presence-only)" \
  || ok "a sovereign owner edit to a value reports nothing"

# --- 5. a pre-stamp profile is diffed anyway, never skipped -------------
grep -v "^seed_version:" "$ppdir/demo.yaml" > "$work/nostamp" \
  && mv "$work/nostamp" "$ppdir/demo.yaml"
grep -q "^seed_version:" "$ppdir/demo.yaml" \
  && err "fixture guard: the stamp should have been removed"
validate
grep -q "packaging.visuals" "$work/err" \
  && ok "a profile with no seed_version is diffed anyway, not skipped" \
  || err "a pre-stamp profile must still be diffed"

# --- 6. a hand-authored profile with no example accuses no one ----------
cp "$ppdir/demo.yaml" "$ppdir/handmade.yaml"
sed -i 's/^platform: demo/platform: handmade/' "$ppdir/handmade.yaml"
validate
grep -q "handmade.yaml" "$work/err" \
  && err "a profile with no shipped example must report no drift" \
  || ok "a hand-authored profile with no example reports nothing"

# --- 7. a missing PARENT is reported once, not once per child -----------
rm -f "$ppdir/handmade.yaml"
python3 "$root/scripts/resolve-platform-profiles.py" seed demo --force \
  --profiles-dir "$ppdir" --examples-dir "$edir" --root "$work" >/dev/null 2>&1
python3 - "$ppdir/demo.yaml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
# drop the whole layout block from the seeded copy
s = re.sub(r"\n  layout:\n(?:    .*\n|      .*\n)*", "\n", s)
open(p, "w", encoding="utf-8").write(s)
PY
validate
n="$(grep -c "packaging.layout" "$work/err" || true)"
if [ "$n" -eq 1 ]; then
  ok "a missing parent block is reported once, not per child"
else
  err "a missing parent must collapse its children (got $n lines)"
fi

# --- 8. the real repo's own examples still validate ---------------------
python3 "$root/scripts/resolve-platform-profiles.py" validate \
  --profiles-dir "$root/config/platform-profiles" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] \
  && ok "the shipped examples directory holds no live profiles to validate" \
  || err "validating the shipped examples dir must stay clean (got $rc)"

if [ "$fail" -eq 0 ]; then
  printf '\nAll seeded-profile drift checks passed.\n'
else
  printf '\nFAILED.\n' >&2
fi
exit "$fail"
