#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/topic-map-directions.py scripts/terrain_brief.py
#   scripts/terrain_scope.py
# removal-signal: the brief acquires a declared JSON schema enforced by a
#   validator at the write — this check asserts by hand exactly what such a
#   schema would assert, and retires the moment one exists.
# check-brief-content-contract.sh — the brief's CONTENT contract (Story 20.99,
# #1077; SPEC-terrain presentation.md, "what the brief CARRIES, and what it
# never carries", added 2026-07-31 for #1077/#1078/#1079/#1080).
#
# WHY A KEY-SET CHECK AND NOT A PROPERTY ONE. The alternative considered at
# triage was to contract the brief's PROPERTIES and leave field names free,
# which matches the hub's non-ratification of the schema most literally. It was
# declined because "no rendering strings" is a judgment nothing can decide
# mechanically, while a key set is decidable — and the whole point of closing
# the list is that a field arrives by amending the clause rather than by
# accretion nobody decided. A five-member brief had reached 41 KB across 21
# top-level keys that way.
#
# THE ALLOWED LIST SHRINKS AS THE COUPLED GROUP LANDS. #1077 (this story)
# removes the vestigial singulars; #1078 removes the embedded screen rendering
# and process documentation; #1079 lands the candidate write-back; #1080 adds
# the harvest scope. Until those land, their keys are listed below as PRESENT
# AND SCHEDULED FOR REMOVAL, named individually with the issue that removes
# each — an honest interim, and one that makes the tightening a visible edit
# here rather than a silent widening.
#
# SCOPE: the INDEXED/SET path (`origin: adopted-index*`), which is what #1077 is
# about. The adopted-candidate path (`topic-map-directions.py:626-629`) is a
# different, older brief shape with no member set; it is not contracted here and
# is recorded as an open observation rather than silently swept in.

set -u
cd "$(dirname "$0")/.."
D="scripts/topic-map-directions.py"
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

