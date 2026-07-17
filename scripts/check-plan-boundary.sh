#!/usr/bin/env sh
# check-plan-boundary.sh — verify the article-plan boundary fences (Story 13.56,
# SPEC-article-plan constraints). POSIX shell + stdlib Python, real git fixture.
#
# The article plan is machine-fenced out of the evidence stream: harvest never
# extracts facts from it, and the provenance gate rejects any claim grounded
# only in a plan pointer. The `kind: article-plan` marker is the machine-
# checkable no-facts posture — a plan may shape questions/recommendations but
# can never ground a claim.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VAL="scripts/validate-fact-sheet.py"
VP="scripts/verify-provenance.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
h="$work/host"; mkdir -p "$h/plans"; git -C "$h" init -q

# A real source file (a legitimate SOURCE) and an article plan sharing scope.
printf 'intro\nThroughput doubled under load\n' > "$h/notes.md"
cat > "$h/plans/interview-is-the-difference.md" <<'EOF'
---
kind: article-plan
slug: interview-is-the-difference
intent: share engineering lessons
claim: the interview is the difference
status: outlined
run_id: 20260717T135459-737958
pin: host@PLACEHOLDER
---

## Section plan

- the interview carries the article / notes.md:2@PLACEHOLDER
EOF
git -C "$h" add -A
git -C "$h" -c user.email=t@e -c user.name=t commit -q -m init
sha=$(git -C "$h" rev-parse HEAD)
printf 'sources:\n  - path: .\n' > "$h/writing-sources.yaml"

emit() { printf '%s\n' "$1" > "$work/fs.md"; }
reason() { python3 "$root/$VAL" "$work/fs.md" --root "$h" 2>&1; }
V() { python3 "$root/$VAL" "$work/fs.md" --root "$h" >/dev/null 2>&1; }

# AC1 — harvest excludes plans/: a SOURCE pointing into an article-plan file is
# rejected, so zero fact-sheet entries can cite it (the "lines rejected as
# SOURCEs" enforcement path). A pointer into the plan's own body line fails too.
emit "- Central claim / plans/interview-is-the-difference.md:4@$sha / decision"
reason | grep -qi 'article plan' && ok "AC1: a SOURCE into an article-plan file is rejected" \
  || err "plan-pointer SOURCE accepted"
emit "- Plan body line / plans/interview-is-the-difference.md:12@$sha / quote"
reason | grep -qi 'article plan' && ok "AC1: a pointer into the plan body is rejected" \
  || err "plan body pointer accepted"

# A legitimate non-plan SOURCE in the same declared scope still passes — the
# fence is the marker, not the directory or the repo.
emit "- Throughput doubled under load / notes.md:2@$sha / result"
V && ok "AC1: a real source pointer in the same scope still validates" \
  || err "the marker fence rejected a legitimate source"

# AC2/AC3 — the provenance gate rejects a claim grounded only in a plan pointer.
# A plan pointer can never enter the fact-sheet id set (rejected above), so a
# derived/sourced claim citing it fails to resolve — a gate failure.
printf 'notes.md:2@%s\n' "$sha" > "$work/ids.txt"     # the ONLY valid fact-sheet id
cat > "$work/map.txt" <<EOF
P1.S1: sourced <- plans/interview-is-the-difference.md:4@$sha
EOF
python3 "$root/$VP" --map "$work/map.txt" --fact-sheet "$work/ids.txt" >/dev/null 2>&1 \
  && err "provenance gate accepted a plan-only-grounded claim" \
  || ok "AC2/AC3: a claim grounded only in a plan pointer fails the provenance gate"
# A claim grounded in the real evidence passes — re-grounding is the escape hatch.
cat > "$work/map2.txt" <<EOF
P1.S1: sourced <- notes.md:2@$sha
EOF
python3 "$root/$VP" --map "$work/map2.txt" --fact-sheet "$work/ids.txt" >/dev/null 2>&1 \
  && ok "AC3: the same idea re-grounded on current evidence passes" \
  || err "a re-grounded claim was rejected"

# AC4 — vocabulary: the article-plan surface names the artifact 'article plan',
# never 'skeleton'. The plan writer, its check, the plan spec, and the plan's
# skill section are grep-clean of 'skeleton' as a name for the artifact.
for f in scripts/write-article-plan.py specs/spec-article-plan/SPEC.md; do
  # allow the word only where the spec explicitly says skeleton appears nowhere
  hits=$(grep -in 'skeleton' "$f" | grep -vi 'appears nowhere' || true)
  [ -z "$hits" ] && ok "AC4: '$f' is grep-clean of 'skeleton' as a plan name" \
    || err "'skeleton' names the plan in $f: $hits"
done
# The harvest fence names the marker, not 'skeleton'.
grep -q 'kind: article-plan' skills/harvest/SKILL.md \
  && ok "AC4: harvest fence names the kind: article-plan marker" \
  || err "harvest fence missing the article-plan marker"

if [ "$fail" -eq 0 ]; then
  printf '\nAll plan-boundary checks passed.\n'; exit 0
else
  printf '\nplan-boundary checks FAILED.\n' >&2; exit 1
fi
