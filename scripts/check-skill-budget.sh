#!/usr/bin/env sh
# parallel-safe
# covers: skills/** specs/**
# (specs/** is what selects this check on an edit to any specs/**/amendments*.md
#  path — the amendment-history class below is asserted over from here, so the
#  declaration must stay at least this wide; Story 20.88, #1046.)
# check-skill-budget.sh — mechanical skill-size ceiling (Story 19.4, #761;
# umbrella #744/#740). The packaging invariant
# (specs/spec-writing-assistant/SPEC.md, 2026-07-26 amendment) says a SKILL.md
# is a dispatcher whose operating detail lives in companion stage files; the
# regrowth pressure is process (commits append, none remove), so the ceiling
# is a wall at authoring time — this check fails the PR that grows a skill
# past it, instead of a later audit noticing.
#
# POSIX shell + coreutils only, like every check-*.sh sibling.

set -eu

# The two budgets, declared once here — code is the single enforcement copy;
# the spec states the invariant, never a number to keep in sync.
WARN_LINES=400   # over this: named, not failing (headroom for the dispatcher)
HARD_LINES=600   # over this: FAIL — split per the packaging invariant

# Grandfathered debt — DECLARED, dated, and shrinking, never silent: files
# over the hard ceiling at the moment the wall was built, whose split is the
# recorded follow-up. A grandfathered file WARNS instead of failing; remove
# its entry when its split lands. New skills never enter this list — the wall
# binds everything born after it. Empty since 2026-07-27: review-article's
# split landed (story 20.13, #818), the last entry retired with it.
GRANDFATHERED=""

# --- Companion family (Story 20.14, #820) ------------------------------------
# Same class of prompt payload as the dispatcher, loaded on entry to its
# phase/stage: every skills/**/*.md except the SKILL.md dispatchers. The
# dispatcher split relocates operating detail here, so an uncapped companion
# is where the #740/#744 regrowth pressure goes next. Same axes as SKILL.md.
COMP_WARN_LINES=400
COMP_HARD_LINES=600
# First offenders at adoption (2026-07-27), RATCHETED like the py outlier —
# growth past adoption+slack FAILS; shrinkage ratchets the entry down.
# Format: "<path>:<lines-at-adoption>", space-separated.
COMP_RATCHETED="skills/draft-article/stages/stage0.md:731 skills/draft-article/stages/stage2.md:705 skills/draft-article/stages/stage3.md:603"

# THE LINE COUNT IS A PROXY, AND THIS CHECK NAMES WHAT IT STANDS FOR (#1199).
# The property that matters is whether a file has absorbed more content than
# its structure carries — whether a reader or an agent can still navigate it.
# That is not mechanically decidable, so a line count stands in for it, and a
# proxy must name the property it proxies or it silently becomes the target.
#
# CONSEQUENCE, STATED BECAUSE IT HAS ALREADY HAPPENED: this count is
# satisfiable by REFORMATTING. Story 20.135 (#1178) needed a clause in
# stage0.md, which sat at exactly its ratchet with zero headroom, and paid for
# it by appending to an existing line — net-zero lines, real content growth,
# fully disclosed and matching the file'"'"'s own convention (it already carries
# lines of 1269 and 1128 characters). Nothing was gamed; the instrument simply
# did not measure what it stands for.
#
# So the messages below say "may have absorbed content" and never "is too
# long", exactly so that shortening a line to duck the threshold is VISIBLY
# not a fix. A BYTE axis was considered and is not the answer either: a
# contributor at a byte ceiling compresses wording instead, and the report
# would still be true about size and silent about the property.

# --- Spec-document family (Story 20.15, #819) ---------------------------------
# Third axis of the per-file-class criterion (SPEC-writing-assistant,
# 2026-07-27 amendment): spec documents are measured in BYTES (~tokens =
# bytes/4), because a line ceiling is density-blind — the first offender is
# 88 KB in 144 lines and passes any line budget by an order of magnitude.
# The byte ceiling is a VISIBILITY instrument: a trip directs to a spec
# decision, never to compacting ratified amendment text.
#
# It applies to LIVE CONTRACT documents only. Amendment history is a separate
# class with its own axis — see the block below (Story 20.88, #1046).
SPEC_WARN_BYTES=36000   # ~9k tokens
SPEC_HARD_BYTES=72000   # ~18k tokens
# First offender at adoption (2026-07-27), RATCHETED — growth past
# adoption+slack FAILS; shrinkage ratchets the entry down.
# Format: "<path>:<bytes-at-adoption>", space-separated.
SPEC_RATCHETED="specs/spec-article-draft-pipeline/SPEC.md:31124"

