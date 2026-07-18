#!/usr/bin/env sh
# check-missing-input-cap.sh — verify the missing-input repair-hop cycle cap
# and publish-blocker (Story 13.64, SPEC-article-draft-pipeline). POSIX shell.
#
# Covers: a within-budget hop re-enters and reports the incremented cycle; a
# hop at the two-cycle cap becomes a publish blocker (no third hop,
# publishable:false); the cap is shared (a cycle count from rewrites/gate
# revisions gates the hop); and the SKILL documents the cap + blocker.

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

# Within budget (cycle 0): a real hop, incremented cycle reported.
out=$(python3 "$DP" repair-hop --upstream "re-harvest bench/results.md" --cycle 0 2>/dev/null)
[ "$(printf '%s' "$out" | jget 'd["action"]')" = "re-harvest" ] && ok "cycle 0: within budget, a real hop is emitted" || err "cycle 0 not a hop"
[ "$(printf '%s' "$out" | jget 'd["cycle"]')" = "1" ] && ok "cycle 0 -> hop reports incremented cycle 1" || err "cycle not incremented"

# Within budget (cycle 1): still a hop (this is the second and last allowed).
out=$(python3 "$DP" repair-hop --upstream "ask what result would convince a skeptic" --cycle 1 2>/dev/null)
[ "$(printf '%s' "$out" | jget 'd["action"]')" = "elicit" ] && ok "cycle 1: still within budget (a hop)" || err "cycle 1 not a hop"
[ "$(printf '%s' "$out" | jget 'd["cycle"]')" = "2" ] && ok "cycle 1 -> hop reports incremented cycle 2 (at the bound)" || err "cycle 1 increment wrong"

# At the cap (cycle 2): NO third hop — a publish blocker instead.
out=$(python3 "$DP" repair-hop --upstream "re-harvest bench/results.md" --cycle 2 2>/dev/null)
[ "$(printf '%s' "$out" | jget 'd["action"]')" = "publish-blocker" ] && ok "cycle 2 (cap): action is publish-blocker, no third hop" || err "cap did not block"
[ "$(printf '%s' "$out" | jget 'str(d["publishable"])')" = "False" ] && ok "cap: publishable is false" || err "cap publishable not false"
printf '%s' "$out" | jget '"missing-input" in d["blocker"]' | grep -q True && ok "cap: blocker names the unrepaired missing-input gap" || err "cap blocker unnamed"
printf '%s' "$out" | jget '"CAP-6" in d["reason"] and "third hop" in d["reason"]' | grep -q True \
  && ok "cap: reason routes to CAP-6 bucket and forbids a third hop" || err "cap reason wrong"

# Beyond the cap (cycle 3) is also a blocker (monotonic).
python3 "$DP" repair-hop --upstream "ask x" --cycle 3 2>/dev/null | jget 'd["action"]' | grep -q publish-blocker \
  && ok "beyond the cap stays a publish blocker" || err "beyond-cap not a blocker"

# A malformed remediation is still refused within budget (13.63 grammar holds).
python3 "$DP" repair-hop --upstream "find more stuff" --cycle 0 >/dev/null 2>&1 \
  && err "malformed remediation accepted within budget" || ok "malformed remediation still refused within budget"

# Negative cycle is refused.
python3 "$DP" repair-hop --upstream "re-harvest x" --cycle -1 >/dev/null 2>&1 \
  && err "negative cycle accepted" || ok "negative --cycle is refused"

# SKILL documents the cap + publish blocker.
sec=$(awk '/Missing-input repair hop/{f=1} f && /^## /{exit} f{print}' "$SKILL")
printf '%s' "$sec" | grep -q -- '--cycle' && ok "SKILL documents the --cycle cap parameter" || err "SKILL missing --cycle"
printf '%s' "$sec" | tr '\n' ' ' | grep -qi 'publish[[:space:]]*blocker' && ok "SKILL states the cap emits a publish blocker" || err "SKILL cap-blocker missing"
printf '%s' "$sec" | grep -qi 'third hop' && ok "SKILL states no third hop past the cap" || err "SKILL no-third-hop missing"

if [ "$fail" -eq 0 ]; then
  printf '\nAll missing-input-cap checks passed.\n'; exit 0
else
  printf '\nmissing-input-cap checks FAILED.\n' >&2; exit 1
fi
