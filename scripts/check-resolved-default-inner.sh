#!/usr/bin/env sh
# tier: inner — fixture-based: a plan file in a temp dir, the plan writer's
#   validator, and two `structure-record` invocations. No pipeline run, no
#   seam call, milliseconds — it guards the record it checks inside the edit
#   loop that writes it.
# covers: scripts/write-article-plan.py scripts/draft-pipeline.py skills/draft-article/stages/complete.md specs/spec-article-draft-pipeline/**
# removal-signal: the plan stops being where a defaulted resolution is
#   recorded — either because SPEC-article-draft-pipeline CAP-3's single-axis
#   clause is withdrawn, or because a shipped multi-axis arbitration takes
#   over the resolution and `resolved_defaults` leaves the plan schema.
#   Either observation retires this file with the field it guards.
#
# check-resolved-default-inner.sh — verify Story 20.62 (#966, umbrella #945;
# SPEC-article-draft-pipeline CAP-3, "Composition over an owner-selected
# Strand set", second clause): a DECLARED DEFAULT resolves a SINGLE-AXIS
# choice, and the resolution is VISIBLE and OVERRIDABLE in the plan rather
# than merely logged. The axis count is the test; a multi-outcome choice with
# no policy basis fires the gate; an undeclared default is not a default.
# POSIX shell + stdlib Python only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
WAP="$root/scripts/write-article-plan.py"
DOC="skills/draft-article/stages/complete.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

for f in "$DP" "$WAP" "$root/scripts/resolved_defaults.py"; do
  python3 -c "import py_compile; py_compile.compile('$f', doraise=True)" 2>/dev/null \
    || { err "syntax error in $f"; printf '\nFAILED.\n' >&2; exit 1; }
done
ok "pipeline helper, plan writer and the resolver compile"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

plan() {  # $1 = the resolved_defaults line (may be empty), $2 = output path
  { printf -- '---\nkind: article-plan\nslug: demo-plan\n'
    printf 'intent: introduce the project\nclaim: the plan shows what it defaulted\n'
    printf 'status: outlined\nrun_id: 20260730T000000\npin: host-repo@abc1234567890\n'
    printf 'arc: sibling-lessons over the selected clusters\n'
    # Story 20.68 (#983): an accepted structure declares its visual slots.
    printf 'visual_slots: []\n'
    printf 'structure_provenance: framework:F2\n'
    [ -n "$1" ] && printf 'resolved_defaults: %s\n' "$1"
    printf -- '---\n\n## Notes\n'
  } > "$2"
}

SINGLE='[{"choice": "audience", "value": "practitioners", "default": "practitioners", "declared_in": "config:article.audience", "axes": 1}]'
OVERRIDE='[{"choice": "audience", "value": "researchers", "default": "practitioners", "declared_in": "config:article.audience", "axes": 1}]'
MULTI='[{"choice": "narrative structure", "value": "thematic-braid", "default": "thematic-braid", "declared_in": "config:article.structure", "axes": 3}]'
UNDECLARED='[{"choice": "audience", "value": "practitioners", "default": "practitioners", "declared_in": "", "axes": 1}]'

# --- 1. a defaulted choice is VISIBLE in the plan, not merely logged ----------
plan "$SINGLE" "$work/plan.md"
python3 "$DP" structure-record --plan "$work/plan.md" > "$work/rec.json" 2>"$work/rec.err" \
  || err "structure-record failed on a plan recording a resolved default"
python3 - "$work/rec.json" <<'PYEOF' && ok "the plan shows which choice was resolved, to what value, and that a DEFAULT resolved it (a plan field, not a log line)" || err "the resolved default is not visible from the plan"
import json, sys
d = json.load(open(sys.argv[1]))
e = d["resolved_defaults"][0]
assert e["choice"] == "audience", e
assert e["value"] == "practitioners", e
assert e["resolved_by"] == "declared default", e
assert e["declared_in"] == "config:article.audience", e
assert d["resolved_choices"] == {"audience": "practitioners"}, d
PYEOF
python3 - <<'PYEOF' && ok "the record's home is the PLAN schema (an optional plan field), so it survives the run workspace" || err "resolved_defaults is not a plan-schema field"
import subprocess, sys, os
root = subprocess.check_output(["git","rev-parse","--show-toplevel"], text=True).strip()
sys.path.insert(0, os.path.join(root, "scripts"))
import importlib.util
spec = importlib.util.spec_from_file_location(
    "wap", os.path.join(root, "scripts", "write-article-plan.py"))
