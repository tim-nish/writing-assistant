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

# THE COMPLETE RENDERING, wherever it now lives (Story 20.84, #1038). This
# fixture's member holds 41 Strands — deliberately, it is the measured worst
# case — which is over the screen budget, so the CONSOLE is a summary and the
# whole rendering is in the View file. Every assertion below that is ABOUT the
# complete rendering follows it to the surface that carries it; that following
# is the split the size switch exists to produce, not a weakening. Assertions
# about the console's own summary form live in the size-switch block at the end
# of this file.
whole_path = tempfile.mktemp(suffix=".md")
subprocess.run(["python3", D, "view", "--map", f.name, "--tag", "workflow",
                "--out", whole_path], capture_output=True, text=True)
whole = open(whole_path).read()
os.unlink(whole_path)
check(d["over_budget"] is True,
      "the 41-Strand fixture is over budget, so the console summarises")

# --- THE PERMUTATION -------------------------------------------------------
member_slugs = {e["slug"] for e in els if "workflow" in e["tags"]}
sectioned = [s for sec in d["sections"] for s in sec["strands"]]
check(len(sectioned) == len(member_slugs) == d["count"] == 41,
      f"count-in == count-out ({len(member_slugs)} in, {len(sectioned)} out)")
check(len(set(sectioned)) == len(sectioned), "no Strand appears twice")
check(set(sectioned) == member_slugs, "no Strand is dropped and none invented")
check("other" not in sectioned, "a Strand outside the member never leaks in")

# --- SERVED WHOLE ----------------------------------------------------------
ids = re.findall(r"^- \*\*((?:L|J)\d+|E\d+\.\d+)\*\* — ", whole, re.M)
check(len(ids) == 41, f"the rendering carries every Strand, whole ({len(ids)} lines)")
check("41 Strand(s), shown whole" in whole,
      "the count is disclosed on the complete rendering")

# --- NO SELECTION AUTHORITY ------------------------------------------------
check("already consumed, still selectable" in whole,
      "a consumed Strand is marked, never hidden")
heads = re.findall(r"^## (.+) \(\d+\)(?: — .+)?$", whole, re.M)
check(len(heads) == len(d["sections"]) >= 2,
      f"sections carry a title and a count — presentation only ({heads[:3]})")

# --- the sectioning contract: no direct parent over 20% (Story 20.23, #852) --
total = d["count"]
cap = max(3, int(total * 0.2))
over = [(s["title"], len(s["strands"])) for s in d["sections"]
        if len(s["strands"]) > cap]
undisclosed = [t for t, _n in over
               if f"{t} ({dict(over)[t]}) — over the one-fifth bound"
               not in whole]
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


def _head_line(listing, sec):
    """The section's heading line, addressed the way the composer writes it.

    Story 20.83 (#1039): the group id is now rendered on EVERY heading, not
    only in composed mode, because the View file always printed it and the two
    surfaces are one rendering. So the heading is addressed by `<gid> — <title>`
    where a gid exists, and by the bare title where one does not.
    """
    key = f"## {sec['group_id']} — {sec['title']} (" if sec.get("group_id") \
        else f"## {sec['title']} ("
    return listing.split(key)[1].split("\n")[0] if key in listing else ""


bad3 = [s["title"] for s in d3["sections"]
        if len(s["strands"]) > cap3
        and "over the one-fifth bound" not in _head_line(listing3, s)]
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
# Matched as WORDS, not substrings (Story 20.84, #1038). The over-budget screen
# names the standing exit `stop here`, whose "stop " contains "top " — a
# substring test reports a ranking claim where there is none, and a check that
# cries wolf is one nobody reads. The property asserted is unchanged.
for banned in (r"\branked\b", r"\btop\b", r"\bbest\b"):
    hits = [s for s in (whole, d["listing"])
            if re.search(banned, s, re.I)]
    check(not hits, f"no ranking language on either surface ({banned!r})")

