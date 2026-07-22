#!/usr/bin/env sh
# check-topic-map-screen.sh — verify the map ends in a BRIEF, not in a second
# proposer (Story 18.63, #591; SPEC-topic-map CAP-3). POSIX sh + stdlib Python;
# every fixture write lands under mktemp -d.
#
# Covers:
#   CAP-3  ONE in-conversation screen carrying the map, machine-proposed
#          candidate directions, and a FREE-FORM response offered every time
#          (not only on rejection); at least one candidate is a cross-topic
#          COMBINATION when the evidence supports one; the outcome is a brief in
#          the owner's words handed to the EXISTING stage-0 `--brief` path; the
#          map composes NO narrative structures (grep-asserted); a sitting that
#          starts at the map ends in a normal brief-carrying run.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/topic-map.py"
D="scripts/topic-map-directions.py"
DP="scripts/draft-pipeline.py"
VP="scripts/validate-proposal-payload.py"
SKILL="skills/topic-map/SKILL.md"

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
printf '# notes\n\nThe retry storm doubled token spend.\n' > "$h/docs/notes.md"
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

python3 "$M" assemble --root "$h" > "$work/map.json" 2>"$work/m.err" \
  || { err "map assembly failed: $(cat "$work/m.err")"; printf '\nFAILED.\n' >&2; exit 1; }
ok "fixture: the map assembles"

# --- candidate directions -----------------------------------------------------
python3 "$D" candidates --map "$work/map.json" > "$work/cands.json"
python3 - "$work/cands.json" <<'PYEOF' || fail=1
import json, sys
c = json.load(open(sys.argv[1]))["candidates"]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check(c, "the map proposes candidate directions")
combos = [x for x in c if x["kind"] == "combination"]
check(combos, "at least one candidate is a CROSS-TOPIC combination")
if combos:
    k = combos[0]
    check(sorted(k["topics"]) == ["engineering", "people"],
          "the combination spans two different topics")
    check(k["axis"] == "retro.md" and "retro.md" in k["shared_evidence"],
          "the combination's axis is named from evidence both subtopics cite")
    check("retro.md" in k["why"],
          "the combination explains itself from the shared evidence")
# No combination is proposed on nothing shared.
check(all("staffing" not in x["subtopics"] for x in combos),
      "a subtopic sharing no evidence is never combined on a hunch")
# Every candidate names WHAT to cover, never HOW to tell it.
for x in c:
    check(set(x) & {"structure", "sections", "outline", "arc"} == set(),
          f"candidate {x['direction']!r} carries no narrative shape")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- ONE screen, presentable, free-form every time ---------------------------
python3 "$D" payload --map "$work/map.json" > "$work/payload.json"
python3 "$VP" --ws "$work/ws" --surface topic-map "$work/payload.json" > "$work/ask.json" \
  && ok "the screen passes validate-proposal-payload.py before presentation" \
  || err "the screen is not presentable: $(cat "$work/ask.json")"
python3 - "$work/payload.json" <<'PYEOF' || fail=1
import json, sys
p = json.load(open(sys.argv[1]))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check(len(p["items"]) == 1, "it is ONE screen, not a sequence of them")
item = p["items"][0]
labels = [c["label"] for c in item["choices"]]
check(any("name your own" in l for l in labels),
      "a free-form response is offered")
check(labels[-1] == "stop here", "stopping is offered and stays first-class")
check(any("connect" in l for l in labels),
      "the combination candidate reaches the screen")
check("signal for your judgment, never a gate" in item["why"],
      "the screen states that depth is a signal, never a gate")
check("selectable" in item["where"],
      "the screen states consumed material remains selectable")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# Free-form is offered EVERY time — including on a map with a single candidate.
python3 - "$work/map.json" > "$work/thin-map.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["topics"] = d["topics"][:1]
for t in d["topics"]:
    t["subtopics"] = t["subtopics"][:1]
print(json.dumps(d))
PYEOF
python3 "$D" payload --map "$work/thin-map.json" > "$work/thin-payload.json"
python3 -c "
import json
labels=[c['label'] for c in json.load(open('$work/thin-payload.json'))['items'][0]['choices']]
assert any('name your own' in l for l in labels), labels
assert 'stop here' in labels, labels
" && ok "free-form is offered every time, not only on rejection" \
  || err "free-form is conditional"

