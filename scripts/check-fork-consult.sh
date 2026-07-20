#!/usr/bin/env sh
# check-fork-consult.sh — verify the fork-gate consult-first contract
# (SPEC-policy-fork-consultation, #480, Stories 18.11/18.12). POSIX shell +
# stdlib Python only. Carries the four acceptance criteria the sitting named
# explicitly: coverage strictness, degradation, no cache, and the carrier check.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

F="scripts/fork-consult.py"
SKILL="skills/fork-gate-consult-first/SKILL.md"
PIN="product-lab@a1b2c3d4e5f6a7b8"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$F', doraise=True)" 2>/dev/null \
  && ok "fork-consult compiles" || { err "syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
present() { python3 "$F" present --input "$work/f.json" --pin "$PIN" ${1:-} > "$work/o.json" 2>"$work/e"; }
q() { python3 -c "import json,sys;print(json.load(open('$work/o.json'))$1)"; }

# A four-fork table: covered+discriminates, covered-but-topical, uncovered,
# out-of-scope mechanical.
cat > "$work/f.json" <<JSON
{"forks": [
  {"id":"cov","question":"independent or syndicated?","in_scope":true,
   "consult":{"covered":true,"discriminates":true,"chosen_option":"independent",
     "quote":"Website stays independent","pointer":"topics/articles.md:17@a1b2c3d4e5f6a7b8","pin":"$PIN"}},
  {"id":"top","question":"which CSS framework?","in_scope":true,
   "consult":{"covered":true,"discriminates":false,"quote":"the site should look clean","pointer":"topics/articles.md:9@a1b2c3d4e5f6a7b8",
     "candidates":[{"answer":"Tailwind","grounding":[]}]}},
  {"id":"unc","question":"publish cadence?","in_scope":true,
   "consult":{"covered":false,"candidates":[{"answer":"weekly","grounding":[]},{"answer":"on-ready","grounding":[]}]}},
  {"id":"mech","question":"tabs or spaces?","in_scope":false}
]}
JSON

# --- CAP-1/2/3: the base partition -------------------------------------------
present || err "present exited non-zero on a clean table"
[ "$(q "['counts']['fyis']")" = "1" ] && [ "$(q "['counts']['skipped']")" = "1" ] \
  && ok "CAP-1/2: one covered fork -> FYI; the mechanical fork skips consultation" \
  || err "base partition wrong: $(cat "$work/o.json")"
q "['fyis'][0]['overrideable']" | grep -q True && ok "CAP-2: the FYI is overrideable, shown not applied" || err "FYI not overrideable"

# --- Coverage strictness (named fixture): topical -> gate, never FYI ---------
python3 - "$work/o.json" <<'PY' && ok "coverage strictness: a topical, non-discriminating quote presents as a GATE, not an FYI" || err "topical fork leaked into an FYI"
import json,sys
d=json.load(open(sys.argv[1]))
assert not any(x["id"]=="top" for x in d["fyis"]), "topical must not be an FYI"
assert any(g["id"]=="top" for g in d["gates"]), "topical must be a gate"
assert any(m["id"]=="top" for m in d["misses"]), "topical is a miss too"
PY

# --- Degradation (named fixture): no policy_source -> all in-scope are gates --
present "--policy-source-available false" || err "degraded present exited non-zero (must never block)"
python3 - "$work/o.json" <<'PY' && ok "degradation: policy_source absent => all 3 in-scope forks are gates, one logged line, run never blocks" || err "degradation wrong"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["counts"]["fyis"]==0 and d["counts"]["gates"]==3, d["counts"]
assert d["degraded"] and "one logged line" in d["degraded"], d["degraded"]
assert d["counts"]["skipped"]==1, "the mechanical fork still skips"
PY

