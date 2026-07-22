#!/usr/bin/env sh
# check-interview-journal.sh — verify the interview journal as the boundary
# diagnostic (Story 10.4). POSIX shell + stdlib Python.
#
# Covers: one entry per candidate question (AC1); an asked question records its
# survival rationale + grounding (when recommended) + owner disposition (AC2); a
# suppressed question records its covering fact-sheet entries (AC3); the failure
# of an answerable-but-asked question is attributable from the recorded fields
# (AC4); the journal is written to the run workspace by the SKILL; and the
# command fails closed on an asked question with no disposition.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# Build a real interview (triage) from harvest state: a covered audience question
# (suppressed), a warning re-raise (recommended), and open questions.
STATE='{"fact_sheet":[{"claim":"this guide is written for backend engineers"}],"needs_owner":[{"topic":"warning","candidate":"do not use on TPUs"}]}'
printf '%s' "$STATE" | python3 "$DP" interview --framework F3 > "$work/iv.json"

# Record dispositions for every ASKED question in the interview.
python3 - "$work" "$DP" <<'PY'
import json, subprocess, sys
work, dp = sys.argv[1], sys.argv[2]
iv = json.load(open(f"{work}/iv.json"))
records = []
for q in iv["questions"]:
    if q["outcome"] == "recommended":
        rec = subprocess.run([sys.executable, dp, "answer", "--id", q["id"],
                              "--disposition", "approved", "--text", "confirmed: do not use on TPUs",
                              "--pointer", "README.md:88@a1b2c3d"], capture_output=True, text=True)
    else:
        rec = subprocess.run([sys.executable, dp, "answer", "--id", q["id"],
                              "--disposition", "answered", "--text", "an owner-only answer"],
                             capture_output=True, text=True)
    records.append(json.loads(rec.stdout))
json.dump(records, open(f"{work}/answers.json", "w"))
PY

python3 "$DP" journal --interview "$work/iv.json" --answers "$work/answers.json" > "$work/journal.json"

# AC1 — one entry per candidate question (== the triage size).
tri=$(jget 'len(d["triage"])' < "$work/iv.json")
jn=$(jget 'len(d["journal"])' < "$work/journal.json")
[ "$tri" = "$jn" ] && ok "one journal entry per candidate question ($jn)" || err "journal size $jn != triage size $tri"

# AC2 — asked questions record rationale + disposition (+ grounding when recommended).
jget 'all("rationale" in e and "disposition" in e for e in d["journal"] if e["status"]=="asked")' < "$work/journal.json" \
  | grep -q True && ok "asked entries record survival rationale + disposition" || err "asked entry missing rationale/disposition"
jget 'all("grounding" in e for e in d["journal"] if e.get("outcome")=="recommended")' < "$work/journal.json" \
  | grep -q True && ok "recommended entries record grounding pointers" || err "recommended entry missing grounding"
jget 'any(e["status"]=="asked" and e["rationale"]=="needs-owner-reraise" for e in d["journal"])' < "$work/journal.json" \
  | grep -q True && ok "a re-raise records rationale=needs-owner-reraise" || err "re-raise rationale not journaled"

# AC3 — suppressed questions record their covering entries.
jget 'any(e["status"]=="suppressed" and e.get("covered_by") for e in d["journal"])' < "$work/journal.json" \
  | grep -q True && ok "suppressed entries record covering fact-sheet entries" || err "suppressed entry missing covered_by"

# AC4 — attributability: the suppressed audience question names WHAT covered it.
jget '[e["covered_by"] for e in d["journal"] if e["id"]=="q5"][0][0]' < "$work/journal.json" \
  | grep -qi 'backend engineers' && ok "a suppression is attributable to its covering entry" || err "suppression not attributable"

# Fail-closed: an asked question with no recorded disposition is rejected.
python3 "$DP" journal --interview "$work/iv.json" --answers /dev/null >/dev/null 2>&1 \
  && err "journal accepted an asked question with no disposition" || ok "fails closed on a missing disposition"

# SKILL writes the journal to the run workspace.
grep -q 'draft-pipeline.py journal' "$SKILL" && grep -q '\$WS/interview-journal.json' "$SKILL" \
  && ok "SKILL writes the journal to the run workspace" || err "SKILL does not write the journal to \$WS"

