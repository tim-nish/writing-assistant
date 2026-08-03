#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-07-31 (#999) — one `mktemp -d` holds the fixture map,
# every answer, every composed-candidate file and every output; the repository
# is only read. No shared path, no ambient state, no network.
# covers: scripts/topic-map-directions.py scripts/terrain_theses.py
#   scripts/terrain_journey.py scripts/terrain_text.py scripts/strand_cover.py
#   skills/terrain/steps/brief.md skills/terrain/steps/brief-gates.md
# tier: inner — CANDIDATE THESES and the k-GROUP PROPOSAL (Story 20.78,
#   #995/#988) against a derived fixture map; no seam, no corpus, no assembly.
#   Its own check rather than more assertions in
#   check-terrain-select-brief-inner.sh or the iteration check, for the #948
#   reason those two exist: the cover needs a case per refusal, and exactly
#   that growth pushed an earlier check to ~90% of INNER_MS. It tripped the
#   ceiling here too, at 2201ms with one CLI run per case; the remedy was #950
#   batching (two CLI runs at the command's boundary, the rest through the same
#   entry point in one interpreter), never a re-tier. Measured 2026-07-31 after
#   that: ~1.2s (ceiling 2s).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-theses-inner.sh — the gate proposes 2–3 candidate theses over
# the COMPLETE selected set, a large selection may be proposed as k
# article-scoped groups, and THE PLACEMENT COUNT RUNS AFTER COMPOSITION. That
# count is the story's own falsifier: a composer that cannot omit in principle
# can still omit in fact, so the assertions below drive the shipped command
# over compositions that DO omit, and require the omission to be caught.
#
# It also covers the JOURNEY-INCORPORATION option composer (Story 20.166,
# #1045) — the same mechanism one selection later, asserted in the same file
# rather than a sibling check, because the falsifiers are the same class: a
# composition that omits, invents a cite, or narrows, caught by the same
# after-composition cover.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/topic-map-directions.py"
T="scripts/terrain_theses.py"
FIX="scripts/fixtures/terrain/screen-map.json"
# The brief's contract spans the step file and its post-adoption companion
# since the 20.212 split (the four-gate sequence crossed the 600-line ceiling).
# Asserted over the CONCATENATION, exactly as check-review-reentry.sh does for
# the review phases: a token moving between the two is a relocation, never a
# deletion, and this check must not read one as the other.
SKILL=$(mktemp)
cat skills/terrain/steps/brief.md skills/terrain/steps/brief-gates.md > "$SKILL"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 -c "import py_compile; py_compile.compile('$T', doraise=True)" 2>/dev/null \
  && ok "terrain_theses.py compiles" || err "terrain_theses.py syntax error"

# One prep run widens the fixture past the partition threshold and writes both
# answers (#950 batching: one interpreter for the map and every fixture).
python3 - "$FIX" "$work" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); w = sys.argv[2]
strands = list(d.get("elements") or [])
for n in range(8):
    strands.append({
        "kind": "lesson", "slug": f"widened-{n:02d}", "title": f"Lesson {n}",
        "topic": "engineering" if n % 2 else "people",
        "date": f"2026-07-{n + 1:02d}",
        "gloss": f"A claim the material itself makes, number {n}",
        "situation": f"LESSONS.md:{n + 10}@abc1234",
        "evidence": [f"LESSONS.md:{n + 10}@abc1234"], "consumed": False,
        # A served arc on every widened Strand (Story 20.166): the small
        # selection then mixes arc-carrying and arc-less members, which is
        # the state the incorporation cover must count honestly.
        "journey": f"we assumed one thing, it broke, we hold another ({n})",
        "journey_cite": f"journeys/w.md:{n + 10}@abc1234"})
d["elements"] = strands
json.dump(d, open(w + "/map.json", "w"))
PYEOF

python3 "$D" candidates --map "$work/map.json" > "$work/cands.json"
python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
pin = json.load(open(w + "/map.json"))["coverage"]["pin"]
ids = [c["id"] for c in json.load(open(w + "/cands.json"))["candidates"]
       if c["kind"] == "element"]
put = lambda n, o: json.dump(o, open(f"{w}/{n}.json", "w"))
put("a-small", {"index": ids[:3], "note": "through the on-call retro",
                "pin": pin})
put("a-large", {"index": ids[:7], "note": "n", "pin": pin})
put("a-one", {"index": ids[0], "note": "n", "pin": pin})
put("a-free", {"free_text": "my own thesis, in my own words"})
PYEOF

python3 "$D" brief --answer "$work/a-small.json" --map "$work/map.json" \
  --out "$work/ws/brief.json" > "$work/b-small.json"
python3 "$D" brief --answer "$work/a-large.json" --map "$work/map.json" \
  --out "$work/ws/brief-large.json" > "$work/b-large.json"
