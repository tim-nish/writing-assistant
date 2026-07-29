#!/usr/bin/env sh
# run-checks.sh — the tiered check runner (#913): validation checks are a
# budgeted family on the RUNTIME axis, and this runner is where the family's
# thresholds are declared (the same declare-once-in-the-enforcement pattern as
# PY_HARD_LINES in check-skill-budget.sh).
#
# Two tiers:
#   inner  — the per-edit tier. Runs every check NOT carrying a `# tier: full`
#            header. An inner check exceeding INNER_MS FAILS the run with the
#            fix named — a slow check silently absorbed by each sitting is the
#            defect class this runner exists to make visible (the 2026-07-29
#            investigation measured a 34.3s check inside the edit loop, paid
#            per iteration and reported by nobody).
#   full   — the pre-PR tier. Runs everything: inner checks plus every check
#            declared `# tier: full` (end-to-end pipeline reruns, seam-invoking
#            scenario suites — legitimate once per sitting, never per edit).
#
# Declaring a check `tier: full` is one greppable header line near the top of
# the file: `# tier: full` (sh) — the declaration lives IN the check so the
# check and its tier cannot drift apart. Headerless checks are inner BY
# DEFAULT, deliberately: the runtime ceiling below polices the default, so a
# new slow check cannot hide in the inner tier — it fails its first inner run
# and the failure message names the two remedies (declare the tier, or make
# the assertion fixture-based).
#
# Usage: run-checks.sh [--tier inner|full] [GLOB]
#   --tier inner   (default) the per-edit loop
#   --tier full    everything, once before gh pr create
#   GLOB           optional filter, e.g. 'scripts/check-terrain*'
#
# Exit: non-zero if any executed check fails, or any inner-tier check breaks
# the runtime ceiling. Per-check runtime is printed always — disclosure is
# unconditional, not only on violation.

INNER_MS=2000          # inner-tier per-check runtime ceiling (ms)
FULL_TIMEOUT_S=120     # hard stop for any single check, either tier

TIER=inner
case "$1" in
  --tier) TIER="$2"; shift 2 ;;
esac
GLOB="${1:-scripts/check-*}"

case "$TIER" in inner|full) ;; *) echo "run-checks: unknown tier '$TIER'" >&2; exit 2 ;; esac

fails=0; ran=0; skipped=0
for f in $GLOB; do
  [ -f "$f" ] || continue
  case "$f" in *run-checks.sh) continue ;; esac
  declared=$(grep -m1 -E '^# tier: full' "$f" >/dev/null 2>&1 && echo full || echo inner)
  if [ "$TIER" = "inner" ] && [ "$declared" = "full" ]; then
    skipped=$((skipped+1)); continue
  fi
  t0=$(date +%s%N)
  timeout "$FULL_TIMEOUT_S" sh "$f" >/dev/null 2>&1
  rc=$?
  t1=$(date +%s%N)
  ms=$(( (t1 - t0) / 1000000 ))
  status=ok
  if [ "$rc" -eq 124 ]; then status="TIMEOUT(${FULL_TIMEOUT_S}s)"; fails=$((fails+1))
  elif [ "$rc" -ne 0 ]; then status="FAIL(rc=$rc)"; fails=$((fails+1))
  fi
  if [ "$TIER" = "inner" ] && [ "$ms" -gt "$INNER_MS" ]; then
    status="$status TIER-VIOLATION: ${ms}ms > ${INNER_MS}ms — declare '# tier: full' or make the assertion fixture-based"
    fails=$((fails+1))
  fi
  printf '%6sms  %-8s %s\n' "$ms" "$status" "$f"
  ran=$((ran+1))
done

echo "run-checks: tier=$TIER ran=$ran skipped=$skipped fails=$fails"
[ "$fails" -eq 0 ]
