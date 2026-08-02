#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-07-31 (#999) — the 2026-07-30 observation stands (it
# does create a directory under the REAL state root), but re-measuring showed
# that directory is KEYED ON ITS OWN `mktemp -d` host path — observed
# `~/.local/state/writing-assistant/-tmp-tmp-<random>-host/` — so two
# concurrent runs can never name the same path, and no check declared
# parallel-safe reads the real state root at all (grepped: every state-root
# consumer in the suite sets XDG_STATE_HOME). The residue is a HYGIENE defect,
# not a concurrency one, and the undeclared default is not the tool for it.
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# covers: scripts/draft-pipeline.py skills/draft-article/stages/stage0.md
# check-named-element-pin.sh — verify CAP-9 named-element pin (#431): a
# `--element <name>` directive at stage 0 records the pin in run state, pinning
# selection to one story element and scoping harvest to it without widening the
# declared-source boundary (Story 18.10, depends 18.8). POSIX shell + stdlib.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
SKILL="skills/draft-article/stages/stage0.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "draft-pipeline compiles" || { err "draft-pipeline syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
printf 'sources:\n  - path: .\n' > "$host/writing-sources.yaml"

# element name from a run_state JSON on stdin (or "NONE" when the key is absent).
elem() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('run_state',d).get('element',{}).get('name','NONE'))"; }

# --- 1. --element records the pin in run state (stage0 caller) -------------------
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" --element "retry-storm")
[ "$(printf '%s' "$out" | elem)" = "retry-storm" ] \
  && ok "stage0 --element records the named pin in run_state.element.name" \
  || err "stage0 did not record the element pin: $out"

# --- 2. no --element -> no element key (default behavior unchanged) --------------
out=$(python3 "$DP" stage0 F2 specs/ --root "$host")
[ "$(printf '%s' "$out" | elem)" = "NONE" ] \
  && ok "no --element: run_state carries no element pin (default unchanged)" \
  || err "element key present without --element: $out"

# --- 3. the other entry point (start) records it too ----------------------------
out=$(python3 "$DP" start F2 specs/ --root "$host" --element "cache-warmth" 2>/dev/null)
[ "$(printf '%s' "$out" | elem)" = "cache-warmth" ] \
  && ok "start --element records the pin (both stage-0 entry points thread it)" \
  || err "start did not record the element pin: $out"

# --- 4. the flag exists on both subparsers (discoverable) -----------------------
python3 "$DP" start --help 2>&1 | grep -q -- '--element' \
  && ok "start exposes --element" || err "start missing --element flag"
python3 "$DP" stage0 --help 2>&1 | grep -q -- '--element' \
  && ok "stage0 exposes --element" || err "stage0 missing --element flag"

# --- 5. SKILL states the pin contract -------------------------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qi 'resolves to an element id' \
  && ok "SKILL: the name resolves to an element id (18.8)" \
  || err "SKILL missing name->id resolution"
printf '%s' "$S" | grep -qi 'selection is pinned' \
  && ok "SKILL: selection is pinned to the named element" \
  || err "SKILL missing the pinned-selection rule"
printf '%s' "$S" | grep -qi 'examine grounds claims for that element alone' \
  && ok "SKILL: examine grounds that element alone (#1182)" \
  || err "SKILL missing the element-scoped grounding rule"
printf '%s' "$S" | grep -qi 'does not widen the declared-source boundary' \
  && ok "SKILL: the pin does NOT widen the declared-source boundary" \
  || err "SKILL missing the no-widen invariant (the load-bearing constraint)"
printf '%s' "$S" | grep -qi 'interview covers that element' \
  && ok "SKILL: the interview covers the pinned element's gaps" \
  || err "SKILL missing the interview-scoping rule"

if [ "$fail" -eq 0 ]; then
  printf '\nAll named-element-pin checks passed.\n'; exit 0
else
  printf '\nnamed-element-pin checks FAILED.\n' >&2; exit 1
fi
