#!/usr/bin/env sh
# parallel-safe
# tier: inner — greps over scripts/ and skills/ plus one small stdlib-python
#   read of the dispatch table; no network, no repo mutation.
# measured: 150ms (three runs, 2026-08-04: 150/160/150ms)
# ends: a shipped mechanism that no run can reach — BOTH conjuncts. §1-3 end
#   "call site absent"; §4 (#1367) ends "call site present, guard never true",
#   the half that let block mode ship dark with this check green. Neither is
#   generation-side preventable from one side: a call site and its skill
#   invocation are authored in different files, and a control surface and its
#   operating doc in different changes — which is why the ambient CLAUDE.md
#   clause carries the duty and this check carries only the visible-absence
#   signal over DECLARED surfaces.
# removal-signal: subcommands and control surfaces becoming derivable from a
#   single declared registry that the skills project rather than restate, at
#   which point a carrier cannot be missing and this check has no subject.
#   §4 alone retires if control surfaces stop being opt-in — a mode on by
#   default has no guard to be dark.
# covers: scripts/draft-pipeline.py scripts/run_block.py
# grep-binding: token — whole-skills-tree greps for subcommand invocation
#   strings, set-wide by construction.
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
#    the platform lint (Story 16.6) is invoked by the draft-article Stage-5 flow;
#    the arbitration-event emitter (Story 13.42) by review-article's arbitration.
grep -rq "lint-platform-variant" skills/ \
  && ok "lint-platform-variant: invocation site present in skills/" \
  || err "lint-platform-variant: ORPHAN — no skill invokes it"
grep -rq "emit-arbitration-events.py" skills/ \
  && ok "emit-arbitration-events.py: invocation site present in skills/" \
  || err "emit-arbitration-events.py: ORPHAN — no skill invokes it"

# 4. THE SECOND CONJUNCT (Story 20.214, #1367). Sections 1-3 assert a CALL SITE
#    exists. Reachability is call-site AND a guard that can be true, and the
#    second half is data-dependent and invisible to enumeration: block mode
#    shipped with its call sites present, this check green, and the mode dark on
#    every skill-driven run, because nothing told the agent to enable it. A
#    passing audit and a dark feature were the same observation.
#
#    THE SURFACE DECLARES ITSELF, so nothing here enumerates "control surface" —
#    that would be the enumeration problem one level up, and this repository has
#    four recorded instances of coverage being relative to its enumeration. An
#    UNDECLARED surface is the author's omission, which CLAUDE.md's ambient
#    clause binds; this section asserts over what is declared.
decls=$(grep -rn '^# control-surface:' scripts/ 2>/dev/null || true)
n_decl=$(printf '%s' "$decls" | grep -c . || true)
if [ "$n_decl" -eq 0 ]; then
  err "no '# control-surface:' declaration found anywhere in scripts/ — block mode (#1360) is the known instance and must carry one"
else
  printf '%s\n' "$decls" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    src=${line%%:*}
    doc=$(printf '%s' "$line" | sed -n 's/.*operating doc:[[:space:]]*\([^ ]*\).*/\1/p')
    name=$(printf '%s' "$line" | sed -n 's/.*# control-surface:[[:space:]]*\([^—]*\).*/\1/p' | sed 's/[[:space:]]*$//')
    if [ -z "$doc" ]; then
      printf 'FAIL: %s declares a control surface naming no operating doc — the declaration is the whole point (#1367)\n' "$src" >&2
      exit 1
    elif [ ! -f "$doc" ]; then
      printf 'FAIL: %s names operating doc %s, which does not exist\n' "$src" "$doc" >&2
      exit 1
    elif ! grep -qi "$name" "$doc"; then
      printf 'FAIL: %s names operating doc %s, which never mentions the surface %s — a declaration pointing at a silent doc is the defect, not evidence of compliance\n' "$src" "$doc" "$name" >&2
      exit 1
    else
      printf 'ok:   control surface %s: declared, operating doc %s exists and names it\n' "$name" "$doc"
    fi
  done || fail=1
  # THE SCOPE, NOT THE CLASS. This detector is after-the-fact by construction:
  # it sees declarations, never surfaces. A clean run says how many it examined
  # so the number is never read as "no dark features exist".
  ok "control-surface scope examined: $n_decl declaration(s) — this asserts nothing about UNDECLARED surfaces, which the CLAUDE.md clause covers"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll subcommand-carrier checks passed.\n'; exit 0
else
  printf '\nsubcommand-carrier checks FAILED.\n' >&2; exit 1
fi
