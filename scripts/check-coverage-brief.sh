#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# covers: scripts/draft-pipeline.py scripts/write-article-plan.py skills/draft-article/stages/stage0.md
# check-coverage-brief.sh — verify the free-form owner coverage brief (Story
# 18.24, #505): an OPTIONAL stage-0 input (text or file) recorded in run state
# with owner-authored provenance and in the article plan; it maps to story-
# element clusters (selected + disclosed per CAP-9), a brief item matching no
# cluster surfaces as a NEEDS-OWNER gap (never silently dropped), it supplies the
# owner's thesis candidate to the argument plan, and harvest emphasis follows it
# WITHIN the declared sources. The brief is a filter/emphasis, NEVER a scope
# widener (same rule as the #431 --element pin). POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
W="scripts/write-article-plan.py"
SKILL="skills/draft-article/stages/stage0.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }
python3 -c "import py_compile; py_compile.compile('$root/$W', doraise=True)" 2>/dev/null \
  && ok "writer compiles" || err "writer syntax error"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
printf 'sources:\n  - path: .\n' > "$host/writing-sources.yaml"

# --- 1. an inline brief is recorded in run state with owner-authored provenance --
out=$(python3 "$DP" start F2 specs/ --root "$host" --brief "cover the retry storm and the token budget")
echo "$out" | jget "d.get('brief',{}).get('provenance')" | grep -q owner-authored \
  && ok "inline --brief recorded with owner-authored provenance" || err "brief provenance not recorded"
echo "$out" | jget "d.get('brief',{}).get('origin')" | grep -q inline \
  && ok "inline brief origin is 'inline'" || err "inline brief origin wrong"
echo "$out" | jget "d.get('brief',{}).get('text')" | grep -q 'retry storm' \
  && ok "inline brief text captured verbatim" || err "inline brief text missing"

# --- 2. a file brief is read and its origin recorded ----------------------------
printf 'Focus on the arbitration bug and how the judge missed it.\n' > "$work/brief.txt"
out=$(python3 "$DP" start F2 specs/ --root "$host" --brief "$work/brief.txt")
echo "$out" | jget "d.get('brief',{}).get('origin')" | grep -q file \
  && ok "a --brief that is a file path is read (origin 'file')" || err "file brief not read"
echo "$out" | jget "d.get('brief',{}).get('text')" | grep -q 'arbitration bug' \
  && ok "file brief contents captured" || err "file brief contents missing"
echo "$out" | jget "d.get('brief',{}).get('source')" | grep -q 'brief.txt' \
  && ok "file brief records its source path (provenance)" || err "file brief source path missing"

# --- 3. the brief NEVER widens the source boundary (filter, not scope widener) ---
base=$(python3 "$DP" start F2 specs/ --root "$host" | jget 'json.dumps(d["sources"])')
withb=$(python3 "$DP" start F2 specs/ --root "$host" --brief "cover only the retry storm" | jget 'json.dumps(d["sources"])')
[ "$base" = "$withb" ] \
  && ok "the brief leaves the classified sources identical (never widens the boundary)" \
  || err "the brief changed the source set: base=$base with=$withb"

# --- 4. no --brief -> no brief key (prior behavior byte-for-byte) ----------------
python3 "$DP" start F2 specs/ --root "$host" | jget "'brief' in d" | grep -q False \
  && ok "no --brief -> no brief key (prior behavior unchanged)" || err "brief key present without a brief"

# stage0 carries the same directive.
export XDG_STATE_HOME="$work/state"
python3 "$DP" stage0 F2 specs/ --root "$host" --brief "cover the retry storm" \
  | jget "d['run_state'].get('brief',{}).get('provenance')" | grep -q owner-authored \
  && ok "stage0 also captures the brief into run_state" || err "stage0 did not capture the brief"
unset XDG_STATE_HOME

