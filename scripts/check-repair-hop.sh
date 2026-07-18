#!/usr/bin/env sh
# check-repair-hop.sh — verify the bounded missing-input repair hop (Story
# 13.63, SPEC-article-draft-pipeline missing-input repair route). POSIX shell.
#
# Covers: a `re-harvest <target>` remediation re-enters harvest scoped to the
# target with pin/policy invariants stated; an `ask <question>` remediation
# re-enters the interview with exactly one owner-facing question recorded as
# owner judgment; a malformed remediation is refused; and the SKILL documents
# the hop as the only backward edge, counted against the two-cycle bound.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

# re-harvest form: re-enters harvest, scoped to the target.
out=$(python3 "$DP" repair-hop --upstream "re-harvest bench/results.md" 2>/dev/null)
[ "$(printf '%s' "$out" | jget 'd["action"]')" = "re-harvest" ] && ok "re-harvest -> action re-harvest" || err "re-harvest action wrong"
[ "$(printf '%s' "$out" | jget 'd["next_stage"]')" = "harvest" ] && ok "re-harvest -> re-enters harvest" || err "re-harvest next_stage wrong"
[ "$(printf '%s' "$out" | jget 'd["scope"]')" = "bench/results.md" ] && ok "re-harvest scoped to the named target" || err "re-harvest scope wrong"
printf '%s' "$out" | jget '"pinned like any Stage-1 fact" in d["note"] and "never becomes a SOURCE" in d["note"]' | grep -q True \
  && ok "re-harvest note states pin + no-policy-SOURCE invariants" || err "re-harvest invariants not stated"

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
python3 "$DP" repair-hop --upstream "Upstream: re-harvest specs/qa.md" >/dev/null 2>&1 \
  && ok "the verbatim 'Upstream:' prefix is accepted" || err "Upstream: prefix rejected"

# A malformed remediation (neither re-harvest nor ask) is refused.
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
