#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# check-stage2-triage.sh — verify the three-outcome triage over harvest output
# (Story 10.2). POSIX shell + stdlib Python.
#
# Covers: every candidate question is triaged into exactly one of
# suppressed / recommended / open (AC1); a question the fact sheet fully covers
# is suppressed and never presented (AC2); a NEEDS-OWNER re-raise is always
# recommended (AC3); triage reads only the harvest output carried in state — no
# source read path (AC4/NFR11); and the SKILL documents the three outcomes.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/stages/stage2.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
iv() { printf '%s' "$1" | python3 "$DP" interview --framework "$2"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Every candidate question carries exactly one of the three outcomes (AC1).
out=$(iv '{"fact_sheet":[{"claim":"written for backend engineers"}],"needs_owner":[{"topic":"warning","candidate":"do not use on TPUs"}]}' F3)
printf '%s' "$out" | jget 'all(t["outcome"] in ("suppressed","recommended","open") for t in d["triage"])' | grep -q True \
  && ok "each triaged question has a valid outcome" || err "an outcome is missing/invalid"
printf '%s' "$out" | jget 'sorted(t["rationale"] for t in d["triage"]) == ["evidence-fallback","needs-owner-reraise"]' | grep -q True \
  && ok "triage classifies the full candidate set (not just survivors)" || err "triage does not cover all candidates"

# 2. NOTHING THE MATERIAL DID NOT RAISE IS EVER ASKED (Story 20.131, #1147).
#    This block used to assert that a fact-sheet-covered BANK question lands
#    `suppressed`. There is no bank: a candidate exists only because harvest
#    raised it, so a covered-and-unraised topic cannot be asked — which is the
#    same property, now held by construction rather than by a de-dup pass. The
#    assertion is kept and re-pointed, because the property is what mattered.
cov='{"fact_sheet":[{"claim":"this guide is written for backend engineers"}],"needs_owner":[]}'
# The evidence fallback is the ONE candidate the material can raise by absence
# (harvest produced no `number`/`result` fact), so it is expected here; what
# must not appear is anything a bank would have supplied.
iv "$cov" F3 | jget 'all(t["rationale"] == "evidence-fallback" for t in d["triage"])' | grep -q True \
  && ok "a covered topic the material did not raise is never a candidate" \
  || err "a question appeared that no NEEDS-OWNER item raised"
# The mandated tier is not material-raised BY DEFINITION and sits outside the
# capped set, so its members are listed here rather than making this assertion
# fail every time the tier gains one (Story 20.172, #1283 added `audience`).
# The property under test is unchanged: no BANK-supplied question may appear.
iv "$cov" F3 | jget 'all(q["id"] in ("q8", "depth", "audience") for q in d["questions"])' | grep -q True \
  && ok "...and only the material-raised fallback and the mandated tier reach the owner" \
  || err "an unraised question was presented"

# 3. A NEEDS-OWNER re-raise is ALWAYS recommended — even when the fact sheet also
#    covers the topic (re-raise wins over suppression) (AC3).
rr='{"fact_sheet":[{"claim":"a known caveat: do not use on TPUs"}],"needs_owner":[{"topic":"warning","candidate":"do not use on TPUs"}]}'
iv "$rr" F3 | jget '[t["outcome"] for t in d["triage"] if t["id"]=="g-warning"][0]' | grep -q recommended \
  && ok "NEEDS-OWNER re-raise is recommended (wins over coverage)" || err "re-raise not recommended"
iv "$rr" F3 | jget '[t.get("rationale") for t in d["triage"] if t["id"]=="g-warning"][0]' | grep -q needs-owner-reraise \
  && ok "re-raise records rationale=needs-owner-reraise" || err "re-raise rationale wrong"
iv "$rr" F3 | jget '[bool(t.get("grounding")) for t in d["triage"] if t["id"]=="g-warning"][0]' | grep -q True \
  && ok "recommended re-raise carries grounding pointers" || err "grounding missing on re-raise"

# 3b. The new tradeoff/audience TOPICs (#145) re-raise their interview questions
#     (q4 tradeoff, q5 audience) — previously they could never reach recommendation.
tr='{"fact_sheet":[],"needs_owner":[{"topic":"tradeoff","candidate":"we gave up incremental builds"}]}'
iv "$tr" F3 | jget '[t["outcome"] for t in d["triage"] if t["id"]=="g-tradeoff"][0]' | grep -q recommended \
  && ok "NEEDS-OWNER topic=tradeoff re-raises q4 (#145)" || err "tradeoff did not re-raise q4"
au='{"fact_sheet":[],"needs_owner":[{"topic":"audience","candidate":"backend SREs specifically"}]}'
iv "$au" F3 | jget '[t["outcome"] for t in d["triage"] if t["id"]=="g-audience"][0]' | grep -q recommended \
  && ok "NEEDS-OWNER topic=audience re-raises q5 (#145)" || err "audience did not re-raise q5"

# 4. A question with neither coverage nor a re-raise is open.
op='{"fact_sheet":[],"needs_owner":[]}'
iv "$op" F1 | jget 'all(t["outcome"]=="open" for t in d["triage"])' | grep -q True \
  && ok "uncovered, non-re-raised questions are open" || err "expected all-open triage"

# 5. Triage reads ONLY harvest output: it never opens a source file. Run from a
#    scratch dir with a decoy file whose content would flip a verdict if read.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
printf 'written for backend engineers\n' > "$work/SOURCE.md"
# The decoy would create an `audience` candidate if triage read it. Under the
# material-driven model an empty harvest yields no topic candidate at all, so
# the property is asserted as the decoy's ABSENCE from the candidate set.
( cd "$work" && printf '%s' '{"fact_sheet":[],"needs_owner":[]}' | python3 "$DP" interview --framework F3 ) \
  | jget 'not any("audience" in t["id"] for t in d["triage"])' | grep -q True \
  && ok "triage ignores on-disk sources (no read beyond harvest output)" || err "triage appears to read source files"

# 6. SKILL documents the three-outcome triage.
for term in suppressed recommended open; do
  grep -qi "$term" "$SKILL" || err "SKILL missing triage outcome: $term"
done
grep -qi 'three-outcome triage' "$SKILL" && ok "SKILL documents three-outcome triage" || err "SKILL does not name the triage"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-2 triage checks passed.\n'; exit 0
else
  printf '\nstage-2 triage checks FAILED.\n' >&2; exit 1
fi
