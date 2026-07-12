#!/usr/bin/env sh
# check-per-run-workspace.sh — verify the per-run workspace for all
# intermediates (Story 9.2). POSIX shell + stdlib Python only.
#
# Covers: new-run creates <state-root>/<repo-key>/runs/<run-id>/ and returns it
# (AC1); two runs get distinct workspaces and neither overwrites the other
# (AC4); there is no state-vs-cache split — everything lives under one
# runs/<id>/ workspace (AC3); run-workspace echoes an existing path without
# creating it; an explicit --run-id that already exists is rejected (uniqueness);
# and the harvest + draft-article prompts route intermediates through the
# resolver's workspace, never the host tree (AC2 contract surface).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RES="scripts/resolve-paths.py"
PY="python3 $root/$RES"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# Isolated fake state root + host repo so we never touch real state.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_STATE_HOME="$work/state"
HOST="$work/host-repo"; mkdir -p "$HOST"

R() { $PY "$@" --root "$HOST"; }

# 0. Compiles.
if python3 -c "import py_compile; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null; then
  ok "resolver compiles"
else
  err "resolver syntax error"; printf '\nChecks FAILED.\n' >&2; exit 1
fi

repo_dir=$(R repo-dir)

# 1. new-run creates <repo-dir>/runs/<run-id>/ and returns it (AC1).
ws1=$(R new-run)
if [ -d "$ws1" ]; then ok "new-run creates the workspace directory"; else err "new-run did not create $ws1"; fi
case "$ws1" in
  "$repo_dir/runs/"*) ok "workspace is under <repo-dir>/runs/<run-id>/" ;;
  *) err "workspace not under repo-dir/runs/ (got $ws1)" ;;
esac

# 2. Two runs are distinct and neither overwrites the other (AC4).
ws2=$(R new-run)
if [ "$ws1" != "$ws2" ] && [ -d "$ws1" ] && [ -d "$ws2" ]; then
  ok "two runs -> distinct workspaces, both present"
else
  err "second run collided or clobbered the first ($ws1 vs $ws2)"
fi

# 3. Writes into a workspace stay isolated to that run (no cross-run bleed).
echo one > "$ws1/fact-sheet.md"; echo two > "$ws2/fact-sheet.md"
if [ "$(cat "$ws1/fact-sheet.md")" = "one" ] && [ "$(cat "$ws2/fact-sheet.md")" = "two" ]; then
  ok "each run's intermediates are independent"
else
  err "run workspaces are not independent"
fi

# 4. No state-vs-cache split (AC3): the only child of repo-dir is runs/ — no
#    separate cache/state directories exist beside it.
children=$(ls -1 "$repo_dir")
if [ "$children" = "runs" ]; then
  ok "no state-vs-cache split (repo-dir holds only runs/)"
else
  err "unexpected siblings beside runs/ in repo-dir: $children"
fi

# 5. run-workspace echoes an existing path (no creation).
rid=$(basename "$ws1")
got=$(R run-workspace --run-id "$rid")
if [ "$got" = "$ws1" ]; then ok "run-workspace resolves an existing run id"; else err "run-workspace mismatch ($got vs $ws1)"; fi

# 6. An explicit --run-id that already exists is rejected (uniqueness).
set +e
out=$(R new-run --run-id "$rid" 2>&1); rc=$?
set -e
if [ "$rc" -ne 0 ]; then ok "explicit existing --run-id is rejected"; else err "new-run reused an existing run id"; fi

# 7. Prompt contract: harvest and draft-article route intermediates through the
#    resolver workspace (AC2 surface — the prompts must not default into the tree).
for f in skills/draft-article/SKILL.md skills/harvest/SKILL.md; do
  # The resolver workspace is reached via `new-run` directly, or via
  # `draft-pipeline.py autostart` / `stage0` (Stories 13.12/13.13), which
  # mint/resume one.
  if grep -qE 'resolve-paths.py new-run|draft-pipeline.py (autostart|stage0)' "$f" && grep -qi 'workspace' "$f"; then
    ok "prompt routes intermediates through the run workspace: $f"
  else
    err "prompt does not reference the resolver run workspace: $f"
  fi
done

if [ "$fail" -eq 0 ]; then
  printf '\nAll per-run-workspace checks passed.\n'; exit 0
else
  printf '\nper-run-workspace checks FAILED.\n' >&2; exit 1
fi
