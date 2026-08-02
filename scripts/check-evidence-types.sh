#!/usr/bin/env sh
# parallel-safe
# covers: scripts/draft_variants.py scripts/draft-pipeline.py skills/draft-article/stages/gate.md
# check-evidence-types.sh — verify per-section minimum evidence-type
# declarations and the fail-closed gate check (Story 13.90, #416). POSIX shell
# + stdlib Python.
#
# Checks: every framework's evidence-bearing slot carries an authored
# [EVIDENCE: …] tag from the closed vocabulary; the gate passes a section whose
# anchored pointers resolve to an allowed fact-sheet KIND; fails a hollow
# section (wrong KINDs) with a missing-input finding whose `upstream` line
# parses into `repair-hop`; fails CLOSED (exit 2) when declarations exist but
# --map/--state are missing; stays silent for a framework declaring nothing;
# and — Story 20.173, #1288 — reports an unresolvable predicate as its own
# named `cannot-determine` state with a reason, on both sides of the replay,
# never as a missing-input finding and never as a publish blocker.
#
# Story 20.174 (#1288) RE-ANCHORS the carrier on the examination pin ledger
# read beside the provenance map, so this check replays against a real
# workspace shape: `episode` resolves through the shipped time-axis predicate,
# and `example`/`measurement` — which a bare pin carries no field for — must
# stay UNMAPPED and report cannot-determine rather than acquire a guessed
# predicate under a publish blocker.

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

fw = w("fw.md", "# T\n\n## GATE {Evidence}   (~100 words) [SKIP: blocker] [EVIDENCE: episode]\n\n## {Limits}\n")
fw_mixed = w("fw_mixed.md", "# T\n\n## GATE {Evidence}   [EVIDENCE: episode|example|measurement]\n\n## {Limits}\n")
fw_ex = w("fw_ex.md", "# T\n\n## GATE {Evidence}   [EVIDENCE: example]\n\n## {Limits}\n")
fw_none = w("fw_none.md", "# T\n\n## {Context}\n\n## GATE {Pointer block}\n")
# THE CARRIER (Story 20.174): the run's derived pin ledger — bare pointers, one
# per line, exactly the file stage 3 hands verify-provenance as --fact-sheet.
# A commit sha carries a time axis; a `path:line@sha` prose pin does not.
state = w("pins.txt", "a1b2c3d\nsrc/b.py:20@bbbbbbb\n")
draft = ("---\naudience: r\naudience_id: r-id\n---\n"
         "## Evidence\n\nBody sentence one.\n\n## Limits\n\nTail.\n")
good_map = w("good.map", "P1.S1[L7]: sourced <- a1b2c3d\n")               # commit -> time axis
holl_map = w("holl.map", "P1.S1[L7]: sourced <- src/b.py:20@bbbbbbb\n")   # prose -> no time axis

def gate(**kw):
    class A:
        draft = "-"; map = None; judge = None; audience_known = None
        cycle = 1; prior_locations = None; profile = "full"
        framework_file = None; state = None; pin_ledger = None
    a = A()
    # `state=` names the CARRIER in this fixture: since 20.174 it is the pin
    # ledger, passed as --pin-ledger. One name kept so every case below reads
    # as "the carrier for this run".
    if "state" in kw:
        kw["pin_ledger"] = kw.pop("state")
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

# (c) fail closed: declarations exist, the carrier flag is missing -> exit 2,
# and the error NAMES the re-anchored flag (an agent re-invoking with --state
# would otherwise loop on the same refusal).
rc, out, errtxt = gate(map=good_map, judge=judge, framework_file=fw, state=None)
if rc != 2 or "fails closed" not in errtxt:
    bad.append("missing --pin-ledger did not fail closed with the named error")
if "--pin-ledger" not in errtxt or "examination-pins.txt" not in errtxt:
    bad.append("fail-closed error does not name the re-anchored carrier (#1288)")

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

# (f) THE THIRD OUTCOME (Story 20.173, #1288) — replayed on BOTH sides, and
# asserted on the emitted report TEXT, never on key presence. (i) a state with
# a resolvable carrier prints a pass or a finding; (ii) one whose carrier
# resolves none of the section's anchored pointers prints the cannot-determine
# line naming the section, the declared type, and WHY.
nores = w("nores.txt", "other/z.py:1@ccccccc\n")
def report_text(out, errtxt):
    g = json.loads(out)
    return "\n".join(g.get("notices", [])
                     + [g["dimensions"].get("evidence", {}).get("locations", "")]
                     + [errtxt])

rc, out, errtxt = gate(map=good_map, judge=judge, framework_file=fw, state=state)
if "cannot-determine" in report_text(out, errtxt):
    bad.append("a resolvable carrier reported cannot-determine (over-triggered)")

rc, out, errtxt = gate(map=good_map, judge=judge, framework_file=fw, state=nores)
text = report_text(out, errtxt)
g = json.loads(out)
if "evidence-type check: cannot-determine" not in text:
    bad.append("an unresolvable carrier printed no cannot-determine line")
if "evidence" not in text or "episode" not in text:
    bad.append("cannot-determine line names neither the section nor the declared type")
if text.count("cannot-determine") and "carrier absent" not in text:
    bad.append("cannot-determine line carries no reason (a bare state repeats the defect)")
# AC-3: never a missing-input finding, so the episode-candidates hop is
# unreachable from it. AC-4: never a publish blocker on its own.
if g.get("evidence_types", {}).get("missing_input"):
    bad.append("cannot-determine leaked into missing_input[] (the #751 fabricated gap)")
if "evidence" in g.get("failing_dimensions", []):
    bad.append("cannot-determine blocked the gate as a failing dimension")
