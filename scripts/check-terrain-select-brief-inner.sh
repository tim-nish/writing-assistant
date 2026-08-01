#!/usr/bin/env sh
# parallel-safe
# covers: scripts/topic-map-directions.py scripts/terrain_text.py
#   scripts/terrain_brief.py scripts/terrain_select.py
#   scripts/terrain_screens.py
# tier: inner — brief-composition assertions against the committed fixture
#   map; no seam, no corpus, no assembly. Split from
#   check-terrain-select-inner.sh (#948): that check carried two subjects its
#   own header named — brief composition and indexed selection — and their
#   combined CLI invocations (~11 x ~150ms) sat at ~90% of INNER_MS, failing
#   intermittently on load variance. Each subject now holds its own check with
#   headroom; assertion content is unchanged. Measured 2026-07-30 at split:
#   ~0.9s (ceiling 2s); ~1.0s after Story 20.75 added the artifact-lifecycle
#   block (three more CLI runs, still well inside the ceiling).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-select-brief-inner.sh — brief composition through the real
# CLI: free-form wording, adopted candidates, and the stop outcome. The
# stage-0 hand-off assertions stay in the full check: they run the real
# pipeline. Indexed selection lives in check-terrain-select-index-inner.sh.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/topic-map-directions.py"
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cp "$FIX" "$work/map.json"

# One prep run writes the static answer fixtures (#950 batching: same data,
# fewer interpreter starts).
python3 - "$work" <<'PYEOF'
import json, os, sys
w = sys.argv[1]
json.dump({"selection": "name your own direction or combination axis",
           "free_text": "connect the retry storm to on-call load, through the retro"},
          open(w + "/answer-free.json", "w"))
json.dump({"selection": "stop here", "free_text": ""},
          open(w + "/answer-stop.json", "w"))
# A pre-#1208 artifact whose two carriers disagree (Story 20.141).
os.makedirs(w + "/ws2", exist_ok=True)
json.dump({"brief": "b", "thesis": {"state": "adopted"},
           "lifecycle": {"state": "composed",
                         "states": ["composed", "inspected", "adopted"],
                         "history": [{"state": "composed"}]}},
          open(w + "/ws2/brief.json", "w"))
PYEOF

# --- the CLI under test: candidates, then the three brief scenarios ---------
python3 "$D" candidates --map "$work/map.json" > "$work/cands.json"
python3 "$D" brief --answer "$work/answer-free.json" --map "$work/map.json" \
  --out "$work/ws/brief.json" > "$work/brief-free.json"

# The NAMED ARTIFACT's lifecycle (Story 20.75, #994): re-open it, record the
# forward transition, and prove the rewind is refused. Two extra CLI runs,
# batched here beside the composition runs for the same INNER_MS reason the
# header records.
python3 "$D" brief-open --at "$work/ws/brief.json" --state inspected \
  > "$work/brief-reopened.json"
if python3 "$D" brief-open --at "$work/ws/brief.json" --state inspected \
     > "$work/brief-rewind.json" 2>&1; then
  ok "a same-state re-open is not a rewind"
else
  err "re-opening at the current state was refused: $(cat "$work/brief-rewind.json")"
fi
if python3 "$D" brief-open --at "$work/ws/brief.json" --state adopted \
     > "$work/brief-adopted.json" 2>&1; then
  ok "the lifecycle advances to adopted"
else
  err "adopting was refused: $(cat "$work/brief-adopted.json")"
fi
if python3 "$D" brief-open --at "$work/ws/brief.json" --state inspected \
     > "$work/brief-back.json" 2>&1; then
  err "the lifecycle ran BACKWARDS from adopted to inspected"
else
  grep -q 'only moves forward' "$work/brief-back.json" \
    && ok "a backwards transition is refused, with the reason named" \
    || err "wrong rewind behaviour: $(cat "$work/brief-back.json")"
fi

