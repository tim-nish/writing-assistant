#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/draft_gates.py scripts/gate-inventory.py
# removal-signal: every gate surface is composed through the one typed seam
#   SPEC-writing-assistant's owner-surface register describes, at which point a
#   surface that reached the owner without an ask row is unrepresentable and
#   there is nothing left for a post-sitting subset check to catch.
# check-gate-inventory.sh — a run's gates are checkable against its payload log
# AFTER the sitting (Story 20.119, #1114/#1122).
#
# WHY AFTER, AND NOT ONLY AT THE BUILDER. Story 20.118 constrains what this
# repository COMPOSES; it cannot constrain the agent's own rendering step, which
# #1102 records as belonging to a layer this repo does not own. So the residue
# is detected rather than prevented: a gate the run REACHED with no matching
# row in `presented-payloads.jsonl` is a defect anyone can find later, which is
# the issue's ask (a) — "a checkable defect after the sitting, not just an
# obligation".
#
# AND THE DETECTION IS BOUNDED (Story 20.136, #1176). Both sides of the audit
# are keyed on `draft_gates.GATES`, so it detects a DECLARED gate that left no
# row and nothing else: an ask composed outside the registry passes silently.
# The bound is `gate_inventory.BOUND`, one string, carried in the audit result,
# in the CLI output and in --help — and this check asserts those carriers,
# because a limit that lives only in a docstring is a limit the next citation
# will not have read.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

report=$(python3 - <<'PY'
import contextlib, importlib.util, io, json, os, sys, tempfile
sys.path.insert(0, "scripts")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gi = load("gate_inventory", "scripts/gate-inventory.py")
dg = load("draft_gates", "scripts/draft_gates.py")

bad = []
def need(c, m):
    if not c: bad.append(m)

# A run that emitted every gate it reached is clean.
ws = tempfile.mkdtemp()
dg.intent_gate({"f%d" % i: "t%d" % i for i in range(1, 6)}, ws=ws)
dg.probe_entry_gate(3, ws=ws)
res = gi.audit(ws, reached=["intent", "probe-entry"])
need(res["ok"] is True, "a run whose gates all emitted is reported clean")
need(res["missing"] == [], "no gate is reported missing on a clean run")

# --- the clean verdict CARRIES ITS BOUND (Story 20.136, #1176) --------------
# A clean audit must not read as a clean class. The bound rides the CLEAN
# result specifically — that is the reader who is about to over-read it.
need("NOT" in gi.BOUND and "never declared" in gi.BOUND,
     "gate_inventory.BOUND does not state what the audit does NOT cover — an "
     "ask that was never declared in the registry is invisible to it")
need(res.get("bound") == gi.BOUND,
     "a CLEAN audit result carries no bound — a caller reading `ok` alone is "
     "exactly the reader the limit is for (#1176)")
need(gi.audit(ws, reached=["intent", "probe-entry", "terrain-axis"]).get("bound"),
     "a FAILING audit result carries no bound either")
_out = io.StringIO()
with contextlib.redirect_stdout(_out):
    gi.main(["--audit", "--ws", ws, "--reached", "intent,probe-entry"])
need(gi.BOUND in _out.getvalue(),
     "the --audit CLI output does not print the bound — the citation shape "
     "the amendment names is `gate-inventory.py --audit`, so that is the "
     "output that must say what it does not cover")
_help = io.StringIO()
with contextlib.redirect_stdout(_help):
    try:
        gi.main(["--help"])
    except SystemExit:
        pass
need("never declared" in _help.getvalue(),
     "--help does not state the bound")

# THE TRANSITION INTO HARVEST IS DECLARED (Story 20.136, #1176) and appears in
# the pending map, which is the surface the owner reads at a sitting end.
need("probe-entry" in dg.GATES,
     "the transition INTO stage 1 is not declared — it reached the owner as "
     "chat prose on 2026-08-01 with no ask row anywhere")
# THE ORDERING ASSERTION WAS HERE and is REMOVED with `harvest-completion`
# (Story 20.148, #1223). It required `harvest-entry` before `harvest-completion`
# on the ground that entering a stage precedes leaving it — true, and vacuous
# once one of the two gates no longer exists. An assertion over a pair whose
# second member is gone is not stale wording; it has no subject.

# THE MOTIVATING RUN. 20260801T091400-250105 reached the thesis gate and wrote
# no payload for it. A check that passes on the run that motivated it is not a
# check, so the shape is a fixture here.
res2 = gi.audit(ws, reached=["intent", "probe-entry", "terrain-member"])
need(res2["ok"] is False,
     "a gate the run REACHED with no ask row is not reported — this is the "
     "2026-08-01 thesis-gate shape, which must fail (#1114)")
need(res2["missing"] == ["terrain-member"],
     "the missing gate is NAMED, not merely counted: %s" % res2["missing"])

# render: is asserted on what the run WROTE, not on what a builder can build —
# the intent gate's emitted payload carried none on the observed run.
ws2 = tempfile.mkdtemp()
with open(os.path.join(ws2, "presented-payloads.jsonl"), "w",
          encoding="utf-8") as f:
    f.write(json.dumps({"kind": "ask", "gate": "intent", "stage": "stage 0",
                        "items": [{"where": "w", "why": "y",
                                   "choices": [{"label": "a", "effect": "b"}]}]}) + "\n")
res3 = gi.audit(ws2, reached=["intent"])
need(res3["ok"] is False and res3["render_missing"] == ["intent"],
     "an EMITTED payload with no render: declaration is not caught — that is "
     "the second half of the #1114 defect")

# An unknown gate id in `reached` is a programming error, not a silent pass.
try:
    gi.audit(ws, reached=["nope"])
    need(False, "audit() accepted a gate id the registry does not declare")
except ValueError:
    pass

# --- the pending-decision map is DERIVED (Story 20.117, #1112) -------------
need(True, "")
bad = [b for b in bad if b]
pend = gi.pending_decisions()
stages = [r["stage"] for r in pend]
need(stages == sorted(stages, key=lambda x: stages.index(x)),
     "the map is not in registry order")
need([r["gate"] for r in pend][:3] == ["terrain-axis", "terrain-member", "thesis"],
     "the map is not in PIPELINE order — 20.117 renders it as 'where each "
     "decision is asked', so an order other than the pipeline's tells the "
     "owner that stage 0 comes before the terrain screens")
need(all(r["gate"] != "resume-confirmation" for r in pend),
     "a gate with owner_decision None is rendered as a row — it carries no "
     "decision the owner must make, so an empty row would be noise")
lines = gi.pending_decision_lines()
joined = "\n".join(lines)
for want in ("stage 3", "stage 2", "terrain screen 1"):
    need(want in joined, "the map omits %r — #1112's ask names the stage-3 "
                         "gates explicitly, and a map missing exactly the "
                         "decisions the owner went looking for is the defect" % want)
need("never asked" in joined and "OBLIGATIONS" in joined,
     "paragraph structure is not stated as NEVER asked, with its reason — "
     "non-member disclosure applied to decisions: an absent item must read as "
     "considered-and-excluded, never as dropped")
need("intent" not in "\n".join(gi.pending_decision_lines(["intent"])),
     "an answered gate still renders as pending")
src = open("scripts/gate-inventory.py", encoding="utf-8").read()
need("_gates()" in src.split("def pending_decisions")[1][:1200],
     "pending_decisions does not read the registry — AC3 forbids a hand-listed "
     "map, since a hardcoded list drifts the first time a gate moves")

for m in bad:
    print(m)
PY
) || { err "gate-inventory harness did not run"; printf '\nFAILED.\n' >&2; exit 1; }

