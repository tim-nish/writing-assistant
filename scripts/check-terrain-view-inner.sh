#!/usr/bin/env sh
# tier: inner — View-content and owner-language assertions against the
#   committed fixture map; no seam, no corpus, no assembly. Measured
#   2026-07-30 at adoption: ~1.4s.
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-view-inner.sh — the View's content, wording and write-only
# contract, split from check-topic-map-screen.sh (Story 20.49, #923). Same
# fixture-drift guard as its siblings: the full check re-assembles the
# fixture map every run.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

M="scripts/terrain_map.py"
D="scripts/topic-map-directions.py"
VP="scripts/validate-proposal-payload.py"
SKILL="skills/terrain/SKILL.md"
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/ws"
cp "$FIX" "$work/map.json"

# Fixture prep (the derivations the source check used): the over-budget map,
# its View, and its candidate set.
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
python3 "$D" candidates --map "$work/big-map.json" > "$work/big-cands.json"
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" \
  > "$work/big-payload.json" 2>/dev/null
[ -s "$work/view.md" ] || { err "no View rendered from the fixture map"; }

# --- the View LEADS WITH THE CANDIDATE DIRECTIONS (Story 18.76, #632) --------
# The size switch moves the terrain, never the proposing: the above-budget
# branch must offer no less guidance than the one-screen branch.
python3 - "$work/big-cands.json" "$work/view.md" <<'PYEOF' || fail=1
import json, re, sys
cands = json.load(open(sys.argv[1]))["candidates"]
view = open(sys.argv[2], encoding="utf-8").read()
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

heads = re.findall(r"^#{2,4} (.+)$", view, re.M)
check(heads and heads[0] == "Candidate directions",
      f"the View's FIRST section is the candidate directions (got {heads[:1]})")
# Story 20.5 (#802): the cluster summary and the per-subtopic detail that used
# to follow the directions are GONE, so "leads with the directions" is now the
# stronger claim that they are the only section there is.
check(heads == ["Candidate directions"],
      f"the directions are the View's only section ({heads})")

# Every derived direction reaches the View, with the index selection uses.
block = view
# Since Story 18.81 (#647) elements are presented HERE, among the directions,
# rather than in a section of their own — so every candidate is covered.
directional = list(cands)
missing = [c["id"] for c in directional if f"**{c['id']}**" not in block]
check(not missing, f"every derived direction appears in the section ({missing[:3]})")
check(len(directional) > 7, f"the fixture derives an over-budget candidate set ({len(directional)})")

# ELEMENTS OPEN THE LIST (the stance-3 pivot, #799): the typed elements are
# the primary selection units. The combination move stays visible right after
# them, before the demoted cluster singles.
rows = re.findall(r"^- \*\*(\S+)\*\* — (.+)$", block, re.M)
elem_ids = {c["id"] for c in cands if c["kind"] == "element"}
combo_ids = {c["id"] for c in cands if c["kind"] == "combination"}
check(not combo_ids, "no combination reaches the View while the move is deferred")
check(elem_ids, "the fixture carries Strands to fill the list")
epos = [i for i, (rid, _) in enumerate(rows) if rid in elem_ids]
check(epos and max(epos) < len(elem_ids),
      "the Strands — the only units since the cluster removal — fill the candidate list")

# Roughly ten pickable candidates in the first screenful — the whole point of
# the section. Counted over the first 40 lines, header included.
head = "\n".join(view.splitlines()[:40])
check(len(re.findall(r"^- \*\*", head, re.M)) >= 10,
      "about ten pickable candidates are visible without scrolling")

# The summary is ONE LINE per subtopic. Since Story 18.81 (#647) the line
# carries the material's own claim where there is one, and the subject alone
# where there is not — the glance (`[bar] level - N ptr`) is a description of
# the corpus and now lives in the subtopic's own block.
# The per-subtopic summary section is gone (Story 20.5, #802); the glance-bar
# and raw-counter ban now applies to the surviving surface, which is the whole
# View.
check("[#" not in view and " ptr," not in view,
      "no line carries the glance bar or raw counters (CAP-3 substance-led)")

