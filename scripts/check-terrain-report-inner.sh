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
json.dump({"kind": "topic-map", "topics": [],
           "coverage": {"pin": "h@abc1234"}, "elements": els},
          open(w + "/map.json", "w"))
PYEOF

python3 "$D" member --map "$work/map.json" --tag workflow > "$work/member.json"
CLAIMS='{"G1":"the agents thread, as the screen said it","G2":"the cost thread, as the screen said it"}'

# Asked in REVERSE screen order, to prove the order is the owner's.
python3 "$D" report --map "$work/map.json" --tag workflow --groups "G2,G1" \
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
check([g["group_id"] for g in b["groups"]] == ["G2", "G1"],
      "each named group renders separately, in the order asked")
check(rep.index("## G2 ") < rep.index("## G1 "),
      "the rendered order is the owner's, not the screen's")
check(b["asked"] == ["G2", "G1"], "the report records what was asked")
allslugs = [s for g in b["groups"] for s in g["strands"]]
check(len(allslugs) == len(set(allslugs)) and len(b["groups"]) == 2,
      "the groups stay two rendered blocks — never flattened into one union")

# AC2 — the claim first, then every member whole: gloss, context line, arc.
for gid in ("G2", "G1"):
    block = rep.split(f"## {gid} ")[1].split("\n## ")[0]
    claim = f"In common: the {'cost' if gid == 'G2' else 'agents'} thread"
    check(claim in block, f"{gid} renders its claim")
    body = block.split("In common:")[1]
    # Every member is present, whole, with its context line beneath it.
    for slug in secs[gid]["strands"]:
        n = slug[1:]
        check(f"a claim the material makes, number {n}" in body,
              f"{gid}: {slug}'s served rendering appears whole")
    check(body.count("(also in:") == len(secs[gid]["strands"]),
          f"{gid}: every member carries its deterministic context line")
    check(block.index("In common:") < block.index("- **"),
          f"{gid}: the claim appears BEFORE its members")

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
listing = mem["listing"]
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
