#!/usr/bin/env sh
# tier: inner — greps over one markdown asset plus one gate invocation over a
#   tiny mktemp fixture; no network, no repo mutation.
# measured: 270ms (three runs, 2026-08-04, all 270ms)
# ends: the quality rubric drifting from the contract its consumers read — a
#   dimension renamed, dropped, or added without its judged/mechanical split
#   and (since #1412) without its absent-subject behaviour, while
#   draft-pipeline.py, the completion summary and review-reentry keep quoting
#   a count they derive from it. NOT generation-side preventable: the rubric
#   is a hand-authored versioned asset by design (exemplar-derived tuning
#   edits it, never the specs), so nothing at the point of writing it can see
#   its consumers.
# removal-signal: the rubric's dimension set becoming machine-derived from a
#   single declared source its consumers read directly, at which point the
#   asset and its readers cannot disagree and this check has no subject.
#
# These headers are owed because this file LEFT the admission baseline when it
# was edited (#1356) — the exemption covers files predating the clauses, not
# edits to them. The edit added the #1412 dimension-5 assertions.
# parallel-safe
# covers: skills/draft-article/quality-rubric.md
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

# 1. The named dimensions (AC1). Each is asserted BY NAME — the count alone
# would let a rename pass — and the count then asserts nothing is present
# beyond them, so an undeclared sixth still fails.
has 'narrative arc'          "dimension 1: narrative arc"
has 'paragraph flow'         "dimension 2: paragraph flow"
has 'explanation calibration' "dimension 3: explanation calibration"
has 'readability mechanics'  "dimension 4: readability mechanics"
has 'plain-register commitment' "dimension 5: both ends realize the commitment (#1412)"
n=$(grep -cE '^## Dimension [0-9]' "$RUBRIC")
[ "$n" -eq 5 ] && ok "exactly five dimension sections" || err "expected 5 dimension sections, found $n"

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

# --- Story 20.213 (#1412): DIMENSION 5 — both ends realize the commitment -----
# Negative run (rule 6): every assertion watched failing against main@bb52986
# (pre-20.213) — no dim5 section, no anti-check clause, dim5 unparsed by
# _DIM_LINE_RE and unwritten by _render_verdict_record.
grep -q '^## Dimension 5' "$RUBRIC" \
  && ok "20.213: the rubric carries dimension 5 (both ends realize the commitment)" \
  || err "20.213: no dimension 5 in the rubric"
grep -qi 'never a target sentence' "$RUBRIC" \
  && ok "20.213: the judge is handed the commitment and the two ends — never a target sentence" \
  || err "20.213: the rubric does not state that no target sentence exists"
grep -qi 'ANTI-check' "$RUBRIC" \
  && ok "20.213: a string match is named as the ANTI-check, not the check" \
  || err "20.213: the anti-check clause is missing — a grep would rebuild the template shape #1410 removed"
grep -qi 'n/a' "$RUBRIC" && grep -qi 'absent line' "$RUBRIC" \
  && ok "20.213: the conditional case is an explicit n/a verdict, never an absent line" \
  || err "20.213: the rubric does not state the n/a disclosure"
grep -q 'rubric-version: 2' "$RUBRIC" \
  && ok "20.213: rubric-version bumped with the dimension change" \
  || err "20.213: rubric-version not bumped — a versioned asset changed silently"

# The contract is CODE-BOUND, not prose-only: the record must carry dim5 and
# the parser must be able to see it. A reader with no writer (or a writer no
# reader parses) is the class this session kept finding.
work5=$(mktemp -d)
printf -- '---\nslug: t\n---\n\nA sentence here.\n' > "$work5/d.md"
printf 'P1.S1[L5]: narration\n' > "$work5/m.txt"
python3 "$root/scripts/draft-pipeline.py" quality-gate --draft "$work5/d.md" \
  --map "$work5/m.txt" --verdicts-out "$work5/v.txt" >/dev/null 2>&1 || true
grep -q '^dim5:' "$work5/v.txt" \
  && ok "20.213: the gate WRITES dim5 into the verdict record, n/a included" \
  || err "20.213: the gate emits no dim5 line — the predicate would require what nothing writes"
python3 - "$work5/v.txt" <<'PY5' \
  && ok "20.213: the record parser SEES dim5, so completeness is computable over it" \
  || err "20.213: _DIM_LINE_RE does not match dim5 — the line is written and unread"
import sys
sys.path.insert(0, "scripts")
import importlib.util as iu
spec = iu.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = iu.module_from_spec(spec); spec.loader.exec_module(dp)
text = open(sys.argv[1]).read()
assert "dim5" not in dp._verdict_record_gaps(text), dp._verdict_record_gaps(text)
stripped = "\n".join(l for l in text.splitlines() if not l.startswith("dim5:"))
assert "dim5" in dp._verdict_record_gaps(stripped), "a record with no dim5 read as complete"
PY5
rm -rf "$work5"

if [ "$fail" -eq 0 ]; then
  printf '\nAll quality-rubric checks passed.\n'; exit 0
else
  printf '\nquality-rubric checks FAILED.\n' >&2; exit 1
fi