# --- Decision-level consulted influence (Story 13.37) -------------------------
# --seed-extra records a policy-shaped DECISION (article-type recommendation)
# in the same consulted: grammar; a malformed pair fails closed.
st='{"fact_sheet":[],"needs_owner":[]}'
ivout=$(printf '%s' "$st" | python3 "$DP" interview --framework F2 -)
ans=$(printf '%s' "$ivout" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([{'id': q['id'], 'disposition': 'skipped'} for q in d['questions']]))")
printf '%s' "$ivout" > "$work/iv.json"; printf '%s' "$ans" > "$work/ans.json"
jout=$(python3 "$DP" journal --interview "$work/iv.json" --answers "$work/ans.json" \
       --seed-extra 'LESSONS.md:12@abc1234=article-type')
printf '%s' "$jout" | python3 -c "
import json, sys
c = json.load(sys.stdin)['consulted']
assert c.startswith('consulted: product-lab@abc1234'), c
assert 'LESSONS.md:12 → article-type' in c, c
" && ok "journal --seed-extra records a decision-level policy influence" \
  || err "seed-extra influence missing from consulted:"
python3 "$DP" journal --interview "$work/iv.json" --answers "$work/ans.json" \
        --seed-extra 'not-a-pointer' >/dev/null 2>&1 \
  && err "malformed --seed-extra accepted" \
  || ok "malformed --seed-extra fails closed"

# F77: the unseeded --policy-note branch normalizes exactly like
# review-consulted — a caller pasting the whole rendered 'none (...)' phrase
# must not double-wrap to 'consulted: none (none (...))'.
jout=$(python3 "$DP" journal --interview "$work/iv.json" --answers "$work/ans.json" \
       --policy-note 'none (policy_source unavailable: gateway down)')
printf '%s' "$jout" | python3 -c "
import json, sys
c = json.load(sys.stdin)['consulted']
assert c == 'consulted: none (policy_source unavailable: gateway down)', c
" && ok "F77: journal pre-wrapped --policy-note is unwrapped, not double-wrapped" \
  || err "journal double-wrap not normalized"
# A bare reason still passes through unchanged (behavior pinned).
jout=$(python3 "$DP" journal --interview "$work/iv.json" --answers "$work/ans.json" \
       --policy-note 'policy_source unavailable: gateway down')
printf '%s' "$jout" | python3 -c "
import json, sys
c = json.load(sys.stdin)['consulted']
assert c == 'consulted: none (policy_source unavailable: gateway down)', c
" && ok "journal bare --policy-note reason carried unchanged" \
  || err "journal bare-reason behavior changed"

# --- Editorial anchor (Story 13.38, SPEC-policy-editorial-direction CAP-2) ----
# The first PRESENTED question with an owner-text answer becomes the anchor.
st='{"fact_sheet":[],"needs_owner":[]}'
ivout=$(printf '%s' "$st" | python3 "$DP" interview --framework F4 -)
printf '%s' "$ivout" > "$work/iv38.json"
# F4 presents q6 (opinion/claim) first; answer it with owner text.
printf '%s' "$ivout" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ans = [{'id': q['id'], 'disposition': 'skipped'} for q in d['questions']]
ans[0] = {'id': d['presentation_order'][0], 'disposition': 'answered',
          'text': 'reproducibility is the feature'}
print(json.dumps(ans))
" > "$work/ans38.json"
python3 "$DP" journal --interview "$work/iv38.json" --answers "$work/ans38.json" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
a = d['editorial_anchor']
assert a['id'] == d['presentation_order'][0], a
assert a['text'] == 'reproducibility is the feature', a
assert a['policy_seeded'] is False, a
" && ok "editorial anchor: first presented owner-text answer, text carried" \
  || err "editorial anchor missing or wrong"
# All-skipped run -> no anchor invented.
printf '%s' "$ivout" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(json.dumps([{'id': q['id'], 'disposition': 'skipped'} for q in d['questions']]))
" > "$work/ans38b.json"
python3 "$DP" journal --interview "$work/iv38.json" --answers "$work/ans38b.json" \
  | python3 -c "
