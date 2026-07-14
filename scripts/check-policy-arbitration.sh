#!/usr/bin/env sh
# check-policy-arbitration.sh — verify policy-finding arbitration routing
# (Story 15.2, SPEC-policy-consistency-pass CAP-3). POSIX shell + stdlib Python.
#
# Covers: the SKILL's three effect-stating choices (fix article / position
# moved / dismiss); position-moved emits a staging-candidate block via the
# emitter's --findings form (only with owner decision text); fix-article and
# dismiss emit nothing; the interview form is byte-identical to before; and
# an open policy finding never blocks "publishable".

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/review-article/SKILL.md"
PIPE="scripts/draft-pipeline.py"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
hasin() { tr '\n' ' ' < "$SKILL" | tr -s ' ' | grep -qi -- "$1" && ok "$2" || err "$2 — missing"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- 1. SKILL: three effect-stating choices + never-blocks rule ----------------
hasin 'Fix article'                       "choice: fix article"
hasin 'Position moved'                    "choice: position moved"
hasin 'Dismiss.*no effect'                "choice: dismiss (effect stated)"
hasin 'never blocks .publishable.'        "open policy finding never blocks publishable"
hasin 'staging-candidates.*--findings'    "position-moved routes through the --findings emitter"

# --- 2. Emitter --findings form -------------------------------------------------
cat > "$work/findings.json" <<'JSON'
[
  {"id": "pf1", "issue": "the draft claims pull-based commands are durable",
   "article": {"quote": "pull-based agent commands are the durable pattern", "pointer": "drafts/intro.md:41"},
   "policy": {"quote": "Agent workflows must be push-based", "pointer": "LESSONS.md:39@8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"},
   "outcome": "position-moved",
   "decision": "The position holds for unattended workflows; interactive review-cadence commands are a recorded exception."},
  {"id": "pf2", "issue": "x", "outcome": "fix-article", "decision": "irrelevant",
   "article": {"quote": "a", "pointer": "d.md:1"}, "policy": {"quote": "b", "pointer": "GLOSSARY.md:9@8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}},
  {"id": "pf3", "issue": "y", "outcome": "dismiss",
   "article": {"quote": "a", "pointer": "d.md:2"}, "policy": {"quote": "b", "pointer": "LESSONS.md:20@8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}},
  {"id": "pf4", "issue": "z", "outcome": "position-moved", "decision": "",
   "article": {"quote": "a", "pointer": "d.md:3"}, "policy": {"quote": "b", "pointer": "LESSONS.md:21@8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}}
]
JSON
python3 "$PIPE" staging-candidates --findings "$work/findings.json" \
  --source-repo papers --created 2026-07-14 --tag claude-code-ops > "$work/blocks.md"
n=$(grep -c '<!-- staging-candidate -->' "$work/blocks.md" || true)
[ "$n" -eq 1 ] && ok "one block: position-moved with decision text only (fix/dismiss/empty-decision propose nothing)" \
  || err "expected 1 block, got $n"
grep -q 'slug: 2026-07-14-papers-reversal-pf1' "$work/blocks.md" && ok "reversal slug carries the finding id" \
  || err "slug wrong"
grep -q 'tags: \[policy-contradiction, claude-code-ops\]' "$work/blocks.md" && ok "tags: criterion + track" \
  || err "tags wrong"
grep -q 'LESSONS.md:39@' "$work/blocks.md" && ok "block quotes the recorded position with its pinned pointer" \
  || err "policy pointer missing from block"
grep -q '^Decision: The position holds' "$work/blocks.md" && ok "Decision carries the owner's text in full sentences" \
  || err "Decision text missing"

# All-dismissed run emits nothing.
python3 - "$work/none.json" <<'PYEOF'
import json, sys
json.dump([{"id": "pf1", "issue": "x", "outcome": "dismiss",
            "article": {"quote": "a", "pointer": "d.md:1"},
            "policy": {"quote": "b", "pointer": "LESSONS.md:5@8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}}],
          open(sys.argv[1], "w"))
PYEOF
out=$(python3 "$PIPE" staging-candidates --findings "$work/none.json" --source-repo papers --created 2026-07-14)
[ -z "$out" ] && ok "no position-moved findings: emits nothing" || err "emitted on all-dismiss: '$out'"

# --- 3. Interview form unchanged; missing-input error names both forms ------------
sh scripts/check-staging-candidates.sh >/dev/null 2>&1 \
  && ok "interview form byte-identical (check-staging-candidates.sh green)" \
  || err "interview-form regression (check-staging-candidates.sh failed)"
set +e; msg=$(python3 "$PIPE" staging-candidates --source-repo papers --created 2026-07-14 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 2 ] && printf '%s' "$msg" | grep -q -- '--findings' \
  && ok "missing input: usage error names both forms" || err "usage error wrong: rc=$rc '$msg'"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-arbitration checks passed.\n'; exit 0
else
  printf '\npolicy-arbitration checks FAILED.\n' >&2; exit 1
fi
