#!/usr/bin/env sh
# check-one-structure-gate.sh — verify Story 18.46 (#559, SPEC-article-draft-
# pipeline CAP-9 #554 + CAP-3/CAP-4 `arc`; SPEC-policy-editorial-direction
# CAP-2): widening the structure proposer's input (Story 18.45) grows NEITHER a
# second gate NOR a second recording location. The brief-informed candidates use
# the shipped CAP-4 gate, and the choice lands in the argument plan's `arc` —
# never in `editorial_anchor`, which carries the claim/angle answer only.
# POSIX shell + stdlib Python only.

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

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

plan() {   # $1 = arc value
  printf -- '---\nkind: article-plan\nslug: s\nintent: F2\nclaim: c\nstatus: outlined\nrun_id: r\npin: repo@abc1234\narc: %s\n---\n\nbody\n' "$1"
}
plan 'thematic-braid — the clusters share cost, braided into one piece' > "$work/plan.md"
plan 'a movement with no structure named' > "$work/plan-nochoice.md"
printf '{"editorial_anchor":{"id":"q2","text":"the judge missed the retry storm","policy_seeded":false}}' > "$work/journal.json"

# --- 1. conforming run: the choice is in `arc`, the anchor is clean ------------
python3 "$DP" structure-record --plan "$work/plan.md" --journal "$work/journal.json" \
  --expect-choice > "$work/out.json" 2>/dev/null \
  && ok "a conforming run passes: the structure is recorded in the plan's arc" \
  || err "conforming run rejected"
python3 - "$work/out.json" <<'PYEOF' && ok "the guard reports the ONE recording location (arc) and the chosen structure" || err "guard payload wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["structure"] == "thematic-braid", d
assert d["recorded_in"] == "arc", d
assert d["editorial_anchor_clean"] is True, d
PYEOF

# --- 2. the structure choice must NEVER ride editorial_anchor -----------------
printf '{"editorial_anchor":{"id":"q2","text":"go with the thematic-braid shape"}}' > "$work/leak.json"
python3 "$DP" structure-record --plan "$work/plan.md" --journal "$work/leak.json" \
  > /dev/null 2>"$work/e1" \
  && err "a structure choice recorded in editorial_anchor.text was accepted" \
  || ok "a structure choice in editorial_anchor.text is REFUSED (the anchor carries the claim/angle answer only)"
grep -qi 'claim/angle answer only' "$work/e1" \
  && ok "the refusal names the CAP-2 anchor rule, not a generic error" \
  || err "refusal message does not name the anchor rule"

printf '{"editorial_anchor":{"id":"q2","text":"a real claim","structure":"thematic-braid"}}' > "$work/leak2.json"
python3 "$DP" structure-record --plan "$work/plan.md" --journal "$work/leak2.json" \
  > /dev/null 2>"$work/e2" \
  && err "a structure-shaped key on editorial_anchor was accepted" \
  || ok "a second recording location (a structure key on editorial_anchor) is REFUSED"
grep -qi 'second recording location' "$work/e2" \
  && ok "the refusal names the second-store failure explicitly" \
  || err "refusal does not name the second-store failure"

# --- 3. a choice that was made but never recorded is a defect -----------------
python3 "$DP" structure-record --plan "$work/plan-nochoice.md" --journal "$work/journal.json" \
  --expect-choice > /dev/null 2>"$work/e3" \
  && err "a made-but-unrecorded structure choice was accepted" \
  || ok "a structure choice the plan's arc does not name is REFUSED"

# --- 4. no choice -> the shipped default still applies, the run never blocks ---
python3 "$DP" structure-record --plan "$work/plan-nochoice.md" --journal "$work/journal.json" \
  > "$work/nc.json" 2>/dev/null \
  && ok "no choice: the guard passes — the run never blocks on the question" \
  || err "the guard blocked a run that made no structure choice"
