#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario
#   class. The breach PRE-DATES story 20.164 (measured on main at 2544ms
#   against the 2000ms ceiling): the check shells out to the validator ~30
#   times. Declared here rather than left failing every scoped inner run.
# covers: scripts/validate-visual-set.py skills/draft-article/**
# grep-binding: file-set (#1325) — the join precondition is read across the
#   skill's whole file set. The $FO/$sec greps assert fan-out.md's and
#   stage3.md's own scheduling wording (which file states the concurrency IS
#   the assertion), so they stay single-file and ride those files' relocation.
# check-visual-set-plan.sh — verify the visual-set planning proposal (Story
# 13.58, SPEC-article-visuals CAP-2a). POSIX shell + stdlib Python.
#
# Covers: the set-level proposal precedes individual visual proposals; the plan
# enumerates role/elements/format/placement/evidence per member; an element
# without pointers routes to [VERIFY]/NEEDS-OWNER; a plan over the cap
# (declared slot + 2) is refused; a zero-visual plan is valid with no padding;
# modification stays within the cap; declining degrades to the per-slot flow.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

V="$root/scripts/validate-visual-set.py"
SKILL="skills/draft-article/stages/stage3.md"
SPEC="specs/spec-article-visuals/SPEC.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$V', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

pass() { printf '%s' "$2" | python3 "$V" --slot-count "$1" >/dev/null 2>&1; }
reason() { printf '%s' "$2" | python3 "$V" --slot-count "$1" 2>&1; }

sha=a1b2c3d4e5f6

# A well-formed one-member plan (slot_count 1, cap 3): every field present,
# each element evidenced (pointer, answer id, or [VERIFY]).
GOOD='{"members":[{"role":"the pipeline flow","required_elements":["harvest","draft","gate edge"],"format":"diagram","placement":"Section 3 - declared slot","evidence":{"harvest":"skills/harvest/SKILL.md:11@'"$sha"'","draft":"q4","gate edge":"[VERIFY: ordering argued in prose]"}}]}'
pass 1 "$GOOD" && ok "a complete, evidenced one-member plan is ratifiable" \
  || err "a valid plan was refused"

# A zero-visual plan is valid and needs no padding.
ZERO='{"members":[]}'
pass 1 "$ZERO" && ok "AC: a zero-visual plan is valid (no padding toward the cap)" \
  || err "zero-visual plan refused"
printf '%s' "$ZERO" | python3 "$V" --slot-count 1 2>/dev/null | grep -q '"zero_plan": true' \
  && ok "AC: a zero-visual plan reports zero members (never padded)" || err "zero plan not reported"

# Over the cap (slot 1 + 2 = 3): a 4-member plan is refused.
M='{"role":"r","required_elements":["e"],"format":"table","placement":"S","evidence":{"e":"'"$sha"'"}}'
OVER="{\"members\":[$M,$M,$M,$M]}"
reason 1 "$OVER" | grep -q 'exceed the cap of 3' \
  && ok "AC: a plan exceeding declared slot + 2 is refused (cap fixture)" \
  || err "over-cap plan accepted"
# Exactly at the cap passes (3 members with slot_count 1).
ATCAP="{\"members\":[$M,$M,$M]}"
pass 1 "$ATCAP" && ok "a plan exactly at the cap (slot + 2) is ratifiable" \
  || err "at-cap plan refused"
# The cap scales with the declared slot count (F3 has a required table slot).
pass 3 "{\"members\":[$M,$M,$M,$M,$M]}" \
  && ok "the cap scales with the declared slot count (slot 3 -> cap 5)" \
  || err "cap did not scale with slot count"

# Each member must enumerate role/elements/format/placement.
NOROLE='{"members":[{"required_elements":["e"],"format":"table","placement":"S","evidence":{"e":"'"$sha"'"}}]}'
reason 1 "$NOROLE" | grep -q 'role: required' && ok "refuse: a member without a role" || err "roleless member accepted"
NOELEM='{"members":[{"role":"r","required_elements":[],"format":"table","placement":"S","evidence":{}}]}'
reason 1 "$NOELEM" | grep -q 'at least one required element' \
  && ok "refuse: a member with no required elements" || err "elementless member accepted"

