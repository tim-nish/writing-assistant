#!/usr/bin/env sh
# check-topic-map.sh — verify the topic map is a DERIVED, BOUNDED view
# (Story 18.61, #585; SPEC-topic-map CAP-1 + CAP-4). POSIX sh + stdlib Python.
#
# Covers:
#   CAP-1  no stored index exists anywhere; nothing the script writes is ever
#          read back; two invocations straddling a fixture change differ
#          exactly where the fixture changed; deleting the debug dump loses
#          nothing.
#   CAP-1  (Story 18.64) every surface carries its SOURCE FAMILY; the
#          hub-lessons family enumerates LESSONS.md index lines through the
#          shipped seam, and an unresolvable policy source makes it
#          declared-but-not-enumerated WITH THE REASON, never silently empty.
#   CAP-4  only index/frontmatter surfaces are read (item BODIES never are);
#          an over-bound invocation NAMES the surfaces it skipped, with the
#          closed read+skipped==matched accounting harvest's manifest uses —
#          per family as well as overall; the manifest names which declared
#          families were enumerated and which were not.
#   Scope  CAP-2 (depth estimates) and CAP-3 (a presentation screen) are NOT
#          implemented by this story — asserted absent.

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
  && ok "topic-map compiles" \
  || { err "topic-map syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

# The hub-lessons family reaches the policy source through the shipped seam,
# so the harness must be hermetic about the gateway: point the documented test
# seam at the stub server. Until a fixture declares lessons, the stub serves a
# MISS — the family is then declared-but-not-enumerated, exactly as an empty
# hub would be. (Before `set-policy-source` runs, the reader exits 10 without
# ever spawning a server; the export matters from section 6 onward.)
FX="$work/gateway.json"
printf '{"pin": "product-lab@%s", "lessons": []}\n' \
  "0123456789abcdef0123456789abcdef01234567" > "$FX"
WRITING_ASSISTANT_GATEWAY_CMD="python3 $root/scripts/fixtures/policy-gateway-stub.py $FX"
export WRITING_ASSISTANT_GATEWAY_CMD

# Host source repo + a conforming articles repo (drafts/ + INDEX.md + backlog/).
h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts" "$a/backlog" "$a/plans" "$a/graveyard"
git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1

# A backlog item: frontmatter carries everything the map projects; the BODY
# carries a sentinel that must never surface (CAP-4: no body fan-out).
backlog_item() {  # slug track status evidence-item body-sentinel
cat > "$a/backlog/$1.md" <<EOF
---
slug: $1
title: On $1
status: $3
track: $2
evidence:
  - $4
---

$5

track: BODY-TRACK-MUST-NOT-BE-READ
EOF
}

backlog_item retry-storm engineering seed "host/log.txt:12@abc1234" "SENTINEL-BODY-ALPHA"
backlog_item cache-warmth engineering shaping "host/bench.md:3@abc1234" "SENTINEL-BODY-BETA"
backlog_item team-shape people seed "host/notes.md:9@abc1234" "SENTINEL-BODY-GAMMA"

cat > "$a/drafts/retry-storm.md" <<'EOF'
---
slug: retry-storm
title: The retry storm
status: published
track: engineering
date: 2026-07-01
---

SENTINEL-BODY-DRAFT
EOF

MAP() { python3 "$M" assemble --root "$h" "$@"; }

# --- 1. the map assembles and declares itself derived ---------------------------
MAP > "$work/m1.json" 2>"$work/m1.err" \
  && ok "assemble produces a map" \
  || err "assemble failed: $(cat "$work/m1.err")"

python3 - "$work/m1.json" <<'PYEOF' && ok "map: topics derived from track_topics-less repo fall back to track names, items projected from frontmatter" || err "map content wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["kind"] == "topic-map" and d["derived"] is True and d["stored"] is False, d
topics = {t["topic"]: t for t in d["topics"]}
assert set(topics) == {"engineering", "people"}, topics.keys()
# no track_topics declared -> tracks show unmapped, never an invented topic
assert topics["engineering"]["mapped"] is False, topics["engineering"]
assert set(d["unmapped_tracks"]) == {"engineering", "people"}, d["unmapped_tracks"]
slugs = sorted(i["surface"] for i in topics["engineering"]["items"])
assert slugs == ["backlog/cache-warmth.md", "backlog/retry-storm.md",
                 "drafts/retry-storm.md"], slugs
item = [i for i in topics["engineering"]["items"] if i["surface"] == "backlog/retry-storm.md"][0]
assert item["status"] == "seed" and item["evidence"] == ["host/log.txt:12@abc1234"], item
PYEOF

python3 - "$work/m1.json" <<'PYEOF' && ok "CAP-1/CAP-4: every surface carries its family, and an undeclared policy source leaves hub-lessons declared-but-NOT-enumerated with the reason" || err "family disclosure wrong for an undeclared policy source"
import json, sys
cov = json.load(open(sys.argv[1]))["coverage"]
fams = {f["family"]: f for f in cov["families"]}
assert set(fams) == {"articles-items", "hub-lessons"}, fams.keys()
assert all(d["family"] == "articles-items" for d in cov["read"]), cov["read"]
assert fams["articles-items"]["enumerated"] is True, fams["articles-items"]
# declared, not enumerated, and the reason is NAMED — never a silent empty family
hl = fams["hub-lessons"]
assert hl["declared"] is True and hl["enumerated"] is False, hl
assert hl["reason"], hl
assert hl["matched"] == 0 and hl["accounting_closes"] is True, hl
assert cov["families_enumerated"] == ["articles-items"], cov["families_enumerated"]
assert [f["family"] for f in cov["families_not_enumerated"]] == ["hub-lessons"], cov
assert cov["families_not_enumerated"][0]["reason"] == hl["reason"], cov
PYEOF

# --- 2. CAP-4: item BODIES are never read ---------------------------------------
if grep -q 'SENTINEL-BODY' "$work/m1.json"; then
  err "a body sentinel reached the map — the assembler read article bodies"
else
  ok "CAP-4: no body text reaches the map (bodies are never read)"
fi
python3 - "$work/m1.json" <<'PYEOF' && ok "CAP-4: a body line shaped like frontmatter (track:) does not become a topic" || err "body key leaked into the map"
import json, sys
d = json.load(open(sys.argv[1]))
assert "BODY-TRACK-MUST-NOT-BE-READ" not in json.dumps(d), "body key parsed"
PYEOF

# Assembly cost must not scale with body size: a 20k-line body changes nothing.
cp "$a/backlog/retry-storm.md" "$work/small.md"
python3 - "$a/backlog/retry-storm.md" <<'PYEOF'
import sys
p = sys.argv[1]
open(p, "a", encoding="utf-8").write("\nfiller line\n" * 20000)
PYEOF
MAP > "$work/m1big.json" 2>/dev/null
python3 - "$work/m1.json" "$work/m1big.json" <<'PYEOF' && ok "CAP-4: a 20k-line body changes nothing in the map (cost scales with index size)" || err "body growth changed the map"
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
assert a["topics"] == b["topics"], "topics differed after body growth"
assert a["coverage"]["matched"] == b["coverage"]["matched"]
PYEOF
cp "$work/small.md" "$a/backlog/retry-storm.md"

# --- 3. CAP-1: two invocations straddling a fixture change differ EXACTLY there --
MAP > "$work/before.json" 2>/dev/null
MAP > "$work/before2.json" 2>/dev/null
cmp -s "$work/before.json" "$work/before2.json" \
  && ok "CAP-1: two invocations over unchanged state are byte-identical (pure derivation)" \
  || err "the map is not deterministic over unchanged state"

backlog_item token-budget engineering seed "host/bill.md:2@abc1234" "SENTINEL-BODY-DELTA"
MAP > "$work/after.json" 2>/dev/null
python3 - "$work/before.json" "$work/after.json" <<'PYEOF' && ok "CAP-1: the map differs exactly where the repo changed (one new item, nothing else)" || err "the map's diff does not match the repo change"
import json, sys
b = json.load(open(sys.argv[1])); a = json.load(open(sys.argv[2]))
def items(d):
    return {i["surface"] for t in d["topics"] for i in t["items"]}
added = items(a) - items(b)
assert added == {"backlog/token-budget.md"}, added
assert items(b) - items(a) == set()
# everything else is untouched
for key in ("track_topics", "unmapped_tracks", "stale_mapping_tracks"):
    assert b[key] == a[key], (key, b[key], a[key])
assert a["coverage"]["matched"] == b["coverage"]["matched"] + 1
PYEOF

# Removing the item removes it again — no ledger remembers it.
rm "$a/backlog/token-budget.md"
MAP > "$work/after2.json" 2>/dev/null
cmp -s "$work/before.json" "$work/after2.json" \
  && ok "CAP-1: removing the fixture restores the earlier map byte-for-byte (nothing accumulated)" \
  || err "a removed item left a trace — something is stored"

# --- 4. CAP-1: no stored index anywhere; the debug dump is never read back -------
MAP --emit-debug "$work/debug.json" > /dev/null 2>&1
[ -s "$work/debug.json" ] && ok "--emit-debug writes a debug dump" \
  || err "--emit-debug wrote nothing"
# Poison the dump: if any code path read it back, the map would change.
python3 - "$work/debug.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["topics"] = [{"topic": "POISON", "mapped": True, "tracks": [], "item_count": 0, "items": []}]
json.dump(d, open(sys.argv[1], "w"))
PYEOF
MAP --emit-debug "$work/debug2.json" > "$work/m2.json" 2>/dev/null
grep -q 'POISON' "$work/m2.json" \
  && err "the map read a previously emitted dump back (a stored index)" \
  || ok "CAP-1: a poisoned debug dump does not influence the next map (write-only artifact)"
rm -f "$work/debug.json" "$work/debug2.json"
MAP > "$work/m3.json" 2>/dev/null
cmp -s "$work/before.json" "$work/m3.json" \
  && ok "CAP-1: deleting the debug dumps loses nothing" \
  || err "deleting the debug dumps changed the map"

# The assembler creates NO state in the articles repo or the machine-global dirs.
for p in "$a/.topic-map" "$a/topic-map.json" "$a/.topics" "$a/topics.json" \
         "$a/backlog/.index" "$a/INDEX.topics.md"; do
  [ -e "$p" ] && err "a stored topic index appeared at $p"
done
if [ -d "$work/state" ] && find "$work/state" -name '*topic*' | grep -q .; then
  err "a topic index was written into machine-global state"
else
  ok "CAP-1: no stored topic index exists anywhere (repo or machine state)"
fi

# Source-level: nothing in the implementation reads a map back.
grep -nE 'json\.load\(|read_map|load_map|cached_map|--from-cache|--map-file' "$M" \
  && err "topic-map.py contains a map-reading code path" \
  || ok "CAP-1: no map-reading code path exists in the implementation"

# --- 5. CAP-4: an over-bound invocation NAMES what it skipped -------------------
MAP --max-surfaces 2 > "$work/bound.json" 2>/dev/null
python3 - "$work/bound.json" <<'PYEOF' && ok "CAP-4: the bound truncates and the coverage manifest NAMES every skipped surface" || err "over-bound disclosure wrong"
import json, sys
d = json.load(open(sys.argv[1]))
cov = d["coverage"]
assert cov["bound"] == 2, cov
assert cov["complete"] is False, cov
assert len(cov["read"]) == 2, cov["read"]
assert cov["skipped"], "nothing disclosed as skipped"
# each skipped surface is NAMED, with a reason (harvest's shape)
for s in cov["skipped"]:
    assert s["surface"] and s["reason"], s
    assert "read bound" in s["reason"], s
names = {s["surface"] for s in cov["skipped"]}
assert "backlog/team-shape.md" in names, names
# the closed accounting harvest's manifest carries
assert cov["accounting_closes"] is True, cov
assert len(cov["read"]) + len(cov["skipped"]) == cov["matched"], cov
PYEOF

python3 - "$work/before.json" <<'PYEOF' && ok "CAP-4: an unbounded run reports complete coverage with a pin and closed accounting" || err "unbounded coverage manifest wrong"
import json, sys
cov = json.load(open(sys.argv[1]))["coverage"]
assert cov["complete"] is True and cov["skipped"] == [], cov
assert cov["pin"], cov
assert len(cov["read"]) == cov["matched"], cov
assert "index and frontmatter only" in cov["surfaces_read"], cov
PYEOF

# `surfaces` enumerates index/frontmatter surfaces only — never body files.
python3 "$M" surfaces --root "$h" > "$work/surfaces.txt" 2>/dev/null
grep -q '^INDEX.md$' "$work/surfaces.txt" \
  && ok "surfaces: the INDEX file is an index surface the map reads" \
  || err "INDEX.md missing from the surface list"
python3 "$M" surfaces --root "$h" --max-surfaces 2 | wc -l | grep -q '^ *2$' \
  && ok "surfaces: the read bound applies to the enumeration too" \
  || err "surfaces ignored --max-surfaces"

# --- 6. track_topics: the map reads the declared mapping, never invents topics ---
printf '{"engineering": "delivery", "ghost": "nowhere"}' | \
  python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
    set-policy-source --track-topics >/dev/null 2>&1
MAP > "$work/mapped.json" 2>/dev/null
python3 - "$work/mapped.json" <<'PYEOF' && ok "track_topics: mapped tracks resolve to hub topic names; a stale mapping track is disclosed" || err "track_topics wiring wrong"
import json, sys
d = json.load(open(sys.argv[1]))
topics = {t["topic"]: t for t in d["topics"]}
assert "delivery" in topics, topics.keys()
assert topics["delivery"]["mapped"] is True and topics["delivery"]["tracks"] == ["engineering"], topics["delivery"]
assert "engineering" not in topics, topics.keys()
assert "people" in topics and topics["people"]["mapped"] is False, topics.keys()
assert d["stale_mapping_tracks"] == ["ghost"], d["stale_mapping_tracks"]
PYEOF

# --- 7. consumption is READ from its one implementation, not re-implemented -----
cat > "$a/plans/retry-storm.md" <<'EOF'
---
kind: article-plan
slug: retry-storm
intent: share engineering lessons
claim: structured discovery paid off
status: drafted
run_id: 20260722T090000-000001
pin: host@a1b2c3d4e5f6a7b8
consumed: [el-retry-storm]
---

## Section plan

- the retry-storm lesson / host/log.txt:12@a1b2c3d4e5f6a7b8
EOF
MAP > "$work/consumed.json" 2>/dev/null
python3 - "$work/consumed.json" <<'PYEOF' && ok "consumption: the map carries the SHIPPED derived view (write-article-plan.py consult), not a second copy" || err "consumption view not wired"
import json, sys
c = json.load(open(sys.argv[1]))["consumption"]
assert c["available"] is True, c
assert c["source"] == "write-article-plan.py consult", c
assert c["derived_not_stored"] is True, c
assert "el-retry-storm" in c["consumed_index"], c
PYEOF
rm "$a/plans/retry-storm.md"
MAP > "$work/unconsumed.json" 2>/dev/null
python3 - "$work/unconsumed.json" <<'PYEOF' && ok "consumption: removing the plan empties the view (regenerated, never a ledger)" || err "consumption view did not regenerate"
import json, sys
c = json.load(open(sys.argv[1]))["consumption"]
assert c["consumed_index"] == {}, c
PYEOF

# --- 7b. the hub-lessons family: LESSONS.md index lines as lesson seeds -------
# Served through the shipped seam only. The stub's LESSONS.md carries a body
# sentinel in its hook text position and a non-index heading line, so "index
# lines only" is asserted rather than assumed.
python3 - "$FX" <<'PYEOF'
import json, sys
sha = "0123456789abcdef0123456789abcdef01234567"
json.dump({
    "pin": f"product-lab@{sha}",
    "lessons": [
        ["LESSONS.md", 1, "# Lessons"],
        ["LESSONS.md", 3, "- [The retry storm](lessons/retry-storm.md) - SENTINEL-HOOK-ALPHA"],
        ["LESSONS.md", 4, "- [Cache warmth](lessons/cache-warmth.md) - SENTINEL-HOOK-BETA"],
        ["LESSONS.md", 5, "- [Team shape](lessons/team-shape.md) - SENTINEL-HOOK-GAMMA"],
    ],
}, open(sys.argv[1], "w"))
PYEOF
MAP > "$work/lessons.json" 2>"$work/lessons.err" \
  && ok "hub-lessons: the map assembles with the family enumerated" \
  || err "assemble failed with a served LESSONS.md: $(cat "$work/lessons.err")"

python3 - "$work/lessons.json" <<'PYEOF' && ok "hub-lessons: one seed per INDEX LINE, tagged with its family, cited at its true line number" || err "lesson seeds wrong"
import json, sys
d = json.load(open(sys.argv[1]))
seeds = [i for t in d["topics"] for i in t["items"] if i.get("family") == "hub-lessons"]
assert {i["slug"] for i in seeds} == {"retry-storm", "cache-warmth", "team-shape"}, seeds
one = [i for i in seeds if i["slug"] == "cache-warmth"][0]
assert one["title"] == "Cache warmth", one
# the seam's own file:line@commit cite, passed through, not recomposed
assert one["evidence"] == ["LESSONS.md:4@0123456789abcdef0123456789abcdef01234567"], one
# the heading line is not an index line
assert not any(i["slug"].startswith("lessons") for i in seeds), seeds
# a seed is available material, not a live article item
assert one["live"] is False, one
PYEOF

grep -q 'SENTINEL-HOOK' "$work/lessons.json" \
  && err "a lesson hook reached the map — more than the index line's title was projected" \
  || ok "hub-lessons: only the index line's title is projected (no hook prose, no lesson body)"

python3 - "$work/lessons.json" <<'PYEOF' && ok "hub-lessons: seeds cluster alongside items and count toward the subtopic's density signal (CAP-2)" || err "lesson seeds do not participate in clustering"
import json, sys
d = json.load(open(sys.argv[1]))
topics = {t["topic"]: t for t in d["topics"]}
# the family enters the topic derivation through the shipped track->topic path
assert "hub-lessons" in topics, topics.keys()
assert "hub-lessons" in d["unmapped_tracks"], d["unmapped_tracks"]
subs = {s["subtopic"]: s for s in topics["hub-lessons"]["subtopics"]}
assert "team-shape" in subs, subs.keys()
s = subs["team-shape"]
assert s["density"]["evidence_pointers"] == 1, s["density"]
assert s["density"]["unconsumed_lessons"] == 1, s["density"]
assert s["depth"]["level"], s["depth"]          # a depth estimate, like any subtopic
assert s["selectable"] is True, s               # thresholds gate surfacing, never picking
PYEOF

python3 - "$work/lessons.json" <<'PYEOF' && ok "CAP-4: the manifest names BOTH enumerated families and the per-family accounting closes" || err "per-family manifest wrong"
import json, sys
cov = json.load(open(sys.argv[1]))["coverage"]
assert cov["families_enumerated"] == ["articles-items", "hub-lessons"], cov["families_enumerated"]
assert cov["families_not_enumerated"] == [], cov["families_not_enumerated"]
fams = {f["family"]: f for f in cov["families"]}
assert fams["hub-lessons"]["matched"] == 3, fams["hub-lessons"]
for f in fams.values():
    assert f["accounting_closes"] is True and f["read"] + f["skipped"] == f["matched"], f
assert sum(f["matched"] for f in fams.values()) == cov["matched"], cov
assert cov["accounting_closes"] is True and cov["complete"] is True, cov
PYEOF

# The bound truncates the later family and NAMES what it skipped, per family.
MAP --max-surfaces 6 > "$work/lbound.json" 2>/dev/null
python3 - "$work/lbound.json" <<'PYEOF' && ok "CAP-4: an over-bound run keeps the closed accounting PER FAMILY and names the skipped surfaces with their family" || err "per-family accounting does not close under the bound"
import json, sys
cov = json.load(open(sys.argv[1]))["coverage"]
assert cov["complete"] is False, cov
fams = {f["family"]: f for f in cov["families"]}
assert fams["hub-lessons"]["skipped"] > 0, fams["hub-lessons"]
for f in fams.values():
    assert f["accounting_closes"] is True, f
for s in cov["skipped"]:
    assert s["family"] and s["surface"] and "read bound" in s["reason"], s
assert len(cov["read"]) + len(cov["skipped"]) == cov["matched"], cov
PYEOF

# Consumed material is MARKED, never hidden (CAP-9 / Story 18.47).
cat > "$a/plans/team-shape.md" <<'EOF'
---
kind: article-plan
slug: team-shape
intent: share engineering lessons
claim: small teams ship
status: drafted
run_id: 20260722T090000-000002
pin: host@a1b2c3d4e5f6a7b8
consumed: [team-shape]
---

## Section plan

- the team-shape lesson / host/notes.md:9@a1b2c3d4e5f6a7b8
EOF
MAP > "$work/lconsumed.json" 2>/dev/null
python3 - "$work/lconsumed.json" <<'PYEOF' && ok "hub-lessons: a consumed seed is MARKED consumed and still surfaced (never hidden, still selectable)" || err "consumed lesson seed handling wrong"
import json, sys
d = json.load(open(sys.argv[1]))
topics = {t["topic"]: t for t in d["topics"]}
subs = {s["subtopic"]: s for s in topics["hub-lessons"]["subtopics"]}
s = subs["team-shape"]
assert s["consumed"] is True and s["selectable"] is True, s
assert s["density"]["unconsumed_lessons"] == 0, s["density"]
assert subs["retry-storm"]["consumed"] is False, subs["retry-storm"]
PYEOF
rm "$a/plans/team-shape.md"

# A degraded policy source is a DISCLOSED family, and the map still produces a
# result — the disclosed-refusal shape, never a silent empty family.
saved_gw="$WRITING_ASSISTANT_GATEWAY_CMD"
WRITING_ASSISTANT_GATEWAY_CMD="python3 $work/no-such-gateway.py"
MAP > "$work/degraded.json" 2>/dev/null \
  && ok "hub-lessons: an unreachable gateway still yields a map (exit 0)" \
  || err "a degraded policy source broke the map instead of being disclosed"
WRITING_ASSISTANT_GATEWAY_CMD="$saved_gw"
python3 - "$work/degraded.json" <<'PYEOF' && ok "hub-lessons: a degraded policy source is disclosed as declared-but-not-enumerated WITH THE REASON" || err "degraded policy source not disclosed"
import json, sys
d = json.load(open(sys.argv[1]))
cov = d["coverage"]
hl = {f["family"]: f for f in cov["families"]}["hub-lessons"]
assert hl["declared"] is True and hl["enumerated"] is False, hl
assert hl["reason"], hl
assert cov["families_not_enumerated"][0]["family"] == "hub-lessons", cov
# the articles-items family is untouched — one family degrading narrows nothing else
assert "articles-items" in cov["families_enumerated"], cov
assert [i for t in d["topics"] for i in t["items"]], "the map lost its items"
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
# targets re-derivation directly, over the comment-stripped code: topic-map.py
# must never read `plans/` itself, and the view must come from
# `write-article-plan.py consult`.
grep -qE "plans" "$CODE" \
  && err "topic-map.py reads plans/ itself (the consumption view must come from consult)" \
  || ok "consumption: topic-map.py never reads plans/ — no second derivation of the predicate"
grep -q 'PLAN_WRITER' "$M" \
  && ok "consumption: the view is read from the shipped write-article-plan.py consult" \
  || err "topic-map.py does not read the shipped consumption view"
# CAP-2 (depth signals) SHIPPED with Story 18.62 (#588) and has its own harness
# (check-topic-map-depth.sh). What must stay true here is that no depth boundary
# is hardcoded in stage code: the numbers live in the declaration file alone.
grep -qiE 'seed-only|short note|article series' "$CODE" \
  && err "topic-map.py hardcodes a depth level name (the levels are declared data)" \
  || ok "scope: no depth level is hardcoded (the boundaries stay declared)"
grep -qE 'min_evidence_pointers *= *[0-9]|min_live_items *= *[0-9]' "$CODE" \
  && err "topic-map.py hardcodes a threshold value (it must read the declaration)" \
  || ok "scope: no threshold value is hardcoded in stage code"
grep -qiE 'approve/modify|proposal contract|candidate direction|screen' "$CODE" \
  && err "topic-map.py builds a presentation screen (CAP-3 belongs to a sibling story)" \
  || ok "scope: no presentation screen is built (CAP-3 left to its own story)"
grep -qiE 'narrative structure|structure candidate|compose.*structure' "$CODE" \
  && err "topic-map.py composes narrative structures (18.45 single-proposer invariant)" \
  || ok "scope: the map composes no narrative structures (single-proposer invariant intact)"
# CAP-4's cost promise as amended: widening the corpus must NOT pull in
# harvest's per-source budgeted extraction. The map stays index-scale. The
# check is a CLOSED SET of sibling scripts the map may reach for — adding one
# is a reviewed decision, not a drive-by import, and no fact-sheet reader or
# harvest cache is on it.
python3 - "$M" <<'PYEOF' && ok "CAP-4: the map reaches only for its declared resolvers/seams — no harvest pass, no fact-sheet extractor (cost stays index-scale)" || err "topic-map.py reaches for a script outside its allowed set (an extraction pass would make the map corpus-scale)"
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
}
extra = sorted(named - allowed)
assert not extra, f"unreviewed sibling scripts: {extra}"
PYEOF
# The hub-lessons family goes through the SHIPPED seam — never a second reader.
grep -q 'POLICY_READER' "$M" \
  && ok "hub-lessons: the family is served by the shipped read-policy-source.py seam" \
  || err "topic-map.py does not read the policy source through the shipped seam"
grep -qE 'lessons_index|LESSONS\.md.*open\(|policy_lookup' "$CODE" \
  && err "topic-map.py talks to the gateway itself (the seam is the only reader)" \
  || ok "hub-lessons: no second policy reader exists in the implementation"

# --- 9. an unresolvable articles repo is a disclosed refusal, not a silent map ---
h2="$work/host2"; mkdir -p "$h2"; git -C "$h2" init -q
if python3 "$M" assemble --root "$h2" > "$work/none.json" 2>"$work/none.err"; then
  rc=0
else
  rc=$?
fi
[ "$rc" -eq 3 ] && ok "no articles repo -> exit 3 (a disclosed refusal, never a silent empty map)" \
  || err "expected exit 3 for an unresolvable articles repo, got $rc"
grep -q 'output.drafts' "$work/none.err" \
  && ok "the refusal names the declaration that is missing" \
  || err "the refusal does not name output.drafts"

if [ "$fail" -eq 0 ]; then
  printf '\nAll topic-map checks passed.\n'; exit 0
else
  printf '\ntopic-map checks FAILED.\n' >&2; exit 1
fi
