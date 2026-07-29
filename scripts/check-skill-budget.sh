#!/usr/bin/env sh
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

# --- Spec-document family (Story 20.15, #819) ---------------------------------
# Third axis of the per-file-class criterion (SPEC-writing-assistant,
# 2026-07-27 amendment): spec documents are measured in BYTES (~tokens =
# bytes/4), because a line ceiling is density-blind — the first offender is
# 88 KB in 144 lines and passes any line budget by an order of magnitude.
# The byte ceiling is a VISIBILITY instrument: a trip directs to a spec
# decision, never to compacting ratified amendment text.
SPEC_WARN_BYTES=36000   # ~9k tokens
SPEC_HARD_BYTES=72000   # ~18k tokens
# First offender at adoption (2026-07-27), RATCHETED — growth past
# adoption+slack FAILS; shrinkage ratchets the entry down.
# Format: "<path>:<bytes-at-adoption>", space-separated.
SPEC_RATCHETED="specs/spec-article-draft-pipeline/SPEC.md:45056"

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
RATCHETED="scripts/draft-pipeline.py:7297"   # adopted 2026-07-26
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
      err "$f is $n lines — GREW past its ratchet ($ratchet at adoption, +${RATCHET_SLACK_PCT}% slack = $limit) — move detail down or split the companion; never raise the ratchet to absorb growth (Story 20.14, #820)"
    elif [ "$n" -lt "$ratchet" ]; then
      warn "$f is $n lines (below its $ratchet ratchet) — ratchet DOWN: update the COMP_RATCHETED entry to $n so the gain is locked in"
    else
      ok "$f is $n lines (ratcheted companion outlier: <= $limit)"
    fi
  elif [ "$n" -gt "$COMP_HARD_LINES" ]; then
    err "$f is $n lines (> hard ceiling $COMP_HARD_LINES for skill companions) — split it or move detail to a spec (Story 20.14, #820)"
  elif [ "$n" -gt "$COMP_WARN_LINES" ]; then
    warn "$f is $n lines (> warning line $COMP_WARN_LINES, ceiling $COMP_HARD_LINES) — consider splitting before the ceiling forces it"
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

if [ "$fail" -eq 0 ]; then
  printf '\nAll skill-budget checks passed.\n'; exit 0
else
  printf '\nskill-budget checks FAILED.\n' >&2; exit 1
fi
