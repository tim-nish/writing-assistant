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
# The FULL tier has a fourth remedy, PARALLEL EXECUTION, and its licence is a
# per-check declaration that DEFAULTS TO UNSAFE (#957). `--tier full -P N` runs
# the checks that DECLARE parallel-safety concurrently (at most N at once), then
# runs the undeclared remainder serially. The declaration is one greppable
# header line in the check file — exactly `# parallel-safe` on its own line —
# the same declare-once-in-the-check shape as `# tier: full`, so a check and its
# concurrency classification cannot drift apart.
#
# THE DEFAULT POLARITY IS INVERTED AGAINST `tier:`, DELIBERATELY. `tier:`
# defaults to the *policed* value because its failure mode is a slow check
# hiding, and the ceiling flushes it out. Parallel-safety's failure mode is not
# slowness but NONDETERMINISTIC WRONGNESS — two checks colliding on
# ~/.config/writing-assistant/repos/<path> or the state root fail in a way that
# is worse than slow because it is not reproducible — so its default must be the
# SAFE value. An absent, misspelled, or commented-out header is NOT a
# declaration: it is never an error and never an inference, it is serial. Do not
# "make the two headers consistent"; the inversion is the load-bearing half.
# Adoption is declare-as-verified and incremental, per check, on its own
# verified isolation.
#
# The per-edit selector is a UNION of two selectors, not one (#998). The
# name-prefix family (#944) finds every check NAMED AFTER the thing being
# edited and no check that asserts a repo-wide property ABOUT it. Measured over
# one sitting, the scoped run was green three separate times and the full tier
# then failed on checks the prefix could never have selected —
# check-check-declarations, check-skill-budget, check-article-plan,
# check-resolved-default-inner — at ~110s a rerun. So a check may DECLARE the
# paths it asserts over, beside its `# tier:` and `# parallel-safe` headers:
#
#   # covers: <space-separated path globs>
#
# and `--changed PATHS` adds every check whose declaration matches any changed
# path to whatever the GLOB already selected. The declaration lives IN the
# check for the same reason the other two do: the person who knows what a check
# asserts is the person writing it, and a central map owes a precedence rule
# and a mismatch check it cannot promise.
#
# THE DEFAULT POLARITY MATCHES `parallel-safe`, NOT `tier:`: an UNDECLARED
# check COVERS NOTHING. It is selected by name-prefix only, never by coverage.
# That makes the map incomplete-but-HONEST while it is populated rather than
# authoritative-and-wrong, and nothing becomes unreachable — the full tier is
# still the single pre-PR gate and still runs everything. The incompleteness is
# REPORTED on every run (the `coverage-map:` line) so it is observable rather
# than silent. A `# covers:` line with no globs after it is an ERROR naming the
# file: an empty declaration is the one shape that reads as a claim and makes
# none. Globs are matched with `case`, so `*` crosses `/` — `skills/**` and
# `skills/*` both mean everything under `skills/`.
#
# Usage: run-checks.sh [--tier inner|full] [-P N] [--changed PATHS] [--list] [GLOB]
#   --tier inner   (default) the per-edit loop
#   --tier full    everything, once before gh pr create
#   -P N           FULL TIER ONLY: run declared-parallel-safe checks with at
#                  most N concurrent, then the undeclared remainder serially.
#                  Ignored for the inner tier — the per-edit remedy is scoping
#                  (#944), never concurrency. Without -P the full tier runs
#                  serially exactly as it always has.
#   --changed PATHS  space- or comma-separated changed paths (repeatable). Adds
#                  every check whose `# covers:` globs match one of them to the
#                  GLOB selection. Omit it and selection is EXACTLY the
#                  name-prefix family it has always been.
#   --list         print the selected checks and the coverage-map line, run
#                  nothing, exit 0. The selector is inspectable on its own.
#   GLOB           optional filter, e.g. 'scripts/check-terrain*' — the
#                  per-edit default should be the blast-radius family, not
#                  the whole suite (#944)
#
# The FULL tier declares TWO ceilings of its own, FULL_TOTAL_MS and
# FULL_WALL_MS (#961), and they REPORT on every full run rather than failing
# it. The runtime-budget family had bounded exactly one level of aggregation at
# a time and left the next one up unwatched twice in a week: INNER_MS bounded
# the member and the family total broke, INNER_TOTAL_MS bounded the family and
# the tier — the once-per-PR gate — was bounded by nothing. The two measure
# different things and neither alone is sufficient:
#   FULL_TOTAL_MS  the SUM of per-check ELAPSED work, DECLARED AT A STATED
#                  CONCURRENCY (#1001). It is NOT concurrency-independent —
#                  that claim shipped here and was false: identical suite,
#                  452,419ms at -P 8 against 570,296ms at -P 14, a 26% move on
#                  the flag alone plus a breach that did not exist. Checks
#                  contend, so every member's elapsed inflates with -P. Summing
#                  CPU instead was tested and rejected: check-harvest measured
#                  5.35s CPU alone against 7.78s (+45%) under ten rivals, so
#                  NOTHING time-based is concurrency-independent here. It stays
#                  the GROWTH instrument, but only compared LIKE FOR LIKE: a
#                  run at another -P reports NOT COMPARABLE and is not checked.
#                  Changing FULL_TOTAL_P obliges re-measuring FULL_TOTAL_MS.
#   FULL_WALL_MS   real ELAPSED wall clock for the whole run. The cost actually
#                  paid once per PR: the EXPERIENCE instrument.
# Wall clock alone goes blind under parallelism (after #957 a new check filling
# an idle slot moves it by ~zero while the suite grows); summed work alone never
# reflects what anyone waits for and would not have registered #957's 3x win.
# NEITHER FAILS THE RUN, unlike the inner tier: a full-tier ceiling is a soft
# budget whose job is to make overage VISIBLE, and a failing one would block
# every PR the moment the suite drifted. Do not "make the tiers consistent" —
# report-not-fail is the load-bearing half here, as fail-on-breach is there.
#
# Exit: non-zero if any executed check fails, any inner-tier check breaks
# the per-check ceiling, or an unscoped inner run breaks the family total.
# A full-tier ceiling breach NEVER contributes to the exit status.
# Per-check runtime is printed always — disclosure is unconditional, not
# only on violation, and the two full-tier figures are disclosed the same way:
# on every full run, whether or not the ceiling is exceeded. Under -P each
# check's line is buffered and printed by the parent in glob order, so
# concurrent runs never interleave into one line.

