#!/usr/bin/env sh
# parallel-safe
# covers: scripts/topic-map-directions.py scripts/terrain_text.py
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
import json, sys
w = sys.argv[1]
json.dump({"selection": "name your own direction or combination axis",
           "free_text": "connect the retry storm to on-call load, through the retro"},
          open(w + "/answer-free.json", "w"))
json.dump({"selection": "stop here", "free_text": ""},
          open(w + "/answer-stop.json", "w"))
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
src = open("scripts/topic-map-directions.py", encoding="utf-8").read()
check("def read_brief_artifact(" in src
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
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