import json, sys
assert 'editorial_anchor' not in json.load(sys.stdin)
" && ok "no owner text -> no editorial anchor invented" \
  || err "anchor invented on an all-skipped run"

# --- Anchor is never a gate item (Story 18.41, #545) -------------------------
# The mandated tier LEADS presentation (Story 18.40), so a naive "first
# answered" scan would record the CAP-7 reconciliation gate as the anchor —
# which is exactly what #545 shipped (`{id: rc1, text: ""}`). The anchor must
# skip mandated items and empty text, and pick the claim/angle answer.
python3 - "$work/iv38.json" "$work/iv41.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
rc = {"id": "rc1", "text": "config vs policy disagree", "topic": "other",
      "from_gap": False, "outcome": "open", "rationale": "policy-reconciliation"}
d["questions"] = [rc] + d["questions"]
d["presentation_order"] = ["rc1"] + d["presentation_order"]
d["mandated"] = ["rc1"]
json.dump(d, open(sys.argv[2], "w"))
PYEOF
# a) gate answered first + a real claim answer -> the CLAIM is the anchor.
python3 - "$work/iv41.json" "$work/ans41.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
ans = [{"id": q["id"], "disposition": "skipped"} for q in d["questions"]]
ans[0] = {"id": "rc1", "disposition": "answered", "text": "keep the recorded position"}
ans[1] = {"id": d["presentation_order"][1], "disposition": "answered",
          "text": "reproducibility is the feature"}