INNER_MS=2000          # inner-tier per-check runtime ceiling (ms)
INNER_TOTAL_MS=15000   # inner-tier FAMILY ceiling for an unscoped run (ms) — #944
FULL_TIMEOUT_S=120     # hard stop for any single check, either tier
FULL_TOTAL_MS=480000   # full-tier ceiling on SUMMED per-check work (ms) — #961, REPORTS ONLY
FULL_TOTAL_P=8         # the -P this ceiling was measured at (#1001). Summed
                       # elapsed inflates with concurrency, so the figure is
                       # comparable only at this value; any other -P reports
                       # NOT COMPARABLE. Re-measure if this changes.
FULL_WALL_MS=120000    # full-tier ceiling on ELAPSED wall clock (ms) — #961, REPORTS ONLY

# Wall clock starts HERE, and the reported figure is the difference against a
# second real timestamp taken at the end (#961). It is never derived from
# total_ms: under -P the two diverge — 425,421ms of summed work against 1m44s
# elapsed, measured at -P 8 — and a "wall" computed from the sum would be blind
# to concurrency, which is the whole defect FULL_WALL_MS exists to catch.
run_t0=$(date +%s%N)

TIER=inner
PARALLEL=0
CHANGED=''
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="$2"; shift 2 ;;
    -P) PARALLEL="$2"; shift 2 ;;
    --changed) CHANGED="$CHANGED $(printf '%s' "$2" | tr ',' ' ')"; shift 2 ;;
    --list) LIST=1; shift ;;
    *) break ;;
  esac
