#!/usr/bin/env sh
# parallel-safe
# tier: inner — greps and small stdlib-python reads over tracked text; no
#   network, no repo mutation, far under the runner's INNER_MS ceiling.
# measured: 130ms (three runs, 2026-08-04, all 130ms)
# ends: a ratified terrain BRIEF DECISION losing its carrier in prose — a
#   decision recorded in the spec while the skill that must execute it says
#   something else, or says nothing. The class is not generation-side
#   preventable here: the two artifacts are authored in different sittings by
#   different acts (a spec amendment and a skill edit), so nothing at the
#   point of writing either one can see the other's state.
# removal-signal: the brief's decisions become derivable from a single
#   declared source both surfaces render — e.g. the gate registry growing an
#   owner-facing contract field the skill projects rather than restates — at
#   which point the two cannot disagree and this check has no subject.
#   Also retires if the terrain brief step stops being skill-driven prose.
#
# The three headers above are owed because this file LEFT the admission
# baseline the moment it was edited (#1356): the exemption covers files that
# predate the clauses, not edits to them. The edit was naming
# steps/brief-gates.md in `covers:` after the 20.212 companion split.
# covers: scripts/terrain_brief.py scripts/terrain_directions.py scripts/terrain_map.py scripts/topic-map-directions.py skills/draft-article/SKILL.md skills/draft-article/stages/stage0.md skills/terrain/SKILL.md skills/terrain/steps/brief.md skills/terrain/steps/brief-gates.md
# covers-note (#1321): the derivation also proposed scripts/check-brief-pointer-unresolved.sh
#   and specs/spec-article-draft-pipeline/**. Both appear in this file in PROSE only — a
#   sibling check named as the owner of an assertion, and a spec cited for a ratified value.
#   Neither is read, exec'd or grepped here, so neither is coverage; removed at ratification.
# check-terrain-decisions.sh — the decisions-shard join (Story 20.22, #851;
# SPEC-terrain CAP-2 as amended 2026-07-27, #850).
#
# The defect this guards (#850 D1): the ratified renderings existed and the
# consumer never asked for them, so the owner read raw recall-register text
# and indicted the hub's authoring. The join keys a topic decision line's
# trailing `(q_a/<batch> D<n> …)` pointer to the served shard's
# `## (q_a/<batch> D<n> · <date>)` heading. A missing rendering is an
# ABNORMAL condition, disclosed loudly (owner ruling, #850 D4) — and the raw
# topic line is NEVER presented as if it were a rendering.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

M="scripts/terrain_map.py"
# #1036: the renderer lives in terrain_directions.py — loaded from THAT path,
# never through the entry point's re-export.
D="scripts/terrain_directions.py"

python3 - "$M" "$D" <<'PYEOF' || fail=1
import importlib.util, sys
def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
tm = load(sys.argv[1], "tm")
dv = load(sys.argv[2], "dv")
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# --- the shard parser reads the served shape --------------------------------
shard = "\n".join([
    "pin: hub@abc1234",
    "=== gloss/decisions/workflow.md @ abc1234",
    "1: # Gloss — decisions: workflow",
    "3: Ratified plain-register renderings of decision lines.",
    "8: Regenerated: 2026-07-27 · 2 entries",
    "10: ---",
    "12: ## (q_a/2026-07-20-retry-budget D1 · 2026-07-20)",
    "14: Retries without a budget turn one slow dependency into an outage.",
    "15: The budget is declared once and enforced by the client.",
    "16: ",
    "18: ## (q_a/2026-07-21-oncall D3 · 2026-07-21)",
    "20: A rota nobody owns silently stops.",
])
entries = tm.parse_decision_shard(shard)
check(set(entries) == {"q_a/2026-07-20-retry-budget D1", "q_a/2026-07-21-oncall D3"},
      f"shard entries key on the provenance pointer ({sorted(entries)})")
check(entries["q_a/2026-07-20-retry-budget D1"]["gloss"].startswith("Retries without")
      and entries["q_a/2026-07-20-retry-budget D1"]["gloss"].endswith("the client."),
      "a multi-line rendering is carried whole, in order")
check(entries["q_a/2026-07-20-retry-budget D1"]["cite"]
      == "gloss/decisions/workflow.md:12@abc1234",
      "the cite points at the entry heading in the served shard")
check(tm.parse_decision_shard("miss: gloss --tag decisions/workflow") == {},
      "a served miss parses to no entries, never to invented ones")