python3 "$D" brief --answer "$work/a-one.json" --map "$work/map.json" \
  > "$work/b-one.json"
python3 "$D" brief --answer "$work/a-free.json" --map "$work/map.json" \
  > "$work/b-free.json"

# The COMPOSED candidate files. Written here, not by the code under test: the
# count reads what a composer EMITTED, so the fixtures are the emissions —
# including the ones that omit a Strand, which is the point.
python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
b = json.load(open(w + "/b-small.json"))
bl = json.load(open(w + "/b-large.json"))
ids, big = b["indexes"], bl["indexes"]
cite = {m["index"]: m["cite"] for m in b["members"]}
g = lambda xs: [{"index": i, "cite": cite[i]} for i in xs]
put = lambda n, o: json.dump(o, open(f"{w}/{n}.json", "w"))
base = {"kind": "candidate-theses", "over": ids, "pin": b["pin"], "candidates": [
    {"thesis": "one reading", "places": ids, "grounds": g(ids)},
    {"thesis": "another reading", "places": ids[:2],
     "omits": [{"index": ids[2], "why": "a different register"}],
     "grounds": g(ids[:2])}]}
put("c-good", base)
# THE FALSIFIER: the same shape with the disclosure removed. Placements are
# identical; only the honesty differs.
silent = json.loads(json.dumps(base)); silent["candidates"][1].pop("omits")
put("c-silent", silent)
one = json.loads(json.dumps(base)); one["candidates"] = one["candidates"][:1]
put("c-one", one)
four = json.loads(json.dumps(base))
four["candidates"] = four["candidates"] + four["candidates"]
put("c-four", four)
inv = json.loads(json.dumps(base))
inv["candidates"][0]["grounds"][0]["cite"] = "INVENTED.md:1@deadbeef"
put("c-invented", inv)
nar = json.loads(json.dumps(base))
nar["over"] = ids[:2]; nar["candidates"][0]["places"] = ids[:2]
nar["candidates"][0]["grounds"] = g(ids[:2])
nar["candidates"][1]["omits"] = []
put("c-narrowed", nar)
out = json.loads(json.dumps(base))
out["candidates"][0]["places"] = ids + ["L99"]
put("c-outside", out)
# The partition fixtures.
part = {"kind": "partition", "over": big, "pin": bl["pin"], "groups": [
    {"label": "the on-call thread", "members": big[:3], "thesis": "t1"},
    {"label": "the budget thread", "members": big[3:], "thesis": "t2"}]}
put("p-good", part)
filt = json.loads(json.dumps(part)); filt["groups"][1]["members"] = big[3:-1]
put("p-filtered", filt)
drop = json.loads(json.dumps(filt))
drop["dropped"] = [{"index": big[-1], "why": "not this article", "by": "owner"}]
put("p-dropped", drop)
mach = json.loads(json.dumps(filt))
mach["dropped"] = [{"index": big[-1], "why": "weakest of the set"}]
put("p-machine-drop", mach)
solo = json.loads(json.dumps(part))
solo["groups"] = [{"label": "all of it", "members": big}]
put("p-one-group", solo)
# The INCORPORATION fixtures (Story 20.166, #1045). The small selection holds
# one arc-carrying member (the widened Strand) beside two arc-less ones, so
# the cover must count over the served material only while the block
# discloses the rest.
mem = {m["index"]: m for m in b["members"]}
served = [i for i in ids if (mem[i].get("journey") or {}).get("served")]
arc = {i: mem[i]["journey"]["arc_cite"] for i in served}
gj = lambda xs: [{"index": i, "cite": arc[i]} for i in xs]
inc = {"kind": "journey-incorporation", "over": ids, "pin": b["pin"],
       "options": [
    {"incorporation": "the arc opens its lesson's section as a worked scene",
     "places": served, "grounds": gj(served)},
    {"incorporation": "one short story carries the arc, with the thesis as "
                      "its conclusion",
     "places": [], "grounds": [],
     "omits": [{"index": served[0],
                "why": "the arc restates the thesis at this length"}]}]}
put("i-good", inc)
# THE SAME FALSIFIER CLASS: the disclosure removed, the choice removed, the
# cite invented, and a placement of material the pin does not serve.
isilent = json.loads(json.dumps(inc)); isilent["options"][1].pop("omits")
put("i-silent", isilent)
ione = json.loads(json.dumps(inc)); ione["options"] = ione["options"][:1]
put("i-one", ione)
iinv = json.loads(json.dumps(inc))
iinv["options"][0]["grounds"][0]["cite"] = "INVENTED.md:1@deadbeef"
put("i-invented", iinv)
iuns = json.loads(json.dumps(inc))
iuns["options"][0]["places"] = served + [ids[0]]
put("i-unserved", iuns)
# The adoption answers: a thesis adopted alone, and a thesis plus register.
put("a-adopt", {"index": ids, "note": "n", "pin": b["pin"],
                "claim": "one reading"})
