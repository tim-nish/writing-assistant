#!/usr/bin/env sh
# check-provenance-map.sh — verify the three provenance classes and the sidecar
# provenance map (Story 11.1). POSIX shell + stdlib Python.
#
# Covers: a valid map with sourced/derived/narration parses and passes (AC1); a
# sourced claim must carry a pointer (AC2); a derived claim must inherit >=2
# pointers and — the drafting rule — a synthesis adding one of the six forbidden
# categories is an inferred claim (documented in the SKILL) (AC3); narration
# carries no pointer (AC4); an inferred claim is `verify` (inline [VERIFY]) (AC5);
# and the SKILL writes the sidecar map to the run workspace, not inline.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
prov() { printf '%s' "$1" | python3 "$DP" provenance --map -; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# AC1 — a clean map with all three classes parses and passes.
GOOD='P1.S1: sourced <- fs-15
P1.S2: derived <- fs-12, fs-14
P1.S3: narration
P4.S5: verify'
prov "$GOOD" >/dev/null 2>&1 && ok "a clean three-class map passes" || err "clean map rejected"
# tallies are emitted for dimension-4 density.
printf '%s' "$GOOD" | python3 "$DP" provenance --map - --count | grep -q '"sourced": 1' \
  && ok "per-class tallies are emitted (--count)" || err "tallies missing"

# AC2 — a sourced claim with no pointer is a structural violation.
prov 'P1.S1: sourced' >/dev/null 2>&1 && err "sourced without a pointer accepted" || ok "sourced claim must carry a pointer"

# AC3 — a derived claim must inherit >=2 pointers (synthesis over >=2 sourced claims).
prov 'P1.S1: derived <- fs-12' >/dev/null 2>&1 && err "derived with one pointer accepted" || ok "derived claim must inherit >=2 pointers"
prov 'P1.S1: derived <- fs-12, fs-14' >/dev/null 2>&1 && ok "derived with >=2 pointers passes" || err "valid derived rejected"
# the six forbidden derivation categories are stated in the drafting rule.
for cat in causality significance evaluation comparison intent scope; do
  grep -qi "$cat" "$SKILL" || err "SKILL missing forbidden derivation category: $cat"
done
ok "SKILL states the six forbidden derivation categories"

# AC4 — narration carries no pointer.
prov 'P1.S3: narration <- fs-1' >/dev/null 2>&1 && err "narration with a pointer accepted" || ok "narration carries no pointer"
grep -qi 'falsifiability test' "$SKILL" && ok "SKILL defines narration via the falsifiability test" || err "SKILL missing falsifiability test"

# AC5 — an inferred claim is class `verify` (inline [VERIFY]); no pointer in the map.
prov 'P4.S5: verify <- fs-1' >/dev/null 2>&1 && err "verify with a pointer accepted" || ok "verify (inferred) carries no map pointer"
grep -q 'VERIFY: <reason>' "$SKILL" && ok "SKILL keeps the inline [VERIFY] marker for inferred claims" || err "SKILL dropped the [VERIFY] marker"

# malformed line rejected.
prov 'this is not a valid entry' >/dev/null 2>&1 && err "malformed line accepted" || ok "malformed provenance line rejected"

# #308 — duplicate position keys fail closed with a named error listing every
# duplicate and all its input line numbers; never last-write-wins, never
# counted twice into the class tallies. Three shapes: identical class,
# conflicting classes (the observed case), conflicting pointer sets.
dup_same='P1.S1: narration
P1.S1: narration'
dup_class='P12.S2: sourced <- t1
P12.S3: narration
P12.S2: sourced <- docs/x.md:1@abc
P12.S2: narration'
dup_ptrs='P2.S1: sourced <- fs-1
P2.S1: sourced <- fs-2'
prov "$dup_same" >/dev/null 2>&1 && err "exact-duplicate key (same class) accepted" \
  || ok "exact-duplicate key (same class) rejected"
prov "$dup_class" >/dev/null 2>&1 && err "duplicate key with conflicting classes accepted" \
  || ok "duplicate key with conflicting classes rejected"
prov "$dup_ptrs" >/dev/null 2>&1 && err "duplicate key with conflicting pointers accepted" \
  || ok "duplicate key with conflicting pointer sets rejected"
duperr=$(prov "$dup_class" 2>&1 >/dev/null) || true
echo "$duperr" | grep -q 'duplicate position key' && ok "duplicate diagnostic is named" \
  || err "duplicate diagnostic not named"
echo "$duperr" | grep -q 'P12.S2' && echo "$duperr" | grep -q '1' && echo "$duperr" | grep -q '3' && echo "$duperr" | grep -q '4' \
  && ok "diagnostic lists the key and all occurrence lines" \
  || err "diagnostic missing key or occurrence line numbers: $duperr"

# Sidecar map is written to the run workspace, not inline.
grep -q 'draft-pipeline.py provenance' "$SKILL" && grep -q 'provenance-map' "$SKILL" \
  && grep -qi 'sidecar' "$SKILL" && ok "SKILL writes a sidecar provenance map to the workspace" \
  || err "SKILL does not write the sidecar map to \$WS"

if [ "$fail" -eq 0 ]; then
  printf '\nAll provenance-map checks passed.\n'; exit 0
else
  printf '\nprovenance-map checks FAILED.\n' >&2; exit 1
fi