# --- deterministic context fields (Story 20.21, #845) -----------------------
ctx = re.findall(r"^  \((?:also in: .+|in no other Topic).*$", whole, re.M)
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
cov = [ln for ln in whole.split("\n") if "carry journey material" in ln]
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
check(re.search(r"^- \*\*L\d+\*\* — ", whole, re.M),
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
# #1036: the renderer lives in terrain_directions.py — loaded from THAT path,
# never through the entry point's re-export, so deleting it where it lives
# has to fail here.
python3 - "scripts/terrain_directions.py" <<'PYEOF' || fail=1
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
# Story 20.84 (#1038): this fixture's member holds 8 Strands, one over the
# screen budget, so the CONSOLE is a summary and carries no `in common:` lines
# at all. The authoring declaration is owed by the surface that carries them —
# the View — and is asserted there. Declaring a class of line the screen does
# not contain is the same defect as a legend for absent rows (#978).
vt = tempfile.mktemp(suffix=".md")
subprocess.run(["python3", D, "view", "--map", path, "--tag", "agents",
                "--substrate", "journey-similarity",
                "--grouping", json.dumps(grouping),
                "--claims", json.dumps({"G1": "shared path X"}),
                "--out", vt], capture_output=True, text=True)
whole_dc = open(vt).read()
check("machine-composed" in whole_dc and "in common: shared path X" in whole_dc,
      "composed `in common:` lines are marked machine-composed")
check("machine-composed at render time" not in listing
      and "in common:" not in listing,
      "the summarised console declares no authoring class, because it carries "
      "no composed lines to declare one for")
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
import json, re, subprocess, tempfile, os, sys

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
check(all(f"g{n}" in body for n in range(8)),
      "the file carries EVERY Strand of the member — the whole view, not a summary")
mem = json.loads(subprocess.run(["python3", D, "member", "--map", f.name,
                                 "--tag", "agents"],
                                capture_output=True, text=True).stdout)
check(all(s["group_id"] in body for s in mem["sections"]),
      "the file and the screen address the same groups by the same ids")

# --- Story 20.83 (#1039): the View IS the complete rendering ---------------
# The defect: `compose_member_view` was a SECOND implementation of the member
# rendering and had drifted into the poorer of the two surfaces — no display
# index (so the file could not be selected from at all), no pin (so it could
# not be joined to the screen it mirrors), no `in common:` claim, no journey
# line. Each assertion below names the thing that was missing, so a future
# re-split is caught by what it drops rather than by a shape comparison.
ids = re.findall(r"^- \*\*(L\d+)\*\* — ", body, re.M)
check(len(ids) == 8,
      f"AC1: every row carries its `L` display index — selection is by index "
      f"and a View without indexes cannot be selected from ({len(ids)})")
# The screen this fixture's member produces is a SUMMARY (8 Strands, over the
# budget — Story 20.84, #1038), so the id-agreement half is asserted on a
# member small enough for the console to carry rows: it is the two SURFACES
# that must agree, and only an under-budget member has both in one place.
small = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
         "elements": els[:4]}
fs = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(small, fs); fs.close()
vs = tempfile.mktemp(suffix=".md")
subprocess.run(["python3", D, "view", "--map", fs.name, "--tag", "agents",
                "--out", vs], capture_output=True, text=True)
small_screen = json.loads(subprocess.run(
    ["python3", D, "member", "--map", fs.name, "--tag", "agents"],
    capture_output=True, text=True).stdout)
pat = r"^- \*\*(L\d+)\*\* — "
check(re.findall(pat, open(vs).read(), re.M)
      == re.findall(pat, small_screen["listing"], re.M)
      and len(re.findall(pat, open(vs).read(), re.M)) == 4,
      "AC1: the file's indexes are the SAME ids the composed screen assigns, "
      "in the same order")
os.unlink(vs)
check("Pin: " in body, "AC2: the View states the pin, so it joins to its screen")
check(all(f"how it changed: arc {n}" in body for n in range(8)),
      "AC4: the journey material reaches the file, per row")

vc = tempfile.mktemp(suffix=".md")
gids = [s["group_id"] for s in mem["sections"]]
rc = subprocess.run(["python3", D, "view", "--map", f.name, "--tag", "agents",
                     "--out", vc, "--claims",
                     json.dumps({gids[0]: "they share a background"})],
                    capture_output=True, text=True)
