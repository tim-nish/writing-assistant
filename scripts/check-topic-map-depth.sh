#!/usr/bin/env sh
# check-topic-map-depth.sh — verify the map carries DEPTH SIGNALS: a rich
# subtopic and a lone seed look different at a glance (Story 18.62, #588;
# SPEC-topic-map CAP-2). POSIX sh + stdlib Python; every fixture write lands
# under mktemp -d.
#
# Covers:
#   CAP-2  each subtopic carries an evidence-density signal (distinct evidence
#          pointers, unconsumed cited elements, backlog items with status); the
#          depth estimate is computed from that signal by DECLARED thresholds,
#          not by taste; the estimate is a signal and NEVER a gate (every
#          subtopic stays selectable); consumed material is MARKED, not hidden,
#          and stays selectable; "why this depth?" is answered with the pointer
#          counts; a dense and a thin subtopic render visibly differently.
#   Decl   the thresholds live in ONE readable place, changing one changes the
#          estimate and nothing else, and the shipped values report themselves
#          as PROPOSED (`ratified: false`) rather than as a settled rule.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/topic-map.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$M', doraise=True)" 2>/dev/null \
  && ok "topic-map compiles" || { err "syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts" "$a/backlog" "$a/plans" "$a/graveyard"
git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1

# A DENSE subtopic: several items, many distinct pointers, cited elements.
cat > "$a/backlog/retry-storm.md" <<'EOF'
---
slug: retry-storm
title: Retry storms
status: shaping
track: engineering
subtopic: retry-behaviour
evidence:
  - host/log.txt:12@abc1234
  - host/log.txt:88@abc1234
  - host/bench.md:3@abc1234
lessons:
  - lesson:retry-storm
  - lesson:backoff-cap
---
EOF
cat > "$a/backlog/backoff-cap.md" <<'EOF'
---
slug: backoff-cap
title: Capping backoff
status: seed
track: engineering
subtopic: retry-behaviour
evidence:
  - host/fix.md:8@abc1234
  - host/retro.md:41@abc1234
lessons:
  - lesson:budget-alarm
---
EOF
cat > "$a/drafts/retry-cost.md" <<'EOF'
---
slug: retry-cost
title: What the storm cost
status: drafted
track: engineering
subtopic: retry-behaviour
evidence:
  - host/invoice.md:2@abc1234
---
EOF
# A THIN subtopic: one seed, one pointer, nothing cited.
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
# A CONSUMED subtopic: its element is recorded consumed by a persisted plan.
cat > "$a/backlog/cache-warmth.md" <<'EOF'
---
slug: cache-warmth
title: Cache warmth
status: seed
track: engineering
subtopic: caching
evidence:
  - host/cache.md:4@abc1234
lessons:
  - lesson:cache-warmth
---
EOF
cat > "$a/plans/cache-warmth.md" <<'EOF'
---
kind: article-plan
slug: cache-warmth
intent: share engineering lessons
claim: warm caches paid for themselves
status: drafted
run_id: 20260722T090000-000001
pin: host@a1b2c3d4e5f6a7b8
consumed: [lesson:cache-warmth]
---

## Section plan
EOF

MAP() { python3 "$M" assemble --root "$h" "$@"; }
MAP > "$work/m.json" 2>"$work/m.err" \
  && ok "assemble produces a map with depth signals" \
  || { err "assemble failed: $(cat "$work/m.err")"; printf '\nFAILED.\n' >&2; exit 1; }

python3 - "$work/m.json" <<'PYEOF' || fail=1
import json, sys
d = json.load(open(sys.argv[1]))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

subs = {}
for t in d["topics"]:
    for s in t.get("subtopics", []):
        subs[s["subtopic"]] = s
check(set(subs) >= {"retry-behaviour", "staffing", "caching"},
      "every topic's items are grouped into subtopics")

rich, thin = subs.get("retry-behaviour", {}), subs.get("staffing", {})

# --- the evidence-density signal -------------------------------------------
rd = rich.get("density", {})
check(rd.get("evidence_pointers") == 6,
      f"the density signal counts DISTINCT evidence pointers (got {rd.get('evidence_pointers')})")
check(rd.get("unconsumed_lessons") == 3,
      f"the density signal counts unconsumed cited elements (got {rd.get('unconsumed_lessons')})")
backlog = {b["slug"]: b["status"] for b in rd.get("backlog_items", [])}
check(backlog == {"retry-storm": "shaping", "backoff-cap": "seed"},
      "the density signal lists backlog items WITH their status")
check(rd.get("live_items") == 3, "the density signal counts live items")

# --- the depth estimate, from declared thresholds ---------------------------
check(rich.get("depth", {}).get("level") == "full article",
      f"a dense subtopic estimates higher (got {rich.get('depth', {}).get('level')})")
check(thin.get("depth", {}).get("level") == "seed-only",
      f"a lone seed estimates seed-only (got {thin.get('depth', {}).get('level')})")
check(d["depth_thresholds"]["available"] is True
      and d["depth_thresholds"]["ratified"] is False,
      "the thresholds are declared and report themselves as PROPOSED, not ratified")

# --- "why this depth?" is answered with the pointer counts ------------------
why = rich.get("depth", {}).get("why", "")
counted = rich.get("depth", {}).get("counted", {})
check(counted == {"evidence_pointers": 6, "unconsumed_lessons": 3, "live_items": 3},
      "the estimate carries the exact numbers it was derived from")
check("6 evidence pointer" in why and "3 unconsumed lesson" in why,
      "the estimate explains itself with its pointer counts, not an opaque score")
check("article series" not in rich.get("depth", {}).get("level", "")
      and "needs" in why,
      "the explanation names what the next level would require")

# --- a signal, never a gate -------------------------------------------------
check(all(s.get("selectable") is True for s in subs.values()),
      "every subtopic stays selectable whatever level it landed in")
check("never what the owner may pick" in rich.get("depth", {}).get("gates", ""),
      "the estimate states that thresholds gate surfacing, never permission")

# --- consumed material is MARKED, not hidden -------------------------------
consumed = subs.get("caching", {})
check(consumed.get("consumed") is True,
      "a fully consumed subtopic is marked consumed")
check(consumed.get("selectable") is True,
      "a consumed subtopic remains selectable — it is marked, not hidden")
check(any(i["slug"] == "cache-warmth" and i.get("consumed") is True
          for i in consumed.get("items", [])),
      "the consumed item itself is present and marked")
check(rich.get("consumed") is False,
      "an unconsumed subtopic is not marked consumed")

# --- visibly different at a glance -----------------------------------------
check(rich.get("glance") != thin.get("glance"),
      "a dense and a thin subtopic render visibly differently")
check(rich["glance"].count("#") > thin["glance"].count("#"),
      "the glance rendering is monotone in density")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- the thresholds live in ONE place, and moving one moves only the estimate --
cat > "$work/alt-thresholds.yaml" <<'EOF'
ratified: true
order: [seed-only, short-note]
levels:
  seed-only:
    name: seed-only
    description: a lone note
    min_evidence_pointers: 0
    min_unconsumed_lessons: 0
    min_live_items: 0
  short-note:
    name: short note
    description: enough for a working note
    min_evidence_pointers: 99
    min_unconsumed_lessons: 0
    min_live_items: 1
EOF
MAP --thresholds "$work/alt-thresholds.yaml" > "$work/alt.json"
python3 - "$work/m.json" "$work/alt.json" <<'PYEOF' || fail=1
import json, sys
base = json.load(open(sys.argv[1]))
alt = json.load(open(sys.argv[2]))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

def subs(d):
    return {s["subtopic"]: s for t in d["topics"] for s in t["subtopics"]}
b, a = subs(base), subs(alt)
check(a["retry-behaviour"]["depth"]["level"] == "seed-only",
      "raising a threshold changes the estimate")
check(a["depth_thresholds"]["ratified"] is True if False else
      alt["depth_thresholds"]["ratified"] is True,
      "the declaration carries its own ratification state")
# Nothing else moved: the density numbers are facts about the corpus, not the
# thresholds, so they are identical across the two runs.
check(a["retry-behaviour"]["density"] == b["retry-behaviour"]["density"],
      "changing a threshold changes the estimate and NOTHING else")
check(set(a) == set(b) and all(a[k]["selectable"] for k in a),
      "no subtopic is dropped by a stricter threshold — surfacing is not permission")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# An unreadable declaration is DISCLOSED, never replaced by invented numbers.
MAP --thresholds "$work/no-such-file.yaml" > "$work/missing.json"
python3 -c "
import json
d=json.load(open('$work/missing.json'))
assert d['depth_thresholds']['available'] is False, d['depth_thresholds']
s=[x for t in d['topics'] for x in t['subtopics']][0]
assert s['depth']['level'] is None, s['depth']
assert 'no depth-threshold declaration' in s['depth']['why'], s['depth']
assert s['selectable'] is True, s
" && ok "a missing threshold declaration is disclosed, and every subtopic stays selectable" \
  || err "a missing declaration was papered over"

# --- CAP-1 holds: the depth layer stores nothing -----------------------------
MAP > "$work/again.json"
python3 -c "
import json
a=json.load(open('$work/m.json')); b=json.load(open('$work/again.json'))
del a['coverage']; del b['coverage']
assert a==b, 'two invocations over an unchanged fixture differ'
" && ok "CAP-1: the depth layer is recomputed, identical across invocations" \
  || err "the depth layer is not purely derived"
[ -z "$(ls "$work/state" 2>/dev/null)" ] \
  && ok "no depth index is written anywhere" \
  || err "the depth layer wrote state: $(ls -R "$work/state")"

# --- the shipped declaration is readable and singular ------------------------
python3 - <<'PYEOF' || exit 1
import os, sys, importlib.util
spec = importlib.util.spec_from_file_location(
    "uc", os.path.join("scripts", "resolve-user-config.py"))
uc = importlib.util.module_from_spec(spec); spec.loader.exec_module(uc)
data = uc.load_yaml(open("config/topic-depth-thresholds.yaml", encoding="utf-8").read())
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)
names = [data["levels"][k]["name"] for k in data["order"]]
check(names == ["seed-only", "short note", "full article", "article series"],
      "the shipped declaration names the four levels the spec lists")
check(data["ratified"] is False,
      "the shipped values declare themselves PROPOSED, awaiting ratification")
check(all(int(data["levels"][k]["min_evidence_pointers"]) >= 0 for k in data["order"]),
      "every level declares its minimums")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- scope: CAP-3 is still someone else's story ------------------------------
sh scripts/check-topic-map.sh >/dev/null 2>&1 \
  && ok "the shipped topic-map harness (CAP-1/CAP-4) passes unchanged" \
  || err "check-topic-map.sh regressed"

[ "$fail" -eq 0 ] && printf '\nAll topic-map depth checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
