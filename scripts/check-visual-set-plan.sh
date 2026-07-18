#!/usr/bin/env sh
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
SKILL="skills/draft-article/SKILL.md"
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
reason 1 "$NOROLE" | grep -q 'resolve exactly the fields named above' \
  && ok "AC(13.79): refusal footer directs a targeted resubmit" \
  || err "refusal footer missing"
# The contract itself is unchanged: the good plan still passes as-is.
pass 1 "$GOOD" && ok "AC(13.79): ratifiability contract unchanged (good plan still passes)" \
  || err "contract changed — previously valid plan now refused"

if [ "$fail" -eq 0 ]; then
  printf '\nAll visual-set-plan checks passed.\n'; exit 0
else
  printf '\nvisual-set-plan checks FAILED.\n' >&2; exit 1
fi
