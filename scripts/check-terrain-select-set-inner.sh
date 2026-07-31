#!/usr/bin/env sh
# parallel-safe
# tier: inner — set-selection assertions against a derived over-budget fixture
#   map; no seam, no corpus, no assembly. A THIRD sibling beside
#   check-terrain-select-brief-inner.sh and check-terrain-select-index-inner.sh
#   for the reason #948 split those two: each subject holds its own check with
#   headroom, rather than pushing an existing one back toward INNER_MS on load
#   variance. Measured 2026-07-30 at adoption: ~1.1s (ceiling 2s).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-select-set-inner.sh — selection is a SET, and the claim is
# recomposed over exactly that set (Story 20.54, #937; SPEC-terrain CAP-3).
#
# The load-bearing assertion here is AC4's member record. Everything else is
# mechanism; the member set is what the completeness invariant follows into
# drafting, so a brief composed from a set with no members recorded turns
# every later omission silent.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/topic-map-directions.py"
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# One prep run builds the over-budget map: enough Strands that a set of three
# is a real subset rather than the whole terrain.
python3 - "$FIX" "$work" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); w = sys.argv[2]
strands = list(d.get("elements") or [])
for n in range(12):
    strands.append({
        "kind": "lesson", "slug": f"widened-{n:02d}",
        "title": f"Lesson {n}",
        "topic": "engineering" if n % 2 else "people",
        # A tag axis with a member big enough to SECTION: the G-id assertions
        # below need a screen that actually mints group ids, and a group id
        # only exists where a member has sections (Story 20.76, #996).
        "tags": ["widened", ["alpha", "beta", "gamma"][n % 3]],
        "date": f"2026-07-{(n % 28) + 1:02d}",
        "gloss": f"A claim the material itself makes, number {n}",
        "situation": f"LESSONS.md:{n + 10}@abc1234",
        "evidence": [f"LESSONS.md:{n + 10}@abc1234"],
        "consumed": False,
    })
d["elements"] = strands
d["coverage"] = dict(d.get("coverage", {}), hub_pin="0123456789abcdef")
json.dump(d, open(w + "/big-map.json", "w"))
PYEOF

python3 "$D" candidates --map "$work/big-map.json" > "$work/cands.json"

# One prep call writes every answer fixture: a three-Strand set, the same set
# with free-form override, a single selection (the degenerate case), and the
# G-id fixtures — a typed group, the same members typed one by one, mixed
# input with set arithmetic, and group ids no screen here defines.
python3 - "$work" <<'PYEOF'
import json, os, sys
sys.path.insert(0, os.path.join(os.getcwd(), "scripts"))
from terrain_members import member_sections
w = sys.argv[1]
m = json.load(open(w + "/big-map.json"))
pin = m["coverage"]["pin"]
c = [x for x in json.load(open(w + "/cands.json"))["candidates"]
     if x["kind"] == "element"]
ids = [x["id"] for x in c[:3]]
note = "the thread that runs through all three"

# THE SCREEN THAT DEFINES THE GROUP IDS, read the way the owner read it: one
# member's sections at this pin. Expansion is only meaningful here.
by_slug = {x["slug"]: x["id"] for x in c}
ms = member_sections(m, "widened", "tag")
sections = [(s["group_id"], [by_slug[e["slug"]] for e in s["strands"]])
            for s in ms["sections"]]
screen = {"member": "widened", "axis": "tag"}
(g1, g1_members), (g2, g2_members) = sections[0], sections[1]
json.dump({"index": ids, "note": note, "pin": pin},
          open(w + "/a-set.json", "w"))
# The same set named as ONE comma-separated string: the payload shape is the
# owner's convenience and must not change what is selected.
json.dump({"index": ", ".join(ids), "note": note, "pin": pin},
          open(w + "/a-set-str.json", "w"))
json.dump({"index": ids, "note": "ignored", "pin": pin,
           "free_text": "my own thesis, in my own words"},
          open(w + "/a-set-free.json", "w"))
json.dump({"index": ids[0], "note": note, "pin": pin},
          open(w + "/a-one.json", "w"))
json.dump({"index": [ids[0], "L9999"], "note": note, "pin": pin},
          open(w + "/a-missing.json", "w"))

# THE G-ID FIXTURES (Story 20.76, #996). A typed group id, and the same set
# typed member by member — the two must be indistinguishable downstream.
gnote = "what these have in common"
json.dump(dict(screen, index=[g1], note=gnote, pin=pin),
          open(w + "/a-group.json", "w"))
