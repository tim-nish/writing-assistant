#!/usr/bin/env sh
# parallel-safe
# check-terrain-member.sh — Screen 2's sectioning is a PERMUTATION, and its
# sections carry NO SELECTION AUTHORITY (Story 20.9, #811; SPEC-terrain as
# resolved 2026-07-27).
#
# The completeness invariant is the whole point: every Strand of the selected
# member appears in AT LEAST ONE section — count-in == count-out over distinct
# Strands — so the information loss the abandoned cluster unit suffered cannot
# compile, and the worst case is a badly grouped but complete list. This check
# FAILS LOUDLY on a dropped Strand; a count mismatch is never a warning.
#
# It is a COVER, not a partition (Story 20.36, #890): under a multi-valued
# substrate a Strand belongs in every section it relates to, and PLACEMENTS
# are the counting unit for the >20% cap. Exactly-once survives as the
# stronger check wherever the substrate is single-valued.
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

D="scripts/topic-map-directions.py"

python3 - "$D" <<'PYEOF' || fail=1
import json, os, re, subprocess, sys, tempfile
D = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# A member large enough to exercise serve-whole (the measured worst case is
# 40-53), with co-tags to section by, a co-tagless Strand, and a consumed one.
els = []
for n in range(40):
    els.append({"kind": "lesson", "slug": f"w{n}", "title": f"W{n}",
                "gloss": f"claim {n}", "tags": ["workflow", "agents" if n % 2 else "cost"],
                "evidence": [], "consumed": False})
els.append({"kind": "lesson", "slug": "solo", "title": "Solo",
            "gloss": "a workflow-only claim", "tags": ["workflow"],
            "evidence": [], "consumed": True})
els.append({"kind": "journey", "slug": "other", "title": "Other",
            "gloss": "not in this member", "tags": ["agents"],
            "evidence": [], "consumed": False})
m = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
     "elements": els}
f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(m, f); f.close()
run = lambda tag, axis="tag": subprocess.run(
    ["python3", D, "member", "--map", f.name, "--tag", tag, "--axis", axis],
    capture_output=True, text=True)

out = run("workflow")
check(out.returncode == 0, f"member composes (rc={out.returncode})")
d = json.loads(out.stdout)

# --- THE PERMUTATION -------------------------------------------------------
member_slugs = {e["slug"] for e in els if "workflow" in e["tags"]}
sectioned = [s for sec in d["sections"] for s in sec["strands"]]
check(len(sectioned) == len(member_slugs) == d["count"] == 41,
      f"count-in == count-out ({len(member_slugs)} in, {len(sectioned)} out)")
check(len(set(sectioned)) == len(sectioned), "no Strand appears twice")
check(set(sectioned) == member_slugs, "no Strand is dropped and none invented")
check("other" not in sectioned, "a Strand outside the member never leaks in")

# --- SERVED WHOLE ----------------------------------------------------------
ids = re.findall(r"^- \*\*((?:L|J)\d+|E\d+\.\d+)\*\* — ", d["listing"], re.M)
check(len(ids) == 41, f"the listing carries every Strand, whole ({len(ids)} lines)")
check("41 Strand(s), shown whole" in d["listing"],
      "the count is disclosed on the listing")

# --- NO SELECTION AUTHORITY ------------------------------------------------
check("already consumed, still selectable" in d["listing"],
      "a consumed Strand is marked, never hidden")
heads = re.findall(r"^## (.+) \(\d+\)(?: — .+)?$", d["listing"], re.M)
check(len(heads) == len(d["sections"]) >= 2,
      f"sections carry a title and a count — presentation only ({heads[:3]})")

# --- the sectioning contract: no direct parent over 20% (Story 20.23, #852) --
total = d["count"]
cap = max(3, int(total * 0.2))
over = [(s["title"], len(s["strands"])) for s in d["sections"]
        if len(s["strands"]) > cap]
undisclosed = [t for t, _n in over
               if f"{t} ({dict(over)[t]}) — over the one-fifth bound"
               not in d["listing"]]
check(not undisclosed,
      f"every over-cap section discloses the bound on its title line ({over})")
# A subdividable fixture: one dominant co-tag whose Strands carry a second
# co-tag, so the 20% rule has a deterministic key to subdivide on.
els3 = []
for n in range(30):
    els3.append({"kind": "lesson", "slug": f"s{n}", "title": f"S{n}",
                 "gloss": f"claim {n}",
                 "tags": ["workflow", "agents", "cost" if n % 2 else "risk"],
                 "evidence": [], "consumed": False})
m3 = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
      "elements": els3}
f3 = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(m3, f3); f3.close()
out3 = subprocess.run(["python3", D, "member", "--map", f3.name,
                       "--tag", "workflow"], capture_output=True, text=True)
d3 = json.loads(out3.stdout)
cap3 = max(3, int(30 * 0.2))
titles3 = [s["title"] for s in d3["sections"]]
check(any(" + " in t for t in titles3),
      f"an over-cap section subdivides on the next shared label ({titles3})")
