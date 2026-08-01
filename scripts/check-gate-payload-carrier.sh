#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/draft_gates.py scripts/draft_resume.py
# removal-signal: every owner-facing gate is emitted through one typed
#   composition point (the seam SPEC-writing-assistant's owner-surface register
#   clause leaves open) — at that point this check's subject becomes the seam
#   rather than the individual builders, and it retires with them.
# check-gate-payload-carrier.sh — a gate emits its question as DATA, in the
# shape that already ships (Story 20.103, #1081).
#
# THE ABSENCE IS WHAT THIS ASSERTS. An obligation produces no event to hook, so
# there is nothing to catch in the act; what is checkable is that a surface
# which asks the owner something HAS an emitted payload, and that the payload
# passes the same validator every other proposal surface passes. This check
# deliberately reads NO reply prose — nothing in this repository can, which is
# exactly why the carrier sits at the composed artifact instead.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$work" <<'PY' || { err "gate payloads did not build"; printf '\nFAILED.\n' >&2; exit 1; }
import importlib.util, json, os, sys
sys.path.insert(0, "scripts")
spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
from draft_gates import intent_gate, sources_gate
from draft_resume import confirmation
w = sys.argv[1]
json.dump(intent_gate(dp.INTENT_LABELS), open(os.path.join(w, "intent.json"), "w"))
json.dump(sources_gate(11, default_kind="subtree", default_detail="skills/terrain",
                       candidates=["skills/terrain/", "scripts/harvest-scope.py"]),
          open(os.path.join(w, "sources.json"), "w"))
json.dump(confirmation("20260718T000000-111111", "/ws", {"next_stage": "harvest"},
                       "started 14 days ago, on a different calendar day"),
          open(os.path.join(w, "resume.json"), "w"))
PY

# EVERY emitted gate passes the SHIPPED validator — not a private mirror of it.
# --require-render (Story 20.107, #1102) is what turns this from an EXISTENCE
# assertion into a CONFORMANCE one: a gate must declare how it renders, or the
# rendering step is free to compose prose from it, which is #1102 exactly.
for g in intent resume sources; do
  if python3 scripts/validate-proposal-payload.py --require-render "$work/$g.json" >/dev/null 2>"$work/$g.err"; then
    ok "the $g gate emits a PRESENTABLE payload (shipped validator, #1081)"
  else
    err "the $g gate's payload is blocked: $(head -2 "$work/$g.err" | tr '\n' ' ')"
  fi
done

python3 - "$work" <<'PY' || fail=1
import json, os, re, sys
w = sys.argv[1]
fail = 0


def check(cond, msg):
    global fail
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond:
        fail = 1


for name in ("intent", "resume", "sources"):
    item = json.load(open(os.path.join(w, name + ".json")))["items"][0]
    # OPTIONS PLUS FREE FORM, never options alone: options-only is a different
    # violation of the same clause that prose-only violates.
    check(item.get("free_text") is True,
          f"#1081: the {name} gate carries a free-text channel beside its "
          f"options")
    check(len(item.get("choices") or []) >= 2,
          f"#1081: ...and offers a real choice rather than one option")
    # NOTHING PRE-SELECTED. Rank is not pre-selection, and neither is order,
    # but a `selected`/`default` key would be.
    check(not any(k in c for c in item["choices"]
                  for k in ("selected", "default", "recommended")),
          f"#1081: ...with nothing pre-selected in the {name} gate")

# THE OWNER-FACING LABEL IS NEVER THE INTERNAL ALIAS. `f1`-`f5` are declared
# internal/expert aliases that never appear in owner-facing text, and building
# the choices from the mapping's KEYS is the obvious implementation that ships
# one to the single surface it is barred from.
blob = json.dumps(json.load(open(os.path.join(w, "intent.json"))))
check(not re.search(r"\bf[1-5]\b", blob),
      "#1081: the intent gate's owner-facing text carries no F-alias")

