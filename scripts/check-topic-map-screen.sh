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
# A subtopic citing ONE file many times — the shape #615 found (24 pointers into
# a single SPEC, six consecutive lines of one tool). Without it the per-file
# aggregation assertion passes vacuously.
dense = copy.deepcopy(base)
dense["subtopic"] = "dense-citations"
dense["density"] = dict(dense["density"], evidence_pointers=9,
                        pointers=[f"specs/spec-loop/SPEC.md:{n}@abc1234"
                                  for n in range(10, 17)]
                                 + [f"tools/ledger:{n}@abc1234" for n in (1403, 1404)])
topic["subtopics"].append(dense)
# A subtopic carrying MANY lesson seeds, one of them very long — the shape #634
# found (65 complete lesson texts joined onto one ~10,000-character line).
# Without it the seed cap, the clip and the remainder disclosure pass vacuously.
seedy = copy.deepcopy(base)
seedy["subtopic"] = "seed-heavy"
seedy["density"] = dict(seedy["density"], evidence_pointers=1,
                        pointers=["host/seeds.md:1@abc1234"])
seedy["items"] = [{"slug": f"seed-heavy-{n}",
                   "title": (f"Lesson {n} " + "x" * 400 if n == 0
                             else f"Seeded lesson number {n:02d}"),
                   "family": "hub-lessons"} for n in range(20)]
topic["subtopics"].append(seedy)
blank = copy.deepcopy(base)
blank["subtopic"] = ""
blank["clustered_by"] = "evidence-subject"
blank["density"] = dict(blank["density"], evidence_pointers=0, pointers=[])
blank["items"] = [{"slug": "nameless-member", "title": "Nameless",
                   "status": "seed", "family": "articles-items"}]
topic["subtopics"].append(blank)
# The SECOND PROJECTION (Story 18.80, #641): typed elements beside the
# clusters, plus the bound disclosure that must reach the owner surface.
d["elements"] = [
    {"kind": "decision", "summary": "Ship behind a flag; rollback is the feature",
     "topic": "delivery", "date": "2026-07-20",
     "situation": "topics/delivery.md:3@abc1234",
     "evidence": ["topics/delivery.md:3@abc1234"], "consumed": False},
    {"kind": "reversal", "summary": "Weekly release train, superseded by continuous deploy",
     "topic": "delivery", "date": "2026-07-19",
     "situation": "topics/delivery.md:4@abc1234",
     "evidence": ["topics/delivery.md:4@abc1234"], "consumed": True},
    {"kind": "decision", "summary": "One repo doubles as the publishing repo",
     "topic": "nowhere", "date": "2026-07-18",
     "situation": "topics/nowhere.md:2@abc1234",
     "evidence": ["topics/nowhere.md:2@abc1234"], "consumed": False},
]
d["coverage"] = dict(d.get("coverage", {}),
                     element_topics_read=["delivery", "nowhere"],
                     element_topics_skipped=["zeta"])
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
# A PLACEHOLDER name is the assembler's enum for "nothing named this", and the
# View renders that state as prose instead (#634) — so those entries are
# checked by their prose, not by the bare token they carry in map.json.
PLACEHOLDERS = ("(unclustered)", "(untracked)", "(unnamed)")
named = [s for s in subs if s["subtopic"] not in PLACEHOLDERS]
check(all(s["subtopic"] in view for s in named),
      f"the View lists every one of the {len(named)} named subtopics")
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
# Evidence pointers are listed AGGREGATED PER FILE (#615), not line-granular:
# the source file must appear, its line anchor must not.
check("host/w5.md" in view, "the evidence source files are listed")
check("host/w5.md:6@abc1234" not in view,
      "raw per-line pointers are NOT dumped into the View")
check(re.search(r"^\s+- \S+ ×\d+$", view, re.M),
      "a file cited more than once is aggregated with a count (path ×N)")
# The total stays printed beside the list, so "why this depth?" is still
# answerable from the same counts the estimate used.
check(re.search(r"- evidence pointers \(\d+\):", view),
      "the pointer TOTAL is still shown alongside the aggregated list")
check("Lesson 3" in view, "lesson-seed names are shown")
# Lesson seeds are budgeted the same way evidence is (#634): one per line,
# clipped, capped, remainder DISCLOSED — never one 10,000-character line.
check(re.search(r"- lesson seeds \(\d+\):", view),
      "the lesson-seed TOTAL is shown alongside the list")
