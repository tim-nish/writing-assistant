#!/bin/sh
# parallel-safe
# parallel-verified 2026-07-31 (#999) — one of the two checks added 2026-07-30
# that never declared either way, which is the omission #999's prevention half
# now turns into an error. Verified: a single `mktemp -d` holds the fixture map
# and every output; the repo is only read. It relies on cwd being the repo root
# (it names `scripts/topic-map-directions.py` relatively rather than resolving
# `git rev-parse`), and that is concurrency-neutral: run-checks.sh never `cd`s,
# and each check is a separate `sh` process inheriting the same cwd.
# check-terrain-relay-fidelity.sh — Story 20.66 (#976/#977).
#
# A Strand placed in more than one section renders the SAME ROW in every one of
# them, and an absence mark renders wherever the row does.
#
# The reported defects were not composition defects: the rows were already
# deterministic (the `no-journey` mark is added in `_strand_context_line`, which
# every expanded path calls), and it was the hand-relay between the script and
# the screen that reworded a headline (#976) and dropped a mark (#977). The
# remedy moved composition into the script, so this asserts the property that
# remedy is supposed to buy — stated over the SCRIPT'S OWN OUTPUT, which is the
# last artifact this repository controls.
#
# tier: inner
# covers: scripts/topic-map-directions.py
# removal-signal: screen 2 stops being composed by the script — if a
# future flow returns the relay to the presenting agent, this check is
# asserting a property nothing upstream still guarantees, and it retires
# with that flow rather than being repaired.
# covers-note (#1321): flag `sparse:1-paths/152-lines` RECORDED AS UNDERSTOOD-AND-NARROW.
#   The ratio is length, not hidden scope: this file carries one subject and no
#   `dynamic-path` flag beside the sparse one, which means the extractor found no variable
#   in path position it could not resolve. A long argument about one module is what it is.
#   (Placed BELOW removal-signal on purpose: check-check-declarations.sh reads only the
#   first 25 lines, so a note above it would push the declaration out of the window.)

set -u
D="scripts/topic-map-directions.py"
fail=0
ok()  { echo "ok:   $1"; }
err() { echo "err:  $1" >&2; fail=1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A map whose Strands carry several co-tags, so the co-tag substrate places one
# Strand under more than one section — the condition the defect needs.
python3 - "$work/map.json" <<'PYEOF'
import json, sys
tags = ["workflow", "agents", "architecture", "method"]
els = []
for i in range(1, 13):
    els.append({
        "id": f"E{i}", "slug": f"lesson-{i}",
        "title": f"Element {i}",
        "gloss": ("uncapped fan-out from one vague instruction is a harness "
                  "gap, not a wording problem"),
        "kind": "lesson",
        "tags": tags[: 2 + (i % 3)],
        "topic": "claude-code-ops", "path": f"topics/t{i}.md", "line": i,
        # Half carry no journey: those rows must show the `no-journey` mark
        # in EVERY section they appear in.
        "journey_recorded": bool(i % 2),
    })
json.dump({"kind": "topic-map", "topics": ["claude-code-ops"],
           "coverage": {"pin": "h@abc1234"}, "elements": els},
          open(sys.argv[1], "w"))
PYEOF

# THE COMPLETE RENDERING is where the rows are. Story 20.84 (#1038) put the
# size switch on the member path, and this fixture's member holds 12 Strands —
# over the screen budget — so the console is a summary and the rows this check
# is about render in the View. Both surfaces are ONE code path since Story 20.83
# (#1039), so the property asserted is the same property; it is asserted on the
# artifact that actually carries the rows rather than vacuously on one that
# does not.
python3 "$D" view --map "$work/map.json" --tag workflow \
  --claims '{"G1":"a claim","G2":"another claim"}' --out "$work/screen.md" \
  >/dev/null 2>"$work/e" \
  || { err "view --claims failed: $(cat "$work/e")"; exit 1; }

python3 - "$work/screen.md" <<'PYEOF' || fail=1
import collections, sys

listing = open(sys.argv[1], encoding="utf-8").read()

# Collect each Strand's full rendered block (row + context line + any arc),
# keyed by section, so the same Strand in two sections can be compared whole.
blocks, sec, cur, key = collections.defaultdict(dict), None, [], None


def flush():
    if key is not None:
        blocks[key][sec] = "\n".join(cur)


for line in listing.splitlines():
    if line.startswith("## "):
        flush()
        sec, cur, key = line, [], None
    elif line.startswith("- **"):
        flush()
        cur, key = [line], line.split("**")[1]
    elif key is not None and line.strip():
        cur.append(line)
    elif key is not None:
        flush()
        cur, key = [], None
flush()

multi = {k: v for k, v in blocks.items() if len(v) > 1}
if not multi:
    print("err:  fixture places no Strand in two sections — the assertion "
          "below would pass vacuously", file=sys.stderr)
    raise SystemExit(1)
print(f"ok:   fixture places {len(multi)} Strand(s) in more than one section")

drift = 0
for ident, per_section in multi.items():
    texts = set(per_section.values())
    if len(texts) != 1:
        drift += 1
        print(f"err:  {ident} renders differently across sections (#976):",
              file=sys.stderr)
        for s, t in per_section.items():
            print(f"        {s}\n          {t}", file=sys.stderr)
if drift:
    raise SystemExit(1)
print(f"ok:   every multi-placed Strand renders one identical row everywhere "
      f"({len(multi)} checked)")

# The absence mark travels with the row it qualifies (#977): a Strand marked
# `no-journey` anywhere carries the mark in EVERY section it appears in.
marked = {i: v for i, v in blocks.items()
          if any("no-journey" in t for t in v.values())}
if not marked:
    print("err:  fixture produced no `no-journey` mark — #977 would pass "
          "vacuously", file=sys.stderr)
    raise SystemExit(1)
for ident, per_section in marked.items():
    missing = [s for s, t in per_section.items() if "no-journey" not in t]
    if missing:
        print(f"err:  {ident} carries `no-journey` in some sections and not "
              f"others (#977): missing in {missing}", file=sys.stderr)
        raise SystemExit(1)
print(f"ok:   the `no-journey` mark renders wherever its row does "
      f"({len(marked)} marked Strand(s))")
PYEOF

# The claim is carried VERBATIM — clipping it would re-create #976 one layer up.
python3 - "$work/screen.md" <<'PYEOF' && ok "claims are carried verbatim" || err "a claim was altered in transit"
import sys
listing = open(sys.argv[1], encoding="utf-8").read()
got = [l[len("in common: "):] for l in listing.splitlines()
       if l.startswith("in common: ")]
assert "a claim" in got and "another claim" in got, got
PYEOF

[ "$fail" -eq 0 ] && echo "scripts/check-terrain-relay-fidelity.sh OK"
exit "$fail"