put("a-adopt-reg", {"index": ids, "note": "n", "pin": b["pin"],
                    "claim": "one reading",
                    "journey_incorporation": inc["options"][1]
                    ["incorporation"]})
PYEOF

# --- the incorporation gate is raised by ADOPTION, and travels the same
# cover (Story 20.166) --------------------------------------------------------
python3 "$D" brief --answer "$work/a-adopt.json" --map "$work/map.json" \
  --composed "$work/c-good.json" --out "$work/ws/brief-adopted.json" \
  > "$work/b-adopted.json" 2>"$work/e-adopt" \
  && ok "an adopted brief composes with the incorporation block offered" \
  || err "adoption failed: $(cat "$work/e-adopt")"
# Adoption of a register may not outrun the record of what it was adopted
# from — the #1079 rule, applied to the incorporation.
if python3 "$D" brief --answer "$work/a-adopt-reg.json" \
     --map "$work/map.json" --composed "$work/c-good.json" \
     >/dev/null 2>"$work/e-reg-refuse"; then
  err "a register was adopted with NO composed options recorded"
else
  grep -q 'adopted from' "$work/e-reg-refuse" \
    && ok "adopting a register without the composed options is refused" \
    || err "wrong register-adoption refusal: $(cat "$work/e-reg-refuse")"
fi
python3 "$D" brief --answer "$work/a-adopt-reg.json" --map "$work/map.json" \
  --composed "$work/c-good.json" --incorporation "$work/i-good.json" \
  --out "$work/ws/brief-final.json" > "$work/b-final.json" \
    2>"$work/e-final" \
  && ok "adopting a register WITH the composed options succeeds" \
  || err "register adoption failed: $(cat "$work/e-final")"
python3 "$D" cover --composed "$work/i-good.json" \
  --from "$work/ws/brief-adopted.json" > "$work/r-inc.json" \
    2>"$work/e-inc-good" \
  && ok "a conforming incorporation set passes the cover" \
  || err "a conforming incorporation set was refused: $(cat "$work/e-inc-good")"
if python3 "$D" cover --composed "$work/i-silent.json" \
     --from "$work/ws/brief-adopted.json" >/dev/null 2>"$work/e-inc-silent"; then
  err "the cover accepted an option that silently dropped a member's arc"
else
  grep -q 'says nothing about' "$work/e-inc-silent" \
    && ok "a silent arc omission is refused, with the member named" \
    || err "wrong incorporation-omission behaviour: $(cat "$work/e-inc-silent")"
fi

# --- the COMMAND, at its two ends: a conforming set, and the falsifier ------
# Two CLI runs, not thirteen. The shipped entry point is exercised here — exit
# code, stderr, the artifact it reads — and every remaining case is driven
# through the same `verify_cover` in ONE interpreter below (#950 batching;
# thirteen interpreter starts put this check over INNER_MS by itself).
python3 "$D" cover --composed "$work/c-good.json" \
  --from "$work/ws/brief.json" > "$work/r-good.json" 2>"$work/e-good" \
  && ok "a conforming candidate set passes the cover" \
  || err "a conforming candidate set was refused: $(cat "$work/e-good")"
# AC2/AC3 — THE STORY'S OWN FALSIFIER, at the command's own boundary: the same
# placements as the conforming set, with the disclosure removed.
if python3 "$D" cover --composed "$work/c-silent.json" \
     --from "$work/ws/brief.json" >/dev/null 2>"$work/e-silent"; then
  err "the cover accepted a candidate that silently dropped a selected Strand"
else
  grep -q 'says nothing about' "$work/e-silent" \
    && ok "a silent omission is refused by the command, with the Strand named" \
    || err "wrong silent-omission behaviour: $(cat "$work/e-silent")"
fi

# --- the skill carries the requirements as contract text --------------------
# Asserted as TEXT for the reason the consultant check states: the requirements
# bind the composer, who reads the skill.
for token in 'CANDIDATE THESES' 'never a narrowing of it' \
             'cover counted in placements' 'runs AFTER composition' \
             'Nothing already computes them' 'Free text wins' \
             'must not filter' 'only explicitly' \
             'never k' 'not a fixed procedure' \
             'A fixed menu of registers is exactly what must not ship' \
             'never collapses to rule-statement register' \
             'never a required slot' \
             'draft_gates.gate("journey-incorporation"'; do
  grep -qF -- "$token" "$SKILL" && ok "the skill carries: $token" \
    || err "the skill is missing the contract text: $token"
done

# --- AC9 — the consultant kept its rules and gained no procedure ------------
grep -q 'CONSULTANT_RULES = \[' "$D" \
  && ok "the consultant's four rules are untouched" \
  || err "CONSULTANT_RULES no longer exists as the consultant's binding"