# --- Story 20.130 (#1146): the map HAS CALLERS -------------------------------
# The map shipped correct and unreachable: `--pending` rendered its nine lines
# and `grep -rn "gate-inventory" skills/` returned NOTHING, so no owner surface
# ever showed it. A derived mechanism with no caller is indistinguishable from
# an absent one at the surface that needed it, which is exactly what the owner
# reported ("I do not know what happens next"). Asserted over the two surfaces
# the story wires — the terrain handoff and the shared completion summary —
# because a caller is what the previous story could not check for itself.
for f in skills/terrain/steps/brief.md skills/completion-summary.md; do
  if grep -q 'gate-inventory.py --pending' "$f"; then
    ok "$f renders the pending-decision map"
  else
    err "$f does not call gate-inventory.py --pending — the map is derived and
     correct, and an owner surface that never renders it leaves the owner
     unable to see which decisions remain (#1146)"
    report="${report}
caller missing in $f"
  fi
done

if [ -z "$report" ]; then
  ok "a run's reached gates are asserted against its emitted ask rows"
  ok "a missing gate is named, and an emitted payload without render: is caught"
  ok "the 2026-08-01 thesis-gate shape fails this check"
  ok "the audit's bound rides its result, its --audit output and its --help"
  printf 'BOUND: the audit covers DECLARED-ID EMISSION. An owner-facing ask never\n'
  printf '       declared in draft_gates.GATES is invisible to it and audits clean.\n'
  printf '       The stated limit is the remedy; the reopen trigger is a harness-level\n'
  printf '       signal for a turn that ends awaiting a reply (#1176).\n'
else
  printf '%s\n' "$report" | while IFS= read -r l; do
    [ -n "$l" ] && printf 'FAIL: %s\n' "$l" >&2
  done
  printf '\ngate-inventory checks FAILED.\n' >&2
  exit 1
fi
exit 0
