#!/usr/bin/env sh
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# removal-signal: the terrain area's harnesses are retired or subsumed by the
#   #857/#858 seam under the #910 retention sweep; removed with that pass.
# check-topic-map-screen.sh — the END-TO-END half of the screen harness
# (Story 20.49, #923 split): everything here needs the real pipeline — the
# fixture repos, resolve-writing-sources, a live `terrain_map.py assemble`,
# and `draft-pipeline.py stage0`. The composition/selection/view assertions
# that only need a map JSON run per edit in the inner tier instead:
#   scripts/check-terrain-compose-inner.sh   (candidates, ONE screen, size switch)
#   scripts/check-terrain-view-inner.sh      (View content, wording, write-only, owner language)
#   scripts/check-terrain-select-inner.sh    (brief composition, indexed selection)
#   scripts/check-terrain-code-inner.sh      (source-level absences, SKILL lockstep, axes)
# Those run against the committed fixture map
# (scripts/fixtures/terrain/screen-map.json); the DRIFT GUARD below re-derives
# that map from this file's fixture repos on every run and fails if the
# committed copy no longer matches, so the inner tier can never silently test
# a stale shape. The sibling-harness re-run this file used to carry
# (check-topic-map.sh / check-topic-map-depth.sh "pass unchanged") is gone:
# the tiered runner executes every check in the same full-tier run, so the
# re-run asserted nothing the suite does not already assert, at double cost.
#
# Original contract coverage (CAP-3 and its amendments) is unchanged in
# SUBSTANCE and split in PLACE — every assertion the pre-split file carried
# runs either here or in the named inner checks (Story 20.49 AC3).
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/terrain_map.py"
D="scripts/topic-map-directions.py"
DP="scripts/draft-pipeline.py"
VP="scripts/validate-proposal-payload.py"
SKILL="skills/terrain/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$D', doraise=True)" 2>/dev/null \
  && ok "topic-map-directions compiles" \
  || { err "syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME
mkdir -p "$work/ws"

h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts" "$a/backlog" "$a/plans" "$a/graveyard"
git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1
# Stage 0 validates the declared sources before it accepts a brief, so the host
# repo carries one readable source file and the config declares it.
mkdir -p "$h/docs"
# The filename is deliberately unrelated to any backlog item's evidence
# pointers: since Story 18.65 a declared source is itself a map surface, so a
# host doc named `notes.md` would share the `notes` pointer subject with the
# `staffing` subtopic below and legitimately earn a combination — defeating the
# "never combined on a hunch" assertion, which is about UNRELATED subtopics.
printf '# intake\n\nThe retry storm doubled token spend.\n' > "$h/docs/intake.md"
git -C "$h" add -A >/dev/null 2>&1
git -C "$h" -c user.email=t@e -c user.name=t commit -qm init >/dev/null 2>&1
srcfile="$work/xdg/writing-assistant/repos/$(python3 "$root/scripts/resolve-paths.py" repo-key --root "$h")/writing-sources.yaml"
python3 - "$srcfile" "$a/drafts/" <<'PYEOF'
import sys
open(sys.argv[1], "w", encoding="utf-8").write(
    "sources:\n  - path: docs\noutput:\n  drafts: %s\n" % sys.argv[2])
PYEOF

# Two subtopics in DIFFERENT topics that share an evidence source — the shape a
# cross-topic combination must be proposed from.
cat > "$a/backlog/retry-storm.md" <<'EOF'
---
slug: retry-storm
title: Retry storms
status: shaping
track: engineering
subtopic: retry-behaviour
evidence:
  - host/retro.md:12@abc1234
  - host/log.txt:88@abc1234
  - host/bench.md:3@abc1234
lessons:
  - lesson:retry-storm
---
EOF
cat > "$a/backlog/oncall-load.md" <<'EOF'
---
slug: oncall-load
title: On-call load
status: seed
track: people
subtopic: oncall
evidence:
  - host/retro.md:44@abc1234
  - host/rota.md:7@abc1234
---
EOF
# A third, unrelated subtopic with nothing shared.
cat > "$a/backlog/team-shape.md" <<'EOF'
---
slug: team-shape
title: Team shape
status: seed
track: people
subtopic: staffing
evidence:
  - host/notes.md:9@abc1234
---
EOF

python3 "$M" assemble --root "$h" > "$work/raw-map.json" 2>"$work/m.err" \
  || { err "map assembly failed: $(cat "$work/m.err")"; printf '\nFAILED.\n' >&2; exit 1; }
# STRANDS ARE THE ONLY UNIT since the cluster removal (Story 20.7, #809), so
# the small fixture must carry some. The backlog items above no longer produce
# candidates on their own — clustering was their only path to one — which is a
# real consequence of the removal, not a fixture quirk: `articles-items` are
# tracking data, and article MATERIAL is Lessons and Journeys.
python3 - "$work/raw-map.json" > "$work/map.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["elements"] = [
    {"kind": "lesson", "slug": "retry-storm", "title": "The retry storm",
     "topic": "engineering", "date": "2026-07-20",
     "gloss": "Retries without a budget turn one slow dependency into an outage",
     "situation": "LESSONS.md:3@abc1234",
     "evidence": ["LESSONS.md:3@abc1234"], "consumed": False},
    {"kind": "lesson", "slug": "team-shape", "title": "Team shape",
     "topic": "people", "date": "2026-07-19",
     "gloss": "A rota that nobody owns is a rota that silently stops",
     "situation": "LESSONS.md:4@abc1234",
     "evidence": ["LESSONS.md:4@abc1234"], "consumed": False},
]
d["coverage"] = dict(d.get("coverage", {}),
                     element_topics_read=["engineering", "people"],
                     element_topics_skipped=[])