check(re.search(r"^\s+- Lesson \d+$", view, re.M),
      "lesson seeds render ONE PER LINE, not comma-joined onto one line")
seed_block = re.search(r"- lesson seeds \(\d+\):\n((?:\s+- .*\n)+)", view)
check(seed_block and "…" in view and re.search(r"… and \d+ more seed\(s\)", view),
      "past the cap the remaining seeds are DISCLOSED, never silently dropped")

# The View is a human surface, so every line is budgeted (#633/#634). This is
# the guard that keeps an 818-line unreadable View from recurring unnoticed.
long_lines = [l for l in view.splitlines() if len(l) > 200]
check(not long_lines,
      f"no View line exceeds its display budget (worst: {max((len(l) for l in long_lines), default=0)} chars)")

# The placeholder states read as PROSE THAT STATES THE REMEDY, never as a bare
# internal enum in a headline position (#634).
check(not re.search(r"^#{2,3} .*\((?:unclustered|untracked|unnamed)\)", view, re.M),
      "no placeholder enum value appears in a heading")
check("not yet clustered" in view and "declare `subtopic:`" in view,
      "the not-yet-clustered state is named to the owner as prose with its remedy")
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

# --- the View LEADS WITH THE CANDIDATE DIRECTIONS (Story 18.76, #632) --------
# The size switch moves the terrain, never the proposing: the above-budget
# branch must offer no less guidance than the one-screen branch.
python3 - "$work/big-cands.json" "$work/view.md" <<'PYEOF' || fail=1
import json, re, sys
cands = json.load(open(sys.argv[1]))["candidates"]
view = open(sys.argv[2], encoding="utf-8").read()
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

heads = re.findall(r"^#{2,3} (.+)$", view, re.M)
check(heads and heads[0] == "Candidate directions",
      f"the View's FIRST section is the candidate directions (got {heads[:1]})")
check("The terrain at a glance" in heads
      and heads.index("The terrain at a glance") == 1,
      "the at-a-glance summary is the SECOND section, before any detail")
first_detail = next((i for i, h in enumerate(heads) if re.match(r"T\d+\.\d+ — ", h)), None)
check(first_detail is not None and first_detail > 1,
      "per-subtopic detail comes only AFTER directions and the summary")

# Every derived direction reaches the View, with the index selection uses.
block = view.split("## The terrain at a glance")[0]
# Elements are candidates too, but the View gives them their own section
# (Story 18.80) — this block covers the subtopic and combination directions.
directional = [c for c in cands if c.get("kind") != "element"]
missing = [c["id"] for c in directional if f"**{c['id']}**" not in block]
check(not missing, f"every derived direction appears in the section ({missing[:3]})")
check(len(directional) > 7, f"the fixture derives an over-budget candidate set ({len(directional)})")

# The combination move stays visible where the owner looks: combinations are
# few and are listed FIRST, so the singles cannot push them below the fold.
rows = re.findall(r"^- \*\*(\S+)\*\* — (.+)$", block, re.M)
combo_ids = {c["id"] for c in cands if c["kind"] == "combination"}
check(combo_ids, "the fixture derives at least one cross-topic combination")
positions = [i for i, (rid, _) in enumerate(rows) if rid in combo_ids]
check(positions and max(positions) < len(combo_ids),
      "combinations are listed before the single-subtopic directions")

# Roughly ten pickable candidates in the first screenful — the whole point of
# the section. Counted over the first 40 lines, header included.
head = "\n".join(view.splitlines()[:40])
check(len(re.findall(r"^- \*\*", head, re.M)) >= 10,
      "about ten pickable candidates are visible without scrolling")

# The summary is ONE LINE per subtopic, carrying index, depth word and glance.
summary = view.split("## The terrain at a glance")[1].split("\n## ")[0]
srows = re.findall(r"^- \*\*(T\d+\.\d+)\*\* — .+ · \[[#.]+\] ", summary, re.M)
check(len(srows) == len(set(srows)) and len(srows) >= 10,
      f"the summary carries one line per subtopic, with its glance ({len(srows)})")