listing3 = d3["listing"]
bad3 = [s["title"] for s in d3["sections"]
        if len(s["strands"]) > cap3
        and "over the one-fifth bound" not in
        (listing3.split(f"## {s['title']} (")[1].split("\n")[0]
         if f"## {s['title']} (" in listing3 else "")]
check(not bad3,
      f"every section is under the bound or discloses why not ({bad3})")
sectioned3 = [s for sec in d3["sections"] for s in sec["strands"]]
# COMPLETENESS IS A COVER counted in PLACEMENTS (Story 20.36, #890): each of
# these Strands carries two co-tags besides `workflow`, so it belongs in two
# sections. Every Strand appears at LEAST once — the assertion the contract
# actually makes — and the placement total is what the cap is computed
# against. The old exactly-once form was written for a single-valued key and
# is false here; asserting it would demand a tie-break that hides half of
# every Strand's relationships.
check(len(set(sectioned3)) == 30,
      f"every Strand is covered — count-in == count-out over distinct Strands ({len(set(sectioned3))})")
check(len(sectioned3) >= 30 and d3["placements"] == len(sectioned3),
      f"placements are the counting unit and are reported ({d3.get('placements')} vs {len(sectioned3)})")
check(d3["covered"] is True and d3["substrate"] == "co-tags",
      f"the substrate names itself and asserts its own coverage ({d3.get('substrate')}, {d3.get('covered')})")
# Small-member floor: 20% of 5 is 1; the floor keeps sections >= viable size.
els5 = [{"kind": "lesson", "slug": f"t{n}", "title": f"T{n}",
         "gloss": f"c {n}", "tags": ["workflow", "agents"],
         "evidence": [], "consumed": False} for n in range(5)]
m5 = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
      "elements": els5}
f5 = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(m5, f5); f5.close()
out5 = subprocess.run(["python3", D, "member", "--map", f5.name,
                       "--tag", "workflow"], capture_output=True, text=True)
d5 = json.loads(out5.stdout)
check(all(len(s["strands"]) >= 1 for s in d5["sections"])
      and len(d5["sections"]) <= 2,
      "the small-member floor prevents one-Strand fragmentation")
for banned in ("ranked", "top ", "best "):
    check(banned not in d["listing"].lower(),
          f"no ranking language on the listing ({banned!r})")

# --- deterministic context fields (Story 20.21, #845) -----------------------
ctx = re.findall(r"^  \((?:also in: .+|in no other Topic).*$", d["listing"], re.M)
check(len(ctx) == 41,
      f"every Strand line carries its deterministic context line ({len(ctx)})")
check(any("in no other Topic" in c for c in ctx),
      "a co-tagless Strand states the absence of other Topics, never a guess")
check(any("origin not recorded" in c for c in ctx),
      "an unrecorded origin is stated as absent, never invented")
check(all("·" in c for c in ctx),
      "context lines carry all three fields on the one line")

# --- journey presence: ABSENCE is marked, and the denominator is stated ------
# (Story 20.51, #933/#934; CAP-2 as amended and corrected 2026-07-30.)
# The fixture's Strands carry no `journey_recorded`, so EVERY row is thin —
# which makes the polarity assertable in both directions from one run.
cov = [ln for ln in d["listing"].split("\n") if "carry journey material" in ln]
check(len(cov) == 1,
      f"the screen states its journey-coverage denominator exactly once ({len(cov)})")
check(re.search(r"\b0 of \d+ Strands carry journey material", cov[0] or ""),
      f"the denominator counts this screen's own Strands ({cov[0] if cov else None!r})")
check(all("no-journey" in c for c in ctx),
      "a Strand with no paired journey record is marked on its own row")
# Polarity, the other way round: a row WITH a record carries no marker.
els_j = [{"kind": "lesson", "slug": "with-arc", "title": "W", "gloss": "c",
          "tags": ["workflow"], "evidence": [], "consumed": False,
          "journey_recorded": True},
         {"kind": "lesson", "slug": "no-arc", "title": "N", "gloss": "c",
          "tags": ["workflow"], "evidence": [], "consumed": False,
          "journey_recorded": False}]
mj = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
      "elements": els_j}
fj = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(mj, fj); fj.close()
dj = json.loads(subprocess.run(["python3", D, "member", "--map", fj.name,
                                "--tag", "workflow"],
                               capture_output=True, text=True).stdout)
ctxj = re.findall(r"^  \((?:also in: .+|in no other Topic).*$", dj["listing"], re.M)
check(sum(1 for c in ctxj if "no-journey" in c) == 1,
      f"presence is SILENT and only absence is marked ({ctxj})")
check("1 of 2 Strands carry journey material" in dj["listing"],
      "the denominator reports the mixed case correctly")
# The wrong-kind claim this amendment exists to stop.
check("no Journey" not in dj["listing"],
      "no screen asserts that no Journey material falls under the member")
os.unlink(fj.name)

# --- background composition: script owns sections, composer owns prose ------
# (Story 20.24, #853; CAP-2 as amended 2026-07-27 #850.)
bg = d.get("background") or {}
check(bg.get("authoring") == "machine-composed at render time, marked",
      "the background block declares its authoring class")