# --- the outcome is a brief IN THE OWNER'S WORDS -----------------------------
printf '%s' '{"selection":"name your own direction or combination axis","free_text":"connect the retry storm to on-call load, through the retro"}' \
  > "$work/answer-free.json"
python3 "$D" brief --answer "$work/answer-free.json" --map "$work/map.json" \
  > "$work/brief-free.json"
python3 -c "
import json
b=json.load(open('$work/brief-free.json'))
assert b['brief']=='connect the retry storm to on-call load, through the retro', b
assert b['provenance']=='owner-authored' and b['origin']=='free-form', b
" && ok "free-form wording becomes the brief verbatim, owner-authored" \
  || err "free-form wording was not carried through"

sel=$(python3 -c "import json;print(json.load(open('$work/cands.json'))['candidates'][0]['direction'])")
python3 -c "
import json,sys
json.dump({'selection':sys.argv[1],'free_text':''},open('$work/answer-sel.json','w'))
" "$sel"
python3 "$D" brief --answer "$work/answer-sel.json" --map "$work/map.json" \
  > "$work/brief-sel.json"
python3 -c "
import json
b=json.load(open('$work/brief-sel.json'))
assert b['origin']=='adopted-candidate', b
assert b['provenance']=='owner-authored', b
" && ok "machine-proposed text the owner accepts becomes OWNER-ADOPTED wording" \
  || err "an adopted candidate did not become an owner-authored brief"

printf '%s' '{"selection":"stop here","free_text":""}' > "$work/answer-stop.json"
python3 "$D" brief --answer "$work/answer-stop.json" --map "$work/map.json" \
  > "$work/brief-stop.json" 2>&1 \
  && err "stopping produced a brief" \
  || grep -q 'first-class outcome' "$work/brief-stop.json" \
     && ok "stopping produces no brief and no run, and says so" \
     || err "wrong stop behaviour: $(cat "$work/brief-stop.json")"

# --- the hand-off is the EXISTING stage-0 --brief path -----------------------
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

# --- NO structure composition anywhere in the map path -----------------------
# Scope is a property of the CODE, not the prose documenting it.
for src in "$D" "$M"; do
  python3 - "$src" > "$work/code.py" <<'PYEOF'
import io, sys, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
out = []
for tok in tokenize.generate_tokens(io.StringIO(src).readline):
    if tok.type in (tokenize.COMMENT, tokenize.STRING):
        continue
    out.append(tok.string)
print(" ".join(out))
PYEOF
  grep -qiE 'narrative structure|structure candidate|compose.*structure|section_plan|outline' \
    "$work/code.py" \
    && err "$src composes narrative structures (18.45 single-proposer invariant)" \
    || ok "$src composes no narrative structures"
done

# --- the map path writes nothing into the host or articles tree --------------
before=$(find "$a" -type f | sort)
python3 "$D" payload --map "$work/map.json" >/dev/null
python3 "$D" candidates --map "$work/map.json" >/dev/null
[ "$before" = "$(find "$a" -type f | sort)" ] \
  && ok "composing the screen writes nothing into the articles repo" \
  || err "the screen composer wrote into the articles repo"

# --- the shipped map harnesses keep passing verbatim -------------------------
for c in check-topic-map.sh check-topic-map-depth.sh; do
  sh "scripts/$c" >/dev/null 2>&1 && ok "$c passes unchanged" || err "$c regressed"
done

# --- lockstep: the SKILL states the shipped mechanics ------------------------
[ -f "$SKILL" ] && ok "the topic-map skill exists" || err "$SKILL missing"
for token in 'topic-map.py assemble' 'topic-map-directions.py payload' \
             'topic-map-directions.py brief' 'validate-proposal-payload.py' \
             'stage0' '--brief' 'free-form' 'every time' \
             'never composes narrative structures' 'single proposer'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the contract text: $token" \
    || err "SKILL is missing contract text: $token"
done

[ "$fail" -eq 0 ] && printf '\nAll topic-map screen checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