# The depth word rides INSIDE the glance; printing it beside the glance would
# render the same word twice on every line.
check(not re.search(r"^- \*\*T\d+\.\d+\*\* — .+ · (\S.*) · \[[#.]+\] \1 ", summary, re.M),
      "the summary does not repeat the depth word beside the glance")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- coverage wording never carries a placeholder (18.78, #637) -------------
# The wording IS the brief on adoption, so this is asserted at the composed
# brief and not only at the surface.
python3 - "$work/big-map.json" "$work/big-cands.json" "$D" <<'PYEOF' || fail=1
import importlib.util, json, sys
d = json.load(open(sys.argv[1]))
cands = json.load(open(sys.argv[2]))["candidates"]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

PLACEHOLDERS = ("(unclustered)", "(untracked)", "(unnamed)")
subs = [s for t in d["topics"] for s in t["subtopics"]]
check(any(s["subtopic"] in PLACEHOLDERS or not str(s["subtopic"]).strip()
          for s in subs),
      "the fixture contains an unnamed / not-yet-clustered subtopic")

bad = [c["direction"] for c in cands
       if any(p in c["direction"] for p in PLACEHOLDERS)]
check(not bad, f"no candidate direction carries a placeholder enum ({bad[:2]})")
check(not any(c["direction"].strip() in ("cover", "cover ") for c in cands),
      "no candidate direction is left with an empty subject")

# The same rule at the BRIEF: adopting any index must never hand the owner an
# enum as their own wording.
spec = importlib.util.spec_from_file_location("d", sys.argv[3])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
pin = d["coverage"]["pin"]
briefs = [mod.brief_from_answer(
              {"index": c["id"], "note": "an angle", "pin": pin}, cands, pin)["brief"]
          for c in cands]
badb = [b for b in briefs if any(p in b for p in PLACEHOLDERS)]
check(not badb, f"no composed brief carries a placeholder enum ({badb[:2]})")
check(all(b.endswith("— an angle") for b in briefs),
      "the owner's note is still carried verbatim onto every composed brief")

# A NAMED cluster's wording is untouched: the articles repo still owns names.
# Stable IDs are assigned by the composer, not carried in the map, so the
# id-annotated view is what pairs a subtopic with its candidate.
named = [s for s in mod._subtopics(d)
         if str(s["subtopic"]).strip() and s["subtopic"] not in PLACEHOLDERS]
byid = {c["id"]: c for c in cands if c["kind"] == "single"}
check(all(byid[s["id"]]["direction"] == f"cover {s['subtopic']}"
          for s in named if s["id"] in byid),
      "a declared or derived name still produces exactly `cover <name>`")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- elements reach the surface and are pickable (18.80, #641) --------------
python3 - "$work/big-cands.json" "$work/view.md" "$work/big-map.json" "$D" <<'PYEOF' || fail=1
import importlib.util, json, re, sys
cands = json.load(open(sys.argv[1]))["candidates"]
view = open(sys.argv[2], encoding="utf-8").read()
d = json.load(open(sys.argv[3]))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

els = [c for c in cands if c.get("kind") == "element"]
check(len(els) == len(d["elements"]), f"every element reaches the candidate list ({len(els)})")
# Own namespace, no collision with the subtopic scheme.
eids = [c["id"] for c in els]
tids = [c["id"] for c in cands if c.get("kind") != "element"]
check(all(re.fullmatch(r"E\d+\.\d+", i) for i in eids), f"element ids are E<topic>.<n> ({eids})")
check(not (set(eids) & set(tids)), "element ids never collide with subtopic ids")
check(len(set(eids)) == len(eids), "element ids are unique")

# Its own section on the View, after the terrain summary, before the detail.
heads = re.findall(r"^#{2,3} (.+)$", view, re.M)
check("What you decided" in heads, f"the View carries an elements section ({heads[:4]})")
check(heads.index("What you decided") == 2, "the elements section follows the at-a-glance summary")
block = view.split("## What you decided")[1].split("\n## ")[0]
check(all(f"**{i}**" in block for i in eids), "every element appears in that section with its index")
check("reversal" in block and "decision" in block, "each element's kind is shown")
check("· consumed" in block, "a consumed element is MARKED, not hidden")
# The bound is never silent.
check("delivery" in block and "zeta" in block and "NOT covered" in block,
      "the section states which topics the elements came from, and which they did not")

# Wording carries no internal marker and becomes the brief on adoption (#637).
PLACEHOLDERS = ("(unclustered)", "(untracked)", "(unnamed)")
check(not any(p in c["direction"] for c in els for p in PLACEHOLDERS),
      "element wording carries no placeholder enum")
spec = importlib.util.spec_from_file_location("dd", sys.argv[4])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
pin = d["coverage"]["pin"]
out = mod.brief_from_answer({"index": eids[0], "note": "the angle I want", "pin": pin},
                            cands, pin)
check(out["brief"].endswith("— the angle I want"),
      f"an element index composes an ordinary brief with the note VERBATIM ({out['brief'][:60]}…)")
check(out["provenance"] == "owner-authored" and out["origin"] == "adopted-index",
      "an adopted element is owner-adopted wording, like any other index")
# A stale pin is refused for an element exactly as for a subtopic.
try:
    mod.brief_from_answer({"index": eids[0], "note": "x", "pin": "other@dead"}, cands, pin)
    check(False, "a stale-pin element selection is refused with the mismatch named")
except SystemExit:
    check(True, "a stale-pin element selection is refused with the mismatch named")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# Elements reach the IN-CONVERSATION screen too — the size switch moves where
# the terrain is presented, never what the map proposes.
python3 - "$work/map.json" "$D" "$work/small-el.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["elements"] = [{"kind": "decision", "summary": "A small-map decision",
                  "topic": "delivery", "date": "2026-07-20",
                  "situation": "topics/delivery.md:3@abc1234",
                  "evidence": ["topics/delivery.md:3@abc1234"], "consumed": False}]
