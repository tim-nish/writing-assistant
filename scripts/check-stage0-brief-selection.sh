#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-08-03 (story 20.192) — every path this check touches
# is under one `mktemp -d`: the host repo, its `XDG_STATE_HOME` (so the run
# workspaces are the fixture's) and the Brief home, which is resolved from
# that host root. No other check reads them, and nothing outside is written.
# tier: full — end-to-end stage0 invocations over a fixture host repo (#913)
# covers: scripts/draft-pipeline.py scripts/draft_brief.py scripts/draft_gates.py
# removal-signal: the Brief home stops being enumerable — a stage-0 entry can
#   no longer reach more than one Brief — at which point there is nothing for a
#   selection gate to enumerate and both this check and the gate retire
#   together. A narrowing of the payload's shape alone is NOT the signal:
#   check-gate-payload-carrier.sh owns that, and this file owns the branch.
# check-stage0-brief-selection.sh — a cold stage-0 entry over a home holding
# Briefs ASKS which one (story 20.192, #1343; SPEC-terrain amendments, the
# 2026-08-03 block, clause (b)).
#
# WHAT WAS WRONG. The only routes into a brief-carrying run were the
# same-sitting terrain handoff, `open the brief` — which defaults to the most
# recent workspace — and a hand-typed path. Multiple accepted Briefs are the
# design ("k accepted briefs feed the drafting backlog — one run at a time,
# never k"), so the k-th Brief was reachable only by typing a state-dir path,
# and the amendment says such a gate "fails the gate-input contract in the
# same act as offering no gate at all".
#
# WHY THESE ASSERTIONS. The gate's existence is checkable at the builder
# (check-gate-payload-carrier.sh iterates the registry); what is NOT checkable
# there is the BRANCH — that a cold entry raises it, that an explicit --brief
# does not, that an empty home states its absence and proceeds rather than
# blocking, and that the ask leaves a row where an audit can find it. Each is a
# stage-0 invocation, so they are asserted end to end.

set -u
cd "$(dirname "$0")/.."
DP="scripts/draft-pipeline.py"
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
printf 'sources:\n  - path: .\n' > "$host/writing-sources.yaml"
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME

# --- AC4: an EMPTY home is a fact, not a blocker -----------------------------
out=$(python3 "$DP" stage0 F2 specs/ --root "$host") \
  || { err "stage0 failed over an empty Brief home"; printf '\nFAILED.\n' >&2; exit 1; }
echo "$out" | jget 'd.get("brief_selection","")' | grep -q "no Briefs" \
  && ok "AC4: an empty home is STATED in the run's own output" \
  || err "AC4: an empty home is silent — absence is a finding, not a nothing"
echo "$out" | jget 'd.get("brief_selection_required")' | grep -q None \
  && ok "AC4: ...and no gate is raised over an empty enumeration" \
  || err "AC4: a gate was raised with no Briefs to choose between"
echo "$out" | jget 'd.get("checkpointed")' | grep -q True \
  && ok "AC4: ...and the run proceeds cold, checkpointed as before" \
  || err "AC4: the cold run did not proceed — an empty home blocked it"

# The home is the RESOLVER'S, and the fixture Briefs go through the SANCTIONED
# WRITER: this check must not learn the layout or the record's shape.
home=$(python3 scripts/resolve-paths.py terrain-briefs-dir --root "$host")
mkdir -p "$home"
python3 - "$home" <<'PY' || { err "fixture Briefs were not written"; printf '\nFAILED.\n' >&2; exit 1; }
import importlib.util, sys
s = importlib.util.spec_from_file_location("tb", "scripts/terrain_brief.py")
tb = importlib.util.module_from_spec(s); s.loader.exec_module(tb)
for i in range(3):
    tb.write_brief_record(
        {"brief": "cover the retry storm and how the judge missed it, %d" % i,
         "indexes": ["L1", "L%d" % i],
         "pins": {"terrain": "h@abc1234", "hub": "hub@def5678"},
         "adopted_claim": "the judge missed the retry storm, %d" % i,
         "lifecycle": {"state": "adopted",
                       "history": [{"state": "adopted",
                                    "at": "2026-08-0%dT10:00:00" % (i + 1)}]}},
        None, sys.argv[1])
PY

# --- AC1: the Briefs are OFFERED, machine-composed, nothing pre-selected -----
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" --fresh) \
  || { err "stage0 failed over a populated Brief home"; printf '\nFAILED.\n' >&2; exit 1; }
