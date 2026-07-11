#!/usr/bin/env sh
# check-slot-skip-semantics.sh — verify per-slot skip semantics in the
# frameworks (Story 10.5). POSIX shell.
#
# Covers: CONVENTIONS defines the `[SKIP: <effect>]` vocabulary (AC1); every
# framework's interview-fed body slots and GATE slots declare a skip effect from
# that closed set (AC1); every GATE slot's effect is `blocker` (a GATE is never
# skipped away); and the SKILL applies the declared effect at stage 3 (AC2/AC3).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

FDIR="skills/draft-article/frameworks"
CONV="$FDIR/CONVENTIONS.md"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

EFFECTS="omit defer accept-later verify blocker"

# 1. CONVENTIONS defines the vocabulary (AC1).
for e in $EFFECTS; do
  grep -qE "\*\*$e\*\*|\b$e\b" "$CONV" || err "CONVENTIONS missing skip effect: $e"
done
grep -qi 'SKIP: <effect>' "$CONV" && ok "CONVENTIONS defines the [SKIP: <effect>] tag" || err "CONVENTIONS missing the SKIP tag syntax"
grep -qi "Every GATE slot's skip effect is .*blocker" "$CONV" && ok "CONVENTIONS: GATE slots are blocker" || err "CONVENTIONS missing GATE=blocker rule"

# 2. Every SKIP tag across the frameworks uses a valid effect (closed set).
badtags=$(grep -rhoE '\[SKIP: [a-z-]+\]' "$FDIR" | sed -E 's/\[SKIP: (.+)\]/\1/' | sort -u \
          | grep -vxE "$(echo $EFFECTS | tr ' ' '|')" || true)
if [ -z "$badtags" ]; then ok "all [SKIP:] tags use a valid effect"; else err "invalid skip effect(s): $badtags"; fi

# 3. Each framework declares skip effects on its slots, and EVERY GATE slot is blocker.
for f in F1-project-introduction F2-engineering-lessons F3-evaluation-methodology F4-research-survey; do
  file="$FDIR/$f.md"
  n=$(grep -cE '\[SKIP: [a-z-]+\]' "$file" || true)
  [ "$n" -ge 4 ] && ok "$f declares skip effects on its slots ($n)" || err "$f has too few skip declarations ($n)"
  # every GATE body slot line carries [SKIP: blocker]
  badgate=$(grep -nE '^## GATE \{' "$file" | grep -v '\[SKIP: blocker\]' || true)
  if [ -z "$badgate" ]; then ok "$f: every GATE slot is [SKIP: blocker]"; else err "$f GATE slot without blocker: $badgate"; fi
done

# 4. The closed vocabulary is actually exercised across the frameworks (each
#    effect appears at least once — the skip menu is meaningful, not one default).
for e in $EFFECTS; do
  grep -rqE "\[SKIP: $e\]" "$FDIR" && ok "effect '$e' is used by at least one slot" || err "effect '$e' never used"
done

# 5. The SKILL applies the declared slot effect at stage 3 (AC2/AC3).
grep -qi 'SKIP: <effect>' "$SKILL" && ok "SKILL reads the slot's [SKIP:] tag" || err "SKILL does not apply the slot skip tag"
grep -qi 'decides the consequence' "$SKILL" && grep -qi 'recorded only the skip disposition' "$SKILL" \
  && ok "SKILL: engine records disposition, framework decides effect" || err "SKILL missing the engine/framework split"

if [ "$fail" -eq 0 ]; then
  printf '\nAll slot skip-semantics checks passed.\n'; exit 0
else
  printf '\nslot skip-semantics checks FAILED.\n' >&2; exit 1
fi
