#!/usr/bin/env sh
# check-stage3-fill.sh — verify Stage 3 framework fill + the `[VERIFY]` marker
# contract (Story 4.4). POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Skill documents the fill contract.
grep -q 'render-frontmatter.py' "$SKILL" && ok "frontmatter from the config article schema (not hardcoded)" || err "frontmatter not config-bound"
grep -q 'Never an unmarked assertion' "$SKILL" && ok "states the never-unmarked-assertion invariant" || err "invariant not stated"
grep -q 'extended by inference' "$SKILL" && ok "partial-source-but-inferred still marked" || err "partial-inference rule missing"
grep -qi "don't summarize" "$SKILL" && ok "warns against summarizing into new claims" || err "summarize caution missing"
grep -q '\[VERIFY: <reason>\]' "$SKILL" && ok "documents the exact marker format" || err "marker format not documented"
grep -q 'verify-markers' "$SKILL" && ok "wires in the marker validator" || err "validator not wired in"

# --- marker contract (machine-detectable, exact) ---------------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# 2. Well-formed markers pass; the count is exact.
cat > "$work/good.md" <<'EOF'
The retry storm doubled token spend [VERIFY: inferred from logs, no exact figure].
We chose JAX [VERIFY: rationale not in sources].
Throughput rose 2x, per the fact sheet.
EOF
python3 "$DP" verify-markers "$work/good.md" >/dev/null 2>&1 && ok "well-formed [VERIFY: reason] markers pass" || err "well-formed markers rejected"
[ "$(python3 "$DP" verify-markers --count "$work/good.md")" -eq 2 ] && ok "--count reports the exact well-formed count (2)" || err "marker count wrong"

# 3. Each malformed shape is caught (exact, machine-detectable format).
for m in '[VERIFY]' '[verify: wrong case]' '[VERIFY no colon]' '[VERIFY: ]'; do
  printf 'A claim %s here.\n' "$m" > "$work/bad.md"
  python3 "$DP" verify-markers "$work/bad.md" >/dev/null 2>&1 \
    && err "malformed marker accepted: $m" || ok "malformed marker rejected: $m"
done

# 4. A VERIFY-like word is not a false positive.
printf 'We are [VERIFYING] the data now.\n' > "$work/word.md"
[ "$(python3 "$DP" verify-markers --count "$work/word.md")" -eq 0 ] \
  && ok "[VERIFYING] is not mistaken for a marker (word boundary)" || err "false-positive on VERIFYING"

# 5. Zero-marker (fully sourced) draft is valid and counts zero.
printf 'Every claim here is sourced.\n' > "$work/clean.md"
python3 "$DP" verify-markers "$work/clean.md" >/dev/null 2>&1 \
  && [ "$(python3 "$DP" verify-markers --count "$work/clean.md")" -eq 0 ] \
  && ok "a fully-sourced draft has zero markers and passes" || err "clean draft mishandled"

# 6. The count is the Stage-4 exit signal (drive markers to zero).
python3 "$DP" verify-markers --count "$work/good.md" | grep -qx 2 \
  && ok "--count is a Stage-4 exit signal (resolve until 0)" || err "count signal wrong"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-3 fill checks passed.\n'; exit 0
else
  printf '\nstage-3 fill checks FAILED.\n' >&2; exit 1
fi
