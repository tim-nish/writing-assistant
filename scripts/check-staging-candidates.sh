#!/usr/bin/env sh
# check-staging-candidates.sh — verify the staging-candidate block emitter
# (Story 14.5, SPEC-policy-source-seam CAP-4; seam-formats.md §3).
# POSIX shell + stdlib Python only.
#
# Covers: an answered policy-seeded tension question yields one schema-valid
# block (frontmatter mirroring q_a/staging: slug/created/source_repo/
# perishable/tags + Q/Decision); skipped tension questions and generic answers
# yield nothing; a run with no candidates emits nothing (no empty block); the
# emitter writes stdout only (no file is created or modified under a policy
# path); and the SKILL routes candidates into the completion summary's
# informational notes.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

PIPE="scripts/draft-pipeline.py"
FIX="scripts/fixtures/interview-items"
SKILL="skills/draft-article/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

state='{"stage":"consume","fact_sheet":[],"needs_owner":[]}'
printf '%s' "$state" | python3 "$PIPE" interview --framework F1 \
  --items "$FIX/valid.json" - > "$work/interview.json"

# Answers: t1 answered (owner text), t2 skipped, q1 (generic) answered.
cat > "$work/answers.json" <<'JSON'
[
  {"id": "t1", "disposition": "replaced",
   "text": "The position moved: mechanism-over-prompt still holds; the draft is wrong and will be fixed."},
  {"id": "t2", "disposition": "skipped"},
  {"id": "q1", "disposition": "answered", "text": "The cap surprised me."},
  {"id": "q2", "disposition": "skipped"},
  {"id": "q3", "disposition": "skipped"},
  {"id": "q4", "disposition": "skipped"},
  {"id": "q5", "disposition": "skipped"}
]
JSON

# --- 1. One answered tension question -> one schema-valid block ----------------
python3 "$PIPE" staging-candidates --interview "$work/interview.json" \
  --answers "$work/answers.json" --source-repo papers --created 2026-07-14 \
  --tag eval-engineering > "$work/blocks.md"
n=$(grep -c '<!-- staging-candidate -->' "$work/blocks.md" || true)
[ "$n" -eq 1 ] && ok "exactly one block: answered tension question only (skip/generic propose nothing)" \
  || err "expected 1 block, got $n"
for field in 'slug: 2026-07-14-papers-' 'created: 2026-07-14' 'source_repo: papers' \
             'perishable: true' 'tags: [contradiction, eval-engineering]'; do
  grep -qF "$field" "$work/blocks.md" && ok "frontmatter: $field" \
    || err "frontmatter missing: $field"
done
grep -q '^Q: ' "$work/blocks.md" && grep -q '^Decision: The position moved' "$work/blocks.md" \
  && ok "block carries Q and the owner's decision in full sentences" \
  || err "Q/Decision body missing"

# --- 2. No candidates -> no output, no empty block -------------------------------
cat > "$work/allskip.json" <<'JSON'
[{"id": "t1", "disposition": "skipped"}, {"id": "t2", "disposition": "skipped"},
 {"id": "q1", "disposition": "skipped"}, {"id": "q2", "disposition": "skipped"},
 {"id": "q3", "disposition": "skipped"}]
JSON
out=$(python3 "$PIPE" staging-candidates --interview "$work/interview.json" \
      --answers "$work/allskip.json" --source-repo papers --created 2026-07-14)
[ -z "$out" ] && ok "all-skip run: emits nothing (no empty/placeholder block)" \
  || err "all-skip run emitted output: '$out'"

# --- 3. Proposal-only: the emitter cannot write files ------------------------------
grep -q 'open(' scripts/draft-pipeline.py \
  && python3 - <<'PYEOF'
import re, sys
src = open("scripts/draft-pipeline.py").read()
m = re.search(r"def cmd_staging_candidates.*?(?=\ndef cmd_)", src, re.S)
body = m.group(0)
assert "open(" not in body.replace('_load_json_state', ''), "emitter opens files itself"
assert 'w"' not in body and "'w'" not in body, "emitter has a write-mode open"
PYEOF
[ $? -eq 0 ] && ok "emitter writes stdout only — no file writes in its body (proposal-only)" \
  || err "emitter body appears to write files"

# --- 4. SKILL wiring: workspace routing + completion-summary visibility ------------
grep -q 'staging-candidates' "$SKILL" && ok "SKILL: stage-2 epilogue emits candidates" \
  || err "SKILL missing staging-candidates step"
grep -q 'staging-candidates.md' "$SKILL" && ok "SKILL: candidates land in the run workspace" \
  || err "SKILL missing workspace routing"
grep -q 'by hand' "$SKILL" && ok "SKILL: the human copies blocks — no automated cross-repo write" \
  || err "SKILL missing the manual-copy contract"
grep -qE 'informational notes.*staging|staging.*informational notes' "$SKILL" \
  || grep -B3 -A3 'staging-candidates.md' "$SKILL" | grep -q 'informational' \
  && ok "SKILL: completion summary names emitted candidates (informational bucket)" \
  || err "SKILL missing completion-summary visibility"

if [ "$fail" -eq 0 ]; then
  printf '\nAll staging-candidate checks passed.\n'; exit 0
else
  printf '\nstaging-candidate checks FAILED.\n' >&2; exit 1
fi
