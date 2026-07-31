#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-07-31 (#999) — verified: a `mktemp -d` for the fixture
# and a bare `mktemp` for the concatenated SKILL text, both unique per process;
# the repo is only read. (The `mktemp` SKILL file outlives the run because the
# later `trap` replaces the earlier one — a leak, not a collision.)
# tier: inner — full-report assertions against a synthesized fixture map; no
#   seam, no corpus, no assembly. Measured 2026-07-30 at adoption: ~0.9s
#   (ceiling 2s).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-report-inner.sh — the FULL REPORT for named group ids (Story
# 20.56, #938; SPEC-terrain CAP-3).
#
# The reported defect was a relay doing its best: nineteen Strands flattened
# into headline one-liners. That is why the rendering lives in code and why
# this check asserts the WHOLE relay rather than a summary — a prose obligation
# with no code path is what failed.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/topic-map-directions.py"
SKILL=$(mktemp)
cat skills/terrain/SKILL.md skills/terrain/steps/map.md \
    skills/terrain/steps/screens.md skills/terrain/steps/brief.md \
    skills/terrain/steps/gap.md > "$SKILL"
# ^ story 20.64 (#962): the skill is a dispatcher + step companions; checks
#   assert over the concatenation, whose order matches the pre-split file.

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# A member with two co-tag groups, each big enough that "whole" is observably
# different from "a summary": the failure being guarded is a relay that
# collapses many Strands into one-liners.
#
# ONE member carries a served journey arc LONGER THAN THE VIEW LINE BUDGET
# (Story 20.73, #1011). That is the fixture the whole-relay assertion needs:
# with every arc short, a renderer that clips every line is indistinguishable
# from one that clips none — which is exactly why the violation shipped
# unnoticed while all four terrain checks passed.
#
# ONE member carries NO CO-TAG (Story 20.74, #987). Every fixture Strand used
# to be co-tagged, which is the only reason the old `count("(also in:") ==
# len(strands)` assertion passed: it encoded the same wrong premise the issue
# did — that the context line is emitted per CO-TAGGED Strand. It is emitted
# per Strand, and a Strand with no co-tags renders `in no other Topic`. The
# co-tagless member makes that difference observable rather than asserted; the
# co-tags substrate places it in its own `no shared co-tag` group.
python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
LONG_ARC = ("the rule began as a local workaround nobody wrote down, then a "
            "second incident showed the same shape at a different layer, and "
            "the reversal came when measurement contradicted the premise the "
            "workaround rested on — so the remedy moved from the consumer to "
            "the site that authored the loss, which is the form it holds "
            "today and the reason it is stated as a rule rather than as a "
            "note attached to one incident")
els = []
for n in range(12):
    el = {"kind": "lesson", "slug": f"w{n}", "title": f"W{n}",
          "gloss": f"a claim the material makes, number {n}",
          "tags": ["workflow", "agents" if n % 2 else "cost"],
          "situation": f"LESSONS.md:{n}@abc1234",
          "evidence": ["LESSONS.md:1@abc1234"], "consumed": False}
    if n == 1:
        el["journey"] = LONG_ARC
        el["journey_recorded"] = True
    els.append(el)
els.append({"kind": "lesson", "slug": "w99", "title": "W99",
            "gloss": "a claim the material makes, number 99",
            "tags": ["workflow"],
            "situation": "LESSONS.md:99@abc1234",
            "evidence": ["LESSONS.md:1@abc1234"], "consumed": False})
json.dump({"kind": "topic-map", "topics": [],
           "coverage": {"pin": "h@abc1234"}, "elements": els},
          open(w + "/map.json", "w"))
PYEOF

python3 "$D" member --map "$work/map.json" --tag workflow > "$work/member.json"
# The complete rendering for the same member — the surface that carries the
# Strand rows once the size switch (Story 20.84, #1038) summarises the console.
python3 "$D" view --map "$work/map.json" --tag workflow \
  --out "$work/member-view.md" >/dev/null
CLAIMS='{"G1":"the agents thread, as the screen said it","G2":"the cost thread, as the screen said it","G3":"the uncotagged thread, as the screen said it"}'