json.dump(dict(screen, index=list(g1_members), note=gnote, pin=pin),
          open(w + "/a-group-typed.json", "w"))
# Mixed input, and its typed equivalent: expansion first, arithmetic second.
mixed = f"{g1} + {g2_members[0]}, minus {g1_members[1]}"
json.dump(dict(screen, index=mixed, note=gnote, pin=pin),
          open(w + "/a-mixed.json", "w"))
json.dump(dict(screen, note=gnote, pin=pin,
               index=[i for i in g1_members if i != g1_members[1]]
                     + [g2_members[0]]),
          open(w + "/a-mixed-typed.json", "w"))
# A group id this screen and pin did not define, and one typed with no screen
# recorded at all: both refused, never resolved against another grouping.
json.dump(dict(screen, index=["G99"], note=gnote, pin=pin),
          open(w + "/a-group-unknown.json", "w"))
json.dump({"index": [g1], "note": gnote, "pin": pin},
          open(w + "/a-group-noscreen.json", "w"))
json.dump({"ids": ids, "note": note, "gnote": gnote, "g1": g1,
           "g1_members": g1_members, "mixed": mixed,
           "groups": [g for g, _ in sections]},
          open(w + "/expect.json", "w"))
PYEOF

for a in set set-str set-free one group group-typed mixed mixed-typed; do
  python3 "$D" brief --answer "$work/a-$a.json" --map "$work/big-map.json" \
    > "$work/b-$a.json" 2>"$work/b-$a.err" \
    || err "brief from a-$a failed: $(cat "$work/b-$a.err")"
done

# A GROUP ID IS TYPED SHORTHAND THAT EXPANDS AT THE SCREEN (Story 20.76,
# #996; SPEC-terrain CAP-3). It was refused outright until this story, on a
# ground that survives with a narrower reach: a rendering is not an address,
# so a G-id may never be RECORDED — but it may be TYPED. Expansion keeps
# grouping presentation-only: no group is selected, its members are, and the
# result is indistinguishable from the same members typed one by one. The
# refusal assertions this block replaces now assert the expansion; the
# refusals that remain are the ones the invariant still needs (below).
#
# A G-ID THIS SCREEN AND PIN DID NOT DEFINE IS REFUSED, naming why — exactly
# as a pin mismatch is, because expansion is only meaningful at the screen
# that minted the id.
for a in group-unknown group-noscreen; do
  if python3 "$D" brief --answer "$work/a-$a.json" --map "$work/big-map.json" \
       > "$work/b-$a.out" 2>"$work/b-$a.err"; then
    err "$a: a group id no screen here defined was resolved to members anyway"
  else
    grep -qi 'per-screen and per-pin' "$work/b-$a.err" \
      && ok "$a: refused with the per-screen, per-pin reason named" \
      || err "$a: the refusal does not name why: $(cat "$work/b-$a.err")"
    [ -s "$work/b-$a.out" ] \
      && err "$a: a refused selection still emitted a brief" \
      || ok "$a: a refused selection emits no brief"
  fi
done

# An unresolvable index refuses the WHOLE selection: dropping it would compose
# the brief over a set the owner did not choose, silently.
python3 "$D" brief --answer "$work/a-missing.json" --map "$work/big-map.json" \
  > /dev/null 2>"$work/b-missing.err" \
  && err "an unresolvable index was silently dropped from the set" \
  || { grep -q "L9999" "$work/b-missing.err" \
       && ok "an unresolvable index refuses the whole selection, naming it" \
       || err "wrong missing-index behaviour: $(cat "$work/b-missing.err")"; }

# --- one assertion run over the produced files ------------------------------
python3 - "$work" <<'PYEOF' || fail=1
import json, sys
w = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

exp = json.load(open(w + "/expect.json"))
ids, note = exp["ids"], exp["note"]
cands = {c["id"]: c for c in json.load(open(w + "/cands.json"))["candidates"]}
s = json.load(open(w + "/b-set.json"))

# AC1 — every named index is carried; none dropped, none collapsed to the first.
check(s.get("indexes") == ids,
      f"all named indexes are carried, in the owner's order ({s.get('indexes')})")
check(s["origin"] == "adopted-index-set",
      "a set records that a SET was adopted, not a single index")

# The payload shape is the owner's convenience: a comma-separated string names
# the same set as a list, and must select the same thing.
sstr = json.load(open(w + "/b-set-str.json"))
check(sstr["indexes"] == ids and sstr["brief"] == s["brief"],
      "a comma-separated string names the same set as a list")