cbody = open(vc).read() if rc.returncode == 0 else ""
check(rc.returncode == 0 and "in common: they share a background" in cbody,
      f"AC6/AC3: `view --claims` reaches the composer and the claim is carried "
      f"VERBATIM (rc={rc.returncode})")
check(len(gids) < 2 or "not composed for this group" in cbody,
      "AC3: a section whose claim was not passed STATES the absence rather "
      "than having one invented")
check(cbody.count("machine-composed at render time from the served claims") == 1,
      "AC7: the authoring class is declared ONCE for the surface, never per line")
# AC5 — one rendering, not two. Asserted structurally: the View path must not
# own a rendering of its own, or the drift this story fixed can simply recur.
mem_src = open("scripts/terrain_members.py").read()
vsrc = mem_src.split("def compose_member_view(", 1)[1].split("\ndef ", 1)[0]
check("_compose_member_rendering(" in vsrc and "lines.append(" not in vsrc,
      "AC5: compose_member_view DELEGATES — it composes no lines of its own, "
      "so one code path renders both surfaces")
check(mem_src.count("def _compose_member_rendering(") == 1,
      "AC5: there is exactly ONE complete member rendering in the module")
os.path.exists(vc) and os.unlink(vc)

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

# --- Story 20.84 (#1038): THE SIZE SWITCH FIRES ON THE MEMBER PATH ----------
# The budget was re-based per axis member on 2026-07-27 (#803) and never
# reached the code: the only predicate counted `map_data["elements"]` — the
# whole terrain — and `compose_member_listing` had no over-budget branch at
# all, so a member of 51 Strands rendered 51 rows because the terrain around it
# was small. Each assertion below is keyed to the criterion it discharges.
python3 - <<'SIZE_EOF'
import json, subprocess, sys, tempfile

D = "scripts/topic-map-directions.py"
fail = 0


def check(cond, msg):
    global fail
    if cond:
        print(f"ok:   {msg}")
    else:
        print(f"FAIL: {msg}", file=sys.stderr)
        fail = 1


def mk(n, extra_els=()):
    els = [{"kind": "lesson", "slug": f"w{i}", "title": f"W{i}",
            "gloss": f"claim {i}",
            "tags": ["workflow", "agents" if i % 2 else "cost"],
            "evidence": [], "consumed": False,
            "journey_recorded": True, "journey": f"arc {i}"}
           for i in range(n)]
    els += list(extra_els)
    m = {"kind": "topic-map", "topics": [],
         "coverage": {"pin": "h@abc1234"}, "elements": els}
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(m, f); f.close()
    return f.name


def member(path, *extra):
    return subprocess.run(
        ["python3", D, "member", "--map", path, "--tag", "workflow"]
        + list(extra), capture_output=True, text=True)


budget = json.loads(member(mk(3)).stdout)["screen_budget"]
check(budget == 7, f"the budget is read from its one declaration ({budget})")

# --- AC1: the predicate counts THIS MEMBER'S Strands ------------------------
# A big member in a small terrain, and a small member in a big terrain. The old
# predicate would answer identically for both; the re-based one must not.
big_member = mk(budget + 5)
d_big = json.loads(member(big_member).stdout)
check(d_big["over_budget"] is True,
      f"AC1: a member above the budget is over budget ({d_big['count']} "
      f"Strands vs a budget of {budget})")
noise = [{"kind": "lesson", "slug": f"n{i}", "title": f"N{i}", "gloss": "x",
          "tags": ["elsewhere"], "evidence": [], "consumed": False}
         for i in range(60)]
small_in_big = mk(3, noise)
d_small = json.loads(member(small_in_big).stdout)
check(d_small["over_budget"] is False,
      "AC1: a SMALL member inside a LARGE terrain is NOT over budget — the "
      "budget is measured per axis member, never over map_data['elements']")
check(len(json.load(open(small_in_big))["elements"]) > budget,
      "AC1: ...and that terrain really is over the old whole-terrain predicate")