# --- 5. the plan writer records the brief provenance (owner-authored) ------------
sha=a1b2c3d4e5f6a7b8
planwith() { # value
cat > "$work/plan.md" <<EOF
---
kind: article-plan
slug: p
intent: share engineering lessons
claim: structured discovery paid off
status: outlined
run_id: 20260720T090000-000001
pin: host@$sha
brief_provenance: $1
---

## Section plan

- the lesson / host/log.txt:12@$sha
EOF
}
planwith owner-authored
python3 "$W" validate --path plans/p.md "$work/plan.md" >/dev/null 2>&1 \
  && ok "plan accepts brief_provenance: owner-authored" || err "plan refused owner-authored brief provenance"
planwith invented-by-tool
python3 "$W" validate --path plans/p.md "$work/plan.md" >/dev/null 2>&1 \
  && err "plan accepted a non-owner brief provenance (must be owner-authored)" \
  || ok "plan refuses a brief provenance that is not owner-authored"

# --- 6. SKILL states the coverage-brief contract --------------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qi 'coverage brief' \
  && ok "SKILL names the coverage brief" || err "SKILL missing the coverage-brief section"
printf '%s' "$S" | grep -qi 'owner-authored' \
  && ok "SKILL: the brief is recorded with owner-authored provenance" \
  || err "SKILL missing the owner-authored provenance"
printf '%s' "$S" | grep -qiE 'maps to (story )?element|story-element cluster|element clusters' \
  && ok "SKILL: the brief maps to story-element clusters (selected + disclosed per CAP-9)" \
  || err "SKILL missing the brief->cluster mapping"
printf '%s' "$S" | grep -qi 'NEEDS-OWNER' \
  && printf '%s' "$S" | grep -qiE 'never silently dropped|not silently dropped|never dropped' \
  && ok "SKILL: a brief item matching no cluster surfaces as NEEDS-OWNER, never dropped" \
  || err "SKILL missing the unmatched-item NEEDS-OWNER rule"
printf '%s' "$S" | grep -qiE 'thesis candidate' \
  && ok "SKILL: the brief supplies the owner's thesis candidate to the argument plan" \
  || err "SKILL missing the thesis-candidate wiring"
printf '%s' "$S" | grep -qiE 'within the (writing-sources-)?declared|within the declared sources|declared-source' \
  && ok "SKILL: harvest emphasis follows the brief within the declared sources" \
  || err "SKILL missing the within-declared-sources emphasis"
printf '%s' "$S" | grep -qiE 'never (a )?scope widener|not (a )?scope widener|does not widen' \
  && ok "SKILL: the brief is a filter/emphasis, never a scope widener" \
  || err "SKILL missing the never-a-scope-widener invariant"
printf '%s' "$S" | grep -qi 'q_a' \
  && ok "SKILL: q_a/ stays unreachable (promotion is the only path)" \
  || err "SKILL missing the q_a-stays-unreachable clause"

# --- 7. the brief RECORD carries the journey arcs across the boundary ----------
# Story 20.91 (#1044): a `--brief` FILE that is a JSON brief record resolves to
# the brief STRING it carries plus the selected Strands' served arcs, recorded
# BESIDE `sources` as declared source material at the pin.
cat > "$work/brief-record.json" <<'EOF'
{"brief": "cover the retry storm — the cold-start angle",
 "stage": "topic-map-brief",
 "pins": {"terrain": "abc123", "hub": "def456"},
 "members": [
   {"index": "L2", "slug": "retry-storm", "gloss": "GLOSS-ALPHA", "cite": "x",
    "journey": {"arc": "ARC-ALPHA the belief inverted after the retro.",
                "arc_cite": "gloss/journeys/agents.md:6@" ,
                "served": true, "not_served_reason": null}},
   {"index": "L1", "slug": "cache-warmth", "gloss": "GLOSS-BETA", "cite": "y",
    "journey": {"arc": null, "arc_cite": null, "served": false,
                "not_served_reason": "no journey shard is named for this lesson"}},
   {"index": "L3", "slug": "team-shape", "gloss": "GLOSS-GAMMA", "cite": "z"}]}
EOF
out=$(python3 "$DP" start F2 specs/ --root "$host" --brief "$work/brief-record.json")
echo "$out" | jget "d.get('brief',{}).get('origin')" | grep -q brief-record \
  && ok "a JSON brief record is recognised by shape (origin 'brief-record')" \
  || err "brief record not recognised"