# AC2 — the claim is recomposed over EXACTLY the selected set.
rec = s.get("recomposition") or {}
check(rec.get("over") == ids,
      f"recomposition is over exactly the selected set ({rec.get('over')})")
check(len(rec.get("claims") or []) == len(ids),
      "one recomposition input per selected member — no union, no group set")
for cid in ids:
    src = cands[cid].get("gloss") or cands[cid]["direction"]
    check(src in rec["claims"],
          f"the input for {cid} is its own served claim")
check(rec.get("authoring") == "machine-composed at render time, marked",
      "the recomposition declares its authoring class")
check(note in s["brief"], "the owner's note is carried into the brief VERBATIM")

# AC4 — the brief records its members and BOTH pins. This is the load-bearing
# criterion: with no member set recorded, a later omission becomes silent.
members = s.get("members") or []
check([m["index"] for m in members] == ids,
      "the brief records the member set it was composed from")
check(all("gloss" in m and "cite" in m for m in members),
      "each member carries its served gloss and its cite")
for m in members:
    check(m["cite"] == cands[m["index"]].get("situation"),
          f"{m['index']}'s cite is the served pointer, not one rebuilt here")
pins = s.get("pins") or {}
check(pins.get("terrain") == s["pin"] and pins.get("hub"),
      f"both pins are recorded — the terrain invocation and the hub commit ({pins})")

# AC3 — free text always wins, set or no set.
f = json.load(open(w + "/b-set-free.json"))
check(f["brief"] == "my own thesis, in my own words",
      "free-form wording is the brief and the machine proposal is discarded")
check(f["origin"] == "free-form", "free text over a set records origin free-form")

# AC5 — a single selection is the degenerate case, unchanged.
one = json.load(open(w + "/b-one.json"))
check(one["origin"] == "adopted-index",
      "one index still records origin adopted-index")
check(one["brief"] == f"{cands[ids[0]]['direction']} — {note}",
      "one index still composes the coverage wording plus the note verbatim")
check(isinstance(one["brief"], str) and isinstance(s["brief"], str),
      "the outcome is one plain brief string either way")

# --- Story 20.76 (#996): G-ids expand at the screen -------------------------
g_raw = open(w + "/b-group.json", encoding="utf-8").read()
t_raw = open(w + "/b-group-typed.json", encoding="utf-8").read()
g, t = json.loads(g_raw), json.loads(t_raw)

# AC1 — the typed group id became its member indexes, in the screen's order.
check(g.get("indexes") == exp["g1_members"],
      f"a typed group id expands to its member indexes ({g.get('indexes')})")

# AC3 — NO G-ID IS EVER RECORDED. This is the clause that keeps the
# rendering-not-address rule intact: a group id is per-screen and per-pin, so
# recording one would make a rendering an address.
check(exp["g1"] not in g_raw,
      f"the composed brief records no group id ({exp['g1']} appears nowhere)")
check(all(not str(x).startswith("G") for x in g.get("indexes") or []),
      "every recorded index is a member index, never a group id")
check([m["index"] for m in g.get("members") or []] == exp["g1_members"],
      "the recorded member set is the group's members")

# AC5 — INDISTINGUISHABLE DOWNSTREAM. The whole test that expansion is a
# typing convenience and not a second kind of address: byte for byte, the
# expanded selection and the same set typed member by member are one output.
check(g_raw == t_raw,
      "an expanded selection is byte-identical to the same set typed "
      "member by member")

# AC2 — mixed input composes by expand-then-set-arithmetic, resolved in full
# before the brief exists. `minus` is this story's new syntax.
mx_raw = open(w + "/b-mixed.json", encoding="utf-8").read()
mxt_raw = open(w + "/b-mixed-typed.json", encoding="utf-8").read()
mx = json.loads(mx_raw)
want = [i for i in exp["g1_members"] if i != exp["g1_members"][1]]
check(mx.get("indexes") == want + [json.loads(mxt_raw)["indexes"][-1]],
      f"{exp['mixed']!r} expands then subtracts, in the owner's order "
      f"({mx.get('indexes')})")
check(exp["g1"] not in mx_raw, "mixed input records no group id either")
check(mx_raw == mxt_raw,
      "mixed input is byte-identical to its typed equivalent")

# AC6 — sections stay presentation-only: what was selected is Strands. The
# group id bought the owner typing, never a group-shaped selection.
check(mx["origin"] == "adopted-index-set" and g["origin"] == "adopted-index-set",
      "an expanded selection records an ordinary index SET, not a group")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
