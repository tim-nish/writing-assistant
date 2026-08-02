#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# check-stage2-interview.sh — verify the bounded gap interview (Story 4.3).
# POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"
__DA_ALL="${TMPDIR:-/tmp}/da-skill-all.$$.md"
cat skills/draft-article/SKILL.md skills/draft-article/stages/stage0.md skills/draft-article/stages/stage1.md skills/draft-article/stages/stage2.md skills/draft-article/stages/stage3.md skills/draft-article/stages/gate.md skills/draft-article/stages/stage4.md skills/draft-article/stages/complete.md > "$__DA_ALL"


DP="$root/scripts/draft-pipeline.py"
SKILL="$__DA_ALL"
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
out=$(iv '{"fact_sheet":[{"claim":"Throughput rose 2x"}],"needs_owner":[{"topic":"warning"},{"topic":"significance"}]}' F1)
[ "$(printf '%s' "$out" | jget 'd["asked"]')" -le 5 ] && ok "asks <= 5 questions" || err "exceeded 5 questions"
# Selection priority: every confirmed NEEDS-OWNER gap survives into the asked
# set (display order is the separate pinned presentation contract, Story 13.30).
printf '%s' "$out" | jget 'all(any(q["id"]==g and q["from_gap"] for q in d["questions"]) for g in ["g-warning","g-significance"])' | grep -q True \
  && ok "confirmed NEEDS-OWNER gaps are selected into the asked set" || err "gaps not prioritized in selection"

# 3. Hard cap even when NEEDS-OWNER exceeds five gaps.
big='{"fact_sheet":[],"needs_owner":[{"topic":"warning"},{"topic":"significance"},{"topic":"tradeoff"},{"topic":"opinion"},{"topic":"other"},{"topic":"audience"}]}'
[ "$(iv "$big" F1 | jget 'd["asked"]')" -le 5 ] && ok "<=5 cap holds when NEEDS-OWNER > 5 gaps" || err "cap broken with many gaps"

# 4. NOTHING UNRAISED IS ASKED (Story 20.131, #1147). This block asserted that
#    semantic de-dup SUPPRESSED a bank question the fact sheet already covered.
#    There is no bank to suppress from: a candidate exists only where harvest
#    raised a gap, so the property holds by construction. Both halves are kept,
#    re-pointed — the covered-and-unraised topic is absent, and a raised one is
#    present even when the fact sheet also covers it.
dd='{"fact_sheet":[{"claim":"This guide is written for backend engineers"}],"needs_owner":[]}'
#    Scoped to the CAPPED pool: the property is about the candidate set, and the mandated
#    tier is by definition not candidates (Story 20.172 put the audience declaration there,
#    where it is an obligation the pipeline owes regardless of what harvest raised).
iv "$dd" F3 | jget 'any("audience" in q["id"] for q in d["questions"] if q["id"] not in d["mandated"])' | grep -q False \
  && ok "a covered topic the material did not raise is never asked" || err "de-dup did not suppress"
rr='{"fact_sheet":[{"claim":"a known caveat: do not use on TPUs"}],"needs_owner":[{"topic":"warning"}]}'
iv "$rr" F3 | jget 'any(q["id"]=="g-warning" for q in d["questions"])' | grep -q True \
  && ok "a NEEDS-OWNER gap is asked even when the fact sheet also covers it" || err "gap did not re-raise"

# 5. Empty-gap: fact sheet covers everything (and carries a result, so the
#    evidence fallback q8 has no condition) + no gaps -> zero questions.
full='{"fact_sheet":[{"claim":"the key result that matters most; a surprising unexpected finding; a caveat/limitation; we gave up speed as a tradeoff; written for SREs; we argue our opinion","kind":"result"}],"needs_owner":[]}'
[ "$(iv "$full" F1 | jget 'd["asked"]')" -eq 0 ] && ok "asks zero when harvest covers everything (no padding)" || err "padded instead of asking zero"

# 6. Deterministic: same input twice -> identical selection.
a=$(iv '{"fact_sheet":[],"needs_owner":[{"topic":"warning"}]}' F2)
b=$(iv '{"fact_sheet":[],"needs_owner":[{"topic":"warning"}]}' F2)
[ "$a" = "$b" ] && ok "selection is deterministic (stable across runs)" || err "non-deterministic selection"

