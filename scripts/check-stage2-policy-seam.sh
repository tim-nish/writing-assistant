#!/usr/bin/env sh
# check-stage2-policy-seam.sh — verify the Stage-2 policy-seam integration
# (Story 14.4, SPEC-policy-source-seam FR45/FR47/FR48, CAP-2).
# POSIX shell + stdlib Python only.
#
# Covers: validated policy items join the asked set as open/policy-seed
# questions carrying their seed (never a recommendation — SPEC-policy-source-seam CAP-2); ordering is
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
    assert "grounding" not in q, "SPEC-policy-source-seam CAP-2: a seeded question must not carry a recommendation"
# SELECTION priority (rec > seed > open under the cap) is unchanged: every
# recommended question survives alongside the seeds. PRESENTATION (Story
# 13.30, SPEC-draft-article-ux CAP-4) now leads with the policy-seeded
# tension question — the claim/angle slot — so the array is display-ordered.
assert any(q["outcome"] == "recommended" for q in qs), \
    "recommended question lost under the cap"
assert qs[0].get("rationale") == "policy-seed", \
    "presentation must lead with the policy-seeded claim/angle question"
assert d["presentation_order"] == [q["id"] for q in qs], d.get("presentation_order")
# Story 18.40/18.42: the <=5 cap governs the CAPPED pool; mandated/gate
# items (reconciliation, depth offer) ride outside it.
assert d["asked"] <= 5, (d["asked"], len(qs))
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
    --items "$work/many-items.json" - | python3 -c "import json,sys; print(json.load(sys.stdin)['asked'])")
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
grep -q 'questions only' "$SKILL" && ok "SKILL: SPEC-policy-source-seam CAP-2 — policy supplies questions only" \
  || err "SKILL missing the questions-only boundary"

# --- 6. #299 — tension items are authored against the WHOLE consulted surface ------
grep -qi 'consulted surface as a whole, never a single line' "$SKILL" \
  && ok "SKILL: tension items are authored against the whole consulted surface" \
  || err "SKILL missing the whole-surface authoring rule (#299)"
grep -qi 'companion line that already resolves it' "$SKILL" \
  && grep -qi 'raise the item at all' "$SKILL" \
  && grep -qi 'with the resolving line' "$SKILL" \
  && ok "SKILL: a same-surface companion means don't raise, or raise with the resolver" \
  || err "SKILL missing the companion-resolution rule (#299)"
grep -qi 'harvest is evidence' "$SKILL" && grep -qi 'interview is the judgment gate' "$SKILL" \
  && ok "SKILL: harvest=evidence assembly vs interview=judgment gate stated where items are authored" \
  || err "SKILL missing the assembly-vs-judgment discriminator (#299)"
grep -qi 'manufactured tension' "$SKILL" \
  && ok "SKILL: names the manufactured-tension cost (an owner slot on settled ground)" \
  || err "SKILL missing the manufactured-tension rationale"
grep -qi 'whole-surface authoring' "specs/spec-policy-source-seam/SPEC.md" \
  && ok "seam SPEC: whole-surface authoring is contract (CAP-3)" \
  || err "seam SPEC missing the whole-surface authoring rule"
grep -q 'companion' "specs/spec-policy-source-seam/seam-formats.md" \
  && ok "seam-formats: seed.companion documented" || err "seam-formats missing seed.companion"

# --- 6b. #302 — one slot is RESERVED for a policy tension item -------------------
# Reproduces the run that found the defect: 6 confirmed NEEDS-OWNER gaps + 3
# valid tension items. Priority alone fills the cap with gaps and emits zero
# tension questions, silently corrupting the anchor and emptying contribute-back.
python3 - "$work/starve-state.json" "$work/starve-items.json" <<'PYEOF'
import json, sys
topics = ["audience", "surprise", "significance", "tradeoff", "warning", "motivation"]
state = {"stage": "consume",
         "fact_sheet": [{"kind": "number", "claim": "the bench recorded a 2x drop"}],
         "needs_owner": [{"topic": t, "candidate": f"owner input on {t}",
                          "reason": "owner's opinion"} for t in topics]}
