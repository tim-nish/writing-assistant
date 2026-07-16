#!/usr/bin/env sh
# check-subcommand-carriers.sh — every shipped pipeline subcommand has a CARRIER:
# at least one invocation site under skills/ (Story 13.41). Guards the
# "mechanism built, orchestration missing" class: three Epic 16 subcommands
# passed their own checks while nothing invoked them, which a suite that tests
# scripts in isolation is structurally blind to. An orphan subcommand fails red.
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# Subcommands whose carrier is COMPOSITION, not direct invocation: stage0
# composes them ("the underlying validate-config, start, and autostart commands
# still exist for standalone use; stage0 composes them" — draft-article SKILL).
# Adding a name here requires naming its composing carrier in the comment.
COMPOSED="start autostart"

# 1. Derive the shipped subcommand list from the dispatch table itself (never a
#    hand-kept copy that can drift).
subs=$(python3 - <<'PY'
import re
src = open("scripts/draft-pipeline.py", encoding="utf-8").read()
print("\n".join(sorted(set(re.findall(r'sub\.add_parser\("([a-z0-9-]+)"', src)))))
PY
)
[ -n "$subs" ] && ok "subcommand list derived from the dispatch table ($(printf '%s\n' "$subs" | wc -l | tr -d ' ') subcommands)" \
  || { err "could not derive subcommands"; printf '\nFAILED.\n' >&2; exit 1; }

# 2. Every subcommand has >=1 invocation site under skills/ ("draft-pipeline.py
#    <sub>" in a skill body — command blocks, not the reference table, which
#    lists flags without the script path).
for sub in $subs; do
  case " $COMPOSED " in *" $sub "*)
    ok "$sub: composed via stage0 (allowlisted carrier)"; continue;;
  esac
  if grep -rq "draft-pipeline.py $sub" skills/; then
    ok "$sub: invocation site present in skills/"
  else
    err "$sub: ORPHAN — no skill invokes it (mechanism without orchestration)"
  fi
done

# 3. Standalone shipped scripts that skills must carry too (same failure class):
#    the platform lint (Story 16.6) is invoked by the draft-article Stage-5 flow.
grep -rq "lint-platform-variant" skills/ \
  && ok "lint-platform-variant: invocation site present in skills/" \
  || err "lint-platform-variant: ORPHAN — no skill invokes it"

if [ "$fail" -eq 0 ]; then
  printf '\nAll subcommand-carrier checks passed.\n'; exit 0
else
  printf '\nsubcommand-carrier checks FAILED.\n' >&2; exit 1
fi
