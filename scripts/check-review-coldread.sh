#!/usr/bin/env sh
# check-review-coldread.sh — verify the cold-read pass (Story 5.5): context-free
# (draft only, no repo/project context), the six-question reader rubric, the
# comparison to the journal q2/q5 intent anchors, capped-anchor tolerance, and the severity mapping (claim/audience
# mismatch = blocker; confusion/assumed-knowledge = should-fix). POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/review-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "review-article SKILL.md exists" || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

sec=$(awk '/^## Pass [45] — Cold read/{f=1} f&&/^## Arbitration/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "cold-read pass section present" || { err "Pass 4 section missing"; printf '\nFAILED.\n' >&2; exit 1; }

has() { printf '%s\n' "$sec" | grep -qi "$1" && ok "$2" || err "$2 — missing"; }

# Context-free by design.
has 'ONLY the draft\|only the draft'          "runs on the draft only"
has 'no repo access\|no project context'      "no repo/project context"
has 'any cheap model'                         "runs on any cheap model"

# Six-question reader rubric.
has 'claim'                                   "rubric Q1: the claim"
has 'who is it for\|audience'                 "rubric Q2: who is it for"
has 'first get confused\|first.*confus'       "rubric Q3: first confusion point"
has 'assume you already knew\|assumed.*knew'  "rubric Q4: assumed knowledge"
has 'read past the first screen'              "rubric Q5: read past first screen"
has 'do after'                                "rubric Q6: next action"

# Comparison to interview answers and severity mapping.
has 'intent anchor'                           "compares to the author's intent anchors"
has 'q2'                                       "claim anchor comes from journal q2"
has 'q5'                                       "audience anchor comes from journal q5"

# Capped-anchor tolerance (Story 15.4): a q5 displaced by policy seeds is an
# absent anchor — informational note, partial comparison, never a failure.
FULL=$(cat "$SKILL")
printf '%s' "$FULL" | tr '\n' ' ' | tr -s ' ' | grep -qi 'recorded as .*capped.* (Story 15.4: displaced by policy-seeded' \
  && ok "capped journal entry recognized as an absent anchor" \
  || err "capped-anchor handling missing"
printf '%s' "$FULL" | tr '\n' ' ' | tr -s ' ' | grep -qi 'never fail or block on the absence' \
  && ok "absent anchor never fails or blocks the pass" \
  || err "never-fail rule missing"
printf '%s' "$FULL" | tr '\n' ' ' | tr -s ' ' | grep -qi 'a partial anchor set is a note, never a pass failure' \
  && ok "single absent anchor: partial comparison + informational note" \
  || err "partial-anchor comparison rule missing"
has 'blocker'                                 "claim/audience mismatch = blocker"
has 'should-fix'                              "confusion/assumed-knowledge = should-fix"

# Behavioral: the capped-q5 input case is REAL — produce a journal with the
# actual interview+journal commands (policy seeds displace q5 under the ≤5
# budget on F1) and confirm q5 lands status=capped (Story 15.4 AC).
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
state='{"stage":"consume","fact_sheet":[],"needs_owner":[{"topic":"significance","candidate":"x","reason":"y"}]}'
printf '%s' "$state" | python3 scripts/draft-pipeline.py interview --framework F1 \
  --items scripts/fixtures/interview-items/valid.json - > "$work/iv.json" 2>/dev/null
python3 - "$work/iv.json" "$work/ans.json" <<'PYE'
import json, sys
d = json.load(open(sys.argv[1]))
json.dump([{"id": q["id"], "disposition": "skipped"} for q in d["questions"]],
          open(sys.argv[2], "w"))
PYE
q5status=$(python3 scripts/draft-pipeline.py journal --interview "$work/iv.json" \
  --answers "$work/ans.json" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(e['status'] for e in d['journal'] if e['id']=='q5'))")
[ "$q5status" = "capped" ] \
  && ok "real interview+journal run yields q5 status=capped (the case the cold read must tolerate)" \
  || err "expected q5 capped from the real pipeline, got '$q5status'"

# Policy-calibrated emphasis (Story 13.39, SPEC-policy-editorial-direction
# CAP-3): anchors flow to structure/prose prompts only, never the cold read;
# criteria stay fixed; influence recorded in consulted:.
SKILL="skills/review-article/SKILL.md"
grep -q 'Policy-calibrated emphasis' "$SKILL" \
  && ok "policy-calibrated emphasis contract present" || err "CAP-3 contract missing"
grep -q 'NEVER to the cold read' "$SKILL" \
  && ok "anchors never flow to the cold read (control arm)" || err "cold-read exclusion missing"
grep -qi 'changes only .*what those reviewers weight' "$SKILL" \
  && ok "criteria fixed — only weighting changes" || err "fixed-criteria clause missing"
grep -qi "editorial_anchor.*is the claim.*anchor when present\|editorial_anchor. (Story 13.38) is the claim" "$SKILL" \
  && ok "claim anchor consumes the journal's editorial_anchor (13.38 handoff)" \
  || err "editorial_anchor consumption missing"
grep -qi 'influence in the review' "$SKILL" \
  && ok "policy-derived anchors recorded in the review consulted: line" \
  || err "consulted recording missing"
grep -q 'the claim intent anchor' "$SKILL" \
  && ok "shared preamble carries the claim anchor" || err "claim anchor missing from preamble"

if [ "$fail" -eq 0 ]; then
  printf '\nAll cold-read checks passed.\n'; exit 0
else
  printf '\ncold-read checks FAILED.\n' >&2; exit 1
fi