wap = importlib.util.module_from_spec(spec); spec.loader.exec_module(wap)
assert "resolved_defaults" in wap.OPTIONAL_KEYS, wap.OPTIONAL_KEYS
# and it is NOT machine state smuggled into the articles repo
assert "resolved_defaults" not in wap.MACHINE_STATE
PYEOF

# --- 2. overridable WHERE SHOWN ----------------------------------------------
plan "$OVERRIDE" "$work/override.md"
python3 "$DP" structure-record --plan "$work/override.md" > "$work/ovr.json" 2>/dev/null \
  || err "structure-record failed on an owner-overridden value"
python3 - "$work/ovr.json" <<'PYEOF' && ok "changing the value in the plan is the override: the changed value is what composition proceeds on, and no brief gate or Strand-set re-selection is involved" || err "the plan-side override is not honoured"
import json, sys
d = json.load(open(sys.argv[1]))
e = d["resolved_defaults"][0]
assert e["value"] == "researchers" and e["default"] == "practitioners", e
assert e["overridden"] is True, e
assert e["resolved_by"] == "owner override in the plan", e
# composition proceeds on the EFFECTIVE value, not the declared default
assert d["resolved_choices"]["audience"] == "researchers", d
# the override was read from the plan alone — the invocation carried no brief,
# no journal, no Strand set
assert d["resolved_defaults_overridable_in"] == "plan:resolved_defaults", d
PYEOF

# --- 3. multi-outcome with no policy basis fires the gate --------------------
plan "$MULTI" "$work/multi.md"
rc=0; python3 "$WAP" validate --path plans/demo-plan.md "$work/multi.md" \
  > "$work/multi.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -qi 'gate' "$work/multi.out" \
  && ok "a plan recording a MULTI-axis choice as defaulted is refused, with the gate named" \
  || err "the writer accepted a multi-axis default (rc=$rc)"
python3 - <<'PYEOF' && ok "the resolver classifies a multi-outcome choice with no policy basis as a GATE — no default is applied to it, visibly or otherwise" || err "multi-axis choice was defaulted"
import importlib.util, os, subprocess
root = subprocess.check_output(["git","rev-parse","--show-toplevel"], text=True).strip()
spec = importlib.util.spec_from_file_location(
    "rd", os.path.join(root, "scripts", "resolved_defaults.py"))
rd = importlib.util.module_from_spec(spec); spec.loader.exec_module(rd)
v = rd.classify({"name": "narrative structure", "axes": 3,
                 "declared_default": {"value": "thematic-braid",
                                      "declared_in": "config:article.structure"}})
assert v["resolution"] == "gate", v
assert "policy basis" in v["why"], v
PYEOF

# --- 4. the AXIS COUNT is the test, not perceived importance ------------------
python3 - <<'PYEOF' && ok "the decision to default turns on the axis count alone — importance, confidence and severity change nothing" || err "an importance/confidence/severity signal changed the decision"
import importlib.util, os, subprocess
root = subprocess.check_output(["git","rev-parse","--show-toplevel"], text=True).strip()
spec = importlib.util.spec_from_file_location(
    "rd", os.path.join(root, "scripts", "resolved_defaults.py"))
rd = importlib.util.module_from_spec(spec); spec.loader.exec_module(rd)
decl = {"value": "practitioners", "declared_in": "config:article.audience"}
base = rd.classify({"name": "audience", "axes": 1, "declared_default": decl})
assert base["resolution"] == "default", base
for extra in ({"importance": "critical"}, {"severity": "blocker"},
              {"confidence": 0.01}, {"importance": "trivial",
                                     "confidence": 0.99, "severity": "nit"}):
    c = {"name": "audience", "axes": 1, "declared_default": decl}
    c.update(extra)
    assert rd.classify(c) == base, (extra, rd.classify(c))
# flipping ONLY the axis count flips the resolution
two = rd.classify({"name": "audience", "axes": 2, "declared_default": decl})
assert two["resolution"] == "gate", two
PYEOF

# --- 5. an undeclared default is not a default -------------------------------
plan "$UNDECLARED" "$work/undeclared.md"
rc=0; python3 "$WAP" validate --path plans/demo-plan.md "$work/undeclared.md" \
  > "$work/und.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -qi 'undeclared default is not a default' "$work/und.out" \
  && ok "a single-axis choice with no DECLARED default is refused — it is asked, never silently resolved" \
  || err "an undeclared default was accepted (rc=$rc)"