echo "$out" > "$work/gate.json"
python3 - "$work" <<'PY' || fail=1
import json, sys
d = json.load(open(sys.argv[1] + "/gate.json"))
bad = 0


def check(cond, msg):
    global bad
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stderr if not cond else sys.stdout)
    bad = bad or (0 if cond else 1)


check(d.get("brief_selection_required") is True,
      "AC1: a cold entry over a populated home declares the selection due")
item = (d.get("items") or [{}])[0]
labels = [c["label"] for c in item.get("choices", [])]
check(len(labels) == 4,
      "AC1: the three Briefs are offered, plus the option that negates the "
      "premise (start cold): %s" % labels)
# THE OPTIONS ARE COMPOSED FROM THE RECORDS, not from filenames: each label
# carries content only the brief record holds.
check(all("retry storm" in c["label"] for c in item["choices"][:3]),
      "AC1: the options are composed from the brief RECORDS' own content")
check(all(c["effect"].startswith("drafts from brief-")
          for c in item["choices"][:3]),
      "AC1: ...and each option carries the evidence bearing on it — the "
      "Brief's own stable id, which is also the address")
check(item.get("free_text") is True,
      "AC1: the free-form override is intact — an enumeration that replaces "
      "free text closes the path to a Brief the machine could not read")
check(item["render"].get("recommended") is None
      and not any("recommended" in c for c in item["choices"]),
      "AC1: NOTHING is pre-selected and nothing is ranked")
check(bool(item.get("no_recommendation")),
      "AC1: ...and the absent ranking is DECLARED, not merely missing (#1222)")
check(d.get("checkpointed") is None,
      "the run is not attached to until the Brief is known — no checkpoint is "
      "written on the gate path")
json.dump(d, open(sys.argv[1] + "/parsed.json", "w"))
sys.exit(bad)
PY

# --- AC2: the gate is DECLARED and leaves an ask row -------------------------
ws=$(echo "$out" | jget 'd["ws"]')
python3 - "$ws" <<'PY' || fail=1
import importlib.util, json, os, sys
ws = sys.argv[1]
s = importlib.util.spec_from_file_location("dg", "scripts/draft_gates.py")
dg = importlib.util.module_from_spec(s); s.loader.exec_module(dg)
bad = 0
if "brief-selection" not in dg.GATES:
    print("FAIL: AC2: the gate is not declared in the registry — a gate with "
          "no declaration is the defect the registry exists to make "
          "impossible", file=sys.stderr)
    bad = 1
elif dg.GATES["brief-selection"]["stage"] not in dg.PROCESSES:
    print("FAIL: AC2: the gate's stage is not one of the declared process "
          "names", file=sys.stderr)
    bad = 1
else:
    print("ok:   AC2: the gate is declared in the registry, at a declared "
          "process")
rows = [json.loads(l) for l in
        open(os.path.join(ws, "presented-payloads.jsonl"), encoding="utf-8")]
row = [r for r in rows if r.get("gate") == "brief-selection"]
if not row:
    print("FAIL: AC2: the gate left NO ask row in the run's payload log — the "
          "surface reached the owner with nothing an audit could find",
          file=sys.stderr)
    bad = 1
else:
    print("ok:   AC2: the ask row is in the run's own payload log")
    if row[0].get("kind") != "ask" or not row[0]["items"][0].get("render"):
        print("FAIL: AC2: the row is not an ASK carrying a render directive",
              file=sys.stderr)
        bad = 1
    else:
        print("ok:   AC2: ...marked as an ask, carrying its render directive")
sys.exit(bad)
PY

# --- AC3: an explicit --brief raises NO gate ---------------------------------
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" --fresh --brief "an explicit brief")
echo "$out" | jget 'd.get("brief_selection_required")' | grep -q None \
  && ok "AC3: an explicit --brief raises no gate" \
  || err "AC3: an explicit --brief raised the selection gate anyway"
echo "$out" | jget 'd["run_state"]["brief"]["text"]' | grep -q "an explicit brief" \
  && ok "AC3: ...and the brief-carrying entry behaves exactly as today" \
  || err "AC3: the explicit brief did not reach run state"
echo "$out" | jget 'd.get("checkpointed")' | grep -q True \
  && ok "AC3: ...checkpointed in the same invocation, as before" \
  || err "AC3: the brief-carrying entry stopped checkpointing"

[ "$fail" = "0" ] && printf '\nAll stage0 brief-selection checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
