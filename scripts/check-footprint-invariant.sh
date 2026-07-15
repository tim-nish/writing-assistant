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
#  - AC3 (as amended by #211/13.23): writing-sources.yaml is machine-global —
#    resolve-paths.py owns its placement, no script composes the per-repo
#    config path itself, and no doc points owners at the host root.

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

# 5. AC3 (amended by Story 13.23, #211 — storage O1 resolved): writing-sources.yaml
#    is machine-global per-repo config, and the RESOLVER owns its placement.
#    5a. plugin-layout documents the machine-global location, not a host-root file.
if grep -q 'repos/<repo-key>/' specs/spec-writing-assistant/plugin-layout.md \
   && ! grep -q '<host-repo>/writing-sources.yaml' specs/spec-writing-assistant/plugin-layout.md; then
  ok "plugin-layout documents machine-global writing-sources.yaml (no host-root contract)"
else
  err "plugin-layout does not document the machine-global writing-sources.yaml contract (#211)"
fi
#    5b. storage-architecture records O1 as resolved.
if grep -q 'Resolved 2026-07-15 (#211)' docs/storage-architecture.md; then
  ok "storage-architecture records the O1 resolution"
else
  err "storage-architecture O1 resolution record is missing (#211)"
fi
#    5c. the resolver is the single owner of writing-sources placement.
if grep -q 'def sources_file' scripts/resolve-paths.py; then
  ok "resolver owns writing-sources.yaml placement (sources_file)"
else
  err "resolve-paths.py does not own writing-sources placement (#211 expects sources_file)"
fi
#    5d. Story 13.25: no production script composes the per-repo config-root
#        layout itself — the `repos/<repo-key>` segment under the config home is
#        resolve-paths.py's alone. (Docs/skills may NAME the location for
#        humans; composing it in code is the violation. check-*.sh fixtures
#        assert resolver behavior and are excluded.)
offenders=$(grep -RnoI 'writing-assistant/repos\|"repos"' scripts/*.py 2>/dev/null \
  | grep -v '^scripts/resolve-paths.py:' || true)
if [ -z "$offenders" ]; then
  ok "single-source: no script outside resolve-paths.py composes the per-repo config path"
else
  err "per-repo config path composed outside the resolver:"
  printf '%s\n' "$offenders" >&2
fi
#    5e. Issue #218: README never claims writing-sources.yaml lives in the host
#        repo. The 13.25 text sweep caught the skills but missed README's
#        at-a-glance config table ("Lives at | host repo root"), which led a
#        reader to commit the config into a host repo the same day. Guard the
#        stale claim pattern; the legacy-migration note ("A legacy in-repo
#        writing-sources.yaml is still read…") is allowed — it names the old
#        location as deprecated, not as the place to put the file.
stale=$(grep -n 'host repo root\|host-repo root' README.md || true)
if [ -z "$stale" ]; then
  ok "README makes no host-repo-root placement claim for writing-sources.yaml (#218)"
else
  err "README still claims a host-repo-root location (#218):"
  printf '%s\n' "$stale" >&2
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll footprint-invariant checks passed.\n'; exit 0
else
  printf '\nfootprint-invariant checks FAILED.\n' >&2; exit 1
fi