if grep -nE 'CONSULTANT_(STRUCTURES|PROCEDURE|STEPS)|assessment_steps' \
     "$D" "$T" >/dev/null; then
  err "a fixed assessment procedure was added to build candidates (#939)"
else
  ok "candidates were built without smuggling a procedure into the consultant"
fi
# --- one assertion run over the produced payloads (#950 batching) -----------
python3 - "$work" <<'PYEOF' || fail=1
import importlib, json, os, sys
w = sys.argv[1]
sys.path.insert(0, os.path.abspath("scripts"))
verify_cover = importlib.import_module("terrain_theses").verify_cover
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

def cover(name, brief):
    """The SAME entry point the command calls, over the SAME emitted files."""
    return verify_cover(json.load(open(f"{w}/{name}.json")),
                        json.load(open(f"{w}/ws/{brief}")), f"{w}/ws/{brief}")

def refuses(name, brief, phrase):
    r = cover(name, brief)
    got = " ".join(r.get("refusals") or [])
    check(bool(r.get("refusals")) and phrase in got,
          f"{name}: refused, with the reason named ({phrase!r})")

# AC1/AC2/AC4 — everything a candidate set is refused for.
refuses("c-one", "brief.json", "the gate proposes")
refuses("c-four", "brief.json", "the gate proposes")
refuses("c-invented", "brief.json", "invented material")
refuses("c-narrowed", "brief.json", "OWNER'S selection")
refuses("c-outside", "brief.json", "not in the owner's")
# AC6 — and everything a partition is refused for.
refuses("p-filtered", "brief-large.json", "MUST NOT FILTER")
refuses("p-machine-drop", "brief-large.json", "explicit act")
refuses("p-one-group", "brief-large.json", "proposes nothing")

s = json.load(open(w + "/b-small.json"))
l = json.load(open(w + "/b-large.json"))
one = json.load(open(w + "/b-one.json"))
free = json.load(open(w + "/b-free.json"))
ct = s.get("candidate_theses") or {}

# --- AC1 — 2–3 candidates per selection, offered as a step -----------------
check(ct.get("count") == {"min": 2, "max": 3},
      "the gate asks for 2–3 candidate theses, never one")
check(bool(ct.get("label")) and bool(ct.get("line")),
      "the candidate step is offered with its own label and line")
check("consultant" not in one and "candidate_theses" not in one,
      "one Strand gets no candidates — there is nothing to re-read")

# --- AC2 — candidates are readings of the COMPLETE set ---------------------
check(ct.get("over") == s["indexes"],
      "the candidates are composed over the complete selected set")
check([m["index"] for m in ct.get("inputs") or []] == s["indexes"],
      "the composition inputs are exactly the selected members")

# --- the grounding correction: candidates are NEW COMPOSITION --------------
check(ct.get("composed") is False,
      "the block states that nothing here is a composed thesis")
con = s.get("consultant") or {}
check(set(con) >= {"subject", "substitution_candidates"}
      and "candidates" not in con,
      "the consultant still computes a subject and an unranked pool, and no "
      "candidate theses — they were never there to render")
# --- the RECOMMENDATION is contract (Story 20.89, #1043) --------------------
# This assertion replaces `ct.get("ranked") is False`, whose reason string
# carried the same false statement the field did: what THESIS_REQUIREMENTS[3]
# bans is ranked-AND-trimmed, not ranking. The gate now states what it actually
# guarantees.
check("ranked" not in ct,
      "the false field is gone — the gate no longer claims that no ordering "
      "exists, which is stronger than anything its requirements say")
rec = ct.get("recommendation") or {}
check(rec.get("required") is True,
      "a recommendation is REQUIRED beside the candidates — a gate presenting "
      "options carries its own comparison, and this is a promise the product "
      "makes rather than something the model happened to do")
check(rec.get("trims") is False and rec.get("machine_final") is False,
      "and nothing is hidden: rank confers no default, no candidate is "
      "trimmed or reordered away, and the recommendation is machine-proposed "
      "and never machine-final")
check(rec.get("declares_axes") is True
      and rec.get("declares_overturn") is True,
      "the recommendation names the axes it assessed on and states what would "
      "overturn it")
check(any("RECOMMENDATION is offered BESIDE" in r
          for r in (ct.get("requirements") or [])),
      "the requirement governing the recommendation ships in "
      "THESIS_REQUIREMENTS, where the composer reads it")
check(any("ENUMERATED, never ranked-and-trimmed" in r
          for r in (ct.get("requirements") or [])),
      "and THESIS_REQUIREMENTS[3] is RETAINED — the new requirement constrains "
      "ranking, it does not replace the ban on trimming")
# --- the ARC travels into the block's inputs (Story 20.90, #1044, AC5) ------
# `thesis_candidates_block` sets `"inputs": list(members)` and gained no edit
# of its own; this asserts the inheritance is a TESTED property rather than an
# incidental one, and that the pool beside it was deliberately NOT widened.
inputs = ct.get("inputs") or []
check(all("journey" in i for i in inputs),
      "every candidate-thesis input carries its Strand's journey block — the "
      "arcs reach the gate without thesis_candidates_block changing")
