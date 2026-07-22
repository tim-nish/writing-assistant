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
PIN="policy-hub@8f3c2d1e4a5b6c7d"

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
     "quote":"Website stays independent","pointer":"topics/articles.md:17@8f3c2d1e4a5b6c7d","pin":"$PIN"}},
  {"id":"top","question":"which CSS framework?","in_scope":true,
   "consult":{"covered":true,"discriminates":false,"quote":"the site should look clean","pointer":"topics/articles.md:9@8f3c2d1e4a5b6c7d",
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

# --- Carrier check (Story 18.13, #484): the fork-presenters are ALL out-of-repo
# (installed skills / userSettings), so the carrier is documented owner-side. The
# check asserts the IN-REPO side is clean and the owner-side wiring is recorded —
# it never greps gitignored/absent files (that would pass locally and fail on a
# fresh checkout, the exact bug this story exists to avoid).
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
# 1. All three out-of-repo fork-presenters named and marked owner-side.
missing=""
for p in "/triage-gh" "bmad-spec" "bmad-architecture"; do
  printf '%s' "$S" | grep -q "$p" || missing="$missing $p"
done
[ -z "$missing" ] && ok "carrier: all 3 spec-lane fork-presenters documented (/triage-gh, bmad-spec, bmad-architecture)" \
  || err "carrier: out-of-repo presenter(s) not documented:$missing"
printf '%s' "$S" | grep -qi 'owner-side invocation' \
  && printf '%s' "$S" | grep -qi 'userSettings' && printf '%s' "$S" | grep -qi 'installed skill' \
  && ok "carrier: the fork-presenters are marked owner-side (userSettings / installed skill)" \
  || err "carrier: the out-of-repo presenters are not marked owner-side"
# 2. Self-guard: the check must NOT depend on gitignored installed skills.
grep -q '[.]claude/skills/bmad' "$0" \
  && err "carrier: this check greps gitignored installed skills (would fail on a fresh checkout)" \
  || ok "carrier: the check asserts only in-repo state, never gitignored installed skills"
# 3. The in-repo exemptions name real repo skills that exist.
printf '%s' "$S" | grep -qi 'gap interview' && printf '%s' "$S" | grep -qi 'review arbitration' \
  && printf '%s' "$S" | grep -qi 'mechanical gates' \
  && ok "carrier: in-repo exemptions declared (gap interview, review arbitration, mechanical gates)" \
  || err "carrier: in-repo exemptions incomplete"
[ -f skills/draft-article/SKILL.md ] && [ -f skills/review-article/SKILL.md ] \
  && ok "carrier: the exempted in-repo skills exist (draft-article, review-article)" \
  || err "carrier: a named in-repo exemption points at a missing skill"
# 4. The orphan-mechanism rule for new IN-REPO skills.
printf '%s' "$S" | grep -qi 'orphan-mechanism defect the carrier check catches' \
  && ok "carrier: the SKILL states the orphan-mechanism rule for new in-repo skills" \
  || err "carrier: orphan-mechanism rule missing"

# --- #519: the consultation-outcome receipt field ----------------------------
# Each per-fork receipt records what the gate DID: a covered FYI is
# auto-resolved-FYI; a gate is escalated. The split is countable from receipts
# alone; an overridden FYI flips to escalated; a missing outcome is lintable.
# Re-establish the clean partition fixture (earlier tests mutate f.json).
cat > "$work/f.json" <<JSON
{"forks": [
  {"id":"cov","question":"independent or syndicated?","in_scope":true,
   "consult":{"covered":true,"discriminates":true,"chosen_option":"independent",
     "quote":"Website stays independent","pointer":"topics/articles.md:17@8f3c2d1e4a5b6c7d","pin":"$PIN"}},
  {"id":"top","question":"which CSS framework?","in_scope":true,
   "consult":{"covered":true,"discriminates":false,"quote":"the site should look clean","pointer":"topics/articles.md:9@8f3c2d1e4a5b6c7d",
     "candidates":[{"answer":"Tailwind","grounding":[]}]}},
  {"id":"unc","question":"publish cadence?","in_scope":true,
   "consult":{"covered":false,"candidates":[{"answer":"weekly","grounding":[]},{"answer":"on-ready","grounding":[]}]}},
  {"id":"mech","question":"tabs or spaces?","in_scope":false}
]}
JSON
present || err "present exited non-zero (outcome fixture)"
[ "$(q "['fyis'][0]['outcome']")" = "auto-resolved-FYI" ] \
  && ok "#519: a covered FYI's receipt records outcome=auto-resolved-FYI" \
  || err "#519: FYI outcome wrong: $(q "['fyis'][0]['outcome']")"
python3 -c "import json;r=json.load(open('$work/o.json'));assert all(g['outcome']=='escalated' for g in r['gates']),r" 2>/dev/null \
  && ok "#519: every gate receipt records outcome=escalated (uncovered + topical)" \
  || err "#519: a gate receipt is not escalated"
[ "$(q "['counts']['auto_resolved_fyi']")" = "1" ] && [ "$(q "['counts']['escalated']")" = "2" ] \
  && ok "#519: the outcome split is countable from receipts (1 auto-resolved, 2 escalated)" \
  || err "#519: counts wrong: $(q "['counts']")"
# a clean report passes the receipt lint
python3 "$F" lint --input "$work/o.json" >/dev/null 2>&1 \
  && ok "#519: lint passes when every in-scope receipt carries a valid outcome" \
  || err "#519: lint rejected a well-formed report"

# an overridden FYI reopens as a gate -> its receipt records escalated
present "--overridden cov" || err "present exited non-zero (override)"
[ "$(q "['fyis'][0]['outcome']")" = "escalated" ] && [ "$(q "['fyis'][0]['overridden']")" = "True" ] \
  && ok "#519: an overridden FYI's receipt records outcome=escalated (disposition, not origin)" \
  || err "#519: override did not flip the FYI outcome: $(q "['fyis'][0]")"
[ "$(q "['counts']['auto_resolved_fyi']")" = "0" ] && [ "$(q "['counts']['escalated']")" = "3" ] \
  && ok "#519: override recounts (0 auto-resolved, 3 escalated)" \
  || err "#519: override counts wrong: $(q "['counts']")"

# lint REJECTS a report whose receipt is missing a valid outcome
python3 -c "
import json
r=json.load(open('$work/o.json')); r['fyis'][0].pop('outcome',None)
json.dump(r,open('$work/bad.json','w'))
"
python3 "$F" lint --input "$work/bad.json" >/dev/null 2>&1 \
  && err "#519: lint accepted a receipt with no outcome" \
  || ok "#519: lint rejects a receipt missing a valid outcome (lockstep gate)"


# --- Story 18.51 (#567): gate-item content grounding reaches CANDIDATE TEXT ---
# Pre-#567 `_check_gate` enforced the <=3 cap, no pre-selected default, and
# grounding POINTERS -- candidate prose itself was never inspected, so an
# invented premise in the answer the owner ratifies passed cleanly.
cat > "$work/f.json" <<'JSON'
{"forks":[{"id":"f1","in_scope":true,"question":"Which release cadence?",
  "consult":{"covered":false,"candidates":[
    {"answer":"weekly, since it was originally built for batch runs","grounding":[]}]}}]}
JSON
present && err "an ungrounded premise in a candidate answer was accepted" \
  || { grep -q 'confabulated-premise' "$work/e" \
       && ok "#567: an ungrounded premise in a gate CANDIDATE is refused" \
       || err "candidate premise refused for the wrong reason: $(cat "$work/e")"; }

# The same candidate GROUNDED at the point of use is accepted.
cat > "$work/f.json" <<'JSON'
{"forks":[{"id":"f1","in_scope":true,"question":"Which release cadence?",
  "consult":{"covered":false,"candidates":[
    {"answer":"weekly, since it was originally built (unverified — no declared source) for batch runs","grounding":[]}]}}]}
JSON
present && ok "#567: an inline \`unverified —\` marker grounds the candidate" \
  || err "grounded candidate refused: $(cat "$work/e")"

# The gate QUESTION is owner-facing text too.
cat > "$work/f.json" <<'JSON'
{"forks":[{"id":"f1","in_scope":true,
  "question":"Given the tool was originally built for replay, which cadence?",
  "consult":{"covered":false,"candidates":[{"answer":"weekly","grounding":[]}]}}]}
JSON
present && err "an ungrounded premise in the gate question was accepted" \
  || { grep -q 'question: confabulated-premise' "$work/e" \
       && ok "#567: an ungrounded premise in the gate QUESTION is refused" \
       || err "gate-question premise not refused: $(cat "$work/e")"; }

if [ "$fail" -eq 0 ]; then
  printf '\nAll fork-consult checks passed.\n'; exit 0
else
  printf '\nfork-consult checks FAILED.\n' >&2; exit 1
fi
