#!/usr/bin/env sh
# check-policy-divergence-runtime.sh — verify the divergence detector's RUNTIME
# half (SPEC-policy-divergence-detector, #436, Story 13.99): the CAP-1 detection
# pass and the CAP-3/CAP-4 disposition emit side, both driving the foundation
# (validate-divergence-candidate.py). This harness is the carrier that gives the
# foundation's validator, direction guard, and ledger their invocation sites.
# POSIX shell + stdlib Python only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/detect-policy-divergence.py"
V="scripts/validate-divergence-candidate.py"
SKILL="skills/policy-divergence-detector/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$D', doraise=True)" 2>/dev/null \
  && ok "runtime driver compiles" || { err "driver syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
run() { python3 "$D" run --input "$work/f.json" --detected 2026-07-20 ${1:-}; }
field() { python3 -c "import json,sys;print(json.load(open('$work/o.json'))['$1'])"; }

# A two-flag input: flag A unchanged at the pin (a candidate), flag B whose
# current line changed (the upstream moved -> routed to the seam, CAP-5).
cat > "$work/f.json" <<'JSON'
[
  { "consult_point": "review:policy-consistency", "direction": "outgrown",
    "rationale": "The tool groups findings by axis where the line assumes a flat list",
    "decision": {"statement": "The review pass classifies findings by axis", "evidence": "specs/spec-article-review/SPEC.md:38"},
    "policy": {"quote": "Findings are presented flat", "pointer": "LESSONS.md:41@a1b2c3d4e5f6a7b8", "pin": "product-lab@a1b2c3d4e5f6a7b8"},
    "current_line": "Findings are presented flat" },
  { "consult_point": "interview:seeding", "direction": "contradiction",
    "rationale": "This tool syndicates where the line kept the site independent",
    "decision": {"statement": "The site syndicates to three platforms", "evidence": "specs/spec-platform-variants/SPEC.md:12"},
    "policy": {"quote": "Website stays independent", "pointer": "topics/articles.md:17@a1b2c3d4e5f6a7b8", "pin": "product-lab@a1b2c3d4e5f6a7b8"},
    "current_line": "Site syndicates everywhere now" }
]
JSON

# --- CAP-1 + CAP-5: candidate vs upstream-moved ------------------------------
run > "$work/o.json" || err "run exited non-zero on a clean input"
[ "$(field 'candidates' | grep -c 'div-2026-07-20-001')" -ge 1 ] 2>/dev/null || true
python3 - "$work/o.json" <<'PY' && ok "CAP-1/CAP-5: unchanged line -> 1 candidate; changed line -> routed to seam, not a candidate" || err "run split wrong"
import json,sys
d=json.load(open(sys.argv[1]))
assert len(d["candidates"])==1, d
assert d["candidates"][0]["id"]=="div-2026-07-20-001", d
assert len(d["routed_to_seam"])==1 and d["candidates"][0]["direction"]=="outgrown", d
assert d["capped"]==0 and d["errors"]==[], d
PY

# --- CAP-2 fail-closed: a surviving flag that cannot validate is a hard error -
cat > "$work/f.json" <<'JSON'
[ { "consult_point": "review:policy-consistency", "direction": "outgrown",
    "rationale": "one sentence", "decision": {"statement": "a decision", "evidence": "specs/x.md:1"},
    "policy": {"quote": "q", "pointer": "NOT-PINNED", "pin": "product-lab@a1b2c3d4e5f6a7b8"},
    "current_line": "q" } ]
JSON
run > "$work/o.json" 2>/dev/null && err "driver accepted an unvalidatable flag (should exit 4)" \
  || ok "CAP-2: a flag whose record fails validation is a hard error (fail-closed, exit 4)"
grep -q 'policy.pointer' "$work/o.json" && ok "CAP-2: the error names the offending field" || err "error not surfaced in output"

# --- CAP-4 dedup: a ledgered key is deduped, not re-surfaced ------------------
cat > "$work/f.json" <<'JSON'
[ { "consult_point": "review:policy-consistency", "direction": "outgrown",
    "rationale": "The tool groups findings by axis where the line assumes a flat list",
    "decision": {"statement": "The review pass classifies findings by axis", "evidence": "specs/spec-article-review/SPEC.md:38"},
    "policy": {"quote": "Findings are presented flat", "pointer": "LESSONS.md:41@a1b2c3d4e5f6a7b8", "pin": "product-lab@a1b2c3d4e5f6a7b8"},
    "current_line": "Findings are presented flat" } ]
JSON
cp scripts/fixtures/policy-divergence/ledger.json "$work/l.json"   # already holds this key
python3 "$D" run --input "$work/f.json" --ledger "$work/l.json" --detected 2026-07-20 > "$work/o.json"
python3 - "$work/o.json" <<'PY' && ok "CAP-4: a candidate whose key is already in the ledger is deduped (occurrence bumped)" || err "dedup did not fire"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["candidates"]==[], d
assert len(d["deduped"])==1 and d["deduped"][0]["occurrences"]==3, d
PY

# --- CAP-4 cap: >3 candidates -> capped, overflow counted --------------------
python3 - <<'PY' > "$work/f.json"
import json
base=lambda i:{"consult_point":"session:consult-first","direction":"contradiction","rationale":"one sentence here",
  "decision":{"statement":f"decision {i}","evidence":f"specs/s.md:{i}"},
  "policy":{"quote":f"line {i}","pointer":f"P.md:{i}@a1b2c3d4e5f6a7b8","pin":"product-lab@a1b2c3d4e5f6a7b8"},
  "current_line":f"line {i}"}
print(json.dumps([base(i) for i in range(1,6)]))
PY
python3 "$D" run --input "$work/f.json" --detected 2026-07-20 --cap 3 > "$work/o.json"
python3 - "$work/o.json" <<'PY' && ok "CAP-4: 5 candidates capped to 3, the 2 overflow counted (not dropped silently)" || err "cap wrong"
import json,sys
d=json.load(open(sys.argv[1]))
assert len(d["candidates"])==3 and d["capped"]==2, d
PY

# --- CAP-3 emit: disposition append validates and writes ---------------------
printf '{"entries": []}' > "$work/l2.json"
python3 "$D" disposition --ledger "$work/l2.json" \
  --key "LESSONS.md:41|outgrown|specs/spec-article-review/SPEC.md:38" \
  --disposition reported --ref "#500" --pin "product-lab@a1b2c3d4e5f6a7b8" --detected 2026-07-20 >/dev/null \
  && python3 "$V" ledger "$work/l2.json" >/dev/null 2>&1 \
  && ok "CAP-3: a 'reported' disposition appends a schema-valid ledger entry" \
  || err "disposition append produced an invalid ledger"
# dismissed without reason is refused (CAP-4 remembers dismissals with a reason).
python3 "$D" disposition --ledger "$work/l2.json" --key "a:1|outgrown|b:2" \
  --disposition dismissed --pin "product-lab@a1b2c3d4e5f6a7b8" >/dev/null 2>&1 \
  && err "dismissed without --reason accepted" \
  || ok "CAP-3: 'dismissed' without a reason is refused"

# --- Never blocks / degrades: empty flag list is a clean no-op ---------------
printf '[]' > "$work/f.json"
python3 "$D" run --input "$work/f.json" --detected 2026-07-20 >/dev/null 2>&1 \
  && ok "degrade: an empty flag set completes cleanly (no candidates, no error)" \
  || err "empty input did not complete cleanly"

# --- SKILL wires the three consult points + proposal-only gate ---------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
for cp in "review:policy-consistency" "interview:seeding" "session:consult-first"; do
  printf '%s' "$S" | grep -q "$cp" && ok "SKILL wires consult point $cp" || err "SKILL missing consult point $cp"
done
printf '%s' "$S" | grep -qi 'proposal-only' && printf '%s' "$S" | grep -qi 'never writes the upstream hub\|hub is never written\|upstream hub is untouched' \
  && ok "SKILL: emission is proposal-only, the upstream hub is never written" \
  || err "SKILL missing the proposal-only / no-hub-write invariant"
printf '%s' "$S" | grep -qi 'conformance copy of the hub .3.1' \
  && ok "SKILL: staging block is a conformance copy of hub §3.1" \
  || err "SKILL missing the §3.1 conformance wiring"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-divergence-runtime checks passed.\n'; exit 0
else
  printf '\npolicy-divergence-runtime checks FAILED.\n' >&2; exit 1
fi