check(all({"arc", "arc_cite", "served", "not_served_reason"} <= set(i["journey"])
          for i in inputs),
      "and each states absence in its KIND — served plus a reason — never as "
      "a missing key")
check(all("journey" not in c
          for c in (con.get("substitution_candidates") or [])),
      "AC3: the substitution pool is NOT widened — it is offered material, not "
      "pointed-at material, and it is the complete unselected set")
check(all("journey" in m for m in (con.get("subject") or [])),
      "AC3: the consultant's SUBJECT — what the owner selected — does carry "
      "the arcs")
check(len(ct.get("requirements") or []) == 6,
      f"the requirement count follows the list "
      f"({len(ct.get('requirements') or [])}) — a silently dropped "
      "requirement still fails this check")

# --- the join is REPLACED as the thesis, not extended ----------------------
th = s.get("thesis") or {}
check(th.get("state") == "candidates-pending" and th.get("text") is None,
      "no thesis exists until the owner chooses one")
check("COVERAGE STATEMENT" in (th.get("brief_string_is") or "")
      and "COVERAGE STATEMENT" in (th.get("line") or ""),
      "the brief string says what it is — a coverage statement, not a reading")
src = open("scripts/topic-map-directions.py", encoding="utf-8").read()
body = src.split("def _brief_from_index")[1].split("\ndef ")[0]
check('"; ".join(' not in body and "coverage_statement(matches)" in body,
      "the one-thesis join is gone from the brief path, not extended")

# --- AC4 — each candidate is pinned and grounded ---------------------------
check(ct.get("pin") == s["pin"],
      "the candidates are pinned to the selection's own pin")
check(all(m.get("cite") for m in ct.get("inputs") or []),
      "every input carries the served cite a candidate must ground in")

# --- AC3 — the count, and what it counted ----------------------------------
r = json.load(open(w + "/r-good.json"))
check(r.get("counted") == "after-composition",
      "the report states that the count ran after composition")
c1, c2 = r["candidates"]
check(c1["placed"] == c1["selected"] == 3 and c1["complete"],
      "a candidate placing every selected Strand is counted complete")
check(c2["placed"] == 2 and c2["omitted"] and not c2["undisclosed"],
      "a DISCLOSED omission is named and offered anyway — annotation, never "
      "narrowing")
check(not r["refusals"],
      "a disclosed omission does not refuse the proposal")

# --- AC5/AC6/AC7 — the partition -------------------------------------------
pp = l.get("partition_proposal") or {}
check("partition_proposal" not in s,
      "a small selection is offered no partition — the threshold is a "
      "condition for OFFERING, and an unoffered proposal is absent")
check(pp.get("over") == l["indexes"] and pp.get("offered") is True,
      "the partition is proposed over the whole selected set")
check((pp.get("contract") or {}).get("options")
      == ["approve", "modify", "decline"],
      "the partition runs under the proposal contract")
check("never a silent restructure" in json.dumps(pp),
      "the proposal states that it is never a silent restructure")
p = cover("p-good", "brief-large.json")
check(not p["refusals"], "a conforming partition passes the cover")
check(p["placed"] == p["selected"] == len(l["indexes"]) and p["complete"],
      "every one of the N selected Strands lands in some proposed group")
b = p.get("backlog") or {}
check(b.get("k") == 2 and "ONE AT A TIME" in (b.get("policy") or ""),
      "k accepted briefs feed the drafting backlog, not k simultaneous "
      "publishes")
check([g["members"] for g in b.get("briefs") or []]
      == [g["members"] for g in p["groups"]],
      "each backlog brief is pinned to its own group's member subset")
d = cover("p-dropped", "brief-large.json")
check([x["index"] for x in d["dropped"]] == [l["indexes"][-1]]
      and d["complete"] and not d["refusals"],
      "an explicitly owner-dropped member is accepted and recorded as "
      "dropped, not lost")

# --- AC8 — free text remains a first-class exit ----------------------------
check(free["brief"] == "my own thesis, in my own words"
      and free["origin"] == "free-form",
      "free text still wins, unchanged")
check("candidate_theses" not in free and "partition_proposal" not in free,
      "a free-form brief proposes nothing over a set it does not have")

# --- JOURNEY INCORPORATION (Story 20.166, #1045) ----------------------------
# A disclosure riding the brief, never a required slot; options composed from
# THIS brief's state; the four ratified requirements frozen; the same
# after-composition cover.
adopted = json.load(open(w + "/b-adopted.json"))
final = json.load(open(w + "/ws/brief-final.json"))
check("journey_incorporation" not in s,
      "before a thesis is adopted the register question does not exist — "
      "the block is absent, not present-and-empty")