# An element without pointers routes to [VERIFY]/NEEDS-OWNER — an unevidenced,
# unmarked element is refused (never laundered in).
UNSOURCED='{"members":[{"role":"r","required_elements":["e"],"format":"diagram","placement":"S","evidence":{"e":""}}]}'
reason 1 "$UNSOURCED" | grep -q 'no evidence' \
  && ok "AC: an element with no pointer and no [VERIFY] marker is refused" \
  || err "unsourced element accepted"
# The same element WITH a [VERIFY] marker is accepted (routes to NEEDS-OWNER).
VERIFIED='{"members":[{"role":"r","required_elements":["e"],"format":"diagram","placement":"S","evidence":{"e":"[VERIFY: unpinned relationship]"}}]}'
pass 1 "$VERIFIED" && ok "AC: an unverified element carrying [VERIFY] is accepted (CAP-3 routing)" \
  || err "[VERIFY] element refused"

# --- Skill + spec wiring ---------------------------------------------------
sec=$(awk '/^### Visual-set plan/{f=1} f && /^### Visual proposals/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "skill has a Visual-set plan section before Visual proposals" \
  || err "Visual-set plan section missing or misordered"
printf '%s' "$sec" | grep -qi 'before any individual visual proposal' \
  && ok "AC: set proposal precedes individual visual proposals" || err "ordering not stated"
printf '%s' "$sec" | grep -q 'validate-visual-set.py' && ok "skill wires in the set validator" || err "validator not wired"
printf '%s' "$sec" | grep -qi 'Zero is a valid plan' && ok "skill states zero is a valid plan" || err "zero-plan rule missing"
printf '%s' "$sec" | grep -qi 'without re-litigating approved members' \
  && ok "AC: modification does not re-litigate approved members" || err "modification rule missing"
printf '%s' "$sec" | grep -qi 'degrades to the per-slot flow' \
  && ok "AC: declining degrades to the per-slot flow" || err "decline-degrade rule missing"
grep -q 'CAP-2a' "$SPEC" && ok "spec declares CAP-2a" || err "spec missing CAP-2a"

# --- First-try ratifiability (Story 13.79) ---------------------------------
# The skill scaffolds the required shape before the validator call.
printf '%s' "$sec" | grep -q '"required_elements"' \
  && ok "AC(13.79): skill shows the required plan shape (scaffold)" \
  || err "skill has no authoring scaffold for the plan shape"
printf '%s' "$sec" | grep -qi 'resolve exactly the named fields' \
  && ok "AC(13.79): skill instructs fixing exactly the named fields on refusal" \
  || err "skill missing the refusal-resolution instruction"
# Refusals carry a concrete fix, not just the rule.
reason 1 "$NOROLE" | grep -q 'fix:' \
  && ok "AC(13.79): a missing-role refusal names the concrete fix" \
  || err "missing-role refusal has no fix hint"
reason 1 "$NOELEM" | grep -q 'fix: list the nodes' \
  && ok "AC(13.79): an empty-elements refusal says what to list" \
  || err "empty-elements refusal has no fix hint"
reason 1 "$UNSOURCED" | grep -q 'fix: set' \
  && ok "AC(13.79): an unevidenced-element refusal shows the accepted forms" \
  || err "unevidenced-element refusal has no fix hint"
BADPTR='{"members":[{"role":"r","required_elements":["e"],"format":"diagram","placement":"S","evidence":{"e":"just prose"}}]}'
reason 1 "$BADPTR" | grep -q 'fix: use' \
  && ok "AC(13.79): a malformed-evidence refusal lists the accepted grammar" \
  || err "malformed-evidence refusal has no fix hint"
FSID='{"members":[{"role":"r","required_elements":["e"],"format":"diagram","placement":"S","evidence":{"e":"fs-11"}}]}'
reason 1 "$FSID" | grep -q 'fact-sheet id' \
  && ok "F72: a fact-sheet-id evidence value gets the targeted dereference fix" \
  || err "fact-sheet-id refusal not targeted"
reason 1 "$NOROLE" | grep -q 'resolve exactly the fields named above' \
  && ok "AC(13.79): refusal footer directs a targeted resubmit" \
  || err "refusal footer missing"
# The contract itself is unchanged: the good plan still passes as-is.
pass 1 "$GOOD" && ok "AC(13.79): ratifiability contract unchanged (good plan still passes)" \
  || err "contract changed — previously valid plan now refused"

# --- the cap's operand is the STRUCTURE's slots, not a framework's (#983) ----
# The framework-anchored operand was undefined on a `bespoke` structure, which
# #911's own instrument expects to be the common case. These assert the bespoke
# path works with NO framework vocabulary anywhere in play.
REC=$(mktemp); RECEMPTY=$(mktemp); RECNONE=$(mktemp)
trap 'rm -f "$REC" "$RECEMPTY" "$RECNONE"' EXIT
printf '%s' '{"arc":"a","visual_slots":["overview diagram"]}' > "$REC"
printf '%s' '{"arc":"a","visual_slots":[]}'                   > "$RECEMPTY"
printf '%s' '{"arc":"a"}'                                     > "$RECNONE"
printf '%s' "$GOOD" | python3 "$V" --plan-record "$REC" 2>/dev/null | grep -q '"cap": 3' \
  && ok "a one-slot structure caps at 3 via --plan-record" \
  || err "--plan-record did not derive the cap from visual_slots"
printf '%s' "$ZERO" | python3 "$V" --plan-record "$RECEMPTY" 2>/dev/null | grep -q '"cap": 2' \
  && ok "a BESPOKE structure declaring no slots caps at 2 — defined, not absent" \
  || err "a zero-slot structure did not produce a defined cap"
printf '%s' "$ZERO" | python3 "$V" --plan-record "$RECNONE" >/dev/null 2>&1 \
  && err "a plan record with no visual_slots was ACCEPTED — the cap had no operand" \
  || ok "a record declaring no visual_slots is refused, never defaulted"
printf '%s' "$ZERO" | python3 "$V" >/dev/null 2>&1 \
  && err "no operand at all was ACCEPTED — a guessed cap is the #983 defect" \
  || ok "no --slot-count and no --plan-record refuses rather than defaulting"

# --- the visual-set track runs BESIDE the judging (Story 20.164, #1248) ------
# Independence is the claim, and it is directional: the plan depends on the
# draft and the argument plan, the judging on neither. Both are LLM steps, so
# the concurrency binds as prose; what a check can hold is that the claim is
# stated where the track is described, that the join is named, and that the
# OWNER-paced half is not swept into the win.
FO="skills/draft-article/stages/fan-out.md"
printf '%s' "$sec" | grep -qi 'beside the provenance judging\|runs beside the judging' \
  && ok "the visual-set section states it runs beside the judging" \
  || err "stage3.md's visual-set section does not state the concurrency (#1248)"
grep -qi 'join at the quality gate\|They \*\*join at the quality gate' "$FO" \
  && ok "fan-out names the quality gate as the join" \
  || err "fan-out.md does not name the join point"
grep -qi 'owner-paced half of the visual set does not speed up\|owner decisions' "$FO" \
  && ok "fan-out excludes the visual set's owner-paced half from the win" \
  || err "fan-out.md claims the owner-paced visual steps speed up"
# The join precondition is contract wherever in the skill's file set it sits
# (#1322/#1325), so the assertion reads the set rather than one file.
grep -rqi 'Join first, then' skills/draft-article/ \
  && ok "the skill carries the join precondition (join first, then gate)" \
  || err "the skill does not state the join point"

if [ "$fail" -eq 0 ]; then
  printf '\nAll visual-set-plan checks passed.\n'; exit 0
else
  printf '\nvisual-set-plan checks FAILED.\n' >&2; exit 1
fi
