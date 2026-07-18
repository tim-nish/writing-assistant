#!/usr/bin/env sh
# check-unmapped-intent.sh — graceful handling when an article intent maps to
# no framework (Story 13.81). POSIX shell + stdlib Python.
#
# Covers: an unmapped intent is refused with the reason (ratified closed set)
# and a nearest fit, never only the label list; a tutorial/how-to intent
# references the deliberate AP-10 exclusion; resolution stays a closed mapping
# (no fuzzy selection); a mapped intent resolves exactly as before.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

P="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$P', doraise=True)" \
  && ok "pipeline compiles" || { err "pipeline syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

py() { python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('dp', '$P')
dp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dp)
$1
"; }

# Closed mapping unchanged: valid labels and F-ids resolve; unmapped stays None.
py "assert dp.resolve_framework('share engineering lessons') == 'f2'
assert dp.resolve_framework('F3') == 'f3'
assert dp.resolve_framework('a tutorial') is None" \
  && ok "AC3: mapped intents resolve unchanged; unmapped stays None (no fuzzy select)" \
  || err "resolve_framework behavior changed"

# The refusal path: reason + nearest fit, not only the label list.
hint_tut=$(py "print(dp.nearest_fit('write a tutorial on X'))")
printf '%s' "$hint_tut" | grep -q 'AP-10' \
  && ok "AC2: tutorial/how-to hint references the AP-10 exclusion" \
  || err "tutorial hint does not reference AP-10"
printf '%s' "$hint_tut" | grep -qi 'working-note' \
  && ok "tutorial hint offers the working-note profile" \
  || err "tutorial hint missing working-note fallback"
py "print(dp.nearest_fit('how-to guide'))" | grep -q 'AP-10' \
  && ok "hyphenated how-to routes to the same exclusion" || err "how-to variant unhinted"
py "print(dp.nearest_fit('a benchmark writeup'))" | grep -q 'evaluation methodology' \
  && ok "AC1: a benchmark intent points to its closest fit (F3 label)" \
  || err "benchmark intent got no nearest fit"
py "print(dp.nearest_fit('utterly unrelated poetry'))" | grep -qi 'working-note' \
  && ok "AC1: an intent with no close fit still gets the working-note fallback" \
  || err "no-fit intent left without direction"
# Hints speak intent labels, never bare F-ids (vocabulary boundary, CAP-1).
py "
import re
for _, h in dp.NEAREST_FIT_HINTS:
    assert not re.search(r'\bF[1-4]\b', h), h" \
  && ok "hints respect the vocabulary boundary (no bare F-ids)" \
  || err "a hint leaks internal F-ids"

# The stage-0 error message itself: reason + nearest fit + nothing started.
out=$(py "print(dp._run_state('write a tutorial', [])[0])" 2>&1) || true
printf '%s' "$out" | grep -q 'invalid article type' \
  && ok "error keeps the 'invalid article type' contract line" \
  || err "error lost the invalid-article-type line"
printf '%s' "$out" | grep -q 'ratified and closed' \
  && ok "AC1: error states why the set is closed" || err "error missing the reason"
printf '%s' "$out" | grep -q 'AP-10' \
  && ok "AC2: stage-0 error surfaces the AP-10 exclusion for a tutorial intent" \
  || err "stage-0 error missing AP-10 for tutorial"
printf '%s' "$out" | grep -q 'Nothing started' \
  && ok "refusal still starts nothing" || err "'Nothing started' line lost"

# Skill wiring: relay-the-hint instruction, no fuzzy selection.
grep -qi 'reason and a nearest fit' "$SKILL" \
  && ok "skill states the reason+nearest-fit contract" \
  || err "skill missing the unmapped-intent contract"
grep -qi 'fuzzy-select a framework' "$SKILL" \
  && ok "skill forbids fuzzy-selecting on the writer's behalf" \
  || err "skill missing the no-fuzzy-select line"

if [ "$fail" -ne 0 ]; then printf '\nFAILED.\n' >&2; exit 1; fi
printf '\nAll unmapped-intent checks passed.\n'