# --- the pointer is captured from the topic line ----------------------------
served = [("5", "- 2026-07-20 — **Retries need a budget.** Because reasons. "
                "(q_a/2026-07-20-retry-budget D1)"),
          ("9", "- 2026-07-22 — **No pointer on this line.**")]
els = tm.parse_topic_elements("workflow", served, "abc1234")
check(els[0]["decision_pointer"] == "q_a/2026-07-20-retry-budget D1",
      "the join key is captured before the summary strips the pointer")
check(els[1]["decision_pointer"] is None,
      "a line with no D-numbered pointer stays pointerless, never guessed")

# --- the join: served -> quoted; absent -> abnormal, loud -------------------
tm.join_decision_gloss(els, {"workflow": entries}, {})
check(els[0]["gloss"].startswith("Retries without")
      and els[0]["gloss_cite"] == "gloss/decisions/workflow.md:12@abc1234",
      "a joined Strand carries the served rendering and its cite")
check(els[0]["gloss_unavailable"] is None,
      "a served rendering carries no absence disclosure")
check(els[1]["gloss"] is None
      and "abnormal condition to fix now" in els[1]["gloss_unavailable"],
      "an absent rendering is disclosed as the abnormal condition it is")
missed = tm.parse_topic_elements("orphan", served, "abc1234")
tm.join_decision_gloss(missed, {}, {"orphan": "gateway unreachable"})
check("gateway unreachable" in missed[0]["gloss_unavailable"]
      and "abnormal condition" in missed[0]["gloss_unavailable"],
      "a whole-shard miss names its reason inside the abnormal disclosure")

# --- the renderer: quotes the rendering, never the raw line -----------------
line = dv._element_direction(dict(els[0], kind="decision"))
check("Retries without a budget" in line and "not being served" not in line,
      "a joined decision row quotes the served rendering")
bare = dv._element_direction(dict(els[1], kind="decision"))
check(els[1]["summary"] not in bare and "abnormal condition" in bare,
      "an unjoined decision row discloses; the raw topic line never poses as "
      "a rendering")
# --- terrain routes into the EXISTING intent gate (Story 20.95, #1051) -------
# The boundary where terrain ends and drafting begins. What a text check can
# hold is exactly the criteria a well-meaning diff breaks: that the gate is
# ENTERED rather than rebuilt, that no pipeline vocabulary reaches the owner
# surface, and that the coupling direction is not inverted. Folded into THIS
# interpreter rather than starting a second one: the assertions are pure text
# reads, and the terrain family's runtime SUM is budgeted (#944).
import re  # noqa: E402

B = open("skills/terrain/steps/brief.md", encoding="utf-8").read()
S = open("skills/terrain/SKILL.md", encoding="utf-8").read()
DA = open("skills/draft-article/SKILL.md", encoding="utf-8").read()
end = B.split("The end of the sitting", 1)[-1]

# AC1 — the existing gate is ENTERED, and no second one is introduced.
check("intent gate" in end and "skills/draft-article/SKILL.md" in end,
      "AC1: terrain's end points at draft-article's OWN intent gate, by name "
      "and by file")
check("Nothing new is built here" in end,
      "AC1: ...and says so, so a later diff does not 'helpfully' add one")
check("second gate" in end and "reimplemented the gate" in end,
      "AC1: a second gate, label set or question shape is barred in terms")
# The closed label set must live in ONE place. Terrain must not restate it.
labels = [l for l in re.findall(r'"([^"]+)"', DA)
          if l.startswith(("introduce the", "share engineering",
                           "explain the evaluation", "survey a research",
                           "write a working"))]
check(labels, f"the gate's label set is where it always was ({len(labels)})")
check(sum(1 for l in set(labels) if l in end) <= 1,
      "AC1: terrain does not restate the closed label set — a second copy is "
      "a second gate wearing the first one's words")

# AC2 — the recommendation is grounded in the adopted thesis and stays one.
check("grounded in the adopted thesis" in end,
      "AC2: the recommended intent is grounded in the thesis's own shape")
check("nothing is pre-selected" in end and "full label set is offered" in end,
      "AC2: ...and it remains a recommendation")

# AC3 — sources are asked with the run's evidence state attached, and stay the
# owner's input.
check("evidence state" in end and "gaps" in end,
      "AC3: sources are asked with the run's evidence state attached")
check("never widens scope" in end,
      "AC3: ...and the brief directs emphasis WITHIN declared sources")

# AC4 — no pipeline vocabulary and no machine path on the owner surface.
check('"framework"' in end and "never owed one here" not in end
      or "was never owed one here" in end,
      "AC4: the vocabulary boundary names `framework` as stage vocabulary")
