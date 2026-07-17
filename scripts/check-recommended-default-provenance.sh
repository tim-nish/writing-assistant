#!/usr/bin/env sh
# check-recommended-default-provenance.sh — end-to-end guards for the
# recommended-default feature (Story 13.61, SPEC-policy-editorial-direction
# CAP-6). POSIX shell + stdlib Python, real git fixtures.
#
# Proves the no-facts and audited invariants hold under the recall-then-ratify
# path: a policy line never grounds a claim (provenance fence), a ratified
# default is owner judgment carrying no policy pointer, and the ineligible/
# tension defaults are rejected before the owner ever sees them.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VAL="scripts/validate-fact-sheet.py"
ITEMS="scripts/validate-interview-items.py"
DP="scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_CONFIG_HOME="$work/xdg"; export XDG_CONFIG_HOME

# A host repo whose declared harvest scope ALSO includes the policy repo — the
# only way a policy line could reach a fact sheet as a resolvable SOURCE. The
# fence must reject it anyway.
h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
printf 'intro\nThroughput doubled under load\n' > "$h/notes.md"
git -C "$h" add notes.md; git -C "$h" -c user.email=t@e -c user.name=t commit -q -m init
sha=$(git -C "$h" rev-parse HEAD)

pol="$work/policy"; mkdir -p "$pol"; git -C "$pol" init -q
printf 'the channel speaks to solo builders\nreproducibility is the feature\n' > "$pol/LESSONS.md"
git -C "$pol" add LESSONS.md; git -C "$pol" -c user.email=t@e -c user.name=t commit -q -m pol
psha=$(git -C "$pol" rev-parse HEAD)

# Declare BOTH the host and the policy repo as harvest sources, and declare the
# policy repo as the policy_source.
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" set-sources >/dev/null 2>&1 <<JSON
[{"path": "."}, {"path": "../policy"}]
JSON
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" set-policy-source "$pol" >/dev/null 2>&1

emit() { printf '%s\n' "$1" > "$work/fs.md"; }
reason() { python3 "$root/$VAL" "$work/fs.md" --root "$h" 2>&1; }
V() { python3 "$root/$VAL" "$work/fs.md" --root "$h" >/dev/null 2>&1; }

# AC1 — a claim grounded in a policy line is rejected (fence), exactly as an
# article-plan pointer is; a real repository source in the same run still passes.
emit "- Channel is for solo builders / ../policy/LESSONS.md:1@$psha / decision"
reason | grep -qi 'policy surface is never harvest evidence\|policy_source' \
  && ok "AC1: a fact-sheet SOURCE into the policy repo is rejected (no-facts fence)" \
  || err "policy-line SOURCE accepted as evidence"
emit "- Throughput doubled under load / notes.md:2@$sha / result"
V && ok "AC1: a genuine repository SOURCE still validates (fence is policy-scoped)" \
  || err "the fence rejected legitimate repository evidence"

# AC2 — audit isolation: a recalled position is never a fact-sheet entry. With
# no policy_source declared, behavior is unchanged (regression guard).
h2="$work/host2"; mkdir -p "$h2"; git -C "$h2" init -q
printf 'x\n' > "$h2/a.md"; git -C "$h2" add a.md; git -C "$h2" -c user.email=t@e -c user.name=t commit -q -m i
python3 "$root/scripts/resolve-writing-sources.py" --root "$h2" set-sources >/dev/null 2>&1 <<'JSON'
[{"path": "."}]
JSON
s2=$(git -C "$h2" rev-parse HEAD)
printf -- '- claim / a.md:1@%s / decision\n' "$s2" > "$work/fs2.md"
python3 "$root/$VAL" "$work/fs2.md" --root "$h2" >/dev/null 2>&1 \
  && ok "AC2: no policy_source declared -> validation unchanged (no fence false-positive)" \
  || err "fence fired without a declared policy_source"

# AC3 — the ineligible-class and tension defaults never reach the owner: the
# item validator rejects them before triage (schema guard from 13.59).
python3 "$ITEMS" scripts/fixtures/interview-items/r6-default-ineligible-class.json >/dev/null 2>&1 \
  && err "R6 default reached the owner" || ok "AC3: ineligible-class default rejected pre-owner (R6)"
python3 "$ITEMS" scripts/fixtures/interview-items/r7-default-on-tension.json >/dev/null 2>&1 \
  && err "R7 default reached the owner" || ok "AC3: tension-item default rejected pre-owner (R7)"

# AC3 cap accounting — a ratified default is recorded as owner judgment
# (interview provenance), never a pointer-inheriting SOURCE (the answer layer
# from 13.60); asserting the invariant end-to-end here.
rec=$(python3 "$DP" answer --id d1 --disposition ratified --text "solo builders" 2>/dev/null)
printf '%s' "$rec" | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['provenance']=='interview' and d['pointers']==[]" 2>/dev/null \
  && ok "AC3: a ratified default records as owner judgment with no SOURCE pointer" \
  || err "ratified default provenance/pointer leak: $rec"

# AC4 — the policy-influence report attributes recalled defaults to their seed.
grep -qi 'recommended default\|ratified' skills/policy-influence-report.md \
  && ok "AC4: policy-influence report accounts for recalled/ratified defaults" \
  || err "policy-influence report does not mention recalled defaults"

if [ "$fail" -eq 0 ]; then
  printf '\nAll recommended-default provenance checks passed.\n'; exit 0
else
  printf '\nrecommended-default provenance checks FAILED.\n' >&2; exit 1
fi
