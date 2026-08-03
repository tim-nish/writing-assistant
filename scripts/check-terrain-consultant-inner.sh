#!/usr/bin/env sh
# parallel-safe
# tier: inner — consultant-contract assertions against a derived fixture map;
# covers: scripts/fixtures/terrain/screen-map.json scripts/topic-map-directions.py skills/terrain/SKILL.md skills/terrain/steps/brief.md skills/terrain/steps/brief-gates.md skills/terrain/steps/gap.md skills/terrain/steps/map.md skills/terrain/steps/screens.md
#   no seam, no corpus, no assembly. Measured 2026-07-30 at adoption: ~0.8s
#   (ceiling 2s).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-consultant-inner.sh — the brief gate's coherence consultant is
# bound by RULES, never by a procedure (Story 20.55, #939; SPEC-terrain CAP-3).
#
# WHAT THIS CHECK DELIBERATELY DOES NOT ASSERT: any fixed assessment
# procedure, any fixed set of narrative structures, any expected verdict. An
# instrument over the judgment itself is precisely what the story's design
# constraint forbids — the failure being avoided is a narrow mechanism that
# reports success for satisfying its own steps while failing what the owner
# wanted. What is asserted is the gate shape, the grounding rule, the honesty
# rule and the no-hiding rule: as contract text, and as observable properties
# of what the command emits.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/topic-map-directions.py"
SKILL=$(mktemp)
cat skills/terrain/SKILL.md skills/terrain/steps/map.md \
    skills/terrain/steps/screens.md skills/terrain/steps/brief.md \
    skills/terrain/steps/gap.md > "$SKILL"
# ^ story 20.64 (#962): the skill is now a dispatcher + step companions; checks
#   assert over the concatenation, whose order matches the pre-split file.
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$FIX" "$work" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); w = sys.argv[2]
strands = list(d.get("elements") or [])
for n in range(10):
    strands.append({
        "kind": "lesson", "slug": f"pool-{n:02d}", "title": f"Pool {n}",
        "topic": "engineering" if n % 2 else "people",
        "date": f"2026-07-{(n % 28) + 1:02d}",
        "gloss": f"A claim the material itself makes, number {n}",
        "situation": f"LESSONS.md:{n + 10}@abc1234",
        "evidence": [f"LESSONS.md:{n + 10}@abc1234"], "consumed": False,
    })
d["elements"] = strands
json.dump(d, open(w + "/map.json", "w"))
PYEOF

python3 "$D" candidates --map "$work/map.json" > "$work/cands.json"
python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
pin = json.load(open(w + "/map.json"))["coverage"]["pin"]
c = [x for x in json.load(open(w + "/cands.json"))["candidates"]
     if x["kind"] == "element"]
ids = [x["id"] for x in c[:3]]
json.dump({"index": ids, "note": "n", "pin": pin}, open(w + "/a-set.json", "w"))
json.dump({"index": ids[0], "note": "n", "pin": pin}, open(w + "/a-one.json", "w"))
json.dump({"free_text": "my own direction"}, open(w + "/a-free.json", "w"))
json.dump({"ids": ids}, open(w + "/expect.json", "w"))
PYEOF

for a in set one; do
  python3 "$D" brief --answer "$work/a-$a.json" --map "$work/map.json" \
    > "$work/b-$a.json" 2>"$work/b-$a.err" \
    || err "brief from a-$a failed: $(cat "$work/b-$a.err")"
done
python3 "$D" brief --answer "$work/a-free.json" --map "$work/map.json" \
  > "$work/b-free.json" 2>/dev/null

# --- the SKILL carries the four rules as contract text ----------------------
# Asserted as TEXT because the rules bind the composer, who reads the skill —
# the code can carry the pool and the declarations, but only the skill can
# bind the judgment that consumes them.
for token in 'coherence CONSULTANT' 'free-form override' \
             'cites served material at the pin' \
             'Incoherence and uncertainty are both stated' \
             'enumerate their candidates' 'never runs before a selection'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the consultant rule: $token" \
    || err "SKILL is missing the consultant rule: $token"
done
# The design constraint itself is contract text: freezing a procedure is the
# failure this capability is shaped to avoid, so the skill has to say so.
grep -q 'not a fixed procedure' "$SKILL" \
  && ok "the SKILL states that the assessment is deliberately unfrozen" \
  || err "SKILL does not state the no-fixed-procedure constraint (#939)"

# --- observable properties of what the command emits ------------------------
python3 - "$work" <<'PYEOF' || fail=1
import json, sys
w = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

ids = json.load(open(w + "/expect.json"))["ids"]
cands = {c["id"]: c for c in json.load(open(w + "/cands.json"))["candidates"]
         if c["kind"] == "element"}
s = json.load(open(w + "/b-set.json"))
con = s.get("consultant") or {}

# AC1 — the gate shape. Nothing here is adopted; the brief is composed from the
# owner's own selection, and the consultant's output is proposal-only.
rules = " ".join(con.get("rules") or [])
check(len(con.get("rules") or []) == 4, "the four binding rules are carried")
for phrase in ("nothing is adopted silently", "free-form override",
               "cites served material at the pin", "outside the served corpus",
               "incoherence and uncertainty are both stated",
               "enumerate their candidates", "never ranks"):
    check(phrase in rules, f"the binding rules state: {phrase!r}")

# AC2 — grounding is OBSERVABLE, not just asserted: every Strand the consultant
# can name arrives with its served cite and the pin those cites are read at.
check(con.get("pin") == s["pin"],
      "the consultant's material is pinned to the selection's own pin")
subject = con.get("subject") or []
check([m["index"] for m in subject] == ids,
      "the subject is exactly the owner's selected set")
check(all(m.get("cite") for m in subject),
      "every subject member carries a citation")
pool = con.get("substitution_candidates") or []
check(all(m.get("cite") for m in pool),
      "every substitution candidate carries a citation")
in_corpus = set(cands)
check(all(m["index"] in in_corpus for m in pool),
      "no candidate comes from outside the served corpus at this pin")

# AC4 — no hiding. The pool is COMPLETE: every unselected Strand at this pin is
# offered. A trimmed pool is the narrowing the second-proposer boundary bars,
# and it is what makes adding unselected material admissible at all.
expected = sorted(set(cands) - set(ids))
check(sorted(m["index"] for m in pool) == expected,
      f"the pool enumerates EVERY unselected Strand ({len(pool)} of {len(expected)})")
check(con.get("ranked") is False,
      "the pool declares itself unranked — order is the map's, never a ranking")
check(len(pool) > 1, "more than one candidate is offered — never a single best swap")

# AC5 — it never runs upstream of a selection.
one = json.load(open(w + "/b-one.json"))
check("consultant" not in one,
      "a single Strand carries no consultant — it cannot fail to cohere with itself")
free = json.load(open(w + "/b-free.json"))
check("consultant" not in free,
      "free-form wording with no selection carries no consultant")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- the absence assertion: no fixed procedure was smuggled in --------------
# A named narrative-structure vocabulary in the consultant path would be the
# instrument-over-judgment this story forbids, so it is grep-asserted absent
# the way the terrain area's other absences are.
if grep -nE 'CONSULTANT_(STRUCTURES|PROCEDURE|STEPS)|assessment_steps' "$D" \
     >/dev/null; then
  err "a fixed assessment procedure was added to the consultant path (#939)"
else
  ok "no fixed assessment procedure or structure vocabulary in the code"
fi

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