# 7. FRAMEWORK-TAILORED PRIORITY IS GONE (Story 20.131, #1147). This asserted
#    that F1 and F4 lead with different questions — a property of the deleted
#    per-framework priority lists. The ruling removes the generator, so the
#    replacement property is the one that survives it: the SAME material yields
#    the same interview whatever the article type, because the candidates come
#    from the material and not from the type.
s='{"fact_sheet":[],"needs_owner":[{"topic":"warning"}]}'
f1=$(iv "$s" F1 | jget '[q["id"] for q in d["questions"]]')
f4=$(iv "$s" F4 | jget '[q["id"] for q in d["questions"]]')
[ "$f1" = "$f4" ] && ok "the same material yields the same interview across article types (F1 == F4)" \
  || err "the article type still tailors the candidate set (F1:$f1 vs F4:$f4)"

# 8. Every asked question carries a stable id (so bullet answers key to it).
iv "$s" F1 | jget 'all(q.get("id") and q.get("text") for q in d["questions"])' | grep -q True \
  && ok "questions carry stable ids + text (answers key by id)" || err "question ids/text missing"

# 9. Pinned presentation order (Story 13.30, SPEC-draft-article-ux CAP-4):
#    claim/angle -> audience -> significance -> color; echoed as
#    presentation_order and matching the questions array.
# THE TOPIC ORDERING WENT WITH THE BANK (Story 20.131, #1147): `claim/angle ->
# audience -> significance -> color` ordered questions that no longer exist.
# What survives is the one rule whose reason sits outside the generator — a
# policy-seeded tension leads, because it reframes every answer after it.
seeded=$(printf '%s' '{"fact_sheet":[],"needs_owner":[{"topic":"warning"}]}' \
  | python3 "$DP" interview --framework F1 --items scripts/fixtures/interview-items/valid.json -)
[ "$(printf '%s' "$seeded" | jget '[q for q in d["presentation_order"] if q not in d["mandated"]][0]')" = "t1" ] \
  && ok "a policy-seeded tension presents first (it reframes the answers after it)" \
  || err "the policy seed does not lead the presentation"
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

# 10b. Story 18.27 (#506, CAP-8 clause) — the depth question MAY offer suggested
#      reading-time bands as the owner's depth-choice unit, recorded AS the depth
#      directive (never a reading-time target).
grep -qiE 'reading-time band|reading time band' "$SKILL" \
  && ok "SKILL: the depth question may offer reading-time bands (#506)" || err "SKILL missing reading-time bands"
grep -qiE 'recorded as the depth directive|as the depth directive' "$SKILL" \
  && ok "SKILL: the band pick is recorded AS the depth directive, not a target (#506)" \
  || err "SKILL missing the recorded-as-directive rule"

# 11. Journal echoes the presentation order (attributable mis-ordering).
ivout=$(iv "$s" F4)
ans=$(printf '%s' "$ivout" | jget 'json.dumps([{"id": q["id"], "disposition": "skipped"} for q in d["questions"]])')
printf '%s' "$ivout" > /tmp/iv-$$.json; printf '%s' "$ans" > /tmp/ans-$$.json
# Asserted as EQUALITY with the interview's own order rather than against a
# bank id (Story 20.131, #1147): what makes a mis-ordered run attributable is
# that the journal echoes what was presented, whatever that was.
order=$(printf '%s' "$ivout" | jget 'json.dumps(d["presentation_order"])')
python3 "$DP" journal --interview /tmp/iv-$$.json --answers /tmp/ans-$$.json \
  | jget 'json.dumps(d.get("presentation_order",[]))' | grep -qF "$order" \
  && ok "journal echoes presentation_order" || err "journal does not echo the order"
rm -f /tmp/iv-$$.json /tmp/ans-$$.json

# --- CAP-8 depth offer is mechanical, not prompt-trusted (Story 18.42, #542) --
# Run 20260722T095152 re-entered via the scope-ratification screen and never
# presented the depth question, defaulting the depth silently. The offer is now
# GENERATED from run state, so no invocation path can omit it, and it rides the
# mandated tier so the <=5 cap can never displace it.
nod='{"fact_sheet":[],"needs_owner":[]}'
iv "$nod" F1 | jget 'd["depth_offer"]' | grep -q '^presented$' \
  && ok "depth: no directive -> the offer is generated (never prompt-trusted)" \
  || err "depth offer not generated on a directive-less run"
iv "$nod" F1 | jget '"depth" in d["mandated"] and d["asked"] <= 5' | grep -q True \
  && ok "depth: the offer rides the mandated tier, outside the ≤5 cap" \
  || err "depth offer counted against the cap or missing from the tier"
