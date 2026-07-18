#!/usr/bin/env sh
# check-quality-gate-delta.sh — verify the Stage 3->4 second-cycle DELTA
# re-check (Story 13.65, #349, SPEC-article-draft-pipeline CAP-7). POSIX shell.
#
# Covers: on cycle 2, a dim1/dim2 judge `fail` at a location cycle 1 never
# flagged is suppressed as interpretive drift (gate converges); a dim1/dim2
# fail at a cycle-1 location is NOT suppressed (a genuine unaddressed finding
# blocks); cycle 1 (default) is unchanged (any dim fail blocks); and a
# mechanical dimension (dim4) still raises a new finding on cycle 2.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# A clean draft + a well-mixed map (dim3/dim4/audience pass), so only the
# dim1/dim2 judge verdicts drive the gate.
cat > "$work/good.md" <<'MD'
---
slug: t
title: The one claim
language: en
audience: en-practitioner
---
# The one claim

Structured discovery halved our token bill. We measured it across the suite.
The mechanism was simple. Fewer redundant reads meant fewer prompt tokens.

## Evidence

The bench recorded a 2x drop. That number held across three runs.
MD
cat > "$work/map.txt" <<'MAP'
P1.S1: sourced <- fs-1
P1.S2: derived <- fs-1, fs-2
P1.S3: narration
P2.S1: sourced <- fs-3
MAP
Q() { python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/map.txt" "$@"; }

# A cycle-1 dim1 failure at a specific location.
printf 'dim1: fail [Section 2, para 3]\ndim2: pass\ndim3: pass\n' > "$work/judge-loc2.txt"
# A cycle-2 dim1 failure at a DIFFERENT location (fresh interpretive finding).
printf 'dim1: fail [Section 5, para 1]\ndim2: pass\ndim3: pass\n' > "$work/judge-loc5.txt"

# --- Cycle 1 (default): a dim1 fail blocks (unchanged behavior) --------------
Q --judge "$work/judge-loc2.txt" >/dev/null 2>&1 \
  && err "cycle 1: a dim1 fail did not block" || ok "cycle 1 (default): a dim1 fail blocks (unchanged)"

# --- Cycle 2: a NEW-location dim1 fail is suppressed (delta re-check) --------
out=$(Q --judge "$work/judge-loc5.txt" --cycle 2 --prior-locations "Section 2, para 3" 2>/dev/null || true)
printf '%s' "$out" | jget 'd["pass"]' | grep -q True \
  && ok "cycle 2: a dim1 fail at a NEW location is suppressed -> gate converges" \
  || err "cycle 2: new-location dim1 fail not suppressed"
printf '%s' "$out" | jget 'd["dimensions"]["dim1"]["verdict"]' | grep -q pass \
  && ok "cycle 2: the suppressed dim1 reads pass" || err "dim1 not flipped to pass"
printf '%s' "$out" | jget 'len(d["delta_recheck"]["suppressed_new_interpretive"])==1' | grep -q True \
  && ok "cycle 2: the suppression is recorded (auditable)" || err "suppression not recorded"
printf '%s' "$out" | jget '"cycle-1 locations as scope" in d["delta_recheck"]["note"]' | grep -q True \
  && ok "cycle 2: note states isolation preserved (locations as scope, not verdicts)" || err "isolation note missing"

# --- Cycle 2: a dim1 fail AT a cycle-1 location is NOT suppressed ------------
Q --judge "$work/judge-loc2.txt" --cycle 2 --prior-locations "Section 2, para 3" >/dev/null 2>&1 \
  && err "cycle 2: an unaddressed cycle-1 finding did not block" \
  || ok "cycle 2: a dim1 fail at a cycle-1 location is NOT suppressed (still blocks)"

# --- Cycle 2 with no prior-locations: falls back to full judging -------------
Q --judge "$work/judge-loc5.txt" --cycle 2 >/dev/null 2>&1 \
  && err "cycle 2 without prior-locations suppressed a fail" \
  || ok "cycle 2 with no prior-locations does not suppress (full judging)"

# --- Mechanical dim (dim4) still raises a new finding on cycle 2 -------------
# A wall-to-wall `sourced` map trips dim4's stitched-fact-sheet signature.
cat > "$work/stitched-map.txt" <<'MAP'
P1.S1: sourced <- fs-1
P1.S2: sourced <- fs-2
P1.S3: sourced <- fs-3
P2.S1: sourced <- fs-4
MAP
printf 'dim1: pass\ndim2: pass\ndim3: pass\n' > "$work/judge-pass.txt"
out=$(python3 "$DP" quality-gate --draft "$work/good.md" --map "$work/stitched-map.txt" \
  --judge "$work/judge-pass.txt" --cycle 2 --prior-locations "Section 2, para 3" 2>/dev/null || true)
printf '%s' "$out" | jget '"dim4" in d["failing_dimensions"]' | grep -q True \
  && ok "cycle 2: a mechanical dim (dim4) still raises a new finding (not suppressed)" \
  || err "cycle 2: mechanical dim4 was suppressed"

if [ "$fail" -eq 0 ]; then
  printf '\nAll quality-gate delta-recheck checks passed.\n'; exit 0
else
  printf '\nquality-gate delta-recheck checks FAILED.\n' >&2; exit 1
fi
