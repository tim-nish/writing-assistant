#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
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

M="scripts/terrain_map.py"
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
  "1111111111111111111111111111111111111111" > "$FX"
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
assert set(fams) == {"articles-items", "hub-lessons", "host-sources",
                     "hub-elements", "hub-gloss"}, fams.keys()
assert all(d["family"] == "articles-items" for d in cov["read"]), cov["read"]
assert fams["articles-items"]["enumerated"] is True, fams["articles-items"]
# declared, not enumerated, and the reason is NAMED — never a silent empty family
for name in ("hub-lessons", "host-sources", "hub-elements", "hub-gloss"):
    f = fams[name]
    assert f["declared"] is True and f["enumerated"] is False, f
    assert f["reason"], f
    assert f["matched"] == 0 and f["accounting_closes"] is True, f
assert cov["families_enumerated"] == ["articles-items"], cov["families_enumerated"]
assert [f["family"] for f in cov["families_not_enumerated"]] == [
    "hub-lessons", "host-sources", "hub-elements", "hub-gloss"], cov
assert cov["families_not_enumerated"][0]["reason"] == fams["hub-lessons"]["reason"], cov
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
  && err "terrain_map.py contains a map-reading code path" \
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

# --- 6b. hub-elements: the second projection (Story 18.79, #640) ---------------
# Three declared topics, two servable, so the seam bound (2 per read) is
# exercised for real rather than assumed. `zeta` is declared and never read.
python3 - "$FX" <<'PYEOF'
import json, sys
fx = json.load(open(sys.argv[1]))
sha = "1111111111111111111111111111111111111111"
fx["topics"] = {
    "delivery": [
        ["topics/delivery.md", 1, "# delivery"],
        ["topics/delivery.md", 3, "- 2026-07-20 — Ship behind a flag; the rollback path is the feature. (q_a/x D1)"],
        ["topics/delivery.md", 4, "- 2026-07-19 — ~~Weekly release train~~ superseded 2026-07-20 by continuous deploy."],
        ["topics/delivery.md", 6, "## Declined (things considered and rejected)"],
        ["topics/delivery.md", 7, "- 2026-07-18 — Blue/green for every service: rejected, the fleet is too small."],
        ["topics/delivery.md", 9, "not a dated line, so not an element"],
    ],
    "nowhere": [
        ["topics/nowhere.md", 1, "# nowhere"],
        ["topics/nowhere.md", 2, "- 2026-07-21 — A decision that mentions a declined option inline, declined as a copy. (q_a/y D2)"],
    ],
    "zeta": [["topics/zeta.md", 2, "- 2026-07-01 — Never read: past the seam bound."]],
}
fx["surface"] = dict(fx.get("surface", {}), topics=["delivery", "nowhere", "zeta"])
json.dump(fx, open(sys.argv[1], "w"))
PYEOF
printf '{"engineering": "delivery", "ghost": "nowhere", "extra": "zeta"}' | \
  python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
    set-policy-source --track-topics >/dev/null 2>&1
MAP > "$work/elements.json" 2>/dev/null
python3 - "$work/elements.json" <<'PYEOF' && ok "hub-elements: decisions and reversals are projected, typed by their native markers, bounded and disclosed" || err "the element projection is wrong"
import json, sys
d = json.load(open(sys.argv[1]))
els = d["elements"]
by_cite = {e["situation"].split("@")[0]: e for e in els}
kinds = {c: e["kind"] for c, e in by_cite.items()}

# Typed by the markers the served surface actually uses.
assert kinds.get("topics/delivery.md:3") == "decision", kinds
assert kinds.get("topics/delivery.md:4") == "reversal", kinds   # struck-through
assert kinds.get("topics/delivery.md:7") == "reversal", kinds   # under ## Declined
# The word "declined" INSIDE an ordinary decision line must not type it as a
# reversal — section membership is the marker, not the word.
assert kinds.get("topics/nowhere.md:2") == "decision", kinds
# A non-dated line is not an element at all.
assert "topics/delivery.md:9" not in kinds, kinds
# The heading itself is never an element.
assert "topics/delivery.md:6" not in kinds, kinds

e = by_cite["topics/delivery.md:3"]
assert e["date"] == "2026-07-20" and e["topic"] == "delivery", e
assert e["evidence"] == [e["situation"]] and "@" in e["situation"], e
assert e["consumed"] is False and e["consumption_join"], e
# The q_a/ provenance pointer is the hub's bookkeeping, not the decision.
assert "q_a/" not in e["summary"], e["summary"]

# Ranked by recency, deterministically — the property the E<topic>.<n> indexes
# assigned downstream depend on.
assert [x["date"] for x in els] == sorted((x["date"] for x in els), reverse=True), els

# The seam bound is real: `zeta` is declared, never read, and NAMED as skipped.
cov = d["coverage"]
assert cov["element_topics_read"] == ["delivery", "nowhere"], cov["element_topics_read"]
assert cov["element_topics_skipped"] == ["zeta"], cov["element_topics_skipped"]
assert not any(e["topic"] == "zeta" for e in els), "an unread topic produced elements"
skipped = [s for s in cov["skipped"] if s["family"] == "hub-elements"]
assert len(skipped) == 1 and "seam" in skipped[0]["reason"], skipped
assert cov["complete"] is False, cov          # a bounded run says so
fams = {f["family"]: f for f in cov["families"]}
f = fams["hub-elements"]
assert f["enumerated"] is True and f["matched"] == 3, f
assert f["read"] == 2 and f["skipped"] == 1 and f["accounting_closes"] is True, f