json.dump(ans, open(sys.argv[2], "w"))
PYEOF
python3 "$DP" journal --interview "$work/iv41.json" --answers "$work/ans41.json" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
a = d['editorial_anchor']
assert a['id'] != 'rc1', a
assert a['text'] == 'reproducibility is the feature', a
" && ok "anchor skips the mandated gate item and records the claim/angle answer (#545)" \
  || err "anchor was recorded as the gate item (#545 regression)"
# b) ONLY the gate answered -> no anchor, and the loss is NAMED not silent.
python3 - "$work/iv41.json" "$work/ans41b.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
ans = [{"id": q["id"], "disposition": "skipped"} for q in d["questions"]]
ans[0] = {"id": "rc1", "disposition": "answered", "text": "keep the recorded position"}
json.dump(ans, open(sys.argv[2], "w"))
PYEOF
python3 "$DP" journal --interview "$work/iv41.json" --answers "$work/ans41b.json" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'editorial_anchor' not in d, d.get('editorial_anchor')
assert d.get('editorial_anchor_rejected') == 'editorial-anchor-is-gate-item', d
" && ok "gate-only run: no anchor, rejection NAMED (editorial-anchor-is-gate-item)" \
  || err "gate-only anchor loss was silent or mis-named"
# c) an empty-text answer is not an anchor either (the #545 `text: ""` shape).
python3 - "$work/iv38.json" "$work/ans41c.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
ans = [{"id": q["id"], "disposition": "skipped"} for q in d["questions"]]
ans[0] = {"id": d["presentation_order"][0], "disposition": "answered", "text": "   "}
json.dump(ans, open(sys.argv[2], "w"))
PYEOF
python3 "$DP" journal --interview "$work/iv38.json" --answers "$work/ans41c.json" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'editorial_anchor' not in d, d.get('editorial_anchor')
assert d.get('editorial_anchor_rejected') == 'editorial-anchor-empty', d
" && ok "empty-text answer is not an anchor (editorial-anchor-empty)" \
  || err "empty-text anchor accepted"

# --- Offered-candidate provenance (Story 18.28, #515) ------------------------
# The answer record + journal entry carry which candidates were offered and
# which the owner took, and --events emits the calibration stream.
SKILL2="skills/draft-article/SKILL.md"
# a) answer record carries candidates + selection; selection grammar validated.
python3 "$DP" answer --id q1 --disposition approved --text "confirmed" \
  --pointer README.md:88@abc1234 \
  --candidates '[{"text":"do not use on TPUs","pointers":["README.md:88@abc1234"]},{"text":"avoid TPUs"}]' \
  --selection 'candidate:1' > "$work/a1.json"
jget 'd["selection"]=="candidate:1" and d["candidates"][0]["order"]==1 and d["candidates"][0]["text"]=="do not use on TPUs"' < "$work/a1.json" \
  | grep -q True && ok "answer record carries offered candidates + selection (18.28)" || err "answer candidates/selection not recorded"
# b) out-of-range / malformed selection fails closed.
python3 "$DP" answer --id q1 --disposition answered --text x --candidates '[{"text":"a"}]' --selection 'candidate:5' >/dev/null 2>&1 \
  && err "out-of-range candidate selection accepted" || ok "reject: selection out of range fails closed"
python3 "$DP" answer --id q1 --disposition answered --text x --selection 'bogus' >/dev/null 2>&1 \
  && err "malformed selection accepted" || ok "reject: malformed selection value fails closed"
# c) candidates offered without a selection fails closed (the choice must be recorded).
python3 "$DP" answer --id q1 --disposition answered --text x --candidates '[{"text":"a"}]' >/dev/null 2>&1 \
  && err "candidates without selection accepted" || ok "reject: candidates without selection fails closed"
# d) a non-tension answer omits both fields (additive / back-compat).
python3 "$DP" answer --id q1 --disposition answered --text "owner only" > "$work/a2.json"
jget '"candidates" not in d and "selection" not in d' < "$work/a2.json" | grep -q True \
  && ok "non-tension answer omits candidates/selection (additive)" || err "candidates/selection leaked onto a plain answer"
# e) the journal carries the provenance and --events emits the calibration stream.
STATE='{"fact_sheet":[],"needs_owner":[{"topic":"warning","candidate":"do not use on TPUs"}]}'
printf '%s' "$STATE" | python3 "$DP" interview --framework F3 > "$work/ivc.json"
python3 - "$work" "$DP" <<'PY'
import json, subprocess, sys
work, dp = sys.argv[1], sys.argv[2]
iv = json.load(open(f"{work}/ivc.json"))
recs = []
for i, q in enumerate(iv["questions"]):
    spec = {"id": q["id"], "disposition": "approved" if q["outcome"] == "recommended" else "answered",
            "text": "confirmed", "pointers": ["README.md:88@abc1234"] if q["outcome"] == "recommended" else None}
    if q["outcome"] == "recommended":
        spec["candidates"] = [{"text": "do not use on TPUs", "pointers": ["README.md:88@abc1234"]},
                              {"text": "avoid TPUs"}]
        spec["selection"] = "candidate:2+edited"
    r = subprocess.run([sys.executable, dp, "answer", "--batch", "-"], input=json.dumps([spec]),
                       capture_output=True, text=True)
    recs.extend(json.loads(r.stdout))
json.dump(recs, open(f"{work}/ansc.json", "w"))
PY
python3 "$DP" journal --interview "$work/ivc.json" --answers "$work/ansc.json" \
  --events "$work/iv-events.jsonl" > "$work/jc.json"
jget 'any(e.get("selection")=="candidate:2+edited" and e.get("candidates") for e in d["journal"] if e["status"]=="asked")' < "$work/jc.json" \
  | grep -q True && ok "journal entry carries candidates + selection provenance (18.28)" || err "journal missing candidate provenance"
[ -s "$work/iv-events.jsonl" ] \
  && python3 -c "import json,sys; e=[json.loads(l) for l in open(sys.argv[1])]; assert any(x['type']=='interview-selection' and x['selection']=='candidate:2+edited' and x['offered']==2 for x in e)" "$work/iv-events.jsonl" \
  && ok "--events emits an interview-selection calibration event per chosen candidate" || err "interview-selection events not emitted"
# f) documented in the SKILL.
grep -q 'candidates' "$SKILL2" && grep -q 'owner-authored' "$SKILL2" \
  && ok "draft-article SKILL documents candidate/selection provenance" || err "SKILL does not document 18.28 provenance"

if [ "$fail" -eq 0 ]; then
  printf '\nAll interview-journal checks passed.\n'; exit 0
else
  printf '\ninterview-journal checks FAILED.\n' >&2; exit 1
fi
