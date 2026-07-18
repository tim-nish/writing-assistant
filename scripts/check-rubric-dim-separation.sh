#!/usr/bin/env sh
# check-rubric-dim-separation.sh — verify the dim4-vs-dim1/2 dimension
# separation (Story 13.66, #349). POSIX shell + stdlib Python.
#
# Covers: the rubric states length is dimension 4's and flow is dimensions
# 1-2's, a dim1/dim2 finding must cite narrative/flow (never a length
# artifact), and a sentence split to satisfy dim4 is neutral for dim1/dim2;
# the judge instruction in the SKILL mirrors it; and — mechanically — a
# long-sentence draft fails dim4 while its split version passes dim4 and
# introduces no new mechanical finding (the convergence case).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
RUBRIC="skills/draft-article/quality-rubric.md"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

# --- Contract documented in the rubric ---------------------------------------
grep -qi 'Dimension separation' "$RUBRIC" && ok "rubric documents the dimension-separation contract" || err "separation contract missing"
grep -qi 'Dimension 4 owns length' "$RUBRIC" && ok "rubric: dim4 owns length/vocabulary distribution" || err "dim4-owns-length missing"
grep -qi 'must cite a narrative' "$RUBRIC" && ok "rubric: dim1/dim2 must cite a narrative/flow defect" || err "dim1/2-cite-flow missing"
tr '\n' ' ' < "$RUBRIC" | grep -qi 'neutral for[[:space:]]*dimensions 1' && ok "rubric: a dim4 split/merge is neutral for dim1/dim2" || err "split-neutral rule missing"
# The judge instruction in the SKILL mirrors it.
grep -qi 'never a sentence- or paragraph-length artifact' "$SKILL" \
  && ok "SKILL instructs the judge: no length artifacts in dim1/dim2" || err "SKILL judge instruction missing"

# --- Mechanical convergence: a dim4 length fix does not create a new finding --
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
printf 'dim1: pass\ndim2: pass\ndim3: pass\n' > "$work/judge-pass.txt"

# A draft whose one body sentence is very long (>40 words) trips dim4.
cat > "$work/long.md" <<'MD'
---
slug: t
title: The one claim
language: en
audience: en-practitioner
---
# The one claim

Structured discovery halved our token bill because the pipeline stopped issuing redundant reads against the same source material over and over which had previously inflated every prompt with duplicated context that the model never actually needed to answer the question at hand.
MD
cat > "$work/map.txt" <<'MAP'
P1.S1: derived <- fs-1, fs-2
MAP
out=$(python3 "$DP" quality-gate --draft "$work/long.md" --map "$work/map.txt" --judge "$work/judge-pass.txt" 2>/dev/null || true)
printf '%s' "$out" | jget '"dim4" in d["failing_dimensions"]' | grep -q True \
  && ok "a long-sentence draft fails dim4 (mechanical length)" || err "long sentence did not fail dim4"

# The SAME draft with that sentence SPLIT into shorter ones passes dim4, with
# no other mechanical dimension newly failing (the convergence case).
cat > "$work/split.md" <<'MD'
---
slug: t
title: The one claim
language: en
audience: en-practitioner
---
# The one claim

Structured discovery halved our token bill. The pipeline stopped issuing redundant reads against the same source. Those duplicate reads had inflated every prompt with context the model never needed.
MD
cat > "$work/map2.txt" <<'MAP'
P1.S1: sourced <- fs-1
P1.S2: derived <- fs-1, fs-2
P1.S3: narration
MAP
out=$(python3 "$DP" quality-gate --draft "$work/split.md" --map "$work/map2.txt" --judge "$work/judge-pass.txt" 2>/dev/null || true)
printf '%s' "$out" | jget 'd["dimensions"]["dim4"]["verdict"]' | grep -q pass \
  && ok "the split version passes dim4 (length resolved)" || err "split version still fails dim4"
printf '%s' "$out" | jget 'd["pass"]' | grep -q True \
  && ok "the split introduces no new MECHANICAL finding (dims 3/4/audience all pass) -> converges" \
  || err "the split created a new mechanical finding: $(printf '%s' "$out" | jget 'd["failing_dimensions"]')"

if [ "$fail" -eq 0 ]; then
  printf '\nAll rubric-dim-separation checks passed.\n'; exit 0
else
  printf '\nrubric-dim-separation checks FAILED.\n' >&2; exit 1
fi