# A PRE-#1208 ARTIFACT can carry an adopted thesis beside a composed
# lifecycle — the adoption act used to write one carrier without the other.
# `brief-open` DISCLOSES the disagreement per axis rather than silently
# preferring either carrier, and the disclosure is never stored
# (Story 20.141, #1208). The artifact is written by the prep run above and
# the disclosure asserted in the batched run below (#950): only the CLI run
# itself is added here.
python3 "$D" brief-open --at "$work/ws2/brief.json" \
  > "$work/brief-mismatch.json" 2>&1 \
  || err "opening a pre-#1208 artifact failed: $(cat "$work/brief-mismatch.json")"

# The selected-candidate answer derives from the candidates output, so it is
# written between CLI calls — one short run, then the brief call it feeds.
python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
sel = json.load(open(w + "/cands.json"))["candidates"][0]["direction"]
json.dump({"selection": sel, "free_text": ""}, open(w + "/answer-sel.json", "w"))
PYEOF
python3 "$D" brief --answer "$work/answer-sel.json" --map "$work/map.json" \
  > "$work/brief-sel.json"

if python3 "$D" brief --answer "$work/answer-stop.json" --map "$work/map.json" \
     > "$work/brief-stop.json" 2>&1; then
  err "stopping produced a brief"
else
  grep -q 'first-class outcome' "$work/brief-stop.json" \
    && ok "stopping produces no brief and no run, and says so" \
    || err "wrong stop behaviour: $(cat "$work/brief-stop.json")"
fi

# --- one assertion run over the produced files (#950 batching) --------------
python3 - "$work" <<'PYEOF' || fail=1
import json, os, sys
w = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

b = json.load(open(w + "/brief-free.json"))
check(b["brief"] == "connect the retry storm to on-call load, through the retro",
      "free-form wording becomes the brief verbatim")
check(b["provenance"] == "owner-authored" and b["origin"] == "free-form",
      "free-form wording is owner-authored, origin free-form")

b = json.load(open(w + "/brief-sel.json"))
check(b["origin"] == "adopted-candidate",
      "machine-proposed text the owner accepts records origin adopted-candidate")
check(b["provenance"] == "owner-authored",
      "an adopted candidate becomes OWNER-ADOPTED wording")

# --- Story 20.75 (#994): the brief is a NAMED ARTIFACT with a lifecycle -----
b = json.load(open(w + "/brief-free.json"))
# AC1 — the gate names the step that produced the brief.
check(bool((b.get("step") or {}).get("name"))
      and (b["step"].get("line") or "").startswith(b["step"]["name"]),
      "the brief names the STEP that produced it, not 'the message above'")
# AC2 — a durable artifact, at the stated path, actually on disk.
art = b.get("artifact") or {}
check(art.get("path") == os.path.join(w, "ws", "brief.json")
      and os.path.isfile(art["path"]),
      "the composed brief is WRITTEN, and the path is stated to the owner")
check(art.get("id") == "brief" and "brief-open" in (art.get("reopen") or ""),
      "the artifact carries its identity and how to re-open it")
# AC4 — re-openable. The contrast with the View is the point, so assert the
# reader exists AND that no rendering gained a cache alongside it.
r = json.load(open(w + "/brief-reopened.json"))
check(r["brief"] == b["brief"] and r["step"] == b["step"],
      "a written brief is read back whole — the never-read-back rule does "
      "not bind the owner's own decision")
# The composition moved into importable siblings (Story 20.80, #1029) while
# argparse and dispatch stayed in the hyphenated entry point. The two halves of
# this assertion do NOT take the same surface, and Story 20.81 (#1030) splits
# them for that reason:
#   * the ABSENCE half gets stronger the more text it reads, so it keeps the
#     whole surface — entry point plus siblings, as one text;
#   * the PRESENCE half gets WEAKER over a union (any one of four files could
#     satisfy it), so it names the module that owns the reader. Deleting
#     `read_brief_artifact` where it now lives has to fail here.
SURFACE = ("scripts/topic-map-directions.py", "scripts/terrain_brief.py",
           "scripts/terrain_select.py", "scripts/terrain_screens.py")