done
SCOPED=yes
[ $# -eq 0 ] && SCOPED=no
GLOB="${1:-scripts/check-*}"

case "$TIER" in inner|full) ;; *) echo "run-checks: unknown tier '$TIER'" >&2; exit 2 ;; esac
case "$PARALLEL" in ''|*[!0-9]*) echo "run-checks: -P wants a non-negative integer" >&2; exit 2 ;; esac
# AC3: -P has no effect on the inner tier, with or without a GLOB.
[ "$TIER" = "full" ] || PARALLEL=0

# --- coverage declarations (#998) --------------------------------------------
# covers_of FILE — the declared globs, or empty. The line must begin `# covers:`
# at column 0, the same greppable shape as `# tier:` and `# parallel-safe`; the
# first such line wins. `## covers:` and `# covers :` are not declarations.
covers_of() {
  grep -m1 -E '^# covers:' "$1" 2>/dev/null | sed -E 's/^# covers:[[:space:]]*//; s/[[:space:]]+$//'
}

# The universe the coverage selector draws from, and the undeclared count the
# runner discloses. Both are computed over the whole suite, never over GLOB —
# a coverage hit is exactly the case the name-prefix family missed.
undeclared=0; declared_n=0
for cov_f in scripts/check-*; do
  [ -f "$cov_f" ] || continue
  case "$cov_f" in *run-checks.sh) continue ;; esac
  if grep -m1 -E '^# covers:' "$cov_f" >/dev/null 2>&1; then
    if [ -z "$(covers_of "$cov_f")" ]; then
      echo "run-checks: $cov_f: malformed '# covers:' declaration — the header carries no path glob; name at least one, or delete the line (#998)" >&2
      exit 2
    fi
    declared_n=$((declared_n + 1))
  else
    undeclared=$((undeclared + 1))
  fi
done

# covers_match FILE — true when one of FILE's declared globs matches one of the
# changed paths. An undeclared check never matches: covers_of is empty, the
# loop body never runs, and the function returns false.
# `set -f` is load-bearing, not tidiness: without it the shell PATHNAME-EXPANDS
# the declared globs and the changed paths while splitting them into the `for`
# lists, so `# covers: scripts/check-*` would arrive as 152 literal filenames
# and match nothing. Globbing is restored before returning, because the
# selection loops below rely on it.
covers_match() {
  set -f
  for cov_g in $(covers_of "$1"); do
    for cov_p in $CHANGED; do
      case "$cov_p" in $cov_g) set +f; return 0 ;; esac
    done
  done
  set +f
  return 1
}

# The selection: the GLOB expansion in its existing order (selector (a)), then
# every coverage hit not already in it (selector (b)). With no --changed, FILES
# is byte-for-byte the list the runner has always built.
FILES=''
for f in $GLOB; do
  [ -f "$f" ] || continue
  case "$f" in *run-checks.sh) continue ;; esac
  FILES="$FILES $f"
done
UNION_ADDED=0
if [ -n "$CHANGED" ]; then
  for f in scripts/check-*; do
    [ -f "$f" ] || continue
    case "$f" in *run-checks.sh) continue ;; esac
    case " $FILES " in *" $f "*) continue ;; esac
    if covers_match "$f"; then
      FILES="$FILES $f"
      UNION_ADDED=$((UNION_ADDED + 1))
    fi
  done
fi

coverage_line="run-checks: coverage-map: ${declared_n} check(s) declare '# covers:', ${undeclared} undeclared (selected by name-prefix only) (#998)"

