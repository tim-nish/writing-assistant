#!/usr/bin/env sh
# tier: inner — fixture-based: a handful of `structures` invocations over inline
#   JSON, no pipeline run, no seam call. Milliseconds, so it belongs in the
#   per-edit loop that guards the composer it checks.
# removal-signal: the placement cover stops being counted in the drafting
#   composer — either because SPEC-article-draft-pipeline CAP-3's
#   "Composition over an owner-selected Strand set" clause is withdrawn, or
#   because the count moves upstream into the brief emitter and the composer's
#   candidates are no longer where placements are decided. Either observation
#   retires this file with the code it guards.
#
# check-strand-cover-inner.sh — verify Story 20.61 (#965, umbrella #945;
# SPEC-article-draft-pipeline CAP-3 "Composition over an owner-selected Strand
# set", 2026-07-30): the structure composer's output is COVERED, counted AFTER
# composition. Every owner-selected Strand is placed in each composed candidate
# or its omission is disclosed BY NAME — a cover, not a partition; per
# candidate, not just the default; an annotation, never a narrowing.
# POSIX shell + stdlib Python only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/stages/strand-cover.md"
STAGE3="skills/draft-article/stages/stage3.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

ST() { printf '%s' "$1" | python3 "$DP" structures; }

# Three selected Strands; the composer sees only TWO of them as elements, so an
# omission exists IN FACT while the composer's inputs claim nothing about it.
PARTIAL='{"elements":[
  {"id":"lesson:retry-storm","kinds":["chronology","cost"]},
  {"id":"lesson:token-budget","kinds":["chronology","motivation"]}],
 "brief":{"text":"what pattern ties these together","provenance":"owner-authored",
   "origin":"adopted-index-set",
   "members":[{"index":"L3","slug":"retry-storm","gloss":"the retry storm"},
              {"index":"L7","slug":"token-budget","gloss":"the token budget"},
              {"index":"L9","slug":"cache-warmth","gloss":"cache warmth"}]}}'

ST "$PARTIAL" > "$work/partial.json" 2>/dev/null || err "structures failed with a member set"

# --- 1. the count runs after composition, on the emitted placements ------------
python3 - "$work/partial.json" <<'PYEOF' && ok "the cover is counted after composition, from each candidate's own emitted placements (sections/beats)" || err "cover not counted from the composed output"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["strand_cover"]["counted"] == "after-composition", d["strand_cover"]
for c in d["candidates"]:
    cov = c["cover"]
    assert cov["counted"] == "after-composition", c
    placed = c.get("sections") or c.get("beats")
    # every placement count is derivable from THIS candidate's placements
    for name, n in cov["placements"].items():
        assert isinstance(n, int), cov
    # the composer's inputs carried three members; the output places two
    assert cov["selected"] == 3 and cov["placed"] == 2, cov
    assert len(placed) == 2, c
PYEOF

# --- 2. a cover, not a partition: two or more placements PASSES ----------------
# One Strand carrying two tags is placed in two co-tag sections. A naive
# len(placements) == len(selected) test fails here; a cover does not.
MULTI='{"elements":[
  {"id":"tag:reliability:cache-warmth","kinds":["cost"]},
  {"id":"tag:latency:cache-warmth","kinds":["cost"]},
  {"id":"lesson:token-budget","kinds":["motivation"]}],
 "brief":{"text":"braid them by theme",
   "members":[{"index":"L9","slug":"cache-warmth","gloss":"cache warmth"},
              {"index":"L7","slug":"token-budget","gloss":"the token budget"}]}}'
ST "$MULTI" > "$work/multi.json" 2>/dev/null || err "structures failed on the multi-placement fixture"
python3 - "$work/multi.json" <<'PYEOF' && ok "a Strand placed in two or more sections PASSES the cover — only zero placements is an omission (cover, not partition)" || err "multi-placement Strand treated as a defect"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["strand_cover"]["complete"] is True, d["strand_cover"]
for c in d["candidates"]:
    cov = c["cover"]
    assert cov["placements"]["L9"] >= 2, cov      # placed twice
    assert cov["placements"]["L7"] == 1, cov
    assert cov["omitted"] == [], cov              # >1 is never an omission
    assert cov["complete"] is True, cov
    # the naive equality test would have failed: more placements than members
    seq = c.get("sections") or c.get("beats")
    assert len(seq) > cov["selected"], (seq, cov)