src = "".join(open(p, encoding="utf-8").read() for p in SURFACE)
owner = open("scripts/terrain_brief.py", encoding="utf-8").read()
check("def read_brief_artifact(" in owner
      and not any(t in src for t in ("read_view(", "load_view(", "VIEW_CACHE")),
      "exactly one reader exists, and it is the brief's — no View reader, "
      "no rendering cache")
# AC5 — the lifecycle is legible: the whole ordered sequence, current state
# marked. Not the current state alone, which says nothing about what follows.
for tag, payload, want in (("composed", b, "composed"),
                           ("reopened", r, "inspected"),
                           ("adopted", json.load(open(w + "/brief-adopted.json")),
                            "adopted")):
    life = payload.get("lifecycle") or {}
    check(life.get("state") == want
          and life.get("states") == ["composed", "inspected", "adopted"]
          and f"[{want}]" in (life.get("line") or ""),
          f"the {tag} brief states its lifecycle with {want} current")
# AC6 — nothing downstream can tell the difference: the hand-off is still the
# brief STRING, and no new field reaches the stage-0 path.
check(r["brief"] == "connect the retry storm to on-call load, through the retro"
      and "--brief" in b.get("next", ""),
      "the stage-0 hand-off is the same brief string — no new entry pipeline")
# Story 20.141 (#1208) — a pre-fix artifact's disagreeing carriers are
# disclosed per axis, and the disclosure never reaches the stored artifact.
cm = (json.load(open(w + "/brief-mismatch.json")).get("lifecycle")
      or {}).get("carrier_mismatch") or {}
check(cm.get("thesis_state") == "adopted"
      and cm.get("lifecycle_state") == "composed"
      and "per axis" in (cm.get("precedence") or ""),
      "disagreeing carriers on a pre-fix artifact are disclosed, per axis")