# THE RENDER FORM IS DECLARED, AND IT IS COMPUTED (Story 20.107, #1102).
# #1081's carrier stopped at "the rendering step quotes it" and never said what
# a conforming rendering IS, so five gates were still narrated seven minutes
# after it merged. What is checkable is the composed artifact: that a directive
# is present, that it AGREES with the choice count, and that a block carries
# the fields it would otherwise make the renderer invent. No reply prose is
# read here either — nothing in this repository can.
sys.path.insert(0, "scripts")
from draft_gates import CONTROL_CAPACITY as BUILDER_CAP
from importlib.machinery import SourceFileLoader
_v = SourceFileLoader("vpp", "scripts/validate-proposal-payload.py").load_module()

check(_v.CONTROL_CAPACITY == BUILDER_CAP,
      f"#1102: builder and validator agree on the control capacity "
      f"({BUILDER_CAP})")

for name in ("intent", "resume", "sources"):
    item = json.load(open(os.path.join(w, name + ".json")))["items"][0]
    r = item.get("render")
    check(isinstance(r, dict),
          f"#1102: the {name} gate declares a render form")
    if not isinstance(r, dict):
        continue
    n = len(item["choices"])
    expected = "selection" if n <= BUILDER_CAP else "block"
    check(r.get("control") == expected,
          f"#1102: ...and its control is {expected!r}, computed from "
          f"{n} choices against a capacity of {BUILDER_CAP}")
    # A recommendation LEADS. Rank is not pre-selection: the assertion above
    # that nothing carries a `recommended` key still holds per CHOICE; this is
    # the directive's index and it can only ever name the first option.
    check(r.get("recommended") in (None, 0),
          f"#1102: ...and any recommendation in the {name} gate leads")
    if r.get("control") == "block":
        check(bool(r.get("banner")) and bool(r.get("reply_line")),
              f"#1102: ...and the {name} block carries its own banner and "
              f"reply line rather than leaving them to the renderer")

# THE SOURCES GATE ASKS A SCOPE (Story 20.109, #1103). The observed gate listed
# candidate FILES and expected them typed back. The owner's decision is where
# the evidence lives; which files carry it is harvest's own step. So what is
# asserted is the ANSWER FORMAT: the choices are the closed scope vocabulary,
# and a path never appears as a choice label.
from draft_gates import SCOPE_KINDS
src = json.load(open(os.path.join(w, "sources.json")))["items"][0]
check(len(src["choices"]) == len(SCOPE_KINDS),
      f"#1103: the sources gate offers exactly the {len(SCOPE_KINDS)} scopes")
check(src["render"]["control"] == "selection",
      "#1103: ...as a selection, not a typing exercise")
check(src["render"]["recommended"] == 0,
      "#1103: ...with the recommended scope leading")
# CANDIDATES INFORM THE DEFAULT AND ARE NEVER THE ANSWER FORMAT: the evidence
# state a terrain-originated run carries is preserved, in the prose the owner
# reads, rather than promoted into the choice set.
# A SUBTREE SCOPE MAY NAME ITS SUBTREE — that is a scope, not a file list.
# What may never happen is a CANDIDATE becoming an option, which is the exact
# shape #1103 reports: the run's evidence state promoted from reason to answer.
_cands = ["skills/terrain/", "scripts/harvest-scope.py"]
check(not any(c["label"] in _cands for c in src["choices"]),
      "#1103: ...and no candidate file was promoted into the choice set")
check(not any(c["label"].endswith(".py") or c["label"].endswith(".md")
              for c in src["choices"]),
      "#1103: ...and no choice label is an individual file")
check("skills/terrain/" in src["why"],
      "#1103: ...while the candidates justifying the default survive in the reason")

sys.exit(1 if fail else 0)
PY