python3 -c "import py_compile; py_compile.compile('$D', doraise=True)" 2>/dev/null \
  || { err "$D does not compile"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
projects = [["repo-a"], ["repo-a", "repo-b"], ["portfolio-wide"], []]
els = [{"kind": "lesson", "slug": f"s{n}", "title": f"S{n}",
        "gloss": f"a claim the material makes, number {n}",
        "tags": ["workflow"], "situation": f"LESSONS.md:{n}@abc1234",
        "evidence": ["LESSONS.md:1@abc1234"], "consumed": False,
        "projects": projects[n],
        "journey_recorded": True, "journey": f"the position changed, {n}"}
       for n in range(4)]
json.dump({"kind": "topic-map", "topics": [],
           "coverage": {"pin": "h@abc1234", "hub_pin": "hub@def5678"},
           "elements": els}, open(w + "/map.json", "w"))
# An OLDER PIN whose element records do not carry `projects:` (#1097 AC4).
json.dump({"kind": "topic-map", "topics": [],
           "coverage": {"pin": "h@abc1234", "hub_pin": "hub@def5678"},
           "elements": [{k: v for k, v in e.items() if k != "projects"}
                        for e in els]}, open(w + "/map-old.json", "w"))
PYEOF

pin=$(python3 -c "import json,sys;print(json.load(open('$work/map.json'))['coverage']['pin'])")

# THE SUBJECT IS THE WRITTEN ARTIFACT, NOT STDOUT (corrected by Story 20.100,
# #1078). The two are deliberately different: the stdout payload carries the
# GATE and must stay undiminished, while the artifact carries the DECISION —
# the seam Story 20.93 built. A check reading stdout would assert the contract
# against the one surface it does not bind, and would block Story 20.100's
# whole change.
emit() {  # $1 = selection string, $2 = artifact path
  # `--answer -` reads the recorded answer from stdin; passing it inline would
  # be read as a PATH, which is what the flag's other form means. The typed
  # selection rides on `index` — the key `_selection_terms` parses — which also
  # accepts one string naming several ids.
  printf '{"index":"%s","pin":"%s"}' "$1" "$pin" \
    | python3 "$D" brief --map "$work/map.json" --answer - --out "$2" \
        > "$work/stdout.json" 2>"$work/err" \
    || { err "brief failed for index '$1': $(cat "$work/err")"; return 1; }
}

emit "L1, L2, L3" "$work/set.json" || { printf '\nFAILED.\n' >&2; exit 1; }

# ADOPTION REQUIRES THE CANDIDATES (Story 20.101, #1079). Asserted at the CLI
# because the refusal is the behaviour: the state that must never exist is
# `adopted` beside an empty record of what it was adopted from.
cat > "$work/cands.json" <<'CJ'
{"kind": "candidate-theses", "over": ["L1", "L2", "L3"], "pin": "PIN",
 "candidates": [{"thesis": "reading one", "places": ["L1", "L2", "L3"]},
                {"thesis": "reading two", "places": ["L1", "L2", "L3"]}],
 "recommendation": {"pick": 1, "axes": ["coverage"],
                    "overturn": "if the cost angle is wanted"}}
CJ
sed -i "s/PIN/$pin/" "$work/cands.json"

printf '{"index":"L1, L2, L3","pin":"%s","claim":"reading two"}' "$pin" \
  | python3 "$D" brief --map "$work/map.json" --answer - \
      > /dev/null 2>"$work/refusal.err" \
  && err "#1079: adopting a thesis with NO composed candidates was allowed" \
  || { grep -q 'adopted from' "$work/refusal.err" \
       && ok "#1079: adopting without composed candidates is REFUSED, naming what is missing" \
       || err "#1079: refused for the wrong reason: $(cat "$work/refusal.err")"; }

printf '{"index":"L1, L2, L3","pin":"%s","claim":"reading two"}' "$pin" \
  | python3 "$D" brief --map "$work/map.json" --answer - \
      --composed "$work/cands.json" --out "$work/adopted.json" \
      > /dev/null 2>"$work/err" \
  || err "#1079: adopting WITH composed candidates failed: $(cat "$work/err")"
emit "L1"         "$work/one.json" || { printf '\nFAILED.\n' >&2; exit 1; }

# The OLDER-PIN composition (#1097 AC4): same selection, records without
# `projects:`, so the scope must render the three-valued absence shape.
printf '{"index":"L1, L2, L3","pin":"%s"}' "$pin" \
  | python3 "$D" brief --map "$work/map-old.json" --answer - \
      --out "$work/old.json" > /dev/null 2>"$work/err" \
  || err "#1097: composing at an older pin failed: $(cat "$work/err")"

# The NON-REPOSITORY carriers (#1185): a portfolio-wide alone-carrier beside
# an empty-carrier, so the two absent-of-repository classes must stay
# distinguishable in the derived scope.
printf '{"index":"L3, L4","pin":"%s"}' "$pin" \
  | python3 "$D" brief --map "$work/map.json" --answer - \
      --out "$work/claims.json" > /dev/null 2>"$work/err" \
  || err "#1185: composing over the claim carriers failed: $(cat "$work/err")"

# THE JUDGE PIN (Story 20.106, #1090) — declared, never introspected, and
# absent-as-absent. Three cases, because the failure being guarded is a pin
# that cannot tell "no judge declared" from "taken before the field existed".
printf '{"index":"L1, L2, L3","pin":"%s"}' "$pin" \
  | python3 "$D" brief --map "$work/map.json" --answer - \
      --judge "a-model@high" --out "$work/judged.json" > /dev/null 2>"$work/err" \
  || err "#1090: a declared judge was refused: $(cat "$work/err")"

python3 - "$work" <<'PYEOF' || fail=1
import json, sys
w = sys.argv[1]
fail = 0


def check(cond, msg):
    global fail
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond:
        fail = 1


# The contract's carried fields, plus the interim ones each named with the
# issue that removes it. Editing this list is how a field arrives or leaves.
CARRIED = {
    "brief", "provenance", "origin", "index", "indexes", "pin", "note",
    "adopted_claim", "members", "pins", "recomposition", "consultant",
    "gaps", "thesis", "candidate_theses", "stage",
    # #1080: the composer's own summary, labelled as the composer's and sitting
    # BESIDE the owner's slot rather than inside it; and the harvest scope,
    # which is owed but not emittable here (see the assertions below).
    "selection_summary", "examine_scope",
    # #1118: the record ATTESTS to the owner's answer. Without these the record
    # is byte-identical to what a silent, machine-initiated adoption would have
    # produced — which is why an incomplete transcript was enough to make a
    # correct, owner-named adoption look like a defect. `thesis_origin` is a
    # different axis from `origin` (that one records how the MEMBERS were
    # selected, never how the THESIS was chosen); `answer_as_given` is the
    # owner's utterance distinct from the text it resolved to; `note_is`
    # declares which question the note answered, since the adoption gate
    # inherits the selection gate's free text.
    "thesis_origin", "answer_as_given", "note_is",
    # Story 20.166 (#1045): the journey-incorporation disclosure — present
    # only on a brief with an adopted thesis and served arcs, asserted below
    # on the adopted fixture. A DISCLOSURE, never a required slot: its
    # absence from the claim-less briefs is asserted too.
    "journey_incorporation",
}
INTERIM = {  # present today, scheduled for removal, named with its issue
    "step": 1079, "lifecycle": 1079, "artifact": 1079, "iteration": 1079,
}
REMOVED = {  # removals asserted absent, each with the issue that made it
    "candidate": 1077, "gap": 1077, "next": 1078,
}
# Rendering and process keys, per block (#1078). The artifact keeps the STATE;
# the screen composes the sentence at render time. Asserted per block so a
# regression names which block grew a line back.
RENDERED = {
    "step": ("line",),
    "artifact": ("line", "read_back"),
    "lifecycle": ("line",),
    "iteration": ("line",),
    "thesis": ("line", "brief_string_is"),
    "candidate_theses": ("line", "label", "requirements", "recommendation",
                         "answer", "inputs"),
    "partition_proposal": ("line", "label", "backlog_line"),
    "journey_incorporation": ("line", "label", "requirements",
                              "payload_contract", "answer", "inputs"),
}

s = json.load(open(w + "/set.json"))
one = json.load(open(w + "/one.json"))
adopted = json.load(open(w + "/adopted.json"))
judged = json.load(open(w + "/judged.json"))

# THE JUDGE PIN (#1090): a fourth component beside terrain/hub/destination.
_jp = (judged.get("pins") or {}).get("judge") or {}
check(_jp.get("model") == "a-model" and _jp.get("effort") == "high"
      and _jp.get("served") is True,
      "#1090: a DECLARED judge is recorded as model + effort tier")
_up = (s.get("pins") or {}).get("judge") or {}
check(_up.get("served") is False and _up.get("not_served_reason"),
      "#1090: ...and an undeclared one records the ABSENCE with its reason — "
      "never a default model name, which would guess the one fact the pin "
      "exists to record")
check(_up.get("model") is None and _up.get("effort") is None,
      "#1090: ...with no invented value beside it")

# THE ADOPTED BRIEF CARRIES WHAT IT WAS ADOPTED FROM (#1079).
_ct = adopted.get("candidate_theses") or {}
check(adopted.get("thesis", {}).get("state") == "adopted"
      and _ct.get("composed") is True,
      "#1079: an adopted thesis records that its candidates were composed")
check(len(_ct.get("candidates") or []) == 2,
      "#1079: ...and the REJECTED candidate survives beside the taken one — "
      "the choice's provenance is the whole offer")
_rec = _ct.get("recommendation") or {}
check(_rec.get("axes") and _rec.get("overturn"),
      "#1079: ...and the recommendation keeps its declared axes and its "
      "OVERTURNING conditions — stripped of those it is a default in disguise")
# The gate's guarantee object and the composed recommendation share a key and
# are told apart by `composed`, a declared field, never by shape.
check((s.get("candidate_theses") or {}).get("recommendation") is None,
      "#1079/#1078: before composition the key holds the gate's own guarantee "
      "object, which is process self-documentation and is NOT stored")

# THE ADOPTION ACT MOVES THE LIFECYCLE (#1208). Recording the adopted answer
# and moving the brief's visible truth are one act: an artifact whose thesis
# is adopted while its lifecycle never entered `adopted` is the two-carrier
# disagreement the observed run produced.
_lf = adopted.get("lifecycle") or {}
check(_lf.get("state") == "adopted"
      and [h.get("state") for h in _lf.get("history") or []]
      == ["composed", "adopted"],
      "#1208: recording the adopted answer moves the lifecycle to `adopted` "
      "in the same act, through the recorded history")
check((s.get("lifecycle") or {}).get("state") == "composed",
      "#1208: ...and a brief whose thesis was never adopted stays `composed`, "
      "exactly as before")

# THE JOURNEY-INCORPORATION DISCLOSURE (Story 20.166, #1045). It RIDES the
# adopted brief — these fixture members all carry served arcs — and never
# exists as a required slot: the claim-less briefs carry no block at all.
_ji = adopted.get("journey_incorporation") or {}
check(_ji.get("state") == "options-pending" and _ji.get("composed") is False
      and _ji.get("with_journey") == ["L1", "L2", "L3"],
      "20.166: an adopted brief over arc-carrying members raises the "
      "incorporation disclosure, composed by nobody yet")
for k in RENDERED["journey_incorporation"]:
    check(k not in _ji,
          f"20.166: `journey_incorporation.{k}` is not stored — the screen "
          "composes it at render time (#1078)")
check("journey_incorporation" not in s and "journey_incorporation" not in one,
      "20.166: before a thesis is adopted no incorporation slot exists — a "
      "disclosure is absent, never present-and-empty")

for name, b in (("a 3-member set", s), ("a 1-member set", one)):
    keys = set(b)
    unknown = keys - CARRIED - set(INTERIM)
    check(not unknown,
          f"{name}: no key outside the contract "
          f"({'unknown: ' + ', '.join(sorted(unknown)) if unknown else 'none'})")
    for k, issue in REMOVED.items():
        check(k not in keys,
              f"{name}: `{k}` is absent from the artifact (#{issue})")

# THE OWNER'S SLOT HOLDS OWNER TEXT OR NOTHING (#1080). It carried machine
# prose on a run where the owner stated no angle, which inverts the ruling that
# kept free text first-class: a reader could no longer tell owner speech from
# composer commentary in the one field reserved for owner speech.
for name, b in (("a 3-member set", s), ("a 1-member set", one)):
    check(b.get("note") is None,
          f"{name}: with no angle stated, `note` is null — absence of an angle "
          f"is recorded AS absence, never as machine prose (#1080)")
    check(isinstance(b.get("selection_summary"), str),
          f"{name}: ...and the composer's own summary sits in its own labelled "
          f"field beside the owner's, never inside it")
    check(b.get("provenance") == "terrain-adopted",
          f"{name}: `provenance` is the RATIFIED value for a brief composed at "
          f"the gate — `owner-authored` is the owner's own free-form words")

# HARVEST SCOPE IS THE UNION OF THE MEMBERS' SERVED `projects:` (#1097). Read
# from the served records, never re-derived from lesson bodies; the interim
# `served: false` branch and its manifest-falsified reason are GONE from the
# served case, and per-member provenance survives the union so a later
# refusal can name its Strand.
hs = s.get("examine_scope") or {}
check(hs.get("served") is True
      and hs.get("projects") == ["repo-a", "repo-b", "portfolio-wide"],
      "#1097: harvest scope is the union of the selected members' served "
      "`projects:` values, as served")
check("not_served_reason" not in hs,
      "#1097: the served case carries no `not_served_reason` — the stale "
      "claim can no longer be written")
check(hs.get("by_member") == [{"index": "L1", "projects": ["repo-a"]},
                              {"index": "L2", "projects": ["repo-a", "repo-b"]},
                              {"index": "L3", "projects": ["portfolio-wide"]}],
      "#1097: per-member provenance survives the union — which member "
      "contributed which values")
hs1 = one.get("examine_scope") or {}
check(hs1.get("served") is True and hs1.get("projects") == ["repo-a"],
      "#1097: a 1-member selection unions its one member's values")
old = json.load(open(w + "/old.json"))
ho = old.get("examine_scope") or {}
check(ho.get("served") is False and ho.get("projects") is None
      and "predates" in (ho.get("not_served_reason") or ""),
      "#1097: at an older pin with no served `projects:` the three-valued "
      "absence shape renders, with a reason true of that pin")

# THE DERIVED EXAMINATION SCOPE (#1185). The scope question has one answer
# where the union resolves to a single repository candidate, and an answered
# question is not asked; more than one candidate leaves it the owner's.
sq = hs1.get("scope_question") or {}
check(sq.get("needed") is False and sq.get("answer") == "repo-a",
      "#1185: a scope union resolving to a single repository candidate asks "
      "no which-repository question — it has one answer")
sq = hs.get("scope_question") or {}
check(sq.get("needed") is True
      and sq.get("candidates") == ["repo-a", "repo-b"],
      "#1185: two repository candidates leave the scope question the owner's")
cd = hs.get("cannot_determine") or {}
check(cd.get("values") == ["repo-a", "repo-b"]
      and "cannot-determine" in (cd.get("classification") or ""),
      "#1185: the repository-vs-scope-claim class is CANNOT-DETERMINE — "
      "parked behind the upstream carrier, never re-derived here")
claims = json.load(open(w + "/claims.json"))
hc = claims.get("examine_scope") or {}
check((hc.get("portfolio_wide") or {}).get("members") == ["L3"]
      and "scope claim" in (hc.get("portfolio_wide") or {}).get(
          "classification", ""),
      "#1185: `portfolio-wide` renders as an explicit named section — a "
      "scope claim, not an attribution, never a silent drop")
check((hc.get("hub_only") or {}).get("members") == ["L4"]
      and "no work item" in (hc.get("hub_only") or {}).get("line", ""),
      "#1185: an empty `projects:` is stated as hub-only material, minting "
      "nothing — and stays distinguishable from the alone-carrier")
check((hc.get("scope_question") or {}).get("needed") is False
      and (hc.get("scope_question") or {}).get("answer") is None,
      "#1185: no repository-valued scope asks nothing and answers nothing")
check("portfolio_wide" not in hs1 and "hub_only" not in hs1,
      "#1185: a section with no carriers is ABSENT, never present-and-empty")

# THE ORACLE BINDING (#1185 AC1): a Strand is examined only against the
# repositories its served `projects:` names — anything else is refused, not
# searched, with the Strand and its served attribution named. The rule lives
# in the scope layer so the examine stage consumes it.
sys.path.insert(0, "scripts")
import terrain_scope as ts
mem = next(m for m in s["members"] if m["index"] == "L2")
check(ts.examination_refusal(mem, "repo-b") is None,
      "#1185: a repository inside the served attribution is admitted")
r = ts.examination_refusal(mem, "repo-x") or {}
check(r.get("refused") is True and r.get("member") == "L2"
      and r.get("attribution") == ["repo-a", "repo-b"]
      and "refused, not searched" in r.get("line", ""),
      "#1185: a repository outside the served attribution is REFUSED, "
      "naming the Strand and its served attribution")
pwm = next(m for m in claims["members"] if m["index"] == "L3")
r = ts.examination_refusal(pwm, "repo-a") or {}
check(r.get("refused") is True,
      "#1185: `portfolio-wide` is never expanded into a repository set — it "
      "admits no repository through the binding")
em = next(m for m in claims["members"] if m["index"] == "L4")
r = ts.examination_refusal(em, "repo-a") or {}
check(r.get("refused") is True and "hub-only" in r.get("line", ""),
      "#1185: an empty attribution refuses as hub-only material")
om = next(m for m in old["members"] if m["index"] == "L1")
r = ts.examination_refusal(om, "repo-a") or {}
check(r.get("refused") is True and "cannot-determine" in r.get("line", ""),
      "#1185: an unserved attribution refuses as cannot-determine — never "
      "searched on a guess")

# NO RENDERED SENTENCE OR PROCESS DOC IS STORED (#1078). Each is a second copy
# that drifts — one already had, the stored line reading "2-3 candidates" while
# the screen showed 3 — and every embedded screen line couples drafting to
# Terrain's rendering, which the ratified boundary property forbids.
for name, b in (("a 3-member set", s), ("a 1-member set", one)):
    for block, keys in RENDERED.items():
        val = b.get(block)
        if not isinstance(val, dict):
            continue
        for k in keys:
            check(k not in val,
                  f"{name}: `{block}.{k}` is not stored — the screen composes "
                  f"it at render time (#1078)")

# THE DEGENERATE CASE TAKES THE SAME PATH. A set of one is not a different
# operation, and the singular growing back as a special case is exactly the
# shape #1077 reports.
check(set(one) - set(s) == set() or not (set(one) - set(s)),
      "a 1-member selection emits no key a 3-member one does not")
check(one.get("origin", "").startswith("adopted-index"),
      "...and it still takes the indexed path")

# GAPS COVER EVERY MEMBER, at every set size — the disclosure that `gap` used
# to provide for member[0] alone must not have been dropped with it.
for name, b in (("a 3-member set", s), ("a 1-member set", one)):
    g = b.get("gaps")
    if g is not None:
        check(all("index" in x for x in g),
              f"{name}: every disclosed gap names the member it belongs to")
        check(len({x["index"] for x in g}) == len(g),
              f"{name}: ...and no member is disclosed twice")

# MAP-INTERNAL WORKING STATE DOES NOT CROSS THE BOUNDARY. `candidate` dragged
# the map-element schema over whole; internal topic vocabulary reaching an
# artifact that crosses into drafting is the specific defect.
blob = json.dumps(s)
for leak in ("element_kind", "usability", "evidence_pointers", "subtopics",
             "hub-lessons"):
    check(leak not in blob,
          f"map-internal `{leak}` does not reach the brief")

# EACH MEMBER IS THE CLEAN PROJECTION, not a raw map element.
for m in s.get("members") or []:
    check(set(m) <= {"index", "slug", "gloss", "cite", "journey", "projects"},
          f"member {m.get('index')} carries only the recorded projection")

sys.exit(1 if fail else 0)
PYEOF

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll brief content-contract checks passed.\n'
