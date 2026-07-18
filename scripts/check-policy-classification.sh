#!/usr/bin/env sh
# check-policy-classification.sh — verify CAP-7 policy-result classification
# (Story 13.75, SPEC-policy-source-seam CAP-7 added 2026-07-18, umbrella #365;
# seam-formats.md §2 reconciliation item). POSIX shell + stdlib Python only.
#
# Covers: the 2026-07-18 EN-topology REPLAY (served records-only line vs
# `syndication.policy.en.mode: canonical` → exactly one `conflict`
# reconciliation item, the original tension item superseded, no ordinary
# candidate carries the records-only position); the owner-judgment structural
# exemption (an `opinion` item passes through `open` untouched even when its
# text matches a conflict subject); the emitted reconciliation item validates
# against the extended schema; determined/constrained are structurally present
# and empty-by-default; no conflict → pure pass-through; reconciliation items
# ride the interview's tension-priority path (reserved slot, presentation
# lead); the journal records positions; an answered reconciliation emits a
# config↔policy reconciliation staging-candidate block; and the SKILL states
# the CAP-7 contracts.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

PIPE="scripts/draft-pipeline.py"
VAL="scripts/validate-interview-items.py"
FIX="scripts/fixtures/policy-classification"
SKILL="skills/draft-article/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 -c "import py_compile; py_compile.compile('$root/$PIPE', doraise=True)" 2>/dev/null \
  && ok "pipeline compiles" || { err "pipeline syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# --- 1. The 2026-07-18 EN-topology replay ---------------------------------------
# Fixture surface serves the records-only line at a pinned cite; fixture config
# declares syndication.policy.en.mode: canonical; the candidate items carry the
# regression's t1 tension on that exact line.
python3 "$PIPE" classify-policy --surface "$FIX/surface.txt" \
  --config-json "$FIX/config.json" --items "$FIX/items.json" \
  --config-version cfgv1 > "$work/classified.json" \
  || err "classify-policy failed on the replay fixtures"
python3 - "$work/classified.json" <<'PYEOF' \
  && ok "EN replay: exactly one conflict reconciliation item, both positions pinned" \
  || err "EN replay: reconciliation item wrong"
import json, sys
d = json.load(open(sys.argv[1]))
recs = d["reconciliation_items"]
assert len(recs) == 1, f"expected exactly 1 reconciliation item, got {len(recs)}"
rc = recs[0]
assert rc["gap_type"] == "reconciliation" and rc["owner_answer"] == "", rc
auth = {p["authority"]: p for p in rc["positions"]}
assert set(auth) == {"policy", "config"}, auth
assert auth["policy"]["pointer"].startswith("topics/articles.md:17@"), auth["policy"]
assert "reference records only" in auth["policy"]["quote"], auth["policy"]
assert auth["config"]["pointer"] == "syndication.policy.en.mode@cfgv1", auth["config"]
assert "canonical" in auth["config"]["quote"], auth["config"]
PYEOF
python3 - "$work/classified.json" <<'PYEOF' \
  && ok "EN replay: original tension superseded; no ordinary candidate carries the records-only position" \
  || err "EN replay: supersession/pass-through wrong (R9 classifier half)"
import json, sys
d = json.load(open(sys.argv[1]))
by_id = {c["id"]: c for c in d["classified"]}
assert by_id["t1"]["class"] == "conflict", by_id["t1"]
assert by_id["t1"]["superseded_by_reconciliation"] == d["reconciliation_items"][0]["id"]
# The pass-through set for `interview` must not smuggle the conflict back in:
# no ordinary item quotes the records-only position or points at its line.
for item in d["interview_items"]:
    if item["gap_type"] == "reconciliation":
        continue
    seed = item.get("seed") or {}
    if item["gap_type"] not in ("opinion", "significance", "surprise", "tradeoff",
                                "warning", "audience", "motivation", "retrospective"):
        assert "reference records only" not in str(seed.get("quote", "")), item
        assert not str(seed.get("pointer", "")).startswith("topics/articles.md:17@"), item
assert not any(c["id"] == "t1" for c in d["classified"] if c["class"] == "open")
assert "t1" not in [i["id"] for i in d["interview_items"]], "superseded item passed through"
assert "t2" in [i["id"] for i in d["interview_items"]], "unrelated tension lost"
PYEOF

# --- 2. Owner-judgment structural exemption --------------------------------------
python3 - "$work/classified.json" "$FIX/items.json" <<'PYEOF' \
  && ok "judgment exemption: the opinion item is open and byte-identical despite matching the conflict subject" \
  || err "judgment exemption broken (judgment was pre-decided or filtered)"