check("carrier_mismatch" not in (json.load(open(w + "/ws2/brief.json"))
                                 .get("lifecycle") or {}),
      "...and the disclosure is composed at read time, never stored")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- the transition is ANNOUNCED (Story 20.116, #1113) ----------------------
python3 - <<'PY_TR' || fail=1
import importlib.util, os, sys
sys.path.insert(0, "scripts")
def load(n, p):
    sp = importlib.util.spec_from_file_location(n, p)
    m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
tt = load("terrain_text", "scripts/terrain_text.py")
tmd = load("tmd", "scripts/topic-map-directions.py")

bad = []
def need(c, m):
    if not c: bad.append(m)

WS = "/state/wa/host-qualified/terrain-runs/20260801T091400-250105"
AP = WS + "/brief.json"
b = tt._brief_transition_banner("composed", artifact_path=AP, workspace=WS)
lines = b.split("\n")

need(tt.BRIEF_STEP_ID in b,
     "the banner names the step ID — the act the owner refers to, not 'the "
     "message above'")
need(AP in lines and WS in lines,
     "the artifact path and the run workspace each render WHOLE on their own "
     "line (#1117): a banner that exists because the owner could not verify a "
     "transition must not hand them an elided path")
need(any(l.startswith("Lifecycle:") and "[composed]" in l for l in lines),
     "the banner carries the lifecycle line with the current state legible — "
     "the #1075-era form is REUSED, never replaced")

# It quotes state; it does not narrate one.
b2 = tt._brief_transition_banner("adopted", artifact_path=AP)
need("[adopted]" in b2 and "now: adopted" in b2,
     "the banner renders the state it was given, so display and record cannot "
     "disagree about which state the brief is in")

# The banner is NOT stored: it renders lifecycle + path, both already kept.
need("banner" in tmd.RENDERED_KEYS.get("lifecycle", ()),
     "the banner is stripped from the stored artifact — a stored rendering is "
     "the frozen copy Story 20.100 removed everywhere else")
need("transition" not in tmd.RENDERED_KEYS,
     "no new top-level key: the brief payload's key set is a CLOSED contract")
need("banner" not in tmd.RENDERED_KEYS.get("step", ()),
     "the banner is NOT on `step`, which is asserted invariant across a "
     "re-open — it quotes the current state, so it varies with `lifecycle`")
rec = tmd._decision_record({
    "step": {"id": "x", "name": "y", "line": "L"},
    "lifecycle": {"state": "adopted", "states": list(tt.BRIEF_LIFECYCLE),
                  "line": "L", "banner": "STALE",
                  "history": [{"state": "adopted"}]},
    "artifact": {"path": AP, "line": "A", "read_back": "r"},
    })
need("banner" not in rec.get("lifecycle", {}), "no banner reaches storage")
tmd._rehydrate_lines(rec)
need("[adopted]" in rec["lifecycle"]["banner"],
     "a re-opened brief recomposes the banner from the lifecycle it KEPT, so a "
     "stale stored state cannot be served back")
need(AP in rec["lifecycle"]["banner"].split("\n"),
     "...and the recomposed banner still renders the path whole")

for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY_TR
[ $? -eq 0 ] && ok "the Terrain->Brief transition is announced, quoted from machine state, and never stored"

# --- the adopt record ATTESTS (Story 20.120, #1118) -------------------------
python3 - <<'PY_AT' || fail=1
import importlib.util, sys
sys.path.insert(0, "scripts")
sp = importlib.util.spec_from_file_location("tmd", "scripts/topic-map-directions.py")
tmd = importlib.util.module_from_spec(sp); sp.loader.exec_module(tmd)

bad = []
def need(c, m):
    if not c: bad.append(m)

els = [{"kind": "lesson", "slug": "s%d" % i, "title": "t%d" % i,
        "tags": ["workflow"], "gloss": "g%d" % i} for i in range(3)]
MAP = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
       "elements": els}
cands = tmd.candidates(MAP)
ids = [c["id"] for c in cands][:2]

# An owner who NAMED a candidate.
named = tmd.brief_from_answer(
    {"index": ", ".join(ids), "note": "my angle", "claim": "the adopted thesis",
     "adopted": "B", "pin": "h@abc1234"}, cands, "h@abc1234", MAP)
# A machine default over the same set: same members, no adopted claim.
silent = tmd.brief_from_answer(
    {"index": ", ".join(ids), "note": "my angle", "pin": "h@abc1234"},
    cands, "h@abc1234", MAP)

need(named.get("answer_as_given") == "B",
     "the owner's utterance is not recorded — the record cannot say THAT the "
     "owner named B, only what B resolved to")
need(named.get("thesis_origin") == "adopted-candidate",
     "an owner-adopted thesis is not recorded as such")
need(silent.get("thesis_origin") == "coverage-statement",
     "a machine coverage statement claims an adopted origin")
need(named.get("thesis_origin") != silent.get("thesis_origin")
     or named.get("answer_as_given") != silent.get("answer_as_given"),
     "an owner-named adoption is INDISTINGUISHABLE from a silent one on the "
     "artifact alone — this is the whole of #1118")
need(silent.get("answer_as_given") is None,
     "an absent utterance is recorded as absence, never filled in")

# `origin` is a different axis and must not be repurposed.
need(named.get("origin", "").startswith("adopted-index"),
     "`origin` stopped recording how the MEMBERS were selected — it is a "
     "different axis from thesis_origin and collapsing them loses a fact")

# The note declares which question it answered.
need(named.get("note_is") and "adopted over" in named["note_is"],
     "a note carried from the selection gate is presented as though typed at "
     "the adoption gate (#1118's second record oddity)")