d["coverage"] = dict(d.get("coverage", {}), element_topics_read=["delivery"],
                     element_topics_skipped=[])
json.dump(d, open(sys.argv[3], "w"))
PYEOF
python3 "$D" payload --map "$work/small-el.json" > "$work/small-el-payload.json" 2>/dev/null
python3 - "$work/small-el-payload.json" <<'PYEOF' && ok "elements are offered on the in-conversation screen, not only in the View" || err "elements never reach the small-map screen"
import json, sys
labels = [c["label"] for c in json.load(open(sys.argv[1]))["items"][0]["choices"]]
assert any("A small-map decision" in l for l in labels), labels
assert any("name your own" in l for l in labels) and labels[-1] == "stop here", labels
PYEOF
[ $? -eq 0 ] || fail=1

# --- the View shows the ESTIMATE, not the estimator's rule (18.77, #633) ----
python3 - "$work/big-map.json" "$work/view.md" "$D" <<'PYEOF' || fail=1
import importlib.util, json, re, sys
d = json.load(open(sys.argv[1]))
view = open(sys.argv[2], encoding="utf-8").read()
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

subs = [s for t in d["topics"] for s in t["subtopics"]]
withpred = [s for s in subs if "the next level needs" in s.get("depth", {}).get("why", "")]
check(withpred, "the fixture contains a subtopic with an UNMET promotion predicate")
# The predicate stays on the record: this is a rendering rule, not a data change.
check(all("the next level needs" in s["depth"]["why"] for s in withpred),
      "map.json still carries the promotion predicate (the depth harness reads it)")
# ...and never reaches the owner surface.
check("the next level needs" not in view,
      "the View does not carry the promotion predicate")
check(not re.search(r"^- depth: .*\d+ < \d+", view, re.M),
      "no threshold arithmetic appears on a depth line")
# The counts DO stay — CAP-2's "why this depth?" is answered from them.
check(re.search(r"^- depth: .+ \d+ evidence pointer\(s\)", view, re.M),
      "the depth line still shows the level and the counts it was derived from")

# A trim must never swallow a DISCLOSURE: a `why` with no predicate is passed
# through whole, including "no depth-threshold declaration is readable".
spec = importlib.util.spec_from_file_location("d", sys.argv[3])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
disclosure = ("no depth-threshold declaration is readable, so no estimate "
              "is offered (nothing declared)")
check(mod._depth_line({"depth": {"why": disclosure}}) == disclosure,
      "a why carrying no predicate passes through unchanged (disclosure preserved)")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# NO SECOND PROPOSER: the View renders the directions it is GIVEN. A
# `candidates()` call inside compose_view would be a second derivation, and the
# screen and the View could then silently disagree about what was offered.
python3 - "$D" <<'PYEOF' && ok "the View reuses the derived directions and derives none of its own" || err "compose_view derives its own directions (second proposer)"
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
fn = next(n for n in ast.parse(src).body
          if isinstance(n, ast.FunctionDef) and n.name == "compose_view")
calls = {n.func.id for n in ast.walk(fn)
         if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
sys.exit(1 if "candidates" in calls else 0)
PYEOF

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