# --- asking is emitting (Story 20.118, #1114) -------------------------------
# THE REGISTRY IS THE CONSTRAINT. An emit call alone still lets a NEW surface be
# written that never calls it — which is exactly how the thesis gate reached the
# owner with no payload and nothing failing. A declared id makes composing an
# unknown surface an error at composition time.
python3 - <<'PY_AIE' || fail=1
import importlib.util, json, os, sys, tempfile
sys.path.insert(0, "scripts")
def load(n, p):
    sp = importlib.util.spec_from_file_location(n, p)
    m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
dg = load("draft_gates", "scripts/draft_gates.py")

bad = []
def need(c, m):
    if not c: bad.append(m)

try:
    dg.payload(where="w", why="y", choices=[{"label": "a", "effect": "b"}],
               gate="not-a-real-gate")
    need(False, "payload() accepted an UNDECLARED gate id — the registry is "
                "advisory, so a new surface can still be written that no "
                "inventory knows about (#1114)")
except ValueError:
    pass

snap = dg.declared_gates()
snap["intent"]["stage"] = "MUTATED"
need(dg.GATES["intent"]["stage"] != "MUTATED",
     "declared_gates() hands out the live dict — a reader can rewrite the "
     "authority it is reading")

for gid, spec in dg.GATES.items():
    need("stage" in spec, "gate %r declares no stage — 20.119 asserts over it" % gid)
    need("owner_decision" in spec,
         "gate %r has no owner_decision KEY — 20.117 derives its map from it, "
         "and a missing key is not the same as an explicit None" % gid)

ws = tempfile.mkdtemp()
dg.intent_gate({"f%d" % i: "type %d" % i for i in range(1, 6)}, ws=ws)
dg.sources_gate(11, ws=ws)
rows = [json.loads(l) for l in
        open(os.path.join(ws, "presented-payloads.jsonl"), encoding="utf-8")]
need([r["gate"] for r in rows] == ["intent", "sources"],
     "the stage-0 gates did not both emit: %s" % [r.get("gate") for r in rows])
need(all(r.get("stage") for r in rows),
     "an emitted row carries no stage — the inventory cannot place it")
need(all(r["items"][0].get("render") for r in rows),
     "an emitted payload lost its render: declaration — the #1114 defect was "
     "an emitted payload with none")
need(all(r.get("kind") == "ask" for r in rows),
     "an emitted row is not marked as an ASK — recording a question and "
     "recording its answer must be tellable apart")

# EVERY DECLARED GATE HAS A CODE SITE (Story 20.122, #1135). A registry entry
# with nothing calling it is the state 20.118 shipped deliberately and this
# story closes: the gate was declared so the audit could REPORT it, not so it
# could stay prose forever.
import glob
sites = ""
for f in glob.glob("skills/**/*.md", recursive=True):
    sites += open(f, encoding="utf-8").read()
sites += open("scripts/draft_gates.py", encoding="utf-8").read()
sites += open("scripts/terrain_screens.py", encoding="utf-8").read()
sites += open("scripts/draft_resume.py", encoding="utf-8").read()
for gid in dg.GATES:
    need(('"%s"' % gid) in sites or ("'%s'" % gid) in sites,
         "gate %r is declared but nothing composes it — a registry entry with "
         "no call site leaves the surface as prose, which is what #1114 "
         "reports (#1135)" % gid)
need(callable(getattr(dg, "gate", None)),
     "there is no generic gate() builder — five near-identical builders would "
     "be five places for the NEXT gate to be added without one")

src = open("scripts/terrain_screens.py", encoding="utf-8").read()
need("from draft_gates import emit" in src,
     "terrain_screens imports render_form without emit — composing a render "
     "directive there still implies no event (#1114)")
need(src.count("emit(") >= 3,
     "not every terrain screen payload routes through emit()")

for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY_AIE
[ "$fail" -eq 0 ] && ok "asking is emitting: the registry refuses an undeclared gate, and every code-path gate leaves an ask row"

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll gate-payload-carrier checks passed.\n'