# SUBSTANCE-LED (CAP-3, amended #647): a ranked line is what the material
# says, never subject-plus-counts. Every direction and terrain row must carry
# something beyond an index, a subject and a number.
COUNTS_ONLY = re.compile(r"^- \*\*\S+\*\* — [^—]+ \(\d+ evidence pointer\(s\)\)$")
bad_rows = [l for l in block.splitlines()
            if COUNTS_ONLY.match(l.strip())]
check(not bad_rows,
      f"no direction or terrain line is a subject plus counts ({bad_rows[:2]})")
# The depth-word duplication check went with the summary section it guarded
# (Story 20.5, #802): with no glance on the surface there is no beside-the-
# glance position for a word to be repeated in.
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- coverage wording never carries a placeholder (18.78, #637) -------------
# The wording IS the brief on adoption, so this is asserted at the composed
# brief and not only at the surface.
python3 - "$work/big-map.json" "$work/big-cands.json" "$D" <<'PYEOF' || fail=1
import importlib.util, json, sys
d = json.load(open(sys.argv[1]))
cands = json.load(open(sys.argv[2]))["candidates"]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# The #637 rule survives the cluster removal in the half that still applies:
# no candidate direction and no composed brief may carry an internal
# placeholder enum. GONE is the cluster-NAMING half — placeholders were the
# assembler's enums for "nothing named this cluster", and there are no
# clusters (Story 20.7, #809). A Strand is named by the material itself.
PLACEHOLDERS = ("(unclustered)", "(untracked)", "(unnamed)")

bad = [c["direction"] for c in cands
       if any(p in c["direction"] for p in PLACEHOLDERS)]
check(not bad, f"no candidate direction carries a placeholder enum ({bad[:2]})")
check(not any(c["direction"].strip() in ("cover", "cover ") for c in cands),
      "no candidate direction is left with an empty subject")

# The same rule at the BRIEF: adopting any index must never hand the owner an
# enum as their own wording.
spec = importlib.util.spec_from_file_location("d", sys.argv[3])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
pin = d["coverage"]["pin"]
briefs = [mod.brief_from_answer(
              {"index": c["id"], "note": "an angle", "pin": pin}, cands, pin)["brief"]
          for c in cands]
badb = [b for b in briefs if any(p in b for p in PLACEHOLDERS)]
check(not badb, f"no composed brief carries a placeholder enum ({badb[:2]})")
check(all(b.endswith("— an angle") for b in briefs),
      "the owner's note is still carried verbatim onto every composed brief")

sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- #651: the direction clip is RENDER-ONLY; the brief carries the full claim
python3 - "$D" <<'PYEOF' || fail=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("d", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# A claim-bearing Strand whose Lesson rendering runs well past the old 120-char
# derivation clip and ends on a whole word. (Re-based from the subtopic path,
# which is gone — Story 20.7, #809. The rule itself is unchanged: clipping is
# RENDER-only, and the derivation carries the material's full claim.)
claim = ("Absence-based verification is three valued not two because "
         "absent with evidence requires both the run count and the corroborating "
         "signal before the regression may be recorded as genuinely resolved")
assert len(claim) > 120 and len(claim.split()) >= 5
strand = {"kind": "lesson", "slug": "verification", "title": claim,
          "gloss": claim, "topic": "engineering", "date": "2026-07-23",
          "evidence": ["LESSONS.md:9@abc1234"]}
direction = mod._element_direction(strand)
check(claim in direction,
      "the full claim is carried into the DERIVATION, not clipped at 120 chars")

# The brief composed from the index carries the whole claim, ending on the
# source's own last word before the owner's note — never a mid-word cut.
cands = [dict(strand, id="L9", direction=direction, kind="element")]
brief = mod.brief_from_answer(
    {"index": "L9", "note": "my angle", "pin": "p@1"}, cands, "p@1")["brief"]
check(claim in brief and brief.endswith("resolved — my angle"),
      "the composed brief carries the full claim and ends on a source word, never mid-word")

# A served decision/reversal rendering is carried whole for the same reason
# (Story 20.20, #843: the direction quotes the SERVED rendering; the raw
# topic-line summary is never presented as one, so the no-clip property now
# attaches to the gloss).
ed = mod._element_direction({"kind": "reversal", "gloss": claim,
                             "summary": "raw line", "date": "2026-07-23"})
check(claim in ed, "a served element rendering is carried whole into its direction too")
bare = mod._element_direction({"kind": "reversal", "summary": claim,
                               "date": "2026-07-23"})
check(claim not in bare and "not being served" in bare,
      "an un-served element discloses instead of quoting the raw topic line")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# --- elements reach the surface and are pickable (18.80, #641) --------------
python3 - "$work/big-cands.json" "$work/view.md" "$work/big-map.json" "$D" <<'PYEOF' || fail=1
import importlib.util, json, re, sys
cands = json.load(open(sys.argv[1]))["candidates"]
view = open(sys.argv[2], encoding="utf-8").read()
d = json.load(open(sys.argv[3]))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

els = [c for c in cands if c.get("kind") == "element"]
check(len(els) == len(d["elements"]), f"every element reaches the candidate list ({len(els)})")
# Own namespace, no collision with the subtopic scheme.
eids = [c["id"] for c in els]
tids = [c["id"] for c in cands if c.get("kind") != "element"]
check(all(re.fullmatch(r"(?:E\d+\.\d+|L\d+|J\d+)", i) for i in eids),
      f"Strand ids use the declared namespaces L<n>/J<n>/E<topic>.<n> ({eids})")
check(not (set(eids) & set(tids)), "element ids never collide with subtopic ids")
check(len(set(eids)) == len(eids), "element ids are unique")

# AMONG THE DIRECTIONS since Story 18.81 (#647): two lists split by internal
# derivation kind is an implementation detail on the owner surface, so the
# elements are pickable where every other candidate is.
heads = re.findall(r"^#{2,4} (.+)$", view, re.M)
check("What you decided" not in heads,
      f"elements have no section of their own ({heads[:4]})")
block = view.split("## Subtopic clusters — a derived, secondary grouping")[0]
check(all(f"**{i}**" in block for i in eids),
      "every element appears among the candidate directions, with its index")
check(any(k in block for k in ("lesson", "journey", "decision", "reversal")),
      "each Strand's kind is shown")
check("already consumed" in block, "a consumed element is MARKED, not hidden")
# The bound is never silent: the projection's coverage disclosure survives the
# section's removal — a bounded projection read as the whole record is what it
# guards against.
check("delivery" in block and "zeta" in block and "NOT covered" in block,
      "the directions state which topics the elements came from, and which they did not")

# Wording carries no internal marker and becomes the brief on adoption (#637).
PLACEHOLDERS = ("(unclustered)", "(untracked)", "(unnamed)")
check(not any(p in c["direction"] for c in els for p in PLACEHOLDERS),
      "element wording carries no placeholder enum")
spec = importlib.util.spec_from_file_location("dd", sys.argv[4])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
pin = d["coverage"]["pin"]
out = mod.brief_from_answer({"index": eids[0], "note": "the angle I want", "pin": pin},
                            cands, pin)
check(out["brief"].endswith("— the angle I want"),
      f"an element index composes an ordinary brief with the note VERBATIM ({out['brief'][:60]}…)")
check(out["provenance"] == "owner-authored" and out["origin"] == "adopted-index",
      "an adopted element is owner-adopted wording, like any other index")
# A stale pin is refused for an element exactly as for a subtopic.
try:
    mod.brief_from_answer({"index": eids[0], "note": "x", "pin": "other@dead"}, cands, pin)
    check(False, "a stale-pin element selection is refused with the mismatch named")
except SystemExit:
    check(True, "a stale-pin element selection is refused with the mismatch named")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# Elements reach the IN-CONVERSATION screen too — the size switch moves where
# the terrain is presented, never what the map proposes.
python3 - "$work/map.json" "$D" "$work/small-el.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d["elements"] = [{"kind": "decision", "summary": "A small-map decision",
                  "topic": "delivery", "date": "2026-07-20",
                  "situation": "topics/delivery.md:3@abc1234",
                  "evidence": ["topics/delivery.md:3@abc1234"], "consumed": False}]
