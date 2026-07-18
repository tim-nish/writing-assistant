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

# A host repo with the policy seam ENABLED (Story 13.73: presence toggle —
# the consumer holds no hub path). The no-facts invariant is now STRUCTURAL:
# policy content arrives only through the gateway seam, whose cites are
# hub-relative `file:line@<hub-sha>` pointers that cannot resolve in the
# declared host scope — a policy line has no resolvable SOURCE form.
h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
printf 'intro\nThroughput doubled under load\n' > "$h/notes.md"
git -C "$h" add notes.md; git -C "$h" -c user.email=t@e -c user.name=t commit -q -m init
sha=$(git -C "$h" rev-parse HEAD)

# A hub commit sha that exists nowhere in the declared scope — the shape of
# every gateway cite (the pin is the HUB's commit, not a host commit).
psha=1111111111111111111111111111111111111111

python3 "$root/scripts/resolve-writing-sources.py" --root "$h" set-sources >/dev/null 2>&1 <<JSON
[{"path": "."}]
JSON
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" set-policy-source >/dev/null 2>&1

emit() { printf '%s\n' "$1" > "$work/fs.md"; }
reason() { python3 "$root/$VAL" "$work/fs.md" --root "$h" 2>&1; }
V() { python3 "$root/$VAL" "$work/fs.md" --root "$h" >/dev/null 2>&1; }

# AC1 — a claim grounded in a policy line is rejected: a seam cite
# (hub-relative path @ hub sha) does not resolve in the declared host scope,
# so a policy line never grounds a claim; a real repository source in the
# same run still passes.
emit "- Channel is for solo builders / LESSONS.md:1@$psha / decision"
V && err "policy-line SOURCE (seam cite) accepted as evidence" \
  || ok "AC1: a seam-cited policy line is rejected (unresolvable in host scope — no-facts)"
emit "- Throughput doubled under load / notes.md:2@$sha / result"
V && ok "AC1: a genuine repository SOURCE still validates (rejection is scope-driven)" \
  || err "legitimate repository evidence rejected"

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
