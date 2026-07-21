#!/usr/bin/env sh
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
SKILL="skills/draft-article/SKILL.md"
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

if [ "$fail" -eq 0 ]; then
  printf '\nAll coverage-brief checks passed.\n'; exit 0
else
  printf '\ncoverage-brief checks FAILED.\n' >&2; exit 1
fi