python3 - <<'PYEOF' && ok "the resolver gates a single-axis choice whose default is declared nowhere" || err "an undeclared default resolved a choice"
import importlib.util, os, subprocess
root = subprocess.check_output(["git","rev-parse","--show-toplevel"], text=True).strip()
spec = importlib.util.spec_from_file_location(
    "rd", os.path.join(root, "scripts", "resolved_defaults.py"))
rd = importlib.util.module_from_spec(spec); spec.loader.exec_module(rd)
v = rd.classify({"name": "audience", "axes": 1, "declared_default": None})
assert v["resolution"] == "gate", v
assert "not a default" in v["why"], v
PYEOF

# --- 6. the ideal path is unchanged: no record, no question ------------------
plan "" "$work/plain.md"
python3 "$WAP" validate --path plans/demo-plan.md "$work/plain.md" >/dev/null 2>&1 \
  && ok "a plan recording no resolution validates exactly as before (additive field)" \
  || err "the plain plan stopped validating"
python3 "$DP" structure-record --plan "$work/plain.md" > "$work/plain.json" 2>/dev/null \
  || err "structure-record failed on a plan with no resolved defaults"
python3 - "$work/plain.json" <<'PYEOF' && ok "no resolved default recorded: nothing is disclosed and nothing is asked — the zero-additional-questions path is untouched" || err "the ideal path changed"
import json, sys
d = json.load(open(sys.argv[1]))
for k in ("resolved_defaults", "resolved_choices",
          "resolved_defaults_overridable_in"):
    assert k not in d, (k, d)
assert d["structure"] == "sibling-lessons", d
PYEOF

# --- 7. no second recording location -----------------------------------------
locs=$(grep -rl 'resolved_defaults' "$root/scripts" 2>/dev/null \
  | grep -v '__pycache__' | sed "s|$root/||" | sort | tr '\n' ' ')
[ "$locs" = "scripts/check-resolved-default-inner.sh scripts/draft-pipeline.py scripts/resolved_defaults.py scripts/write-article-plan.py " ] \
  && ok "one recording location: the plan schema (writer), its resolver, and the record command — no second store" \
  || err "resolved_defaults appears in unexpected places: $locs"
python3 - <<'PYEOF' && ok "editorial_anchor is untouched: it carries the claim/angle answer only (CAP-9 unchanged)" || err "the resolution leaked onto editorial_anchor"
import os, re, subprocess
root = subprocess.check_output(["git","rev-parse","--show-toplevel"], text=True).strip()
src = open(os.path.join(root, "scripts", "draft-pipeline.py"), encoding="utf-8").read()
m = re.search(r"\ndef cmd_structure_record\(.*?\n(?=\ndef )", src, re.S)
assert m, "cmd_structure_record not found"
body = m.group(0)
assert "rdm.disclosure(fields, wap)" in body, body
# the anchor is read for the second-store guard only, never written
assert "anchor[" not in body and "anchor.update" not in body, body
PYEOF

# --- 8. the recording contract is stated where the plan is assembled ----------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$DOC")
printf '%s' "$S" | grep -q 'resolved_defaults' \
  && ok "the completion doc states the resolved_defaults field" || err "doc missing the field"
printf '%s' "$S" | grep -qiE 'visible and overridable' \
  && ok "doc: visible and overridable in the plan" || err "doc missing the visible/overridable rule"
printf '%s' "$S" | grep -qiE 'merely logged' \
  && ok "doc: a journal or log entry does not satisfy it" || err "doc missing the merely-logged failure"
printf '%s' "$S" | grep -qiE 'axis count is the test' \
  && ok "doc: the axis count is the test, not perceived importance" || err "doc missing the axis-count test"
printf '%s' "$S" | grep -qiE 'undeclared default is not a default' \
  && ok "doc: an undeclared default is not a default" || err "doc missing the undeclared-default rule"
printf '%s' "$S" | grep -qiE 'fires the gate' \
  && ok "doc: a multi-outcome choice with no policy basis fires the gate" || err "doc missing the gate rule"
printf '%s' "$S" | grep -qiE 'zero additional questions' \
  && ok "doc: the ideal path stays at zero additional questions" || err "doc missing the ideal-path clause"

if [ "$fail" -eq 0 ]; then
  printf '\nAll resolved-default checks passed.\n'; exit 0
else
  printf '\nresolved-default checks FAILED.\n' >&2; exit 1
fi
