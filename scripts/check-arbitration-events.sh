#!/usr/bin/env sh
# check-arbitration-events.sh — verify review-arbitration event emission
# (SPEC-article-review CAP-5, Story 13.42): one raw event per finding
# disposition (N in -> N out, five fields, reason required on reject, nothing
# classified at emit); events always land in $WS; the optional
# dogfood.ingest_cmd hook fires when configured and degrades to one logged
# line when absent or failing. POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

EMIT="$root/scripts/emit-arbitration-events.py"
SKILL="skills/review-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$EMIT', doraise=True)" 2>/dev/null \
  && ok "emitter compiles" || { err "emitter syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat > "$work/d.jsonl" <<'EOF'
{"pass":"structure","criterion":"rubric-dim2","severity":"should","disposition":"accepted"}
{"pass":"prose","criterion":"hedging","severity":"nit","disposition":"rejected","reason":"intentional hedge"}
{"pass":"policy","criterion":"policy-contradiction","severity":"blocker","disposition":"position-moved"}
EOF

# 1. N dispositions -> exactly N events, five fields, raw (nothing classified).
out=$(python3 "$EMIT" "$work/d.jsonl" --ws "$work" --scenario t --run-id r1 --ingest-cmd "" 2>/dev/null)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin); assert d["emitted"]==3 and d["ingested"] is False, d' \
  && ok "N dispositions emit exactly N events" || err "emit count wrong: $out"
python3 - "$work/arbitration-events.jsonl" <<'PY' && ok "events carry the five fields, raw, source=review-arbitration" || err "event shape wrong"
import json,sys
lines=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(lines)==3
for e in lines:
    assert e["source"]=="review-arbitration" and e["type"]=="review-arbitration"
    for k in ("pass","criterion","severity","disposition","scenario","run","detail"): assert k in e, e
    assert "finding_class" not in e and "verdict" not in e   # nothing judged at emit
assert lines[1]["reason"]=="intentional hedge"
PY

# 2. A rejected disposition without a reason is refused (exit 2, per-line error).
printf '%s\n' '{"pass":"p","criterion":"c","severity":"nit","disposition":"rejected"}' > "$work/bad.jsonl"
set +e
out=$(python3 "$EMIT" "$work/bad.jsonl" --ws "$work" --ingest-cmd "" 2>&1); rc=$?
set -e
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "requires a one-line" \
  && ok "rejected-without-reason refused (exit 2)" || err "reject-reason contract not enforced (rc=$rc)"

# 3. Configured ingest hook fires with the events file; absence degrades to one
#    logged line and exit 0 (enhancer, never dependency).
cat > "$work/fake-ingest" <<'SH'
#!/bin/sh
echo "$1" > "$(dirname "$0")/ingested-path"
SH
chmod +x "$work/fake-ingest"
python3 "$EMIT" "$work/d.jsonl" --ws "$work" --ingest-cmd "$work/fake-ingest" 2>/dev/null \
  | python3 -c 'import json,sys; assert json.load(sys.stdin)["ingested"] is True' \
  && [ -f "$work/ingested-path" ] \
  && ok "configured dogfood.ingest_cmd receives the events file" || err "ingest hook did not fire"
notice=$(python3 "$EMIT" "$work/d.jsonl" --ws "$work" --ingest-cmd "" 2>&1 >/dev/null)
printf '%s' "$notice" | grep -q "events kept in the run workspace" \
  && ok "absent ingest hook degrades to one logged line (exit 0)" || err "graceful degrade wrong: $notice"
set +e
python3 "$EMIT" "$work/d.jsonl" --ws "$work" --ingest-cmd "/nonexistent-cmd-xyz" >/dev/null 2>"$work/e"; rc=$?
set -e
[ "$rc" -eq 0 ] && grep -q "notice:" "$work/e" \
  && ok "failing ingest hook degrades (exit 0, one notice)" || err "failing hook not graceful (rc=$rc)"

# 4. The review SKILL wires the emit into the arbitration step (CAP-5 carrier).
grep -q "emit-arbitration-events.py" "$SKILL" \
  && grep -qi "one emit per disposition\|one emit per finding disposition" "$SKILL" \
  && ok "review SKILL carries the emit in the arbitration step" || err "SKILL wiring missing"
grep -qi "enhancer, never a dependency" "$SKILL" \
  && ok "SKILL documents the graceful-degrade contract" || err "SKILL degrade contract missing"

if [ "$fail" -eq 0 ]; then
  printf '\nAll arbitration-event checks passed.\n'; exit 0
else
  printf '\narbitration-event checks FAILED.\n' >&2; exit 1
fi