PYEOF

# --- 3. an omission is disclosed BY NAME, and the candidate is still offered ---
python3 - "$work/partial.json" <<'PYEOF' && ok "an omitted Strand is named individually in the presentation, and the structure carrying the omission is still offered (disclosure, never rejection)" || err "omission not disclosed by name, or the candidate was withheld"
import json, sys
d = json.load(open(sys.argv[1]))
assert 2 <= len(d["candidates"]) <= 3, d["candidates"]   # nothing withheld
for c in d["candidates"]:
    cov = c["cover"]
    assert cov["complete"] is False, cov
    names = [m.get("index") for m in cov["omitted"]]
    assert names == ["L9"], cov
    assert cov["omitted"][0]["slug"] == "cache-warmth", cov
    # named in the OWNER-FACING rationale, not only in the structured payload
    r = c["rationale"]
    assert "L9" in r and "cache-warmth" in r, r
    assert "L9 (cache-warmth)" in d["strand_cover"]["candidates"][c["structure"]]["omitted"], d
PYEOF

# --- 4. per candidate, independently -----------------------------------------
# The default places both Strands it can; an alternative is given an emptier
# beat list only in this fixture's second run, so the per-candidate result is
# not a copy of the default's. Here the assertion is structural: EVERY
# candidate carries its own cover object and its own name in the summary.
python3 - "$work/partial.json" <<'PYEOF' && ok "every candidate carries its OWN cover result and disclosure — not just the default" || err "cover missing on a non-default candidate"
import json, sys
d = json.load(open(sys.argv[1]))
summary = d["strand_cover"]["candidates"]
assert len(d["candidates"]) >= 2, d
for c in d["candidates"]:
    assert isinstance(c.get("cover"), dict), c
    assert c["structure"] in summary, (c["structure"], summary)
nondefault = [c for c in d["candidates"] if not c.get("default")]
assert nondefault, d["candidates"]
for c in nondefault:
    assert c["cover"]["omitted"], c        # disclosed on the non-default too
PYEOF

# --- 5. no brief, no member set: today's output exactly, no cover imposed ------
ELEMS='{"elements":[
  {"id":"lesson:retry-storm","kinds":["chronology","cost"]},
  {"id":"lesson:token-budget","kinds":["motivation"]},
  {"id":"lesson:cache-warmth","kinds":["cost"]}]}'
ST "$ELEMS" > "$work/plain.json" 2>/dev/null || err "structures failed without a brief"
printf '%s' '{"elements":[
  {"id":"lesson:retry-storm","kinds":["chronology","cost"]},
  {"id":"lesson:token-budget","kinds":["motivation"]},
  {"id":"lesson:cache-warmth","kinds":["cost"]}],
 "brief":{"text":"what pattern ties these together"}}' \
  | python3 "$DP" structures > "$work/nomembers.json" 2>/dev/null
python3 - "$work/plain.json" "$work/nomembers.json" <<'PYEOF' && ok "input carrying no Strand set: the output is exactly today's — no cover key, no rationale change (the pre-existing element-selection path is untouched)" || err "the no-member-set path changed"
import json, sys
for path in sys.argv[1:]:
    d = json.load(open(path))
    assert "strand_cover" not in d, (path, d)
    for c in d["candidates"]:
        assert "cover" not in c, (path, c)
        r = c["rationale"]
        assert "Omits" not in r and "Places all" not in r, (path, r)
PYEOF

# --- 6. the cover is a check, not a narrowing --------------------------------
# Same elements and brief text, with and without the member set: the candidate
# LIST — order, membership, composition and placements — is identical. Only
# annotations differ.
python3 - "$work/partial.json" <<'PYEOF' && ok "the cover annotates only: it never reorders, filters, drops or chooses among candidates" || err "the cover altered the candidate set"
import json, subprocess, sys, os
root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                               text=True).strip()
dp = os.path.join(root, "scripts", "draft-pipeline.py")
elems = [{"id": "lesson:retry-storm", "kinds": ["chronology", "cost"]},
         {"id": "lesson:token-budget", "kinds": ["chronology", "motivation"]}]