# --- AC2: at or under the budget, nothing changes ---------------------------
under = json.loads(member(small_in_big, "--claims", '{"G1":"c"}').stdout)
check("shown whole" in under["listing"]
      and "- **L1**" in under["listing"],
      "AC2: the at-or-under branch is the shipped whole listing, rows and all")
check("summarised" not in under["listing"],
      "AC2: no summary wording leaks onto the small branch")

# --- AC3: above the budget — summaries plus the path, and no rows -----------
VP = "/nonexistent-destination/terrain/terrain-view.md"
d3 = json.loads(member(big_member, "--view", VP,
                       "--claims", '{"G1":"a claim that must not ride along"}').stdout)
L = d3["listing"]
check("- **L" not in L,
      "AC3: the over-budget console carries NO per-Strand rows")
check("how it changed:" not in L,
      "AC3: ...and no journey lines")
check("in common: a claim that must not ride along" not in L,
      "AC4 (decided): the `in common:` claims do NOT ride along with the "
      "summaries — they are unclipped composer prose, which is unbounded "
      "screen height, and they are in the View one open away")
heads = [l for l in L.splitlines() if l.startswith("## ")]
check(len(heads) == len(d3["sections"]) >= 2,
      f"AC3: one compact summary line per group, all of them ({len(heads)})")
check(all(s["group_id"] in L and s["title"] in L
          and f"({len(s['strands'])})" in L for s in d3["sections"]),
      "AC3: each summary carries the group id, its derived title and its count")
check("terrain-view.md" in L,
      "AC3: the View path is on the screen")
check("no-journey" not in L and "carry journey material" not in L,
      "AC3: the row-type legend and the journey coverage denominator stay "
      "with the rows they qualify (#978, #933/#934) — a legend for rows the "
      "screen does not contain primes the reader for rows that never appear")

# --- AC5: the above-budget branch proposes NO LESS --------------------------
for exit_name in ("switch substrate", "back to the member list",
                  "name your own direction", "stop here"):
    check(exit_name in L,
          f"AC5: the standing exit '{exit_name}' is on the over-budget screen")
check("Selection is by Strand index" in L,
      "AC5: selection stays BY INDEX on the over-budget screen")
check("capped, truncated or ordered by any measure of strength" in L,
      "AC5: the screen states that nothing was narrowed away")

# --- AC7: the switch never fails open ---------------------------------------
r7 = member(big_member)
d7 = json.loads(r7.stdout)
check("- **L" not in d7["listing"],
      "AC7: over budget with NO view path, the screen still summarises — the "
      "switch does not fail open into the whole-screen dump")
check("NO VIEW PATH WAS GIVEN" in d7["listing"],
      "AC7: ...and it states that the complete rendering was written nowhere")
check("--view" in r7.stderr and str(budget) in r7.stderr,
      f"AC7: the caller is warned, naming the fix ({r7.stderr.strip()[:60]!r})")

# --- AC6: the screen is composed and relayed ONCE per selection -------------
# The two-call flow's first call is an INPUTS call. Nothing in the response
# said so, and the identical screen was relayed twice back-to-back.
d_in = json.loads(member(big_member, "--view", VP).stdout)
check(d_in["relay"].startswith("inputs-only"),
      "AC6: the first (no-claims) call declares itself inputs-only")
check("do NOT relay" in d_in["relay"],
      "AC6: ...and says so in the imperative the relaying skill needs")
check(d3["relay"] == "whole",
      "AC6: the second (claims) call is the one screen, marked whole")
sk = open("skills/terrain/steps/screens.md").read()
check("exactly ONCE per selection" in sk,
      "AC6: the relay-once rule is on the presenting surface too")

sys.exit(1 if fail else 0)
SIZE_EOF
[ $? -eq 0 ] || fail=1

# --- The semantic SUBGROUP layer (Story 20.86, #1041) ------------------------
# The layer is model-triggered, so what a check can hold is exactly the
# mechanical half: the partition, the ids, the leaf cover, and the ABSENCE of a
# member-count trigger. Those are the criteria a well-meaning diff breaks.
python3 - <<'SUBGROUP_EOF'
import json, re, subprocess, sys, tempfile