if [ "$LIST" -eq 1 ]; then
  for f in $FILES; do echo "$f"; done
  echo "$coverage_line"
  echo "run-checks: selected=$(set -- $FILES; echo $#) union-added=${UNION_ADDED}"
  exit 0
fi

fails=0; ran=0; skipped=0; total_ms=0

# report FILE MS RC — the single place a check's outcome becomes a line. Both
# the serial path and the parallel wave call it from the PARENT shell, so the
# counters it maintains are the run's counters and no two lines interleave.
report() {
  status=ok
  if [ "$3" -eq 124 ]; then status="TIMEOUT(${FULL_TIMEOUT_S}s)"; fails=$((fails+1))
  elif [ "$3" -ne 0 ]; then status="FAIL(rc=$3)"; fails=$((fails+1))
  fi
  if [ "$TIER" = "inner" ] && [ "$2" -gt "$INNER_MS" ]; then
    status="$status TIER-VIOLATION: ${2}ms > ${INNER_MS}ms — declare '# tier: full' or make the assertion fixture-based"
    fails=$((fails+1))
  fi
  printf '%6sms  %-8s %s\n' "$2" "$status" "$1"
  ran=$((ran+1))
  total_ms=$((total_ms + $2))
}

# is_parallel_safe FILE — an AFFIRMATIVE declaration only. The line must be
# exactly `# parallel-safe` (trailing blanks tolerated). `## parallel-safe`,
# `# parallel-safe: yes`, `# not parallel-safe` and a typo are all NOT
# declarations, and all mean serial.
is_parallel_safe() {
  grep -m1 -E '^# parallel-safe[[:space:]]*$' "$1" >/dev/null 2>&1
}

if [ "$PARALLEL" -gt 0 ]; then
  # --- full tier, parallel wave + serial remainder -------------------------
  wave=''; rest=''
  for f in $FILES; do
    if is_parallel_safe "$f"; then wave="$wave $f"; else rest="$rest $f"; fi
  done

  if [ -n "$wave" ]; then
    tmpd=$(mktemp -d "${TMPDIR:-/tmp}/run-checks.XXXXXX") || exit 2
    trap 'rm -rf "$tmpd"' EXIT INT TERM
    # A FIFO holding N tokens is the concurrency bound: the parent takes a
    # token before spawning and each child returns its own on exit, so at most
    # N run at once and a finished check frees its slot immediately (a batched
    # `wait` would stall the whole wave behind the slowest member of a batch).
    mkfifo "$tmpd/sem" || exit 2
    exec 9<>"$tmpd/sem"
    i=0
    while [ "$i" -lt "$PARALLEL" ]; do printf 'x\n' >&9; i=$((i+1)); done

    n=0
    for f in $wave; do
      n=$((n+1))
      read -r _tok <&9
      (
        c0=$(date +%s%N)
        timeout "$FULL_TIMEOUT_S" sh "$f" >/dev/null 2>&1
        crc=$?
        c1=$(date +%s%N)
        printf '%s %s\n' "$(( (c1 - c0) / 1000000 ))" "$crc" > "$tmpd/r.$n"
        printf 'x\n' >&9
      ) &
    done
    wait

    n=0
    for f in $wave; do
      n=$((n+1))
      if [ -s "$tmpd/r.$n" ]; then
        IFS=' ' read -r ms rc < "$tmpd/r.$n"
      else
        ms=0; rc=125   # the worker itself died — a failure, never a silent pass
      fi
      report "$f" "$ms" "$rc"
    done
  fi

  for f in $rest; do
    t0=$(date +%s%N)
    timeout "$FULL_TIMEOUT_S" sh "$f" >/dev/null 2>&1
    rc=$?
    t1=$(date +%s%N)
    report "$f" "$(( (t1 - t0) / 1000000 ))" "$rc"
  done
