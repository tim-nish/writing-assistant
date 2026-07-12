#!/usr/bin/env sh
# check-completion-summary.sh — verify the three-bucket completion summary
# (Story 7.5, CAP-6): every run ends with exactly three labelled buckets
# (informational notes / publish blockers / optional cleanup) + an explicit next
# step; a blocker lives only in the publish-blockers bucket; article-producing /
# review runs show a reading-time estimate (~200 wpm EN / ~500 cpm JA) while a
# standalone harvest omits it. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

CONV="skills/completion-summary.md"
RT="scripts/reading-time.py"
DRAFT="skills/draft-article/SKILL.md"
REVIEW="skills/review-article/SKILL.md"
HARVEST="skills/harvest/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$CONV" ] && ok "completion-summary convention exists" \
  || { err "convention missing ($CONV)"; printf '\nFAILED.\n' >&2; exit 1; }

hasc() { grep -qi -- "$1" "$CONV" && ok "$2" || err "$2 — missing from convention"; }

# 1. Convention: three named buckets + next step + reading-time rule.
hasc 'informational notes'  "bucket: informational notes"
hasc 'publish blockers'     "bucket: publish blockers"
hasc 'optional cleanup'     "bucket: optional cleanup"
hasc 'next step'            "explicit next step"
hasc 'here and nowhere else\|nowhere else' "a blocker appears in exactly one bucket"
hasc '200 wpm'              "reading time: ~200 wpm EN"
hasc '500 cpm'             "reading time: ~500 cpm JA"

# 1b. Partial-progress reporting + budget-triage signal (Story 13.7, CAP-6).
hasc 'last completed stage' "partial run reports the last completed stage"
hasc 'resume --ws'          "partial run gives the resume path (pairs with Story 13.5)"
hasc 'budget-triage signal' "budget-triage signal surfaced before hard failure"
grep -qi 'informational' "$CONV" && grep -qi 'not a blocker\|recoverable, not broken' "$CONV" \
  && ok "partial progress is informational, not a blocker" || err "partial-progress bucket unclear"

# 2. reading-time.py computes EN words/200 and JA chars/500.
python3 -c "import py_compile; py_compile.compile('$root/$RT', doraise=True)" 2>/dev/null \
  && ok "reading-time helper compiles" || { err "reading-time syntax error"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# 400 EN words -> 400/200 = ~2 min.
awk 'BEGIN{for(i=0;i<400;i++)printf "word "}' > "$work/en.md"
en=$(python3 "$RT" --language en "$work/en.md")
[ "$en" = "~2 min read" ] && ok "EN: 400 words -> $en" || err "EN estimate wrong ($en)"
# 1000 JA chars -> 1000/500 = ~2 min.
python3 -c "open('$work/ja.md','w',encoding='utf-8').write('あ'*1000)"
ja=$(python3 "$RT" --language ja "$work/ja.md")
[ "$ja" = "~2 min read" ] && ok "JA: 1000 chars -> $ja" || err "JA estimate wrong ($ja)"
# short body -> at least ~1 min.
printf 'just a few words here\n' > "$work/tiny.md"
[ "$(python3 "$RT" --language en "$work/tiny.md")" = "~1 min read" ] \
  && ok "short body -> ~1 min (never 0)" || err "short-body estimate wrong"

# 3. All three skills reference the shared convention.
for f in "$DRAFT" "$REVIEW" "$HARVEST"; do
  grep -q 'completion-summary.md' "$f" && ok "$f references the completion summary" \
    || err "$f does not reference the completion summary"
done

# 4. Article-producing/review runs show reading time; standalone harvest omits it.
grep -q 'reading-time.py' "$DRAFT"  && ok "draft run shows reading time"  || err "draft missing reading time"
grep -q 'reading-time.py' "$REVIEW" && ok "review run shows reading time" || err "review missing reading time"
grep -qi 'omits.*reading-time\|omits the reading-time' "$HARVEST" \
  && ok "standalone harvest omits reading time" || err "harvest does not omit reading time"
grep -q 'reading-time.py' "$HARVEST" \
  && err "harvest should NOT invoke reading-time (no article body)" \
  || ok "harvest does not invoke reading-time"

# 5. Draft SKILL wires the budget-triage/partial-progress reporting (Story 13.7).
grep -qi 'budget-triage signal before hard failure' "$DRAFT" \
  && grep -qi 'last completed stage and the resume path' "$DRAFT" \
  && ok "draft SKILL surfaces budget-triage + partial-progress reporting" \
  || err "draft SKILL missing budget-triage/partial-progress wiring"

if [ "$fail" -eq 0 ]; then
  printf '\nAll completion-summary checks passed.\n'; exit 0
else
  printf '\ncompletion-summary checks FAILED.\n' >&2; exit 1
fi