need(silent.get("note_is") and "with this answer" in silent["note_is"],
     "a note recorded with its own answer is not declared as such")

for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY_AT
[ "$fail" -eq 0 ] && ok "the adopt record distinguishes an owner-named adoption from a silent one"

# --- the lifecycle renders its TRAVERSAL too (Story 20.121, #1118) ----------
python3 - <<'PY_TV' || fail=1
import importlib.util, sys
sys.path.insert(0, "scripts")
def load(n, p):
    sp = importlib.util.spec_from_file_location(n, p)
    m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
tt = load("terrain_text", "scripts/terrain_text.py")
tb = load("terrain_brief", "scripts/terrain_brief.py")

bad = []
def need(c, m):
    if not c: bad.append(m)

# THE OBSERVED RUN: composed -> adopted, `inspected` never entered.
skipped = tt._brief_traversal_line([{"state": "composed"}, {"state": "adopted"}])
need("composed → adopted" in skipped,
     "the traversal does not render the states actually entered")
need("Never entered: inspected" in skipped,
     "a state the run SKIPPED is not stated as skipped — bracketing marks "
     "where the owner IS, never where they HAVE BEEN, which is how "
     "`inspected` rendered as though it had occurred (#1118)")

full = tt._brief_traversal_line([{"state": s} for s in tt.BRIEF_LIFECYCLE])
need("Never entered" not in full,
     "a brief that entered every state still reports skips")

# THE FORWARD MAP IS UNCHANGED — rendering history INSTEAD was refused.
line = tt._brief_lifecycle_line("adopted")
need(line == "Lifecycle: composed → inspected → [adopted] — now: adopted.",
     "the forward map changed — Story 20.121 ADDS the traversal beside it and "
     "must not replace it; the docstring's reason (one word out of three tells "
     "the owner nothing about what comes next) is untouched by this story")

# Both render, from the same block, and the traversal is not stored.
blk = tb._brief_lifecycle("adopted", [{"state": "composed"}, {"state": "adopted"}])
need(blk.get("line") and blk.get("traversal"),
     "the lifecycle block does not carry BOTH the map and the traversal")
need("Never entered: inspected" in blk["traversal"],
     "the block's traversal disagrees with its own history")

for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY_TV
[ "$fail" -eq 0 ] && ok "the lifecycle renders what happened beside what comes next"

# --- Story 20.125 (#1145): the artifact's key set is an ALLOWLIST ------------
# The two prior fixes removed named keys and the class returned under new names
# both times. What is asserted here is the SHAPE of the guard, not a key list:
# an unlisted key must REFUSE (a silent strip is the same denial shape one
# layer down), and a brief written before the allowlist must still open.
python3 - <<'PY_AL' || fail=1
import sys, json, tempfile, os
sys.path.insert(0, "scripts")
import terrain_brief as tb

bad = []
def need(c, m):
    if not c: bad.append(m)

need(isinstance(tb.BRIEF_KEYS, frozenset) and tb.BRIEF_KEYS,
     "BRIEF_KEYS is not a declared, non-empty set")
tmp = tempfile.mktemp(suffix=".json")
try:
    tb.write_brief_artifact(tmp, {"brief": "b", "a_new_payload": {"x": 1}})
    bad.append("an unlisted key was WRITTEN — the allowlist does not refuse, "
               "which is the denial-list shape the story exists to remove")
except ValueError as e:
    need("a_new_payload" in str(e),
         "the refusal does not NAME the offending key, so the next author "
         "cannot tell which field to decide about")
    need(not os.path.exists(tmp),
         "a refused write left a file behind")
# The listed set still writes.
tb.write_brief_artifact(tmp, {"brief": "b", "members": [], "pins": {}})
need(json.load(open(tmp))["brief"] == "b",
     "a conforming artifact no longer writes")
for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY_AL
[ "$fail" -eq 0 ] && ok "the brief artifact REFUSES an unlisted key, naming it"

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
