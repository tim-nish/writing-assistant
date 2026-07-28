#!/usr/bin/env sh
# check-terrain-member.sh — Screen 2's sectioning is a PERMUTATION, and its
# sections carry NO SELECTION AUTHORITY (Story 20.9, #811; SPEC-terrain as
# resolved 2026-07-27).
#
# The permutation invariant is the whole point: every Strand of the selected
# member appears in EXACTLY ONE section — count-in == count-out — so the
# information loss the abandoned cluster unit suffered cannot compile, and the
# worst case is a badly grouped but complete list. This check FAILS LOUDLY on
# a dropped or duplicated Strand; a count mismatch is never a warning.
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
import json, re, subprocess, sys, tempfile
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
check(len(sectioned3) == 30 and len(set(sectioned3)) == 30,
      "subdivision preserves the permutation (count in == count out)")
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
for phrase in ("never omits, merges, ranks, or gates",
               "machine-composed", "never silent"):
    check(phrase in rules, f"the binding rules state: {phrase!r}")

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

# --- NEGATIVE TEST: a broken permutation must fail RED ---------------------
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
grep -q "What each row IS" "$D" \
  && ok "the row-kind legend is composed for the reading surfaces" \
  || err "the row-kind legend is missing"

# --- the Journey shortfall is DISCLOSED, detection-based (Story 20.10, #812) --
python3 - "$D" <<'PYEOF' || fail=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dv", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
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
line = m._journey_disclosure_line(gap)
check(line is not None and "requested" in line.lower(),
      "nothing requested yields the shortfall as a LINE, named as not-requested")
check("served at this pin" not in line,
      "a not-requested corpus is NEVER reported as a not-served one")
check("\n" not in line and "##" not in line,
      "the disclosure is a line, never a section")
check("requested" in m.compose_axis_payload(gap)["items"][0]["where"].lower(),
      "the shortfall is named on the axis screen")
check("requested" in
      m.compose_member_listing(gap, "workflow", m.candidates(gap)).lower(),
      "the shortfall is named on the member listing")
# REQUESTED AND MISSING: a different fact, and an abnormal condition to fix.
missing = dict(base, gloss={"served": True, "lesson_renderings": 3,
                            "journey_renderings": 0,
                            "journeys_requested": ["journeys/workflow"],
                            "journey_misses": {"journeys/workflow": "served a miss"}})
mline = m._journey_disclosure_line(missing)
check(mline is not None and "journeys/workflow" in mline
      and "abnormal condition" in mline,
      "a requested shard that did not arrive is named as the abnormal condition")
check(mline != line,
      "requested-and-missing is a DIFFERENT line from not-requested")
ok_served = dict(base, gloss={"served": True, "lesson_renderings": 3,
                              "journey_renderings": 2,
                              "journeys_requested": ["journeys/workflow"]})
check(m._journey_disclosure_line(ok_served) is None,
      "served journeys retire the disclosure BY DETECTION, no flag to flip")
down = dict(base, gloss={"served": False, "reason": "gateway down"})
check(m._journey_disclosure_line(down) is None,
      "a whole-gloss outage is the gloss line's to name — no double disclosure")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll terrain-member checks passed (sectioning is a permutation).\n'
