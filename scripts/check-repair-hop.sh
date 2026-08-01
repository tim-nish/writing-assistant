#!/usr/bin/env sh
# parallel-safe
# check-repair-hop.sh — verify the bounded missing-input repair hop (Story
# 13.63, SPEC-article-draft-pipeline missing-input repair route). POSIX shell.
#
# Covers: an `examine <claim>` remediation runs one bounded examination and
# resumes the fill (harvest is retired, #1182/Story 20.147 — the legacy
# `re-harvest` spelling maps to the same route, disclosed); an `ask <question>` remediation
# re-enters the interview with exactly one owner-facing question recorded as
# owner judgment; a malformed remediation is refused; and the SKILL documents
# the hop as the only backward edge, counted against the two-cycle bound.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
SKILL="skills/draft-article/stages/gate.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

# examine form: one bounded examination for the named claim, then the fill
# resumes — never a stage re-entry (#1182).
out=$(python3 "$DP" repair-hop --upstream "examine the bench results ground the claimed speedup" 2>/dev/null)
[ "$(printf '%s' "$out" | jget 'd["action"]')" = "examine" ] && ok "examine -> action examine" || err "examine action wrong"
[ "$(printf '%s' "$out" | jget 'd["next_stage"]')" = "fill" ] && ok "examine -> the fill resumes (no stage re-entry)" || err "examine next_stage wrong"
[ "$(printf '%s' "$out" | jget 'd["claim"]')" = "the bench results ground the claimed speedup" ] && ok "examine carries the named claim" || err "examine claim wrong"
printf '%s' "$out" | jget '"recorded at the read" in d["note"] and "never" in d["note"] and "SOURCE" in d["note"]' | grep -q True \
  && ok "examine note states at-the-read pin + no-policy-SOURCE invariants" || err "examine invariants not stated"
# The legacy spelling maps to the same route, with the mapping disclosed.
lout=$(python3 "$DP" repair-hop --upstream "re-harvest bench/results.md" 2>/dev/null)
[ "$(printf '%s' "$lout" | jget 'd["action"]')" = "examine" ] && ok "legacy re-harvest maps to the examine route" || err "legacy re-harvest unmapped"
printf '%s' "$lout" | jget '"legacy_remediation" in d' | grep -q True \
  && ok "the legacy mapping is disclosed on the output" || err "legacy mapping silent"

# ask form: re-enters interview, exactly one owner-facing question.
out=$(python3 "$DP" repair-hop --upstream "ask which decision this cost you the most" 2>/dev/null)
[ "$(printf '%s' "$out" | jget 'd["action"]')" = "elicit" ] && ok "ask -> action elicit" || err "ask action wrong"
[ "$(printf '%s' "$out" | jget 'd["next_stage"]')" = "interview" ] && ok "ask -> re-enters interview" || err "ask next_stage wrong"
printf '%s' "$out" | jget 'd["question"]["from_repair_hop"] is True' | grep -q True \
  && ok "ask emits one owner-facing question tagged from_repair_hop" || err "ask question not tagged"
printf '%s' "$out" | jget '"owner judgment" in d["note"] and "never a SOURCE" in d["note"]' | grep -q True \
  && ok "ask note states owner-judgment provenance, never a SOURCE" || err "ask provenance not stated"
# the emitted question ends with a single '?'
printf '%s' "$out" | jget 'd["question"]["text"].endswith("?") and not d["question"]["text"].endswith("??")' | grep -q True \
  && ok "ask question is well-formed (single trailing ?)" || err "ask question malformed"

# The Upstream: prefix is tolerated (findings carry it verbatim).
python3 "$DP" repair-hop --upstream "Upstream: examine specs/qa.md" >/dev/null 2>&1 \
  && ok "the verbatim 'Upstream:' prefix is accepted" || err "Upstream: prefix rejected"

# A malformed remediation (neither examine nor ask) is refused.
python3 "$DP" repair-hop --upstream "go find more evidence somewhere" >/dev/null 2>&1 \
  && err "malformed remediation accepted" || ok "malformed remediation refused (exit non-zero)"

# SKILL wiring: the hop is documented as the only backward edge, two-cycle bound.
sec=$(awk '/Missing-input repair hop/{f=1} f && /^## /{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "SKILL documents the missing-input repair hop" || err "SKILL hop section missing"
printf '%s' "$sec" | grep -q 'repair-hop' && ok "SKILL wires in the repair-hop command" || err "repair-hop command not wired"
printf '%s' "$sec" | grep -qi 'only.*backward edge' && ok "SKILL states it is the only backward edge" || err "only-backward-edge not stated"
printf '%s' "$sec" | grep -qi 'same two-cycle bound' && ok "SKILL states it counts against the two-cycle bound" || err "two-cycle bound not stated"
printf '%s' "$sec" | tr '\n' ' ' | grep -qi 'publish[[:space:]]*blocker' && ok "SKILL states an unrepaired gap becomes a publish blocker" || err "publish-blocker not stated"

if [ "$fail" -eq 0 ]; then
  printf '\nAll repair-hop checks passed.\n'; exit 0
else
  printf '\nrepair-hop checks FAILED.\n' >&2; exit 1
fi
