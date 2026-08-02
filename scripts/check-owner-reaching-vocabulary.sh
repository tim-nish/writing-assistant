#!/bin/sh
# check-owner-reaching-vocabulary.sh — no OWNER-REACHING surface carries
# harvest vocabulary (Story 20.149, #1220) or a NUMBERED PROCESS LABEL
# (Story 20.158, #1247).
#
# tier: inner
# covers: scripts/draft_gates.py scripts/owner_surface.py
# serial-reason: ends with a whole-tree content grep over scripts/ skills/
#   docs/ README.md, which is the shape that collides with a concurrently
#   running check writing a fixture into one of those trees even when the two
#   file SETS look disjoint. The residue count feeds a note: rather than a
#   verdict, so a race would misreport rather than misfail — but "it would
#   only corrupt the advisory line" is not an isolation argument.
# removal-signal: this check retires when `harvest`/`fact sheet` no longer
#   exists anywhere in the repository, at which point it has no subject — or
#   when the owner-surface seam grows a general register gate that subsumes a
#   per-vocabulary assertion. It does NOT retire merely because it passes: the
#   residue it guards against is declared report-only and is expected to
#   survive, so a green run is the steady state rather than a reason to delete.
#
# WHY THIS EXISTS, AND WHY IT IS ONE MEMBER RATHER THAN THIRTEEN.
# `specs/spec-article-draft-pipeline/amendments.md` (2026-08-02, #1220/#1223)
# declines to enumerate harvest remnants. The measurement that killed the
# enumeration framing: `harvest`/`fact sheet` appears 918 times repo-wide, in
# 26 spec files, inside 7 of 10 capabilities. #1220 named six surfaces and
# #1223 named seven more; both were far short. So the amendment declares the
# residue REPORT-ONLY and binds exactly one property, which this file asserts:
#
#     no owner-reaching surface carries harvest vocabulary
#
# That is the subset with a READER. The rest is stale text with no audience,
# and failing on all 918 would be the enumerated remedy the register clause
# (`specs/spec-writing-assistant/SPEC.md:80`) prohibits — its own diagnostic is
# "a check suite growing at roughly one member per incident".
#
# WHAT MAKES "OWNER-REACHING" DECIDABLE, which was this story's open question.
# It is not a file-path heuristic. SPEC.md:80 already fixes owner-facing as
# "a TYPE carried by the value rather than a property of which file it lives
# in", and two typed surfaces implement that today:
#
#   1. `draft_gates.payload()` — every emitted gate payload. Its presented
#      fields are enumerable by construction: `where`, `why`, and each
#      choice's `label` and `effect`.
#   2. `owner_surface` — the composition seam (Story 20.115, #1117), whose
#      `completion_summary` composes the buckets the owner reads at run end.
#
# So the check asserts over what the code EMITS, never over source text. A
# comment in a script explaining why harvest was retired is not owner-reaching
# and must not fail here; a `why` string handed to the selection UI is.
#
# THREE-VALUED, because a vacuous pass is the #933 failure mode.
# `specs/spec-writing-assistant/SPEC.md:81` clause (b) requires that a failed
# corpus precondition report as its own state. Eight of the ten declared gates
# have no builder — they reach the owner from a SKILL prompt, which
# `draft_gates.py` documents in as many words — so their text is not reachable
# from here. Those are CANNOT-DETERMINE and are printed as such. They are not
# passes, and the count is displayed so a shrinking or growing unreachable set
# is visible rather than silent.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail=0
ok()   { printf 'ok:   %s\n' "$1"; }
err()  { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
note() { printf 'note: %s\n' "$1"; }

# --- the emitted owner surface ------------------------------------------
# Builders are called with representative arguments. A builder whose signature
# this cannot satisfy is reported cannot-determine rather than skipped, so a
# new required parameter never silently removes a gate from coverage.
OUT=$(cd "$ROOT" && python3 - <<'PY'
import importlib.util, inspect, json, os, re, sys

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

dg = load("draft_gates", os.path.join("scripts", "draft_gates.py"))

# The vocabulary. Deliberately short: this is the ONE class the amendment
# binds, not a general register blocklist — adding unrelated terms here would
# turn a bound property back into the enumerated denial list SPEC.md:80 (a)
# prohibits.
TERMS = ("harvest", "fact sheet", "fact-sheet")

# THE SECOND BOUND CLASS (Story 20.158, #1247), and it RIDES HERE rather than
# founding a family. Owner ruling 2026-08-02: *"I prohibit the expression
# 'Stage N.' … By attaching a number, the system abandons its responsibility to
# explain which process the Human Gate belongs to."* The remedy is at the
# SOURCE — `draft_gates` declares process names (`terrain`/`start`/`probe`/
# `interview`/`fill`) and the composition sources carry no numbers — so this is
# the DETECT half of the same constrain->detect order, asserted over the same
# emitted surface and by the same three-valued rule. It is not a per-word
# checker: one pattern over an already-enumerated field set, in a file that
# already exists, is what the amendment's "detection rides the existing
# owner-surface check" names. The class is NUMBERED PROCESS LABELS, not the
# word "stage": the 2026-08-02 leak that survived the 20.158 sweep read
# "Step 3 — compose the brief" (terrain's brief gate), in-class and unmatched
# by a stage-only pattern. Widening the alternation is still one bound class;
# adding a second TERMS-style list would be the denial-list growth SPEC.md:80
# prohibits.
NUMBERED = re.compile(r"\b(stage|step|phase)\s*[-_]?\s*\d", re.I)

# The presented fields of a payload item, per `draft_gates.payload`. Named
# rather than walked, so a new field is a deliberate addition here instead of
# silently inheriting coverage it was never checked for.
def presented(item):
    yield "where", item.get("where", "")
    yield "why", item.get("why", "")
    for i, c in enumerate(item.get("choices") or []):
        yield f"choices[{i}].label", c.get("label", "")
        yield f"choices[{i}].effect", c.get("effect", "")
    render = item.get("render") or {}
    for i, o in enumerate(render.get("overflow") or []):
        yield f"render.overflow[{i}]", o

# Representative arguments by parameter name. Values are shaped to exercise
# the builder, never to dodge it.
SAMPLE = {"source_count": 3, "fact_count": 5, "needs_owner_count": 2,
          "blockers": 1, "ws": None, "brief": True, "count": 3, "n": 3,
          "labels": {"introduce the project": "a project introduction",
                     "share engineering lessons": "lessons from building it",
                     "explain the evaluation methodology": "how it was measured",
                     "survey a research area": "a survey of the area",
                     "write a working note": "a short working note"}}

def call(fn):
    kwargs = {}
    for name, p in inspect.signature(fn).parameters.items():
        if name in SAMPLE:
            kwargs[name] = SAMPLE[name]
        elif p.default is inspect.Parameter.empty:
            return None, f"required parameter {name!r} has no sample value"
    try:
        return fn(**kwargs), None
    except Exception as e:                      # pragma: no cover - reported
        return None, f"{type(e).__name__}: {e}"

builders = {}
for name, obj in vars(dg).items():
    if inspect.isfunction(obj) and name.endswith("_gate"):
        builders[name] = obj

# Map builder -> declared gate id from the `gate=` it passes to `payload`,
# which is where the id is declared. `payload` consumes the argument and does
# not put it in the item, so it cannot be read back off the returned dict —
# and guessing from the function name would silently mis-map any builder whose
# name and id diverge, which is exactly what this story just renamed.
def gate_id(fn):
    src = inspect.getsource(fn)
    m = re.search(r"gate=[\"']([a-z0-9-]+)[\"']", src)
    return m.group(1) if m else None
checked, undetermined, hits, numbered = [], [], [], []
for name in sorted(builders):
    payload, why = call(builders[name])
    if payload is None:
        undetermined.append((name, why))
        continue
    gid = gate_id(builders[name]) or name
    for item in payload.get("items") or []:
        checked.append(gid)
        for field, value in presented(item):
            low = str(value).lower()
            for t in TERMS:
                if t in low:
                    hits.append((gid, field, t, " ".join(str(value).split())))
            m = NUMBERED.search(str(value))
            if m:
                numbered.append((gid, field, m.group(0),
                                 " ".join(str(value).split())))

# Declared gates with no builder reachable from here.
built = {gate_id(fn) for fn in builders.values()} - {None}
for gate in dg.GATES:
    if gate not in built:
        undetermined.append((gate, "declared with no builder — composed from a skill prompt"))

# --- the composition seam ------------------------------------------------
try:
    osurf = load("owner_surface", os.path.join("scripts", "owner_surface.py"))
    buckets = list(getattr(osurf, "BUCKETS", []))
    for b in buckets:
        low = str(b).lower()
        for t in TERMS:
            if t in low:
                hits.append(("owner_surface.BUCKETS", str(b), t, str(b)))
        m = NUMBERED.search(str(b))
        if m:
            numbered.append(("owner_surface.BUCKETS", str(b), m.group(0),
                             str(b)))
    # The gate registry's `stage` value is the process name the payload
    # carries into `where`/inventory rendering, so it is owner-reaching by the
    # same TYPE argument the header states.
    for gate, meta in dg.GATES.items():
        v = str(meta.get("stage", ""))
        m = NUMBERED.search(v)
        if m:
            numbered.append((gate, "GATES.stage", m.group(0), v))
    checked.append("draft_gates.GATES[*].stage")
    checked.append("owner_surface.BUCKETS")
except Exception as e:
    undetermined.append(("owner_surface", f"{type(e).__name__}: {e}"))

# --- terrain's register seam ---------------------------------------------
# The 2026-08-02 leak: terrain's brief gate relayed "Step 3 — compose the
# brief (terrain/step-3-compose-the-brief)" while this check watched only
# draft_gates and owner_surface. `terrain_text` is terrain's DECLARED
# owner-facing string seam (its own header says "Owner-facing strings, so
# they live HERE"), and `topic-map-directions.py` composes the brief payload's
# `step.line` from it verbatim — so it is owner-reaching by the same TYPE
# argument as the two surfaces above, not by file-path heuristic.
try:
    tt = load("terrain_text", os.path.join("scripts", "terrain_text.py"))
    for field, value in (("BRIEF_STEP_ID", tt.BRIEF_STEP_ID),
                         ("BRIEF_STEP_NAME", tt.BRIEF_STEP_NAME),
                         ("step.line", tt._brief_step_line())):
        low = str(value).lower()
        for t in TERMS:
            if t in low:
                hits.append(("terrain_text", field, t, str(value)))
        m = NUMBERED.search(str(value))
        if m:
            numbered.append(("terrain_text", field, m.group(0), str(value)))
    checked.append("terrain_text.BRIEF_STEP_*")
except Exception as e:
    undetermined.append(("terrain_text", f"{type(e).__name__}: {e}"))

json.dump({"checked": sorted(set(checked)), "hits": hits,
           "numbered": numbered,
           "undetermined": [list(u) for u in undetermined]}, sys.stdout)
PY
)

CHECKED=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["checked"]))')
NHITS=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["hits"]))')
NUND=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["undetermined"]))')

