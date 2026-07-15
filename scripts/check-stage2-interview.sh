#!/usr/bin/env sh
# check-stage2-interview.sh — verify the bounded gap interview (Story 4.3).
# POSIX shell + stdlib Python.

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
# iv STATE_JSON FRAMEWORK -> the selection JSON
iv() { printf '%s' "$1" | python3 "$DP" interview --framework "$2"; }
# jq-ish: read a python expression over the parsed JSON on stdin
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Skill documents the stage-2 contract.
grep -q 'draft-pipeline.py interview' "$SKILL" && ok "skill wires in the interview step" || err "interview not wired in"
grep -q 'at most 5' "$SKILL" && ok "skill states the <=5 cap" || err "cap not documented"
grep -qi 'bullet' "$SKILL" && ok "skill accepts bullet answers" || err "bullet answers not documented"
grep -q 'verbatim' "$SKILL" && ok "skill captures answers verbatim" || err "verbatim capture not documented"

# 2. At most 5 questions, prioritized/framework-tailored, gaps first.
out=$(iv '{"fact_sheet":[{"claim":"Throughput rose 2x"}],"needs_owner":[{"topic":"surprise"},{"topic":"significance"}]}' F1)
[ "$(printf '%s' "$out" | jget 'd["asked"]')" -le 5 ] && ok "asks <= 5 questions" || err "exceeded 5 questions"
# Selection priority: every confirmed NEEDS-OWNER gap survives into the asked
# set (display order is the separate pinned presentation contract, Story 13.30).
printf '%s' "$out" | jget 'all(any(q["id"]==g and q["from_gap"] for q in d["questions"]) for g in ["q1","q2"])' | grep -q True \
  && ok "confirmed NEEDS-OWNER gaps are selected into the asked set" || err "gaps not prioritized in selection"

# 3. Hard cap even when NEEDS-OWNER exceeds five gaps.
big='{"fact_sheet":[],"needs_owner":[{"topic":"surprise"},{"topic":"significance"},{"topic":"warning"},{"topic":"opinion"},{"topic":"other"},{"topic":"surprise"}]}'
[ "$(iv "$big" F1 | jget 'd["asked"]')" -le 5 ] && ok "<=5 cap holds when NEEDS-OWNER > 5 gaps" || err "cap broken with many gaps"

# 4. De-dup is semantic (synonym), not literal: a differently-phrased fact
#    suppresses the matching question when it is not a NEEDS-OWNER gap.
dd='{"fact_sheet":[{"claim":"This guide is written for backend engineers"}],"needs_owner":[]}'
iv "$dd" F3 | jget 'any(q["id"]=="q5" for q in d["questions"])' | grep -q False \
  && ok "semantic de-dup suppresses a redundant question (audience already stated)" || err "de-dup did not suppress"
# ...but a NEEDS-OWNER gap re-raises the same topic (warning is a real gap topic).
rr='{"fact_sheet":[{"claim":"a known caveat: do not use on TPUs"}],"needs_owner":[{"topic":"warning"}]}'
iv "$rr" F3 | jget 'any(q["id"]=="q3" for q in d["questions"])' | grep -q True \
  && ok "a NEEDS-OWNER gap re-raises an otherwise-suppressed question" || err "gap did not re-raise"

# 5. Empty-gap: fact sheet covers everything (and carries a result, so the
#    evidence fallback q8 has no condition) + no gaps -> zero questions.
full='{"fact_sheet":[{"claim":"the key result that matters most; a surprising unexpected finding; a caveat/limitation; we gave up speed as a tradeoff; written for SREs; we argue our opinion","kind":"result"}],"needs_owner":[]}'
[ "$(iv "$full" F1 | jget 'd["asked"]')" -eq 0 ] && ok "asks zero when harvest covers everything (no padding)" || err "padded instead of asking zero"

# 6. Deterministic: same input twice -> identical selection.
a=$(iv '{"fact_sheet":[],"needs_owner":[{"topic":"warning"}]}' F2)
b=$(iv '{"fact_sheet":[],"needs_owner":[{"topic":"warning"}]}' F2)
[ "$a" = "$b" ] && ok "selection is deterministic (stable across runs)" || err "non-deterministic selection"

# 7. Prioritization is framework-tailored (tied to GATE slots, not bank order).
s='{"fact_sheet":[],"needs_owner":[]}'
f1=$(iv "$s" F1 | jget 'd["questions"][0]["id"]')
f4=$(iv "$s" F4 | jget 'd["questions"][0]["id"]')
[ "$f1" != "$f4" ] && ok "different frameworks yield different priority (F1:$f1 vs F4:$f4)" || err "framework did not tailor order"

# 8. Every asked question carries a stable id (so bullet answers key to it).
iv "$s" F1 | jget 'all(q.get("id") and q.get("text") for q in d["questions"])' | grep -q True \
  && ok "questions carry stable ids + text (answers key by id)" || err "question ids/text missing"

# 9. Pinned presentation order (Story 13.30, SPEC-draft-article-ux CAP-4):
#    claim/angle -> audience -> significance -> color; echoed as
#    presentation_order and matching the questions array.
[ "$(iv "$s" F1 | jget '",".join(d["presentation_order"])')" = "q5,q2,q4,q3,q1" ] \
  && ok "F1 presentation: audience, significance, then color (pinned)" || err "F1 presentation order wrong"
[ "$(iv "$s" F4 | jget 'd["presentation_order"][0]')" = "q6" ] \
  && ok "F4: the claim/angle (opinion) question presents first" || err "claim slot not first for F4"
iv "$s" F1 | jget 'd["presentation_order"] == [q["id"] for q in d["questions"]]' | grep -q True \
  && ok "presentation_order matches the questions array" || err "order field out of sync"

# 10. Evidence fallback (Story 13.30, CAP-5): q8 joins only when harvest has
#     no number/result entry.
cov='{"fact_sheet":[{"claim":"a surprising unexpected finding; we gave up speed as a tradeoff; a caveat limitation; written for SREs","kind":"decision"}],"needs_owner":[]}'
iv "$cov" F2 | jget 'any(q["id"]=="q8" for q in d["questions"])' | grep -q True \
  && ok "no number/result fact -> evidence fallback q8 is asked" || err "q8 missing without evidence"
covr='{"fact_sheet":[{"claim":"a surprising unexpected finding; we gave up speed as a tradeoff; a caveat limitation; written for SREs","kind":"decision"},{"claim":"p99 latency 180ms","kind":"number"}],"needs_owner":[]}'
iv "$covr" F2 | jget 'any(q["id"]=="q8" for q in d["questions"])' | grep -q False \
  && ok "a number/result fact present -> q8 not asked (condition-gated)" || err "q8 asked despite evidence"

# 11. Journal echoes the presentation order (attributable mis-ordering).
ivout=$(iv "$s" F4)
ans=$(printf '%s' "$ivout" | jget 'json.dumps([{"id": q["id"], "disposition": "skipped"} for q in d["questions"]])')
printf '%s' "$ivout" > /tmp/iv-$$.json; printf '%s' "$ans" > /tmp/ans-$$.json
python3 "$DP" journal --interview /tmp/iv-$$.json --answers /tmp/ans-$$.json \
  | jget 'd.get("presentation_order",[])[0]' | grep -q q6 \
  && ok "journal echoes presentation_order" || err "journal does not echo the order"
rm -f /tmp/iv-$$.json /tmp/ans-$$.json

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-2 interview checks passed.\n'; exit 0
else
  printf '\nstage-2 interview checks FAILED.\n' >&2; exit 1
fi