sha = "8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"
seeds = [("contradiction", "rejected as generate-then-filter",
          "Your pipeline assembles many facts before any prose exists — where does the judgment gate sit relative to the pattern you declined?"),
         ("reversal-candidate", "prose generation demoted to non-goal",
          "That non-goal predates the readability rubric — does it still hold now that drafting gates prose on it?"),
         ("ambiguity", "lessons first",
          "When a lesson and a topic line disagree about emphasis, which governs the article's claim?")]
items = [{"id": f"t{i}", "gap_type": gt,
          "seed": {"quote": q, "pointer": f"topics/articles.md:{30+i}@{sha}"},
          "question": qq, "owner_answer": ""}
         for i, (gt, q, qq) in enumerate(seeds, 1)]
json.dump(state, open(sys.argv[1], "w")); json.dump(items, open(sys.argv[2], "w"))
PYEOF
python3 "$PIPE" interview --framework F2 --items "$work/starve-items.json" \
  "$work/starve-state.json" > "$work/starve-out.json"
python3 - "$work/starve-out.json" <<'PYEOF' && ok "6 gaps + 3 tensions: 5 asked, exactly 1 tension survives (reserved slot)" || err "#302 reserved slot: tension starved or cap broken"
import json, sys
d = json.load(open(sys.argv[1]))
qs = d["questions"]
seeded = [q for q in qs if q.get("rationale") == "policy-seed"]
gaps = [q for q in qs if q.get("from_gap")]
assert d["asked"] == 5, f'cap broken: {d["asked"]} asked'
assert len(seeded) == 1, f"expected exactly 1 tension question, got {len(seeded)}"
assert len(gaps) == 4, f"expected 4 gap questions alongside it, got {len(gaps)}"
assert seeded[0]["id"] == "t1", f"reserved slot took {seeded[0]['id']}, not the highest-priority t1"
PYEOF

# No tension items → no reservation, no residue: selection is exactly as before.
python3 "$PIPE" interview --framework F2 "$work/starve-state.json" > "$work/nores.json"
python3 - "$work/nores.json" <<'PYEOF' && ok "no tension items: 5 gaps asked, no slot held open (no reservation residue)" || err "#302: reservation left residue on an unseeded run"
import json, sys
d = json.load(open(sys.argv[1]))
qs = d["questions"]
assert d["asked"] == 5, f'expected a full 5 gap questions, got {d["asked"]}'
assert not [q for q in qs if q.get("rationale") == "policy-seed"], "phantom seed"
PYEOF

# --- 7. #306 — a seed older than the material it contradicts is STALE, not live ----
grep -qi 'Stale seed, not a live tension' "$SKILL" \
  && ok "SKILL: staleness is distinguished from a live tension" \
  || err "SKILL missing the stale-seed rule (#306)"
grep -qi 'confirm or update' "$SKILL" \
  && grep -qi 'reversal-candidate' "$SKILL" \
  && ok "SKILL: a stale seed routes to reversal-candidate, asking confirm-or-update" \
  || err "SKILL missing the staleness routing (#306)"
grep -qi 'updated:' "$SKILL" && grep -qi "state:" "$SKILL" \
  && ok "SKILL: staleness is decided from inputs the run already holds" \
  || err "SKILL missing the existing-inputs rule (#306)"
grep -qi 'proposes an update, not a resolution' "$SKILL" \
  && ok "SKILL: a staleness answer stages a policy-update proposal, not a resolution" \
  || err "SKILL missing the staging framing for staleness (#306)"
grep -qi 'staleness routing' "specs/spec-policy-source-seam/SPEC.md" \
  && ok "seam SPEC: staleness routing is contract (CAP-3)" \
  || err "seam SPEC missing the staleness-routing rule"
grep -qi 'one slot reserved for policy tension' "$SKILL" \
  && ok "SKILL: the reserved tension slot is documented (#302)" \
  || err "SKILL missing the reserved-slot rule"
grep -qi 'one slot is reserved' "specs/spec-article-draft-pipeline/SPEC.md" \
  && ok "pipeline SPEC: the reserved slot is contract (CAP-2)" \
  || err "pipeline SPEC missing the reserved-slot amendment"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-2 policy-seam checks passed.\n'; exit 0
else
  printf '\nstage-2 policy-seam checks FAILED.\n' >&2; exit 1
fi
