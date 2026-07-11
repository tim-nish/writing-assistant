#!/usr/bin/env sh
# check-stage2-recommended.sh — verify recommended answers with dispositions
# (Story 10.3). POSIX shell + stdlib Python.
#
# Covers: approve adopts the recommendation verbatim and inherits its source
# pointers as SOURCED provenance (AC2); modify/replace are INTERVIEW-sourced
# owner judgment carrying no pointers (AC3); skip records only the disposition,
# deferring the effect to the framework slot (AC4); an open question takes a
# bullet (answered → interview) (AC5); and the SKILL documents the four
# dispositions with effect-stating labels under the extended contract (AC1).

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
ans() { python3 "$DP" answer "$@"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# AC2 — approve: adopted verbatim + inherits pointers + SOURCED provenance.
out=$(ans --id q2 --disposition approved --text "Throughput rose 2x" --pointer "bench/results.md:42@a1b2c3d")
[ "$(printf '%s' "$out" | jget 'd["provenance"]')" = "sourced" ] && ok "approved answer is sourced provenance" || err "approved not sourced"
[ "$(printf '%s' "$out" | jget 'd["answer"]')" = "Throughput rose 2x" ] && ok "approved answer kept verbatim" || err "approved text altered"
printf '%s' "$out" | jget 'len(d["pointers"])>=1' | grep -q True && ok "approved answer inherits source pointers" || err "approved lost pointers"
# approve WITHOUT a pointer is rejected (it must ground like a fact-sheet entry).
ans --id q2 --disposition approved --text "x" >/dev/null 2>&1 && err "approve without pointer was accepted" || ok "approve without a pointer is rejected"

# AC3 — modify / replace: INTERVIEW-sourced owner judgment, no pointers.
[ "$(ans --id q1 --disposition modified --text "what surprised me" | jget 'd["provenance"]')" = "interview" ] \
  && ok "modified answer is interview-sourced" || err "modified not interview"
[ "$(ans --id q1 --disposition replaced --text "my own take" | jget 'd["provenance"]')" = "interview" ] \
  && ok "replaced answer is interview-sourced" || err "replaced not interview"
# a modify/replace carrying source pointers is rejected (owner judgment isn't source-pointed).
ans --id q1 --disposition modified --text "x" --pointer "a:1@sha" >/dev/null 2>&1 \
  && err "modified with a pointer was accepted" || ok "modified with a source pointer is rejected"

# AC4 — skip: records ONLY the disposition; no answer, effect deferred to slot.
out=$(ans --id q3 --disposition skipped)
[ "$(printf '%s' "$out" | jget 'd["disposition"]')" = "skipped" ] && ok "skip records the disposition" || err "skip disposition missing"
printf '%s' "$out" | jget 'd["answer"] is None and d["provenance"] is None and d["pointers"]==[]' | grep -q True \
  && ok "skip captures no answer/provenance (effect deferred to the slot, Story 10.5)" || err "skip captured more than the disposition"
# a skip carrying text is rejected (the engine records intent only).
ans --id q3 --disposition skipped --text "oops" >/dev/null 2>&1 && err "skip with text was accepted" || ok "skip with text is rejected"

# AC5 — open question: bullet free-text → answered → interview.
[ "$(ans --id q5 --disposition answered --text "for SREs; page them" | jget 'd["provenance"]')" = "interview" ] \
  && ok "open-question bullet answer is interview-sourced" || err "answered not interview"

# invalid disposition rejected.
ans --id q1 --disposition bogus --text x >/dev/null 2>&1 && err "invalid disposition accepted" || ok "invalid disposition rejected"

# AC1 — SKILL documents the four dispositions + recommended default + records via the answer command.
for term in Approve Modify Replace Skip "default choice" "draft-pipeline.py answer"; do
  grep -qi -- "$term" "$SKILL" || err "SKILL missing disposition contract term: $term"
done
grep -qi 'recommended' "$SKILL" && ok "SKILL documents recommended answers + dispositions" || err "SKILL missing recommended-answer contract"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-2 recommended-answer checks passed.\n'; exit 0
else
  printf '\nstage-2 recommended-answer checks FAILED.\n' >&2; exit 1
fi