# Asked in REVERSE screen order, to prove the order is the owner's. G3 is the
# co-tagless group (Story 20.74): it is asked HERE, in the mixed report, so the
# footnote assertions below run over a set that contains both shapes.
python3 "$D" report --map "$work/map.json" --tag workflow --groups "G2,G1,G3" \
  --claims "$CLAIMS" > "$work/both.json" 2>"$work/both.err" \
  || err "the full report failed: $(cat "$work/both.err")"
# One group only: the report covers exactly what was named, never the member.
python3 "$D" report --map "$work/map.json" --tag workflow --groups "G2" \
  --claims "$CLAIMS" > "$work/one.json" 2>/dev/null
# A group whose claim is not carried states the absence rather than inventing.
python3 "$D" report --map "$work/map.json" --tag workflow --groups "G1" \
  > "$work/noclaim.json" 2>/dev/null

# An id that is not on this screen is refused, with the per-screen, per-pin
# nature of group ids named — that is what makes the refusal actionable.
python3 "$D" report --map "$work/map.json" --tag workflow --groups "G9" \
  > /dev/null 2>"$work/bad.err" \
  && err "an unknown group id produced a report" \
  || { grep -qi 'per-screen' "$work/bad.err" \
       && grep -q 'G9' "$work/bad.err" \
       && ok "an unknown group id is refused, naming it and why ids are local" \
       || err "wrong unknown-id behaviour: $(cat "$work/bad.err")"; }

# AC5 — it renders from held state; the written View is never read back. This
# is asserted the same way the existing never-read-back check is written.
python3 - "scripts/terrain_members.py" <<'PYEOF' \
  && ok "the report path opens no View file for reading" \
  || err "a View-reading code path exists in the report path"
import ast, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
fn = next(n for n in ast.parse(src).body
          if isinstance(n, ast.FunctionDef) and n.name == "compose_full_report")
seg = ast.get_source_segment(src, fn) or ""
for r in re.findall(r'open\((?![^)]*"w")[^)]*\)', seg):
    assert "view" not in r.lower(), r
assert "VIEW_FILENAME" not in seg
PYEOF

# --- the SKILL states the capability and its two standing constraints -------
for token in 'FULL REPORT for named group ids' 'never flattened into a union' \
             'never recomposes' 'inspection only' 'never read back'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the report contract: $token" \
    || err "SKILL is missing the report contract: $token"
done

# --- one assertion run over the produced files ------------------------------
python3 - "$work" <<'PYEOF' || fail=1
import json, sys
w = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

mem = json.load(open(w + "/member.json"))
secs = {s["group_id"]: s for s in mem["sections"]}
b = json.load(open(w + "/both.json"))
rep = b["report"]

# AC1 — separately, in the order asked, keyed by screen id. Never a union.
check([g["group_id"] for g in b["groups"]] == ["G2", "G1", "G3"],
      "each named group renders separately, in the order asked")
check(rep.index("## G2 ") < rep.index("## G1 ") < rep.index("## G3 "),
      "the rendered order is the owner's, not the screen's")
check(b["asked"] == ["G2", "G1", "G3"], "the report records what was asked")
allslugs = [s for g in b["groups"] for s in g["strands"]]
check(len(allslugs) == len(set(allslugs)) and len(b["groups"]) == 3,
      "the groups stay separate rendered blocks — never flattened into a union")

# AC2 — the claim first, then every member whole: gloss and arc. The context
# line is NOT on the row any more (Story 20.74, #987) — see the footnote block
# assertions below, which is where it went.
CLAIM_WORD = {"G2": "cost", "G1": "agents", "G3": "uncotagged"}
for gid in ("G2", "G1", "G3"):
    block = rep.split(f"## {gid} ")[1].split("\n## ")[0]
    check(f"In common: the {CLAIM_WORD[gid]} thread" in block,
          f"{gid} renders its claim")
    body = block.split("In common:")[1]
    # Every member is present, whole.
    for slug in secs[gid]["strands"]:
        n = slug[1:]
        check(f"a claim the material makes, number {n}" in body,
              f"{gid}: {slug}'s served rendering appears whole")
    # AC1 of story 20.74: no Strand row carries the context line here. Both
    # renderings of its first field are excluded, because excluding only
    # "(also in:" would repeat the premise bug this story exists to fix.
    check("(also in:" not in body and "in no other Topic" not in body,
          f"{gid}: no Strand row carries the deterministic context line")
    check(block.index("In common:") < block.index("- **"),
          f"{gid}: the claim appears BEFORE its members")

