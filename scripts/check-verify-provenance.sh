#!/usr/bin/env sh
# check-verify-provenance.sh — verify the independent verify-provenance check
# (Story 11.2). POSIX shell + stdlib Python.
#
# Covers: verify-provenance runs standalone, not sharing the drafting context
# (NFR13) — it lives in its own script and reads only the map + declared
# pointers + the judge's verdicts (AC1); a narration sentence the judge flags as
# asserting a checkable proposition is a gate failure (AC2); a derived claim
# whose inherited pointers don't resolve to fact-sheet entries is a gate failure,
# and a judge-flagged forbidden category is too (AC3); a clean map passes with no
# findings (AC4).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VP="$root/scripts/verify-provenance.py"
DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$VP', doraise=True)" 2>/dev/null \
  && ok "verify-provenance compiles" || { err "verify-provenance syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# AC1 — it is a STANDALONE script, independent of the drafting pipeline.
[ -f "$VP" ] && ok "verify-provenance is its own script (independent of drafting)" || err "verify-provenance.py missing"
grep -qE 'add_parser\("verify-provenance"\)' "$DP" 2>/dev/null && err "verify-provenance is a draft-pipeline subcommand (not independent)" \
  || ok "verify-provenance is not a draft-pipeline subcommand (independence)"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
printf 'fs-15\nfs-12\nfs-14\n' > "$work/ids.txt"

# AC4 — a clean map whose pointers all resolve, no judge findings, passes.
cat > "$work/good.txt" <<'MAP'
P1.S1: sourced <- fs-15
P1.S2: derived <- fs-12, fs-14
P1.S3: narration
P4.S5: verify
MAP
python3 "$VP" --map "$work/good.txt" --fact-sheet "$work/ids.txt" >/dev/null 2>&1 \
  && ok "a clean map passes with no findings" || err "clean map failed"

# AC3a — a derived claim whose inherited pointer does not resolve is a gate failure.
cat > "$work/badptr.txt" <<'MAP'
P1.S2: derived <- fs-12, fs-99
MAP
python3 "$VP" --map "$work/badptr.txt" --fact-sheet "$work/ids.txt" >/dev/null 2>&1 \
  && err "unresolvable derived pointer accepted" || ok "derived pointer must resolve to a fact-sheet entry"

# AC2 — a narration sentence the judge flags (asserts a checkable proposition) fails.
printf 'P1.S3: narration asserts a checkable proposition (falsifiability)\n' > "$work/verdicts.txt"
python3 "$VP" --map "$work/good.txt" --fact-sheet "$work/ids.txt" --judge-findings "$work/verdicts.txt" >/dev/null 2>&1 \
  && err "judge-flagged narration was not a gate failure" || ok "judge-flagged narration (falsifiability) is a gate failure"

# AC3b — a judge-flagged forbidden derivation category fails.
printf 'P1.S2: derived adds causality (forbidden)\n' > "$work/verdicts2.txt"
python3 "$VP" --map "$work/good.txt" --fact-sheet "$work/ids.txt" --judge-findings "$work/verdicts2.txt" >/dev/null 2>&1 \
  && err "judge-flagged forbidden category was not a gate failure" || ok "judge-flagged forbidden derivation category is a gate failure"

# Structural independence: narration/verify carrying a pointer fails even without a fact sheet.
printf 'P1.S3: narration <- fs-1\n' | python3 "$VP" --map - >/dev/null 2>&1 \
  && err "narration with a pointer accepted" || ok "narration-with-pointer fails (independent structural re-check)"

# The judge worklist is extractable (list narration + derived for grading).
[ "$(python3 "$VP" --map "$work/good.txt" --list-narration)" = "P1.S3" ] \
  && ok "narration positions are listable for the judge" || err "--list-narration wrong"
python3 "$VP" --map "$work/good.txt" --list-derived | grep -q 'P1.S2: fs-12, fs-14' \
  && ok "derived claims are listable for the judge" || err "--list-derived wrong"

# SKILL wires the independent check and states it does not share drafting context.
grep -q 'verify-provenance.py' "$SKILL" && grep -qi 'does .*not.*share\|not share this' "$SKILL" \
  && ok "SKILL wires the independent verify-provenance (no shared context)" || err "SKILL does not wire independent verify-provenance"

if [ "$fail" -eq 0 ]; then
  printf '\nAll verify-provenance checks passed.\n'; exit 0
else
  printf '\nverify-provenance checks FAILED.\n' >&2; exit 1
fi
