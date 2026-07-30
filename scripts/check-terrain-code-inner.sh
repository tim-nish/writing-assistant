#!/usr/bin/env sh
# tier: inner — source/skill-text assertions plus the self-contained screen-1
#   axes fixture; no seam, no corpus, no map assembly. Measured 2026-07-30 at
#   adoption: ~1.3s (the runner discloses the live number every run).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-code-inner.sh — the terrain area's CODE-LEVEL assertions,
# split from check-topic-map.sh and check-topic-map-screen.sh (Story 20.49,
# #923; the two-tier protocol is #913). Everything here runs against the
# repository's own files or a fixture synthesized in place, so it belongs in
# the per-edit inner loop. The end-to-end halves remain in the two source
# checks, which still gate the PR (tier: full).
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/terrain_map.py"
D="scripts/topic-map-directions.py"
T="scripts/terrain_text.py"
VP="scripts/validate-proposal-payload.py"
SKILL="skills/terrain/SKILL.md"
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/ws"
cp "$FIX" "$work/map.json"

python3 -c "import py_compile; py_compile.compile('$M', doraise=True)" 2>/dev/null \
  && ok "terrain_map.py compiles" || err "terrain_map.py syntax error"
python3 -c "import py_compile; py_compile.compile('$D', doraise=True)" 2>/dev/null \
  && ok "topic-map-directions compiles" || err "topic-map-directions syntax error"
python3 -c "import py_compile; py_compile.compile('$T', doraise=True)" 2>/dev/null \
  && ok "terrain_text.py compiles" || err "terrain_text.py syntax error"

# NO SECOND PROPOSER: the View renders the directions it is GIVEN. A
# `candidates()` call inside compose_view would be a second derivation, and the
# screen and the View could then silently disagree about what was offered.
python3 - "$D" <<'PYEOF' && ok "the View reuses the derived directions and derives none of its own" || err "compose_view derives its own directions (second proposer)"
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
fn = next(n for n in ast.parse(src).body
          if isinstance(n, ast.FunctionDef) and n.name == "compose_view")
calls = {n.func.id for n in ast.walk(fn)
         if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
sys.exit(1 if "candidates" in calls else 0)
PYEOF

# Source-level: the View path is written, never read (the --emit-debug rule).
python3 - "$D" <<'PYEOF' && ok "size switch: no code path reads a View file back" || err "topic-map-directions.py contains a View-reading code path"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
reads = re.findall(r'open\((?![^)]*"w")[^)]*\)', src)
for r in reads:
    assert "view" not in r.lower(), f"a View file is opened for reading: {r}"
assert 'def write_view' in src and 'open(path, "w"' in src, "the View is not write-only"
PYEOF

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


# --- lockstep: the SKILL states the shipped mechanics ------------------------
[ -f "$SKILL" ] && ok "the topic-map skill exists" || err "$SKILL missing"
# The owner path is the two-screen flow (Story 20.19, #841): axis, then
# member, then brief. The pre-pivot `payload --view` invocation left the
# skill with that story; the View survives on the size switch's over-budget
# branch via the `view` subcommand.
for token in 'terrain_map.py assemble' 'topic-map-directions.py axis' \
             'topic-map-directions.py member' \
             'topic-map-directions.py brief' 'validate-proposal-payload.py' \
             'stage0' '--brief' 'free-form' 'every time' \
             'never composes narrative structures' 'single proposer' \
             'topic-map-directions.py view' '--out' 'size switch' \
             'never read back' \
             'resolve-paths.py topic-map-view' 'destination repository' \
             'stable within a pin' 'refused with the mismatch named' \
             'note verbatim' 'machine-composed'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the contract text: $token" \
    || err "SKILL is missing contract text: $token"
done


# --- owner-surface text fits by authorship, never by clipping (#832) ---------
# The slice-plus-fake-period idiom is gone for good: a truncation that ends in
# "." masquerades as a sentence ("Too many to f."), which the owner reads as a
# complete statement saying something else. Grep-asserted like the other
# absences in this file.
# Both files: the fitting primitives moved to `terrain_text.py` (Story 20.58,
# #942), so the guard follows the code it guards rather than staying pointed at
# the file the code left.
if grep -nE '\[:(budget|room) *- *1\]' scripts/topic-map-directions.py \
     scripts/terrain_text.py >/dev/null; then
  err "the mid-word slice idiom is back in the terrain composer (#832)"
else
  ok "no mid-word slice-plus-period idiom in the composer"
fi
python3 - scripts/topic-map-directions.py scripts/terrain_text.py <<'PYEOF' || fail=1
import importlib.util, sys
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)
spec = importlib.util.spec_from_file_location("tmd", sys.argv[1])
tmd = importlib.util.module_from_spec(spec); spec.loader.exec_module(tmd)
# The fitting primitives moved to their own leaf module (Story 20.58, #942) and
# are exercised through THAT module's path — never through the composer's
# re-export, so a symbol deleted where it now lives fails here.
tspec = importlib.util.spec_from_file_location("ttext", sys.argv[2])
txt = importlib.util.module_from_spec(tspec); tspec.loader.exec_module(txt)
# Static template text fits its budget BY CONSTRUCTION — measured here, at
# authoring time, per the owner-facing proposal contract clause (e).
check(len(tmd.WHY_TEXT) <= tmd.BUDGETS["why"],
      f"WHY_TEXT is authored inside BUDGETS['why'] ({len(tmd.WHY_TEXT)}/{tmd.BUDGETS['why']})")
