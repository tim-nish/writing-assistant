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
# The family SUM is budgeted too (#944): INNER_MS polices members, and the
# 2026-07-30 measurement showed the class recurring through the aggregate —
# 91 inner checks all under the per-check ceiling summing to 51s per edit
# iteration, ~10-15 min of a 30-min sitting. A per-member ceiling with an
# unbudgeted total is budget-every-member-of-a-budgeted-command-family one
# level up: the total is the unbudgeted member. INNER_TOTAL_MS below is the
# family ceiling; an unscoped inner run exceeding it FAILS with the remedies
# named. Scoped runs (an explicit GLOB) are exempt from the TOTAL ceiling —
# scoping is itself the first remedy, and a blast-radius run is already
# bounded by its family size.
#
# Usage: run-checks.sh [--tier inner|full] [GLOB]
#   --tier inner   (default) the per-edit loop
#   --tier full    everything, once before gh pr create
#   GLOB           optional filter, e.g. 'scripts/check-terrain*' — the
#                  per-edit default should be the blast-radius family, not
#                  the whole suite (#944)
#
# Exit: non-zero if any executed check fails, any inner-tier check breaks
# the per-check ceiling, or an unscoped inner run breaks the family total.
# Per-check runtime is printed always — disclosure is unconditional, not
# only on violation.

INNER_MS=2000          # inner-tier per-check runtime ceiling (ms)
INNER_TOTAL_MS=15000   # inner-tier FAMILY ceiling for an unscoped run (ms) — #944
FULL_TIMEOUT_S=120     # hard stop for any single check, either tier

TIER=inner
case "$1" in
  --tier) TIER="$2"; shift 2 ;;
esac
SCOPED=yes
[ $# -eq 0 ] && SCOPED=no
GLOB="${1:-scripts/check-*}"

case "$TIER" in inner|full) ;; *) echo "run-checks: unknown tier '$TIER'" >&2; exit 2 ;; esac

fails=0; ran=0; skipped=0; total_ms=0
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
  total_ms=$((total_ms + ms))
done

if [ "$TIER" = "inner" ] && [ "$SCOPED" = "no" ] && [ "$total_ms" -gt "$INNER_TOTAL_MS" ]; then
  echo "run-checks: FAMILY-VIOLATION: unscoped inner run ${total_ms}ms > ${INNER_TOTAL_MS}ms (#944)" >&2
  echo "  — scope the per-edit run to the blast-radius family (e.g. run-checks.sh 'scripts/check-terrain*')," >&2
  echo "    declare slow members '# tier: full', or make their assertions fixture-based." >&2
  echo "    The full suite still runs unscoped once, pre-PR: run-checks.sh --tier full" >&2
  fails=$((fails+1))
fi
echo "run-checks: tier=$TIER ran=$ran skipped=$skipped fails=$fails total=${total_ms}ms"
[ "$fails" -eq 0 ]