D = "scripts/topic-map-directions.py"
fail = 0


def check(cond, msg):
    global fail
    if cond:
        print(f"ok:   {msg}")
    else:
        print(f"FAIL: {msg}", file=sys.stderr)
        fail = 1


# IN-PROCESS, deliberately: the layer is a pure function of the sections and a
# proposal, so exercising it through six CLI round trips buys nothing but
# interpreter starts — and this check is inner-tier, where the runtime ceiling
# is the constraint. ONE subprocess below covers the CLI wiring.
sys.path.insert(0, "scripts")
from terrain_members import member_sections, apply_subgroups  # noqa: E402

els = [{"kind": "lesson", "slug": f"s{i}", "title": f"S{i}", "gloss": f"g{i}",
        "tags": ["workflow", "agents"], "evidence": [], "consumed": False,
        "journey_recorded": True, "journey": f"arc {i}"} for i in range(6)]
m = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
     "elements": els}


def sections():
    return member_sections(m, "workflow")


base = apply_subgroups(sections(), None)
gid = base["sections"][0]["group_id"]
slugs = [e["slug"] for e in base["sections"][0]["strands"]]
check(len(base["sections"]) == 1 and len(slugs) == 6,
      f"fixture: one group of six ({gid})")

# AC8 — an UNSUBDIVIDED screen is unchanged, and the leaf cover agrees with the
# parent cover rather than being a special case.
check(base["subdivided"] == [] and base["leaf_covered"] is True
      and base["leaf_placements"] == base["placements"],
      "AC5/AC8: with no subdivision the leaf cover equals the parent cover and "
      "nothing is marked subdivided")

d = apply_subgroups(sections(), {gid: [
    {"claim": "the first stratum", "strands": slugs[:3]},
    {"claim": "the second stratum", "strands": slugs[3:]}]})
sub = d["sections"][0]["subgroups"]

# AC4 — the ids are G<n>-<m>, and they are a DISPLAY kind.
check([s["subgroup_id"] for s in sub] == [f"{gid}-1", f"{gid}-2"],
      f"AC4: subgroup ids follow G<n>-<m> ({[s['subgroup_id'] for s in sub]})")

# AC5/AC6 — the cover is counted at the LEAVES, in placements, AFTER
# composition. Equality with count is what "no silent drop" means here.
check(d["leaf_covered"] is True and d["leaf_placements"] == d["placements"],
      "AC5/AC6: the leaf cover is asserted over the composed hierarchy and "
      "still holds every Strand, in placements")

# AC7 — presentation only: parent membership does not move because a
# subdivision was adopted.
check([e["slug"] for e in d["sections"][0]["strands"]] == slugs,
      "AC7: parent membership and order are untouched by the subdivision")

# AC7 again, on the refusal side: a proposal that would move a Strand across
# parents, drop one, or duplicate one is REFUSED rather than repaired.
def refuses(proposal, needle, msg):
    try:
        apply_subgroups(sections(), proposal)
    except ValueError as exc:
        check(needle in str(exc), f"{msg} ({str(exc)[:60]!r})")
    else:
        check(False, f"{msg} — but it was ACCEPTED")


refuses({gid: [{"claim": "a", "strands": slugs[:3]},
                {"claim": "b", "strands": slugs[3:5]}]}, "drops",
        "AC5: a subdivision that drops a Strand is refused, naming what it lost")
refuses({gid: [{"claim": "a", "strands": slugs[:4]},
                {"claim": "b", "strands": slugs[3:]}]}, "exactly one part",
        "AC7: a Strand in two parts of one parent is refused")
refuses({gid: [{"claim": "a", "strands": slugs[:3] + ["not-in-this-group"]},
                {"claim": "b", "strands": slugs[3:]}]},
        "never moves a Strand between parent groups",
        "AC7: a Strand from another parent group is refused")
refuses({"G99": [{"claim": "a", "strands": slugs[:3]},
                  {"claim": "b", "strands": slugs[3:]}]}, "PER-SCREEN",
        "AC4: an id that is not on this screen is refused — ids are "
        "per-screen and per-pin")