# The summary `where` picks an authored variant beside the path — never slices.
long_path = "/home/owner/work/some-articles-repo/drafts/topic-map/topic-map-view.md"
where = txt._fit_with_path(
    ["Terrain at deadbeef: 61 element(s) — each its own Strand — and 3 "
     "topic(s), 61 strand(s); 0 already consumed and still selectable.",
     "Terrain at deadbeef: 61 Strands, 3 topic(s); 0 consumed.",
     "Terrain: 61 Strands."], long_path, tmd.BUDGETS["where"])
check(where.endswith(long_path), "the View path is never clipped")
check(len(where) <= tmd.BUDGETS["where"],
      f"an authored variant fits beside a realistic path ({len(where)}/{tmd.BUDGETS['where']})")
prefix = where[: -len(" Open the View: " + long_path)]
check(not __import__("re").search(r"\b\w\.$", prefix),
      "the summary prefix is a whole authored wording, not a cut wearing a period")
# View-line elision is visible and lands on a word boundary.
e = txt._elide("Too many to fit on one screen indeed", 20)
check(e.endswith("…") and not e.endswith(" …") and "fit" not in e.split("…")[0].split()[-1][:1],
      f"View elision is marked and word-bounded ({e!r})")
check(txt._elide("short", 20) == "short", "under-budget View value is untouched")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- SCREEN 1: the two served axes (Story 20.8, #810; Story 20.25, #860) -----
# Screen 1 offers TWO axes (SPEC-terrain CAP-2 as amended 2026-07-28): the
# served TAG vocabulary over Lessons and Journeys, and the served decision
# TOPIC over decisions and reversals. Both keys are already shard keys, so
# neither axis joins anything. Deterministic; no cap; per-axis denominators,
# never pooled; Strands outside EVERY axis disclosed as a line.
#
# The word "topic" is legitimate on this screen for the topic axis and its
# members. What the 2026-07-27 retirement forbids is the TAG axis calling its
# members topics — the collision with `topics/*.md` — and that is what the
# assertion below tests, rather than the blanket absence it used to.
#
# Asserted on a fixture that exercises every clause: a 53-entry member so
# serve-whole is tested at the measured worst case, a NAME COLLIDING across
# both vocabularies, decisions and reversals carrying no tags, and one Strand
# outside both axes.
python3 - "$D" <<'PYEOF' || fail=1
import json, subprocess, sys, tempfile
D = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

els = []
for n in range(53):                    # the measured largest member is 40-53
    els.append({"kind": "lesson", "slug": f"w{n}", "title": f"W{n}",
                "tags": ["workflow"], "evidence": [], "consumed": False})
els.append({"kind": "lesson", "slug": "a1", "title": "A1",
            "tags": ["agents", "workflow"], "evidence": [], "consumed": False})
els.append({"kind": "journey", "slug": "j1", "title": "J1",
            "tags": ["agents"], "evidence": [], "consumed": True})
els.append({"kind": "lesson", "slug": "untagged", "title": "U",
            "tags": [], "evidence": [], "consumed": False})
# The topic axis's corpus: decisions and reversals carry NO tags (the served
# shard entries have none), and their topic IS their shard key. `workflow`
# deliberately collides with a tag-axis member name.
els.append({"kind": "decision", "slug": "d1", "title": "D1", "tags": [],
            "topic": "workflow", "evidence": [], "consumed": False})
els.append({"kind": "decision", "slug": "d2", "title": "D2", "tags": [],
            "topic": "articles", "evidence": [], "consumed": False})
# `reversal` is NOT a served element kind (#893). Kept in the fixture on
# purpose: it must NOT reach the topic axis, and must fall to the
# outside-every-axis disclosure rather than being silently counted.
els.append({"kind": "reversal", "slug": "r1", "title": "R1", "tags": [],
            "topic": "workflow", "evidence": [], "consumed": False})
m = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
     "elements": els}