# --- Story 20.74 (#987): the context line is RELOCATED, never dropped -------
# It bundles cross-group placement, the audit pin and a completeness
# attestation — three audiences, none of them the reader of one group read
# whole — so it leaves the row for a footnote block. CAP-3 still requires the
# report to restate the pins it rendered, which is why "dropped" would fail
# this story and every field below is asserted present.
head, sep, foot = rep.partition("## Footnotes")
check(sep, "the report carries a footnote block")
check("FOOTNOTES" in head.split("## ")[0],
      "the header says WHERE the audit metadata went, before the reader misses it")
check("\n## " not in foot,
      "the footnote block is LAST — the verification material never stands "
      "between the reader and the material it verifies")

# The rows the body actually rendered, in rendered order, with their group.
rendered = []
for gid in ("G2", "G1", "G3"):
    block = rep.split(f"## {gid} ")[1].split("\n## ")[0]
    rendered += [(ln.split("**")[1], gid) for ln in block.splitlines()
                 if ln.startswith("- **")]
entries = [ln for ln in foot.splitlines() if ln.startswith("- **")]
check(len(entries) == len(rendered) == len(allslugs),
      f"one footnote entry per RENDERED Strand ({len(entries)} of {len(rendered)})")
check(b["footnotes"] == len(entries),
      "the payload declares the footnote count, so 'never dropped' is checkable "
      "without parsing prose")
check([(e.split("**")[1], e.split("—")[1].strip()) for e in entries] == rendered,
      "each entry names its Strand and the group it was rendered under, in "
      "rendered order")

# THE PREMISE FIX (AC4). The old assertion counted `(also in:` once per Strand
# and so ASSUMED every Strand is co-tagged; it passed only because every
# fixture Strand was. The line renders for EVERY Strand and only its first
# field varies, so the count that holds is over both renderings — and the
# fixture now contains one of each, which is what makes this falsifiable.
placed = [e for e in entries if "(also in:" in e]
unplaced = [e for e in entries if "in no other Topic" in e]
check(len(placed) + len(unplaced) == len(entries),
      "every footnote entry carries a placement field, co-tagged or not")
check(unplaced and placed,
      f"the fixture exercises BOTH shapes — {len(placed)} co-tagged, "
      f"{len(unplaced)} co-tagless. Without a co-tagless Strand the assertion "
      "above is as untested as the premise bug it replaces")
# All three fields survive the move, plus the two absence marks.
for e in entries:
    check("· from LESSONS.md:" in e or "origin not recorded" in e,
          f"the origin pin survives the move: {e.split('—')[0].strip()}")
    check("recorded" in e.split("· from")[-1],
          f"the attestation survives the move: {e.split('—')[0].strip()}")
check(sum("· no-journey" in e for e in entries) == len(entries) - 1,
      "the `no-journey` mark travels into the footnote with the Strand it "
      "qualifies (all but the one fixture Strand with a recorded journey)")

# AC3 — claims are carried, never recomposed, over the FULL unaltered set.
for g in b["groups"]:
    check(g["strands"] == secs[g["group_id"]]["strands"],
          f"{g['group_id']}: the claim is carried over the group's full, unaltered member set")
check(b["recomposed"] is False, "the report declares that nothing was recomposed")
nc = json.load(open(w + "/noclaim.json"))
check(nc["groups"][0]["claim_carried"] is False
      and "not carried from the screen" in nc["report"],
      "a group whose claim was not carried STATES the absence, never invents one")
check("recomposition belongs to subset selection" in nc["report"],
      "the absence names where recomposition does belong")

# AC4 — nothing is selected, no brief is composed.
check(b["selected"] == [] and b["brief"] is None,
      "no Strand is selected and no brief is composed")