echo "$out" | jget "d.get('brief',{}).get('text')" | grep -q '^cover the retry storm — the cold-start angle$' \
  && ok "the brief STRING is the record's own, used unchanged (behaviour uniform)" \
  || err "brief record text wrong"
echo "$out" | jget "json.dumps(d.get('journey_arcs',{}).get('at'))" | grep -q def456 \
  && ok "the arcs are carried AT the recorded pin" || err "arc pin not carried"
echo "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
a = {x['slug']: x for x in d['journey_arcs']['arcs']}
assert a['retry-storm']['arc'] == 'ARC-ALPHA the belief inverted after the retro.', a
assert a['retry-storm']['served'] is True and a['retry-storm']['arc_cite'], a
# AC2: absence keeps its kinds — 'no arc exists' vs 'no arc arrived' vs a
# record that predates the field. None of the three collapse into the others.
assert a['cache-warmth']['served'] is False, a
assert 'no journey shard' in a['cache-warmth']['not_served_reason'], a
assert a['team-shape']['served'] is False, a
assert 'predates' in a['team-shape']['not_served_reason'], a
" && ok "the served arc is quoted verbatim; absence keeps its three kinds" \
  || err "arc payload wrong"
# AC3: the arcs arrive ALONGSIDE the sources — the source set is untouched.
arcsrc=$(echo "$out" | jget 'json.dumps(d["sources"])')
[ "$base" = "$arcsrc" ] \
  && ok "arcs never widen the source boundary (repositories stay harvest scope)" \
  || err "the brief record changed the source set: base=$base with=$arcsrc"
# The entry request carries the brief TEXT, never the file's path.
if echo "$out" | jget "d.get('entry',{}).get('request','')" | grep -q 'brief-record.json'; then
  err "the entry request leaked the brief file path"
else
  ok "the entry request carries the brief text, never a machine path"
fi
# A plain-text brief file is untouched by all of the above.
out=$(python3 "$DP" start F2 specs/ --root "$host" --brief "$work/brief.txt")
echo "$out" | jget "'journey_arcs' in d" | grep -q False \
  && ok "a plain text brief grows no journey_arcs (format, not producer)" \
  || err "a plain text brief was read as a record"

# --- 8. the stage-0 surface states the arc contract ----------------------------
printf '%s' "$S" | grep -qi 'journey_arcs' \
  && ok "stage0: the run state's journey_arcs is documented" \
  || err "stage0 missing the journey_arcs contract"
printf '%s' "$S" | grep -qiE 'alongside the host-repo sources|beside .sources.' \
  && ok "stage0: arcs arrive alongside the host-repo sources, never in place" \
  || err "stage0 missing the alongside-the-sources clause"
printf '%s' "$S" | grep -qiE 'article floor is unchanged|never satisfies it|never a new licence' \
  && ok "stage0: the article floor is unchanged — an arc is not a Fact" \
  || err "stage0 missing the article-floor clause"
# The host-side recording task stage0 used to hold the arc apart from was
# RETIRED with the join that minted it (Story 20.134, #1183). The assertion that
# stage0 stated their adjacency is deleted rather than weakened; what stage0
# still owes — the arc is material and never a Fact — is asserted just above.
printf '%s' "$S" | grep -qi 'NEEDS-RECORDING' \
  && err "stage0 still names the retired host-side recording task (#1183)" \
  || ok "stage0 names no retired recording task (#1183)"
printf '%s' "$S" | grep -qi '#1045' \
  && printf '%s' "$S" | grep -qi 'parked' \
  && ok "stage0: the incorporation register stays parked (#1045), nothing decided" \
  || err "stage0 missing the parked-register clause"
printf '%s' "$S" | grep -qiE 'format and never a producer|never a producer' \
  && ok "stage0: the record is a format, never a producer (entry-agnosticism)" \
  || err "stage0 missing the format-not-producer clause"

if [ "$fail" -eq 0 ]; then
  printf '\nAll coverage-brief checks passed.\n'; exit 0
else
  printf '\ncoverage-brief checks FAILED.\n' >&2; exit 1
fi