d["coverage"] = dict(d.get("coverage", {}), element_topics_read=["delivery"],
                     element_topics_skipped=[])
json.dump(d, open(sys.argv[3], "w"))
PYEOF
python3 "$D" payload --map "$work/small-el.json" > "$work/small-el-payload.json" 2>/dev/null
python3 - "$work/small-el-payload.json" <<'PYEOF' && ok "elements are offered on the in-conversation screen, not only in the View" || err "elements never reach the small-map screen"
import json, sys
labels = [c["label"] for c in json.load(open(sys.argv[1]))["items"][0]["choices"]]
# The decision row reaches the screen as a DISCLOSURE-shaped direction (Story
# 20.20, #843): identified by kind, date and record — its raw topic line is
# not the label any more.
assert any("cover the decision" in l and "2026-07-20" in l for l in labels), labels
assert any("name your own" in l for l in labels) and labels[-1] == "stop here", labels
PYEOF
[ $? -eq 0 ] || fail=1

# --- the depth ESTIMATOR is GONE (Story 20.7, #809) -------------------------
# This block asserted that the View showed the estimate but not the
# estimator's promotion rule. There is no estimator: it was derived per
# subtopic and retired with the unit. What survives is the stronger claim —
# nothing depth-shaped reaches the owner surface at all — plus the absence of
# the machinery, so a reader meets the removal rather than a silent gap.
python3 - "$work/view.md" "$D" <<'PYEOF' || fail=1
import re, sys
view = open(sys.argv[1], encoding="utf-8").read()
src = open(sys.argv[2], encoding="utf-8").read()
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check(not re.search(r"^- depth: ", view, re.M),
      "no depth line reaches the View (the estimate is not an owner surface)")