check("<sources...>" not in end,
      "AC4: the `<sources...>` placeholder is gone from the handoff")
check("stage0 <framework>" not in B,
      "AC4: the raw `stage0 <framework> ...` relay is gone")
check("--brief" in end and "never retyped" in end,
      "AC5: `--brief` is wired from the artifact rather than retyped")

# AC6 — the uniformity clause is scoped to BEHAVIOUR, explicitly.
check("uniformity is of BEHAVIOUR" in end,
      "AC6: the uniformity clause is scoped to behaviour")
check("provenance record" in end and "#1050" in end,
      "AC6: ...and the provenance record is named as what does distinguish "
      "the producers, so the text does not contradict story 20.94")
check("nothing downstream can tell the two apart" not in B,
      "AC6: the unscoped clause is gone, not merely qualified nearby")

# AC7 — entry-agnosticism, and the direction is the reason.
# Named by PROCESS, never by a number (#1247): the run mint is `start`.
check("terrain → the gate → the run mint" in end,
      "AC7: the coupling direction is stated")
check("nothing in drafting branches on which producer ran" in end,
      "AC7: drafting gains no knowledge of terrain")
DRAFT = ["skills/draft-article/SKILL.md",
         "skills/draft-article/stages/stage0.md"]

# WHAT AC7 FORBIDS IS THE ACT, NOT THE WORD (#1070). The first cut of this
# assertion was `"terrain" not in t.lower()`, and it went red the day story
# 20.94 (#1050) landed: stage 0 records `brief_provenance: terrain-adopted`, a
# closed-vocabulary VALUE ratified in specs/spec-article-draft-pipeline/
# amendments.md (2026-07-31). Recording a label is not importing, resolving or
# detecting anything — nothing in drafting branches on it, which is the
# entry-agnostic property AC7 exists to protect — so the bare substring test
# asserted strictly more than the criterion behind it and made a ratified line
# a red suite. The neighbouring half of the prohibition, that the recorded
# pointer must never be FOLLOWED, has its own check
# (scripts/check-brief-pointer-unresolved.sh) and is not restated here.
#
# An exemption list for the ratified line was the other candidate and was
# rejected: it re-creates the same brittleness one level down, where the next
# ratified value has to be added to a list nobody remembers exists.
#
# The three forbidden acts, as three patterns:
T_IMPORT = re.compile(
    r"terrain[-_](?:runs?|map|directions|root)"      # a terrain state location
    r"|(?:scripts|skills|specs)/terrain"             # a terrain module by path
    r"|\bterrain[\w-]*\.(?:py|md|json)\b"            # a terrain file by name
    r"|topic-map-directions",
    re.I)
T_RESOLVE = re.compile(
    r"\b(?:imports?|resolv(?:e|es|ed|ing)|read(?:s|ing)?|open(?:s|ing)?"
    r"|load(?:s|ing)?|fetch(?:es|ing)?|inspect(?:s|ing)?|follow(?:s|ing)?"
    r"|quer(?:y|ies|ying)|glob(?:s|bing)?|walk(?:s|ing)?|locat(?:e|es|ing)"
    r"|discover(?:s|ing)?|consult(?:s|ing)?)\b[^.\n]{0,40}\bterrain\b",
    re.I)
T_DETECT = re.compile(
    r"\bterrain\b\W{0,3}"
    r"(?:runs?|sitting|workspace|state|artifact|brief|thesis|corpus)\b",
    re.I)
T_RULES = (("imports a terrain module or state location", T_IMPORT),
           ("resolves terrain state", T_RESOLVE),
           ("detects terrain state", T_DETECT))


def terrain_consumer_hits(text):
    """Lines where drafting would import, resolve or detect terrain state."""
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        for why, rx in T_RULES:
            if rx.search(line):
                out.append((i, why, line.strip()[:70]))
                break
    return out


for p in DRAFT:
    t = open(p, encoding="utf-8").read()
    check(not terrain_consumer_hits(t),
          f"AC7: {p} does not import, resolve or detect terrain — a diff that "
          "makes drafting a terrain consumer has inverted the dependency "
          f"({terrain_consumer_hits(t)[:1]})")