print(json.dumps(d))
PYEOF
ok "fixture: the map assembles"

# --- ONE screen, presentable, free-form every time ---------------------------
python3 "$D" payload --map "$work/map.json" > "$work/payload.json"
python3 "$VP" --ws "$work/ws" --surface topic-map "$work/payload.json" > "$work/ask.json" \
  && ok "the screen passes validate-proposal-payload.py before presentation" \
  || err "the screen is not presentable: $(cat "$work/ask.json")"

# --- DRIFT GUARD: the committed inner-tier fixture is this map ---------------
# Compare the freshly assembled map (paths and pin are per-run values and are
# excluded) against scripts/fixtures/terrain/screen-map.json. A real change to
# the map's shape lands here first: update the committed fixture in the same
# change, and the inner checks follow.
python3 - "$work/map.json" "scripts/fixtures/terrain/screen-map.json" <<'PYEOF' \
  && ok "drift guard: the committed inner-tier fixture matches a fresh assembly" \
  || err "the committed fixture has drifted from a fresh assembly — regenerate scripts/fixtures/terrain/screen-map.json (Story 20.49)"
import json, sys
def norm(p):
    d = json.load(open(p))
    for k in ("articles_repo", "host_root", "recording_target"):
        d.pop(k, None)
    d.get("coverage", {}).pop("pin", None)
    return d
a, b = norm(sys.argv[1]), norm(sys.argv[2])
if a != b:
    ka = {k for k in a if a[k] != b.get(k)} | {k for k in b if k not in a}
    print("drift in keys: %s" % sorted(ka), file=sys.stderr)
    sys.exit(1)
PYEOF

python3 - "$work/map.json" > "$work/big-map.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
# An OVER-BUDGET terrain, built from STRANDS (Story 20.7, #809). It used to be
# built by cloning subtopics; subtopics no longer exist, and a Strand is now
# the only thing that counts toward the screen budget.
strands = list(d.get("elements") or [])
for n in range(12):                       # comfortably past the screen budget
    strands.append({
        "kind": "lesson", "slug": f"widened-{n:02d}",
        "title": f"Lesson {n}",
        # Two topics, so topic-spanning rendering is still exercised.
        "topic": "engineering" if n % 2 else "people",
        "date": f"2026-07-{(n % 28) + 1:02d}",
        "gloss": f"A claim the material itself makes, number {n}",
        "situation": f"LESSONS.md:{n + 10}@abc1234",
        "evidence": [f"LESSONS.md:{n + 10}@abc1234"],
        "consumed": (n == 0),
    })
# A strand whose rendering was NOT served: it must still appear, with the
# reason disclosed, never dropped and never quoting the one-liner as a gloss.
strands.append({
    "kind": "lesson", "slug": "no-rendering", "title": "Unrendered lesson",
    "topic": "people", "date": "2026-07-02",
    "gloss": None,
    "gloss_unavailable": "the served gloss index carries no rendering for this lesson",
    "situation": "LESSONS.md:40@abc1234",
    "evidence": ["LESSONS.md:40@abc1234"], "consumed": False,
})
d["elements"] = strands
d["coverage"] = dict(d.get("coverage", {}),
                     element_topics_read=["delivery", "engineering", "people", "nowhere"],
                     element_topics_skipped=["zeta"])
