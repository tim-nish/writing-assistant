#!/usr/bin/env sh
# tier: full — reads the SERVED CORPUS (terrain_map.strand_entries), so it is
#   seam/corpus-dependent by construction. Measured 2026-07-30: ~1.0s, which
#   alone pushed check-terrain-code-inner.sh from 1.25s to 2.2s and tripped the
#   INNER_MS ceiling (#913). Not the 30-second class, and the reason it cannot
#   be a unit-level assertion today is stated in the removal signal below.
# removal-signal: the committed fixture map (scripts/fixtures/terrain/
#   screen-map.json) carries journey material — it holds journey_renderings: 0
#   and journeys_requested: [] today, which is why a fixture version of this
#   assertion would be VACUOUS rather than cheap. Story 20.57 (#940) makes the
#   fixture exercise every declared capability; when it lands, this assertion
#   folds back into check-terrain-code-inner.sh's fixture block and this file
#   is deleted. Removed with that story.
# check-terrain-split.sh — the lessons/journeys split has a guard, because it
# had none (Story 20.51 AC7, #933).
#
# Why this exists as its own member: ALL FOUR terrain checks passed while a
# change moved 109 of 117 served lesson renderings out of the lessons lookup.
# The split at scripts/terrain_map.py was exercised by nothing, so the trap
# that stopped this story's first implementation attempt stayed armed. This
# asserts count-in == count-out over it — the shape the suite already uses for
# composed Strands.
#
# POSIX sh + stdlib Python, like every check-*.sh sibling.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/terrain_map.py"
fail=0

python3 - "$M" <<'PYEOF' || fail=1
import importlib.util, sys
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)
spec = importlib.util.spec_from_file_location("tm", sys.argv[1])
tm = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(tm)
except SystemExit:
    pass
by_file, strands, reason = tm.strand_entries(".")
entries = [e for _rel, parsed in by_file for e in parsed]
if not entries:
    # Reported DISTINCTLY: an unexercised precondition is neither a pass nor a
    # failure. A silent pass here is the #933 failure mode exactly.
    print(f"precondition: no records served here — split guard NOT exercised "
          f"({reason})", file=sys.stderr)
else:
    # The routing the gloss read performs, reproduced exactly.
    lessons = [e for e in entries if not e["journey"]]
    arcs = [e for e in entries if e["journey"]]
    check(len(lessons) == len(entries) and not arcs,
          f"every served lesson rendering lands in the lessons lookup — "
          f"count-in == count-out ({len(lessons)}/{len(entries)}, {len(arcs)} misrouted)")
    # And presence is carried, separately from that discriminator.
    rec = sum(1 for e in entries if e.get("journey_recorded"))
    ptr = sum(1 for e in entries if e.get("journey_shard") is not None)
    check(any(e.get("journey_recorded") for e in entries),
          f"journey presence reaches the composed entries ({rec} of {len(entries)})")
    check(rec >= ptr,
          f"presence is record-based, never narrower than pointer resolution "
          f"({rec} recorded vs {ptr} resolving)")
sys.exit(1 if fail else 0)
PYEOF

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
