#!/usr/bin/env sh
# parallel-safe
# tier: inner — a grep over four skill files plus a handful of sub-second
#   validator invocations; no pipeline run, no network.
# covers: skills/review-article/** scripts/validate-review-findings.py
# removal-signal: the style contract stops being the Reviewer's only style
#   authority — either the corpus-level drift instrument is built (its trigger
#   is recorded at scripts/style-contract.py: the owner reads two shipped
#   articles as written by different people) and re-homes the dimension, or
#   SPEC-writing-assistant retires the one-dimension rule. Removed with
#   whichever lands first.
# check-review-style-conformance.sh — the Reviewer MEASURES conformance to the
# named style contract and never CARRIES style (Story 20.140, #1202; umbrella
# #1191, the 2026-08-01 amendment).
#
# The defect this guards is not a missing feature but an indistinguishability:
# a preference delivered as a review finding reads to the owner exactly like a
# contract requirement, and becomes one by repetition. So the assertions below
# are as much about what the dimension may NOT say as about its presence —
# exactly ONE dimension, a mandatory clause citation, no finding against the
# deliberately uninstrumented syntax profile, no judged duplicate of the
# mechanical coinage lint, and a tier of its own that never blocks.
#
# POSIX shell + stdlib Python, like every check-*.sh sibling.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DIM="skills/review-article/style-conformance.md"
SKILL="skills/review-article/SKILL.md"
PASSES="skills/review-article/phases/passes.md"
ARB="skills/review-article/phases/arbitration.md"
PROMPTS="skills/review-article/review-prompts.md"
V="scripts/validate-review-findings.py"
READER="scripts/style-contract.py"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

for f in "$DIM" "$SKILL" "$PASSES" "$ARB" "$PROMPTS" "$V" "$READER"; do
  [ -f "$f" ] || err "missing $f — wrong root?"
done
[ "$fail" -eq 0 ] || { printf '\nstyle-conformance checks FAILED.\n' >&2; exit 1; }

# --- 1. EXACTLY ONE dimension, and it consumes the shipped reader ------------

grep -qi 'exactly one dimension' "$DIM" \
  && ok "the companion declares EXACTLY ONE dimension" \
  || err "$DIM does not declare that exactly one dimension is added (AC1)"

grep -qF 'style-contract.py read' "$DIM" \
  && ok "the dimension reads the contract through the single reader" \
  || err "$DIM does not consume scripts/style-contract.py — the contract has"\
" exactly one reader and review must not open the artifact by another path"

# The Reviewer never writes the contract: the plugin's only interaction is a
# read (Story 20.139 asserts the absence of a writer; this asserts review does
# not become one).
if grep -Eqi '(style-contract\.py (write|init|create))|(creates? the (style )?contract)' "$DIM"; then
  err "$DIM implies review writes or creates the contract — it is owner-authored"\
" and read-only here"
else
  ok "the dimension never writes, creates, or offers to create the contract"
fi

# --- 2. the taste prohibition is carried WITH ITS REASON (AC4) ---------------
# Asserted in the pass's own text, not merely in a spec: the rule is broken at
# the moment an agent writes a style finding.

grep -qi 'indistinguishable' "$DIM" && grep -qi 'by repetition' "$DIM" \
  && ok "the taste prohibition carries its reason (indistinguishable … becomes one by repetition)" \
  || err "$DIM asserts the taste prohibition without its reason — a bare"\
" prohibition is the one a reviewer talks itself past (AC4)"

grep -qi 'not emitted' "$DIM" \
  && ok "an uncitable finding is NOT EMITTED (never downgraded to a nit)" \
  || err "$DIM does not state that an uncitable finding is not emitted (AC2)"

# --- 3. the measured set, and the two exclusions (AC5, AC6) ------------------

grep -qF 'STRUCTURAL VOICE' "$DIM" && grep -qF 'REGISTER' "$DIM" \
  && ok "the dimension measures REGISTER and STRUCTURAL VOICE" \
  || err "$DIM does not name the two judgment sections it measures"

grep -qi 'duplicate a mechanical check' "$DIM" \
  && ok "LEXICON is excluded, and the reason (no judged duplicate of a mechanical check) is carried" \
  || err "$DIM does not exclude LEXICON with its reason (AC5)"