# --- Amendment-history class (Story 20.88, #1046) -----------------------------
# Fourth axis of the per-file-class criterion, applied one level finer than the
# spec-document family above: an amendment companion is an APPEND-ONLY
# ratification record, not a live contract. The byte ceiling is a visibility
# instrument whose trip "directs to a spec decision" — but for history the only
# decision available is compaction, which Story 20.15 (#819) forbids in the same
# sentence the error string names it. So history leaves the ceiling entirely and
# gets its own axis: a threshold that schedules the MECHANICAL era split.
#
# CLASS MEMBERSHIP IS A NAMING RULE, NOT A LIST (AC2). A file is amendment
# history when its BASENAME matches `amendments*.md`, anywhere under specs/.
# The alternative considered was the `companions:` frontmatter key; it was
# rejected because nothing in skills/, scripts/ or commands/ parses that key
# today, so a frontmatter rule would make this check its first and only reader —
# a parser to maintain for a decision the filename already carries, and one that
# would silently exempt nothing (and mis-classify a suite that forgets the key).
# The basename convention holds for every companion that exists. A list of paths
# was rejected outright: a new spec suite would fall outside it in silence.
#
# WITHIN the class there are two states:
#   * the LIVE append target — basename exactly `amendments.md` — measured
#     against AMEND_ERA_BYTES below;
#   * a CLOSED era — `amendments-<something>.md`, already renamed by a past
#     split — reported and never re-cut. The rule is prospective: no already
#     relocated text moves (AC6).
#
# THE THRESHOLD IS DECLARED HERE AND NOWHERE ELSE (AC3) — the spec states the
# invariant, never a number to keep in sync. Derivation, so it is not a round
# number someone later "adjusts": one sitting appended 17.8 KB to
# spec-terrain/amendments.md (42,109 -> 59,929 B, 2026-07-31). Splitting at
# 46,000 leaves a full sitting of headroom below the 72,000 the class has now
# left, so the split is always SCHEDULED work rather than a ceiling breach
# discovered mid-commit — which is the cost #1046 was filed on. The figure
# appears nowhere under specs/ (AC3) — verified by grep at adoption.
AMEND_ERA_BYTES=46000

# --- Script-surface family (Story 20.1, #759) --------------------------------
# Same cost-typed class, second family: scripts/*.py. Thresholds sized from
# the 2026-07-26 distribution (next-largest after the outlier: terrain_map.py
# 1,612; the long tail <= ~1,300) so only genuine outliers trip.
PY_WARN_LINES=1400
PY_HARD_LINES=2000
# The outlier is RATCHETED, not warn-forever grandfathered (deliberately NOT
# the skill list's shape above): its entry records the line count at adoption
# plus 1% slack, and the check FAILS when the file GROWS past it — a 7,297-line
# monolith that keeps growing under a warning is the #740/#744 incident again.
# Shrinkage: when the file drops below the recorded count, update the entry
# (ratchet down). The remedy for a trip is the sanctioned split shape —
# per-stage command modules — which is a SPEC decision, not this check's:
# the check points, it never restructures.
# Format: "<path>:<lines-at-adoption>", space-separated.
RATCHETED="scripts/draft-pipeline.py:5344"   # adopted 2026-07-26
RATCHET_SLACK_PCT=1

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
warn(){ printf 'warn: %s\n' "$1"; }

found=0
for f in skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  found=1
  n=$(wc -l < "$f")
  if [ "$n" -gt "$HARD_LINES" ]; then
    case " $GRANDFATHERED " in
      *" $f "*)
        warn "$f is $n lines (> hard ceiling $HARD_LINES) — GRANDFATHERED at adoption; its dispatcher split is the recorded follow-up, and this entry is removed with it" ;;
      *)
        err "$f is $n lines (> hard ceiling $HARD_LINES) — move stage detail to companion files (the dispatcher + stage-file split, packaging invariant: specs/spec-writing-assistant/SPEC.md)" ;;
    esac
  elif [ "$n" -gt "$WARN_LINES" ]; then
    warn "$f is $n lines (> warning line $WARN_LINES, ceiling $HARD_LINES) — consider splitting before the ceiling forces it"
  else
    ok "$f is $n lines (within budget)"
  fi
