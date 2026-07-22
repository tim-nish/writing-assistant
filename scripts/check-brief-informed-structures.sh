#!/usr/bin/env sh
# check-brief-informed-structures.sh — verify Story 18.45 (#558, SPEC-article-
# draft-pipeline CAP-9 2026-07-22 #554 amendment): the SHIPPED structure
# proposer's INPUT is widened to the owner's free-form coverage brief (#505), so
# the candidates are composed for the story the owner described. It is the same
# proposer — no second mechanism — and with no brief the output is unchanged.
# POSIX shell + stdlib Python only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

ELEMS='{"elements":[
  {"id":"lesson:retry-storm","kinds":["chronology","cost"]},
  {"id":"lesson:token-budget","kinds":["motivation"]},
  {"id":"lesson:cache-warmth","kinds":["cost"]}]}'

ST() { printf '%s' "$1" | python3 "$DP" structures ${2+--brief "$2"}; }

# --- 1. no brief -> byte-identical to the element-only Story 18.26 output -------
ST "$ELEMS" > "$work/plain.json" 2>/dev/null || err "structures failed without a brief"
python3 - "$work/plain.json" <<'PYEOF' && ok "no brief: the element-only candidates are unchanged — no brief keys leak in" || err "no-brief output changed"
import json, sys
d = json.load(open(sys.argv[1]))
assert "brief_informed" not in d, d
assert d["default"] == "sibling-lessons", d
for c in d["candidates"]:
    assert "grounding" not in c and "brief_informed" not in c, c
    assert "brief" not in (c.get("rationale") or "").lower(), c
PYEOF

# --- 2. the brief is an INPUT: candidates reflect the described story -----------
ST "$ELEMS" "tell the story of how the retry storm unfolded, start to finish" \
  > "$work/journey.json" 2>/dev/null || err "structures failed with a brief"
python3 - "$work/journey.json" <<'PYEOF' && ok "a brief describing a chronological story yields a chronological-journey candidate, brief-grounded" || err "brief did not inform the candidates"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("brief_informed") is True, d
names = {c["structure"] for c in d["candidates"]}
assert "chronological-journey" in names, names
j = next(c for c in d["candidates"] if c["structure"] == "chronological-journey")
assert "brief" in j["rationale"].lower(), j
assert j.get("grounding") in {"brief-requested", "evidence-signalled"}, j
PYEOF

# --- 3. emphasis: a named element leads sections/beats; every element survives ---
ST "$ELEMS" "just the token budget, in depth" > "$work/emph.json" 2>/dev/null
python3 - "$work/emph.json" <<'PYEOF' && ok "the brief's named element leads the composition, and every selected element survives (composition, not selection)" || err "brief emphasis wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["brief_emphasis"] == ["lesson:token-budget"], d["brief_emphasis"]
allids = {"lesson:retry-storm", "lesson:token-budget", "lesson:cache-warmth"}
for c in d["candidates"]:
    seq = c.get("sections") or c.get("beats")
    assert seq[0] == "lesson:token-budget", c
    assert set(seq) == allids, c          # nothing dropped: emphasis reorders only
PYEOF

# --- 4. no invented evidence: only MATCHED element ids are ever named -----------
ST "$ELEMS" "cover the kubernetes migration and the billing incident" \
  > "$work/unmatched.json" 2>/dev/null
python3 - "$work/unmatched.json" "$work/plain.json" <<'PYEOF' && ok "a brief naming things no cluster covers never invents them into a candidate (no evidence absent from the fact sheet)" || err "brief leaked unmatched material into candidates"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("brief_emphasis", []) == [], d.get("brief_emphasis")
# a brief matching no cluster and cueing no shape degrades to the element-only
# candidates — it is NOT reported as brief-informed, and it invents nothing
assert d.get("brief_informed") is None, d
assert json.load(open(sys.argv[2])) == d, "unmatched brief changed the candidates"
blob = json.dumps(d).lower()
for word in ("kubernetes", "billing", "migration"):
    assert word not in blob, word
allids = {"lesson:retry-storm", "lesson:token-budget", "lesson:cache-warmth"}
for c in d["candidates"]:
    assert set(c.get("sections") or c.get("beats")) == allids, c
PYEOF

# --- 5. the shipped guarantees survive the widening ----------------------------
for brief in "tell the story over time" "what pattern ties these together" \
             "just the retry storm, in depth" "walk each lesson one by one"; do
  ST "$ELEMS" "$brief" > "$work/g.json" 2>/dev/null || err "structures failed for brief: $brief"
  python3 - "$work/g.json" <<'PYEOF' || err "guarantees broken for a brief"
