#!/usr/bin/env sh
# check-stage2-policy-seam.sh — verify the Stage-2 policy-seam integration
# (Story 14.4, SPEC-policy-source-seam FR45/FR47/FR48, NFR15).
# POSIX shell + stdlib Python only.
#
# Covers: validated policy items join the asked set as open/policy-seed
# questions carrying their seed (never a recommendation — NFR15); ordering is
# recommended > policy-seed > open and the ≤5 cap holds; the journal records
# the seed<- field parallel to rec<- groundings; the journal ends with the
# consulted: line in all three modes (seeded map / unset / unavailable via
# --policy-note); and the SKILL documents the probe's degradation contract
# (one line, then generic — no exit code aborts the run).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

PIPE="scripts/draft-pipeline.py"
FIX="scripts/fixtures/interview-items"
SKILL="skills/draft-article/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# A state with one NEEDS-OWNER gap (=> a recommended question) and no coverage.
state='{"stage":"consume","fact_sheet":[],
        "needs_owner":[{"topic":"significance","candidate":"the 40% cut is the headline","reason":"unsourced"}]}'

# --- 1. Seeded items join the asked set, with their seed, without a recommendation
printf '%s' "$state" | python3 "$PIPE" interview --framework F1 \
      --items "$FIX/valid.json" - > "$work/seeded.json"
python3 - "$work/seeded.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
qs = d["questions"]
seeded = [q for q in qs if q.get("rationale") == "policy-seed"]
assert seeded, "no policy-seeded question in the asked set"
for q in seeded:
    assert q["outcome"] == "open", q
    assert "seed" in q and q["seed"]["pointer"], q
    assert "grounding" not in q, "NFR15: a seeded question must not carry a recommendation"
# ordering: recommended first, then policy-seed, then generic open
kinds = ["rec" if q["outcome"] == "recommended" else
         "seed" if q["rationale"] == "policy-seed" else "open" for q in qs]
order = {"rec": 0, "seed": 1, "open": 2}
assert kinds == sorted(kinds, key=order.get), kinds
assert len(qs) <= 5, len(qs)
PYEOF
[ $? -eq 0 ] && ok "seeded items: asked, open, seed carried, no recommendation, rec>seed>open order, cap holds" \
  || err "seeded-item fold-in failed"

# --- 2. Cap still holds with many seeded items ---------------------------------
python3 - "$work/many-items.json" <<'PYEOF'
import json, sys
sha = "8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"
items = [{"id": f"t{i}", "gap_type": "ambiguity",
          "seed": {"quote": f"position line {i} about run budgets",
                   "pointer": f"LESSONS.md:{i+1}@{sha}"},
          "question": f"Where do you draw the boundary for case {i} between the run budget rule and the wall-clock exemption?",
          "owner_answer": ""} for i in range(7)]
json.dump(items, open(sys.argv[1], "w"))
PYEOF
n=$(printf '%s' "$state" | python3 "$PIPE" interview --framework F1 \
    --items "$work/many-items.json" - | python3 -c "import json,sys; print(len(json.load(sys.stdin)['questions']))")
[ "$n" -le 5 ] && ok "7 seeded items: asked set capped at $n (≤5)" || err "cap broken: $n asked"

# --- 3. Journal: seed<- field + consulted: mapping under one pin -----------------
printf '%s' "$state" | python3 "$PIPE" interview --framework F1 \
  --items "$FIX/valid.json" - > "$work/interview.json"
python3 - "$work/interview.json" "$work/answers.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
answers = [{"id": q["id"], "disposition": "skipped"} for q in d["questions"]]
json.dump(answers, open(sys.argv[2], "w"))
PYEOF
python3 "$PIPE" journal --interview "$work/interview.json" \
  --answers "$work/answers.json" > "$work/journal.json"
python3 - "$work/journal.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
seeded = [e for e in d["journal"] if e.get("seed")]
assert seeded, "no journal entry carries a seed field"
for e in seeded:
    assert e["rationale"] == "policy-seed" and e["seed"][0], e
c = d["consulted"]
assert c.startswith("consulted: product-lab@"), c
for e in seeded:
    ptr = e["seed"][0].rsplit("@", 1)[0]
    assert f"{ptr} → {e['id']}" in c, (ptr, c)
assert c.count("@") >= 1 and c.split("—")[0].count("@") == 1, "pin stated once in the header"
PYEOF
[ $? -eq 0 ] && ok "journal: seed<- recorded; consulted: maps every seed to its question under the pin" \
  || err "journal seed/consulted failed"

# --- 4. consulted: none — unset vs unavailable -----------------------------------
printf '%s' "$state" | python3 "$PIPE" interview --framework F1 - > "$work/generic.json"
python3 - "$work/generic.json" "$work/ganswers.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
json.dump([{"id": q["id"], "disposition": "skipped"} for q in d["questions"]],
          open(sys.argv[2], "w"))
PYEOF
c=$(python3 "$PIPE" journal --interview "$work/generic.json" --answers "$work/ganswers.json" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['consulted'])")
[ "$c" = "consulted: none (policy_source unset)" ] && ok "generic run: consulted: none (unset)" \
  || err "unset consulted line: '$c'"
c=$(python3 "$PIPE" journal --interview "$work/generic.json" --answers "$work/ganswers.json" \
    --policy-note "policy_source unavailable: path does not exist" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['consulted'])")
[ "$c" = "consulted: none (policy_source unavailable: path does not exist)" ] \
  && ok "degraded run: consulted: none carries the unavailable reason" \
  || err "unavailable consulted line: '$c'"

# --- 5. The SKILL documents the probe + degradation contract ----------------------
grep -q 'read-policy-source.py' "$SKILL" && ok "SKILL: stage 2 probes the policy source" \
  || err "SKILL missing the reader probe"
grep -q 'no exit code here may abort the run' "$SKILL" && grep -q 'relay that one line once' "$SKILL" \
  && ok "SKILL: degradation is one relayed line, then generic — never an abort" \
  || err "SKILL missing the one-line degradation contract"
grep -q -- '--policy-note' "$SKILL" && ok "SKILL: journal records why a run was not seeded" \
  || err "SKILL missing --policy-note wiring"
grep -q 'questions only' "$SKILL" && ok "SKILL: NFR15 — policy supplies questions only" \
  || err "SKILL missing the questions-only boundary"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-2 policy-seam checks passed.\n'; exit 0
else
  printf '\nstage-2 policy-seam checks FAILED.\n' >&2; exit 1
fi