# AC7, POSITIVE: the narrowing must not have disarmed the criterion. Plant a
# real resolver in the DRAFT file the ratified value lives in, one per
# forbidden act, and confirm the check fires — then confirm the unplanted file
# is clean, so the signal came from the plant and not from ambient text.
S0 = open("skills/draft-article/stages/stage0.md", encoding="utf-8").read()
PLANTS = [
    "Read the adopted brief from the newest `terrain-runs` workspace.",
    "Load `scripts/terrain_map.py` and ask it for the adopted thesis.",
    "Stage 0 reads the terrain that produced the brief before drafting.",
    "If a terrain run is present, skip the intent gate.",
]
for plant in PLANTS:
    check(terrain_consumer_hits(S0 + "\n" + plant + "\n"),
          "AC7 (positive): a planted terrain resolver still FAILS — "
          f"{plant[:46]!r}")
check(not terrain_consumer_hits(S0),
      "AC7 (positive): ...and with the plants removed the file is clean, so "
      "the narrowing detects the act rather than the word")
check(not terrain_consumer_hits(
          "record `brief_provenance`: `owner-authored` when the owner typed "
          "the brief, `terrain-adopted` when it arrived composed."),
      "AC7: recording the ratified `terrain-adopted` VALUE is not an import, "
      "a resolution or a detection (#1050, #1070)")

check("intent gate" in S,
      "the dispatcher's own summary records where the sitting now ends")

# --- a NAMED TRIGGER opens the brief (Story 20.92, #1042) -------------------
# Discovery for an existing move. What is asserted is that the trigger is
# listed WITH the phrases it joins rather than replacing them, that its
# no-path resolution is stated rather than heuristic, and that the
# cross-workspace refusal it could most easily have relaxed is intact.
check("open the brief" in S and "show the terrain" in S
      and "show the topic map" in S and "what could I write about" in S,
      "AC2: the new trigger is listed WITH the three existing phrases, not "
      "instead of them")
check("All three still start at **the workspace\nmint**" in S,
      "AC2: ...and those three still start at the workspace mint, unchanged")
check("enters at compose-the-brief" in S,
      "AC1: the trigger's entry point is stated on the skill's own surface")
brief_trigger = B.split("The named trigger", 1)[-1]
check("walks no screens and loads no corpus" in (brief_trigger + S),
      "AC1: the trigger reaches the brief without walking Screens 1-2 or "
      "re-loading the corpus")
check("newest terrain run workspace" in brief_trigger
      and "sorts last" in brief_trigger,
      "AC3: the no-path resolution rule is STATED and deterministic")
check("named, never guessed between" in brief_trigger,
      "AC3: ...and an ambiguous workspace is stated, never silently picked")
check("says so plainly" in brief_trigger
      and "composes nothing" in brief_trigger,
      "AC3: with no brief it says so plainly rather than starting the workspace mint")
check("Opening and inspecting" in brief_trigger
      and "still hits the existing refusal" in brief_trigger,
      "AC4: opening across workspaces succeeds while the EDIT refusal stands")
check("no new transition, no new state" in brief_trigger,
      "AC5: the lifecycle stays forward-only and gains nothing")
check("standing exits are offered" in brief_trigger,
      "AC6: the standing exits are offered at this entry too")

# AC4, on the code rather than the prose: the refusal message itself is
# untouched. This is the criterion a convenience-minded diff relaxes.
TMD = open("scripts/topic-map-directions.py", encoding="utf-8").read()
check("are in different " in TMD and "Retention is WITHIN-SITTING" in TMD
      and "cross-invocation" in TMD,
      "AC4: the cross-workspace edit refusal ships unchanged, with its "
      "existing message")

# AC3 — the resolver owns the layout. The consumer must ASK for the run root,
# never compose it (D1).
# `_resolve_newest_brief` MOVED to scripts/terrain_brief.py on 2026-08-03
# (Story 20.191), beside the artifact's writer, reader and addressing. The
# assertion is about the CONSUMER asking the resolver, wherever the consumer
# lives, so the subject file moves with it and the property is unchanged.
TB = open("scripts/terrain_brief.py", encoding="utf-8").read()
resolve = TB.split("_resolve_newest_brief", 1)[-1].split("\ndef ", 1)[0]
check("terrain-runs-root" in resolve and "resolve-paths.py" in resolve,
      "AC3: the run root is resolved through the path resolver, never "
      "composed here (storage-architecture D1)")
check('"terrain-runs"' not in resolve,
      "AC3: ...and no layout string is spelled out in the consumer")

sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

if [ "$fail" -eq 0 ]; then
  printf '\nAll terrain-decisions checks passed (the join is loud, never silent).\n'
else
  printf '\nFAILED.\n' >&2
  exit 1
fi