check(len(bg.get("inputs") or []) == len(d["sections"]),
      "composition inputs cover every section — none omitted")
check(all(len(i["claims"]) == len(s["strands"])
          for i, s in zip(bg["inputs"], d["sections"])),
      "every Strand's claim is a composition input (count-in == count-in)")
rules = " ".join(bg.get("rules") or [])
# The authoring declaration is owed ONCE PER SURFACE, not once per line
# (Story 20.53, #936). Both halves of the conditional are asserted — the
# preamble discharge AND the minority re-arming — because a rule that stated
# only the first would license dropping the marker on a mixed screen, which
# is the case the marker exists for. "never silent" and "machine-composed"
# stay in the list unweakened: the obligation's force is unchanged.
for phrase in ("never omits, merges, ranks, or gates",
               "machine-composed", "never silent",
               "once on the surface", "mark the minority"):
    check(phrase in rules, f"the binding rules state: {phrase!r}")
check("mark each background line as machine-composed" not in rules,
      "the unconditional per-line rule is gone (#936)")

# --- determinism + selection contract --------------------------------------
check(out.stdout == run("workflow").stdout, "byte-identical across invocations")
check(re.search(r"^- \*\*L\d+\*\* — ", d["listing"], re.M),
      "lines carry the candidate ids selection already resolves")

# --- an empty member is a disclosed refusal --------------------------------
# The refusal names the member AND the axis it was looked up in (Story 20.25):
# the two vocabularies overlap, so "not found" without the axis would leave the
# owner unable to tell a wrong name from a right name on the wrong axis.
bad = run("no-such-tag")
check(bad.returncode != 0 and "no Strand sits under the tag" in bad.stderr
      and "no-such-tag" in bad.stderr,
      "an unknown tag member is refused with the reason named")
bad_topic = run("no-such-topic", "topic")
check(bad_topic.returncode != 0
      and "no Strand sits under the topic" in bad_topic.stderr,
      "an unknown topic member is refused, naming the topic axis")

# --- NEGATIVE TEST: a broken cover must fail RED ---------------------------
# Simulated at the assertion layer: feed the checker a sectioning that drops
# one Strand and assert THIS logic would catch it (a check never shown to
# fire is a clean bill nobody earned).
dropped = sectioned[1:]
check(not (len(dropped) == len(member_slugs)),
      "negative test: a dropped Strand breaks count-in == count-out")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- E rows disclose an un-served rendering; row kinds are named ------------
# (Story 20.20, #843.) A decision/reversal Strand with no served rendering
# carries the SAME not-served disclosure shape lesson rows use — the raw
# recall-register topic line is never presented as if it were a rendering —
# and the disclosure retires BY DETECTION the moment a rendering is served.
python3 - "$D" <<'PYEOF' || fail=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dv", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

raw = ("The disposition axis is ADOPTED for the hub's own lane: a parked "
       "item's state must be legible on the issue.")
bare = {"kind": "decision", "summary": raw, "topic": "knowledge-architecture",
        "date": "2026-07-22", "situation": "x:1@abc1234",
        "evidence": ["x:1@abc1234"], "consumed": False}
line = m._element_direction(bare)
check("its plain-language rendering is not being served" in line,
      "an un-served decision row carries the lesson-row disclosure shape")
check(raw not in line,
      "the raw topic line is never presented as if it were a rendering")
check("2026-07-22" in line and "knowledge-architecture" in line,
      "the disclosure still identifies the record (date and source)")
served = dict(bare, gloss="We adopted a rule that a parked item says so on "
                          "its own issue.")
line2 = m._element_direction(served)
check("not being served" not in line2 and served["gloss"] in line2,
      "a served rendering retires the disclosure by detection")
mm = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@1"},
      "elements": [bare]}
cand = m.candidates(mm)[0]
check(not cand.get("why"),
      "an un-served decision row leads with no claim (fallback-shaped)")
check(m.candidates({"kind": "topic-map", "topics": [],
                    "coverage": {"pin": "h@1"},
                    "elements": [served]})[0].get("why") == served["gloss"],
      "a served rendering becomes the row's claim")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- the row-kind legend is on both reading surfaces ------------------------
# Story 20.66 (#978): the legend is COMPOSED from the row types present, so
# the sentence lives in terrain_text.py and each surface calls it. Asserting
# the call rather than the literal is what keeps a screen from re-acquiring a
# hard-coded row type the id-minting path never emits.
# Story 20.80 (#1029): the View's composer moved to terrain_screens.py with the
# rest of the screen compositions; the assertion follows the call site.
grep -q "def row_type_legend" scripts/terrain_text.py \
  && grep -q "row_type_legend(" scripts/terrain_screens.py \
  && grep -q "row_type_legend(" scripts/terrain_members.py \
  && ok "the row-kind legend is composed for both reading surfaces" \
  || err "the row-kind legend is missing from a reading surface"

