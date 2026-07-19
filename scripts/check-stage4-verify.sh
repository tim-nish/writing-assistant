#!/usr/bin/env sh
# check-stage4-verify.sh — verify Stage 4 owner verification pass (Story 4.5):
# the `[VERIFY]` worklist + zero-marker exit, and the >1-rewrite reroute rule.
# POSIX shell + stdlib Python.

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

# 1. Skill documents the Stage-4 contract.
grep -q 'Stage 4 — owner verification pass' "$SKILL" && ok "documents Stage 4" || err "Stage 4 not documented"
grep -qi 'zero .*VERIFY.* markers remain' "$SKILL" && ok "states the zero-marker exit criterion" || err "exit criterion missing"
grep -qi '4 minute' "$SKILL" && ok "states the ≤4-minute owner budget" || err "owner budget missing"
grep -qi 'routes back to a question' "$SKILL" && ok "documents the >1-rewrite reroute rule" || err "reroute rule missing"
grep -q 'reroute --section' "$SKILL" && ok "wires in the reroute helper" || err "reroute helper not wired in"
grep -q 'draft-pipeline.py verify ' "$SKILL" && ok "wires in the verify worklist" || err "verify worklist not wired in"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# 2. Worklist: each well-formed marker becomes an entry with line + reason.
cat > "$work/draft.md" <<'EOF'
Intro line, sourced.
The retry storm doubled token spend [VERIFY: inferred from logs, no exact figure].
Middle line.
We chose JAX [VERIFY: rationale not in sources].
EOF
out=$(python3 "$DP" verify "$work/draft.md")
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["remaining"]==2, d
assert d["next_stage"]=="verify", d
lines=sorted(w["line"] for w in d["worklist"])
assert lines==[2,4], lines
assert d["worklist"][0]["reason"].startswith("inferred from logs"), d
' && ok "worklist has one entry per marker with line + reason" || err "worklist wrong"

# 2b. A word-wrapped marker (newline inside the brackets) still enters the
# worklist — verify-markers/provenance accept it as well-formed, so the
# worklist scan must see it too or it ships unresolved (F10).
cat > "$work/wrapped.md" <<'EOF'
Sourced intro.
The reader cost claim is an estimate [VERIFY: this next claim is
my inference, not a statement in the sources].
EOF
python3 "$DP" verify "$work/wrapped.md" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["remaining"]==1, d
assert d["worklist"][0]["line"]==2, d
assert "\n" not in d["worklist"][0]["reason"], d
' && ok "F10: a word-wrapped marker enters the worklist (line of its start, reason unwrapped)" \
  || err "wrapped marker dropped from worklist"

# 3. Zero markers -> pass complete, next_stage = variants (Stage 5).
printf 'Every claim here is sourced or confirmed.\n' > "$work/clean.md"
python3 "$DP" verify "$work/clean.md" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["remaining"]==0 and d["next_stage"]=="variants", d
' && ok "zero markers -> next_stage variants (pass complete)" || err "clean-draft exit wrong"

# 4. Zero-marker exit matches the Stage-3 count gate (drive to zero).
[ "$(python3 "$DP" verify-markers --count "$work/clean.md")" -eq 0 ] \
  && ok "verify-markers --count is the same zero-exit signal" || err "count gate disagreement"

# 5. A malformed marker blocks the pass.
printf 'A claim [VERIFY] with no reason.\n' > "$work/bad.md"
python3 "$DP" verify "$work/bad.md" >/dev/null 2>&1 \
  && err "malformed marker did not block the pass" || ok "malformed marker blocks the pass"

# 6. Reroute: first rewrite is allowed; a second routes to an interview question.
python3 "$DP" reroute --section S2 --rewrites 0 | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["decision"]=="edit" and d["remaining_edits"]==1, d
' && ok "first rewrite allowed (decision: edit)" || err "first-rewrite decision wrong"

python3 "$DP" reroute --section S2 --rewrites 1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["decision"]=="reroute", d
assert d["next_stage"]=="interview", d
assert d["question"]["from_reroute"] is True, d
assert "S2" in d["question"]["id"], d
' && ok "second rewrite reroutes into a bounded interview question" || err "reroute decision wrong"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-4 verification checks passed.\n'; exit 0
else
  printf '\nstage-4 verification checks FAILED.\n' >&2; exit 1
fi
