#!/bin/sh
# A served path that differs from the requested one is ANNOUNCED, never
# re-cited (SPEC-terrain CAP-4, amended 2026-07-29; Story 20.29, #873).
#
# Why this check exists at all: in this failure nothing is missing. The wrong
# thing arrives and reads as the right one, so no absence-shaped check fires.
# The cite used to be recomposed from the requested topic key, which made the
# substitution unobservable — archived decisions displayed as the live record
# for days, and the consumer reported the gap as an upstream fix that had
# "landed". Detection is therefore the CONSUMER's own and is never conditional
# on an upstream version or on a claim that a fix shipped.
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

python3 - "scripts/terrain_map.py" "scripts/topic-map-directions.py" \
         "scripts/terrain_text.py" <<'PYEOF' || fail=1
import importlib.util, sys

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

tm = load("tm", sys.argv[1])
di = load("di", sys.argv[2])
# The disclosure primitives moved to their own leaf module (Story 20.58, #942).
# Asserted against THAT module's path, not through the composer's re-export:
# a symbol deleted from where it now lives must fail here.
tx = load("tx", sys.argv[3])

fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond:
        fail.append(msg)

# The real served shape: the reader's `=== <path> @ <sha>` header followed by
# `N: text` lines. This is an ARCHIVE answering a request for the live thread,
# which is exactly what the live gateway did (measured 2026-07-29).
SERVED = (
    "pin: hub@abc123\n"
    "=== topics/archive/claude-code-ops.md @ deadbee\n"
    "1: # claude-code-ops\n"
    "2: - 2026-07-01 — **An archived decision.** Its reasoning. "
    "(q_a/2026-07-01-x D1)\n"
)

els = tm.parse_topic_elements("claude-code-ops",
                              [("2", "- 2026-07-01 — **An archived decision.** "
                                     "Its reasoning. (q_a/2026-07-01-x D1)")],
                              "deadbee",
                              "topics/archive/claude-code-ops.md")
check(bool(els), "the served lines parse into an element")
cite = els[0]["situation"] if els else ""
check(cite.startswith("topics/archive/claude-code-ops.md:"),
      "the cite names the SERVED path, not one rebuilt from the topic key")
check("topics/claude-code-ops.md:" not in cite,
      "the requested path never stands in for the served one")

# Detection reaches the screen: the map carries the substitution, the screen
# announces it, and the affected row is marked.
sub = [{"requested": "topics/claude-code-ops.md",
        "served": "topics/archive/claude-code-ops.md"}]
mp = {"kind": "topic-map", "topics": [], "elements": [],
      "coverage": {"pin": "p1", "substitutions": sub}}
line = tx._substitution_disclosure_line(mp)
check(line is not None, "a substitution yields a disclosure line")
check("topics/archive/claude-code-ops.md" in line
      and "topics/claude-code-ops.md" in line,
      "the disclosure names BOTH the requested and the served path")
check("abnormal" in line.lower(),
      "the substitution is stated as an abnormal condition, not a tolerated gap")
check("\n" not in line and "##" not in line,
      "the disclosure is a line, never a section")

row = di._strand_context_line(
    {"situation": "topics/archive/claude-code-ops.md:2@deadbee",
     "tags": [], "evidence": ["x"]},
    "claude-code-ops", tx._substituted_paths(mp))
check("SUBSTITUTED SOURCE" in row,
      "material read from a substituted path is marked on its own row")

clean = {"kind": "topic-map", "topics": [], "elements": [],
         "coverage": {"pin": "p1", "substitutions": []}}
check(tx._substitution_disclosure_line(clean) is None,
      "the normal case says nothing — silence by detection, no flag to flip")
row_ok = di._strand_context_line(
    {"situation": "topics/claude-code-ops.md:2@deadbee",
     "tags": [], "evidence": ["x"]},
    "claude-code-ops", tx._substituted_paths(clean))
check("SUBSTITUTED" not in row_ok,
      "an unsubstituted row carries no marker")

sys.exit(1 if fail else 0)
PYEOF

# The accumulator must never drop a served surface (#873): two files resolving
# to one topic key extend, they do not assign.
grep -q 'by_topic.setdefault(current, \[\]).extend(' scripts/terrain_map.py \
  && ok "two served surfaces under one topic key EXTEND, never clobber" \
  || err "read_topic_elements assigns by_topic[current] — an earlier set is dropped silently"

# Detection is the consumer's own: no code path may gate it on an upstream
# version, flag, or claim that a fix has landed.
if grep -nE 'substitut' scripts/terrain_map.py scripts/topic-map-directions.py \
     | grep -qiE 'gateway_version|if .*fixed|upstream_ok'; then
  err "substitution detection is gated on an upstream claim — the failure it catches IS the false claim"
else
  ok "detection is unconditional — never gated on an upstream fix having landed"
fi

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll substituted-served-path checks passed.\n'
