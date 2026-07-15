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

if [ "$fail" -eq 0 ]; then
  printf '\nAll interview-journal checks passed.\n'; exit 0
else
  printf '\ninterview-journal checks FAILED.\n' >&2; exit 1
fi
