#!/usr/bin/env sh
# check-footprint-invariant.sh — verify the host-repo footprint invariant is
# enforced end-to-end (Story 9.3). POSIX shell + stdlib Python only.
#
# The invariant (docs/storage-architecture.md D1): the plugin never writes
# state or intermediate artifacts into a host repo's working tree — the only
# files it creates there are declared products at output.drafts.
#
# Covers:
#  - AC1/AC2 (mechanical): against a clean host git repo, the resolver's run
#    workspace lands OUTSIDE the tree, and creating it + writing intermediates
#    leaves `git status` in the host repo empty — no scratch, no stray file.
#  - AC1 (contract): all three run-producing skills (harvest, draft-article,
#    review-article) declare the footprint invariant and route intermediates
#    through the resolver workspace, never the host tree.
#  - AC3: the writing-sources.yaml in-repo contract is left unchanged (O1 out
#    of scope) — still host-root, still resolved from the host root, no
#    state-root migration.

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

# --- Isolated fake state root + clean host git repo -----------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_STATE_HOME="$work/state"
HOST="$work/host-repo"; mkdir -p "$HOST"
git -C "$HOST" init -q
git -C "$HOST" config user.email t@e.st
git -C "$HOST" config user.name test
: > "$HOST/README.md"
git -C "$HOST" add -A && git -C "$HOST" commit -qm init

clean() { [ -z "$(git -C "$HOST" status --porcelain)" ]; }

clean && ok "host repo starts clean" || err "host repo not clean at start"

# 1. The run workspace lands OUTSIDE the host tree (AC1/AC2 mechanical).
ws=$(cd "$HOST" && $PY new-run --root "$HOST")
case "$ws" in
  "$HOST"/*) err "run workspace is INSIDE the host tree ($ws)" ;;
  *) ok "run workspace is outside the host tree" ;;
esac
case "$ws" in
  "$XDG_STATE_HOME"/*) ok "run workspace is under the state root" ;;
  *) err "run workspace not under the state root ($ws)" ;;
esac

# 2. Creating the workspace left the host tree clean (AC2: git status empty).
clean && ok "host git status clean after new-run" || {
  err "new-run dirtied the host tree:"; git -C "$HOST" status --porcelain >&2;
}

# 3. Writing intermediates into the workspace still leaves the host tree clean.
printf '# fact sheet\n' > "$ws/fact-sheet.md"
printf 'scratch\n'     > "$ws/scratch.txt"
clean && ok "host tree clean after intermediates written to the workspace" || {
  err "intermediates leaked into the host tree:"; git -C "$HOST" status --porcelain >&2;
}

# 4. Contract: each run-producing skill declares the footprint invariant and
#    routes intermediates through the resolver workspace (AC1 surface).
for f in skills/harvest/SKILL.md skills/draft-article/SKILL.md skills/review-article/SKILL.md; do
  if grep -q 'resolve-paths.py' "$f" \
     && grep -qiE 'output\.drafts|host (working )?tree|host repo' "$f" \
     && grep -qi 'workspace' "$f"; then
    ok "footprint contract stated in $f"
  else
    err "footprint contract missing/incomplete in $f"
  fi
done

# 5. AC3: writing-sources.yaml in-repo contract unchanged.
#    5a. plugin-layout still documents the host-root writing-sources.yaml.
if grep -q '<host-repo>/writing-sources.yaml' specs/spec-writing-assistant/plugin-layout.md; then
  ok "plugin-layout still documents host-root writing-sources.yaml"
else
  err "host-root writing-sources.yaml contract changed in plugin-layout.md"
fi
#    5b. storage-architecture O1 leaves it open with the current contract standing.
if grep -qi 'current contract stands' docs/storage-architecture.md; then
  ok "storage-architecture O1 keeps writing-sources.yaml contract standing"
else
  err "storage-architecture O1 note for writing-sources.yaml is missing"
fi
#    5c. the resolver did NOT take over writing-sources placement (still host-root).
if grep -q 'writing-sources' scripts/resolve-paths.py; then
  err "resolve-paths.py unexpectedly handles writing-sources placement (O1 is out of scope)"
else
  ok "resolver leaves writing-sources placement alone (O1 out of scope)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll footprint-invariant checks passed.\n'; exit 0
else
  printf '\nfootprint-invariant checks FAILED.\n' >&2; exit 1
fi