check("journey_incorporation" not in free,
      "a free-form brief raises no incorporation gate")
ji = adopted.get("journey_incorporation") or {}
check(ji.get("state") == "options-pending" and ji.get("composed") is False,
      "adoption raises the incorporation block, composed by nobody yet — "
      "`composed: false` is literal, exactly as the thesis block's is")
check(len(ji.get("with_journey") or []) == 1
      and len(ji.get("without_journey") or []) == 2
      and all(x.get("reason") for x in ji.get("without_journey") or []),
      "the block names which members carry a served arc and discloses the "
      "rest with a reason — the omission the options never owe")
reqs = ji.get("requirements") or []
check(len(reqs) == 4,
      f"the four ratified requirements travel frozen ({len(reqs)}) — a "
      "silently dropped requirement still fails this check")
for phrase in ("cover counted in placements", "SERVED arc rendering",
               "rule-statement register", "ENUMERATED, never ranked-and-trimmed"):
    check(any(phrase in r for r in reqs),
          f"the requirements carry: {phrase}")
check("options" not in ji,
      "no option is authored at the gate — a fixed register enumeration is "
      "exactly what must not ship (per-brief composition, never a menu)")
check((ji.get("inputs") or {}).get("thesis") == "one reading",
      "the composition inputs carry THIS brief's adopted thesis — the state "
      "the options are composed against")
jf = final.get("journey_incorporation") or {}
check(jf.get("state") == "adopted" and jf.get("adopted")
      and len(jf.get("options") or []) == 2,
      "an adopted register records the WHOLE offer beside the choice — the "
      "rejected option is the provenance of the choice (#1079's rule)")
for k in ("line", "label", "requirements", "answer", "inputs",
          "payload_contract"):
    check(k not in jf,
          f"the artifact stores no `journey_incorporation.{k}` — rendering "
          "and process documentation are composed at the screen (#1078)")
# The cover, over the emitted options, against the served material only.
r = json.load(open(w + "/r-inc.json"))
o1, o2 = r["options"]
check(r.get("counted") == "after-composition"
      and o1["placed"] == o1["selected"] == 1 and o1["complete"],
      "an option placing every served arc is counted complete")
check(o2["placed"] == 0 and o2["disclosed"] and not o2["undisclosed"]
      and not r["refusals"],
      "a DISCLOSED omission is named and offered anyway — annotation, "
      "never narrowing")
