#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# check-draft-scaffold.sh — verify the draft-article skill scaffold and stage-0
# invocation (Story 4.1). POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/draft-article/SKILL.md"
DP="scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 0. Helper compiles.
python3 -c "import py_compile; py_compile.compile('$root/$DP', doraise=True)" 2>/dev/null \
  && ok "stage-0 helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Skill scaffold present + invocable + generic.
[ -f "$SKILL" ] && ok "present: $SKILL" || { err "missing $SKILL"; printf '\nFAILED.\n' >&2; exit 1; }
head -1 "$SKILL" | grep -q '^---$' && ok "SKILL.md has frontmatter" || err "no frontmatter"
grep -q '^name: draft-article' "$SKILL" && ok "frontmatter name: draft-article" || err "missing name"
grep -q 'draft article <article-type> from <sources>' "$SKILL" && ok "documents the invocation (intent-label form)" || err "invocation not documented"
grep -qi 'tim-nish' "$SKILL" && err "leaks owner identity" || ok "no owner identity in scaffold"

# Synthetic tagged fixture repo: F1's entry gate requires a tagged release, and
# the host repo carries no tags — the check must never depend on host state.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fixture="$work/fixture"
mkdir -p "$fixture"
git -C "$fixture" -c init.defaultBranch=main init -q
printf '# fixture\n' > "$fixture/README.md"
git -C "$fixture" add README.md
git -C "$fixture" -c user.name=fixture -c user.email=f@x commit -qm init
git -C "$fixture" tag v0.1.0

# 2. Valid run: records framework + raw sources, proceeds to probe.
out=$(python3 "$DP" start F1 README.md 'src/**/*.py' HEAD~5..HEAD --root "$fixture")
echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["framework"] == "F1", d
assert d["framework_file"].endswith("F1-project-introduction.md"), d
assert d["next_stage"] == "probe", d
assert d["sources_raw"] == ["README.md", "src/**/*.py", "HEAD~5..HEAD"], d  # raw, unmodified
print("ok")' >/dev/null 2>&1 \
  && ok "valid run records framework + raw sources, next_stage=probe" || err "run-state record wrong"

# 3. Source-form disambiguation (all three forms, path vs range not confused).
forms=$(python3 "$DP" start F2 notes.md 'a/**' HEAD~3..HEAD ../sibling v1..v2 \
        | python3 -c 'import json,sys; print(" ".join(s["form"] for s in json.load(sys.stdin)["sources"]))')
[ "$forms" = "path glob commit-range path commit-range" ] \
  && ok "classifies path / glob / commit-range (../sibling stays a path)" \
  || err "source classification wrong: [$forms]"

# 4. Invalid framework: reports valid set, halts, NO run state (no side effects).
set +e
out=$(python3 "$DP" start F9 README.md 2>&1 1>/dev/null); rc=$?
sout=$(python3 "$DP" start F9 README.md 2>/dev/null); src=$?
set -e
[ "$rc" -ne 0 ] && ok "invalid framework exits non-zero" || err "invalid framework exited 0"
printf '%s' "$out" | grep -q '"introduce the project" (F1)' && printf '%s' "$out" | grep -q '(F4)' \
  && printf '%s' "$out" | grep -q '(F5)' \
  && ok "rejection reports the valid intent labels (with F1-F5 aliases)" || err "valid set not reported"
[ -z "$sout" ] && ok "invalid framework emits NO run state (no partial run)" || err "run state leaked on invalid framework"

# 5. Framework allowlist is closed + case-insensitive. F5 (working-note,
# story 13.89) is a member of the ratified set, not an invalid name (#835).
python3 "$DP" start f3 >/dev/null 2>&1 && ok "framework name is case-insensitive (f3)" || err "case-insensitive check failed"
python3 "$DP" start F5 >/dev/null 2>&1 && ok "F5 (working-note) is in the valid set" || err "F5 rejected"
for bad in F0 F6 project-introduction ''; do
  set +e; python3 "$DP" start "$bad" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -ne 0 ] || { err "accepted invalid framework: '$bad'"; }
done
ok "allowlist rejects F0/F6/slug/empty"

# 6. Scope reconciliation is documented (selection intersects declared scope; no
# widening). The text moved from the dispatcher SKILL.md to the stage-1
# companion in the dispatcher split; the check follows the text (#835).
# RE-POINTED FROM STAGE 1 TO EXAMINE (Story 20.154, #1224). These assert a
# property of the step that READS, and probe stopped reading: it is a
# configuration and permission check now, with no enumeration and no anchors.
# Left on stage 1 the assertions would have forced the retired vocabulary back
# into the file to keep a check green — the shape `check-readme.sh` was caught
# in at story 20.150, where an assertion pinned documentation to a capability
# that no longer existed. The invariant is unchanged; only its site moved.
READS="skills/draft-article/stages/examine.md"
grep -q 'intersect' "$READS" && ok "documents that reads intersect declared scope (no widening)" || err "scope-intersection not documented"
grep -q 'resolve-writing-sources.py files' "$READS" && ok "defers read scope to the declared files boundary" || err "does not defer to files boundary"

if [ "$fail" -eq 0 ]; then
  printf '\nAll draft-scaffold checks passed.\n'; exit 0
else
  printf '\ndraft-scaffold checks FAILED.\n' >&2; exit 1
fi