# It TRAILS the capped set: the claim/angle question keeps presentation slot 1
# (CAP-4), which the editorial anchor reads.
# (The tail is the whole TRAILING group, not one item, since Story 20.172 added the
# audience declaration beside the depth offer — what is asserted is that the offer is in
# it and not in slot 1, which is what the CAP-4 reason actually says.)
iv "$nod" F4 | jget 'd["presentation_order"][0] != "depth" and "depth" in d["presentation_order"][-2:]' \
  | grep -q True \
  && ok "depth: the offer trails the capped set (claim/angle keeps slot 1)" \
  || err "depth offer displaced the claim/angle lead"
# A directive already given -> no re-ask, in either state shape.
iv '{"depth":{"level":"deep-dive"},"fact_sheet":[],"needs_owner":[]}' F1 \
  | jget 'd["depth_offer"] == "directive-present" and "depth" not in d["mandated"]' | grep -q True \
  && ok "depth: a top-level directive is not re-offered (no double-ask)" \
  || err "depth offer re-presented despite a directive"
iv '{"run_state":{"depth":{"scope":"just the retry bug"}},"fact_sheet":[],"needs_owner":[]}' F1 \
  | jget 'd["depth_offer"] == "directive-present"' | grep -q True \
  && ok "depth: a nested run_state directive is honored too" \
  || err "nested run_state depth directive ignored"
# depth-check: accounted runs pass; an unaccounted run DISCLOSES the default.
tmpd=$(mktemp -d)
iv "$nod" F1 > "$tmpd/offered.json"
python3 "$DP" depth-check --interview "$tmpd/offered.json" >/dev/null 2>&1 \
  && ok "depth-check: an offered run is accounted for (exit 0)" \
  || err "depth-check failed an offered run"
printf '{"stage":"interview","questions":[],"mandated":[]}' > "$tmpd/silent.json"
if python3 "$DP" depth-check --interview "$tmpd/silent.json" >"$tmpd/out" 2>&1; then
  err "depth-check passed a run that silently defaulted the depth"
else
  grep -qi 'without asking' "$tmpd/out" \
    && ok "depth-check: a silent default exits 1 and discloses the applied default" \
    || err "depth-check disclosure message wrong: $(cat "$tmpd/out")"
fi
rm -rf "$tmpd"
# SKILL states the mechanical guarantee.
grep -q 'depth-check' "$SKILL" && grep -qi 'fresh or re-opened' "$SKILL" \
  && ok "SKILL states the depth offer is guaranteed on every run (incl. re-entry)" \
  || err "SKILL missing the mechanical depth-offer guarantee"

# --- The AUDIENCE DECLARATION rides the same tier (Story 20.172, #1283) -------
# The stage 3->4 quality gate hard-fails on frontmatter `audience`/`audience_id`
# (draft_variants.py:219-237) but its interview producer went with the question
# bank (#1147), leaving agent composition at the fill as the only live path.
# The ask is now GENERATED from run state as the third mandated-tier member, so
# no invocation path can omit it, and it is a SELECTION over the installed
# profiles' audience vocabulary plus a free-form named reader.
PROFD="${TMPDIR:-/tmp}/da-profiles.$$"
mkdir -p "$PROFD"
cp config/platform-profiles/zenn.example.yaml "$PROFD/zenn.yaml"
cp config/platform-profiles/devto.example.yaml "$PROFD/devto.yaml"
ivp() { printf '%s' "$1" | python3 "$DP" interview --framework "$2" --profiles-dir "$PROFD"; }

ivp "$nod" F1 | jget 'd["audience_declaration"]' | grep -q '^presented$' \
  && ok "audience: no declaration in run state -> the ask is generated (never prompt-trusted)" \
  || err "audience declaration not generated on a declaration-less run"
ivp "$nod" F1 | jget '"audience" in d["mandated"] and d["asked"] <= 5' | grep -q True \
  && ok "audience: the ask rides the mandated tier, outside the ≤5 cap" \
  || err "audience ask counted against the cap or missing from the tier"
# It TRAILS with the depth offer — BLOCKING_MANDATED is unchanged, so the
# claim/angle question keeps presentation slot 1 (CAP-4).
ivp "$nod" F4 | jget 'd["presentation_order"][0] != "audience" and "audience" in d["presentation_order"][-2:]' \
  | grep -q True \
  && ok "audience: the ask trails the capped set (claim/angle keeps slot 1)" \
  || err "audience ask displaced the claim/angle lead"
