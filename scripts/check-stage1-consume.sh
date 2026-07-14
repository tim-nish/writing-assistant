#!/usr/bin/env sh
# check-stage1-consume.sh — verify Stage 1 consumes the harvest output into
# pipeline state (Story 4.2). POSIX shell + stdlib Python.

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

# 1. Skill documents the stage-1 consume behavior.
grep -q 'draft-pipeline.py consume' "$SKILL" && ok "skill wires in the consume step" || err "consume not wired in"
grep -q 'without re-reading any source' "$SKILL" && ok "skill states no source re-read" || err "no-re-read not stated"
grep -q 'verbatim' "$SKILL" && ok "skill requires verbatim source pointers" || err "verbatim rule not stated"
grep -qi 'NEEDS-OWNER' "$SKILL" && ok "skill carries the NEEDS-OWNER list forward" || err "NEEDS-OWNER not threaded"

# 1b. Validator convergence (Story 13.22, #206): stage 1 states the bounded
#     repair behavior as its own contract, not just harvest's.
grep -q -- '--emit-entry' "$SKILL" && ok "stage 1 names the emitter as the construction path" \
  || err "emit-entry not referenced in stage 1"
grep -q 'bounded at two validator passes' "$SKILL" && ok "stage 1 states the two-pass repair bound" \
  || err "two-pass bound not stated in stage 1"
grep -q 'budget-triage signal' "$SKILL" && ok "stage 1 reuses the per-stage budget-triage signal on breach" \
  || err "budget-triage on breach not stated in stage 1"
grep -qi 'never instructs.*free-hand\|free-hand entry writing' "$SKILL" \
  && ok "stage 1 forbids free-hand entry writing + validate-loop repair" \
  || err "free-hand validate-loop prohibition not stated"
grep -q 'informational notes' "$SKILL" && ok "rerouted entries land in the completion summary" \
  || err "completion-summary surfacing of rerouted entries not stated"

# --- fixture: a harvest output document (fact sheet + NEEDS-OWNER) ----------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat > "$work/harvest.md" <<'EOF'
# Fact sheet: demo

- Throughput rose 2x / bench/results.md:42@a1b2c3d / result
- Chose JAX / a1b2c3d / decision
- Prior art / https://example.com/x / event

# NEEDS-OWNER

- The win surprised us / no artifact in declared sources / surprise
- Reviewers ask about leakage / owner framing / significance
EOF

state=$(python3 "$DP" consume "$work/harvest.md")

# 2. Holds BOTH the fact sheet and the NEEDS-OWNER list.
echo "$state" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert len(d["fact_sheet"]) == 3, d
assert len(d["needs_owner"]) == 2, d
assert d["next_stage"] == "interview", d           # NEEDS-OWNER threads to the interview
' && ok "consume holds fact sheet (3) + NEEDS-OWNER (2), next_stage=interview" || err "consume state wrong"

# 3. Source pointers carried VERBATIM (each form survives unmodified).
echo "$state" | python3 -c '
import json, sys
srcs = [e["source"] for e in json.load(sys.stdin)["fact_sheet"]]
assert srcs == ["bench/results.md:42@a1b2c3d", "a1b2c3d", "https://example.com/x"], srcs
' && ok "source pointers preserved verbatim (path:line@sha / sha / URL)" || err "source pointers altered"

# 4. NEEDS-OWNER threaded forward with its topic (for the gap interview).
echo "$state" | python3 -c '
import json, sys
tops = sorted(n["topic"] for n in json.load(sys.stdin)["needs_owner"])
assert tops == ["significance", "surprise"], tops
' && ok "NEEDS-OWNER items carry their interview topic forward" || err "NEEDS-OWNER not threaded with topic"

# 5. Does NOT re-read sources: consume works with NO writing-sources.yaml / no
#    source repos present in cwd (it reads only the harvest document).
bare=$(mktemp -d)
cp "$work/harvest.md" "$bare/h.md"
( cd "$bare" && python3 "$DP" consume "$bare/h.md" >/dev/null 2>&1 ) \
  && ok "consume needs no source repos (reads only the harvest doc — no re-read path)" \
  || err "consume tried to read sources"
rm -rf "$bare"

# 5b. SOURCE grammar matches validate-fact-sheet.py (Story 13.8): a multi-line
#     quote range that the validator accepts must not be rejected by consume.
cat > "$work/mlquote.md" <<'EOF'
# Fact sheet: multiline

- "wrapped table cell first half second half" / notes.md:4-5@a1b2c3d / quote

# NEEDS-OWNER
EOF
python3 "$DP" consume "$work/mlquote.md" >/dev/null 2>&1 \
  && ok "consume accepts a multi-line quote range (path:l1-l2@sha) like validate-fact-sheet.py" \
  || err "consume rejected a multi-line quote range the validator accepts (regression #136)"
# a range on a NON-quote KIND is rejected here, exactly as the validator rejects it.
printf '# Fact sheet: x\n- Ranged fact / notes.md:4-5@a1b2c3d / result\n\n# NEEDS-OWNER\n' > "$work/mlrange.md"
python3 "$DP" consume "$work/mlrange.md" >/dev/null 2>&1 \
  && err "consume accepted a line range on a non-quote KIND" \
  || ok "consume rejects a range on a non-quote KIND (single-line-only, like the validator)"
# Divergence guard: consume routes through the validator's shared grammar function.
grep -q 'source_form_ok' "$DP" && ok "consume uses validate-fact-sheet.py's shared source_form_ok grammar" \
  || err "consume does not route through the shared SOURCE grammar (can diverge again)"

# 6. Empty-but-valid harvest output advances (total stage contract).
printf '# Fact sheet: empty\n\n# NEEDS-OWNER\n' > "$work/empty.md"
python3 "$DP" consume "$work/empty.md" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["fact_sheet"] == [] and d["needs_owner"] == [], d
' && ok "valid-but-empty harvest output advances (empty lists, no error)" || err "empty result errored"

# 7. A contract violation surfaces here rather than being absorbed.
printf '# Fact sheet: x\n- A / a1b2c3d / event\n' > "$work/nosec.md"
python3 "$DP" consume "$work/nosec.md" >/dev/null 2>&1 && err "missing NEEDS-OWNER section absorbed silently" \
  || ok "missing NEEDS-OWNER section surfaces as an error"
printf '# Fact sheet: x\n- Bad / a1b2c3d / opinion\n\n# NEEDS-OWNER\n' > "$work/badkind.md"
python3 "$DP" consume "$work/badkind.md" >/dev/null 2>&1 && err "off-contract KIND absorbed silently" \
  || ok "off-contract fact-sheet KIND surfaces as an error"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-1 consume checks passed.\n'; exit 0
else
  printf '\nstage-1 consume checks FAILED.\n' >&2; exit 1
fi