else
  for f in $FILES; do
    declared=$(grep -m1 -E '^# tier: full' "$f" >/dev/null 2>&1 && echo full || echo inner)
    if [ "$TIER" = "inner" ] && [ "$declared" = "full" ]; then
      skipped=$((skipped+1)); continue
    fi
    t0=$(date +%s%N)
    timeout "$FULL_TIMEOUT_S" sh "$f" >/dev/null 2>&1
    rc=$?
    t1=$(date +%s%N)
    report "$f" "$(( (t1 - t0) / 1000000 ))" "$rc"
  done
fi

# The family ceiling binds an unscoped run, and it binds a UNION run too
# (#998). The scoped exemption above rests on a blast-radius run being bounded
# by its family SIZE; coverage-selected members are not in the family and are
# bounded by nothing but the declared globs, so the ceiling is what keeps a
# too-broad glob visible. A union that routinely breaches it means the globs
# are too broad — that is a finding, never a reason to raise the ceiling.
if [ "$TIER" = "inner" ] && { [ "$SCOPED" = "no" ] || [ "$UNION_ADDED" -gt 0 ]; } && [ "$total_ms" -gt "$INNER_TOTAL_MS" ]; then
  echo "run-checks: FAMILY-VIOLATION: inner run ${total_ms}ms > ${INNER_TOTAL_MS}ms (#944)" >&2
  echo "  — scope the per-edit run to the blast-radius family (e.g. run-checks.sh 'scripts/check-terrain*')," >&2
  echo "    narrow a too-broad '# covers:' glob (#998) — never raise the ceiling," >&2
  echo "    declare slow members '# tier: full', or make their assertions fixture-based." >&2
  echo "    The full suite still runs unscoped once, pre-PR: run-checks.sh --tier full" >&2
  fails=$((fails+1))
fi
par_note=''
[ "$PARALLEL" -gt 0 ] && par_note=" parallel=$PARALLEL"
union_note=''
[ "$UNION_ADDED" -gt 0 ] && union_note=" union-added=$UNION_ADDED"
echo "run-checks: tier=$TIER ran=$ran skipped=$skipped fails=$fails total=${total_ms}ms$par_note$union_note"
echo "$coverage_line"

# Full-tier budget disclosure (#961). Unconditional on a full run, and it never
# touches `fails` — a breach is a finding, not a red suite.
if [ "$TIER" = "full" ]; then
  run_t1=$(date +%s%N)
  wall_ms=$(( (run_t1 - run_t0) / 1000000 ))
  # The summed figure is comparable only at the concurrency it was declared
  # at (#1001). Serial runs (-P absent) are treated as -P 1.
  run_p=$PARALLEL; [ "$run_p" -gt 0 ] || run_p=1
  if [ "$run_p" -ne "$FULL_TOTAL_P" ]; then
    work_verdict="NOT COMPARABLE — ceiling is declared at -P ${FULL_TOTAL_P}, this run used -P ${run_p}; summed elapsed inflates with concurrency, so it is not checked"
  elif [ "$total_ms" -gt "$FULL_TOTAL_MS" ]; then
    work_verdict="OVER by $((total_ms - FULL_TOTAL_MS))ms — reported, not failing"
  else
    work_verdict="within, $((FULL_TOTAL_MS - total_ms))ms to spare"
  fi
  if [ "$wall_ms" -gt "$FULL_WALL_MS" ]; then
    wall_verdict="OVER by $((wall_ms - FULL_WALL_MS))ms — reported, not failing"
  else
    wall_verdict="within, $((FULL_WALL_MS - wall_ms))ms to spare"
  fi
  echo "run-checks: FULL-TIER BUDGET work=${total_ms}ms at -P ${run_p} / FULL_TOTAL_MS=${FULL_TOTAL_MS}ms at -P ${FULL_TOTAL_P} — ${work_verdict} (#961, #1001)"
  echo "run-checks: FULL-TIER BUDGET wall=${wall_ms}ms / FULL_WALL_MS=${FULL_WALL_MS}ms — ${wall_verdict} (#961)"
fi

[ "$fails" -eq 0 ]
