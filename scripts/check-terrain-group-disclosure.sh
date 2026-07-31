#!/bin/sh
# parallel-safe
# parallel-verified 2026-07-31 (#999) — the second of the two checks added
# 2026-07-30 with no declaration either way. Verified: one `mktemp -d` holds
# the fixture map and all three rendered claim states; the repo is only read;
# same concurrency-neutral cwd reliance as check-terrain-relay-fidelity.sh.
# check-terrain-group-disclosure.sh — Story 20.67 (#979/#980).
#
# A group's `in common:` line has THREE states — composed, explicitly no
# commonality, and not composed — and none of them may touch the grouping.
#
# #980 proposed a member cap for groups whose composed claim "exceeds what one
# in-common claim can honestly state". The cap was declined at triage on
# measurement: the ratified sectioning cap is 20% of PLACEMENTS, which for the
# reported run was 21 members, and the groups called oversized held 15 and 13.
# What the report actually found was the COMPOSER failing to state a
# commonality, so the remedy is disclosure — and the whole risk of a disclosure
# driven by prose quality is that it starts moving Strands. This check is the
# guard on that: the disclosure is rendering, and grouping stays navigation.
#
# tier: inner
# removal-signal: the `in common:` line stops being composed per group — if a
# later decision moves commonality out of the per-group rendering, or adopts
# subdivision on the degeneracy signal (the watch trigger #980 recorded), this
# check is asserting a shape that no longer exists and retires with it.

set -u
D="scripts/topic-map-directions.py"
fail=0
ok()  { echo "ok:   $1"; }
err() { echo "err:  $1" >&2; fail=1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 - "$work/map.json" <<'PYEOF'
import json, sys
tags = ["workflow", "agents", "architecture", "method"]
els = [{"id": f"E{i}", "slug": f"lesson-{i}", "title": f"Element {i}",
        "gloss": f"a distilled rule number {i}", "kind": "lesson",
        "tags": tags[: 2 + (i % 3)], "topic": "claude-code-ops",
        "path": f"topics/t{i}.md", "line": i,
        "journey_recorded": bool(i % 2)} for i in range(1, 13)]
json.dump({"kind": "topic-map", "topics": ["claude-code-ops"],
           "coverage": {"pin": "h@abc1234"}, "elements": els},
          open(sys.argv[1], "w"))
PYEOF

# THE COMPLETE RENDERING is what carries `in common:` lines. Story 20.84
# (#1038) put the size switch on the member path, and this fixture's member
# holds 12 Strands — over the screen budget — so the console is a summary and
# the claim states render in the View. The check follows the lines it is about
# to the surface that carries them; the three states, and the invariance of the
# grouping across them, are exactly as they were.
run() {  # $1 = --claims JSON or empty, $2 = out path
  if [ -n "$1" ]; then
    python3 "$D" view --map "$work/map.json" --tag workflow --claims "$1" \
      --out "$2" >/dev/null
  else
    python3 "$D" view --map "$work/map.json" --tag workflow --out "$2" >/dev/null
  fi
}

run '{"G1":"a stated commonality","G2":null}' "$work/mixed.md" 2>"$work/e" \
  || { err "view --claims failed: $(cat "$work/e")"; exit 1; }
run '{"G1":"a stated commonality","G2":"also stated"}' "$work/both.md" 2>/dev/null
run '{}'                                               "$work/none.md" 2>/dev/null

python3 - "$work/mixed.md" "$work/both.md" "$work/none.md" <<'PYEOF' || fail=1
import sys

def listing(p): return open(p, encoding="utf-8").read()

def sections(text):
    """(title, [row idents]) per section — the grouping, without any prose."""
    out, cur = [], None
    for line in text.splitlines():
        if line.startswith("## "):
            cur = (line.split("—", 1)[-1].strip(), [])
            out.append(cur)
        elif line.startswith("- **") and cur is not None:
            cur[1].append(line.split("**")[1])
    return out

mixed, both, none = (listing(p) for p in sys.argv[1:4])

# THE THREE STATES ARE DISTINCT — a composer that tried and found nothing is
# not the same as one that was never asked.
lines = [l for l in mixed.splitlines() if l.startswith("in common:")]
composed = [l for l in lines if "a stated commonality" in l]
degenerate = [l for l in lines if "no single commonality found" in l]
absent = [l for l in listing(sys.argv[3]).splitlines()
          if l.startswith("in common:") and "not composed" in l]
for name, got in (("composed", composed), ("no-commonality", degenerate),
                  ("not-composed", absent)):
    if not got:
        print(f"err:  the {name!r} claim state does not render", file=sys.stderr)
        raise SystemExit(1)
print("ok:   the three `in common:` states each render, and differ")

# AC3 — THE GROUPING IS IDENTICAL across every claim state. This is the whole
# point: the disclosure reports, it never restructures.
base = sections(both)
if not base or all(not ids for _, ids in base):
    print("err:  fixture produced no sections — the comparison below would "
          "pass vacuously", file=sys.stderr)
    raise SystemExit(1)
for name, text in (("no-commonality", mixed), ("not-composed", none)):
    if sections(text) != base:
        print(f"err:  the {name!r} state CHANGED the grouping (#980 AC3) — "
              f"a prose judgment moved a Strand", file=sys.stderr)
        print(f"        expected {base}\n        got      {sections(text)}",
              file=sys.stderr)
        raise SystemExit(1)
print(f"ok:   grouping identical across all three claim states "
      f"({len(base)} sections, {sum(len(i) for _, i in base)} placements)")
PYEOF

# AC4 — NO NEW CAP. The declined member cap must not reappear as a constant.
python3 - <<'PYEOF' && ok "the sectioning cap is unchanged — no member cap was added" \
  || err "a sectioning threshold changed; the member cap was DECLINED (#980)"
import importlib.util as u
s = u.spec_from_file_location("m", "scripts/terrain_members.py")
m = u.module_from_spec(s); s.loader.exec_module(m)
assert m.SECTION_SHARE_CAP == 0.2, m.SECTION_SHARE_CAP
assert m.SECTION_FLOOR == 3, m.SECTION_FLOOR
PYEOF

[ "$fail" -eq 0 ] && echo "scripts/check-terrain-group-disclosure.sh OK"
exit "$fail"