f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(m, f); f.close()
run = lambda: subprocess.run(
    ["python3", D, "axis", "--map", f.name], capture_output=True, text=True)
out = run()
check(out.returncode == 0, f"axis composes (rc={out.returncode})")
d = json.loads(out.stdout)
axes = {a["key"]: a for a in d["axis"]["axes"]}
check(sorted(axes) == ["tag", "topic"], f"Screen 1 offers two axes ({sorted(axes)})")
tags = {x["member"]: x["strands"] for x in axes["tag"]["members"]}
topics = {x["member"]: x["strands"] for x in axes["topic"]["members"]}
check(tags == {"workflow": 54, "agents": 2},
      f"tag-axis members are exactly the element tags with correct counts ({tags})")
check(topics == {"workflow": 1, "articles": 1},
      f"topic-axis members are exactly the decision topics with correct counts ({topics})")
# The collision case: one name, two axes, different material. Neither member
# absorbs the other's Strands — which is why a merged listing was refused.
check(tags["workflow"] == 54 and topics["workflow"] == 1,
      "a name served by BOTH vocabularies stays two distinct members")
check(d["axis"]["unreachable_strands"] == 2,
      "a Strand outside EVERY axis is counted (incl. the unserved `reversal` kind, #893), and decisions no longer are")

# PER-AXIS COMPLETENESS (Story 20.25): count in == count out, on each axis
# independently, recomputed here rather than trusted from the payload.
want_tag, want_topic, want_out = {}, {}, 0
for el in els:
    hit = False
    for t in el.get("tags") or []:
        want_tag[t] = want_tag.get(t, 0) + 1; hit = True
    if el["kind"] == "decision" and el.get("topic"):
        want_topic[el["topic"]] = want_topic.get(el["topic"], 0) + 1; hit = True
    if not hit: want_out += 1
check(tags == want_tag and topics == want_topic
      and d["axis"]["unreachable_strands"] == want_out,
      "each axis reconciles independently against a recount of the elements")

item = d["payload"]["items"][0]
labels = [c["label"] for c in item["choices"]]
check(labels[0] == "by tag — agents (2 Strands)"
      and labels[1] == "by tag — workflow (54 Strands)",
      f"every member is offered with its count — 54 entries included, no cap ({labels[:2]})")
check(labels[2] == "by topic — articles (1 Strand)"
      and labels[3] == "by topic — workflow (1 Strand)",
      f"the topic axis's members are offered too, kind-labelled ({labels[2:4]})")
check(labels[-2:] == ["name your own direction or combination axis", "stop here"],
      "free-form is offered and stop stays last")
check("outside both listings" in item["where"],
      "the outside-every-axis disclosure is a line on the screen")
check("no served tag" not in item["where"],
      "the retired untagged-strand line is gone, not reworded")
check("tag(s) and" in item["where"] and "topic(s)" in item["where"],
      f"the denominator is stated per axis, never pooled ({item['where'][:70]})")
tag_labels = [x for x in labels if x.startswith("by tag")]
check(all("topic" not in x for x in tag_labels),
      "the tag axis never calls its members topics (the retired UI word)")
