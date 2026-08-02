#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-08-02 — all writes land in a private `mktemp -d`
#   (fixture repo + workspace); the only reads outside it are this repo's
#   scripts. No XDG state, no config home, no network source is consulted
#   (the issues source is never requested by any fixture run).
# tier: inner
# covers: scripts/examine.py scripts/terrain_scope.py skills/draft-article/stages/examine.md
# removal-signal: retire this check when examine's contract (never-judge,
#   anchored commits, derived-scope refusal, coverage separation, at-the-read
#   pin recording) is enforced by a schema over the emitted record rather than
#   by assertions here, or when the examine step itself is superseded.
# check-examine.sh — per-claim examination grounds a claim at the read that
# produced its pin, and the tool NEVER judges (Story 20.147, #1182/#1097/#1185).
#
# POSIX shell + stdlib Python.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

EX="scripts/examine.py"
python3 -c "import py_compile; py_compile.compile('$EX', doraise=True)" 2>/dev/null \
  && ok "examine.py compiles" \
  || { err "examine.py syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
h="$work/host"; mkdir -p "$h"
git -C "$h" init -q
printf 'the retry storm was fixed by widening the backoff\n' > "$h/notes.md"
git -C "$h" add -A
git -C "$h" -c user.email=t@example.com -c user.name=t commit -qm "widen the retry backoff"

WS="$work/ws"; mkdir -p "$WS"

# 1. Commits are ANCHOR-ADDRESSED: no anchor -> skipped with the stated reason,
#    never a keyword search over history.
out=$(python3 "$EX" --root "$h" --claim "the retry backoff was widened" --sources commits)
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["verdict"] is None, "verdict not null"
assert d["verdict_owner"], "no verdict_owner"
assert d["searched"] == [], "anchorless commits were searched"
sk = {s["source"]: s for s in d["skipped"]}
assert "commits" in sk and "anchor" in sk["commits"]["reason"], sk
' && ok "anchorless commits are SKIPPED with the anchor-addressing reason (never keyword-searched)" \
  || err "anchorless commits were not skipped with a reason"

# 2. An anchored query returns pinned, time-axis material with a citable form,
#    and --ws records the pin AT THE READ (record + ledger).
out=$(python3 "$EX" --root "$h" --claim "the retry backoff was widened" \
      --sources commits --anchor "path:notes.md" --ws "$WS")
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["verdict"] is None and d["verdict_owner"], "tool judged, or no owner"
ev = d["evidence"]
assert ev and ev[0]["source_type"] == "commit" and ev[0]["time_axis"] is True, ev
assert ev[0]["cite"] and ev[0]["cite"] == ev[0]["ref"], "commit cite is not the sha"
assert d["counts"]["time_axis"] == len(ev), d["counts"]
assert d["recorded"]["record"] and d["recorded"]["pin_ledger"], "not recorded"
' && ok "anchored commit query: pinned time-axis evidence with a citable sha" \
  || err "anchored commit query wrong shape"
[ -s "$WS/examination-pins.txt" ] \
  && grep -qE '^[0-9a-f]{7,40}$' "$WS/examination-pins.txt" \
  && ok "the pin is recorded at the read: ledger carries the citable sha (AC1)" \
  || err "examination-pins.txt missing or carries no sha"
ls "$WS/examinations/"*.json >/dev/null 2>&1 \
  && ok "the full examination record persists under \$WS/examinations/" \
  || err "no examination record written"

# 3. Coverage separates read-empty from unreachable-empty (AC3): prose with no
#    declared sources is a SKIP with a reason, not an absence finding.
out=$(python3 "$EX" --root "$h" --claim "anything" --sources prose)
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sk = {s["source"]: s for s in d["skipped"]}
assert "prose" in sk and sk["prose"]["reason"], "prose skip carries no reason"
assert "coverage_claim" in d, "no coverage claim"
' && ok "coverage: an unreachable source is a skip WITH ITS REASON, never absence" \
  || err "coverage separation missing"

# 4. Derived scope binds (AC2): a repository outside the served attribution is
#    REFUSED, NOT SEARCHED — through terrain_scope's one refusal layer.
cat > "$work/scope.json" <<'EOF'
{"examine_scope": {"projects": ["other-repo"], "served": true,
 "by_member": [{"index": "1.2", "projects": ["other-repo"]}]}}
EOF
out=$(python3 "$EX" --root "$h" --claim "x" --scope "$work/scope.json" --member 1.2)
rc=$?
[ "$rc" -eq 3 ] && ok "out-of-scope examination exits 3 (refused)" \
  || err "out-of-scope examination did not exit 3 (rc=$rc)"
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["refusal"]["refused"] is True, "no refusal"
assert "refused, not searched" in d["refusal"]["line"], d["refusal"]["line"]
assert d["evidence"] == [] and d["searched"] == [], "a refused scope was searched"
assert "false attribution" in d["refusal"]["line"], "refusal does not name the reason"
' && ok "refusal names the Strand attribution and searches NOTHING (#1185)" \
  || err "refusal shape wrong"

# 5. An in-scope repository proceeds (membership, not classification).
cat > "$work/scope2.json" <<EOF
{"examine_scope": {"projects": ["host"], "served": true,
 "by_member": [{"index": "1.2", "projects": ["host"]}]}}
EOF
python3 "$EX" --root "$h" --claim "x" --scope "$work/scope2.json" --member 1.2 \
  --sources commits >/dev/null 2>&1 \
  && ok "an in-scope repository is examined, not asked about" \
  || err "in-scope examination refused"

# 6. The retired sources gate stays unconstructible here too (AC4): the skill
#    text carries no sources-gate instruction, and no gate composes a file list.
grep -q 'sources_gate' skills/draft-article/stages/stage0.md \
  && err "stage0.md still instructs composing the retired sources gate (#1209)" \
  || ok "stage0.md carries no sources-gate instruction (#1209)"
grep -q 'compose or approve a file list' \
  skills/draft-article/stages/examine.md \
  && ok "examine.md states the no-file-list-gate contract" \
  || err "examine.md missing the no-file-list-gate statement"

[ "$fail" -eq 0 ] || { printf '\nexamine checks FAILED.\n' >&2; exit 1; }
printf '\nAll examine checks passed.\n'
