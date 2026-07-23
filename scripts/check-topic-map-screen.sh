#!/usr/bin/env sh
# check-topic-map-screen.sh — verify the map ends in a BRIEF, not in a second
# proposer (Story 18.63, #591; SPEC-topic-map CAP-3). POSIX sh + stdlib Python;
# every fixture write lands under mktemp -d.
#
# Covers:
#   CAP-3  ONE in-conversation screen carrying the map, machine-proposed
#          candidate directions, and a FREE-FORM response offered every time
#          (not only on rejection); at least one candidate is a cross-topic
#          COMBINATION when the evidence supports one; the outcome is a brief in
#          the owner's words handed to the EXISTING stage-0 `--brief` path; the
#          map composes NO narrative structures (grep-asserted); a sitting that
#          starts at the map ends in a normal brief-carrying run.
#   CAP-3  (Story 18.66) the SIZE SWITCH: a map at or under the screen budget
#          composes a byte-identical payload and writes no View; a map above it
#          renders a View file the owner opens and summarises on the screen.
#          The View is write-only, fully regenerated, and losing it loses
#          nothing.
#   CAP-3  (Story 18.67) STABLE per-pin subtopic indexes and INDEXED SELECTION:
#          {index, note} composes the subtopic's coverage wording plus the
#          owner's note VERBATIM; free text still always wins; an index chosen
#          against a different pin is REFUSED with the mismatch named; stopping
#          stays first-class; downstream cannot tell an indexed selection from
#          a typed brief.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/topic-map.py"
D="scripts/topic-map-directions.py"
DP="scripts/draft-pipeline.py"
VP="scripts/validate-proposal-payload.py"
SKILL="skills/topic-map/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$D', doraise=True)" 2>/dev/null \
  && ok "topic-map-directions compiles" \
  || { err "syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME
mkdir -p "$work/ws"

h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts" "$a/backlog" "$a/plans" "$a/graveyard"
git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1
# Stage 0 validates the declared sources before it accepts a brief, so the host
# repo carries one readable source file and the config declares it.
mkdir -p "$h/docs"
# The filename is deliberately unrelated to any backlog item's evidence
# pointers: since Story 18.65 a declared source is itself a map surface, so a
# host doc named `notes.md` would share the `notes` pointer subject with the
# `staffing` subtopic below and legitimately earn a combination — defeating the
# "never combined on a hunch" assertion, which is about UNRELATED subtopics.
printf '# intake\n\nThe retry storm doubled token spend.\n' > "$h/docs/intake.md"
git -C "$h" add -A >/dev/null 2>&1
git -C "$h" -c user.email=t@e -c user.name=t commit -qm init >/dev/null 2>&1
srcfile="$work/xdg/writing-assistant/repos/$(python3 "$root/scripts/resolve-paths.py" repo-key --root "$h")/writing-sources.yaml"
python3 - "$srcfile" "$a/drafts/" <<'PYEOF'
import sys
open(sys.argv[1], "w", encoding="utf-8").write(
    "sources:\n  - path: docs\noutput:\n  drafts: %s\n" % sys.argv[2])
PYEOF

# Two subtopics in DIFFERENT topics that share an evidence source — the shape a
# cross-topic combination must be proposed from.
cat > "$a/backlog/retry-storm.md" <<'EOF'
---
slug: retry-storm
title: Retry storms
status: shaping
track: engineering
subtopic: retry-behaviour
evidence:
  - host/retro.md:12@abc1234
  - host/log.txt:88@abc1234
  - host/bench.md:3@abc1234
lessons:
  - lesson:retry-storm
---
EOF
cat > "$a/backlog/oncall-load.md" <<'EOF'
---
slug: oncall-load
title: On-call load
status: seed
track: people
subtopic: oncall
evidence:
  - host/retro.md:44@abc1234
  - host/rota.md:7@abc1234
---
EOF
# A third, unrelated subtopic with nothing shared.
cat > "$a/backlog/team-shape.md" <<'EOF'
---
slug: team-shape
title: Team shape
status: seed
track: people
subtopic: staffing
evidence:
  - host/notes.md:9@abc1234
---
EOF

python3 "$M" assemble --root "$h" > "$work/map.json" 2>"$work/m.err" \
  || { err "map assembly failed: $(cat "$work/m.err")"; printf '\nFAILED.\n' >&2; exit 1; }
ok "fixture: the map assembles"

# --- candidate directions -----------------------------------------------------
python3 "$D" candidates --map "$work/map.json" > "$work/cands.json"
python3 - "$work/cands.json" <<'PYEOF' || fail=1
import json, sys
c = json.load(open(sys.argv[1]))["candidates"]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check(c, "the map proposes candidate directions")
combos = [x for x in c if x["kind"] == "combination"]
check(combos, "at least one candidate is a CROSS-TOPIC combination")
if combos:
    k = combos[0]
    check(sorted(k["topics"]) == ["engineering", "people"],
          "the combination spans two different topics")
    check(k["axis"] == "retro.md" and "retro.md" in k["shared_evidence"],
          "the combination's axis is named from evidence both subtopics cite")
    check("retro.md" in k["why"],
          "the combination explains itself from the shared evidence")
# No combination is proposed on nothing shared.
check(all("staffing" not in x["subtopics"] for x in combos),
      "a subtopic sharing no evidence is never combined on a hunch")
# Every candidate names WHAT to cover, never HOW to tell it.
for x in c:
    check(set(x) & {"structure", "sections", "outline", "arc"} == set(),
          f"candidate {x['direction']!r} carries no narrative shape")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- ONE screen, presentable, free-form every time ---------------------------
python3 "$D" payload --map "$work/map.json" > "$work/payload.json"
python3 "$VP" --ws "$work/ws" --surface topic-map "$work/payload.json" > "$work/ask.json" \
  && ok "the screen passes validate-proposal-payload.py before presentation" \
  || err "the screen is not presentable: $(cat "$work/ask.json")"
python3 - "$work/payload.json" <<'PYEOF' || fail=1
import json, sys
p = json.load(open(sys.argv[1]))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check(len(p["items"]) == 1, "it is ONE screen, not a sequence of them")
item = p["items"][0]
labels = [c["label"] for c in item["choices"]]
check(any("name your own" in l for l in labels),
      "a free-form response is offered")
check(labels[-1] == "stop here", "stopping is offered and stays first-class")
check(any("connect" in l for l in labels),
      "the combination candidate reaches the screen")
check("signal for your judgment, never a gate" in item["why"],
      "the screen states that depth is a signal, never a gate")
check("selectable" in item["where"],
      "the screen states consumed material remains selectable")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# Free-form is offered EVERY time — including on a map with a single candidate.
python3 - "$work/map.json" > "$work/thin-map.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["topics"] = d["topics"][:1]
for t in d["topics"]:
    t["subtopics"] = t["subtopics"][:1]
print(json.dumps(d))
PYEOF
python3 "$D" payload --map "$work/thin-map.json" > "$work/thin-payload.json"
python3 -c "
import json
labels=[c['label'] for c in json.load(open('$work/thin-payload.json'))['items'][0]['choices']]
assert any('name your own' in l for l in labels), labels
assert 'stop here' in labels, labels
" && ok "free-form is offered every time, not only on rejection" \
  || err "free-form is conditional"

# --- the SIZE SWITCH: a large map gets a View file, a small one does not -----
# At or under the screen budget the shipped flow must not move at all: passing
# --view to a small map changes nothing and writes nothing.
python3 "$D" payload --map "$work/map.json" --view "$work/small-view.md" \
  > "$work/payload-view.json" 2>/dev/null
cmp -s "$work/payload.json" "$work/payload-view.json" \
  && ok "size switch: a map at or under the budget composes a BYTE-IDENTICAL payload, --view or not" \
  || err "the small-map screen changed"
[ -e "$work/small-view.md" ] \
  && err "a View file was written for a map under the screen budget" \
  || ok "size switch: no View file exists for a map under the budget"
grep -q 'View' "$work/payload.json" \
  && err "a View path leaked onto the small-map screen" \
  || ok "size switch: no View path appears on the small-map screen"

# A map ABOVE the budget: the terrain moves to the View, the screen summarises.
python3 - "$work/map.json" > "$work/big-map.json" <<'PYEOF'
import copy, json, sys
d = json.load(open(sys.argv[1]))
topic = d["topics"][0]
base = topic["subtopics"][0]
for n in range(12):                       # comfortably past the screen budget
    s = copy.deepcopy(base)
    s["subtopic"] = f"widened-{n:02d}"
    s["density"] = dict(s["density"], evidence_pointers=n,
                        pointers=[f"host/w{n}.md:{n + 1}@abc1234"])
    s["consumed"] = (n == 0)
    s["items"] = [{"slug": f"seed-{n}", "title": f"Lesson {n}",
                   "family": "hub-lessons"}]
    topic["subtopics"].append(s)
# A POINTERLESS entry, and an UNNAMED one — the two opaque shapes #616 found in
# a real View. Without these the no-opaque-entries assertions pass vacuously.
blank = copy.deepcopy(base)
blank["subtopic"] = ""
blank["clustered_by"] = "evidence-subject"
blank["density"] = dict(blank["density"], evidence_pointers=0, pointers=[])
blank["items"] = [{"slug": "nameless-member", "title": "Nameless",
                   "status": "seed", "family": "articles-items"}]
topic["subtopics"].append(blank)
lonely = copy.deepcopy(base)
lonely["subtopic"] = "(unclustered)"
lonely["clustered_by"] = "unclustered"
lonely["density"] = dict(lonely["density"], evidence_pointers=0, pointers=[])
lonely["items"] = [{"slug": "hidden-live-item", "title": "Hidden",
                    "status": "shaping", "family": "articles-items"}]
topic["subtopics"].append(lonely)
print(json.dumps(d))
PYEOF
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" \
  > "$work/big-payload.json" 2>/dev/null
[ -s "$work/view.md" ] \
  && ok "size switch: a map above the budget renders a View file" \
  || err "no View file was rendered for an over-budget map"
python3 "$VP" --ws "$work/ws" --surface topic-map "$work/big-payload.json" \
  > "$work/big-ask.json" \
  && ok "size switch: the summary screen still passes validate-proposal-payload.py" \
  || err "the summary screen is not presentable: $(cat "$work/big-ask.json")"
python3 - "$work/big-payload.json" "$work/view.md" <<'PYEOF' || fail=1
import json, sys
p = json.load(open(sys.argv[1]))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check(len(p["items"]) == 1, "the over-budget screen is still ONE screen")
item = p["items"][0]
check(sys.argv[2] in item["where"],
      "the summary carries the View file's path, whole and unclipped")
check(len(item["where"]) <= 240, "the summary stays inside the display budget")
labels = [c["label"] for c in item["choices"]]
check(any("index" in l for l in labels), "selection by index is offered")
check(any("name your own" in l for l in labels),
      "free-form is still offered every time")
check(labels[-1] == "stop here", "stopping is still offered last, first-class")
check("signal for your judgment, never a gate" in item["why"],
      "the depth-is-a-signal line is intact on the summary screen")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

python3 - "$work/big-map.json" "$work/view.md" <<'PYEOF' || fail=1
import json, re, sys
d = json.load(open(sys.argv[1]))
view = open(sys.argv[2], encoding="utf-8").read()
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

subs = [s for t in d["topics"] for s in t["subtopics"]]
check(all(s["subtopic"] in view for s in subs),
      f"the View lists every one of the {len(subs)} subtopics")
check(d["coverage"]["pin"] in view, "the View header carries the map's pin")
check(re.search(r"^### T\d+\.\d+ — ", view, re.M),
      "every subtopic carries a stable ID (T<topic>.<subtopic>)")
ids = re.findall(r"^### (T\d+\.\d+) ", view, re.M)
check(len(ids) == len(set(ids)) == len(subs), "the IDs are unique, one per subtopic")
# IDs are assigned in RANK order (richest terrain first), so the View must show
# them in numeric order (#612). A string sort renders T3.1, T3.10, … T3.19, T3.2
# and scatters exactly the ranking that makes the file scannable.
def _num(i):
    return tuple(int(p) for p in re.findall(r"\d+", i))
check(ids == sorted(ids, key=_num),
      f"the View lists subtopics in NUMERIC id order, not lexicographic ({ids[:6]})")
# Not vacuous: the two orders only differ once a topic reaches ten subtopics.
check(any(_num(i)[1] >= 10 for i in ids),
      f"the fixture reaches two-digit indexes, so the order above is a real test ({ids[-3:]})")
check(all(t["topic"] in view for t in d["topics"]), "each subtopic sits under its topic")
check("glance:" in view, "the depth glance is shown")
check("host/w5.md:6@abc1234" in view, "the evidence pointers are listed")
check("Lesson 3" in view, "lesson-seed names are shown")
check("consumed: yes" in view and "consumed: no" in view,
      "consumed marks are shown, and consumed material is NOT hidden")

# No opaque entries (Story 18.70, #616). An entry that shows counts and no
# subjects is invisible terrain, and the unclustered bucket is exactly the
# material nothing else surfaces.
check(not re.search(r"^### T\d+\.\d+ —\s*$", view, re.M),
      "no subtopic heading is left empty (no dangling dash)")
# Each entry's own block, so a member name found elsewhere in the file cannot
# stand in for the entry that was supposed to list it.
blocks = {h: b for h, b in re.findall(
    r"^### (T\d+\.\d+) — .*?$\n(.*?)(?=^### |\Z)", view, re.M | re.S)}
opaque = [s for s in subs if not (s.get("density", {}).get("pointers") or [])]
check(opaque, "the fixture contains a pointerless entry to exercise this")
missing = [s["subtopic"] for s in opaque
           if not any("- items (" in b and all(
               str(i.get("slug") or i.get("title") or "") in b
               for i in s.get("items", []))
               for b in blocks.values())]
check(not missing,
      f"a subtopic with no evidence pointers names its members, not just counts ({missing[:2]})")
check(sum("- items (" in b for b in blocks.values()) >= len(opaque),
      "every pointerless entry carries an explicit items list")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# The caps stop being fixed constants above the budget.
python3 "$D" candidates --map "$work/big-map.json" > "$work/big-cands.json"
python3 -c "
import json
c=json.load(open('$work/big-cands.json'))['candidates']
singles=[x for x in c if x['kind']=='single']
assert len(singles) > 3, len(singles)
" && ok "size switch: above the budget the fixed candidate caps no longer apply" \
  || err "the over-budget branch is still capped at the screen constants"

# Fully regenerated per invocation, for an unchanged pin.
cp "$work/view.md" "$work/view-1.md"
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" >/dev/null 2>&1
cmp -s "$work/view-1.md" "$work/view.md" \
  && ok "size switch: two invocations regenerate the View identically at one pin" \
  || err "the View is not deterministic at an unchanged pin"

# WRITE-ONLY: poison it, and nothing downstream changes. Delete it, and nothing
# is lost — it is a rendering, never a record.
printf 'POISON-VIEW\n' > "$work/view.md"
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" \
  > "$work/big-payload2.json" 2>/dev/null
grep -q 'POISON-VIEW' "$work/big-payload2.json" \
  && err "the composer read the View back (a stored index)" \
  || ok "size switch: a poisoned View does not influence the next screen (write-only)"
cmp -s "$work/big-payload.json" "$work/big-payload2.json" \
  && ok "size switch: the screen is unchanged after the View was overwritten" \
  || err "overwriting the View changed the screen"
rm -f "$work/view.md"
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" \
  > "$work/big-payload3.json" 2>/dev/null
cmp -s "$work/big-payload.json" "$work/big-payload3.json" \
  && cmp -s "$work/view-1.md" "$work/view.md" \
  && ok "size switch: deleting the View loses nothing (map and View both regenerate)" \
  || err "deleting the View lost something"

# Source-level: the View path is written, never read (the --emit-debug rule).
python3 - "$D" <<'PYEOF' && ok "size switch: no code path reads a View file back" || err "topic-map-directions.py contains a View-reading code path"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
reads = re.findall(r'open\((?![^)]*"w")[^)]*\)', src)
for r in reads:
    assert "view" not in r.lower(), f"a View file is opened for reading: {r}"
assert 'def write_view' in src and 'open(path, "w"' in src, "the View is not write-only"
PYEOF

# --- the outcome is a brief IN THE OWNER'S WORDS -----------------------------
printf '%s' '{"selection":"name your own direction or combination axis","free_text":"connect the retry storm to on-call load, through the retro"}' \
  > "$work/answer-free.json"
python3 "$D" brief --answer "$work/answer-free.json" --map "$work/map.json" \
  > "$work/brief-free.json"
python3 -c "
import json
b=json.load(open('$work/brief-free.json'))
assert b['brief']=='connect the retry storm to on-call load, through the retro', b
assert b['provenance']=='owner-authored' and b['origin']=='free-form', b
" && ok "free-form wording becomes the brief verbatim, owner-authored" \
  || err "free-form wording was not carried through"

sel=$(python3 -c "import json;print(json.load(open('$work/cands.json'))['candidates'][0]['direction'])")
python3 -c "
import json,sys
json.dump({'selection':sys.argv[1],'free_text':''},open('$work/answer-sel.json','w'))
" "$sel"
python3 "$D" brief --answer "$work/answer-sel.json" --map "$work/map.json" \
  > "$work/brief-sel.json"
python3 -c "
import json
b=json.load(open('$work/brief-sel.json'))
assert b['origin']=='adopted-candidate', b
assert b['provenance']=='owner-authored', b
" && ok "machine-proposed text the owner accepts becomes OWNER-ADOPTED wording" \
  || err "an adopted candidate did not become an owner-authored brief"

printf '%s' '{"selection":"stop here","free_text":""}' > "$work/answer-stop.json"
python3 "$D" brief --answer "$work/answer-stop.json" --map "$work/map.json" \
  > "$work/brief-stop.json" 2>&1 \
  && err "stopping produced a brief" \
  || grep -q 'first-class outcome' "$work/brief-stop.json" \
     && ok "stopping produces no brief and no run, and says so" \
     || err "wrong stop behaviour: $(cat "$work/brief-stop.json")"

# --- INDEXED SELECTION: {index, note} against the View's pin -----------------
bigpin=$(python3 -c "import json;print(json.load(open('$work/big-map.json'))['coverage']['pin'])")
idx=$(python3 -c "
import json
c=[x for x in json.load(open('$work/big-cands.json'))['candidates'] if x['kind']=='single']
print(c[0]['id'])")
python3 -c "
import json,sys
json.dump({'index':sys.argv[1],'note':'through the on-call retro, not the metrics',
           'pin':sys.argv[2]}, open('$work/answer-idx.json','w'))
" "$idx" "$bigpin"
python3 "$D" brief --answer "$work/answer-idx.json" --map "$work/big-map.json" \
  > "$work/brief-idx.json" 2>"$work/brief-idx.err" \
  && ok "indexed selection: an index plus a note composes a brief" \
  || err "indexed selection failed: $(cat "$work/brief-idx.err")"
python3 - "$work/brief-idx.json" "$work/big-cands.json" <<'PYEOF' || fail=1
import json, sys
b = json.load(open(sys.argv[1]))
cands = json.load(open(sys.argv[2]))["candidates"]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

note = "through the on-call retro, not the metrics"
check(note in b["brief"], "the owner's note is carried into the brief VERBATIM")
wording = next(c["direction"] for c in cands if c["id"] == b["index"])
check(b["brief"].startswith(wording),
      "the brief is the subtopic's coverage wording plus the note")
check(b["provenance"] == "owner-authored", "an adopted index is owner-adopted wording")
check(b["origin"] == "adopted-index", "the origin records that an index was adopted")
check(isinstance(b["brief"], str), "the outcome is one plain brief string")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# Free text ALWAYS wins — even when an index is also present.
python3 -c "
import json,sys
json.dump({'index':sys.argv[1],'note':'ignored','pin':sys.argv[2],
           'free_text':'my own direction, in my own words'},
          open('$work/answer-idx-free.json','w'))
" "$idx" "$bigpin"
python3 "$D" brief --answer "$work/answer-idx-free.json" --map "$work/big-map.json" \
  > "$work/brief-idx-free.json" 2>/dev/null
python3 -c "
import json
b=json.load(open('$work/brief-idx-free.json'))
assert b['brief']=='my own direction, in my own words', b
assert b['origin']=='free-form', b
" && ok "indexed selection: free text still always wins over an index" \
  || err "an index overrode the owner's free text"

# A STALE index is refused with the pin mismatch NAMED — never re-resolved.
python3 -c "
import json,sys
json.dump({'index':sys.argv[1],'note':'x','pin':'deadbeef'},
          open('$work/answer-stale.json','w'))
" "$idx"
if python3 "$D" brief --answer "$work/answer-stale.json" --map "$work/big-map.json" \
     > "$work/brief-stale.out" 2>"$work/brief-stale.err"; then
  err "a stale-pin index produced a brief instead of a refusal"
else
  rc=$?
  [ "$rc" -eq 1 ] && ok "indexed selection: a stale-pin index is refused (exit 1)" \
    || err "stale-pin refusal used exit $rc, not the documented refusal exit"
  grep -q 'pin mismatch' "$work/brief-stale.err" \
    && grep -q 'deadbeef' "$work/brief-stale.err" \
    && grep -q "$bigpin" "$work/brief-stale.err" \
    && ok "indexed selection: the refusal NAMES both pins" \
    || err "the refusal does not name the mismatch: $(cat "$work/brief-stale.err")"
  [ -s "$work/brief-stale.out" ] \
    && err "a refused selection still emitted a brief" \
    || ok "indexed selection: a refused selection emits no brief"
fi

# An index with no pin at all cannot be proven current, so it is refused too.
python3 -c "
import json,sys
json.dump({'index':sys.argv[1],'note':'x'},open('$work/answer-nopin.json','w'))
" "$idx"
python3 "$D" brief --answer "$work/answer-nopin.json" --map "$work/big-map.json" \
  > /dev/null 2>"$work/brief-nopin.err" \
  && err "an index without a pin was silently resolved" \
  || grep -q 'no pin' "$work/brief-nopin.err" \
     && ok "indexed selection: an index without a pin is refused, and says why" \
     || err "wrong no-pin behaviour: $(cat "$work/brief-nopin.err")"

# Stopping stays first-class even from the View branch.
printf '%s' '{"selection":"stop here","index":"T1.1","free_text":""}' \
  > "$work/answer-idx-stop.json"
python3 "$D" brief --answer "$work/answer-idx-stop.json" --map "$work/big-map.json" \
  >"$work/idx-stop.out" 2>&1 \
  && err "stopping from the View branch produced a brief" \
  || grep -q 'first-class outcome' "$work/idx-stop.out" \
     && ok "indexed selection: stop here still produces no brief and no run" \
     || err "wrong stop behaviour from the View branch"

# ID STABILITY within a pin: two invocations produce identical IDs.
python3 "$D" candidates --map "$work/big-map.json" > "$work/big-cands2.json"
cmp -s "$work/big-cands.json" "$work/big-cands2.json" \
  && ok "indexed selection: IDs are identical across invocations at one pin" \
  || err "the IDs are not stable within a pin"
python3 - "$work/view-1.md" "$work/big-cands.json" <<'PYEOF' && ok "indexed selection: the View's IDs and the composer's IDs are the same identifiers" || err "the View and the composer disagree about indexes"
import json, re, sys
view_ids = set(re.findall(r"^### (T\d+\.\d+) ", open(sys.argv[1], encoding="utf-8").read(), re.M))
cand_ids = {c["id"] for c in json.load(open(sys.argv[2]))["candidates"]
            if c["kind"] == "single"}
assert cand_ids <= view_ids, cand_ids - view_ids
PYEOF

# No new entry pipeline: an indexed brief reaches stage 0 exactly like a typed one.
idxbrief=$(python3 -c "import json;print(json.load(open('$work/brief-idx.json'))['brief'])")
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$idxbrief" --root "$h" \
  > "$work/stage0-idx.json" 2>"$work/e-idx" \
  || err "an indexed brief did not start a normal run: $(cat "$work/e-idx")"
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$idxbrief" --root "$h" \
  > "$work/stage0-idx-typed.json" 2>/dev/null
python3 -c "
import json
b=(json.load(open('$work/stage0-idx.json')).get('run_state') or {}).get('brief') or {}
t=(json.load(open('$work/stage0-idx-typed.json')).get('run_state') or {}).get('brief') or {}
assert b.get('text')=='''$idxbrief''', b
assert b.get('provenance')=='owner-authored', b
# byte-for-byte the same record the SAME string typed unaided produces: the
# index, the note and the pin exist only in the composer's output, never here
assert b==t, (b,t)
assert 'index' not in b and 'pin' not in b and 'note' not in b, b
" && ok "indexed selection: downstream cannot distinguish an indexed selection from a typed brief" \
  || err "an indexed selection left a downstream trace"

# --- the hand-off is the EXISTING stage-0 --brief path -----------------------
brief=$(python3 -c "import json;print(json.load(open('$work/brief-free.json'))['brief'])")
mkdir -p "$work/ws2"
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$brief" --root "$h" \
  > "$work/stage0.json" 2>"$work/e-stage0" \
  || { err "the brief-carrying run did not start: $(cat "$work/e-stage0")"; }
python3 -c "
import json
o=json.load(open('$work/stage0.json'))
b=(o.get('run_state') or {}).get('brief') or {}
assert b.get('text')=='$brief', b
assert b.get('provenance')=='owner-authored', b
" && ok "stage 0 receives the brief through its existing --brief path, owner-authored" \
  || err "the hand-off did not reach stage 0: $(cat "$work/stage0.json")"

# Indistinguishable downstream: the same brief typed unaided produces the same
# run-state brief record.
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$brief" --root "$h" \
  > "$work/stage0-typed.json" 2>/dev/null
python3 -c "
import json
a=json.load(open('$work/stage0.json'))['run_state'].get('brief')
b=json.load(open('$work/stage0-typed.json'))['run_state'].get('brief')
assert a==b, (a,b)
" && ok "a map-started run is indistinguishable downstream from a hand-typed brief" \
  || err "the map leaves a downstream trace the brief path does not"

# --- NO structure composition anywhere in the map path -----------------------
# Scope is a property of the CODE, not the prose documenting it.
for src in "$D" "$M"; do
  python3 - "$src" > "$work/code.py" <<'PYEOF'
import io, sys, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
out = []
for tok in tokenize.generate_tokens(io.StringIO(src).readline):
    if tok.type in (tokenize.COMMENT, tokenize.STRING):
        continue
    out.append(tok.string)
print(" ".join(out))
PYEOF
  grep -qiE 'narrative structure|structure candidate|compose.*structure|section_plan|outline' \
    "$work/code.py" \
    && err "$src composes narrative structures (18.45 single-proposer invariant)" \
    || ok "$src composes no narrative structures"
done

# --- the map path writes nothing into the host or articles tree --------------
before=$(find "$a" -type f | sort)
python3 "$D" payload --map "$work/map.json" >/dev/null
python3 "$D" candidates --map "$work/map.json" >/dev/null
[ "$before" = "$(find "$a" -type f | sort)" ] \
  && ok "composing the screen writes nothing into the articles repo" \
  || err "the screen composer wrote into the articles repo"

# --- the shipped map harnesses keep passing verbatim -------------------------
for c in check-topic-map.sh check-topic-map-depth.sh; do
  sh "scripts/$c" >/dev/null 2>&1 && ok "$c passes unchanged" || err "$c regressed"
done

# --- lockstep: the SKILL states the shipped mechanics ------------------------
[ -f "$SKILL" ] && ok "the topic-map skill exists" || err "$SKILL missing"
for token in 'topic-map.py assemble' 'topic-map-directions.py payload' \
             'topic-map-directions.py brief' 'validate-proposal-payload.py' \
             'stage0' '--brief' 'free-form' 'every time' \
             'never composes narrative structures' 'single proposer' \
             '--view' 'size switch' 'never read back' \
             'resolve-paths.py topic-map-view' 'destination repository' \
             'stable within a pin' 'refused with the mismatch named' \
             'note verbatim'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the contract text: $token" \
    || err "SKILL is missing contract text: $token"
done

[ "$fail" -eq 0 ] && printf '\nAll topic-map screen checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
