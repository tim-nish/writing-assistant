#!/usr/bin/env sh
# parallel-safe
# check-readme.sh — verify the README install/usage guide (Story 6.3): documents
# the marketplace-add/install flow, user-config.yaml and writing-sources.yaml
# setup, the output.drafts behavior (no default), and the local-skill development
# mode. POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

README="README.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$README" ] && ok "README.md exists" || { err "README.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

has() { grep -qi "$1" "$README" && ok "$2" || err "$2 — missing"; }

# Install / marketplace flow.
has '/plugin marketplace add'              "documents /plugin marketplace add"
has '/plugin install'                      "documents /plugin install"
has 'writing-assistant@'                   "shows the plugin@marketplace install target"

# Config setup: both files.
has 'user-config'                          "documents user-config.yaml setup"
has 'writing-sources'                      "documents writing-sources.yaml setup"
has '~/.config/writing-assistant'          "documents the machine-global config path"

# output.drafts behavior (no fixed default).
has 'output.drafts'                        "documents output.drafts"
grep -qiE 'no default|no fixed|asks once|write.*back' "$README" \
  && ok "documents the no-default / ask-once output.drafts behavior" \
  || err "output.drafts no-default behavior not documented"

# Usage: the invocable skills.
# `harvest` WAS asserted here and is REMOVED with the stage (Story 20.150,
# #1223). The assertion required the README to document an invocation that no
# longer exists — skills/harvest/ held only a .gitkeep — so this check was
# actively holding the stale documentation in place: story 20.150 could not
# correct the README without turning this check red. A check that pins
# documentation to a retired capability is not a safety net, it is the defect
# with a green light, and it fails in the direction nobody looks.
has 'draft article'                        "documents the draft-article invocation"
has 'review article'                       "documents the review-article invocation"

# Development mode retained.
grep -qi 'development mode' "$README" && ok "documents local-skill development mode" \
  || err "development mode section missing"
has 'plugin-dir'                           "documents --plugin-dir dev mode"

if [ "$fail" -eq 0 ]; then
  printf '\nAll README checks passed.\n'; exit 0
else
  printf '\nREADME checks FAILED.\n' >&2; exit 1
fi