done
[ "$found" -eq 1 ] || err "no skills/*/SKILL.md found — wrong root?"

# --- companion family loop (Story 20.14, #820) -------------------------------
compfound=0
for f in $(find skills -name '*.md' ! -name 'SKILL.md' | sort); do
  [ -f "$f" ] || continue
  compfound=1
  n=$(wc -l < "$f")
  ratchet=""
  for entry in $COMP_RATCHETED; do
    case "$entry" in
      "$f":*) ratchet="${entry##*:}" ;;
    esac
  done
  if [ -n "$ratchet" ]; then
    limit=$(( ratchet + ratchet * RATCHET_SLACK_PCT / 100 ))
    if [ "$n" -gt "$limit" ]; then
      err "$f may have ABSORBED CONTENT past what its structure carries — $n lines against its $ratchet ratchet (+${RATCHET_SLACK_PCT}% slack = $limit). Move detail down or split the companion; never raise the ratchet to absorb growth. NOTE: this count is satisfiable by reformatting (longer lines, tighter wording), which does not address what it stands for (Story 20.14, #820; #1199)"
    elif [ "$n" -lt "$ratchet" ]; then
      warn "$f is $n lines (below its $ratchet ratchet) — ratchet DOWN: update the COMP_RATCHETED entry to $n so the gain is locked in"
    else
      ok "$f is $n lines (ratcheted companion outlier: <= $limit)"
    fi
  elif [ "$n" -gt "$COMP_HARD_LINES" ]; then
    err "$f may have ABSORBED CONTENT past what its structure carries — $n lines, over the $COMP_HARD_LINES ceiling for skill companions. Split it or move detail to a spec; reformatting to fit the count is not a fix (Story 20.14, #820; #1199)"
  elif [ "$n" -gt "$COMP_WARN_LINES" ]; then
    warn "$f may be absorbing content past what its structure carries — $n lines, over the $COMP_WARN_LINES warning line (ceiling $COMP_HARD_LINES). Consider splitting before the ceiling forces it (#1199)"
  else
    ok "$f is $n lines (within budget)"
  fi
done
[ "$compfound" -eq 1 ] || err "no skill companion .md found — wrong root?"


# --- spec-document family loop (Story 20.15, #819) ----------------------------
specfound=0
for f in $(find specs -name '*.md' | sort); do
  [ -f "$f" ] || continue
  specfound=1
  b=$(wc -c < "$f")
  tok=$(( b / 4 / 1000 ))
  # Amendment-history class (Story 20.88, #1046): its own axis, never the
  # ceiling. Reported, never failed — the split is scheduled work, not wrong
  # work, and a red suite for scheduled work is what breakered a live sitting.
  case "${f##*/}" in
    amendments*.md)
      if [ "${f##*/}" != "amendments.md" ]; then
        ok "$f is $b bytes (~${tok}k tokens; amendment history, CLOSED era — off the spec ceiling by class, and never re-cut)"
      elif [ "$b" -gt "$AMEND_ERA_BYTES" ]; then
        warn "$f is $b bytes (~${tok}k tokens; amendment history past the era-split threshold $AMEND_ERA_BYTES) — the next act is MECHANICAL and is not a decision: rename this file to its own date range (amendments-<first>--<last>.md), open a fresh amendments.md beside it, and update the owning SPEC.md pointer. Ratified text is never compacted, and this never fails the run"
      else
        ok "$f is $b bytes (~${tok}k tokens; amendment history, within the era-split threshold $AMEND_ERA_BYTES)"
      fi
      continue ;;
  esac
  ratchet=""
  for entry in $SPEC_RATCHETED; do
    case "$entry" in
      "$f":*) ratchet="${entry##*:}" ;;
    esac
  done
  if [ -n "$ratchet" ]; then
    limit=$(( ratchet + ratchet * RATCHET_SLACK_PCT / 100 ))
    if [ "$b" -gt "$limit" ]; then
      err "$f is $b bytes (~${tok}k tokens) — GREW past its ratchet ($ratchet at adoption, +${RATCHET_SLACK_PCT}% slack = $limit). A trip is a SPEC decision about what the growth is made of — ratified amendment text is never compacted (Story 20.15, #819); never raise the ratchet to absorb growth"
    elif [ "$b" -lt "$ratchet" ]; then
      warn "$f is $b bytes (below its $ratchet ratchet) — ratchet DOWN: update the SPEC_RATCHETED entry to $b so the gain is locked in"
    else
      ok "$f is $b bytes (~${tok}k tokens; ratcheted spec outlier: <= $limit)"
    fi
  elif [ "$b" -gt "$SPEC_HARD_BYTES" ]; then
    err "$f is $b bytes (~${tok}k tokens; > hard ceiling $SPEC_HARD_BYTES for spec documents) — take a spec decision on the growth; ratified amendment text is never compacted (Story 20.15, #819)"
  elif [ "$b" -gt "$SPEC_WARN_BYTES" ]; then
    warn "$f is $b bytes (~${tok}k tokens; > warning line $SPEC_WARN_BYTES, ceiling $SPEC_HARD_BYTES) — growth worth watching"
  else
    ok "$f is $b bytes (~${tok}k tokens; within budget)"
  fi
