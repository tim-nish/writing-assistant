#!/usr/bin/env sh
# tier: inner — screen-composition assertions against the committed fixture
#   map (scripts/fixtures/terrain/screen-map.json); no seam, no corpus, no
#   assembly. Measured 2026-07-30 at adoption: ~1.5s.
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-compose-inner.sh — candidate derivation, the ONE screen and
# the size switch, split from check-topic-map-screen.sh (Story 20.49, #923).
# The fixture map is the map the full check assembles from its fixture repos,
# captured at adoption; check-topic-map-screen.sh (tier: full) re-assembles
# it every run and fails on drift, so this file can never silently test a
# stale shape.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/terrain_map.py"
D="scripts/topic-map-directions.py"
VP="scripts/validate-proposal-payload.py"
SKILL="skills/terrain/SKILL.md"
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/ws"
cp "$FIX" "$work/map.json"

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
# CROSS-TOPIC COMBINATIONS ARE DEFERRED (Story 20.7, #809) — asserted absent
# WITH ITS REASON, never deleted silently. CAP-3 still promises the move; what
# does not exist is evidence that could support one, because a Strand's only
# pointer is the surface it was read from ("Its own index line is its evidence
# pointer", scripts/terrain_map.py lesson_item). Pairing on that made every
# cross-topic pair share `LESSONS.md`.
combos = [x for x in c if x["kind"] == "combination"]
check(not combos,
      f"no combination is derived while the move is deferred behind OQ3 ({combos[:1]})")
# The DEFERRAL IS RECORDED IN THE CODE, so a future reader meets the reason
# rather than an unexplained gap — this is what distinguishes a deferral from
# a silent retirement.
src = open("scripts/topic-map-directions.py", encoding="utf-8").read()
check("DEFERRED, not derived" in src and "OQ3" in src,
      "the deferral and its reopen trigger are stated where the move used to be")
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
# The combination candidate is DEFERRED (Story 20.7, #809), so no "connect …"
# label reaches the screen. Asserted absent rather than dropped: a screen that
# silently stopped offering the move would be indistinguishable from one where
# the evidence simply did not support one that run.
check(not any(l.startswith("connect ") for l in labels),
      f"no combination candidate is offered while the move is deferred ({labels[:2]})")
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
import json, sys
d = json.load(open(sys.argv[1]))
# An OVER-BUDGET terrain, built from STRANDS (Story 20.7, #809). It used to be
# built by cloning subtopics; subtopics no longer exist, and a Strand is now
# the only thing that counts toward the screen budget.
strands = list(d.get("elements") or [])
for n in range(12):                       # comfortably past the screen budget
    strands.append({
        "kind": "lesson", "slug": f"widened-{n:02d}",
        "title": f"Lesson {n}",
        # Two topics, so topic-spanning rendering is still exercised.
        "topic": "engineering" if n % 2 else "people",
        "date": f"2026-07-{(n % 28) + 1:02d}",
        "gloss": f"A claim the material itself makes, number {n}",
        "situation": f"LESSONS.md:{n + 10}@abc1234",
        "evidence": [f"LESSONS.md:{n + 10}@abc1234"],
        "consumed": (n == 0),
    })
# A strand whose rendering was NOT served: it must still appear, with the
# reason disclosed, never dropped and never quoting the one-liner as a gloss.
strands.append({
    "kind": "lesson", "slug": "no-rendering", "title": "Unrendered lesson",
    "topic": "people", "date": "2026-07-02",
    "gloss": None,
    "gloss_unavailable": "the served gloss index carries no rendering for this lesson",
    "situation": "LESSONS.md:40@abc1234",
    "evidence": ["LESSONS.md:40@abc1234"], "consumed": False,
})
d["elements"] = strands
d["coverage"] = dict(d.get("coverage", {}),
                     element_topics_read=["delivery", "engineering", "people", "nowhere"],
                     element_topics_skipped=["zeta"])
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

python3 - "$work/big-map.json" "$work/view.md" "scripts/terrain_text.py" \
         <<'PYEOF' || fail=1
import importlib.util, json, re, sys
d = json.load(open(sys.argv[1]))
view = open(sys.argv[2], encoding="utf-8").read()
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# STORY 20.5 (#802): the View is the header plus Candidate Directions, and
# NOTHING ELSE. ~2,300 of a 2,511-line view served no function the owner could
# identify, so this asserts the ABSENCE of the three deleted sections — a
# regression that re-adds one fails here rather than being noticed by token
# cost months later.
heads = re.findall(r"^## (.+)$", view, re.M)
check(heads == ["Candidate directions"],
      f"the View carries exactly ONE section: Candidate directions ({heads})")
for gone in ("Subtopic clusters", "Maintenance", "Diagnostics"):
    check(not any(h.startswith(gone) for h in heads),
          f"the {gone!r} section is gone from the View")
check(not re.search(r"^#### T\d+\.\d+ — ", view, re.M),
      "no per-subtopic detail block survives")
check("- glance:" not in view and "- evidence pointers (" not in view,
      "the per-subtopic diagnostics fields are gone")

# CAP-4's duty is discharged by a LINE, and dropping these would be a real
# regression rather than more cleanup (SPEC-terrain, amended 2026-07-27).
# Compared against the emitters themselves, not against guessed wording: a
# substring test would keep passing if the line silently changed shape.
#
# The emitters moved to their own leaf module (Story 20.58, #942), so they are
# loaded from THERE — through the new module's own path, never through the
# composer's re-export, so deleting one where it now lives fails here.
spec = importlib.util.spec_from_file_location("dvtext", sys.argv[3])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
cov_line = mod._element_coverage_line(d)
gloss_line = mod._gloss_disclosure_line(d)
check(cov_line in view,
      "the one-line element coverage disclosure still sits under the directions")
check(gloss_line in view,
      "the one-line gloss disclosure still sits under the directions")
# The disclosure must reach the surface WHOLE. `_clip_line` would otherwise
# truncate the reason — the actionable half — mid-word, leaving a disclosure
# that names a gap without naming its remedy (Story 20.5, #802).
check(len(gloss_line) <= mod.VIEW_LINE_CHARS,
      f"the gloss disclosure fits the View line budget uncut ({len(gloss_line)})")
check(len(cov_line) <= mod.VIEW_LINE_CHARS,
      f"the coverage disclosure fits the View line budget uncut ({len(cov_line)})")
check("below" not in gloss_line and "maintenance" not in gloss_line.lower(),
      "no disclosure line points at a section this story deleted")

# The header survives whole: it is what the amended CAP-2 points at.
check(d["coverage"]["pin"] in view, "the View header carries the map's pin")
check(re.search(r"\d+ topic", view), "the header carries the terrain-size line")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# The caps stop being fixed constants above the budget.
python3 "$D" candidates --map "$work/big-map.json" > "$work/big-cands.json"
python3 -c "
import json
c=json.load(open('$work/big-cands.json'))['candidates']
strands=[x for x in c if x['kind']=='element']
assert len(strands) > 3, len(strands)
" && ok "size switch: above the budget the fixed candidate caps no longer apply" \
  || err "the over-budget branch is still capped at the screen constants"

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