check("the next level needs" not in view,
      "the estimator's promotion rule appears nowhere on the owner surface")
for gone in ("_depth_line", "DEPTH_PREDICATE_MARKER"):
    check(gone not in src, f"{gone} is deleted, not merely unreferenced")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

# Fully regenerated per invocation, for an unchanged pin.
cp "$work/view.md" "$work/view-1.md"
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" >/dev/null 2>&1
cmp -s "$work/view-1.md" "$work/view.md" \
  && ok "size switch: two invocations regenerate the View identically at one pin" \
  || err "the View is not deterministic at an unchanged pin"

# WRITE-ONLY: poison it, and nothing downstream changes. Delete it, and nothing
# is lost — it is a rendering, never a record.
printf 'POISON-VIEW\n' > "$work/view.md"
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" \
  > "$work/big-payload2.json" 2>/dev/null
grep -q 'POISON-VIEW' "$work/big-payload2.json" \
  && err "the composer read the View back (a stored index)" \
  || ok "size switch: a poisoned View does not influence the next screen (write-only)"
cmp -s "$work/big-payload.json" "$work/big-payload2.json" \
  && ok "size switch: the screen is unchanged after the View was overwritten" \
  || err "overwriting the View changed the screen"
rm -f "$work/view.md"
python3 "$D" payload --map "$work/big-map.json" --view "$work/view.md" \
  > "$work/big-payload3.json" 2>/dev/null
cmp -s "$work/big-payload.json" "$work/big-payload3.json" \
  && cmp -s "$work/view-1.md" "$work/view.md" \
  && ok "size switch: deleting the View loses nothing (map and View both regenerate)" \
  || err "deleting the View lost something"

