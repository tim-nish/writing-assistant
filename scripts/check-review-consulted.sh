#!/usr/bin/env sh
# check-review-consulted.sh — verify the review-side consulted line and the
# policy pass's degradation wiring (Story 15.3, SPEC-policy-consistency-pass
# CAP-4). POSIX shell + stdlib Python only.
#
# Covers: `review-consulted` emits the pin + pointer→finding map with
# (no conflict) closures, the zero-findings mode, and both `none` modes
# (unset / unavailable with reason); the SKILL branches on the reader's exit
# codes (10 silent, 11/12 one relayed line, 4 halt) and never aborts the
# review; and no new reader/config/pointer surface exists — the pass's only
# policy access is read-policy-source.py.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/review-article/SKILL.md"
PIPE="scripts/draft-pipeline.py"
SHA=8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
hasin() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qi -- "$1" && ok "$2" || err "$2 — missing"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- 1. review-consulted: seeded mode -----------------------------------------
cat > "$work/pf.json" <<JSON
[{"id": "pf1", "policy": {"pointer": "LESSONS.md:39@$SHA", "quote": "x"}},
 {"id": "pf2", "policy": {"pointer": "topics/claude-code-ops.md:12@$SHA", "quote": "y"}}]
JSON
line=$(python3 "$PIPE" review-consulted --pin "product-lab@$SHA" --findings "$work/pf.json" \
       --file GLOSSARY.md --file LESSONS.md --file topics/claude-code-ops.md)
echo "$line" | grep -q "^consulted: product-lab@$SHA — LESSONS.md:39 → finding 1; topics/claude-code-ops.md:12 → finding 2; GLOSSARY.md → (no conflict)$" \
  && ok "seeded: pin + pointer→finding map + (no conflict) closure" \
  || err "seeded line wrong: '$line'"

# --- 2. Pass ran, zero findings --------------------------------------------------
line=$(python3 "$PIPE" review-consulted --pin "product-lab@$SHA" --file GLOSSARY.md --file LESSONS.md)
echo "$line" | grep -q '(no conflict)$' && echo "$line" | grep -qv 'finding' \
  && ok "zero findings: every checked file closes (no conflict)" \
  || err "zero-findings line wrong: '$line'"

# --- 3. Skipped modes -------------------------------------------------------------
[ "$(python3 "$PIPE" review-consulted --policy-note)" = "consulted: none (policy_source unset)" ] \
  && ok "skipped (unset): consulted: none" || err "unset mode wrong"
line=$(python3 "$PIPE" review-consulted --policy-note "policy_source unavailable: path does not exist")
[ "$line" = "consulted: none (policy_source unavailable: path does not exist)" ] \
  && ok "skipped (unavailable): reason carried" || err "unavailable mode wrong: '$line'"

# --- 4. Usage error names both modes ------------------------------------------------
set +e; msg=$(python3 "$PIPE" review-consulted 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 2 ] && printf '%s' "$msg" | grep -q -- '--policy-note' \
  && ok "no-args: usage error names both modes" || err "usage error wrong: rc=$rc"

# --- 5. SKILL: exit-code branches, one-line relay, artifact closure -------------------
hasin 'no exit code here may abort the review'      "no reader exit code aborts the review"
hasin '\*\*10\*\*.*skip the pass \*\*silently\*\*'  "exit 10: silent skip"
hasin 'relay that one line once'                    "exit 11/12: one relayed line"
hasin 'review-consulted'                            "SKILL composes the consulted line"
hasin 'review run artifact ends with the .consulted:. line' "artifact ends with consulted:"
hasin 'every review run states its policy provenance' "generic runs record consulted: none"

# --- 6. No second policy-access path ---------------------------------------------------
n=$(grep -c 'read-policy-source.py' "$SKILL" || true)
[ "$n" -ge 1 ] && ok "the seam reader is the pass's policy access" || err "reader invocation missing"
grep -Eq 'policy_source[^ ]*\.(ya?ml|json)' "$SKILL" \
  && err "SKILL parses policy config directly (second surface)" \
  || ok "no second reader/config surface in the SKILL"

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-consulted checks passed.\n'; exit 0
else
  printf '\nreview-consulted checks FAILED.\n' >&2; exit 1
fi