check(out.stdout == run().stdout, "the axis listing is byte-identical across invocations")
v = subprocess.run(["python3", "scripts/validate-proposal-payload.py",
                    "--surface", "topic-map", "/dev/stdin"],
                   input=json.dumps(d["payload"]), capture_output=True, text=True)
check(v.returncode == 0, f"the axis screen passes the proposal validator ({v.stderr.strip()[:80]})")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1


# --- from check-topic-map.sh (Story 20.49) -----------------------------------
# --- the depth estimator is GONE (Story 20.7, #809) -------------------------
# It was derived PER SUBTOPIC and has no carrier once the unit is gone. The
# threshold declaration goes with it — a declaration nothing reads is exactly
# the assembly cost this removal exists to stop.
python3 - "$root/scripts/terrain_map.py" <<'PYEOF' && ok "no depth estimator, no threshold plumbing, no --thresholds flag" || err "depth estimator survives"
import sys
src = open(sys.argv[1], encoding="utf-8").read()
for gone in ("estimate_depth", "load_thresholds", "--thresholds", "depth_thresholds"):
    assert gone not in src, f"{gone} survives"
PYEOF
[ ! -f "$root/config/topic-depth-thresholds.yaml" ] \
  && ok "the shipped threshold declaration is removed" \
  || err "config/topic-depth-thresholds.yaml survives its only consumer"

# --- clustering is GONE (Story 20.7, #809) ----------------------------------
# The path-family derivation, the declared-subtopic precedence and the
# malformed-declaration lint all existed to NAME a cluster. The cluster unit is
# abandoned, so they are asserted absent rather than re-pointed: a lint on a
# key nothing reads reports a defect with no consequence.
python3 - "$root/scripts/terrain_map.py" <<'PYEOF' && ok "clustering, its naming and its declaration lint are deleted, not merely unreferenced" || err "cluster machinery survives"
import sys
src = open(sys.argv[1], encoding="utf-8").read()
for gone in ("def cluster_subtopics(", "def subtopic_key(", "def subtopic_defect(",
             "def estimate_depth(", "def load_thresholds(", "def thresholds_path(",
             "def _glance(", "SUBTOPIC_KEYS", "THRESHOLDS_FILE", "UNCLUSTERED"):
    assert gone not in src, f"{gone} survives the cluster removal"
PYEOF

# --- 8. scope: CAP-2 and CAP-3 are NOT implemented here -------------------------
# Scope is a property of the CODE, not of the prose that documents it: strip
# comments and string literals first, so a docstring saying "composes no
# narrative structures" is never mistaken for composing one.
python3 - "$M" > "$work/code.py" <<'PYEOF'
import io, sys, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
out = []
for tok in tokenize.generate_tokens(io.StringIO(src).readline):
    if tok.type in (tokenize.COMMENT, tokenize.STRING):
        continue
    out.append(tok.string)
print(" ".join(out))
PYEOF
CODE="$work/code.py"
# The invariant is that the PREDICATE is not re-derived here. Story 18.62 marks
# items against the shipped index (a lookup, not a second rule), so the check
# targets re-derivation directly, over the comment-stripped code: terrain_map.py
# must never read `plans/` itself, and the view must come from
# `write-article-plan.py consult`.
grep -qE "plans" "$CODE" \
  && err "terrain_map.py reads plans/ itself (the consumption view must come from consult)" \
  || ok "consumption: terrain_map.py never reads plans/ — no second derivation of the predicate"
grep -q 'PLAN_WRITER' "$M" \
  && ok "consumption: the view is read from the shipped write-article-plan.py consult" \
  || err "terrain_map.py does not read the shipped consumption view"
# CAP-2 (depth signals) SHIPPED with Story 18.62 (#588) and has its own harness
# (check-topic-map-depth.sh). What must stay true here is that no depth boundary
# is hardcoded in stage code: the numbers live in the declaration file alone.
grep -qiE 'seed-only|short note|article series' "$CODE" \
  && err "terrain_map.py hardcodes a depth level name (the levels are declared data)" \
  || ok "scope: no depth level is hardcoded (the boundaries stay declared)"
grep -qE 'min_evidence_pointers *= *[0-9]|min_live_items *= *[0-9]' "$CODE" \
  && err "terrain_map.py hardcodes a threshold value (it must read the declaration)" \
  || ok "scope: no threshold value is hardcoded in stage code"
