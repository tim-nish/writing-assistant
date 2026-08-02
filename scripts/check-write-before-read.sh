#!/usr/bin/env sh
# parallel-safe
# covers: skills/draft-article/SKILL.md skills/draft-article/stages/complete.md skills/draft-article/stages/gate.md skills/draft-article/stages/stage0.md skills/draft-article/stages/stage1.md skills/draft-article/stages/stage2.md skills/draft-article/stages/stage3.md skills/draft-article/stages/stage4.md
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
__DA_ALL="${TMPDIR:-/tmp}/da-skill-all.$$.md"
cat skills/draft-article/SKILL.md skills/draft-article/stages/stage0.md skills/draft-article/stages/stage1.md skills/draft-article/stages/stage2.md skills/draft-article/stages/stage3.md skills/draft-article/stages/gate.md skills/draft-article/stages/stage4.md skills/draft-article/stages/complete.md > "$__DA_ALL"


DRAFT="$__DA_ALL"
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

# (The harvest fact-sheet write-site assertion retired with the skill —
# #1182/Story 20.147.)

if [ "$fail" -ne 0 ]; then printf '\nFAILED.\n' >&2; exit 1; fi
printf '\nAll write-before-read checks passed.\n'