refuses({gid: [{"claim": "a", "strands": slugs}]}, "at least two parts",
        "AC4: a one-part 'subdivision' is refused as the leaf case it is")

# AC3 — the recursive stop is semantic, and the structure supports any depth.
dn = apply_subgroups(sections(), {gid: [
    {"claim": "the first stratum", "strands": slugs[:3]},
    {"claim": "the second stratum", "strands": slugs[3:],
     "subgroups": [{"claim": "deeper a", "strands": slugs[3:5]},
                   {"claim": "deeper b", "strands": slugs[5:]}]}]})
deep = [x["subgroup_id"]
        for x in dn["sections"][0]["subgroups"][1]["subgroups"]]
check(deep == [f"{gid}-2-1", f"{gid}-2-2"],
      f"AC3: a subgroup subdivides again, ids composing downward ({deep})")
check(dn["leaf_covered"] is True,
      "AC5/AC6: the leaf cover is counted at the DEEPEST parts, not the "
      "intermediate ones")

# THE COMMAND WIRING, once. `cmd_member` is called directly rather than through
# a tenth interpreter start: the family SUM is budgeted (#944), and what is
# being asserted is that `--subgroups` reaches the layer and the payload
# carries the ids — argparse's own declaration is asserted by
# check-check-declarations.sh, not here.
import io  # noqa: E402
from contextlib import redirect_stdout  # noqa: E402
from terrain_members import cmd_member  # noqa: E402


class _Args:
    pass


f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(m, f); f.close()
a = _Args()
a.map, a.tag, a.axis = f.name, "workflow", "tag"
a.claims = '{"G1":"the parent claim"}'
a.subgroups = json.dumps({gid: [{"claim": "a", "strands": slugs[:3]},
                                {"claim": "b", "strands": slugs[3:]}]})
a.grouping = a.view = None
a.substrate = "co-tags"
buf = io.StringIO()
with redirect_stdout(buf):
    rc = cmd_member(a)
dc = json.loads(buf.getvalue())
check(rc == 0, "the member command runs with --subgroups")
check(dc["subdivided"] == [gid]
      and dc["sections"][0]["subgroups"][0]["subgroup_id"] == f"{gid}-1",
      "AC4: --subgroups reaches the layer through the CLI and the payload "
      "carries the ids and claims as data")
from terrain_members import candidates, compose_member_listing  # noqa: E402
check(dc["listing"] != compose_member_listing(
          m, "workflow", candidates(m), "tag", {"G1": "the parent claim"})
      and f"{gid}-1" in dc["listing"],
      "AC4: an adopted subdivision reaches the composed listing carrying its "
      "ids (the rendering itself is asserted in "
      "check-terrain-group-disclosure.sh, story 20.87)")

# AC2/AC9 — THE DECLINED CAP STAYS DECLINED. No member-count constant may
# appear in the layer, and the surface must state the trigger it does use.
src = open("scripts/terrain_members.py").read()
layer = src.split("The SEMANTIC SUBGROUP LAYER", 1)[1].split(
    "def _strand_context_line", 1)[0]
check(not re.search(r"len\((?:sec|group|strands|parent_strands)[^)]*\)\s*[<>]=?\s*\d",
                    layer),
      "AC9: the subgroup layer compares no member count against a constant — "
      "the trigger is the tightness differential, never a cap (#980's decline "
      "is untouched)")
check("tightness differential" in layer.lower(),
      "AC2: the layer names the tightness differential as what decides")
sk = open("skills/terrain/steps/screens.md").read()
check("tightness differential" in sk.lower()
      and "measurably tighter" in sk,
      "AC2: the composing surface states the trigger the composer applies")
check("no member count" in sk.lower() or "No member count" in sk,
      "AC9: ...and states that no member count participates")

# AC8 — the deterministic co-tag subdivision is untouched and the two compose.
check("_subdivide_section" in src and "WHICH RUNS WHEN" in src,
      "AC8: `_subdivide_section` still ships and the layer states which "
      "mechanism runs when")

sys.exit(1 if fail else 0)
SUBGROUP_EOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll terrain-member checks passed (every Strand is covered).\n'
