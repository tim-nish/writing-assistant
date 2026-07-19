#!/usr/bin/env sh
# check-quality-gate.sh — verify the mandatory Stage 3→4 quality gate with
# bounded retry (Story 11.4). POSIX shell + stdlib Python.
#
# Covers: the gate is a stage-progression precondition (non-zero exit blocks),
# not an advisory finding (AC1); dimension 4 is checked mechanically (zero
# tokens) and dims 1-3 come from the single-pass judge (AC2); a fact-sheet-
# stitched draft (all sourced, no derived/narration tissue) fails and does not
# reach stage 4 unrevised (AC-final); and the SKILL states the bounded ≤2
# revision cycles re-running BOTH gates, the publish-blocker surface, and the
# NFR12 owner-approved-content protection (AC3/AC4).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# A clean, well-mixed draft + map + all-pass judge verdicts. Carries the
# pipeline-internal `audience` field (a gate precondition since Story 13.41).
cat > "$work/good.md" <<'MD'
---
slug: t
title: The one claim
language: en
audience: en-practitioner
audience_id: en-practitioner
---
# The one claim

Structured discovery halved our token bill. We measured it across the suite.
The mechanism was simple. Fewer redundant reads meant fewer prompt tokens.

## Evidence

The bench recorded a 2x drop. That number held across three runs.
MD
cat > "$work/good-map.txt" <<'MAP'
P1.S1: sourced <- fs-1
P1.S2: derived <- fs-1, fs-2
P1.S3: narration
P2.S1: sourced <- fs-3
MAP
printf 'dim1: pass\ndim2: pass\ndim3: pass\n' > "$work/judge-pass.txt"

