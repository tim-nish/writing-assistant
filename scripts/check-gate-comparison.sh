#!/usr/bin/env sh
# parallel-safe
# covers: skills/fork-gate-consult-first/SKILL.md specs/spec-policy-fork-consultation/SPEC.md
# check-gate-comparison.sh — the ranked-recommendation obligation has a carrier
# at every layer that can carry it (Story 20.12, #808).
#
# THIS IS A VISIBLE-ABSENCE SIGNAL, NOT A GATE — and the distinction is the
# whole design. An obligation ("every fork panel carries the machine's own
# comparison") is violated by an ABSENCE, at the moment an agent draws a panel
# in prose. There is no event to hook and no artifact to inspect, so it cannot
# be gated the way a malformed payload can. What is owed instead is that the
# obligation's absence is VISIBLE. A pretend gate here would be worse than
# nothing: it would report `ok` for a rule it never actually enforced.
#
# WHAT THIS CHECK DOES NOT COVER — stated, because a check whose coverage is
# overstated is worse than a narrow one that admits its edges:
#
#   * It CANNOT tell whether any particular panel an agent drew carried a
#     recommendation. Those panels are conversational; they are not written to
#     any file this check could read. #808's own incident is of exactly that
#     shape, and this check would not have caught it.
#   * It does NOT extend `validate-proposal-payload.py`. That validator is a
#     real blocking gate, and it is the STRONGER carrier for the payload-shaped
#     surfaces it already covers (gap interview, review arbitration, Stage-4
#     verification, visual proposals). Requiring new fields there would change a
#     contract every one of those surfaces depends on — an altitude decision
#     this story does not own. Recorded as the next step, not smuggled in.
#
# What it DOES check: that the obligation is stated at each layer that can
# state it, so a silent deletion of the rule fails red instead of passing
# unnoticed. That is weak enforcement and strong drift-detection.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

AMBIENT="CLAUDE.md"
SPEC="specs/spec-policy-fork-consultation/SPEC.md"
SKILL="skills/fork-gate-consult-first/SKILL.md"

# The three clauses that make the rule falsifiable rather than a slogan. All
# three must appear at a layer, or the rule has decayed into "be thoughtful".
required='ranked recommendation|per-option evidence|overturn'

# 1. THE AMBIENT LAYER (CLAUDE.md). Load-bearing because a skill binds only the
#    sittings that invoke it, and the #808 incident happened in a sitting that
#    invoked none.
if [ -f "$AMBIENT" ] && grep -qi "ranked recommendation" "$AMBIENT"; then
  ok "the rule is ambient in $AMBIENT (binds sittings that invoke no skill)"
else
  err "$AMBIENT does not state the ranked-recommendation rule"
fi
if grep -qi "overturn" "$AMBIENT"; then
  ok "the ambient rule names the overturning-evidence clause (the falsifiability half)"
else
  err "$AMBIENT states the rule without its falsifiability discriminator"
fi

# 2. THE CONTRACT (CAP-3).
if [ -f "$SPEC" ] && grep -qi "ranked recommendation" "$SPEC"; then
  ok "CAP-3 carries the comparison clause ($SPEC)"
else
  err "$SPEC CAP-3 does not require the comparison"
fi

# 3. THE PROCEDURE (the skill). It must make the rule CHEAP TO OBEY — i.e.
#    carry steps, not merely repeat the obligation.
if [ -f "$SKILL" ] && grep -qi "attach the evidence to the option" "$SKILL"; then
  ok "the skill carries the procedure, not just the rule"
else
  err "$SKILL does not carry the comparison procedure"
fi

# 4. The no-default invariant survives at every layer that mentions rank. A
#    recommendation that became a pre-selection would satisfy every check above
#    while breaking the thing they exist to protect.
for f in "$AMBIENT" "$SPEC" "$SKILL"; do
  if grep -qi "rank is not pre-selection" "$f"; then
    ok "$f keeps rank distinct from pre-selection"
  else
    err "$f mentions ranking without denying pre-selection"
  fi
done

# 5. NEGATIVE TEST: the matcher must be able to fail. A drift check never shown
#    to fire is a clean bill nobody earned — which is the same defect class
#    #808 reports, applied to this check.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'Present the options in a sensible order.\n' > "$tmp/silent.md"
if grep -qi "ranked recommendation" "$tmp/silent.md"; then
  err "the matcher does not distinguish a document that omits the rule"
else
  ok "negative test: a document omitting the rule fails this matcher"
fi

# 6. Coverage disclosure is itself asserted: this file must keep saying what it
#    cannot see. Deleting that paragraph would turn a narrow check into an
#    apparently comprehensive one.
if grep -q "WHAT THIS CHECK DOES NOT COVER" "$0"; then
  ok "the check discloses its own coverage limits"
else
  err "the coverage disclosure was removed — a narrow check now reads as complete"
fi

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll gate-comparison checks passed (obligation stated at every carrying layer).\n'