print(json.dumps(d))
PYEOF

# --- the hand-off is the EXISTING stage-0 --brief path -----------------------
# (brief composition itself is asserted in check-terrain-select-inner.sh; here
# a brief is composed only as the input to the REAL stage-0 run.)
printf '%s' '{"selection":"name your own direction or combination axis","free_text":"connect the retry storm to on-call load, through the retro"}' \
  > "$work/answer-free.json"
python3 "$D" brief --answer "$work/answer-free.json" --map "$work/map.json" \
  > "$work/brief-free.json" || err "brief composition failed"
brief=$(python3 -c "import json;print(json.load(open('$work/brief-free.json'))['brief'])")
mkdir -p "$work/ws2"
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$brief" --root "$h" \
  > "$work/stage0.json" 2>"$work/e-stage0" \
  || { err "the brief-carrying run did not start: $(cat "$work/e-stage0")"; }
python3 -c "
import json
o=json.load(open('$work/stage0.json'))
b=(o.get('run_state') or {}).get('brief') or {}
assert b.get('text')=='$brief', b
assert b.get('provenance')=='owner-authored', b
" && ok "stage 0 receives the brief through its existing --brief path, owner-authored" \
  || err "the hand-off did not reach stage 0: $(cat "$work/stage0.json")"

# Indistinguishable downstream: the same brief typed unaided produces the same
# run-state brief record.
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$brief" --root "$h" \
  > "$work/stage0-typed.json" 2>/dev/null
python3 -c "
import json
a=json.load(open('$work/stage0.json'))['run_state'].get('brief')
b=json.load(open('$work/stage0-typed.json'))['run_state'].get('brief')
assert a==b, (a,b)
" && ok "a map-started run is indistinguishable downstream from a hand-typed brief" \
  || err "the map leaves a downstream trace the brief path does not"


# --- an indexed brief reaches stage 0 exactly like a typed one ---------------
python3 "$D" candidates --map "$work/big-map.json" > "$work/big-cands.json"
python3 - "$work" <<'PYEOF' || err "indexed-answer prep failed"
import json, sys
w = sys.argv[1]
pin = json.load(open(w + "/big-map.json"))["coverage"]["pin"]
c = [x for x in json.load(open(w + "/big-cands.json"))["candidates"]
     if x["kind"] == "element"]
json.dump({"index": c[0]["id"], "note": "through the on-call retro, not the metrics",
           "pin": pin}, open(w + "/answer-idx.json", "w"))
PYEOF
python3 "$D" brief --answer "$work/answer-idx.json" --map "$work/big-map.json" \
  > "$work/brief-idx.json" 2>/dev/null || err "indexed brief composition failed"
# No new entry pipeline: an indexed brief reaches stage 0 exactly like a typed one.
idxbrief=$(python3 -c "import json;print(json.load(open('$work/brief-idx.json'))['brief'])")
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$idxbrief" --root "$h" \
  > "$work/stage0-idx.json" 2>"$work/e-idx" \
  || err "an indexed brief did not start a normal run: $(cat "$work/e-idx")"
python3 "$DP" stage0 "share engineering lessons" "$h" --brief "$idxbrief" --root "$h" \
  > "$work/stage0-idx-typed.json" 2>/dev/null
python3 -c "
import json
b=(json.load(open('$work/stage0-idx.json')).get('run_state') or {}).get('brief') or {}
t=(json.load(open('$work/stage0-idx-typed.json')).get('run_state') or {}).get('brief') or {}
assert b.get('text')=='''$idxbrief''', b
assert b.get('provenance')=='owner-authored', b
# byte-for-byte the same record the SAME string typed unaided produces: the
# index, the note and the pin exist only in the composer's output, never here
assert b==t, (b,t)
assert 'index' not in b and 'pin' not in b and 'note' not in b, b
" && ok "indexed selection: downstream cannot distinguish an indexed selection from a typed brief" \
  || err "an indexed selection left a downstream trace"

# --- the map path writes nothing into the host or articles tree --------------
before=$(find "$a" -type f | sort)
python3 "$D" payload --map "$work/map.json" >/dev/null
python3 "$D" candidates --map "$work/map.json" >/dev/null
[ "$before" = "$(find "$a" -type f | sort)" ] \
  && ok "composing the screen writes nothing into the articles repo" \
  || err "the screen composer wrote into the articles repo"



[ "$fail" -eq 0 ] && printf '\nAll topic-map screen checks passed.\n' \