done
[ "$specfound" -eq 1 ] || err "no specs/**/*.md found — wrong root?"

# --- scripts/*.py family (Story 20.1, #759) ----------------------------------
pyfound=0
for f in scripts/*.py; do
  [ -f "$f" ] || continue
  pyfound=1
  n=$(wc -l < "$f")
  ratchet=""
  for entry in $RATCHETED; do
    case "$entry" in
      "$f":*) ratchet="${entry##*:}" ;;
    esac
  done
  if [ -n "$ratchet" ]; then
    limit=$(( ratchet + ratchet * RATCHET_SLACK_PCT / 100 ))
    if [ "$n" -gt "$limit" ]; then
      err "$f is $n lines — GREW past its ratchet ($ratchet at adoption, +${RATCHET_SLACK_PCT}% slack = $limit). The sanctioned remedy is the per-stage command-module split (a spec decision — see #759); shrink the file or take that decision, never raise the ratchet to absorb growth"
    elif [ "$n" -lt "$ratchet" ]; then
      warn "$f is $n lines (below its $ratchet ratchet) — ratchet DOWN: update the RATCHETED entry to $n so the gain is locked in"
    else
      ok "$f is $n lines (ratcheted outlier: <= $limit; split shape is a spec decision, #759)"
    fi
  elif [ "$n" -gt "$PY_HARD_LINES" ]; then
    err "$f is $n lines (> hard ceiling $PY_HARD_LINES for scripts/*.py) — split it, or take a spec decision if the split alters packaging (Story 20.1, #759)"
  elif [ "$n" -gt "$PY_WARN_LINES" ]; then
    warn "$f is $n lines (> warning line $PY_WARN_LINES, ceiling $PY_HARD_LINES) — consider splitting before the ceiling forces it"
  else
    ok "$f is $n lines (within budget)"
  fi
done
[ "$pyfound" -eq 1 ] || err "no scripts/*.py found — wrong root?"

# --- check-suite slope (Story 20.48, #922; spec amendment #910/#913) --------
# The check family joins the packaging budget on its SLOPE, not its level: a
# count alone never fails the build — growth is what the instrument is for,
# and it is REPORTED so the between-sittings delta is observable. The measured
# defect this answers: 126 -> 132 -> 136 across two days, absorbed silently.
# The baseline is re-recorded whenever the slope is deliberately reviewed —
# never bumped just to quiet the warn line, which IS the instrument reading.
CHECK_SUITE_BASELINE=138       # recorded 2026-07-30 (Story 20.48 adoption)
CHECK_SUITE_BASELINE_DATE=2026-07-30
suite_n=$(ls scripts/check-*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$suite_n" -gt "$CHECK_SUITE_BASELINE" ]; then
  warn "check suite has grown: $suite_n checks, +$((suite_n - CHECK_SUITE_BASELINE)) since $CHECK_SUITE_BASELINE_DATE ($CHECK_SUITE_BASELINE) — slope is the instrument (never a failure); each new member declares its tier and removal signal (check-check-declarations.sh)"
elif [ "$suite_n" -lt "$CHECK_SUITE_BASELINE" ]; then
  ok "check suite: $suite_n checks, down $((CHECK_SUITE_BASELINE - suite_n)) since $CHECK_SUITE_BASELINE_DATE ($CHECK_SUITE_BASELINE) — consider re-recording the baseline to lock the reduction in"
else
  ok "check suite: $suite_n checks, flat since $CHECK_SUITE_BASELINE_DATE"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll skill-budget checks passed.\n'; exit 0
else
  printf '\nskill-budget checks FAILED.\n' >&2; exit 1
fi