# It must never name `J` rows: the namespace was retired with the Journey id
# (#871/#933), so a legend mentioning it describes a row that cannot exist.
grep -q "J rows are Journeys" scripts/terrain_text.py scripts/terrain_members.py \
     scripts/terrain_screens.py "$D" \
  && err "a reading surface still names J rows — the namespace is retired (#933)" \
  || ok "no reading surface names the retired J row type"

# --- the Journey shortfall is DISCLOSED, detection-based (Story 20.10, #812) --
python3 - "$D" "scripts/terrain_text.py" "scripts/terrain_members.py" <<'PYEOF' || fail=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dv", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# The disclosure emitter moved to its own leaf module (Story 20.58, #942).
# Loaded from THAT path, never through the composer's re-export: deleting it
# where it now lives has to fail here.
tspec = importlib.util.spec_from_file_location("dvtext", sys.argv[2])
# Story 20.65 (#974): the member surface moved to terrain_members.py.
mmspec = importlib.util.spec_from_file_location("dvmem", sys.argv[3])
t = importlib.util.module_from_spec(tspec); tspec.loader.exec_module(t)
mm = importlib.util.module_from_spec(mmspec); mmspec.loader.exec_module(mm)
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

base = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@1"},
        "elements": [{"kind": "lesson", "slug": "a", "title": "A",
                      "gloss": "claim", "tags": ["workflow"],
                      "evidence": [], "consumed": False}]}
# NOT REQUESTED (Story 20.30, #871): no lesson names a shard, so nothing was
# asked for. This must NEVER be reported as the hub failing to serve — the two
# are facts about different parties, and the old line said the second while
# meaning the first, which sent a real triage after a hub gap that did not
# exist (CAP-4, amended 2026-07-28).
gap = dict(base, gloss={"served": True, "lesson_renderings": 3,
                        "journey_renderings": 0, "journeys_requested": [],
                        "journey_misses": {}})
line = t._journey_disclosure_line(gap)
check(line is not None and "requested" in line.lower(),
      "nothing requested yields the shortfall as a LINE, named as not-requested")
check("served at this pin" not in line,
      "a not-requested corpus is NEVER reported as a not-served one")
check("\n" not in line and "##" not in line,
      "the disclosure is a line, never a section")
check("requested" in m.compose_axis_payload(gap)["items"][0]["where"].lower(),
      "the shortfall is named on the axis screen")
check("requested" in
      mm.compose_member_listing(gap, "workflow", m.candidates(gap)).lower(),
      "the shortfall is named on the member listing")
# REQUESTED AND MISSING: a different fact, and an abnormal condition to fix.
missing = dict(base, gloss={"served": True, "lesson_renderings": 3,
                            "journey_renderings": 0,
                            "journeys_requested": ["journeys/workflow"],
                            "journey_misses": {"journeys/workflow": "served a miss"}})
mline = t._journey_disclosure_line(missing)
check(mline is not None and "journeys/workflow" in mline
      and "abnormal condition" in mline,
      "a requested shard that did not arrive is named as the abnormal condition")
check(mline != line,
      "requested-and-missing is a DIFFERENT line from not-requested")
ok_served = dict(base, gloss={"served": True, "lesson_renderings": 3,
                              "journey_renderings": 2,
                              "journeys_requested": ["journeys/workflow"]})
check(t._journey_disclosure_line(ok_served) is None,
      "served journeys retire the disclosure BY DETECTION, no flag to flip")
down = dict(base, gloss={"served": False, "reason": "gateway down"})
check(t._journey_disclosure_line(down) is None,
      "a whole-gloss outage is the gloss line's to name — no double disclosure")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1


# --- Story 20.36 (#890): grouping runs on a NAMED SUBSTRATE, and completeness
# is a COVER counted in PLACEMENTS (SPEC-terrain CAP-2 as amended 2026-07-29).
python3 - <<'SUBSTRATE_EOF'
import json, subprocess, tempfile, sys

D = "scripts/topic-map-directions.py"
fail = 0


def check(cond, msg):
    global fail
    if cond:
        print(f"ok:   {msg}")
    else:
        print(f"FAIL: {msg}", file=sys.stderr)
        fail = 1


def member(els, tag):
    m = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
         "elements": els}
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(m, f); f.close()
    r = subprocess.run(["python3", D, "member", "--map", f.name, "--tag", tag],
                       capture_output=True, text=True)
    return json.loads(r.stdout)


# --- AC1/AC2: a multi-valued substrate is a COVER, and it names itself ------
# Each Strand carries two co-tags besides `agents`, so each belongs in two
# sections. The single-valued predecessor would have hidden one of the two.
els = [{"kind": "lesson", "slug": f"m{n}", "title": f"M{n}", "gloss": f"g{n}",
        "tags": ["agents", "cost", "method"], "evidence": [], "consumed": False}
       for n in range(10)]
d = member(els, "agents")
placed = [s for sec in d["sections"] for s in sec["strands"]]
check(d["substrate"] == "co-tags", f"the active substrate is named ({d['substrate']})")
check(len(set(placed)) == 10 and d["covered"] is True,
      "every Strand is covered at least once (count-in == count-out over distinct Strands)")
