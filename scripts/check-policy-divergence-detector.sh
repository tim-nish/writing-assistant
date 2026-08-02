#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# covers: scripts/mint_guard.py scripts/detect-policy-divergence.py
# check-policy-divergence-detector.sh — verify the consumer-side
# policy-divergence detector's mechanical core (SPEC-policy-divergence-detector,
# #436, Story 13.99). POSIX shell + stdlib Python only.
#
# Covers: CAP-2 record schema (valid record + every rejection class, incl. the
# no-verdict-field invariant); CAP-4 ledger schema + dedup key + dismissed-needs-
# reason + duplicate-key refusal; CAP-5 direction guard (both verdicts); and the
# CAP-3/#436 ratification invariant — the staging block is a CONFORMANCE COPY of
# the hub §3.1 schema with declared precedence, not an independent definition.
#
# It also carries the mint-guard COMPOSE refusal, re-homed here when
# check-minted-issue-denominator.sh retired (#1278). The retirement's premise is
# that the typed filing seam now refuses an empty denominator, so an unguarded
# composition can no longer reach the tracker — true, and verified at delivery.
# But the seam guards FILING, and this detector composes proposal-only bodies
# that are never filed: their guard is mint_guard.py itself. Retiring the whole
# fixture would have left a live module with zero coverage, so the one polarity
# the seam cannot reach moved here rather than being dropped with the rest.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

V="scripts/validate-divergence-candidate.py"
FIX="scripts/fixtures/policy-divergence"
SPEC="specs/spec-policy-divergence-detector/SPEC.md"
FMT="specs/spec-policy-divergence-detector/detector-formats.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$V', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# rec <python-mutation> : write the base record with a mutation applied, to $work/r.json.
rec() {
python3 - "$FIX/candidate.json" "$work/r.json" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[3])            # mutation operates on `d`
json.dump(d, open(sys.argv[2], "w"))
PY
}
R() { python3 "$V" record "$work/r.json" >/dev/null 2>"$work/e"; }
saw() { grep -q -- "$1" "$work/e" && ok "$2" || err "$2 (report was: $(cat "$work/e"))"; }

# --- CAP-2: the valid record passes -----------------------------------------
python3 "$V" record "$FIX/candidate.json" >/dev/null 2>&1 \
  && ok "CAP-2: the seeded valid record passes" || err "valid record refused"

# --- CAP-2: rejection classes (each a seeded mutation the validator fails) ---
rec "d['policy'].pop('quote')";  R && err "missing policy.quote accepted" || saw "policy.quote" "CAP-2 rejects a missing upstream quote"
rec "d['policy'].pop('pointer')";R && err "missing policy.pointer accepted" || saw "policy.pointer" "CAP-2 rejects a missing policy pointer"
rec "d['policy'].pop('pin')";    R && err "missing policy.pin accepted" || saw "policy.pin" "CAP-2 rejects a missing pin"
rec "d['direction']='wrong'";    R && err "bad direction accepted" || saw "direction" "CAP-2 rejects a direction outside {contradiction,outgrown}"
rec "d['status']='resolved'";    R && err "bad status accepted" || saw "status" "CAP-2 rejects a status other than 'candidate'"
rec "d['severity']='high'";      R && err "verdict field accepted" || saw "verdict-shaped" "CAP-2 rejects a verdict-shaped field (no severity/verdict/resolution)"
rec "d['proposed_resolution']='update the line'"; R && err "resolution field accepted" || saw "verdict-shaped" "CAP-2 rejects a proposed-resolution field"
rec "d['extra']=1";              R && err "unknown field accepted" || saw "closed" "CAP-2 rejects an unknown field (closed schema)"
rec "d['decision']['evidence']='we changed our minds about this'"; R && err "prose evidence accepted" || saw "decision.evidence" "CAP-2 rejects prose evidence (needs path:line)"
rec "d['policy']['pointer']='LESSONS.md:41'"; R && err "unpinned pointer accepted" || saw "policy.pointer" "CAP-2 rejects an unpinned policy pointer"
rec "d['rationale']='They disagree. This is why. And more.'"; R && err "multi-sentence rationale accepted" || saw "rationale" "CAP-2 rejects a multi-sentence rationale (one sentence, describes not resolves)"

# --- CAP-4: dedup key equals the ledger key ---------------------------------
k=$(python3 "$V" dedup-key "$FIX/candidate.json")
lk=$(python3 -c "import json;print(json.load(open('$FIX/ledger.json'))['entries'][0]['key'])")
[ "$k" = "$lk" ] && ok "CAP-4: the record's dedup key equals its ledger entry key ($k)" \
  || err "dedup key ($k) != ledger key ($lk)"