# --- No consultation cache: --pin required, fresh per run, nothing cached -----
python3 "$F" present --input "$work/f.json" --policy-source-available true 2>/dev/null && err "present ran without --pin" || ok "no cache: --pin (fresh per run) is required, refused when absent"
python3 "$F" present --input "$work/f.json" --pin "not-a-pin" >/dev/null 2>&1 && err "bad pin accepted" || ok "no cache: the pin must be <policy-source>@<commit>"
[ ! -e "$work/.fork-consult-cache" ] && [ ! -e "config/fork-consult-cache.json" ] \
  && ok "no cache: the pass writes no consultation-cache file" || err "a consult cache appeared"

# --- CAP-3 payload guards: >3 candidates and a pre-selected default refused ---
cat > "$work/f.json" <<JSON
{"forks":[{"id":"g","question":"q","in_scope":true,"consult":{"covered":false,
  "candidates":[{"answer":"a"},{"answer":"b"},{"answer":"c"},{"answer":"d"}]}}]}
JSON
present && err ">3 candidates accepted" || { grep -q "≤3 candidates" "$work/e" && ok "CAP-3: a gate with >3 candidates is refused"; }
cat > "$work/f.json" <<JSON
{"forks":[{"id":"g","question":"q","in_scope":true,"consult":{"covered":false,
  "candidates":[{"answer":"a","default":true},{"answer":"b"}]}}]}
JSON
present && err "pre-selected default accepted" || { grep -q "pre-selected" "$work/e" && ok "CAP-3: a pre-selected default candidate is refused (never times out into a choice)"; }

# --- Publication boundary: a non-served FYI pointer is refused ----------------
cat > "$work/f.json" <<JSON
{"forks":[{"id":"c","question":"q","in_scope":true,"consult":{"covered":true,"discriminates":true,
  "chosen_option":"x","quote":"q","pointer":"not-a-served-pointer","pin":"$PIN"}}]}
JSON
present && err "non-served FYI pointer accepted" || { grep -q "not a served" "$work/e" && ok "publication boundary: a non-served FYI pointer is refused"; }

# --- CAP-4: the miss emission is a §3.1 conformance copy, proposal-only -------
python3 "$F" emit-miss --question "publish cadence?" --decision "on-ready" \
  --slug 2026-07-20-publish-cadence --source-repo writing-assistant --created 2026-07-20 > "$work/s.md" 2>&1 \
  || err "emit-miss failed"
grep -q '<!-- staging-candidate -->' "$work/s.md" \
  && grep -qi 'conforms to hub §3.1' "$work/s.md" \
  && grep -qi 'hub schema is the authority' "$work/s.md" \
  && grep -q 'fork-miss' "$work/s.md" \
  && ok "CAP-4: emit-miss produces a §3.1-conformant staging block (authority + precedence declared, no own schema)" \
  || err "emit-miss block not §3.1-conformant: $(cat "$work/s.md")"
python3 "$F" emit-miss --question q --decision d --slug BADSLUG --source-repo r --created 2026-07-20 >/dev/null 2>&1 \
  && err "bad slug accepted" || ok "CAP-4: the staging slug grammar is enforced"

# --- Carrier check: every fork-presenting stop point -> invocation or exemption
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qi 'triage spec-lane re-offer' \
  && printf '%s' "$S" | grep -qi 'spec-run fork tables' \
  && ok "carrier: the two fork-presenting stop points are enumerated as invocations" \
  || err "carrier: a fork-presenting stop point is not enumerated"
printf '%s' "$S" | grep -qi 'Exemption' \
  && ok "carrier: mechanical-gate stop points carry a declared exemption (no orphan mechanism)" \
  || err "carrier: no declared exemptions for mechanical gates"
printf '%s' "$S" | grep -qi 'orphan-mechanism defect the carrier check catches' \
  && ok "carrier: the SKILL states the orphan-mechanism rule" \
  || err "carrier: orphan-mechanism rule missing"

if [ "$fail" -eq 0 ]; then
  printf '\nAll fork-consult checks passed.\n'; exit 0
else
  printf '\nfork-consult checks FAILED.\n' >&2; exit 1
fi