check(len(placed) == 20 and d["placements"] == 20,
      f"a multi-valued substrate PLACES each Strand under every co-tag it carries ({d['placements']})")
titles = {s["title"] for s in d["sections"]}
check(any(t.startswith("also cost") for t in titles)
      and any(t.startswith("also method") for t in titles),
      f"both relationships are visible, not just the alphabetically-first ({sorted(titles)})")

# --- AC3: no-relation Strands get an EXPLICIT NAMED section ----------------
els2 = [{"kind": "lesson", "slug": "solo", "title": "Solo", "gloss": "g",
         "tags": ["agents"], "evidence": [], "consumed": False}]
els2 += [{"kind": "lesson", "slug": f"p{n}", "title": f"P{n}", "gloss": "g",
          "tags": ["agents", "cost"], "evidence": [], "consumed": False}
         for n in range(4)]
d2 = member(els2, "agents")
no_rel = [s for s in d2["sections"] if s["title"] == "no shared co-tag"]
check(len(no_rel) == 1 and no_rel[0]["strands"] == ["solo"],
      f"a Strand sharing nothing lands in an explicitly NAMED section, never dropped ({[s['title'] for s in d2['sections']]})")
placed2 = [s for sec in d2["sections"] for s in sec["strands"]]
check(len(set(placed2)) == 5 and d2["covered"] is True,
      "the no-relation section participates in the coverage assertion")
check([s["title"] for s in d2["sections"]][-1] == "no shared co-tag",
      "the no-relation section sorts LAST by a declared key — ordering, never ranking")

# --- AC4: the cap is computed against PLACEMENTS ---------------------------
# 30 Strands x 2 co-tags = 60 placements. A cap on Strands (6) would demand
# subdivisions this material cannot support; on placements it is 12.
els4 = [{"kind": "lesson", "slug": f"c{n}", "title": f"C{n}", "gloss": "g",
         "tags": ["agents", "cost", "risk" if n % 2 else "method"],
         "evidence": [], "consumed": False} for n in range(30)]
d4 = member(els4, "agents")
check(d4["placements"] == 60,
      f"placements exceed the member count under a multi-valued substrate ({d4['placements']} vs {d4['count']})")
cap = max(3, int(d4["placements"] * 0.2))
undisclosed = [s["title"] for s in d4["sections"]
               if len(s["strands"]) > cap and not s.get("note")]
check(not undisclosed,
      f"every section is under the placement cap or discloses why not ({undisclosed})")

# --- AC6: the mega-group anti-pattern cannot render silently ---------------
# One meaningless group holding the whole member is the recorded T4.1 collapse.
biggest = max(len(s["strands"]) for s in d4["sections"])
check(biggest < d4["count"] or any(s.get("note") for s in d4["sections"]),
      f"no single section silently holds the whole member ({biggest} of {d4['count']})")

# --- presentation-only: nothing here gates selection -----------------------
check(all("strands" in s and s["strands"] for s in d4["sections"]),
      "no section is empty — a grouping never removes material")

sys.exit(1 if fail else 0)
SUBSTRATE_EOF
[ $? -eq 0 ] || fail=1


# --- Story 20.37 (#891): a Journey-similarity substrate that groups but cannot
# narrow — BUILT AND NOT OFFERED until one measurement run passes an owner
# verdict (SPEC-terrain CAP-2's offering gate, #889).
python3 - <<'JOURNEY_EOF'
import importlib.util, json, subprocess, tempfile, sys

D = "scripts/topic-map-directions.py"
# Story 20.65 (#974): the member surface now lives in terrain_members.py.
# D stays the CLI entry point; the module inspected is where the code is.
M = "scripts/terrain_members.py"
spec = importlib.util.spec_from_file_location("dv", M)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = 0


def check(cond, msg):
    global fail
    if cond:
        print(f"ok:   {msg}")
    else:
        print(f"FAIL: {msg}", file=sys.stderr)
        fail = 1


def mkmap(els):
    d = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
         "elements": els}
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(d, f); f.close()
    return f.name


def member(path, tag, extra=()):
    r = subprocess.run(["python3", D, "member", "--map", path, "--tag", tag,
                        *extra], capture_output=True, text=True)
    return json.loads(r.stdout)


els = [{"kind": "lesson", "slug": f"a{n}", "title": f"A{n}", "gloss": f"g{n}",
        "tags": ["agents", "cost"], "journey": f"arc {n}",
        "journey_cite": f"gloss/journeys/agents.md:{n}@abc1234",
        "evidence": [], "consumed": False} for n in range(6)]
# Two Strands with NO served arc — distinguishable from "no arc exists".
els += [{"kind": "lesson", "slug": f"n{n}", "title": f"N{n}", "gloss": "g",
         "tags": ["agents"], "journey": None,
         "journey_unavailable": "the journey shard was not served",
         "evidence": [], "consumed": False} for n in range(2)]
