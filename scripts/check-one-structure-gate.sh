#!/usr/bin/env sh
# parallel-safe
# covers: scripts/draft-pipeline.py skills/*/SKILL.md skills/draft-article/stages/stage3.md
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
SKILL="skills/draft-article/stages/stage3.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

plan() {   # $1 = arc value, $2 = structure_provenance (#911; empty = omit the key)
  printf -- '---\nkind: article-plan\nslug: s\nintent: F2\nclaim: c\nstatus: outlined\nrun_id: r\npin: repo@abc1234\narc: %s\n' "$1"
  [ -n "${2:-}" ] && printf 'structure_provenance: %s\n' "$2"
  printf -- '---\n\nbody\n'
}
plan 'thematic-braid — the clusters share cost, braided into one piece' bespoke > "$work/plan.md"
plan 'a movement with no structure named' framework:F2 > "$work/plan-nochoice.md"
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

# --- 5b. the #911 instrument: provenance recorded, validated, disclosed -------
# One interpreter, module loaded once, four guard invocations (the
# check-framework-f5 idiom — keeps this check inside the inner-tier ceiling).
plan 'thematic-braid — the clusters share cost' > "$work/plan-nofield.md"
plan 'thematic-braid — braided' 'framework:F9' > "$work/plan-badvocab.md"
plan 'thematic-braid — braided' 'framework:F2' > "$work/plan-disagree.md"
plan 'thematic-braid — braided' 'bespoke+owner-edited' > "$work/plan-edited.md"
python3 - "$DP" "$work" <<'PYEOF' || fail=1
import contextlib, importlib.util, io, json, sys
spec = importlib.util.spec_from_file_location("dp", sys.argv[1])
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
w = sys.argv[2]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

class A:
    journal = w + "/journal.json"
    expect_choice = True
    brief_informed = False
def record(plan):
    a = A(); a.plan = plan
    out, errs = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(errs):
        rc = dp.cmd_structure_record(a)
    return rc, out.getvalue(), errs.getvalue()

# An accepted structure with no structure_provenance is a MISSING MEASUREMENT.
rc, _o, e = record(w + "/plan-nofield.md")
check(rc != 0, "an accepted structure with no structure_provenance is REFUSED (#911)")
check("missing measurement" in e.lower(),
      "the refusal names the missing measurement, not a generic error")
# The vocabulary is closed, and it is the plan writer's regex — not a copy.
rc, _o, _e = record(w + "/plan-badvocab.md")
check(rc != 0, "an out-of-vocabulary structure_provenance is REFUSED")
# The recorded value must agree with the proposer's marking: sibling-lessons IS
# the F2 shape; any other accepted structure is bespoke.
rc, _o, _e = record(w + "/plan-disagree.md")
check(rc != 0, "a provenance disagreeing with the proposer's marking is REFUSED (carried, never re-derived)")
# +owner-edited passes and is disclosed, so matched-then-rewritten is
# distinguishable from matched-and-kept.
rc, o, _e = record(w + "/plan-edited.md")
check(rc == 0, "an owner-edited provenance passes the guard")
d = json.loads(o)
check(d.get("structure_provenance") == "bespoke+owner-edited"
      and d.get("owner_edited") is True,
      "the disclosure carries the provenance and the owner-edited flag (#911)")

# The proposer marks every candidate at proposal time — silence is impossible.
buf = io.StringIO()
class S:
    selected = w + "/sel.json"
    brief = None
json.dump({"elements": [{"id": "lesson:a", "kinds": ["chronology"]},
                        {"id": "lesson:b", "kinds": ["chronology"]}]},
          open(w + "/sel.json", "w"))
with contextlib.redirect_stdout(buf):
    dp.cmd_structures(S())
c = json.loads(buf.getvalue())["candidates"]
check(all("provenance" in x for x in c)
      and next(x for x in c if x["structure"] == "sibling-lessons")["provenance"] == "framework:F2"
      and all(x["provenance"] == "bespoke" for x in c if x["structure"] != "sibling-lessons"),
      "every proposed candidate carries its provenance (framework:F2 for the F2 shape, bespoke otherwise)")
sys.exit(1 if fail else 0)
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