python3 - "$work/nc.json" <<'PYEOF' && ok "no choice: nothing is invented into arc (the sibling-lessons default stands)" || err "no-choice payload wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["structure"] is None and d["recorded_in"] is None, d
PYEOF
python3 - <<'PYEOF' && ok "the proposer still marks sibling-lessons the default when no choice is made" || err "default lost"
import json, subprocess, sys
out = subprocess.run([sys.executable, "scripts/draft-pipeline.py", "structures",
                      "--brief", "tell the story over time"],
                     input='{"elements":[{"id":"lesson:a","kinds":["chronology"]},'
                           '{"id":"lesson:b","kinds":["chronology"]}]}',
                     capture_output=True, text=True).stdout
d = json.loads(out)
assert d["default"] == "sibling-lessons", d
PYEOF

# --- 5. brief-informed disclosure is carried ----------------------------------
python3 "$DP" structure-record --plan "$work/plan.md" --journal "$work/journal.json" \
  --expect-choice --brief-informed > "$work/bi.json" 2>/dev/null
python3 - "$work/bi.json" <<'PYEOF' && ok "the disclosure states the structure choice was brief-informed (CAP-9 per-element disclosure, extended)" || err "brief-informed disclosure missing"
import json, sys
assert json.load(open(sys.argv[1]))["brief_informed"] is True
PYEOF

# --- 6. exactly ONE gate in the entry path ------------------------------------
# The gate is the CAP-4 presentation in the draft SKILL. A second one anywhere in
# the entry path (a second `structures` presentation instruction, a second
# proposal-contract block for structures) is the failure this story guards.
n=$(grep -c 'draft-pipeline.py structures' "$SKILL" || true)
[ "$n" -le 3 ] && ok "the SKILL invokes the proposer only in the one CAP-4 sub-step (${n} invocation lines, all in that block)" \
  || err "structures is invoked in $n places — a second gate may have grown"
awk '/^\*\*Narrative-structure choice/{c++} END{exit !(c==1)}' "$SKILL" \
  && ok "exactly one Narrative-structure-choice gate block in the draft SKILL" \
  || err "expected exactly one Narrative-structure-choice block"
for s in skills/*/SKILL.md; do
  [ "$s" = "$SKILL" ] && continue
  grep -qi 'candidate structures\|narrative-structure choice' "$s" \
    && err "a second structure gate appears in $s"
done
ok "no other skill presents a structure gate — the entry path has exactly one"

# --- 7. SKILL states the one-gate/one-record contract -------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qiE 'no second gate' \
  && ok "SKILL: no second gate is introduced in the entry path" || err "SKILL missing the no-second-gate rule"
printf '%s' "$S" | grep -qiE 'recorded in the argument plan.s arc and nowhere else' \
  && ok "SKILL: the choice is recorded in arc and nowhere else" || err "SKILL missing the one-record rule"
printf '%s' "$S" | grep -qiE 'not in editorial_anchor' \
  && ok "SKILL: explicitly NOT editorial_anchor" || err "SKILL missing the anchor exclusion"
printf '%s' "$S" | grep -qi 'claim/angle answer only' \
  && ok "SKILL: editorial_anchor carries the claim/angle answer only (18.41 intact)" \
  || err "SKILL missing the CAP-2 anchor rule"
printf '%s' "$S" | grep -qiE 'exactly one confirmation' \
  && ok "SKILL: exactly one confirmation, options plus a free-form counter-proposal" \
  || err "SKILL missing the one-confirmation rule"
printf '%s' "$S" | grep -qi 'structure-record --plan' \
  && ok "SKILL wires the mechanical guard into the run" || err "SKILL does not invoke the guard"
printf '%s' "$S" | grep -qiE 'never blocks on the question' \
  && ok "SKILL: with no choice the default applies and the run never blocks" \
  || err "SKILL missing the never-blocks clause"

if [ "$fail" -eq 0 ]; then
  printf '\nAll one-structure-gate checks passed.\n'; exit 0
else
  printf '\none-structure-gate checks FAILED.\n' >&2; exit 1
fi
