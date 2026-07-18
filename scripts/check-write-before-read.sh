#!/usr/bin/env sh
# check-write-before-read.sh — verify the artifact-write precondition (Story
# 13.78). POSIX shell only.
#
# Covers: the draft-article SKILL declares the pipeline-wide read-before-write
# invariant (including the resume case); each repeat-write site carries its
# anchor (Stage 3 revision loop, visual modify); the harvest fact-sheet write
# site carries the read-first comment; the script-side exemption is stated so
# the precondition is not misapplied to pipeline-script writes.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DRAFT="skills/draft-article/SKILL.md"
HARVEST="skills/harvest/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

has() { grep -q "$2" "$1"; }

# The global invariant exists and names the exact harness error.
has "$DRAFT" 'Artifact-write precondition' \
  && ok "draft SKILL declares the artifact-write precondition" \
  || err "draft SKILL missing the artifact-write precondition section"
has "$DRAFT" 'not been read yet' \
  && ok "precondition names the harness error string" \
  || err "precondition does not name 'File has not been read yet'"

# The resume case: existing artifacts are unread in a fresh session.
has "$DRAFT" 'existing workspace artifact as unread' \
  && ok "resume case covered (existing artifacts are unread)" \
  || err "resume case not covered by the precondition"

# Script-side writes are exempt — the precondition is a Write-tool rule.
has "$DRAFT" 'are exempt' \
  && ok "script-side exemption stated" \
  || err "script-side exemption missing (precondition would be misapplied)"

# Per-site anchors at the repeat-write loops.
has "$DRAFT" 'current draft and provenance map before re-writing' \
  && ok "Stage 3 revision loop anchors the precondition" \
  || err "Stage 3 revision loop missing its read-before-rewrite anchor"
has "$DRAFT" 're-writes the same workspace' \
  && ok "visual modify anchors the precondition" \
  || err "visual modify choice missing its read-first anchor"

# Harvest fact-sheet write site.
has "$HARVEST" 'Read it' \
  && ok "harvest fact-sheet write site carries the read-first comment" \
  || err "harvest fact-sheet write site missing the read-first comment"

if [ "$fail" -ne 0 ]; then printf '\nFAILED.\n' >&2; exit 1; fi
printf '\nAll write-before-read checks passed.\n'
