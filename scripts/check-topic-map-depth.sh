#!/usr/bin/env sh
# check-topic-map-depth.sh — the depth ESTIMATOR IS GONE (Story 20.7, #809).
#
# This suite used to exercise the estimator end to end: clustering, the
# evidence-density signal, the declared thresholds, the promotion predicate and
# the glance bar. All of it was derived PER SUBTOPIC, and the subtopic unit was
# abandoned — not tuned — after a dogfood run spent its whole budget to produce
# a single usable line.
#
# The file survives, rewritten to assert the ABSENCE, because deleting it would
# leave a reader who goes looking for the depth harness with a missing file,
# which reads as an oversight rather than as a decision. What it checks now is
# that the machinery is deleted rather than merely unreferenced.
#
# The positive assertions about what replaced it are NOT duplicated here:
#   * `check-topic-map.sh` — no estimator, no threshold plumbing, no
#     `--thresholds` flag, no shipped threshold declaration;
#   * `check-topic-map-screen.sh` — nothing depth-shaped reaches the View.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

M="scripts/topic-map.py"
D="scripts/topic-map-directions.py"

# 1. The estimator and its inputs are deleted from the assembler.
if python3 - "$M" <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
gone = ["def estimate_depth(", "def load_thresholds(", "def thresholds_path(",
        "def _glance(", "def cluster_subtopics(", "THRESHOLDS_FILE",
        "SUBTOPIC_KEYS", "depth_thresholds", "--thresholds"]
present = [g for g in gone if g in src]
assert not present, f"still present: {present}"
PYEOF
then ok "assembler: the estimator, its thresholds and the glance bar are deleted"
else err "depth machinery survives in topic-map.py"
fi

# 2. ...and from the rendering side.
if python3 - "$D" <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
gone = ["def _depth_line(", "DEPTH_PREDICATE_MARKER"]
present = [g for g in gone if g in src]
assert not present, f"still present: {present}"
PYEOF
then ok "directions: the depth line and the promotion-rule marker are deleted"
else err "depth rendering survives in topic-map-directions.py"
fi

# 3. The shipped threshold declaration goes with its only consumer.
if [ ! -f "config/topic-depth-thresholds.yaml" ]; then
  ok "the shipped threshold declaration is removed"
else
  err "config/topic-depth-thresholds.yaml survives its only consumer"
fi

# 4. NEGATIVE TEST: this suite must be able to fail. A rewritten-to-absence
#    check that cannot fire is a clean bill nobody earned — the same trap the
#    removal exists to avoid, one layer up.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'def estimate_depth(x):\n    return x\n' > "$tmp/probe.py"
if python3 - "$tmp/probe.py" >/dev/null 2>&1 <<'PYEOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
assert "def estimate_depth(" not in src
PYEOF
then err "the matcher does not detect a surviving estimator"
else ok "negative test: a file that still defines the estimator fails this matcher"
fi

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll topic-map depth checks passed (the estimator is absent, by design).\n'