path = mkmap(els)

# --- Story 20.82 (#1031) AC1/AC6: OFFERED, and the default is unchanged -----
# The gate this replaces (#889) asserted the substrate was withheld. It ran on
# 2026-07-31 over the `agents` member and the owner verdicted PASS, so the
# assertion flips to its discharged form: offered, and NOT promoted. Both
# halves are checked, because "offer it" and "make it the default" are one
# edit apart and only the first was ratified.
check(m.JOURNEY_SUBSTRATE in m.SUBSTRATES,
      "the judged substrate is in the OFFERED set (#889's gate, discharged 2026-07-31)")
check(m.SUBSTRATE_DEFAULT == "co-tags",
      f"offering did not promote: the default is still co-tags ({m.SUBSTRATE_DEFAULT})")
d_off = member(path, "agents")
check(d_off["substrate"] == "co-tags" and d_off["substrate_offered"] is True,
      f"a run naming no substrate composes on co-tags ({d_off['substrate']})")
d_js = member(path, "agents", ["--substrate", "journey-similarity"])
check(d_js["substrate_offered"] is True,
      "substrate_offered reports TRUE for journey similarity (AC1)")

# --- AC4: arcs come from the SERVED rendering ------------------------------
r = subprocess.run(["python3", D, "journey-inputs", "--map", path,
                    "--tag", "agents"], capture_output=True, text=True)
ji = json.loads(r.stdout)
check(ji["count"] == 8 and ji["served"] == 6,
      f"inputs carry every Strand and count what is SERVED ({ji['served']}/{ji['count']})")
check(ji["offered"] is True,
      "the inputs surface states the substrate IS offered (gate discharged)")
by = {x["slug"]: x for x in ji["inputs"]}
check(by["a0"]["arc"] == "arc 0" and by["a0"]["arc_cite"].startswith("gloss/journeys/"),
      "an arc is the served rendering, quoted with its cite")
check(by["n0"]["arc"] is None and by["n0"]["served"] is False
      and by["n0"]["not_served_reason"],
      "a Strand with no served arc says NOT SERVED with its reason — never 'no arc exists'")

# --- AC1/AC2: the composer PLACES; omission is re-attached, not accepted ----
grouping = [{"in_common": "shared path X", "members": ["a0", "a1"]}]
d = member(path, "agents", ["--substrate", "journey-similarity",
                            "--grouping", json.dumps(grouping)])
placed = [s for sec in d["sections"] for s in sec["strands"]]
check(len(set(placed)) == 8 and d["covered"] is True,
      f"every Strand is covered AFTER composition ({len(set(placed))} of {d['count']})")
check(d["placements"] == len(placed),
      "placements are counted on the composed output, not on the proposal")
titles = {s["title"]: s for s in d["sections"]}
check("shared path X" in titles, "the composer's own grouping is honoured")

# --- #1017: the COMPOSED LISTING renders the same substrate as `sections` ---
# The defect this catches: `compose_member_listing` called `member_sections`
# without substrate/grouping, so in composed mode the `listing` rendered
# CO-TAG sections while `sections` beside it rendered the judged grouping —
# one response answering the same question two ways.
#
# Every assertion above reads `sections`, which was always correct; that is
# why nothing caught it. The composed listing is the surface an owner actually
# READS (Story 20.66 made the script compose it end to end precisely so a
# relay could not reword it), so it is the one that must be checked.
dc = member(path, "agents", ["--substrate", "journey-similarity",
                             "--grouping", json.dumps(grouping),
                             "--claims", json.dumps({"G1": "shared path X"})])
listing = dc["listing"]
sec_titles_expected = [s["title"] for s in dc["sections"]]
check("shared path X" in listing,
      "the composed listing renders the JUDGED grouping's section title")
# Assert over HEADINGS, never over the whole body: `(also in: …)` legitimately
# appears on Strand ROWS on every screen (Screen 2 keeps the context line on
# the row by design), so a naive substring test over the body passes or fails
# on fixture co-tagging rather than on the defect.
heads = [ln for ln in listing.splitlines() if ln.startswith("## ")]
stray = [h for h in heads if not any(t in h for t in sec_titles_expected)]
check(not stray,
      f"every heading in the composed listing belongs to the JUDGED grouping — "
      f"a co-tag heading here is the #1017 defect, invisible in `sections` ({stray})")
check(dc["substrate"] == "journey-similarity",
      f"the response names the substrate it actually rendered ({dc['substrate']})")
# Same question of both fields: whatever the listing shows, `sections` shows.
sec_titles = sec_titles_expected
check(all(t in listing for t in sec_titles),
      f"every section title in `sections` appears in the composed listing "
      f"({[t for t in sec_titles if t not in listing]} missing)")

# --- Story 20.82 (#1031) AC3: the verified constraints are ON THE SURFACE ---
# #889 verified four constraints; two of them are surface declarations, and
# until this story the composed screen 2 carried neither. Asserted here rather
# than trusted, because an axis now offered to the owner is read by the owner.
check("machine-composed" in listing,
      "composed `in common:` lines are marked machine-composed")