text = "what pattern ties these together"
members = [{"index": "L3", "slug": "retry-storm"},
           {"index": "L9", "slug": "cache-warmth"}]

def run(brief):
    p = subprocess.run([sys.executable, dp, "structures"],
                       input=json.dumps({"elements": elems, "brief": brief}),
                       capture_output=True, text=True)
    assert p.returncode == 0, p.stderr
    return json.loads(p.stdout)

bare = run({"text": text})
covered = run({"text": text, "members": members})
assert [c["structure"] for c in bare["candidates"]] \
    == [c["structure"] for c in covered["candidates"]], "order/membership changed"
assert bare["default"] == covered["default"], "the default changed"
for b, c in zip(bare["candidates"], covered["candidates"]):
    assert b.get("default") == c.get("default"), (b, c)
    assert b.get("sections") == c.get("sections"), (b, c)
    assert b.get("beats") == c.get("beats"), (b, c)
    assert b.get("provenance") == c.get("provenance"), (b, c)
    # only the annotations are new
    assert set(c) - set(b) == {"cover"}, set(c) - set(b)
    assert c["rationale"].startswith(b["rationale"]), (b, c)
PYEOF

# --- 7. the count is read from the composed output, not asserted about inputs --
# A guard against the regression the clause names: satisfying the cover from
# the composer's INPUTS. The cover must read `sections`/`beats`.
python3 - <<'PYEOF' && ok "the cover implementation reads the emitted candidate's placements (sections/beats), not the element list it was given" || err "cover reads the composer's inputs"
import re, subprocess, os
root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                               text=True).strip()
src = open(os.path.join(root, "scripts", "draft-pipeline.py"),
           encoding="utf-8").read()
mod = open(os.path.join(root, "scripts", "strand_cover.py"), encoding="utf-8").read()
m = re.search(r"\ndef candidate_placements\(.*?\n(?=\ndef )", mod, re.S)
assert m, "no candidate_placements reader"
body = m.group(0)
assert '"sections"' in body and '"beats"' in body, body
# the cover is applied AFTER the candidates exist: the call site passes `out`,
# the composer's assembled output, from the LAST line of _narrative_structures
assert re.search(r'return _load\("strand_cover.py"\).apply_cover\(out, brief\)', src)
# and it never reaches back for the elements the composer was handed
apply_body = re.search(r"\ndef apply_cover\(.*", mod, re.S).group(0)
assert "elements" not in apply_body, apply_body
PYEOF

# --- 8. SKILL states the cover contract --------------------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qiE 'placement cover|cover, counted after composition' \
  && ok "SKILL names the placement cover" || err "SKILL missing the placement-cover section"
printf '%s' "$S" | grep -qiE 'counted after composition|after composition' \
  && ok "SKILL: the cover is counted after composition" || err "SKILL missing the ordering rule"
printf '%s' "$S" | grep -qiE 'cover, not a partition' \
  && ok "SKILL: a cover, not a partition (two or more placements pass)" \
  || err "SKILL missing the cover-not-partition rule"
printf '%s' "$S" | grep -qiE 'named individually|discloses the omission by name' \
  && ok "SKILL: an omission is disclosed by name" || err "SKILL missing the by-name disclosure rule"
printf '%s' "$S" | grep -qiE 'per candidate' \
  && ok "SKILL: per candidate, not just the default" || err "SKILL missing the per-candidate rule"
printf '%s' "$S" | grep -qiE 'no cover check is imposed' \
  && ok "SKILL: with no member set no cover check is imposed" || err "SKILL missing the no-set clause"
grep -q 'strand-cover.md' "$STAGE3" \
  && ok "stage3 points at the cover companion, so the stage that composes reaches it" \
  || err "stage3.md does not reference strand-cover.md"

if [ "$fail" -eq 0 ]; then
  printf '\nAll strand-cover checks passed.\n'; exit 0
else
  printf '\nstrand-cover checks FAILED.\n' >&2; exit 1
fi
