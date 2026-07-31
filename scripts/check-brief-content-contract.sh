#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/topic-map-directions.py scripts/terrain_brief.py
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
els = [{"kind": "lesson", "slug": f"s{n}", "title": f"S{n}",
        "gloss": f"a claim the material makes, number {n}",
        "tags": ["workflow"], "situation": f"LESSONS.md:{n}@abc1234",
        "evidence": ["LESSONS.md:1@abc1234"], "consumed": False,
        "journey_recorded": True, "journey": f"the position changed, {n}"}
       for n in range(4)]
json.dump({"kind": "topic-map", "topics": [],
           "coverage": {"pin": "h@abc1234", "hub_pin": "hub@def5678"},
           "elements": els}, open(w + "/map.json", "w"))
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
    "selection_summary", "harvest_scope",
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
}

s = json.load(open(w + "/set.json"))
one = json.load(open(w + "/one.json"))
adopted = json.load(open(w + "/adopted.json"))

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
    hs = b.get("harvest_scope") or {}
    check(hs.get("served") is False and hs.get("not_served_reason"),
          f"{name}: harvest scope states WHY it is absent — `projects:` is not "
          f"served by the element manifest, and it is never re-derived here")

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
    check(set(m) <= {"index", "slug", "gloss", "cite", "journey"},
          f"member {m.get('index')} carries only the recorded projection")

sys.exit(1 if fail else 0)
PYEOF

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll brief content-contract checks passed.\n'