if [ "$NHITS" -ne 0 ]; then
  printf '%s' "$OUT" | python3 -c '
import json,sys
for gate, field, term, value in json.load(sys.stdin)["hits"]:
    print("  %s %s carries %r: %s" % (gate, field, term, value[:160]), file=sys.stderr)
'
  err "an owner-reaching surface carries harvest vocabulary (see above) — the
      stage is retired, so a payload naming it describes a pipeline the owner
      is not running"
else
  ok "no owner-reaching surface carries harvest vocabulary ($CHECKED surface(s) checked)"
fi

NNUM=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["numbered"]))')
if [ "$NNUM" -ne 0 ]; then
  printf '%s' "$OUT" | python3 -c '
import json,sys
for gate, field, form, value in json.load(sys.stdin)["numbered"]:
    print("  %s %s carries %r: %s" % (gate, field, form, value[:160]), file=sys.stderr)
'
  err "an owner-reaching surface carries a NUMBERED process label (see above) —
      the owner cannot tell brief creation from draft creation from a number,
      so name the process (terrain/start/probe/interview/fill)"
else
  ok "no owner-reaching surface carries a numbered process label"
fi

# CANNOT-DETERMINE is printed, never counted as a pass and never a failure.
# A hard failure here would make the check unusable on a corpus that legitimately
# composes some gates from skill prompts; a silent skip would make its silence
# read as coverage.
printf '%s' "$OUT" | python3 -c '
import json,sys
for name, why in json.load(sys.stdin)["undetermined"]:
    print("note: cannot-determine: %s — %s" % (name, why))
'
note "cannot-determine: $NUND surface(s); checked: $CHECKED"

# --- the residue is NOT this check_s subject -----------------------------
# Asserted positively so a future reader does not "strengthen" this check into
# the repo-wide sweep the amendment declined.
RESIDUE=$(cd "$ROOT" && grep -rniE 'harvest|fact[ -]sheet' scripts skills docs README.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$RESIDUE" -eq 0 ]; then
  note "no harvest vocabulary remains anywhere — this check has no subject left
      and its removal-signal has fired"
else
  ok "the $RESIDUE non-owner-facing occurrence(s) under scripts/ skills/ docs/
      README.md are report-only by declaration and do not fail this check"
fi

[ "$fail" -eq 0 ] || { echo; echo "owner-reaching vocabulary check FAILED."; exit 1; }
echo
echo "owner-reaching vocabulary check passed."
