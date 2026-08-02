#!/usr/bin/env sh
# serial-reason: a known mtime race — recorded as an intermittent in the full
# covers: docs/dogfood-findings.md docs/evidence-gloss-consumption-join.md scripts/inspect-article-join.py
#   tier, and its fixture files are written inside one second so an
#   ordering-by-mtime assertion can read them as simultaneous. Re-verified
#   2026-07-31 (#999) and DELIBERATELY LEFT SERIAL: declaring a member with a
#   known nondeterminism is the exact defect the undeclared default exists to
#   prevent, and concurrency is the wrong place to first diagnose a
#   pre-existing flake. Diagnose it alone; declare it only once it is fixed.
# NOT parallel-safe (#957/#964) — deliberately carries no `# parallel-safe`
# header, so run-checks.sh -P leaves it in the serial remainder.
# check-article-join-view.sh — the per-paragraph Evidence/Gloss/consumption
# inspection view (Story 18.118, #725). POSIX shell + stdlib Python.
#
# Covers: the join document exists and states all three joins (AC1); every
# paragraph is rendered with all three legs, each explicit rather than omitted
# (AC2); consumption claims are classified with a stated reason (AC3); the
# findings write-up exists and names the design clause each divergence strains
# (AC5); the view writes nothing outside its own --out path (AC6).
#
# The load-bearing assertion is AC2's third leg: leg (b) must render as
# cannot-determine, NEVER as "none". The served lessons index carries no
# Evidence pointers, so "none" would assert an absence nothing established —
# collapsing three-valued absence to two-valued is the defect.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VIEW="$root/scripts/inspect-article-join.py"
JOINDOC="$root/docs/evidence-gloss-consumption-join.md"
FINDINGS="$root/docs/dogfood-findings.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$VIEW', doraise=True)" 2>/dev/null \
  && ok "inspect-article-join compiles" \
  || { err "inspect-article-join syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# --- AC1: the join is documented in one place, all three joins named. --------
[ -f "$JOINDOC" ] && ok "join document exists" || err "docs/evidence-gloss-consumption-join.md missing"
if [ -f "$JOINDOC" ]; then
  for want in 'claim-level' 'article-level' 'cannot-determine' 'LESSONS.md:9' \
              'write-article-plan.py:115-122' 'verify-provenance.py:16-22'; do
    grep -qF "$want" "$JOINDOC" \
      && ok "join doc states '$want'" \
      || err "join doc does not state '$want'"
  done
  # The disjoint-namespace fact is the whole point of the document.
  grep -qF 'write-article-plan.py:155-178' "$JOINDOC" \
    && ok "join doc grounds the element-id derivation in shipped code" \
    || err "join doc asserts the key story without a code citation"
fi

# --- Fixture: a plan + draft + provenance map, joined end to end. ------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/plans" "$work/repo/drafts" "$work/ws"

cat > "$work/repo/plans/fx.md" <<'PLAN'
---
kind: article-plan
slug: fx
run_id: FIXTURERUN
pin: host@abcdef1234567890abcdef1234567890abcdef12
consumed: [el-alpha, el-beta, el-orphan]
---

# Editorial decisions

- el-alpha — the grounded one. Evidence:
  README.md:10@abcdef1234567890abcdef1234567890abcdef12.
- el-beta — declared, but no paragraph carries it. Evidence:
  docs/never.md:99@abcdef1234567890abcdef1234567890abcdef12.
- el-orphan — named in consumed with no evidence stated at all.
PLAN

cat > "$work/repo/drafts/fx.md" <<'DRAFT'
---
slug: fx
---

Lede paragraph.

## First section

Grounded body.

## Second section

Ungrounded body.
DRAFT

cat > "$work/ws/provenance-map-v2.txt" <<'MAP'
P1.S1[L5]: narration
P2.S1[L9]: sourced <- README.md:10@abcdef1234567890abcdef1234567890abcdef12
P2.S2[L9]: sourced <- README.md:77@abcdef1234567890abcdef1234567890abcdef12
P3.S1[L13]: narration
MAP

# Stub resolve-paths so the fixture never touches real machine state.
mkdir -p "$work/bin"
cat > "$work/bin/resolve-paths.py" <<PY
import sys
print("$work/ws")
PY
cp "$VIEW" "$work/bin/inspect-article-join.py"

# Footprint snapshot BEFORE the view runs (#931): file list + content hashes.
# The old `find -newer plans/fx.md` compared mtimes, and the fixture files are
# all created within the same second as the sentinel — under load, timestamp
# jitter produced false positives on an assertion about WRITES. Content
# hashes detect exactly writes, with no clock in the loop.
footprint() { find "$1" -type f | sort | xargs -r sha256sum; }
before_fp=$(footprint "$work/repo")

out="$work/report.md"
python3 "$work/bin/inspect-article-join.py" --slug fx \
  --articles-repo "$work/repo" --host-root "$work/repo" --out "$out" >/dev/null 2>&1 \
  && ok "the view runs end to end over a fixture" \
  || { err "the view failed on the fixture"; printf '\nFAILED.\n' >&2; exit 1; }

# --- AC2: every paragraph rendered, all three legs explicit. -----------------
for p in 'P1' 'P2' 'P3'; do
  grep -qE "^\| $p \|" "$out" && ok "$p is rendered" || err "$p is missing from the view"
done
grep -qF 'First section' "$out" \
  && ok "paragraph->section derived from the draft's headings via the [L] anchor" \
  || err "section join did not resolve"
grep -qF '_none_' "$out" \
  && ok "an empty evidence leg renders explicitly as none, not omitted" \
  || err "an empty leg was omitted rather than stated"

# AC2, load-bearing: leg (b) is cannot-determine, and is never called "none".
grep -qF '_cannot-determine_' "$out" \
  && ok "leg (b) renders as cannot-determine (three-valued absence preserved)" \
  || err "leg (b) is not reported as cannot-determine"
gloss_none=$(awk -F'|' '/^\| P[0-9]+ \|/ {gsub(/ /,"",$5); if ($5=="_none_") c++} END {print c+0}' "$out")
[ "$gloss_none" -eq 0 ] \
  && ok "no paragraph claims the Gloss leg is empty (absence never asserted)" \
  || err "$gloss_none paragraph(s) rendered the Gloss leg as 'none' — absence asserted without a read"

# --- AC3: every consumption claim classified, with its reason. ---------------
grep -qE '\| `el-alpha` \| \*\*paragraph-attributable\*\*' "$out" \
  && ok "an element a paragraph grounds is paragraph-attributable" \
  || err "el-alpha misclassified"
grep -qE '\| `el-beta` \| \*\*article-level-only\*\*' "$out" \
  && ok "an element declared but never carried in prose is article-level-only" \
  || err "el-beta misclassified"
grep -qE '\| `el-orphan` \| \*\*not-attributable\*\*' "$out" \
  && ok "an element with no declared evidence is not-attributable" \
  || err "el-orphan misclassified"

# A paragraph grounded in evidence belonging to no element is counted, not hidden.
grep -qF 'paragraphs whose evidence maps to no element' "$out" \
  && ok "evidence with no element is reported as its own total" \
  || err "evidence-with-no-element is not surfaced"

# --- AC6: read-only — the fixture repo is untouched. -------------------------
# Compared by file list + content hash against the pre-run snapshot (#931):
# a write is a changed/added/removed file, never an mtime.
if [ "$before_fp" = "$(footprint "$work/repo")" ]; then
  ok "the view wrote nothing into the articles repo"
else
  err "the view wrote into the articles repo (footprint invariant)"
fi

# --- AC5: the findings write-up exists and traces each divergence. -----------
grep -qF '2026-07-26 — Gloss↔article join' "$FINDINGS" \
  && ok "findings entry recorded" || err "no 2026-07-26 join entry in dogfood-findings.md"
strains=$(grep -c '^  \*Strains:\*' "$FINDINGS" || true)
[ "$strains" -ge 4 ] \
  && ok "each recorded divergence names the design clause it strains ($strains)" \
  || err "findings entries do not name what they strain (found $strains)"
proposed=$(grep -c '\*Proposed (not applied):\*' "$FINDINGS" || true)
[ "$proposed" -ge 4 ] \
  && ok "amendments are proposed, never applied ($proposed)" \
  || err "findings do not carry proposal-only amendments (found $proposed)"

# --- AC6, statically: --out is the view's ONLY write path. ------------------
# The fixture check above proves it did not write this time; this proves it
# cannot, so a future edit that adds a second sink fails here rather than in a
# dogfood run against the owner's real repo.
writes=$(grep -cE '\bopen\([^)]*["'"'"']w' "$VIEW" || true)
[ "$writes" -eq 1 ] \
  && ok "the view has exactly one write path (--out)" \
  || err "the view has $writes write path(s); --out must be the only one"
grep -qE 'if args\.out:' "$VIEW" \
  && ok "the single write is guarded by --out" \
  || err "the view's write is not guarded by --out"

[ "$fail" -eq 0 ] && printf '\nPASSED.\n' || { printf '\nFAILED.\n' >&2; exit 1; }
