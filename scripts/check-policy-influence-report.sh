#!/usr/bin/env sh
# check-policy-influence-report.sh — verify the policy-influence report
# convention (Story 13.40, SPEC-policy-editorial-direction CAP-4): a view over
# recorded run state, on request only, no second draft / A/B run, record-only
# counterfactuals, human-facing placement. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

CONV="skills/policy-influence-report.md"
DRAFT="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$CONV" ] && ok "report convention exists" \
  || { err "convention missing ($CONV)"; printf '\nFAILED.\n' >&2; exit 1; }

hasc() { grep -qi -- "$1" "$CONV" && ok "$2" || err "$2 — missing"; }

hasc 'on request only'            "emitted on request only, never unasked"
hasc 'second draft'               "no second draft"
hasc 'never an A/B run'           "no A/B run"
hasc 'interview-journal'          "input: the interview journal"
hasc 'presented-payloads'         "input: the presented-payload log"
hasc 'consulted'                  "input: consulted lines"
hasc 'counterfactual not recorded' "unrecorded counterfactuals are named, never invented"
hasc 'output.drafts'              "file form lands at the declared product location"
hasc 'no policy files'            "report generation reads no policy files (record is the truth)"
grep -q 'policy-influence-report.md' "$DRAFT" \
  && ok "draft SKILL references the report convention" \
  || err "draft SKILL does not reference the report"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-influence-report checks passed.\n'; exit 0
else
  printf '\npolicy-influence-report checks FAILED.\n' >&2; exit 1
fi