python3 - "$work/view-1.md" "$work/big-cands.json" <<'PYEOF' && ok "indexed selection: the View's IDs and the composer's IDs are the same identifiers" || err "the View and the composer disagree about indexes"
import json, re, sys
# Story 20.5 (#802): the per-subtopic detail headings are gone, so the View's
# identifiers are read where they now live — the candidate direction rows,
# which is the surface the owner actually answers from.
# Story 20.7 (#809): the identifiers are Strand ids now (L<n>/J<n>/E<t>.<n>),
# subtopic T-ids having gone with the cluster unit.
view_ids = set(re.findall(r"^- \*\*((?:L|J)\d+|E\d+\.\d+)\*\* — ",
                          open(sys.argv[1], encoding="utf-8").read(), re.M))
cand_ids = {c["id"] for c in json.load(open(sys.argv[2]))["candidates"]
            if c["kind"] == "element"}
assert cand_ids <= view_ids, cand_ids - view_ids
PYEOF

# --- the owner surface carries owner language only (18.82, #646) -------------
# The reading path is everything above the maintenance section: what the owner
# reads to choose. Counters, cluster/depth enums and remediation prompts belong
# below it, in sections labeled for what they are.
python3 - "$work/view.md" "$work/big-map.json" "$D" <<'PYEOF' || fail=1
import importlib.util, json, re, sys
view = open(sys.argv[1], encoding="utf-8").read()
d = json.load(open(sys.argv[2]))
spec = importlib.util.spec_from_file_location("dv", sys.argv[3])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# Story 20.5 (#802): with the maintenance and diagnostics sections deleted,
# the reading path is THE WHOLE VIEW. The #646 boundary is not weakened by
# this — it is satisfied trivially, because there is no longer a
# non-owner-facing tail for internal vocabulary to hide in. The lint below is
# therefore now the ONLY thing standing between a derivation defect and the
# owner surface, which makes it more load-bearing than before, not less.
reading = view

# The lint's own contract: it FLAGS the pre-#646 line shape and passes the
# shipped one — a lint that never fires would be a clean bill nobody earned.
offender = "- **T1.1** — not yet clustered · [##..] seed-only - 4 ptr, 0 unconsumed"
check(mod.lint_owner_lines([offender]), "the render-boundary lint flags an internal-vocabulary line")
hits = mod.lint_owner_lines(reading.splitlines())
check(not hits, f"the reading path carries no internal vocabulary ({hits[:2]})")

# Registration is a contract, not a convenience list: a depth level or source
# family the assembler grows and nobody registers would silently stop being
# gated (the check-internal-vocabulary.sh pattern, applied to the map).
levels = {s.get("depth", {}).get("level") for t in d["topics"] for s in t["subtopics"]}
families = {i.get("family") for t in d["topics"] for s in t["subtopics"]
            for i in s.get("items", [])}
vocab = {v.lower() for v in mod.INTERNAL_VOCAB}
unregistered = [x for x in (levels | families) if x
                and x.lower().replace(" ", "-") not in vocab and x.lower() not in vocab]
check(not unregistered,
      f"every depth level and source family is registered in INTERNAL_VOCAB ({unregistered})")

# The remediation prompt and the counters were DELETED with their sections,
# not relocated — and that is the story's point: they were ~2,300 lines nobody
# could find a use for. What must survive is that the owner surface still
# carries no remediation prompt inside a terrain or direction line.
check("declare `subtopic:`" not in reading,
      "no remediation prompt sits inside a terrain or direction line")
check("[#" not in reading,
      "no depth bar reaches the owner surface")
# IDs stay — they are the ratified selection mechanism.
check(re.search(r"^- \*\*((?:L|J)\d+|E\d+\.\d+)\*\* — ", reading, re.M),
      "terrain lines still carry their Strand index for selection")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1


[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
