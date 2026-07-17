#!/usr/bin/env sh
# check-internal-vocabulary.sh — the dimension-3 inventory DRIFT check (#305).
# POSIX shell + stdlib Python only.
#
# Dimension 3 gates exactly the vocabulary registered in
# skills/draft-article/internal-vocabulary.json. That makes the inventory a
# contract rather than a convenience list: if the code grows a new framework ID,
# pipeline stage, or owner-facing marker and nobody registers it, dim3 would
# silently stop gating it and still report `dim3: pass` — a false clean bill.
#
# This check derives the identifier families that CAN be derived from canonical
# code structures and fails when any derived identifier is not covered by the
# registered inventory:
#
#   framework IDs   <- draft-pipeline.py FRAMEWORK_PRIORITY keys
#   pipeline stages <- draft-pipeline.py `next_stage` values (the run's own
#                      stage vocabulary)
#   markers         <- [VERIFY] and NEEDS-OWNER, the owner-facing draft markers
#
# Prose nouns (fact sheet, editorial anchor, ...) have no canonical machine
# source; for those the inventory IS the source of truth and this check enforces
# its shape, not its completeness. The boundary is reported, never implied.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
VOCAB="skills/draft-article/internal-vocabulary.json"
RUBRIC="skills/draft-article/quality-rubric.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# --- 1. The inventory asset exists and is well-formed --------------------------
[ -f "$VOCAB" ] && ok "the registered inventory exists ($VOCAB)" \
  || { err "inventory asset missing — dim3 has no contract"; printf '\nFAILED.\n' >&2; exit 1; }
python3 - "$VOCAB" <<'PY' && ok "inventory is well-formed (version + non-empty terms + patterns)" || err "inventory malformed"
import json, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d.get("vocabulary_version"), int), "vocabulary_version must be an int"
assert isinstance(d.get("terms"), list) and d["terms"], "terms must be a non-empty list"
assert isinstance(d.get("patterns"), list), "patterns must be a list"
assert all(isinstance(t, str) and t.strip() for t in d["terms"]), "terms must be non-empty strings"
PY

# --- 2. A missing/malformed inventory FAILS CLOSED (never a silent empty scan) --
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 - "$DP" "$tmp" <<'PY' && ok "an unreadable inventory is a named error, not a silent pass" || err "unreadable inventory did not fail closed"
import importlib.util, sys, os
spec = importlib.util.spec_from_file_location("dp", sys.argv[1])
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
missing = os.path.join(sys.argv[2], "nope.json")
try:
    dp._load_internal_vocabulary(missing)
except SystemExit as e:
    assert "internal-vocabulary inventory unreadable" in str(e), f"unnamed error: {e}"
else:
    raise AssertionError("a missing inventory did not raise")
bad = os.path.join(sys.argv[2], "bad.json")
open(bad, "w").write('{"terms": [], "patterns": []}')
try:
    dp._load_internal_vocabulary(bad)
except SystemExit as e:
    assert "malformed" in str(e), f"unnamed error: {e}"
else:
    raise AssertionError("an empty inventory did not raise")
PY

# --- 3. DRIFT: every derivable identifier family is registered ------------------
python3 - "$DP" "$VOCAB" <<'PY' && ok "no drift: every derivable framework ID, stage name, and marker is registered" || err "inventory DRIFT — an internal identifier is not registered (see above)"
import importlib.util, json, re, sys

spec = importlib.util.spec_from_file_location("dp", sys.argv[1])
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
inv = json.load(open(sys.argv[2]))
terms = [t.lower() for t in inv["terms"]]
pats = [re.compile(p, re.I) for p in inv["patterns"]]

def covered(token):
    t = token.lower()
    if any(t == x or t in x or x in t for x in terms):
        return True
    return any(p.search(token) for p in pats)

drift = []

# (a) framework IDs — canonical: FRAMEWORK_PRIORITY keys
for fid in dp.FRAMEWORK_PRIORITY:
    if not covered(fid):
        drift.append(f"framework ID {fid!r} is not covered by the registered inventory")

# (b) pipeline stage names — canonical: the run's own `next_stage` vocabulary.
#     Rendered the way an article would name them ("Stage 3") AND as the stage
#     noun itself, so both surfaces are gated.
src = open(sys.argv[1], encoding="utf-8").read()
stages = sorted(set(re.findall(r'"next_stage":\s*"([a-z0-9-]+)"', src)))
assert stages, "derivation broke: no next_stage values found — fix the check, not the inventory"
for st in stages:
    if st in ("done", "review"):      # not internal article vocabulary
        continue
    if not covered(st):
        drift.append(f"pipeline stage {st!r} is not covered by the registered inventory")
if not any(p.search("Stage 3") for p in pats):
    drift.append("the numbered-stage family ('Stage N') is not covered by any pattern")

# (c) owner-facing markers — canonical: the draft markers the pipeline emits
for marker in ("[VERIFY]", "NEEDS-OWNER"):
    if not covered(marker):
        drift.append(f"marker {marker!r} is not covered by the registered inventory")

if drift:
    for d in drift:
        print("  drift:", d, file=sys.stderr)
    print("\n  Register each in skills/draft-article/internal-vocabulary.json — an\n"
          "  unregistered internal term is silently ungated by dimension 3.", file=sys.stderr)
    raise SystemExit(1)
print(f"  derived and checked: {len(dp.FRAMEWORK_PRIORITY)} framework IDs, "
      f"{len(stages)} stage names, 2 markers")
PY

# --- 4. The inventory is declared CONTRACT where the rubric defines dim3 --------
grep -qi 'internal-vocabulary.json' "$RUBRIC" \
  && ok "rubric names the inventory as dim3's registered contract" \
  || err "rubric does not name the inventory — the contract must be discoverable from the rubric"
grep -qi 'registration is mandatory' "$RUBRIC" \
  && ok "rubric states registration is mandatory for new internal vocabulary" \
  || err "rubric missing the registration obligation"

# --- 5. The gate stamps which inventory produced the verdict --------------------
work=$(mktemp -d); trap 'rm -rf "$tmp" "$work"' EXIT
printf -- '---\nslug: s\naudience: en-practitioner\n---\n# T\n\nNothing internal is named in this sentence at all.\n' > "$work/clean.md"
python3 "$DP" quality-gate --draft "$work/clean.md" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dim3_inventory']['vocabulary_version'])" >/dev/null 2>&1 \
  && ok "gate output stamps the inventory version behind the dim3 verdict" \
  || err "gate does not stamp dim3_inventory — a dim3 pass would not say what it scanned"

printf '\nBoundary (reported, not implied): framework IDs, pipeline stage names, and\n'
printf 'markers are DERIVED from code and cannot drift unnoticed. Prose nouns are\n'
printf 'contract-registered only — adding one is a reviewed edit to the inventory.\n'

if [ "$fail" -eq 0 ]; then
  printf '\nAll internal-vocabulary checks passed.\n'; exit 0
else
  printf '\ninternal-vocabulary checks FAILED.\n' >&2; exit 1
fi
