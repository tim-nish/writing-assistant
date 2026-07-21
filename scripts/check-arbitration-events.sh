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

# 5. Stable finding identity (#497): distinct findings emit distinct events, but
#    true cross-run recurrence (same criterion at the same anchor) still
#    collapses. Two accepted findings with identical pass|criterion|severity|
#    disposition but DIFFERENT anchors must NOT emit byte-identical detail
#    (they would collapse under Tanuki's scenario|type|detail exact-dupe key).
mkdir -p "$work/a" "$work/b"
cat > "$work/two.jsonl" <<'EOF'
{"pass":"cold-read","criterion":"assumed-knowledge","severity":"should","disposition":"accepted","anchor":"L64:exploration-axes"}
{"pass":"cold-read","criterion":"assumed-knowledge","severity":"should","disposition":"accepted","anchor":"L32:sonnet-tier"}
EOF
python3 "$EMIT" "$work/two.jsonl" --ws "$work/a" --scenario t --run-id r1 --ingest-cmd "" >/dev/null 2>&1
python3 - "$work/a/arbitration-events.jsonl" <<'PY' && ok "distinct findings (differing anchor) emit distinct detail (#497)" || err "distinct findings collapsed to identical detail"
import json,sys
ev=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(ev)==2, ev
assert ev[0]["detail"]!=ev[1]["detail"], ev
# the identity must let the event be joined back to its originating edit offline
assert "L64:exploration-axes" in ev[0]["detail"] and "L32:sonnet-tier" in ev[1]["detail"], ev
PY

# Same criterion at the same anchor across two SEPARATE runs -> identical detail
# (recurrence still collapses; detail must be run-independent).
printf '%s\n' '{"pass":"cold-read","criterion":"assumed-knowledge","severity":"should","disposition":"accepted","anchor":"L64:exploration-axes"}' > "$work/one.jsonl"
mkdir -p "$work/a2" "$work/b2"
python3 "$EMIT" "$work/one.jsonl" --ws "$work/a2" --scenario t --run-id r1 --ingest-cmd "" >/dev/null 2>&1
python3 "$EMIT" "$work/one.jsonl" --ws "$work/b2" --scenario t --run-id r2 --ingest-cmd "" >/dev/null 2>&1
python3 - "$work/a2/arbitration-events.jsonl" "$work/b2/arbitration-events.jsonl" <<'PY' && ok "same criterion+anchor across runs keeps identical detail (recurrence collapses, #497)" || err "cross-run recurrence detail diverged"
import json,sys
a=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
b=[json.loads(l) for l in open(sys.argv[2]) if l.strip()]
assert a[-1]["detail"]==b[-1]["detail"], (a[-1]["detail"], b[-1]["detail"])
assert a[-1]["run"]!=b[-1]["run"]  # different runs, same detail
PY

if [ "$fail" -eq 0 ]; then
  printf '\nAll arbitration-event checks passed.\n'; exit 0
else
  printf '\narbitration-event checks FAILED.\n' >&2; exit 1
fi