check("DISPLAY id" in listing and "no selection authority" in listing,
      "the `G` group-id kind is DECLARED on the screen that renders it")
check("Grouped by: journey-similarity" in listing
      and "none narrowed away" in listing,
      "the judged screen names its substrate and states that nothing was narrowed")
check("declared key" in listing and "never a strength ranking" in listing,
      "the section order is declared as a key, not a ranking")
check(f"All {len(dc['sections'])} group(s) are shown" in listing,
      "the disclosure counts the groups actually rendered")
# AC5, in its stronger single-valued form: this substrate places each Strand
# ONCE, checked AFTER composition on the composed output.
check(dc["placements"] == dc["count"] and dc["covered"] is True,
      f"exactly-once holds after composition ({dc['placements']} placements "
      f"for {dc['count']} Strands)")
# AC6 at the rendering layer: the co-tag screen is untouched by the above.
plain = member(path, "agents", ["--claims", json.dumps({})])["listing"]
check("model-judged substrate" not in plain,
      "the judged-substrate disclosure does not leak onto the co-tag screen")

# --- AC6/AC3: residues are NAMED and distinguished -------------------------
check(m.NO_SHARED_PATH_TITLE in titles
      and sorted(titles[m.NO_SHARED_PATH_TITLE]["strands"]) == ["a2", "a3", "a4", "a5"],
      f"arc-bearing Strands the composer left out land in an explicit 'no shared path' section ({sorted(titles)})")
check(m.NO_ARC_TITLE in titles
      and sorted(titles[m.NO_ARC_TITLE]["strands"]) == ["n0", "n1"],
      "a Strand with no SERVED arc gets its own named section — not-served is not no-shared-path")
# Story 20.82 (#1031) AC4: the two residues are TWO sections on the READING
# surface too, with distinct group ids and no merged heading. One Strand was
# never eligible for judgment, the other was judged and matched nothing; the
# #889 measurement kept them apart (G11 vs G12) and merging them would report
# a judgment that never happened.
check(titles[m.NO_ARC_TITLE]["group_id"] != titles[m.NO_SHARED_PATH_TITLE]["group_id"],
      "the two residues carry different group ids — never one merged section")
res_heads = [ln for ln in listing.splitlines()
             if ln.startswith("## ") and any(
                 f"— {t} (" in ln for t in (m.NO_ARC_TITLE,
                                            m.NO_SHARED_PATH_TITLE))]
check(len(res_heads) == 2,
      f"both residues render as their own named heading on the screen ({res_heads})")

# --- AC1: ranking, scoring and hiding are unreachable ----------------------
# A proposal carrying an order and a score must not change what reaches the
# owner: order is re-derived from a declared key and extra fields are ignored.
ranked = [{"in_common": "zzz last alphabetically", "members": ["a0"], "score": 0.99, "rank": 1},
          {"in_common": "aaa first alphabetically", "members": ["a1"], "score": 0.01, "rank": 2}]
d2 = member(path, "agents", ["--substrate", "journey-similarity",
                             "--grouping", json.dumps(ranked)])
order = [s["title"] for s in d2["sections"] if s["title"] in
         ("aaa first alphabetically", "zzz last alphabetically")]
check(order == ["aaa first alphabetically", "zzz last alphabetically"],
      f"a proposal's own ranking is IGNORED — order comes from a declared key ({order})")
placed2 = {s for sec in d2["sections"] for s in sec["strands"]}
check(len(placed2) == 8,
      "a low-scored group is never hidden — scoring cannot remove a Strand")

# --- an empty proposal is the honest empty state, never an invented grouping
d3 = member(path, "agents", ["--substrate", "journey-similarity"])
placed3 = {s for sec in d3["sections"] for s in sec["strands"]}
check(len(placed3) == 8 and d3["covered"] is True,
      "with no proposed grouping every Strand lands in a named residue, still covered")
check(all(s["title"] in (m.NO_SHARED_PATH_TITLE, m.NO_ARC_TITLE)
          for s in d3["sections"]),
      "nothing is invented when the composer proposes nothing")

# --- AC9: group ids are a DISPLAY kind -------------------------------------
check(all(s["group_id"].startswith("G") for s in d["sections"]),
      "every section carries a G display id")
check(len({s["group_id"] for s in d["sections"]}) == len(d["sections"]),
      "group ids are unique within the screen")
# Selection stays by element id: the G namespace must not appear as a
# selectable candidate index anywhere in the composed listing contract.
check("group_id" not in json.dumps(d.get("background", {})),
      "the group id confers no selection authority (it is not a selection key)")

# --- a judged substrate is not subdivided on another substrate's key -------
over = [s for s in d3["sections"] if s.get("note")]
check(all("another substrate's key" in (s.get("note") or "") for s in over),
      "an over-cap judged section DISCLOSES rather than borrowing the co-tag key")
check(not any(" + " in s["title"] for s in d3["sections"]),
      "no co-tag subdivision leaks into a judged substrate's titles")

