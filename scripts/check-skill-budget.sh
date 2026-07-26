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
# recorded follow-up (story 19.3's story-question: harvest/review-article
# follow after the ceiling lands). A grandfathered file WARNS instead of
# failing; remove its entry when its split lands. New skills never enter
# this list — the wall binds everything born after it.
GRANDFATHERED="skills/review-article/SKILL.md"   # 904 lines at adoption, 2026-07-26

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

if [ "$fail" -eq 0 ]; then
  printf '\nAll skill-budget checks passed.\n'; exit 0
else
  printf '\nskill-budget checks FAILED.\n' >&2; exit 1
fi
