#!/usr/bin/env sh
# check-publication-boundary.sh — reject private provenance markers under
# specs/ (owner decision 2026-07-16). This repo is public; the ratified
# publication boundary is "mechanism public, provenance private": specs may
# state that a decision was ratified (date + title), but never the address,
# layout, or internal names of the owner's private knowledge hub.
#
# Rejected markers: the private hub's name, its q_a/ archive layout, absolute
# home-relative paths (~/work), and lesson-slug file references.
# POSIX shell + grep only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

# One alternation per marker class. Kept in the script (not a config file):
# the marker set IS the policy, and it must not be repo-locally overridable.
PATTERN='product-lab|q_a/|~/work|lessons/[a-z0-9-]*\.md'

# .memlog.md files are BMAD process artifacts, not published contract text,
# and are gitignored — never tracked, so never in the published tree. They are
# excluded here so process scratch does not gate the contract lint.
violations=$(grep -rnE "$PATTERN" specs/ --include='*.md' \
  | grep -v '/\.memlog\.md:' || true)

if [ -n "$violations" ]; then
  printf 'FAIL: private provenance markers under specs/ (publication boundary):\n' >&2
  printf '%s\n' "$violations" >&2
  count=$(printf '%s\n' "$violations" | wc -l | tr -d ' ')
  printf '%s violation(s). Replace with a generic decision line — e.g.\n' "$count" >&2
  printf '"owner decision record — YYYY-MM-DD (title)" — and keep hub paths private.\n' >&2
  exit 1
fi

printf 'OK: no private provenance markers under specs/\n'
