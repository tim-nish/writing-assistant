#!/usr/bin/env sh
# parallel-safe
# tier: full — end-to-end probe invocations over a fixture host repo (#913)
# covers: scripts/probe.py skills/draft-article/stages/stage1.md
# removal-signal: stage 1 stops being probe (a later amendment replaces or
#   folds it), at which point these assertions have no subject and retire with
#   the stage.
# check-probe.sh — probe is the stage-1 feasibility check (Story 20.146,
# #1210; umbrella #1182): a verdict plus a handful of anchors, NO fact sheet,
# coverage over every declared source, and a doomed article dying early.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

PR="$root/scripts/probe.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$PR', doraise=True)" \
  && ok "probe compiles" || { err "probe syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host/docs"
git -C "$host" init -q
printf 'one\ntwo\nthree\n' > "$host/docs/a.md"
git -C "$host" add -A
git -C "$host" -c user.email=t@t -c user.name=t commit -qm seed
sha=$(git -C "$host" rev-parse --short HEAD)
printf 'sources:\n  - path: docs\n' > "$host/writing-sources.yaml"
WS="$work/ws"; mkdir -p "$WS"

# --- the surface reads THROUGH the typed source model (AC3) ------------------
python3 "$PR" surface --root "$host" > "$work/surface.json"
python3 - "$work/surface.json" <<'PY' && ok "surface: typed entries with derived time_axis and coverage ids" || err "surface lacks the typed model's shape"
import json, sys
d = json.load(open(sys.argv[1]))
e = d["entries"][0]
assert e["type"] == "path" and e["time_axis"] is False and e["id"] == "path:docs", e
assert any(f.endswith("docs/a.md") for f in d["files"]), d["files"]
PY

# --- grounded: anchors resolve, coverage total, no fact sheet (AC1) ----------
printf '{"verdict":"grounded","anchors":[{"pointer":"docs/a.md:2","for":"the claim"},{"pointer":"%s","for":"the change"}],"coverage":{"consulted":["path:docs"],"unreached":[]}}' "$sha" \
  | python3 "$PR" record --ws "$WS" --root "$host" - > "$work/rec.json" \
  && ok "record: a grounded result with resolvable anchors is accepted" \
  || err "a valid grounded result was refused"
jget 'd["next_stage"]' < "$work/rec.json" | grep -q interview \
  && ok "record: grounded routes next_stage=interview" || err "grounded did not route to interview"
[ -f "$WS/probe.json" ] && ok "record: probe.json persisted in the run workspace" || err "probe.json missing"
[ ! -f "$WS/fact-sheet.md" ] && ok "no artifact of harvest's shape exists in the workspace (#1182)" \
  || err "a fact sheet appeared — harvest's shape is retired"
jget 'd["next_stage"]' < "$WS/checkpoint.json" | grep -q interview \
  && ok "record: the checkpoint is routed in the same invocation" || err "checkpoint not routed"

# slim profile routes to fill
printf '{"verdict":"grounded","anchors":[{"pointer":"docs/a.md:1"}],"coverage":{"consulted":["path:docs"],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS" --root "$host" --framework working-note - \
  | jget 'd["next_stage"]' | grep -q fill \
  && ok "record: the slim profile routes next_stage=fill" || err "slim routing broken"

# --- refusals: the tool validates, it never judges ---------------------------
printf '{"verdict":"maybe","anchors":[],"coverage":{"consulted":["path:docs"],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS" --root "$host" - 2>"$work/e1" \
  && err "a third verdict was accepted" || ok "refused: a verdict is grounded or ungrounded, nothing third"
printf '{"verdict":"grounded","anchors":[{"pointer":"docs/a.md:99"}],"coverage":{"consulted":["path:docs"],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS" --root "$host" - 2>"$work/e2" \
  && err "an out-of-range anchor was accepted" || ok "refused: an anchor must resolve (line inside the file)"
printf '{"verdict":"grounded","anchors":[{"pointer":"../outside.md:1"}],"coverage":{"consulted":["path:docs"],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS" --root "$host" - 2>/dev/null \
  && err "an outside-the-surface anchor was accepted" || ok "refused: an anchor points inside the declared surface only"
printf '{"verdict":"grounded","anchors":[{"pointer":"docs/a.md:1"}],"coverage":{"consulted":[],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS" --root "$host" - 2>"$work/e3" \
  && err "a coverage gap was accepted" || ok "refused: coverage accounts for every declared source (AC3)"
grep -q "path:docs" "$work/e3" && ok "...naming the unaccounted source" || err "the gap is not named"
printf '{"verdict":"grounded","anchors":[],"coverage":{"consulted":["path:docs"],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS" --root "$host" - 2>/dev/null \
  && err "grounded-with-no-anchor was accepted" || ok "refused: a grounded verdict carries at least one anchor"
python3 - <<PY | python3 "$PR" record --ws "$WS" --root "$host" - 2>/dev/null \
  && err "more than a handful of anchors was accepted" || ok "refused: anchors are a handful (cap), never a sheet"
import json
print(json.dumps({"verdict": "grounded",
                  "anchors": [{"pointer": "docs/a.md:1"}] * 8,
                  "coverage": {"consulted": ["path:docs"], "unreached": []}}))
PY

# an unreached source needs its WHY
printf '{"verdict":"grounded","anchors":[{"pointer":"docs/a.md:1"}],"coverage":{"consulted":[],"unreached":[{"source":"path:docs"}]}}' \
  | python3 "$PR" record --ws "$WS" --root "$host" - 2>/dev/null \
  && err "an unreached source without a why was accepted" \
  || ok "refused: an unreachable source is a finding — it carries its why"

# --- a doomed article dies early (AC2) ---------------------------------------
WS2="$work/ws2"; mkdir -p "$WS2"
printf '{"stage":"stage0","next_stage":"probe","run_state":{"framework":"F2"}}' > "$WS2/checkpoint.json"
printf '{"verdict":"ungrounded","reasons":["the brief needs episode claims and no declared source carries a time axis"],"anchors":[],"coverage":{"consulted":["path:docs"],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS2" --root "$host" - > "$work/dead.json" \
  && ok "record: an ungrounded result is recordable" || err "ungrounded result refused"
jget 'd["next_stage"]' < "$work/dead.json" | grep -q done \
  && ok "ungrounded: the run stops (next_stage=done) before interview or structure work" \
  || err "an ungrounded run kept going"
jget 'd["stopped"]' < "$work/dead.json" | grep -q "before any interview" \
  && ok "...stating the stop" || err "the stop is not stated"
jget 'd["run_state"]["framework"]' < "$WS2/checkpoint.json" | grep -q F2 \
  && ok "...with the prior checkpoint state preserved, nothing deleted" \
  || err "the checkpoint lost its run_state"
printf '{"verdict":"ungrounded","reasons":[],"anchors":[],"coverage":{"consulted":["path:docs"],"unreached":[]}}' \
  | python3 "$PR" record --ws "$WS2" --root "$host" - 2>/dev/null \
  && err "a bare ungrounded stop was accepted" || ok "refused: an ungrounded verdict carries its reasons"

# --- checkpoint/resume contract is declared (AC4) ----------------------------
grep -q "Checkpoint/resume contract" skills/draft-article/stages/stage1.md \
  && ok "stage1.md declares probe's checkpoint/resume contract" \
  || err "stage 1 declares no resume contract — an interruptible stage without one is a gap"
grep -q "next_stage: probe" skills/draft-article/stages/stage1.md \
  && ok "...naming where an interrupted probe resumes" || err "...that names no resume point"

# --- stage wiring: the mint points at probe, no consume step at stage 1 ------
python3 - <<'PY' && ok "the stage-0 mint routes a fresh run to probe" || err "the fresh-run mint does not point at probe"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
state, code = dp._run_state("F2", ["docs/"], None)
assert state["next_stage"] == "probe", state
PY
grep -q "consume <harvest-doc>" skills/draft-article/stages/stage1.md skills/draft-article/SKILL.md \
  && err "stage 1 still instructs consuming a harvest document" \
  || ok "no stage instructs consuming a harvest document (#1182)"

[ "$fail" -eq 0 ] && printf '\nAll probe checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