import json, sys
d = json.load(open(sys.argv[1]))
originals = {i["id"]: i for i in json.load(open(sys.argv[2]))}
c = next(c for c in d["classified"] if c["id"] == "q6")
assert c["class"] == "open" and c.get("exemption") == "owner-judgment", c
assert c["item"] == originals["q6"], "judgment item was modified in passing"
assert originals["q6"] in d["interview_items"], "judgment item filtered out"
PYEOF

# --- 3. determined/constrained: structurally present, empty-by-default ----------
python3 - "$work/classified.json" <<'PYEOF' \
  && ok "determined/constrained present and empty (the subject table is the extension point)" \
  || err "determined/constrained shape wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["determined"] == [] and d["constrained"] == [], (d["determined"], d["constrained"])
assert d["journal_records"], "conflict left no journal record"
assert any(r.get("class") == "conflict" for r in d["journal_records"])
PYEOF

# --- 4. The emitted reconciliation item passes the extended validator -----------
python3 - "$work/classified.json" <<'PYEOF' > "$work/rc-items.json"
import json, sys
json.dump(json.load(open(sys.argv[1]))["reconciliation_items"], sys.stdout)
PYEOF
set +e; out=$(python3 "$VAL" "$work/rc-items.json" 2>&1); rc=$?; set -e
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "emitted reconciliation item validates (R8/R9 clean)" \
  || err "emitted reconciliation item failed validation: $out"

# --- 5. No conflict → pure pass-through, no reconciliation residue ---------------
printf '{"syndication": {"policy": {"en": {"mode": "source", "variants": []}}}}' \
  > "$work/no-conflict-config.json"
python3 "$PIPE" classify-policy --surface "$FIX/surface.txt" \
  --config-json "$work/no-conflict-config.json" --items "$FIX/items.json" \
  > "$work/no-conflict.json" || err "classify-policy failed without a conflict"
python3 - "$work/no-conflict.json" "$FIX/items.json" <<'PYEOF' \
  && ok "no conflict (config not canonical): every item open, zero reconciliation items" \
  || err "no-conflict run left residue"
import json, sys
d = json.load(open(sys.argv[1]))
items = json.load(open(sys.argv[2]))
assert d["reconciliation_items"] == [], d["reconciliation_items"]
assert all(c["class"] == "open" for c in d["classified"]), d["classified"]
assert d["interview_items"] == items, "pass-through changed the items"
PYEOF

# --- 6. --config-version default is a sha256 prefix of the resolved config -------
v=$(python3 "$PIPE" classify-policy --surface "$FIX/surface.txt" \
    --config-json "$FIX/config.json" --items "$FIX/items.json" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['config_version'])")
python3 - "$v" "$FIX/config.json" <<'PYEOF' \
  && ok "default configVersion = sha256 prefix of the resolved config JSON ($v)" \
  || err "default configVersion wrong: $v"
import hashlib, json, sys
cfg = json.load(open(sys.argv[2]))
want = hashlib.sha256(json.dumps(cfg, sort_keys=True).encode()).hexdigest()[:12]
assert sys.argv[1] == want, (sys.argv[1], want)
PYEOF

# --- 7. Interview: reconciliation items ride the tension-priority path -----------
python3 - "$work/classified.json" <<'PYEOF' > "$work/interview-items.json"
import json, sys
json.dump(json.load(open(sys.argv[1]))["interview_items"], sys.stdout)
PYEOF
printf '{"stage":"consume","fact_sheet":[],"needs_owner":[]}' \
  | python3 "$PIPE" interview --framework F1 --items "$work/interview-items.json" - \
  > "$work/interview.json"
python3 - "$work/interview.json" <<'PYEOF' \
  && ok "interview: reconciliation asked with positions, leads presentation, ≤5 cap holds" \
  || err "interview fold-in of the reconciliation item failed"
import json, sys
d = json.load(open(sys.argv[1]))
qs = d["questions"]
rcs = [q for q in qs if q.get("rationale") == "policy-reconciliation"]
assert len(rcs) == 1, rcs
assert rcs[0]["outcome"] == "open" and len(rcs[0]["positions"]) == 2, rcs[0]
assert qs[0]["id"] == rcs[0]["id"], "reconciliation must lead (claim/angle slot)"
assert len(qs) <= 5, len(qs)
PYEOF

# Reserved slot (#302): 6 confirmed gaps + 1 reconciliation item → the
# reconciliation question is guaranteed a slot, exactly like a tension item.
python3 - "$work/starve-state.json" <<'PYEOF'
import json, sys
topics = ["audience", "surprise", "significance", "tradeoff", "warning", "motivation"]
json.dump({"stage": "consume",
           "fact_sheet": [{"kind": "number", "claim": "the bench recorded a 2x drop"}],
           "needs_owner": [{"topic": t, "candidate": f"owner input on {t}",
                            "reason": "owner's opinion"} for t in topics]},
          open(sys.argv[1], "w"))
