#!/usr/bin/env sh
# check-narrative-structure.sh — verify F2 plan-time narrative-structure choice
# (Story 18.26, SPEC-article-frameworks CAP-4, #503): the argument-plan sub-step
# proposes 2-3 candidate structures for the selected elements — sibling-lessons
# (default), chronological journey, single-incident deep thread, thematic braid
# — each with a one-line rationale grounded in the selected elements' evidence
# kinds; combining elements into ONE narrative thread is a supported structure
# (composition, not selection — CAP-9 unchanged); the owner picks or counter-
# proposes; default sibling-lessons when no choice; the chosen structure passes
# the existing Stage 3->4 gate. POSIX shell + stdlib Python only.

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

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

ST() { printf '%s' "$1" | python3 "$DP" structures; }

# --- 1. chronology-rich clusters -> journey proposed; >=2 candidates -------------
chrono='{"elements":[
  {"id":"lesson:retry-storm","kinds":["chronology","cost"]},
  {"id":"lesson:token-budget","kinds":["chronology","motivation"]},
  {"id":"lesson:cache-warmth","kinds":["chronology"]}]}'
ST "$chrono" > /tmp/ns-$$.json 2>/dev/null || err "structures command failed"
python3 - /tmp/ns-$$.json <<'PYEOF' && ok "chronology-rich clusters -> a chronological-journey candidate, >=2 candidates, each with an element-grounded rationale" || err "journey proposal wrong"
import json, sys
d = json.load(open(sys.argv[1]))
cands = d["candidates"]
assert len(cands) >= 2, cands
names = {c["structure"] for c in cands}
assert "chronological-journey" in names, names
# each candidate carries a one-line rationale grounded in the elements' kinds/ids
for c in cands:
    r = (c.get("rationale") or "").lower()
    assert r and ("chronolog" in r or "incident" in r or "lesson" in r
                  or "theme" in r or "cluster" in r or "sibling" in r), c
PYEOF

# --- 2. sibling-lessons is always present and marked the default ----------------
python3 - /tmp/ns-$$.json <<'PYEOF' && ok "sibling-lessons is always present and is the default (no hardened single shape, but a stable fallback)" || err "sibling-lessons default missing"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("default") == "sibling-lessons", d.get("default")
sib = next((c for c in d["candidates"] if c["structure"] == "sibling-lessons"), None)
assert sib is not None and sib.get("default") is True, d["candidates"]
# sibling-lessons composes one SECTION per element (not beats)
assert sib.get("composition") == "sections", sib
PYEOF

# --- 3. one dominant incident -> single-incident-deep-thread proposed -----------
dom='{"elements":[
  {"id":"lesson:the-outage","kinds":["chronology","cost","motivation"],"dominant_incident":true},
  {"id":"lesson:the-fix","kinds":["motivation"]}]}'
ST "$dom" > /tmp/ns2-$$.json 2>/dev/null
python3 - /tmp/ns2-$$.json <<'PYEOF' && ok "one dominant incident -> a single-incident deep-thread candidate" || err "deep-thread proposal wrong"
import json, sys
d = json.load(open(sys.argv[1]))
names = {c["structure"] for c in d["candidates"]}
assert "single-incident-deep-thread" in names, names
PYEOF

# --- 4. combining into ONE thread yields elements-as-BEATS (composition, not
#        selection): every selected element survives as a beat (CAP-9 unchanged) -
python3 - /tmp/ns2-$$.json <<'PYEOF' && ok "single-thread structure yields the elements as beats — all selected elements preserved (composition, not selection)" || err "single-thread beats wrong"
import json, sys
d = json.load(open(sys.argv[1]))
thread = next(c for c in d["candidates"] if c["structure"] == "single-incident-deep-thread")
assert thread.get("composition") == "beats", thread
assert set(thread.get("beats", [])) == {"lesson:the-outage", "lesson:the-fix"}, thread
PYEOF

# --- 5. no signal / minimal input still proposes >=2 candidates (never one
#        hardened default) and defaults to sibling-lessons ------------------------
flat='{"elements":[{"id":"lesson:a","kinds":["cost"]},{"id":"lesson:b","kinds":["motivation"]}]}'
ST "$flat" > /tmp/ns3-$$.json 2>/dev/null
python3 - /tmp/ns3-$$.json <<'PYEOF' && ok "even with no strong signal, >=2 candidates are offered (never a single hardened shape)" || err "flat case offered fewer than 2 candidates"
import json, sys
d = json.load(open(sys.argv[1]))
assert len(d["candidates"]) >= 2, d["candidates"]
assert d["default"] == "sibling-lessons", d
# a candidate cap of 3 (CAP-4: 2-3)
assert len(d["candidates"]) <= 3, d["candidates"]
PYEOF
rm -f /tmp/ns-$$.json /tmp/ns2-$$.json /tmp/ns3-$$.json

# --- 6. SKILL states the CAP-4 narrative-structure-choice contract --------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qiE 'narrative structure|candidate structures' \
  && ok "SKILL names the narrative-structure choice" || err "SKILL missing narrative-structure section"
printf '%s' "$S" | grep -qi 'CAP-4' \
  && ok "SKILL cites CAP-4" || err "SKILL missing the CAP-4 citation"
printf '%s' "$S" | grep -qiE '2-3 candidate|2.3 candidate|two to three' \
  && ok "SKILL: the sub-step proposes 2-3 candidate structures" \
  || err "SKILL missing the 2-3-candidates rule"
printf '%s' "$S" | grep -qi 'sibling-lessons' && printf '%s' "$S" | grep -qi 'chronological' \
  && printf '%s' "$S" | grep -qi 'deep thread' && printf '%s' "$S" | grep -qi 'braid' \
  && ok "SKILL names all four F2 structures" || err "SKILL missing one of the four structures"
printf '%s' "$S" | grep -qiE 'element-grounded|grounded in the selected elements|evidence kinds' \
  && ok "SKILL: each rationale is grounded in the selected elements' evidence kinds" \
  || err "SKILL missing the element-grounded rationale rule"
printf '%s' "$S" | grep -qiE 'composition, not selection|composition not selection' \
  && ok "SKILL: combining into one thread is composition, not selection (CAP-9 unchanged)" \
  || err "SKILL missing the composition-not-selection rule"
printf '%s' "$S" | grep -qiE 'counter-propose|proposal contract' \
  && ok "SKILL: the owner picks or counter-proposes under the proposal contract" \
  || err "SKILL missing the owner-choice/proposal-contract wiring"
printf '%s' "$S" | grep -qiE 'default(s)? (to )?sibling-lessons|sibling-lessons.*default' \
  && ok "SKILL: default sibling-lessons when no choice" || err "SKILL missing the default clause"
printf '%s' "$S" | grep -qiE 'pass(es)? the (existing )?(Stage 3.>?4 )?gate|Stage 3.>?4 gate' \
  && ok "SKILL: whichever structure is chosen must pass the existing Stage 3->4 gate" \
  || err "SKILL missing the gate-still-owns-coherence rule"

if [ "$fail" -eq 0 ]; then
  printf '\nAll narrative-structure checks passed.\n'; exit 0
else
  printf '\nnarrative-structure checks FAILED.\n' >&2; exit 1
fi