# --- CAP-4: ledger schema ----------------------------------------------------
python3 "$V" ledger "$FIX/ledger.json" >/dev/null 2>&1 \
  && ok "CAP-4: the seeded valid ledger passes" || err "valid ledger refused"

led() {
python3 - "$FIX/ledger.json" "$work/l.json" "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"))
PY
}
L() { python3 "$V" ledger "$work/l.json" >/dev/null 2>"$work/e"; }

led "d['entries'][0].pop('reason')"; L && err "dismissed w/o reason accepted" || saw "reason" "CAP-4 rejects a dismissed entry with no reason"
led "d['entries'].append(dict(d['entries'][0]))"; L && err "duplicate dedup key accepted" || saw "duplicate dedup key" "CAP-4 rejects a duplicate dedup key (one row per divergence)"
led "d['entries'][0]['occurrences']=0"; L && err "occurrences 0 accepted" || saw "occurrences" "CAP-4 rejects occurrences < 1"

# --- CAP-5: direction guard --------------------------------------------------
same=$(python3 "$V" direction --original "reference records only" --current "reference records only")
printf '%s' "$same" | grep -q '"is_candidate": true' \
  && ok "CAP-5: unchanged line at the pin -> a divergence candidate (this tool moved)" \
  || err "CAP-5 same-line verdict wrong: $same"
moved=$(python3 "$V" direction --original "reference records only" --current "syndicate everywhere")
printf '%s' "$moved" | grep -q '"is_candidate": false' \
  && printf '%s' "$moved" | grep -q 'upstream-moved' \
  && ok "CAP-5: changed line -> upstream-moved, routed to seam stale machinery, NOT a candidate" \
  || err "CAP-5 moved-line verdict wrong: $moved"

# --- CAP-3 / #436 ratification: staging block conforms to hub §3.1 -----------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SPEC"); F=$(norm "$FMT")
printf '%s' "$S" | grep -qi 'Ratified 2026-07-20' \
  && ok "SPEC is ratified (not a draft)" || err "SPEC still marked draft/awaiting ratification"
printf '%s' "$F" | grep -qi 'conformance copy' && printf '%s' "$F" | grep -qi 'knowledge-architecture.md .3.1' \
  && ok "CAP-3: staging block is a conformance copy of the hub §3.1 schema" \
  || err "detector-formats §4 missing the hub §3.1 conformance-copy framing"
printf '%s' "$F" | grep -qi 'hub schema is the authority' \
  && printf '%s' "$F" | grep -qi 'defect of THIS spec' \
  && ok "CAP-3: declared precedence — hub wins on mismatch; mismatch is this spec's defect" \
  || err "detector-formats §4 missing the precedence rule"
printf '%s' "$F" | grep -qi 'Not the only emitter' \
  && ok "CAP-3: does not assume it is the sole emitter (fork-triage cites the same authority)" \
  || err "detector-formats §4 missing the not-sole-emitter clause"

# --- mint-guard compose refusal, re-homed from #1278's retired fixture --------
# The seam refuses an empty denominator at FILING. This asserts the same refusal
# at COMPOSE, which is the surface this detector actually uses.
G="$(dirname "$0")/mint_guard.py"
mwork=$(mktemp -d)
printf '# divergence: probe\n\nbody\n' > "$mwork/body.md"
printf '{"checked": []}' > "$mwork/empty.json"
if python3 "$G" compose --record "$mwork/empty.json" --body-file "$mwork/body.md" \
     --run-record "$mwork/rr.json" --detected 2026-08-02 >"$mwork/out.md" 2>"$mwork/err.txt"; then
  err "#1278: an empty-enumeration record composed a body (exit 0) — the #1171-#1175 shape is representable again"
else
  ok "#1278: empty enumeration refuses to compose (non-zero exit)"
fi
[ -s "$mwork/out.md" ] \
  && err "#1278: refusal still composed a body on stdout" \
  || ok "#1278: refusal composes NOTHING — no body exists to file"
printf '{"checked": ["a.md", "b.md"]}' > "$mwork/full.json"
python3 "$G" compose --record "$mwork/full.json" --body-file "$mwork/body.md" \
    --run-record "$mwork/rr2.json" --detected 2026-08-02 >"$mwork/out2.md" 2>/dev/null \
  && [ -s "$mwork/out2.md" ] \
  && ok "#1278: a non-empty enumeration composes, denominator visible" \
  || err "#1278: a non-empty record was refused or composed nothing"
rm -rf "$mwork"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-divergence-detector checks passed.\n'; exit 0
else
  printf '\npolicy-divergence-detector checks FAILED.\n' >&2; exit 1
fi
