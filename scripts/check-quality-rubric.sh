#!/usr/bin/env sh
# check-quality-rubric.sh — verify the article-quality rubric asset (Story 11.3).
# POSIX shell.
#
# Covers: a versioned quality-rubric.md exists and defines the four dimensions
# — narrative arc, paragraph flow, explanation calibration, readability
# mechanics (AC1); each dimension states an operational check (AC2); and the
# asset declares that exemplar-derived threshold tuning edits the asset, not the
# specs (AC3).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RUBRIC="skills/draft-article/quality-rubric.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -qi -- "$1" "$RUBRIC"; then ok "$2"; else err "$2 — missing"; fi; }

# 0. The asset exists and is versioned.
[ -f "$RUBRIC" ] && ok "quality-rubric.md exists" \
  || { err "quality-rubric.md missing at $RUBRIC"; printf '\nFAILED.\n' >&2; exit 1; }
grep -qE 'rubric-version: *[0-9]+' "$RUBRIC" && ok "asset carries a rubric-version" || err "no rubric-version marker"

# 1. Four named dimensions (AC1).
has 'narrative arc'          "dimension 1: narrative arc"
has 'paragraph flow'         "dimension 2: paragraph flow"
has 'explanation calibration' "dimension 3: explanation calibration"
has 'readability mechanics'  "dimension 4: readability mechanics"
n=$(grep -cE '^## Dimension [0-9]' "$RUBRIC")
[ "$n" -eq 4 ] && ok "exactly four dimension sections" || err "expected 4 dimension sections, found $n"

# 2. Each dimension states an operational check (AC2) — the named probes/metrics.
has 'deletion probe'                 "arc: section-level deletion probe"
has 'topic sentence first'           "flow: topic-sentence-first"
has 'orphan fact'                    "flow: no orphan facts"
has 'term-introduced-at-or-before-first-use' "calibration: term-introduced-at-or-before-first-use (#305)"
has 'sentence length'                "mechanics: sentence-length metric"
has 'heading density'                "mechanics: heading density"
has 'density'                        "mechanics: quote/sourced-claim density"
# dimension 4 is mechanical / zero-token.
grep -qiE 'zero.token|mechanical' "$RUBRIC" && ok "dimension 4 is mechanical (zero tokens)" || err "dimension 4 not marked mechanical"

# 3. AC3 — exemplar tuning edits the asset, not the specs.
grep -qi 'edits .*this file\|tuning edits' "$RUBRIC" && grep -qi 'never the specs\|not the specs' "$RUBRIC" \
  && ok "asset states tuning edits the asset, not the specs" || err "missing the tuning-edits-asset clause"

if [ "$fail" -eq 0 ]; then
  printf '\nAll quality-rubric checks passed.\n'; exit 0
else
  printf '\nquality-rubric checks FAILED.\n' >&2; exit 1
fi