grep -qi 'back door' "$DIM" \
  && ok "SYNTAX PROFILE emits NO finding, with the back-door reason carried" \
  || err "$DIM does not carry the no-instrument reason for SYNTAX PROFILE (AC6)"

# --- 4. the no-contract state is STATED, and is distinct from an unauthored
#        clause (AC7 and its neighbour) --------------------------------------

grep -qi 'DID NOT RUN' "$DIM" \
  && ok "with no contract the dimension STATES that it did not run" \
  || err "$DIM has no did-not-run statement for an absent contract (AC7)"

grep -qi 'never silently skip' "$DIM" \
  && ok "the absent case is never a silent skip" \
  || err "$DIM does not forbid a silent skip (AC7)"

grep -qi 'NOT YET AUTHORED' "$DIM" \
  && ok "an authored-but-empty section has its own state" \
  || err "$DIM conflates an unauthored clause with an absent contract — the"\
" contract ships structure ahead of content, so this is today's state"

grep -qi 'is not an absent contract' "$DIM" \
  && ok "the two states are explicitly distinguished" \
  || err "$DIM does not say that an authored-but-empty section is not an"\
" absent contract"

# --- 5. findings-only, owner sole arbiter, no rewrites (AC3) -----------------

grep -qi 'no rewrites' "$DIM" \
  && ok "the dimension emits findings only — no rewrites" \
  || err "$DIM does not restate the no-rewrites half of the review contract (AC3)"

grep -qi 'reject-only' "$ARB" \
  && ok "arbitration is unchanged (reject-only, owner sole arbiter)" \
  || err "$ARB lost the reject-only arbitration contract"

# --- 6. TIERING: its own class, outside blocker/should/nit, never blocking ---
# Resolved at the gate as a recorded consult-MISS; the three-tier vocabulary is
# untouched.

grep -qi 'never block' "$DIM" \
  && ok "conformance findings never block" \
  || err "$DIM does not state that conformance findings never block"

grep -qi 'different kinds, not different severities' "$DIM" \
  && ok "the tiering grounds are carried (different kinds, not severities)" \
  || err "$DIM does not carry the recorded grounds for the separate class"

grep -qi 'OUTSIDE this table' "$PROMPTS" \
  && ok "the severity criteria table declares conformance outside itself" \
  || err "$PROMPTS does not place conformance outside the severity table"

# The three-tier vocabulary must be untouched: the table still carries exactly
# the three rows it had.
rows=$(grep -c '^| \*\*\(blocker\|should\|nit\)\*\*' "$PROMPTS" || true)
if [ "$rows" = "3" ]; then
  ok "the severity table still carries exactly blocker/should/nit"
else
  err "the severity table has $rows severity rows, expected 3 — the existing"\
" vocabulary is untouched by this story"
fi

if grep -Eq '^\| \*\*(blocker|should|nit)\*\*.*conformance' "$PROMPTS"; then
  err "a severity row admits the conformance criterion — folding style into"\
" blocker/should/nit is the exact indistinguishability the prohibition prevents"
else
  ok "no severity row admits conformance (the classes stay disjoint)"
fi

grep -qi 'never blocker-eligible' "$ARB" \
  && ok "arbitration states conformance is never blocker-eligible" \
  || err "$ARB does not exclude conformance from blocker eligibility"

# --- 7. the pass phase carries the item and POINTS at the contract ----------

grep -qi 'Style-contract conformance' "$PASSES" \
  && ok "the prose pass carries the style-conformance item" \
  || err "$PASSES does not carry the dimension"

grep -qF 'style-conformance.md' "$PASSES" && grep -qF 'style-conformance.md' "$SKILL" \
  && ok "the pass file and the dispatcher POINT at the contract rather than restating it" \
  || err "the dimension's contract is not pointed at from $PASSES and $SKILL"

# Exactly one dimension means exactly one addition to the prose rubric: item 8,
# and no item 9.
if grep -q '^9\. ' "$PASSES"; then
  err "$PASSES grew a ninth prose rubric item — the story adds EXACTLY ONE"\
" dimension, never a family of style findings (AC1)"
else
  ok "the prose rubric gained exactly one item (no family of style findings)"
fi

# --- 8. AC2 IS MECHANICAL: the validator rejects an uncitable finding -------

python3 -c "import py_compile; py_compile.compile('$root/$V', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