if g["dimensions"].get("evidence", {}).get("verdict") != "cannot-determine":
    bad.append("the evidence dimension did not carry the third verdict")
# AC-2: dropping the flags no longer routes around the check in silence.
rc, out, errtxt = gate(map=good_map, judge=judge)
if "evidence-type check: cannot-determine" not in report_text(out, errtxt):
    bad.append("gate run without --framework-file omitted the check silently (#1288)")

# (g) THE RE-ANCHOR REPLAY (Story 20.174, #1288) — the three outcomes AC-6
# names, all asserted on emitted output, against a real workspace shape: a pin
# ledger of bare pointers plus an anchored provenance map.
#
# (i) `episode` grounded in a COMMIT pointer passes — through the SAME
# time-axis predicate verify-provenance enforces per claim (#1184 (iii)).
rc, out, errtxt = gate(map=good_map, judge=judge, framework_file=fw, state=state)
g = json.loads(out)
if g["dimensions"].get("evidence", {}).get("verdict") != "pass":
    bad.append("episode grounded in a commit pointer did not pass the time-axis predicate")

# (ii) the SAME section grounded only in a `path:line@sha` prose pointer is a
# missing-input finding NAMING the section and the type — never a pass, and
# never cannot-determine (the predicate resolved; it was refuted). examine
# declares that negative at the source: a prose item is "state claims only —
# not an episode source".
rc, out, errtxt = gate(map=holl_map, judge=judge, framework_file=fw, state=state)
g = json.loads(out)
mi = g.get("evidence_types", {}).get("missing_input", [])
loc = g["dimensions"].get("evidence", {}).get("locations", "")
if g["dimensions"].get("evidence", {}).get("verdict") != "fail" or not mi:
    bad.append("prose-only episode section did not produce a missing-input finding")
elif mi[0]["section"] != "evidence" or "episode" not in "|".join(mi[0]["declared"]):
    bad.append("missing-input finding names neither the section nor the type")
if "evidence" not in loc or "episode" not in loc:
    bad.append("the emitted fail locations name neither the section nor the type")
if "cannot-determine" in report_text(out, errtxt):
    bad.append("a REFUTED episode predicate reported cannot-determine (over-triggered)")

# (iii) an `example`-declaring section is cannot-determine — ALWAYS, including
# over a carrier that resolves every one of its pointers. A pin ledger line is
# a bare pointer with no kind field, so quote/result/number are not recoverable
# from it; a guessed predicate under a publish blocker is the worse failure.
for fwx, label in ((fw_ex, "example-only"), (fw_mixed, "episode|example|measurement")):
    rc, out, errtxt = gate(map=good_map if fwx is fw_ex else holl_map,
                           judge=judge, framework_file=fwx, state=state)
    g = json.loads(out)
    text = report_text(out, errtxt)
    if "evidence-type check: cannot-determine" not in text:
        bad.append(f"{label}: no cannot-determine line for an unmapped type")
    if "example" not in text:
        bad.append(f"{label}: cannot-determine line does not name the unmapped type")
    if g.get("evidence_types", {}).get("missing_input"):
        bad.append(f"{label}: an unmapped type produced a missing-input finding "
                   "(a guessed mapping under a publish blocker)")
    if "evidence" in g.get("failing_dimensions", []):
        bad.append(f"{label}: an unmapped type blocked the gate")

# (iv) `example`/`measurement` have NO entry in the predicate table — asserted
# on the table itself, so a future edit that quietly adds one is caught here
# and not only in the replay above.
PY_TABLE = getattr(dp, "draft_variants", None)
if PY_TABLE is None or not hasattr(PY_TABLE, "EVIDENCE_TYPE_PREDICATES"):
    bad.append("EVIDENCE_TYPE_PREDICATES is not reachable from the host module")
elif PY_TABLE.EVIDENCE_TYPE_PREDICATES != {"episode"}:
    bad.append("the predicate table drifted: only `episode` has a shipped "
               f"predicate post-harvest, got {PY_TABLE.EVIDENCE_TYPE_PREDICATES!r}")

# (v) an EMPTY but readable ledger is a corpus precondition (cannot-determine),
# while an UNREADABLE one is an invocation defect (exit 2). The #751 line
# between "computed over nothing" and "computed and found nothing", re-pointed.
empty = w("empty.txt", "")
rc, out, errtxt = gate(map=good_map, judge=judge, framework_file=fw, state=empty)
if rc == 2 or "cannot-determine" not in report_text(out, errtxt):
    bad.append("an empty pin ledger refused instead of reporting cannot-determine")
rc, out, errtxt = gate(map=good_map, judge=judge, framework_file=fw,
                       state=os.path.join(tmp, "does-not-exist.txt"))
if rc != 2 or "cannot read --pin-ledger" not in errtxt:
    bad.append("an unreadable pin ledger did not refuse as an invocation defect")

# (vi) NO NEW STORE (AC-2): the check only READS its carrier — no second
# ledger, no index, no kind-sidecar, and no append to the derived ledger.
files_before = sorted(os.listdir(tmp))
pins_before = open(state).read()
gate(map=good_map, judge=judge, framework_file=fw_mixed, state=state)
if sorted(os.listdir(tmp)) != files_before:
    bad.append("the evidence-type check wrote a file — it creates no store (AC-2)")
if open(state).read() != pins_before:
    bad.append("the evidence-type check mutated the pin ledger — it stays DERIVED (AC-2)")

for b in bad: print(f"  drift: {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

if [ "$fail" -eq 0 ]; then printf '\nPASSED: per-section evidence types + fail-closed gate.\n'; else printf '\nFAILED.\n' >&2; exit 1; fi