sys.exit(1 if fail else 0)
JOURNEY_EOF
[ $? -eq 0 ] || fail=1


# --- Story 20.38 (#892): in-invocation view navigation over HELD state
# (SPEC-terrain CAP-3 as amended 2026-07-29). The screen summarises, the path
# holds the whole view, and the file is never read back.
python3 - <<'NAV_EOF'
import json, subprocess, tempfile, os, sys

D = "scripts/topic-map-directions.py"
# Story 20.64 (#962): the skill is a dispatcher + step companions; the
# assertion is over the family, whose order matches the pre-split file.
SK = ["skills/terrain/SKILL.md", "skills/terrain/steps/map.md",
      "skills/terrain/steps/screens.md", "skills/terrain/steps/brief.md",
      "skills/terrain/steps/gap.md"]
fail = 0


def check(cond, msg):
    global fail
    if cond:
        print(f"ok:   {msg}")
    else:
        print(f"FAIL: {msg}", file=sys.stderr)
        fail = 1


els = [{"kind": "lesson", "slug": f"v{n}", "title": f"V{n}", "gloss": f"g{n}",
        "tags": ["agents", "cost"], "journey": f"arc {n}",
        "evidence": [], "consumed": False} for n in range(8)]
d = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
     "elements": els}
f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(d, f); f.close()
out = tempfile.mktemp(suffix=".md")

# --- AC4: the screen summarises; the path holds the whole view -------------
r = subprocess.run(["python3", D, "view", "--map", f.name, "--tag", "agents",
                    "--out", out], capture_output=True, text=True)
check(r.returncode == 0 and os.path.exists(out),
      f"a member's whole view renders to the given path (rc={r.returncode})")
body = open(out).read()
check(all(f"`v{n}`" in body for n in range(8)),
      "the file carries EVERY Strand of the member — the whole view, not a summary")
mem = json.loads(subprocess.run(["python3", D, "member", "--map", f.name,
                                 "--tag", "agents"],
                                capture_output=True, text=True).stdout)
check(all(s["group_id"] in body for s in mem["sections"]),
      "the file and the screen address the same groups by the same ids")

# --- AC1/AC2: regenerated per invocation, byte-identical from held inputs ---
out2 = tempfile.mktemp(suffix=".md")
subprocess.run(["python3", D, "view", "--map", f.name, "--tag", "agents",
                "--out", out2], capture_output=True, text=True)
check(open(out).read() == open(out2).read(),
      "the same map renders the same view — nothing accumulates between renders")

# --- AC5/AC6: never read back; no cross-invocation cache -------------------
# Grep-shaped, exactly as CAP-3's existing never-read-back rule is enforced.
# Story 20.80 (#1029): the View's writer moved to scripts/terrain_screens.py
# when the hyphenated entry point was inverted into a CLI shim. The rule is a
# property of the SURFACE, so the entry point and that module are read as one
# text — the guard follows the code it guards.
# Story 20.81 (#1030): the write_view BODY is read from its owner alone. Over a
# concatenation the `split` would take whichever file happened to be first, so
# naming the owner is what keeps this assertion about the function it names; the
# absence assertion below keeps the whole surface, where more text is stronger.
src = "".join(open(p).read() for p in (D, "scripts/terrain_screens.py"))
owner = open("scripts/terrain_screens.py").read()
check("def write_view(" in owner, "write_view lives in terrain_screens.py")
after_write = owner.split("def write_view(", 1)[1]
check("open(" not in after_write.split("\ndef ", 1)[0].replace("open(path", "OK"),
      "write_view only writes — it never opens the view for reading")
check(not any(tok in src for tok in ("read_view(", "load_view(", "VIEW_CACHE")),
      "no reader and no cache exist for the view file (grep-assertable)")

# --- AC7: the standing exits are on the screen -----------------------------
sk = "".join(open(p).read() for p in SK)
for exit_name in ("switch substrate", "back to the member list",
                  "name your own direction", "stop here"):
    check(exit_name in sk, f"the standing exit '{exit_name}' is on the screen")

# --- AC3: back/switch re-present, and the reason is recorded ---------------
check("RE-PRESENT held state" in sk and "Never recompute" in sk,
      "back/switch re-present held state rather than recomputing")
check("different grouping" in sk and "unstable" in sk,
      "the REASON is recorded: recomputing a judged substrate can return a "
      "different grouping, destabilising the owner's own history")

# --- AC1: one corpus load, stated as the rule ------------------------------
check("One invocation = one corpus load" in sk,
      "the one-corpus-load rule is stated on the presenting surface")
check("lazily" in sk and "held for the rest of the invocation" in sk,
      "a judged substrate is computed lazily, then held")

# --- the forbidden shape is named, not merely omitted ----------------------
check("cross-invocation view cache is forbidden" in sk,
      "the forbidden cross-invocation cache is named explicitly")

for p in (out, out2):
    os.path.exists(p) and os.unlink(p)
sys.exit(1 if fail else 0)
NAV_EOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll terrain-member checks passed (every Strand is covered).\n'