pass() { printf '%s\n' "$1" | python3 "$V" >/dev/null 2>&1 && ok "$2" || err "$2 (conforming finding rejected)"; }
rej()  { printf '%s\n' "$1" | python3 "$V" 2>&1 >/dev/null; }

GOOD='- [conformance] draft.md:41: the opening assumes the reader has already met the seam. Contract: style contract §REGISTER — "written for an engineer who has never seen this repository". Fix: gloss the seam at first use.'
pass "$GOOD" "a cited conformance finding passes"

GOOD2='- [conformance] draft.md:88: the section buries its claim under three paragraphs of setup. Contract: style contract §STRUCTURAL VOICE — "claim-first paragraphs, so skimming survives". Fix: lead the section with its claim.'
pass "$GOOD2" "a STRUCTURAL VOICE conformance finding passes"

# C1 — taste: a style finding with no clause citation.
C1='- [conformance] draft.md:12: the tone here feels a little flat for my taste. Fix: liven it up.'
rej "$C1" | grep -q 'C1:' && ok "C1: an uncitable conformance finding is REJECTED (AC2 is mechanical)" \
  || err "C1 not caught — an uncitable finding would reach arbitration as taste"

# C1 — a citation naming a section that is not one of the two measurable ones.
C1B='- [conformance] draft.md:12: no exemplar is imitated. Contract: style contract §EXEMPLARS — "the slots are declared and empty". Fix: pick one.'
rej "$C1B" | grep -q 'C1:' && ok "C1: a citation outside REGISTER/STRUCTURAL VOICE is rejected" \
  || err "a non-measurable section citation was accepted"

# C2 — the syntax profile carries no instrument (AC6).
C2='- [conformance] draft.md:20: average sentence length is 34 words. Contract: style contract §SYNTAX PROFILE — "short sentences". Fix: split them.'
rej "$C2" | grep -q 'C2:' && ok "C2: a SYNTAX PROFILE finding is REJECTED (no instrument, by ratified decision)" \
  || err "C2 not caught — a syntax instrument would arrive through the back door"

# C2 — the lexicon is already mechanical (AC5).
C2B='- [conformance] draft.md:31: "seam" is coined without a gloss. Contract: style contract §LEXICON — "coin with definition". Fix: gloss it.'
rej "$C2B" | grep -q 'C2:' && ok "C2: a LEXICON finding is REJECTED (the coinage lint already carries it)" \
  || err "C2 not caught for LEXICON — the Reviewer would duplicate a mechanical check as a judgment"

# C3 — a conformance miss never enters the blocking vocabulary.
C3='- [blocker] draft.md:41: the register is wrong. Why blocker: quality-rubric dimension violation. Fix: rewrite for the declared reader (style-contract.md §REGISTER).'
rej "$C3" | grep -q 'C3:' && ok "C3: a blocker citing the style contract is REJECTED (conformance never blocks)" \
  || err "C3 not caught — a style finding wearing a blocker tag is indistinguishable from a correctness one"

# The pre-existing classes are untouched by the addition.
WP='- [should] Section 2, para 3: the transition is abrupt. Why should: non-rubric structure/prose. Fix: add a bridging sentence.'
pass "$WP" "an ordinary writing-problem finding still passes (existing classes untouched)"
MI='- [blocker] [missing-input] Section 3: the central claim has no measured result. Why blocker: quality-rubric dimension violation. Upstream: re-harvest bench/results.md'
pass "$MI" "a missing-input finding still passes"

# --- 9. the reader's three states are the ones the dimension branches on -----
# Contract-side truth, not restated prose: the shipped reader's own absence
# path and its NOT YET AUTHORED rendering are what states (a) and (b) rest on.

grep -qF 'NOT YET AUTHORED' "$READER" \
  && ok "the shipped reader really renders NOT YET AUTHORED (state (b) has a source)" \
  || err "$READER no longer renders an unauthored section — state (b) would be"\
" inferred rather than read"

grep -qi 'no style contract at' "$READER" \
  && ok "the shipped reader really states the absence (state (a) has a source)" \
  || err "$READER no longer states the absence — state (a) would be inferred"

if [ "$fail" -eq 0 ]; then
  printf '\nAll review style-conformance checks passed.\n'; exit 0
else
  printf '\nreview style-conformance checks FAILED.\n' >&2; exit 1
fi