# Elements are a SECOND projection: they never become clustered items.
items = [i for t in d["topics"] for i in t["items"]]
assert not any(i.get("family") == "hub-elements" for i in items), "elements leaked into items"
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
sha = "1111111111111111111111111111111111111111"
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
assert one["evidence"] == ["LESSONS.md:4@" + "1" * 40], one
# the heading line is not an index line
assert not any(i["slug"].startswith("lessons") for i in seeds), seeds
# a seed is available material, not a live article item
assert one["live"] is False, one
PYEOF

grep -q 'SENTINEL-HOOK' "$work/lessons.json" \
  && err "a lesson hook reached the map — more than the index line's title was projected" \
  || ok "hub-lessons: only the index line's title is projected (no hook prose, no lesson body)"

# --- 7c. topic↔evidence usability join (Story 18.96, #669) --------------------
# With no journey record declared, every hub-lesson candidate is
# episodic-unrecorded and surfaced in needs_recording — never silently dropped.
python3 - "$work/lessons.json" <<'PYEOF' && ok "#669: unmatched hub lessons are episodic-unrecorded, surfaced as NEEDS-RECORDING (never dropped)" || err "usability join / needs_recording wrong with no journey"
import json, sys
d = json.load(open(sys.argv[1]))
seeds = [i for t in d["topics"] for i in t["items"] if i.get("family") == "hub-lessons"]
assert seeds, "no hub-lesson seeds"
assert all(i["usability"]["verdict"] == "episodic-unrecorded" for i in seeds), \
    [i.get("usability") for i in seeds]
nr = {t["slug"]: t for t in d["needs_recording"]}
assert {"retry-storm", "cache-warmth", "team-shape"} <= set(nr), nr
one = nr["cache-warmth"]
assert one["target_file"].endswith("journey.md") and one["episode"], one
PYEOF

# Declare a journey record carrying ONE lesson's slug -> that candidate MATCHES;
# the others stay episodic-unrecorded (three-valued, never collapsed).
mkdir -p "$h/docs"
printf '2026-07-01 · the retry storm doubled token spend (event) · #665 · retry-storm\n' \
  > "$h/docs/journey.md"
cfg=$(find "$work/xdg" -name writing-sources.yaml | head -1)
printf '\njourney:\n  - docs/journey.md\n' >> "$cfg"
MAP > "$work/lessons2.json" 2>"$work/l2.err" \
  && ok "#671/#669: the map assembles with a declared journey record" \
  || err "assemble failed with a journey declared: $(cat "$work/l2.err")"
python3 - "$work/lessons2.json" <<'PYEOF' && ok "#669: a lesson whose slug a journey entry carries is MATCHED; others stay episodic-unrecorded" || err "journey match verdict wrong"
import json, sys
d = json.load(open(sys.argv[1]))
seeds = {i["slug"]: i for t in d["topics"] for i in t["items"]
         if i.get("family") == "hub-lessons"}
assert seeds["retry-storm"]["usability"]["verdict"] == "matched", \
    seeds["retry-storm"]["usability"]
assert seeds["retry-storm"]["usability"]["checked"], \
    "a matched verdict must carry the pointers checked (audited)"
assert seeds["cache-warmth"]["usability"]["verdict"] == "episodic-unrecorded", \
    seeds["cache-warmth"]["usability"]
nr = {t["slug"] for t in d["needs_recording"]}
assert "retry-storm" not in nr and "cache-warmth" in nr, nr
PYEOF