check("inspection only" in rep, "the report says on its face that it selects nothing")

# AC6 — the pin and each rendered id's definition are restated.
check(b["pin"] in rep, "the report restates the invocation's pin")
for gid in ("G2", "G1"):
    block = rep.split(f"## {gid} ")[1].split("\n## ")[0]
    check("Group definition:" in block,
          f"{gid}: its definition is restated — a bare id is unreadable later")
    check(secs[gid]["title"] in block, f"{gid}: the definition names its title")

# AC7 — whole relay, bounded by the owner's pointers.
check(b["relay"] == "whole", "the report declares a whole relay")
check("Open the View" not in rep and ".md" not in rep.split("LESSONS.md")[0],
      "the report relays whole — never a summary plus a path")
one = json.load(open(w + "/one.json"))
check([g["group_id"] for g in one["groups"]] == ["G2"],
      "a report covers EXACTLY the groups named — never the whole member")
check(one["groups"][0]["count"] == len(secs["G2"]["strands"])
      and all(f"number {s[1:]}" in one["report"] for s in one["groups"][0]["strands"]),
      "the one named group is still relayed whole, every member")
check(one["footnotes"] == len(secs["G2"]["strands"]),
      "a single-group report footnotes exactly the Strands it rendered — the "
      "block is bounded by the report, not by the member")

# --- Story 20.73 (#1011): UNTRUNCATED, and the journey label named ----------
# Whole-relay was already the contract and the renderer was violating it:
# every line was clipped at VIEW_LINE_CHARS, so journey arcs ended in `…`
# mid-sentence on the one surface exempted from the size switch. NO CHECK
# COVERED THIS, which is why it shipped — so the assertion is written against
# a fixture whose served arc exceeds the budget.
import importlib.util
spec = importlib.util.spec_from_file_location("ttext", "scripts/terrain_text.py")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
arc = next(e["journey"] for e in json.load(open(w + "/map.json"))["elements"]
           if e.get("journey"))
check(len(arc) > mod.VIEW_LINE_CHARS,
      f"the fixture's served arc exceeds the View line budget ({len(arc)} > "
      f"{mod.VIEW_LINE_CHARS}) — otherwise this assertion proves nothing")

# AC1 — the served arc reaches the report WHOLE, and no line on the report
# path carries a cut this renderer authored.
check(f"how it changed: {arc}" in rep,
      "the served journey arc renders WHOLE on the report path")
cut = [ln for ln in rep.splitlines() if ln.rstrip().endswith("…")]
check(not cut,
      "no line on the report path ends in the renderer's elision marker"
      + (f" (found: {cut[:1]})" if cut else ""))
srcseg = open("scripts/terrain_members.py", encoding="utf-8").read()
fnseg = srcseg.split("def compose_full_report")[1].split("\ndef ")[0]
check("_clip_line(" not in fnseg,
      "the report composer calls no clipper — the whole relay is structural, "
      "not a property of today's fixture widths")

# AC2 — and the SIZE-SWITCHED surface is untouched: screen 2's listing still
# clips at the same budget. A diff that removed clipping globally has overshot
# this story; this is the assertion that says so.
#
# Read from the COMPLETE RENDERING (Story 20.84, #1038). This fixture's member
# is over the screen budget, so the console is now a summary that has no Strand
# rows to clip; the surface the size switch governs and that carries the arcs is
# the View. Asserting clipping on the summary would be asserting it about lines
# that are not there — the assertion follows its subject.
listing = open(w + "/member-view.md", encoding="utf-8").read()
check(f"how it changed: {arc}" not in listing,
      "screen 2's listing still clips the same over-budget arc")
check(max(len(ln) for ln in listing.splitlines()) <= mod.VIEW_LINE_CHARS,
      "screen 2's listing still bounds every line at VIEW_LINE_CHARS")

# AC3 — the journey label is named ON the surface, not left to be inferred.
check("JOURNEY" in rep and "how it changed:" in rep.split("## ")[0],
      "the report carries a legend naming `how it changed:` as the Journey")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
