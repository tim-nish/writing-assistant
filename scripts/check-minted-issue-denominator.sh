#!/usr/bin/env sh
# parallel-safe
# tier: inner — stdlib-Python guard replay over local mktemp fixtures; no seam,
#   no network, no shared state; runs in well under a second
# covers: scripts/mint_guard.py scripts/detect-policy-divergence.py skills/policy-divergence-detector/SKILL.md
# removal-signal: the typed filing seam carries the guard itself (story-sync
#   file-issue refusing an empty denominator toolkit-side, the cross-repo
#   handoff named in story 20.167's question), at which point an unguarded
#   composition in this repo can no longer reach the tracker and this replay
#   is redundant; or #1260 reopens the filing-boundary design.
#
# check-minted-issue-denominator.sh — a mechanically minted issue carries its
# denominator, and an empty denominator refuses to mint (Story 20.167, #1260).
#
# THE REPLAY, BOTH POLARITIES (#1260 AC-4), asserted on BEHAVIOR, never on key
# presence:
#   refuse — a record whose enumeration is empty (`checked: []`, zero bytes,
#            unreachable source) exits non-zero, puts the reason on stderr,
#            reports cannot-determine to the run record, and composes NO body:
#            stdout stays empty, so an absence-shaped issue cannot be filed
#            from it (the #1171-#1175 shape).
#   mint   — a record with a real enumeration composes the full body: the
#            draft text survives verbatim and the denominator section names
#            the actual values (each checked entry, the byte count), from the
#            minting code's own fields (#1260 AC-2).
# Plus the wiring that makes the guard reachable from the one remaining filing
# path (#1260 AC-1): the divergence pass emits a mechanical `denominator`
# block whose values match its input, and the SKILL routes tracker-issue
# emission through the guard.
#
# POSIX shell + stdlib Python only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