refuses("i-one", "brief-adopted.json", "at least")
refuses("i-invented", "brief-adopted.json", "invented material")
refuses("i-unserved", "brief-adopted.json", "not served at this pin")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- Story 20.211 (#1410): STRUCTURE IS COMPOSED, NEVER SELECTED FROM A STOCK.
# Negative run (governance rule 6): every assertion below was watched failing
# against main@06f291d (pre-20.211 modules) — block absent, kind unrouteable,
# adoption unguarded — before this section landed.
python3 - "$work" <<'PYEOF' || fail=1
import json, subprocess, sys
w = sys.argv[1]
fail = 0
def check(cond, msg):
    global fail
    if cond: print("ok:   20.211: " + msg)
    else:    print("FAIL: 20.211: " + msg); fail = 1
run = lambda *a: subprocess.run(
    ["python3", "scripts/topic-map-directions.py"] + list(a),
    capture_output=True, text=True)

final = json.load(open(w + "/b-final.json"))
small = json.load(open(w + "/b-small.json"))
sc = final.get("structure_candidates") or {}
# The gate is raised by ADOPTION, sequenced after the register, composed by
# nobody yet.
check(sc.get("state") == "candidates-pending" and sc.get("composed") is False,
      "an adopted brief raises the structure block, `composed: false` literal")
check("structure_candidates" not in small,
      "no structure gate before a thesis is adopted — absent, not empty")
check("candidates" not in sc,
      "no candidate is authored at the gate — a framework menu is exactly "
      "what must not ship (#1410)")
check((sc.get("inputs") or {}).get("thesis") == "one reading",
      "the inputs carry THIS brief's adopted thesis")
check((sc.get("inputs") or {}).get("journey_incorporation"),
      "the adopted register rides the inputs — a journey-shaped candidate "
      "must agree with the register the owner already chose")
reqs = sc.get("requirements") or []
check(any("bespoke" in r for r in reqs) and
      any("never a framework name" in r for r in reqs),
      "the requirements carry the #911 instrument and the no-menu rule")

# The cover: a conforming set passes; the menu returning through the answer
# file is refused; so are a missing rationale and a silent drop.
b = json.load(open(w + "/ws/brief-final.json"))
ids = [m["index"] for m in b["members"]]
gd = lambda xs: [{"index": i, "cite": "LESSONS.md:1@abc1234"} for i in xs]
good = {"kind": "structure-candidates", "over": ids, "pin": b["pin"],
        "candidates": [
    {"structure": "open with the failure case; walk each member's claim; "
                  "close by composing them into the thesis",
     "rationale": "the widened Strand's arc is the strongest concrete anchor",
     "places": ids, "grounds": gd(ids)},
    {"structure": "state the thesis plainly; contrast the two engineering "
                  "members; end on the people member as the cost",
     "rationale": "the topic split in the set motivates a contrast shape",
     "places": ids[:2], "grounds": gd(ids[:2]),
     "omits": [{"index": ids[2], "why": "reads as an aside in this shape"}]}]}
json.dump(good, open(w + "/s-good.json", "w"))
r = run("cover", "--composed", w + "/s-good.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode == 0, "a conforming structure set passes the cover: "
      + r.stderr[:120])
menu = json.loads(json.dumps(good))
menu["candidates"][0] = {"structure": "ki-sho-ten-ketsu",
                         "places": ids, "grounds": gd(ids)}
json.dump(menu, open(w + "/s-menu.json", "w"))
r = run("cover", "--composed", w + "/s-menu.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode != 0 and "menu" in (r.stdout + r.stderr),
      "a bare framework name where ordered moves belong is refused — the "
      "menu returning through the answer file")
silent = json.loads(json.dumps(good))
silent["candidates"][1].pop("omits")
json.dump(silent, open(w + "/s-silent.json", "w"))
r = run("cover", "--composed", w + "/s-silent.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode != 0 and "neither places nor discloses" in (r.stdout + r.stderr),
      "a silent Strand drop is refused, by name")
one = json.loads(json.dumps(good)); one["candidates"] = one["candidates"][:1]
json.dump(one, open(w + "/s-one.json", "w"))
r = run("cover", "--composed", w + "/s-one.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode != 0 and "at least" in (r.stdout + r.stderr),
      "one candidate is the machine deciding — refused")

# Adoption: the #1079 rule and the #911 instrument, both refusals named.
ans = json.load(open(w + "/a-adopt-reg.json"))
ans["structure"] = good["candidates"][0]["structure"]
json.dump(ans, open(w + "/a-adopt-struct.json", "w"))
r = run("brief", "--answer", w + "/a-adopt-struct.json",
        "--map", w + "/map.json", "--composed", w + "/c-good.json",
        "--incorporation", w + "/i-good.json")
check(r.returncode != 0 and "adopted from" in (r.stdout + r.stderr),
      "adopting a structure without --structures is refused (#1079)")
r = run("brief", "--answer", w + "/a-adopt-struct.json",
        "--map", w + "/map.json", "--composed", w + "/c-good.json",
        "--incorporation", w + "/i-good.json",
        "--structures", w + "/s-good.json")
check(r.returncode != 0 and "bespoke" in (r.stdout + r.stderr),
      "adopting a structure with no framework_matched is refused — the #911 "
      "instrument makes silence impossible")
ans["structure_framework_matched"] = "bespoke"
json.dump(ans, open(w + "/a-adopt-struct.json", "w"))
r = run("brief", "--answer", w + "/a-adopt-struct.json",
        "--map", w + "/map.json", "--composed", w + "/c-good.json",
        "--incorporation", w + "/i-good.json",
        "--structures", w + "/s-good.json",
        "--out", w + "/ws/brief-struct.json")
check(r.returncode == 0, "adoption with candidates + explicit bespoke "
      "succeeds: " + r.stderr[:150])
if r.returncode == 0:
    out = json.loads(r.stdout)
    scb = out.get("structure_candidates") or {}
    check(scb.get("state") == "adopted"
          and len(scb.get("candidates") or []) == 2,
          "an adopted structure records the WHOLE offer beside the choice")

# The registry and the prose both carry the gate.
import re
gates_src = open("scripts/draft_gates.py", encoding="utf-8").read()
check(gates_src.find('"journey-incorporation"') < gates_src.find('"structure"')
      < gates_src.find('"resume-confirmation"'),
      "GATES declares `structure` after `journey-incorporation` — the "
      "registry order is load-bearing")
prose = (open("skills/terrain/steps/brief.md", encoding="utf-8").read()
         + open("skills/terrain/steps/brief-gates.md", encoding="utf-8").read())
check('draft_gates.gate("structure"' in prose,
      "brief.md routes the candidates through the declared carrier — a gate "
      "with no writer is dead code wearing enforcement's name")
s3 = open("skills/draft-article/stages/stage3.md", encoding="utf-8").read()
check("not re-raised" in s3 or "not re-raise" in s3,
      "stage3 states the narrative-structure gate is not re-raised over a "
      "brief-adopted structure — asked exactly once")

# --- Story 20.212 (#1411): THE PLAIN-REGISTER COMMITMENT ----------------------
def check(cond, msg):        # noqa: F811 — this block labels its own story
    global fail
    if cond: print("ok:   " + msg)
    else:    print("FAIL: " + msg); fail = 1
# Negative run (rule 6): every assertion watched failing against main@c8e74ed
# (pre-20.212) — block absent, kind unrouteable, adoption unguarded.
b = json.load(open(w + "/ws/brief-final.json"))
ids = [m["index"] for m in b["members"]]
final2 = json.load(open(w + "/b-final.json"))
pr = final2.get("plain_register") or {}
check(pr.get("state") == "candidates-pending" and pr.get("composed") is False,
      "20.212: an adopted brief raises the register block, composed:false")
check("candidates" not in pr,
      "20.212: no candidate is authored at the gate")
reqs2 = pr.get("requirements") or []
check(any("never 'write for a child'" in r for r in reqs2),
      "20.212: the requirements refuse audience impersonation by name")
check(any("ROUND-TRIP CONCESSION" in r for r in reqs2),
      "20.212: the requirements demand the round-trip concession")
check("quoted as served" in str(pr.get("boundary") or "").lower()
      or "QUOTED AS SERVED" in str(pr.get("boundary") or ""),
      "20.212: the block states the journey boundary — arcs stay quoted")

rend = lambda xs: [{"index": i, "plain": "a simple sentence",
                    "cite": "LESSONS.md:1@abc1234"} for i in xs]
rgood = {"kind": "plain-register", "over": ids, "pin": b["pin"],
         "candidates": [
    {"plain": "when one thing changes, the other stops working",
     "concession": "loses the word 'invariant'; restored in the body",
     "renderings": rend(ids)},
    {"plain": "a rule only helps where someone checks it",
     "concession": "nothing lost", "renderings": rend(ids)}]}
json.dump(rgood, open(w + "/r-good.json", "w"))
r = run("cover", "--composed", w + "/r-good.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode == 0, "20.212: a conforming register set passes the cover: "
      + r.stderr[:120])
noc = json.loads(json.dumps(rgood)); noc["candidates"][0].pop("concession")
json.dump(noc, open(w + "/r-noconc.json", "w"))
r = run("cover", "--composed", w + "/r-noconc.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode != 0 and "round-trip concession" in (r.stdout + r.stderr),
      "20.212: a candidate with no concession is refused — losslessness "
      "asserted silently is the derivation hazard's quiet form")
nocite = json.loads(json.dumps(rgood))
nocite["candidates"][0]["renderings"][0]["cite"] = ""
json.dump(nocite, open(w + "/r-nocite.json", "w"))
r = run("cover", "--composed", w + "/r-nocite.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode != 0 and "invention wearing simplicity" in (r.stdout + r.stderr),
      "20.212: a rendering with no served-claim cite is refused")
rsilent = json.loads(json.dumps(rgood))
rsilent["candidates"][1]["renderings"] = rend(ids[:1])
json.dump(rsilent, open(w + "/r-silent.json", "w"))
r = run("cover", "--composed", w + "/r-silent.json",
        "--from", w + "/ws/brief-final.json")
check(r.returncode != 0 and "neither renders nor discloses" in (r.stdout + r.stderr),
      "20.212: a silent Strand drop is refused — the close inherits the gap")

ans2 = json.load(open(w + "/a-adopt-struct.json"))
ans2["plain_register"] = rgood["candidates"][0]["plain"]
json.dump(ans2, open(w + "/a-adopt-reg2.json", "w"))
base = ["brief", "--answer", w + "/a-adopt-reg2.json", "--map", w + "/map.json",
        "--composed", w + "/c-good.json", "--incorporation", w + "/i-good.json",
        "--structures", w + "/s-good.json"]
r = run(*base)
check(r.returncode != 0 and "adopted from" in (r.stdout + r.stderr),
      "20.212: adopting a commitment without --register is refused (#1079)")
r = run(*(base + ["--register", w + "/r-good.json",
                  "--out", w + "/ws/brief-reg.json"]))
check(r.returncode == 0, "20.212: adoption with candidates succeeds: "
      + r.stderr[:150])
if r.returncode == 0:
    prb = (json.loads(r.stdout).get("plain_register") or {})
    check(prb.get("state") == "adopted"
          and len(prb.get("candidates") or []) == 2,
          "20.212: an adopted commitment records the WHOLE offer")

gsrc = open("scripts/draft_gates.py", encoding="utf-8").read()
check(gsrc.find('"structure"') < gsrc.find('"plain-register"')
      < gsrc.find('"resume-confirmation"'),
      "20.212: GATES declares `plain-register` after `structure`")
prose2 = (open("skills/terrain/steps/brief.md", encoding="utf-8").read()
          + open("skills/terrain/steps/brief-gates.md", encoding="utf-8").read())
check('draft_gates.gate("plain-register"' in prose2,
      "20.212: brief.md routes the candidates through the declared carrier")
check("never re-expressed" in prose2 or "quoted as served" in prose2,
      "20.212: brief.md restates the journey boundary at the new gate")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