# AC1/AC2 — clean draft + all dims pass -> gate passes (exit 0).
out=$(python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-pass.txt")
echo "$out" | jget 'd["pass"]' | grep -q True && ok "a clean, well-mixed draft passes the gate" || err "clean draft failed the gate"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-pass.txt" >/dev/null 2>&1 \
  && ok "gate exits 0 on pass" || err "gate non-zero on a passing draft"

# AC1 — a judge fail on any dimension BLOCKS (non-zero exit): it is a precondition.
printf 'dim1: fail — opening states a topic, not a claim\ndim2: pass\ndim3: pass\n' > "$work/judge-fail.txt"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-fail.txt" >/dev/null 2>&1 \
  && err "a failing dimension did not block" || ok "a failing judged dimension blocks stage 4 (precondition)"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-fail.txt" \
  | jget '"dim1" in d["failing_dimensions"]' | grep -q True && ok "names the failing dimension" || err "failing dimension not named"

# AC2 — dimension 4 is mechanical (zero tokens): with NO judge verdicts, dim4
# still evaluates; a stitched-fact-sheet map fails dim4.
cat > "$work/stitch-map.txt" <<'MAP'
P1.S1: sourced <- fs-1
P1.S2: sourced <- fs-2
P1.S3: sourced <- fs-3
MAP
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/stitch-map.txt" --judge "$work/judge-pass.txt" \
  | jget 'd["dimensions"]["dim4"]["verdict"]' | grep -q fail \
  && ok "stitched fact sheet (all sourced, no tissue) fails dimension 4 mechanically" || err "stitched fact sheet passed"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/stitch-map.txt" --judge "$work/judge-pass.txt" >/dev/null 2>&1 \
  && err "stitched fact sheet reached stage 4" || ok "stitched fact sheet does not reach stage 4 unrevised"

# A wall-of-text paragraph fails dim4 mechanically (no judge needed).
python3 -c "print('---\nslug: w\naudience: en-practitioner\naudience_id: en-practitioner\n---\n# t\n\n' + ' '.join('word%d'%i for i in range(200)) + '.')" > "$work/wall.md"
python3 "$DP" quality-gate --draft "$work/wall.md" | jget 'd["dimensions"]["dim4"]["verdict"]' | grep -q fail \
  && ok "a wall-of-text paragraph fails dim4 (mechanical)" || err "wall of text passed dim4"

# #303 — an unparseable judge file is a distinct named error (exit 2), never a
# per-dimension "no judge verdict" fail: format mismatch must be
# distinguishable from a genuine rubric failure.
printf 'dimension 1: pass\ndimension 2: pass\ndimension 3: pass\n' > "$work/judge-prose.txt"
rc=0; errout=$(python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-prose.txt" 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 2 ] && ok "prose-form judge verdicts exit 2 (unparseable), not a dimension fail" \
  || err "prose-form judge verdicts exited $rc, expected 2"
echo "$errout" | grep -q 'judge verdicts unparseable' && ok "unparseable-judge error is named" || err "unparseable-judge error not named"
printf 'dim1: pass\n' > "$work/judge-missing.txt"
rc=0; python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-missing.txt" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && ok "a judge file missing a gated dimension exits 2 (incomplete = unparseable)" \
  || err "missing-dimension judge file exited $rc, expected 2"

# F83 — a nonexistent --judge path is a named error, never a raw FileNotFoundError
# traceback (the same convention _load_json_state gives JSON callers).
rc=0; errout=$(python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/no-such-judge.txt" 2>&1 >/dev/null) || rc=$?
[ "$rc" -ne 0 ] && echo "$errout" | grep -q 'file not found' \
  && ! echo "$errout" | grep -q 'Traceback' \
  && ok "a missing --judge file is a named 'file not found' error, not a traceback (F83)" \
  || err "missing --judge file: rc=$rc, output: $errout"

# #305 — dim3 is MECHANICAL: the judge gates dims 1-2 only, and a judge file
# carrying no dim3 line is complete.
printf 'dim1: pass\ndim2: pass\n' > "$work/judge-12.txt"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-12.txt" >/dev/null 2>&1 \
  && ok "a dim1+dim2 judge file is complete (dim3 is scanned, not judged)" \
  || err "dim1+dim2 judge file rejected"
# A judge dim3 verdict is recorded as an ADVISORY and never gates: here the
# judge says dim3 fails, the scan says it passes -> the gate passes.
printf 'dim1: pass\ndim2: pass\ndim3: fail line 9: "harvest" unintroduced\n' > "$work/judge-d3.txt"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-d3.txt" >/dev/null 2>&1 \
  && ok "a judge dim3 FAIL does not gate (advisory only)" || err "judge dim3 gated the run"
python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/good-map.txt" --judge "$work/judge-d3.txt" \
  | jget 'd["advisories"][0]["dimension"] + ":" + d["advisories"][0]["source"]' | grep -q 'dim3:rubric-judge' \
  && ok "the judge's dim3 opinion is recorded as an advisory" || err "dim3 advisory not recorded"

# #305 — the scan is exhaustive: N uncalibrated terms yield N in ONE verdict.
cat > "$work/vocab.md" <<'MD'
---
slug: v
audience: en-practitioner
audience_id: en-practitioner
---
# T

The harvest fed Stage 3, the GATE, and the fact sheet in one pass here.
MD
n=$(python3 "$DP" quality-gate --draft "$work/vocab.md" \
    | jget 'd["dimensions"]["dim3"]["locations"].count(";") + 1' 2>/dev/null || echo 0)
[ "$n" -ge 3 ] && ok "dim3 reports the COMPLETE violation set in one verdict ($n terms)" \
  || err "dim3 reported $n violations, expected the full set (>=3)"
python3 "$DP" quality-gate --draft "$work/vocab.md" | jget 'd["dimensions"]["dim3"]["verdict"]' | grep -q fail \
  && ok "uncalibrated vocabulary fails dim3 mechanically" || err "uncalibrated draft passed dim3"

# #305 — determinism: the same text yields a byte-identical verdict every run.
a=$(python3 "$DP" quality-gate --draft "$work/vocab.md" | jget 'd["dimensions"]["dim3"]["locations"]')
b=$(python3 "$DP" quality-gate --draft "$work/vocab.md" | jget 'd["dimensions"]["dim3"]["locations"]')
[ "$a" = "$b" ] && ok "dim3 verdict is deterministic across runs (no interpretation drift)" \
  || err "dim3 verdict drifted: '$a' vs '$b'"

# #305 — the audience allowlist enters ONCE as owner-ratified data.
python3 "$DP" quality-gate --draft "$work/vocab.md" \
  --audience-known "harvest,fact sheet,GATE,Stage 3" | jget 'd["dimensions"]["dim3"]["verdict"]' | grep -q pass \
  && ok "audience-known terms are excluded from the scan (--audience-known)" \
  || err "allowlisted terms still failed dim3"

# #305 — convergence: one revision addressing the complete set clears dim3.
cat > "$work/vocab-fixed.md" <<'MD'
---
slug: v
audience: en-practitioner
audience_id: en-practitioner
---
# T

The harvest (the step that gathers source-pointed facts) fed Stage 3 — the
framework-fill step — the GATE, which marks each required slot, and the fact
sheet, the list of those gathered facts, in turn.
MD
python3 "$DP" quality-gate --draft "$work/vocab-fixed.md" | jget 'd["dimensions"]["dim3"]["verdict"]' | grep -q pass \
  && ok "one revision addressing the complete set clears dim3 (convergence)" \
  || err "dim3 still failing after a complete revision — the loop cannot converge"

# #305 — WRAPPED GLOSS reproduction: prose wraps, so a term and the gloss that
# introduces it straddle a line break. A line-based scan calls the gloss absent
# and manufactures a false violation. Asserted explicitly (not only via the
# convergence case) so unwrapping that fixture can never silently drop it.
printf -- '---\nslug: w\naudience: en-practitioner\naudience_id: en-practitioner\n---\n# T\n\nThe fact\nsheet, the list of gathered claims, fed Stage 3 — the framework-fill\nstep — without any trouble.\n' > "$work/wrapped.md"
python3 "$DP" quality-gate --draft "$work/wrapped.md" | jget 'd["dimensions"]["dim3"]["verdict"]' | grep -q pass \
  && ok "a gloss wrapped across a line break still introduces its term (no false violation)" \
  || err "wrapped gloss manufactured a false dim3 violation"

# #305 — the de-dup -> de-duplication reproduction: expanding an introduced
# abbreviation must NOT manufacture a fresh violation (contract rule 6).
cat > "$work/dedup.md" <<'MD'
---
slug: d
audience: en-practitioner
audience_id: en-practitioner
---
# T

The de-dup, which suppresses any question the facts already answer, ran first.
Later the de-duplication check ran again over the revised set of questions.
MD
python3 "$DP" quality-gate --draft "$work/dedup.md" | jget 'd["dimensions"]["dim3"]["verdict"]' | grep -q pass \
  && ok "expanding an introduced abbreviation does not re-promote it (de-dup case)" \
  || err "de-dup -> de-duplication check manufactured a violation"

# #305 — a heading occurrence is NEUTRAL: it neither introduces nor uses.
printf -- '---\nslug: h\naudience: en-practitioner\n---\n## The harvest step\n\nNothing else is said here at all.\n' > "$work/heading.md"
python3 "$DP" quality-gate --draft "$work/heading.md" | jget 'd["dimensions"]["dim3"]["verdict"]' | grep -q pass \
  && ok "a heading occurrence is neutral (neither introduction nor use)" \
  || err "a heading-only term failed dim3"

# Story 13.41 — audience presence is a stage-progression precondition: a draft
# with an unfilled (or absent) `audience` fails the gate mechanically.
sed 's/^audience:.*/audience: {audience}/' "$work/good.md" > "$work/noaud.md"
python3 "$DP" quality-gate --draft "$work/noaud.md" --map "$work/good-map.txt" --judge "$work/judge-pass.txt" >/dev/null 2>&1 \
  && err "an unfilled audience passed the gate" \
  || ok "an unfilled audience fails the gate (stage-progression precondition)"
# Story 13.71: audience_id presence is gated identically — never inferred later.
sed 's/^audience_id:.*/audience_id: {audience_id}/' "$work/good.md" > "$work/noaudid.md"
python3 "$DP" quality-gate --draft "$work/noaudid.md" --map "$work/good-map.txt" --judge "$work/judge-pass.txt" >/dev/null 2>&1 \
  && err "an unfilled audience_id passed the gate" \
  || ok "an unfilled audience_id fails the gate (13.71)"
python3 "$DP" quality-gate --draft "$work/noaud.md" --map "$work/good-map.txt" --judge "$work/judge-pass.txt" \
  | jget '"audience" in d["failing_dimensions"]' | grep -q True \
  && ok "the audience precondition is named in failing_dimensions" || err "audience failure not named"

# SKILL contract: precondition wording, mechanical dim4 + judged dims1-3,
# bounded ≤2 cycles re-running both gates, publish blocker, NFR12.
grep -qi 'stage-progression precondition' "$SKILL" && ok "SKILL: gate is a stage-progression precondition" || err "SKILL missing precondition wording"
grep -qi 'mechanically' "$SKILL" && grep -qi 'single-pass' "$SKILL" \
  && grep -qi 'Dimensions 1–2' "$SKILL" && grep -qi 'Dimension 3 is mechanical' "$SKILL" \
  && ok "SKILL: dims 3+4 mechanical, dims 1-2 single-pass judge (#305)" || err "SKILL missing gate composition"
grep -qi 'Dimensions 1–2 are judged' "skills/draft-article/quality-rubric.md" \
  && ok "rubric: states the judged/mechanical split (dims 1-2 judged)" || err "rubric missing the split"
grep -qi -- '--audience-known' "$SKILL" \
  && ok "SKILL: the audience allowlist is passed once, from the ratified answer" \
  || err "SKILL missing --audience-known wiring"
grep -qi 'advisory' "$SKILL" \
  && ok "SKILL: a judge dim3 line is advisory, never a gate verdict" \
  || err "SKILL missing the dim3-advisory rule"
grep -qiE '2 revision cycles|at most 2' "$SKILL" && ok "SKILL: at most 2 revision cycles" || err "SKILL missing the retry bound"
grep -qi 'verify-provenance' "$SKILL" && grep -qi 're-run' "$SKILL" && ok "SKILL: revision re-runs both rubric and verify-provenance" || err "SKILL missing both-gates re-run"
grep -qi 'publish blocker' "$SKILL" && ok "SKILL: surviving failure surfaces as a publish blocker" || err "SKILL missing blocker surface"
grep -qi 'NFR12\|owner-approved content' "$SKILL" && ok "SKILL: owner-approved content never silently altered (NFR12)" || err "SKILL missing NFR12 protection"
# NFR13 extended to the CAP-7 rubric judge (#123): dims 1-3 judged in a fresh
# subagent that never saw the drafting turn, so the drafting context never grades
# its own rubric pass.
grep -qi 'fresh subagent that never saw the drafting turn' "$SKILL" \
  && grep -qi 'never grades its own rubric pass' "$SKILL" \
  && ok "SKILL: CAP-7 rubric judge runs in an isolated subagent (NFR13)" || err "SKILL missing rubric-judge isolation"

if [ "$fail" -eq 0 ]; then
  printf '\nAll quality-gate checks passed.\n'; exit 0
else
  printf '\nquality-gate checks FAILED.\n' >&2; exit 1
fi