grep -qiE 'approve/modify|proposal contract|candidate direction|screen' "$CODE" \
  && err "terrain_map.py builds a presentation screen (CAP-3 belongs to a sibling story)" \
  || ok "scope: no presentation screen is built (CAP-3 left to its own story)"
grep -qiE 'narrative structure|structure candidate|compose.*structure' "$CODE" \
  && err "terrain_map.py composes narrative structures (18.45 single-proposer invariant)" \
  || ok "scope: the map composes no narrative structures (single-proposer invariant intact)"
# CAP-4's cost promise as amended: widening the corpus must NOT pull in
# harvest's per-source budgeted extraction. The map stays index-scale. The
# check is a CLOSED SET of sibling scripts the map may reach for — adding one
# is a reviewed decision, not a drive-by import, and no fact-sheet reader or
# harvest cache is on it.
python3 - "$M" <<'PYEOF' && ok "CAP-4: the map reaches only for its declared resolvers/seams — no harvest pass, no fact-sheet extractor (cost stays index-scale)" || err "terrain_map.py reaches for a script outside its allowed set (an extraction pass would make the map corpus-scale)"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
named = set(re.findall(r'os\.path\.join\(SCRIPT_DIR,\s*"([^"]+\.py)"\)', src))
named |= set(re.findall(r'_load\(\s*"([^"]+\.py)"\s*\)', src))
allowed = {
    "resolve-writing-sources.py",   # the declared-location / mapping resolver
    "resolve-paths.py",             # the storage-layout resolver
    "resolve-user-config.py",       # the YAML-subset reader
    "write-article-plan.py",        # the SHIPPED consumption derived view
    "read-policy-source.py",        # the SHIPPED policy seam (hub-lessons)
    # The shipped non-blank-line SIZE PROXY only (`harvestable_lines`, Story
    # 18.65) — reused so the map and harvest measure a source the same way.
    # Harvest's per-source EXTRACTION pass is a different thing entirely and
    # is never invoked; the assertion below pins that distinction.
    "harvest-budget.py",
}
extra = sorted(named - allowed)
assert not extra, f"unreviewed sibling scripts: {extra}"
PYEOF
# harvest-budget.py was reached for ONE measure, by the host-sources item
# builder. That builder went with the family (Story 20.7, #809), so the
# strongest form of CAP-4's cost promise now holds: the map does not reach for
# harvest's budgeting AT ALL.
python3 - "$M" <<'PYEOF' && ok "CAP-4: the map no longer reaches for harvest's budgeting at all (the host-sources item builder went with the family)" || err "terrain_map.py still reaches into harvest's budgeting"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
used = set(re.findall(r'_budget\(\)\.(\w+)', src))
assert not used, f"harvest-budget attributes still used: {sorted(used)}"
PYEOF
# The hub-lessons family goes through the SHIPPED seam — never a second reader.
# Since the seam split (Story 20.40, #903) the reader is owned by ONE module,
# which is a stronger form of the same property: `terrain_map.py` cannot reach
# the policy source except through it, so "one reader" is structural rather
# than a convention this grep polices.
SEAM="scripts/terrain_seam.py"
grep -q 'POLICY_READER' "$SEAM" \
  && ok "the seam module owns the shipped read-policy-source.py invocation" \
  || err "$SEAM does not invoke the shipped policy reader"
grep -q 'terrain_seam' "$M" \
  && ok "hub-lessons: the family is served through the seam module" \
  || err "terrain_map.py does not reach the policy source through the seam module"
# INVOCATION SHAPES, never prose (#834's rule): the docstrings still name the
# reader, and should — what must not survive is a call to it.
grep -qE 'POLICY_READER|subprocess\.run\(\[sys\.executable, *[A-Z_]*READER' "$M" \
  && err "terrain_map.py invokes the policy reader directly — the seam layer is bypassed (#903)" \
  || ok "no seam invocation remains in terrain_map.py (the split holds)"
grep -qE 'lessons_index|LESSONS\.md.*open\(|policy_lookup' "$CODE" \
  && err "terrain_map.py talks to the gateway itself (the seam is the only reader)" \
  || ok "hub-lessons: no second policy reader exists in the implementation"


[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