import json, sys
d = json.load(open(sys.argv[1]))
c = d["candidates"]
assert 2 <= len(c) <= 3, c                                   # >=2, capped at 3
assert len({x["structure"] for x in c}) == len(c), c          # distinct
assert d["default"] == "sibling-lessons", d                   # default unchanged
sib = next(x for x in c if x["structure"] == "sibling-lessons")
assert sib.get("default") is True, sib                        # default marked
for x in c:
    assert (x.get("rationale") or "").strip(), x              # element-grounded rationale
PYEOF
done
ok ">=2 distinct candidates, capped at 3, sibling-lessons still the marked default, every candidate carries a rationale"

# --- 6. deterministic: same inputs -> same candidates ---------------------------
a=$(ST "$ELEMS" "the story of the retry storm over time" | sha256sum)
b=$(ST "$ELEMS" "the story of the retry storm over time" | sha256sum)
[ "$a" = "$b" ] && ok "composition is deterministic — the same brief x elements yields the same candidates" \
  || err "proposer is not deterministic"

# --- 7. the brief may ride the run state, and --brief accepts a file ------------
printf '%s' '{"elements":[{"id":"lesson:a","kinds":["cost"]},{"id":"lesson:b","kinds":["motivation"]}],"brief":{"text":"what pattern ties these together","provenance":"owner-authored","origin":"inline"}}' \
  | python3 "$DP" structures > "$work/state.json" 2>/dev/null
python3 - "$work/state.json" <<'PYEOF' && ok "the recorded run-state brief (state.brief) informs the candidates without a flag" || err "state-carried brief ignored"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("brief_informed") is True, d
assert "thematic-braid" in {c["structure"] for c in d["candidates"]}, d
PYEOF
printf 'tell the story of how the retry storm unfolded\n' > "$work/brief.md"
ST "$ELEMS" "$work/brief.md" > "$work/file.json" 2>/dev/null
python3 - "$work/file.json" <<'PYEOF' && ok "--brief accepts a file path, resolved by the same reader stage 0 uses (#505)" || err "--brief file path not resolved"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("brief_informed") is True, d
assert d["brief_emphasis"] == ["lesson:retry-storm"], d
PYEOF

# --- 8. exactly ONE proposer exists (no second mechanism) ----------------------
n=$(grep -c '^def _narrative_structures' "$DP" || true)
[ "$n" = "1" ] && ok "exactly one structure proposer function (_narrative_structures) — no second proposer introduced" \
  || err "expected exactly 1 _narrative_structures definition, found $n"
n=$(grep -c '"structures": cmd_structures' "$DP" || true)
[ "$n" = "1" ] && ok "exactly one structures subcommand carries it" \
  || err "expected exactly 1 structures dispatch entry, found $n"
grep -rlE '^def .*(narrative_structure|propose_structures|structure_candidates)' \
  "$root/scripts" 2>/dev/null | grep -v 'draft-pipeline.py' > "$work/others" || true
[ ! -s "$work/others" ] && ok "no other script defines a structure proposer" \
  || err "a second structure proposer exists: $(cat "$work/others")"

# --- 9. SKILL states the widened-input contract --------------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qiE 'structures --brief|--brief .*structures' \
  && ok "SKILL shows passing the brief to the proposer" || err "SKILL missing the --brief invocation"
printf '%s' "$S" | grep -qiE 'no second proposer' \
  && ok "SKILL: the widening adds no second proposer" || err "SKILL missing the one-proposer rule"
printf '%s' "$S" | grep -qiE 'brief-requested' && printf '%s' "$S" | grep -qi 'evidence-signalled' \
  && ok "SKILL names the brief-requested vs evidence-signalled grounding split" \
  || err "SKILL missing the grounding distinction"
printf '%s' "$S" | grep -qiE 'emphasis and shape, never scope|never a scope widener' \
  && ok "SKILL: the brief steers emphasis and shape, never scope" \
  || err "SKILL missing the no-scope-widening rule for the proposer"
printf '%s' "$S" | grep -qiE 'only element ids the brief actually matched' \
  && ok "SKILL: only matched element ids are named (no invented evidence)" \
  || err "SKILL missing the no-invented-evidence rule"
printf '%s' "$S" | grep -qiE 'With no brief, the candidates are exactly the element-only ones' \
  && ok "SKILL: with no brief the behavior is unchanged" || err "SKILL missing the no-brief clause"

if [ "$fail" -eq 0 ]; then
  printf '\nAll brief-informed-structures checks passed.\n'; exit 0
else
  printf '\nbrief-informed-structures checks FAILED.\n' >&2; exit 1
fi
