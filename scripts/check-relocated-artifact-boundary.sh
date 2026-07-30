#!/bin/sh
# serial-reason: it mutates THIS REPOSITORY'S GIT INDEX (`git add -f`, then
#   `git reset`) as its negative test — a shared resource behind index.lock,
#   not a temp dir. Re-verified 2026-07-31 (#999): check-skeleton,
#   check-dev-harness and check-release-strip all read that index with `git
#   ls-files` and ARE declared parallel-safe, so a concurrent run could both
#   see the force-added path and contend on the lock. 119ms; there is nothing
#   to buy here and a real race to avoid.
# NOT parallel-safe (#957/#964) — deliberately carries no `# parallel-safe`
# header, so run-checks.sh -P leaves it in the serial remainder.
# A relocated Terrain artifact cannot reach a commit (Story 20.33, #874).
#
# Story 20.32 moved this tool's outputs and debug artifacts INTO this
# repository, because that is where the owner works. This repository is
# public, and a run's `map.json` carries verbatim hub renderings and a real
# hub commit sha — values the publication boundary forbids in tracked text
# (`CLAUDE.md` §"Claims about the served surface"). Outside a repo those
# artifacts were safe by construction; inside one they are one `git add -A`
# away from a boundary breach.
#
# So the relocation binds together with two carriers, and this check is the
# second: the ignore entry is CONVENIENCE, this is the BOUNDARY. An ignored
# file can still be force-added, and `git add -A` in a tree whose ignore rule
# was edited away would sweep the whole directory in.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# The directory the resolver owns. Read from the resolver, never hard-coded:
# D1 makes the resolver the contract and the scheme an implementation detail,
# so a check with its own literal would pass while the real path drifted.
troot=$(python3 "$root/scripts/resolve-paths.py" terrain-output-root)
case "$troot" in
  "$root"/*) rel=$(printf '%s' "${troot#"$root"/}") ;;
  *)
    # Not inside this repo (an installed clone falls back to the state root):
    # there is nothing here that could be committed, and the check says so
    # rather than inventing a target.
    ok "the terrain output root is outside this repository ($troot) — nothing here can be committed"
    printf '\nAll relocated-artifact boundary checks passed.\n'
    exit 0
    ;;
esac

# --- 1. The ignore entry ships -----------------------------------------------
# Committed, not personal: it travels with the plugin so a fresh clone stays
# clean. `.git/info/exclude` would be the right carrier for a user preference
# and the wrong one for the tool's own output.
if git check-ignore -q "$rel/probe" 2>/dev/null; then
  ok "the terrain output root is ignored"
else
  err "the terrain output root ($rel) is not ignored — a run leaves the tree dirty"
fi
if git ls-files --error-unmatch .gitignore >/dev/null 2>&1 \
   && grep -q "$rel" .gitignore; then
  ok "the ignore entry is COMMITTED (ships with the plugin, not a personal pattern)"
else
  err "the ignore entry is not in the tracked .gitignore — a fresh clone goes dirty"
fi

# --- 2. Nothing under it is tracked ------------------------------------------
tracked=$(git ls-files -- "$rel" | head -5)
if [ -z "$tracked" ]; then
  ok "no terrain artifact is tracked"
else
  err "terrain artifacts are TRACKED and can be published: $tracked"
fi

# --- 3. A STAGED terrain artifact FAILS, and the failure names it ------------
# This is the boundary. Not a warning: a staged artifact is one `git commit`
# from publishing hub renderings out of a public repository.
staged_now=$(git diff --cached --name-only -- "$rel" 2>/dev/null | head -5)
if [ -n "$staged_now" ]; then
  err "a terrain artifact is STAGED and would be published: $staged_now"
else
  ok "no terrain artifact is staged"
fi

# Negative test: the detection above must actually fire. Force-add a probe
# carrying the real SHAPE with a synthetic sha (a real one here would be
# the very violation this check exists to prevent),
# confirm it is seen, then restore the index. Not satisfied by the ignore
# rule — force-add is precisely how an ignored file reaches the index.
probe="$troot/boundary-probe/map.json"
mkdir -p "$(dirname "$probe")"
printf '{"coverage":{"hub_pin":"0123456789abcdef0123456789abcdef01234567"}}\n' > "$probe"
git add -f -- "$probe" >/dev/null 2>&1 || true
seen=$(git diff --cached --name-only -- "$rel" 2>/dev/null | head -5)
git reset -q -- "$rel" >/dev/null 2>&1 || true
rm -rf "$troot/boundary-probe"
if [ -n "$seen" ]; then
  ok "negative test: a force-added artifact IS detected and named ($seen)"
else
  err "negative test: a force-added artifact went undetected — the boundary has no carrier"
fi

# --- 4. The guard is not satisfied by the ignore rule alone ------------------
# Stated as an assertion about this script so the pairing cannot be dropped by
# someone who reads the ignore entry as sufficient.
if grep -q 'add -f' "$0"; then
  ok "the guard exercises the force-add path, not just the ignore rule"
else
  err "this check never force-adds — it would pass on ignore alone, which is not the boundary"
fi

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll relocated-artifact boundary checks passed.\n'
