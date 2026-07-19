#!/usr/bin/env sh
# check-evidence-types.sh — verify per-section minimum evidence-type
# declarations and the fail-closed gate check (Story 13.90, #416). POSIX shell
# + stdlib Python.
#
# Checks: every framework's evidence-bearing slot carries an authored
# [EVIDENCE: …] tag from the closed vocabulary; the gate passes a section whose
# anchored pointers resolve to an allowed fact-sheet KIND; fails a hollow
# section (wrong KINDs) with a missing-input finding whose `upstream` line
# parses into `repair-hop`; fails CLOSED (exit 2) when declarations exist but
# --map/--state are missing; and stays silent for a framework declaring
# nothing.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
FW="skills/draft-article/frameworks"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 1. Template declarations present (the authored contract).
tag() { if grep -qF -- "$2" "$FW/$1"; then ok "$1: $3"; else err "$1 missing declaration: $3"; fi; }
tag F1-project-introduction.md "[EVIDENCE: episode|example|measurement]" "Evidence slot declares episode|example|measurement"
tag F2-engineering-lessons.md  "[EVIDENCE: episode|example|measurement]" "artifact GATE declares episode|example|measurement"
tag F3-evaluation-methodology.md "[EVIDENCE: measurement]" "results GATE declares measurement"
tag F4-research-survey.md      "[EVIDENCE: example]" "map slot declares example"
tag F5-working-note.md         "[EVIDENCE: episode|example]" "one-lesson GATE declares episode|example"
tag F5-working-note.md         "[EVIDENCE: measurement]" "one-number GATE declares measurement"

# 2. Gate behavior, in-process.
python3 - "$DP" <<'PY' && ok "gate: satisfied/hollow/fail-closed/undeclared/slim behave per contract" || err "gate behavior drifted (see above)"
import importlib.util, io, json, os, sys, tempfile
from contextlib import redirect_stdout, redirect_stderr

spec = importlib.util.spec_from_file_location("dp", sys.argv[1])
dp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dp)

bad = []
tmp = tempfile.mkdtemp()
def w(name, text):
    p = os.path.join(tmp, name)
    open(p, "w").write(text)
    return p

fw = w("fw.md", "# T\n\n## GATE {Evidence}   (~100 words) [SKIP: blocker] [EVIDENCE: episode|example|measurement]\n\n## {Limits}\n")
fw_none = w("fw_none.md", "# T\n\n## {Context}\n\n## GATE {Pointer block}\n")
state = w("state.json", json.dumps({"fact_sheet": [
    {"claim": "c1", "source": "src/a.py:10@aaaaaaa", "kind": "event"},
    {"claim": "c2", "source": "src/b.py:20@bbbbbbb", "kind": "decision"},
]}))
draft = ("---\naudience: r\naudience_id: r-id\n---\n"
         "## Evidence\n\nBody sentence one.\n\n## Limits\n\nTail.\n")
good_map = w("good.map", "P1.S1[L7]: sourced <- src/a.py:10@aaaaaaa\n")   # event -> allowed
holl_map = w("holl.map", "P1.S1[L7]: sourced <- src/b.py:20@bbbbbbb\n")   # decision -> not allowed

def gate(**kw):
    class A:
        draft = "-"; map = None; judge = None; audience_known = None
        cycle = 1; prior_locations = None; profile = "full"
        framework_file = None; state = None
    a = A()
    for k, v in kw.items(): setattr(a, k, v)
    out, errbuf = io.StringIO(), io.StringIO()
    sys.stdin = io.StringIO(draft)
    with redirect_stdout(out), redirect_stderr(errbuf):
        rc = a and dp.cmd_quality_gate(a)
    sys.stdin = sys.__stdin__
    return rc, out.getvalue(), errbuf.getvalue()

# judge stub for full profile
judge = w("judge.txt", "dim1: pass\ndim2: pass\n")

# (a) satisfied: anchored event pointer in the Evidence section.
rc, out, _ = gate(map=good_map, judge=judge, framework_file=fw, state=state)
g = json.loads(out)
if g["dimensions"].get("evidence", {}).get("verdict") != "pass":
    bad.append("satisfied section did not pass the evidence check")
if not g.get("evidence_types", {}).get("checked"):
    bad.append("evidence_types.checked missing on a checked run")

# (b) hollow: only a `decision` pointer — declared types unmet -> fail + missing-input.
rc, out, _ = gate(map=holl_map, judge=judge, framework_file=fw, state=state)
g = json.loads(out)
if rc == 0: bad.append("hollow section passed the gate")
if g["dimensions"].get("evidence", {}).get("verdict") != "fail":
    bad.append("hollow section: evidence verdict not fail")
mi = g.get("evidence_types", {}).get("missing_input", [])
if not mi or mi[0].get("classification") != "missing-input":
    bad.append("hollow section: no missing-input finding emitted")
else:
    # the ready-made upstream line must parse into repair-hop as a bounded hop
    class H: cycle = 0; upstream = mi[0]["upstream"]
    out2 = io.StringIO()
    with redirect_stdout(out2), redirect_stderr(io.StringIO()):
        rc2 = dp.cmd_repair_hop(H())
    hop = json.loads(out2.getvalue())
    if rc2 != 0 or hop.get("action") not in ("elicit", "re-harvest"):
        bad.append(f"missing-input upstream line did not parse in repair-hop (action={hop.get('action')!r})")

# (c) fail closed: declarations exist, --state missing -> exit 2.
rc, out, errtxt = gate(map=good_map, judge=judge, framework_file=fw, state=None)
if rc != 2 or "fails closed" not in errtxt:
    bad.append("missing --state did not fail closed with the named error")

# (d) undeclared framework: no evidence key, no failure.
rc, out, _ = gate(map=good_map, judge=judge, framework_file=fw_none, state=state)
g = json.loads(out)
if "evidence" in g["dimensions"] or "evidence_types" in g:
    bad.append("undeclared framework still produced an evidence check")

# (e) slim profile runs the check too (no judge, dims 1-2 waived, evidence still gates).
rc, out, _ = gate(map=holl_map, framework_file=fw, state=state, profile="slim")
g = json.loads(out)
if g["dimensions"].get("dim1", {}).get("verdict") != "waived":
    bad.append("slim profile: dim1 not waived")
if g["dimensions"].get("evidence", {}).get("verdict") != "fail":
    bad.append("slim profile bypassed the evidence check")

for b in bad: print(f"  drift: {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

if [ "$fail" -eq 0 ]; then printf '\nPASSED: per-section evidence types + fail-closed gate.\n'; else printf '\nFAILED.\n' >&2; exit 1; fi
