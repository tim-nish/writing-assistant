#!/usr/bin/env sh
# check-provenance-pin.sh — the two-tier grounding pin (Story 18.120, #731).
# POSIX shell + stdlib Python.
#
# Covers: CLAUDE.md no longer mandates the leaking form and states the two-tier
# rule (AC1); the store resolves through the path resolver and carries no path
# literal elsewhere (AC2); a decision line resolves to its pin, and a miss is a
# miss (AC3); a public line with no store entry is reported unverified (AC4);
# a compliant pin passes check-publication-boundary and the old form fails it
# (AC5).
#
# The load-bearing assertion is AC5: the two rules must agree BY CONSTRUCTION.
# If a compliant pin could still fail the boundary check, the fix would have
# moved the contradiction rather than resolved it.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

PP="$root/scripts/provenance-pin.py"
BOUNDARY="$root/scripts/check-publication-boundary.sh"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$PP', doraise=True)" 2>/dev/null \
  && ok "provenance-pin compiles" \
  || { err "provenance-pin syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# --- AC1: CLAUDE.md states the two-tier rule and drops the leaking mandate. ---
# Deliberately checks the INSTRUCTION, not mere absence of the string: the file
# necessarily discusses the leaking form in order to forbid it.
grep -q 'the pin is' CLAUDE.md && grep -qi 'two-tier' CLAUDE.md \
  && ok "CLAUDE.md states the two-tier pin rule" \
  || err "CLAUDE.md does not state the two-tier pin rule"
grep -q 'owner decision record — YYYY-MM-DD' CLAUDE.md \
  && ok "CLAUDE.md gives the public half's form" \
  || err "CLAUDE.md does not show the public decision-line form"
grep -q 'provenance-pin.py record' CLAUDE.md \
  && ok "CLAUDE.md names how to record the private half" \
  || err "CLAUDE.md does not name the recording command"
grep -qi 'private record wins' CLAUDE.md \
  && ok "CLAUDE.md states precedence" || err "CLAUDE.md omits the precedence rule"
# The old mandate must no longer read as an instruction.
grep -qE '^\s*`consulted: [a-z-]+@<sha>' CLAUDE.md \
  && err "CLAUDE.md still mandates the full pin at the point of use" \
  || ok "CLAUDE.md no longer mandates the leaking form"

# --- AC2: the store resolves through the path resolver, nowhere else. --------
grep -q 'RESOLVE_PATHS' "$PP" && grep -q '"config-home"' "$PP" \
  && ok "the store resolves through resolve-paths (single seam)" \
  || err "the store path is not resolved through resolve-paths"
strays=$(grep -rlF --exclude-dir=__pycache__ --exclude='*.pyc' \
           'provenance/decisions.json' scripts/ skills/ specs/ 2>/dev/null \
         | grep -v 'scripts/provenance-pin.py' | grep -v 'scripts/check-provenance-pin.sh' || true)
[ -z "$strays" ] \
  && ok "no second site composes the store path" \
  || err "store path literal also appears in: $strays"

# --- AC3 / AC4: record -> resolve -> check, against an isolated store. -------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_CONFIG_HOME="$work/cfg"; export XDG_CONFIG_HOME

LINE='owner decision record — 2026-01-02 (fixture decision)'
python3 "$PP" record --decision "$LINE" --pin 'fixture-hub@abc1234' \
  --cites 'topics/x.md:1' >/dev/null 2>&1 \
  && ok "a decision line records" || err "record failed"

python3 "$PP" resolve --decision "$LINE" 2>/dev/null | grep -q 'fixture-hub@abc1234' \
  && ok "a recorded decision resolves to its pin" || err "resolve did not return the pin"

# Punctuation is noise: the same decision written differently must resolve.
python3 "$PP" resolve --decision 'owner decision record 2026-01-02 (Fixture Decision)' \
  >/dev/null 2>&1 \
  && ok "punctuation and case variants resolve to the same decision" \
  || err "a punctuation variant failed to resolve (would manufacture false unverified findings)"

# A miss is a miss — never an empty-looking success.
if python3 "$PP" resolve --decision 'owner decision record — 2030-12-31 (absent)' \
     >/dev/null 2>&1; then
  err "an unrecorded decision resolved successfully (absence rendered as a hit)"
else
  ok "an unrecorded decision reports a miss, not an empty success"
fi

# AC4 — a public line with no store entry is reported unverified.
mkdir -p "$work/tree/specs"
printf 'Grounded in the owner decision record — 2026-01-02 (fixture decision).\n' \
  > "$work/tree/specs/known.md"
printf 'Grounded in the owner decision record — 2030-12-31 (absent decision).\n' \
  > "$work/tree/specs/unknown.md"
out=$(cd "$work/tree" && python3 "$PP" check specs 2>&1 || true)
printf '%s' "$out" | grep -q 'unverified: 1 of 2' \
  && ok "an unrecorded public line is reported unverified; a recorded one is not" \
  || err "check miscounted unverified lines: $out"
printf '%s' "$out" | grep -q 'unknown.md' \
  && ok "the unverified finding names its site" || err "check did not name the offending file"

# The tolerant grammar is load-bearing: a matcher that finds nothing reports a
# confident, useless ok. Guard the false zero.
printf 'per the owner decision record 2026-01-02 (fixture decision)\n' \
  > "$work/tree/specs/variant.md"
out2=$(cd "$work/tree" && python3 "$PP" check specs 2>&1 || true)
printf '%s' "$out2" | grep -qE 'of 3 public decision line' \
  && ok "all punctuation variants are matched (no false zero)" \
  || err "a real decision-line variant went unmatched: $out2"

# --- AC5: the two rules agree by construction. -------------------------------
# A compliant pin must pass the boundary check; the old form must fail it. Run
# the boundary check's own patterns over each shape rather than reimplementing.
compliant='Grounded in the owner decision record — 2026-01-02 (fixture decision).'
# The negative fixture uses a DECLARED SYNTHETIC hub name and pin — never a real
# one. A test that proves the leak detector works must not itself be the leak;
# the boundary check applies the same discipline to its own self-tests.
leaking='Grounded in `consulted: fixture-hub@8f3c2d1a8f3c2d1a8f3c2d1a8f3c2d1a8f3c2d1a q_a/x.md:1`.'
PATTERN=$(grep -m1 "^PATTERN=" "$BOUNDARY" | sed "s/^PATTERN='//; s/'$//")
printf '%s\n' "$compliant" | grep -qE "$PATTERN" \
  && err "the compliant form trips the boundary pattern (the fix moved the contradiction)" \
  || ok "the compliant public half passes the boundary pattern"
printf '%s\n' "$leaking" | grep -qE "$PATTERN" \
  && ok "the old full-pin form still fails the boundary pattern" \
  || err "the boundary pattern no longer catches the old form"

[ "$fail" -eq 0 ] && printf '\nPASSED.\n' || { printf '\nFAILED.\n' >&2; exit 1; }