# The SKILL presents the verdicts and never silently filters to matched.
# Story 20.64 (#962): dispatcher + step companions — assert over the family.
__tsk=$(cat skills/terrain/SKILL.md skills/terrain/steps/*.md)
printf '%s' "$__tsk" | grep -qi 'never silently' \
  && printf '%s' "$__tsk" | grep -q 'needs_recording' \
  && printf '%s' "$__tsk" | grep -qi 'no-episode' \
  && ok "#669: topic-map SKILL presents verdicts + NEEDS-RECORDING, never silently filters" \
  || err "topic-map SKILL missing the usability-verdict presentation"

# --- 7d. the stance-3 pivot (#799): elements primary, the Gloss quoted -------
# With the two-tier gloss surface served (`gloss_index`, tsurezure-gateway#64),
# every hub Lesson is a PRIMARY element quoting the ratified `gloss:` rendering
# — never the recall one-liner — and a journey-named index path yields journey
# elements quoting `journey_gloss:`. Every element carries its VISIBLE
# three-valued usability verdict, verdicts never filter, and the map names the
# recording target a gap artifact lands in.
python3 - "$FX" <<'PYEOF'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["tools"] = ["glossary_entry", "lessons_index", "topic_thread",
               "policy_lookup", "surface_names", "gloss_index"]
fx["gloss_index"] = [
    ["gloss/INDEX.md", 8,
     "- **retry-storm** — GLOSS-ALPHA retries multiply their own load. (agents, cost) · journeys/agents"],
    ["gloss/INDEX.md", 9,
     "- **cache-warmth** — GLOSS-BETA a warm cache hides every cold start. (testing)"],
]
# The tier-2 journey shard the tier-1 marker names. Journeys are REQUESTED
# (Story 20.30, #871): the arc arrives from `gloss --tag journeys/<tag>`, not
# from a tier-1 journeys index — the hub publishes no such index, which is why
# `journey_renderings` was 0 on every real run before the tagged read shipped.
fx["gloss_shards"] = {
    "journeys/agents": [
        ["gloss/journeys/agents.md", 4,
         "## retry-storm"],
        ["gloss/journeys/agents.md", 6,
         "JOURNEY-ALPHA the belief inverted after the retro."],
    ],
}
json.dump(fx, open(sys.argv[1], "w"))
PYEOF
MAP > "$work/pivot.json" 2>"$work/pivot.err" \
  && ok "#799: the map assembles with the gloss surface served" \
  || err "assemble failed with gloss served: $(cat "$work/pivot.err")"

python3 - "$work/pivot.json" <<'PYEOF' && ok "#799/#871: every Lesson is a primary element and its Journey rides its row; the slot quotes the served gloss, never the one-liner; team-shape's absent rendering is disclosed" || err "element pivot wrong in the assembled map"
import json, sys
d = json.load(open(sys.argv[1]))
els = {(e["kind"], e.get("slug")): e for e in d["elements"]}
assert ("lesson", "retry-storm") in els and ("lesson", "cache-warmth") in els \
    and ("lesson", "team-shape") in els, sorted(els)
# A Journey is NOT an element of its own (Story 20.30, #871): the arc
# attaches to its lesson's row, and the J namespace is retired.
assert not any(k == "journey" for k, _ in els), sorted(els)
rs = els[("lesson", "retry-storm")]
# The slot's quote is the SERVED rendering, verbatim — never the recall
# one-liner ("The retry storm", the LESSONS.md link text).
assert rs["gloss"].startswith("GLOSS-ALPHA"), rs["gloss"]
assert rs["gloss_cite"].startswith("gloss/INDEX.md:8@"), rs["gloss_cite"]
# The tier-1 journey marker (hub specs/gloss.md §5.1) never swallows the tags
# — and the shard address it names is kept for journey discovery.
assert rs["tags"] == ["agents", "cost"], rs["tags"]
assert rs["journey_shard"] == "journeys/agents", rs.get("journey_shard")
assert "journeys/" not in rs["gloss"], rs["gloss"]
assert "The retry storm" not in (rs["gloss"] or ""), rs
# The arc rides the LESSON, quoting the served rendering verbatim.
assert rs["journey"].startswith("JOURNEY-ALPHA"), rs.get("journey")
assert rs["journey_cite"].startswith("gloss/journeys/agents.md:"), rs.get("journey_cite")
# A lesson whose tier-1 line names no shard is NOT REQUESTED, and says so —
# never reported as the hub failing to serve.
cw = els[("lesson", "cache-warmth")]
assert cw.get("journey") is None and "not requested" in (cw.get("journey_unavailable") or ""), cw
# A lesson the served index carries no rendering for DISCLOSES that — nothing
# is substituted for a ratified rendering.
ts = els[("lesson", "team-shape")]
assert ts["gloss"] is None and ts["gloss_unavailable"], ts
# Every element carries its VISIBLE verdict; the journey record declared above
# still matches retry-storm, and the others stay episodic-unrecorded.
assert all(e.get("usability", {}).get("verdict") for e in d["elements"]), \
    [e.get("usability") for e in d["elements"]]
assert els[("lesson", "retry-storm")]["usability"]["verdict"] == "matched"
assert els[("lesson", "cache-warmth")]["usability"]["verdict"] == "episodic-unrecorded"
# The gap artifact's destination is named on the map.
assert d["recording_target"]["file"].endswith("journey.md"), d["recording_target"]
assert d["gloss"]["served"] is True and d["gloss"]["journey_renderings"] == 1, d["gloss"]
assert d["gloss"]["journeys_requested"] == ["journeys/agents"], d["gloss"]
fams = {f["family"]: f for f in d["coverage"]["families"]}
assert fams["hub-gloss"]["enumerated"] is True, fams["hub-gloss"]
PYEOF

# The directions surface: elements are individually selectable ideas with their
# verdicts visible; selecting an unmatched one yields the brief PLUS the gap
# disclosure and its NEEDS-RECORDING artifact content — never a refusal.
DIR="$root/scripts/topic-map-directions.py"
python3 "$DIR" candidates --map "$work/pivot.json" > "$work/pivot-cands.json"
python3 - "$work/pivot-cands.json" <<'PYEOF' && ok "#799/#871: N elements are N selectable candidates (L namespace; J retired), each quoting the gloss with its verdict attached" || err "element candidates wrong"
import json, sys
c = json.load(open(sys.argv[1]))["candidates"]
els = {x["id"]: x for x in c if x.get("kind") == "element"}
# Lesson ids in slug-sorted order. The J namespace is RETIRED (Story 20.30,
# #871): an arc is not separately selectable, so it mints no candidate.
assert {"L1", "L2", "L3"} <= set(els), sorted(els)
assert not any(i.startswith("J") for i in els), sorted(els)
assert els["L1"]["slug"] == "cache-warmth" and els["L2"]["slug"] == "retry-storm", els
assert "GLOSS-ALPHA" in els["L2"]["direction"], els["L2"]["direction"]
# The one-liner is identification, never the quote.
assert "The retry storm" not in els["L2"]["direction"], els["L2"]
assert els["L2"]["usability"]["verdict"] == "matched", els["L2"]
assert els["L1"]["usability"]["verdict"] == "episodic-unrecorded", els["L1"]
PYEOF

pivotpin=$(python3 -c "import json;print(json.load(open('$work/pivot.json'))['coverage']['pin'])")
printf '{"index":"L1","note":"the cold-start angle","pin":"%s"}' "$pivotpin" > "$work/pivot-answer.json"
python3 "$DIR" brief --answer "$work/pivot-answer.json" --map "$work/pivot.json" \
  > "$work/pivot-brief.json" 2>"$work/pivot-brief.err" \
  && ok "#799: selecting an episodic-unrecorded element STILL yields a brief (exit 0, never a refusal)" \
  || err "an unmatched element selection was refused: $(cat "$work/pivot-brief.err")"
python3 - "$work/pivot-brief.json" <<'PYEOF' && ok "#799: the unmatched selection carries the gap disclosure + NEEDS-RECORDING artifact content beside the brief" || err "gap disclosure wrong on the brief"
import json, sys
b = json.load(open(sys.argv[1]))
assert b["brief"].startswith("cover the lesson — GLOSS-BETA"), b["brief"]
assert b["brief"].endswith("the cold-start angle"), b["brief"]
# `gaps`, NOT `gap` (Story 20.99, #1077). The singular carried member[0]'s
# record beside the plural and read as "the selection"; a one-member selection
# is the degenerate case of a set and now takes the same path and the same key.
# Every assertion below is unchanged — only where the record is read from.
assert "gap" not in b, sorted(b)
assert len(b["gaps"]) == 1, b["gaps"]
gap = b["gaps"][0]
assert gap["index"] == "L1", gap
assert gap["verdict"] == "episodic-unrecorded", gap
assert "never" in gap["drafting"] and "gate" in gap["drafting"], gap
nr = gap["needs_recording"]
assert nr["slug"] == "cache-warmth" and nr["target_file"].endswith("journey.md"), nr
assert nr["heading"] == "NEEDS-RECORDING" and nr["entry"], nr
# Story 20.91 (#1044) AC2: with NO arc served, the absence is still reported —
# and it says WHICH absence it is, in the kind Story 20.90 carries. "No arc
# exists" and "no arc arrived" must not collapse into one finding.
ep = gap["episode"]
assert ep["served"] is False and ep["arc"] is None, ep
assert "not requested" in (ep["not_served_reason"] or ""), ep
assert "host_join" not in gap, gap
PYEOF

# --- 7f. an episode the system is CARRYING is not an absent one (#1044, 20.91)
# Same fixture, unit-exact: a selected Strand whose host-repo join found nothing
# but whose served arc IS present is not reported `episodic-unrecorded`. The
# host verdict is kept under `host_join`, the arc travels quoted at its cite,
# and the NEEDS-RECORDING task is STILL minted — recording host-side feeds
# evidence, the arc is material that already existed; adjacent, never
# substitutes (AC3/AC4).
python3 - <<PYEOF && ok "#1044/20.91: a served arc is reported as episode-served, keeps host_join, and still mints NEEDS-RECORDING" || err "the served-arc gap disclosure is wrong"
import sys
sys.path.insert(0, "$root/scripts")
from terrain_select import _selection_gap
target = {"repo": "host", "file": "docs/journey.md"}
served = {"kind": "element", "slug": "retry-storm",
          "journey": "JOURNEY-ALPHA the belief inverted after the retro.",
          "journey_cite": "gloss/journeys/agents.md:6@" + "1" * 40,
          "usability": {"verdict": "episodic-unrecorded", "checked": ["docs/journey.md"]}}
g = _selection_gap(served, target)
assert g["verdict"] == "episode-served", g
assert g["host_join"]["verdict"] == "episodic-unrecorded", g
assert g["host_join"]["checked"] == ["docs/journey.md"], g
assert "NOT an unrecorded episode" in g["disclosure"], g
# The arc is QUOTED, never re-expressed, and carries its cite (AC5).
assert g["episode"]["arc"] == served["journey"], g
assert g["episode"]["arc_cite"] == served["journey_cite"], g
assert g["episode"]["served"] is True, g
# AC4: the flow is unchanged and the relationship is STATED, not silently
# subsumed. AC3: the arc is material, never a Fact.
assert g["needs_recording"]["slug"] == "retry-storm", g
assert g["needs_recording"]["heading"] == "NEEDS-RECORDING", g
assert "adjacent, not substitutes" in g["disclosure"], g
assert "never a Fact" in g["disclosure"], g
assert "never" in g["drafting"] and "gate" in g["drafting"], g
# An arc-less Strand at the same verdict is UNCHANGED — the two findings stay
# distinct, and nothing here relabels an absence.
bare = dict(served, journey=None, journey_cite=None,
            journey_unavailable="requested journeys/agents and it did not arrive")
b = _selection_gap(bare, target)
assert b["verdict"] == "episodic-unrecorded", b
assert "host_join" not in b, b
assert b["episode"]["served"] is False, b
assert b["episode"]["not_served_reason"] == bare["journey_unavailable"], b
# A `no-episode` or `cannot-determine` verdict is never relabelled by an arc.
noep = dict(served, usability={"verdict": "no-episode", "checked": []})
assert _selection_gap(noep, target)["verdict"] == "no-episode", noep
PYEOF

# The step companion states the relationship rather than leaving it inferred.
__gapf=$(cat skills/terrain/steps/gap.md)
printf '%s' "$__gapf" | grep -q 'episode-served' \
  && printf '%s' "$__gapf" | grep -qi 'adjacent, not' \
  && printf '%s' "$__gapf" | grep -qi 'harvest' \
  && ok "#1044/20.91: gap.md states episode-served and the NEEDS-RECORDING relationship" \
  || err "gap.md missing the episode-served relationship note"

# A MATCHED selection carries no gap block — the verdict already located its
# evidence, and the brief is indistinguishable from any other.
printf '{"index":"L2","note":"","pin":"%s"}' "$pivotpin" > "$work/pivot-answer2.json"
python3 "$DIR" brief --answer "$work/pivot-answer2.json" --map "$work/pivot.json" \
  > "$work/pivot-brief2.json" 2>/dev/null
python3 - "$work/pivot-brief2.json" <<'PYEOF' && ok "#799: a matched element selection carries no gap block" || err "a matched selection grew a gap block"
import json, sys
b = json.load(open(sys.argv[1]))
assert "gap" not in b, b.get("gap")
assert "GLOSS-ALPHA" in b["brief"], b["brief"]
PYEOF

# Without gloss_index (an older gateway), the elements STILL exist — the pivot
# does not depend on the rendering being served — and the absent rendering is
# a named disclosure, never a silent fallback to the one-liner.
python3 - "$FX" <<'PYEOF'
import json, sys
fx = json.load(open(sys.argv[1]))
fx.pop("gloss_index", None)
fx.pop("tools", None)
json.dump(fx, open(sys.argv[1], "w"))
PYEOF
MAP > "$work/pivot-nogloss.json" 2>/dev/null \
  && ok "#799: an older gateway (no gloss_index) still yields a map" \
  || err "a gateway without gloss_index broke the map"
python3 - "$work/pivot-nogloss.json" <<'PYEOF' && ok "#799: without the served rendering the element survives, discloses the reason, and never quotes the one-liner as a gloss" || err "gloss degradation wrong"
import json, sys
d = json.load(open(sys.argv[1]))
els = {e.get("slug"): e for e in d["elements"] if e["kind"] == "lesson"}
assert set(els) == {"retry-storm", "cache-warmth", "team-shape"}, sorted(els)
assert all(e["gloss"] is None and e["gloss_unavailable"] for e in els.values()), \
    [(e["gloss"], e["gloss_unavailable"]) for e in els.values()]
assert d["gloss"]["served"] is False and d["gloss"]["reason"], d["gloss"]
assert not [e for e in d["elements"] if e["kind"] == "journey"], "journeys invented"
fams = {f["family"]: f for f in d["coverage"]["families"]}
assert fams["hub-gloss"]["enumerated"] is False and fams["hub-gloss"]["reason"], \
    fams["hub-gloss"]
PYEOF

# --- code-level assertions moved to the inner tier (Story 20.49, #923) ------
# The depth-estimator/clustering absence assertions and the section-8 scope/
# reach assertions run per edit in scripts/check-terrain-code-inner.sh now;
# nothing here re-runs them. This file keeps every assertion that needs a real
# assembly (seam invocation, fixture repos, corpus parse).

python3 - "$work/lessons.json" <<'PYEOF' && ok "hub-lessons: every served Lesson becomes its own Strand (the unit since the cluster removal)" || err "lesson strands wrong"
import json, sys
d = json.load(open(sys.argv[1]))
strands = [e for e in d["elements"] if e.get("kind") == "lesson"]
assert strands, "no lesson strands projected"
# Each strand is individually selectable and carries its own evidence.
for e in strands:
    assert e.get("slug"), e
    assert "evidence" in e, e
# And no clustering happened: subtopics are empty everywhere.
for t in d["topics"]:
    assert t["subtopics"] == [], f"{t['topic']} still has subtopics: {t['subtopics']}"
PYEOF

python3 - "$work/lessons.json" <<'PYEOF' && ok "CAP-4: the manifest names BOTH enumerated families and the per-family accounting closes" || err "per-family manifest wrong"
import json, sys
cov = json.load(open(sys.argv[1]))["coverage"]
assert cov["families_enumerated"] == ["articles-items", "hub-lessons"], cov["families_enumerated"]
assert [f["family"] for f in cov["families_not_enumerated"]] == [
    "host-sources", "hub-elements", "hub-gloss"], cov
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
python3 - "$work/lconsumed.json" <<'PYEOF' && ok "hub-lessons: a consumed Strand is MARKED consumed and still surfaced (never hidden, still selectable)" || err "consumed strand handling wrong"
import json, sys
d = json.load(open(sys.argv[1]))
# Since the cluster removal (Story 20.7, #809) a Lesson is a STRAND, not a
# member of a subtopic — so the consumed mark is asserted where it now lives.
strands = [e for e in d["elements"] if e.get("kind") == "lesson"]
assert strands, "the fixture must project lesson strands"
consumed = [e for e in strands if e.get("consumed")]
assert consumed, "the consumed fixture lesson is not marked consumed"
# Marked, never hidden: it is still in the projection.
assert len(strands) >= len(consumed), (len(strands), len(consumed))
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
# --- 7c. host-sources is DECLARED BUT NOT ENUMERATED (Story 20.7, #809) ------
# The family emitted ~190 junk directions in the second dogfood ("cover
# check-topic-map" — repo check scripts are evidence, not article material), so
# its emitting path is gone. It stays DECLARED: CAP-4's denominator must still
# name a family that is deliberately out of scope, or "complete" silently means
# "complete over whatever we felt like reading".
MAP > "$work/nohost.json" 2>/dev/null
python3 - "$work/nohost.json" <<'PYEOF' && ok "host-sources: declared, NOT enumerated, and the reason names the decision" || err "host-sources disclosure wrong after the removal"
import json, sys
d = json.load(open(sys.argv[1]))
fams = {f["family"]: f for f in d["coverage"]["families"]}
hs = fams["host-sources"]
assert hs["declared"] is True, hs
assert hs["enumerated"] is False, hs
assert hs["reason"], "a not-enumerated family must carry its reason"
assert "20.7" in hs["reason"] or "not article material" in hs["reason"], hs["reason"]
# and it contributes nothing to the read set
surfaces = [s for s in d["coverage"].get("read", []) if s.get("family") == "host-sources"]
assert not surfaces, f"host-sources still contributed read surfaces: {surfaces}"
PYEOF

python3 - "$M" <<'PYEOF' && ok "host-sources: the item-emitting path is DELETED, not merely unreferenced" || err "a host-sources item builder survives"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
for gone in ("def source_item(", "def source_surfaces(", "SOURCE_TRACK", "SOURCE_SECTION"):
    assert gone not in src, f"{gone} survives — an emitter kept 'in case' is the assembly cost"
PYEOF
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

# --- (section 8 moved to scripts/check-terrain-code-inner.sh, Story 20.49) --

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

# --- 7f. record-authoritative Strand membership (#884, gateway#76) -----------
# With element_survey served, membership/tags/journey-attachment come from the
# manifest records; tier-1 supplies only headline text (joined by slug); the
# three completeness checks run and record<->tier-1 mismatches are FINDINGS.
# Without it, the tier-1 fallback engages WITH the substitution disclosed.
python3 - "$FX" <<'PYEOF'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["tools"] = ["glossary_entry", "lessons_index", "topic_thread",
               "policy_lookup", "surface_names", "gloss_index",
               "element_survey"]
# Tier-1 must be SERVED here: a later section emptied it, and with the whole
# index a miss the composer rightly discloses one headline_source_reason
# instead of per-slug findings — this section tests the per-slug finding.
fx["gloss_index"] = [
    ["gloss/INDEX.md", 8,
     "- **retry-storm** — GLOSS-ALPHA retries multiply their own load. (agents, cost) · journeys/agents"],
    ["gloss/INDEX.md", 9,
     "- **cache-warmth** — GLOSS-BETA a warm cache hides every cold start. (testing)"],
]
fx["elements"] = [
    {"slug": "retry-storm", "kind": "lesson", "tags": ["agents", "cost"],
     "renderings": ["lessons/agents", "lessons/cost"],
     "source": "lessons/retry-storm.md:1"},
    {"slug": "retry-storm", "kind": "journey", "tags": ["agents", "cost"],
     "renderings": ["journeys/agents", "journeys/cost"],
     "source": "lessons/retry-storm.md:1"},
    {"slug": "cache-warmth", "kind": "lesson", "tags": ["testing"],
     "renderings": ["lessons/testing"], "source": "lessons/cache-warmth.md:1"},
    {"slug": "ghost-lesson", "kind": "lesson", "tags": ["method"],
     "renderings": ["lessons/method"], "source": "lessons/ghost-lesson.md:1"},
]
json.dump(fx, open(sys.argv[1], "w"))
PYEOF
MAP > "$work/records.json" 2>"$work/records.err" \
  && ok "#884: the map assembles with the element manifest served" \
  || err "assemble failed with records served: $(cat "$work/records.err")"
python3 - "$work/records.json" <<'PYEOF' && ok "#884: membership is record-authoritative; count-in = count-out against the served denominator; journey attachment from record pointers; mismatches are named findings" || err "record-authoritative composition wrong"
import json, sys
d = json.load(open(sys.argv[1]))
s = d["gloss"]["strands"]
assert s["source"] == "element manifest (records)", s
# The served denominator and the count-in = count-out verdict.
assert s["lesson_records"] == 3 and s["composed"] == 3 and s["complete"], s
# Journey attachment comes from the journey record's kind-qualified pointer,
# and its completeness is checked against the journey-record count.
assert s["journey_records"] == 1, s
assert s["journeys_attached"] == 1 and s["journeys_attached_complete"], s
# ghost-lesson is a record with no tier-1 line: a NAMED finding, and its row
# takes the marked-absent path — never an empty quote, never substituted.
assert any("ghost-lesson" in c and "no tier-1 headline" in c
           for c in s["conflicts"]), s["conflicts"]
els = {(e["kind"], e.get("slug")): e for e in d["elements"]}
rs = els[("lesson", "retry-storm")]
assert rs["tags"] == ["agents", "cost"], rs["tags"]
assert rs["journey_shard"] == "journeys/agents", rs.get("journey_shard")
assert rs["gloss"].startswith("GLOSS-ALPHA"), rs["gloss"]
PYEOF
# The fallback: no element_survey -> tier-1 acquisition, disclosed by name.
python3 - "$FX" <<'PYEOF'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["tools"] = ["glossary_entry", "lessons_index", "topic_thread",
               "policy_lookup", "surface_names", "gloss_index"]
fx.pop("elements", None)
json.dump(fx, open(sys.argv[1], "w"))
PYEOF
MAP > "$work/fallback.json" 2>/dev/null \
  && ok "#884: the map still assembles without element_survey (older gateway)" \
  || err "assemble failed on the fallback path"
python3 - "$work/fallback.json" <<'PYEOF' && ok "#884: the tier-1 fallback DISCLOSES the substitution and its reason at the point it happens" || err "fallback substitution not disclosed"
import json, sys
d = json.load(open(sys.argv[1]))
s = d["gloss"]["strands"]
assert s["source"] == "tier-1 markdown (fallback)", s
assert "element_survey" in (s.get("fallback_reason") or ""), s
PYEOF

# --- 8. #886/Story 20.35: the by-topic axis enumerates from the SERVED manifest -
# The defect: the axis population was consumer config (`track_topics`, bounded
# by ELEMENT_TOPIC_BOUND), so a repo declaring nothing offered 0 members
# whatever the hub served, and the screen could not distinguish "the hub serves
# one topic" from "we asked for one topic".
python3 - "$FX" <<'AXIS_FIXTURE'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["tools"] = ["glossary_entry", "lessons_index", "topic_thread", "policy_lookup",
               "surface_names", "gloss_index", "element_survey"]
# THREE served decision topics. None is declared in `track_topics` (which still
# maps delivery/nowhere/zeta) — so if any consumer-side gate survives, the axis
# cannot show these at all. Three also exceeds ELEMENT_TOPIC_BOUND (2).
fx["elements"] = [
    {"slug": "q_a/2026-07-28-alpha D1", "kind": "decision", "tags": [],
     "topic": "served-a", "renderings": ["decisions/served-a"],
     "source": "topics/served-a.md:9"},
    {"slug": "q_a/2026-07-28-alpha D2", "kind": "decision", "tags": [],
     "topic": "served-a", "renderings": ["decisions/served-a"],
     "source": "topics/served-a.md:10"},
    {"slug": "q_a/2026-07-27-beta D1", "kind": "decision", "tags": [],
     "topic": "served-b", "renderings": ["decisions/served-b"],
     "source": "topics/served-b.md:4"},
    {"slug": "q_a/2026-07-26-gamma D1", "kind": "decision", "tags": [],
     "topic": "served-c", "renderings": ["decisions/served-c"],
     "source": "topics/served-c.md:2"},
    {"slug": "only-a-lesson", "kind": "lesson", "tags": ["agents"],
     "renderings": ["lessons/agents"], "source": "lessons/only-a-lesson.md:1"},
]
fx["gloss_shards"] = dict(fx.get("gloss_shards", {}), **{
    "decisions/served-a": [
        ["gloss/decisions/served-a.md", 1, "## (q_a/2026-07-28-alpha D1 - 2026-07-28)"],
        ["gloss/decisions/served-a.md", 2, "RENDERED-A1 the ratified plain-register line."],
        ["gloss/decisions/served-a.md", 4, "## (q_a/2026-07-28-alpha D2 - 2026-07-28)"],
        ["gloss/decisions/served-a.md", 5, "RENDERED-A2 another ratified line."],
    ],
    "decisions/served-b": [
        ["gloss/decisions/served-b.md", 1, "## (q_a/2026-07-27-beta D1 - 2026-07-27)"],
        ["gloss/decisions/served-b.md", 2, "RENDERED-B1 the ratified line."],
    ],
    "decisions/served-c": [
        ["gloss/decisions/served-c.md", 1, "## (q_a/2026-07-26-gamma D1 - 2026-07-26)"],
        ["gloss/decisions/served-c.md", 2, "RENDERED-C1 the ratified line."],
    ],
})
json.dump(fx, open(sys.argv[1], "w"))
AXIS_FIXTURE
MAP > "$work/axis.json" 2>/dev/null
python3 - "$work/axis.json" <<'AXIS_ASSERT' && ok "#886: the by-topic axis is the SERVED decision topics — no consumer config bounds its members, counts, or Strands" || err "the by-topic axis is not record-authoritative"
import json, sys
d = json.load(open(sys.argv[1]))
cov, els = d["coverage"], d["elements"]
ax = cov["element_axis"]

# AC1 — members are the served topics, not the declared mapping. The repo
# declares delivery/nowhere/zeta and NONE of them may appear.
assert ax["source"] == "element manifest (records)", ax
assert ax["topics"] == ["served-a", "served-b", "served-c"], ax["topics"]
declared = {"delivery", "nowhere", "zeta"}
assert not (set(ax["topics"]) & declared), ax["topics"]
assert not any(e.get("topic") in declared for e in els), "a declared topic reached the axis"

# AC2 — no consumer-side bound survives: three served topics is MORE than
# ELEMENT_TOPIC_BOUND, and all three are read with none skipped.
assert ax["bounded_by_consumer_config"] is False, ax
assert cov["element_topics_read"] == ["served-a", "served-b", "served-c"], cov
assert cov["element_topics_skipped"] == [], cov["element_topics_skipped"]
assert not [s for s in cov["skipped"] if s["family"] == "hub-elements"], cov["skipped"]

# AC4 — the denominator is the served record set, per member, and the
# per-family accounting closes over it.
assert ax["records_per_topic"] == {"served-a": 2, "served-b": 1, "served-c": 1}, ax
assert ax["decision_records"] == 4, ax
dec = [e for e in els if e["kind"] == "decision"]
assert len(dec) == 4, len(dec)
f = {x["family"]: x for x in cov["families"]}["hub-elements"]
assert f["enumerated"] and f["matched"] == 3 and f["read"] == 3, f
assert f["skipped"] == 0 and f["accounting_closes"] and f["complete"], f

# AC6 — the axis claims only what is served: no `reversal` is derived, and the
# absence is DISCLOSED rather than inferred away.
assert ax["reversal_served"] is False, ax
assert "reversal" not in ax["served_kinds"], ax["served_kinds"]
assert not any(e["kind"] == "reversal" for e in els), "a reversal was derived from prose"

# Each Strand quotes its SERVED rendering, joined by the record slug — the
# manifest embeds no bodies, so a missing join would show as a disclosure.
by_ptr = {e["decision_pointer"]: e for e in dec}
assert by_ptr["q_a/2026-07-28-alpha D1"]["gloss"].startswith("RENDERED-A1"), by_ptr
assert by_ptr["q_a/2026-07-26-gamma D1"]["gloss"].startswith("RENDERED-C1"), by_ptr
# The cite names the manifest's own source line, never a recomposed path.
assert by_ptr["q_a/2026-07-27-beta D1"]["situation"].startswith("topics/served-b.md:4@"), by_ptr
# The date comes from the record's own batch slug.
assert by_ptr["q_a/2026-07-27-beta D1"]["date"] == "2026-07-27", by_ptr
AXIS_ASSERT

# AC7 — a reintroduced consumer-side gate is caught mechanically, asserted on
# the shipped source rather than on a mocked boolean.
python3 - <<'AXIS_GUARD' && ok "#886: no consumer-declared gate stands between the manifest and the axis (regression guard)" || err "a consumer-side gate is reachable from the record-authoritative axis path"
src = open("scripts/terrain_map.py").read()
axis = src.split("def element_axis(", 1)[1].split("\ndef ", 1)[0]
body = axis.split('"""', 2)[2]
# The record-authoritative branch must not consult the declared mapping or the
# seam bound. `element_topics(mapping)` may appear ONLY on the fallback return.
assert body.count("element_topics(") == 1, body
assert "ELEMENT_TOPIC_BOUND" not in body, "the axis re-acquired the seam bound"
# And the bound must still exist for whatever still reads a raw thread.
assert "ELEMENT_TOPIC_BOUND" in src, "the raw-thread bound was deleted, not just lifted"
rt = src.split("def read_topic_elements(", 1)[1].split("\ndef ", 1)[0]
assert "--topics" in rt, "the raw-thread read path vanished"
AXIS_GUARD

# AC5 — records unavailable degrades LOUDLY: the axis falls back to the
# declared mapping and NAMES the reason at the point of substitution.
python3 - "$FX" <<'AXIS_DEGRADE'
import json, sys
fx = json.load(open(sys.argv[1]))
fx["tools"] = [t for t in fx["tools"] if t != "element_survey"]
json.dump(fx, open(sys.argv[1], "w"))
AXIS_DEGRADE
MAP > "$work/axis-fallback.json" 2>/dev/null \
  && ok "#886: the map still assembles when the manifest is unavailable" \
  || err "assemble failed on the degraded axis path"
python3 - "$work/axis-fallback.json" <<'AXIS_DEGRADE_ASSERT' && ok "#886: a degraded axis NAMES its substitution and says it is consumer-bounded, never silently empty" || err "the degraded axis is silent"
import json, sys
ax = json.load(open(sys.argv[1]))["coverage"]["element_axis"]
assert ax["source"] == "consumer-declared mapping (fallback)", ax
assert "element_survey" in (ax.get("fallback_reason") or ""), ax
assert ax["bounded_by_consumer_config"] is True, ax
AXIS_DEGRADE_ASSERT


if [ "$fail" -eq 0 ]; then
  printf '\nAll topic-map checks passed.\n'; exit 0
else
  printf '\ntopic-map checks FAILED.\n' >&2; exit 1
fi