PYEOF
python3 "$PIPE" interview --framework F2 --items "$work/rc-items.json" \
  "$work/starve-state.json" > "$work/starved.json"
python3 - "$work/starved.json" <<'PYEOF' \
  && ok "reserved slot: 6 gaps + 1 reconciliation → 5 asked, the reconciliation survives" \
  || err "reconciliation starved out of the reserved slot"
import json, sys
d = json.load(open(sys.argv[1]))
qs = d["questions"]
assert len(qs) == 5, len(qs)
assert sum(1 for q in qs if q.get("rationale") == "policy-reconciliation") == 1, qs
PYEOF

# --- 8. Journal records the positions; consulted: maps the policy side ----------
python3 - "$work/interview.json" "$work/answers.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
answers = []
for q in d["questions"]:
    if q.get("rationale") == "policy-reconciliation":
        answers.append({"id": q["id"], "disposition": "answered",
                        "text": "Config governs: EN is canonical on the site; "
                                "propose updating the records-only line."})
    else:
        answers.append({"id": q["id"], "disposition": "skipped"})
json.dump(answers, open(sys.argv[2], "w"))
PYEOF
python3 "$PIPE" journal --interview "$work/interview.json" \
  --answers "$work/answers.json" > "$work/journal.json"
python3 - "$work/journal.json" <<'PYEOF' \
  && ok "journal: reconciliation entry carries authority+pointer positions; consulted: maps the served line" \
  || err "journal positions/consulted wrong"
import json, sys
d = json.load(open(sys.argv[1]))
e = next(e for e in d["journal"] if e.get("positions"))
assert e["status"] == "asked" and e["rationale"] == "policy-reconciliation", e
auth = {p["authority"] for p in e["positions"]}
assert auth == {"policy", "config"}, auth
assert all(p["pointer"] for p in e["positions"]), e
assert f"topics/articles.md:17 → {e['id']}" in d["consulted"], d["consulted"]
PYEOF

# --- 9. Answered reconciliation → config↔policy reconciliation staging block -----
python3 "$PIPE" staging-candidates --interview "$work/interview.json" \
  --answers "$work/answers.json" --source-repo demo-repo --created 2026-07-18 \
  > "$work/staging.md"
grep -q '<!-- staging-candidate -->' "$work/staging.md" \
  && grep -q 'Config↔policy reconciliation decision' "$work/staging.md" \
  && grep -q 'config-policy-reconciliation' "$work/staging.md" \
  && grep -q 'syndication.policy.en.mode@' "$work/staging.md" \
  && grep -q 'topics/articles.md:17@' "$work/staging.md" \
  && ok "answered reconciliation emits a staging block framed as the config↔policy decision, both positions cited" \
  || err "reconciliation staging-candidate block wrong: $(cat "$work/staging.md")"
# A skipped reconciliation proposes nothing.
python3 - "$work/interview.json" "$work/skip-answers.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
json.dump([{"id": q["id"], "disposition": "skipped"} for q in d["questions"]],
          open(sys.argv[2], "w"))
PYEOF
out=$(python3 "$PIPE" staging-candidates --interview "$work/interview.json" \
      --answers "$work/skip-answers.json" --source-repo demo-repo --created 2026-07-18)
[ -z "$out" ] && ok "skipped reconciliation emits no block" \
  || err "skip emitted a block: $out"

# --- 10. The SKILL states the CAP-7 contracts ------------------------------------
grep -q 'classify-policy' "$SKILL" \
  && ok "SKILL: Stage 2 runs classify-policy between the policy read and interview" \
  || err "SKILL missing the classify-policy step"
grep -qi 'only as the emitted reconciliation' "$SKILL" \
  && ok "SKILL: a conflict subject is presented only as the reconciliation question (contract)" \
  || err "SKILL missing the conflict-presentation contract"
grep -qi 'never pre-decided' "$SKILL" && grep -qi 'structural exemption' "$SKILL" \
  && ok "SKILL: judgment classes are never pre-decided (structural exemption stated)" \
  || err "SKILL missing the judgment exemption"
grep -qi 'never treated as current policy' "$SKILL" \
  && ok "SKILL: an owner reversal routes to staging, never current policy for later stages" \
  || err "SKILL missing the reversal-to-staging contract"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-classification checks passed.\n'; exit 0
else
  printf '\npolicy-classification checks FAILED.\n' >&2; exit 1
fi