G="scripts/mint_guard.py"
D="scripts/detect-policy-divergence.py"
SKILL="skills/policy-divergence-detector/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$G', doraise=True)" 2>/dev/null \
  && ok "mint guard compiles" || { err "mint guard syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

printf '# divergence: review pass groups findings by axis\n\nThe applied line assumes a flat list.\n' > "$work/body.md"

compose() { # $1 record file, $2 stdout file, $3 stderr file
  python3 "$G" compose --record "$1" --body-file "$work/body.md" \
    --run-record "$work/rr.json" --detected 2026-08-02 >"$2" 2>"$3"
}

# --- polarity 1: an empty enumeration REFUSES the mint (AC-3, AC-4) ----------
printf '{"checked": []}' > "$work/empty.json"
if compose "$work/empty.json" "$work/out.md" "$work/err.txt"; then
  err "an empty-enumeration record minted a body (exit 0) — the #1171-#1175 shape is representable again"
else
  ok "empty enumeration: the mint is refused (non-zero exit)"
fi
[ -s "$work/out.md" ] \
  && err "refusal still composed a body on stdout — an absence-shaped issue can be filed from it" \
  || ok "refusal composes NOTHING: stdout is empty, no body exists to file"
grep -qi "empty" "$work/err.txt" && grep -qi "REFUSED" "$work/err.txt" \
  && ok "the refusal reason is on stderr and names the empty search" \
  || err "stderr carries no reason for the refusal"
python3 - "$work/rr.json" <<'PY' && ok "cannot-determine is reported to the run record, with the reason" || err "run record does not carry the cannot-determine outcome"
import json,sys
d=json.load(open(sys.argv[1]))
m=[e for e in d["mints"] if not e["minted"]]
assert len(m)==1, d
assert m[0]["verdict"]=="cannot-determine", d
assert "empty" in m[0]["reason"], d
PY

# Zero bytes and an unreachable source are the same emptiness, same refusal.
printf '{"bytes_read": 0, "sources": 0}' > "$work/zero.json"
compose "$work/zero.json" "$work/out2.md" "$work/err2.txt" \
  && err "a zero-byte search minted a body" \
  || { [ ! -s "$work/out2.md" ] && grep -qi "REFUSED" "$work/err2.txt" \
       && ok "zero bytes read: refused, nothing composed" \
       || err "zero-byte refusal did not behave (body composed or no stderr reason)"; }
printf '{"checked": ["a"], "unreachable": ["policy-hub"]}' > "$work/unreach.json"
compose "$work/unreach.json" "$work/out3.md" "$work/err3.txt" \
  && err "an unreachable source minted a body" \
  || { grep -qi "unreachable" "$work/err3.txt" \
       && ok "unreachable source: refused with the source named" \
       || err "unreachable refusal does not name the source"; }

# --- polarity 2: a real enumeration MINTS, denominator visible (AC-2, AC-4) --
printf '{"checked": ["review:policy-consistency", "interview:seeding", "session:consult-first"], "bytes_read": 2048}' > "$work/full.json"
if compose "$work/full.json" "$work/minted.md" "$work/err4.txt"; then
  ok "real enumeration: the mint composes (exit 0)"
else
  err "a non-empty record was refused"
fi
grep -q "The applied line assumes a flat list." "$work/minted.md" \
  && ok "the draft body survives verbatim in the composed issue" \
  || err "the composed body lost the draft text"
if grep -q "review:policy-consistency" "$work/minted.md" \
   && grep -q "interview:seeding" "$work/minted.md" \
   && grep -q "session:consult-first" "$work/minted.md" \
   && grep -q "(3)" "$work/minted.md" \
   && grep -q "2048" "$work/minted.md"; then
  ok "the body states the denominator's VALUES: all 3 checked entries, their count, and the byte count"
else
  err "the composed body does not state the searched enumeration's actual values"
fi
awk '/## Denominator/{f=1} f' "$work/minted.md" | grep -q "2048" \
  && ok "the denominator is a section of the filed body, not a side channel" \
  || err "the denominator values are not under the body's denominator section"

# --- the filing path holds the record mechanically (AC-1, AC-2) --------------
# The one remaining compose+file path (post-#1183) is the divergence
# detector's tracker-issue emission; its run output must carry a denominator
# whose values MATCH the input it examined — behavior, not key presence.
cat > "$work/f.json" <<'JSON'
[
  { "consult_point": "review:policy-consistency", "direction": "outgrown",
    "rationale": "The tool groups findings by axis where the line assumes a flat list",
    "decision": {"statement": "The review pass classifies findings by axis", "evidence": "specs/spec-article-review/SPEC.md:38"},
    "policy": {"quote": "Findings are presented flat", "pointer": "LESSONS.md:41@8f3c2d1e4a5b6c7d", "pin": "policy-hub@8f3c2d1e4a5b6c7d"},
    "current_line": "Findings are presented flat" }
]
JSON
python3 "$D" run --input "$work/f.json" --detected 2026-08-02 > "$work/o.json" \
  || err "divergence run failed on a clean input"
python3 - "$work/o.json" <<'PY' && ok "the divergence pass emits its denominator from its own record (1 flag, its consult point)" || err "the divergence run output carries no usable denominator"
import json,sys
d=json.load(open(sys.argv[1]))["denominator"]
assert d["checked"]==["review:policy-consistency"], d
assert d["records_read"]==1, d
PY
# And that block IS a mintable record: feed it straight to the guard.
python3 -c "import json;json.dump(json.load(open('$work/o.json'))['denominator'],open('$work/den.json','w'))"
compose "$work/den.json" "$work/o-body.md" "$work/err5.txt" \
  && grep -q "review:policy-consistency" "$work/o-body.md" \
  && ok "the pass's denominator block composes through the guard end to end" \
  || err "the pass's own denominator block cannot mint through the guard"

# --- the SKILL routes the emission through the guard -------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -q "mint_guard.py compose" \
  && ok "SKILL: tracker-issue emission is composed through the mint guard" \
  || err "SKILL does not route tracker-issue emission through mint_guard.py"
printf '%s' "$S" | grep -qi "no issue is opened" \
  && ok "SKILL: a refusal means no issue, relayed as cannot-determine" \
  || err "SKILL does not state that a guard refusal opens no issue"

if [ "$fail" -eq 0 ]; then
  printf '\nAll minted-issue-denominator checks passed.\n'; exit 0
else
  printf '\nminted-issue-denominator checks FAILED.\n' >&2; exit 1
fi