grep -q 'BLOCKING_MANDATED = ("policy-reconciliation",)$' "$DP" \
  && ok "audience: BLOCKING_MANDATED is unchanged (obligations do not lead)" \
  || err "BLOCKING_MANDATED changed — a non-blocking obligation must not lead presentation"
# `audience_id` is a SELECTION over the resolved profiles' audience vocabulary.
ivp "$nod" F1 | jget 'json.dumps(d["audience_vocabulary"])' \
  | grep -q 'en-practitioner' \
  && ok "audience: options are drawn from the resolved platform profiles" \
  || err "audience options not drawn from the resolved profiles"
ivp "$nod" F1 \
  | jget '[q["options"] for q in d["questions"] if q["id"]=="audience"] == [d["audience_vocabulary"]]' \
  | grep -q True \
  && ok "audience: the ask carries the vocabulary as its selectable options" \
  || err "audience ask does not carry selectable options"
# No second capped-set audience question — one ask, never two.
aud_gap='{"fact_sheet":[],"needs_owner":[{"topic":"audience","candidate":"a practitioner"}]}'
ivp "$aud_gap" F1 \
  | jget 'sum(1 for q in d["questions"] if q["topic"]=="audience") == 1 and "audience" in d["mandated"]' \
  | grep -q True \
  && ok "audience: a capped-set audience question is absorbed, never asked twice" \
  || err "audience asked twice (capped-set question survived beside the mandated ask)"
ivp "$aud_gap" F1 | jget 'json.dumps([q.get("recommended_from") for q in d["questions"] if q["id"]=="audience"])' \
  | grep -q 'g-audience' \
  && ok "audience: the absorbed question rides the ask as its recommended default" \
  || err "absorbed audience question dropped instead of carried"
# A declaration already in run state -> no re-ask, in either state shape.
ivp '{"audience":{"audience_id":"en-practitioner"},"fact_sheet":[],"needs_owner":[]}' F1 \
  | jget 'd["audience_declaration"] == "directive-present" and "audience" not in d["mandated"]' \
  | grep -q True \
  && ok "audience: a top-level declaration is not re-asked (no double-ask)" \
  || err "audience ask re-presented despite a declaration in run state"
ivp '{"run_state":{"audience":{"audience_id":"ja-practitioner"}},"fact_sheet":[],"needs_owner":[]}' F1 \
  | jget 'd["audience_declaration"] == "directive-present"' | grep -q True \
  && ok "audience: a nested run_state declaration is honored too" \
  || err "nested run_state audience declaration ignored"
# No installed profile -> the ask DEGRADES to free text rather than refusing.
EMPTYD="${TMPDIR:-/tmp}/da-profiles-empty.$$"
mkdir -p "$EMPTYD"
printf '%s' "$nod" | python3 "$DP" interview --framework F1 --profiles-dir "$EMPTYD" \
  | jget 'd["audience_vocabulary"] == [] and "audience" in d["mandated"]' | grep -q True \
  && ok "audience: no installed profile degrades to a free-text ask (never a refusal)" \
  || err "audience ask refused or vanished with no installed profile"
rmdir "$EMPTYD"
rm -f "$PROFD"/*.yaml; rmdir "$PROFD"
# The rationale is in the tier, and the anchor guard moved WITH it (lockstep).
grep -q '"audience-declaration"' "$DP" \
  && ok "audience: 'audience-declaration' is a MANDATED_RATIONALES member" \
  || err "audience-declaration rationale not in the mandated tier"
grep -q 'CAP-8 depth offer, the' "$DP" \
  && ok "audience: the editorial-anchor guard enumerates the third member (lockstep)" \
  || err "the anchor guard's tier enumeration did not move with MANDATED_RATIONALES"
# Skill prose names the shipped producer, in both directions.
grep -qi 'mandated audience declaration' "$SKILL" \
  && ok "skill names the mandated audience declaration as the fill's producer" \
  || err "skill prose still describes the producerless state"
grep -q 'no interview producer' "$SKILL" \
  && err "the interim 'no interview producer today (#1283)' prose survived the code" \
  || ok "the interim producerless prose is gone"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-2 interview checks passed.\n'; exit 0
else
  printf '\nstage-2 interview checks FAILED.\n' >&2; exit 1
fi
