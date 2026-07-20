#!/usr/bin/env sh
# check-verify-provenance.sh — verify the independent verify-provenance check
# (Story 11.2). POSIX shell + stdlib Python.
#
# Covers: verify-provenance runs standalone, not sharing the drafting context
# (NFR13) — it lives in its own script and reads only the map + declared
# pointers + the judge's verdicts (AC1); a narration sentence the judge flags as
# asserting a checkable proposition is a gate failure (AC2); a derived claim
# whose inherited pointers don't resolve to fact-sheet entries is a gate failure,
# and a judge-flagged forbidden category is too (AC3); a clean map passes with no
# findings (AC4).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VP="$root/scripts/verify-provenance.py"
DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$VP', doraise=True)" 2>/dev/null \
  && ok "verify-provenance compiles" || { err "verify-provenance syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# AC1 — it is a STANDALONE script, independent of the drafting pipeline.
[ -f "$VP" ] && ok "verify-provenance is its own script (independent of drafting)" || err "verify-provenance.py missing"
grep -qE 'add_parser\("verify-provenance"\)' "$DP" 2>/dev/null && err "verify-provenance is a draft-pipeline subcommand (not independent)" \
  || ok "verify-provenance is not a draft-pipeline subcommand (independence)"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
printf 'fs-15\nfs-12\nfs-14\n' > "$work/ids.txt"

# AC4 — a clean map whose pointers all resolve, no judge findings, passes.
cat > "$work/good.txt" <<'MAP'
P1.S1: sourced <- fs-15
P1.S2: derived <- fs-12, fs-14
P1.S3: narration
P4.S5: verify
MAP
python3 "$VP" --map "$work/good.txt" --fact-sheet "$work/ids.txt" >/dev/null 2>&1 \
  && ok "a clean map passes with no findings" || err "clean map failed"

# Story 13.51 — a `den:<ledger-id>@<run>` pointer resolves like any other
# declared fact-sheet pointer (the pointer set is the resolution surface; the
# colon/@ in the form must not break map parsing), and an undeclared one still
# fails.
printf 'den:f-19@r-208\nden:f-3@r-208\nfs-12\n' > "$work/den-ids.txt"
cat > "$work/den.txt" <<'MAP'
P1.S1: sourced <- den:f-19@r-208
P1.S2: derived <- den:f-19@r-208, den:f-3@r-208
P2.S1: derived <- den:f-19@r-208, fs-12
MAP
python3 "$VP" --map "$work/den.txt" --fact-sheet "$work/den-ids.txt" >/dev/null 2>&1 \
  && ok "den:<ledger-id>@<run> pointers parse and resolve (Story 13.51)" \
  || err "den pointer rejected by verify-provenance"
cat > "$work/den-bad.txt" <<'MAP'
P1.S1: sourced <- den:f-99@r-208
MAP
python3 "$VP" --map "$work/den-bad.txt" --fact-sheet "$work/den-ids.txt" >/dev/null 2>&1 \
  && err "undeclared den pointer accepted" \
  || ok "a den pointer absent from the fact sheet is still a gate failure"

# Story 17.2 (#439) — a paragraph-granularity OWNER-ATTRIBUTED PROSE SPAN: a
# bare `P<n>` position (no `.S<n>`) carrying an interview question-id pointer is
# valid `sourced` attribution for the whole owner-opinion paragraph. It must
# pass when the question-id resolves, and still fail closed when it does not.
printf 'q2\nfs-15\n' > "$work/span-ids.txt"
cat > "$work/span.txt" <<'MAP'
P1.S1: sourced <- fs-15
P2: sourced <- q2
MAP
python3 "$VP" --map "$work/span.txt" --fact-sheet "$work/span-ids.txt" >/dev/null 2>&1 \
  && ok "paragraph-granularity owner-attributed span (P<n> <- q<id>) is accepted (Story 17.2)" \
  || err "paragraph-granularity owner-attributed span rejected by verify-provenance"
cat > "$work/span-bad.txt" <<'MAP'
P2: sourced <- q9
MAP
python3 "$VP" --map "$work/span-bad.txt" --fact-sheet "$work/span-ids.txt" >/dev/null 2>&1 \
  && err "owner span with unresolvable question-id accepted" \
  || ok "an owner span whose question-id does not resolve is still a gate failure"

# AC3a — a derived claim whose inherited pointer does not resolve is a gate failure.
cat > "$work/badptr.txt" <<'MAP'
P1.S2: derived <- fs-12, fs-99
MAP
python3 "$VP" --map "$work/badptr.txt" --fact-sheet "$work/ids.txt" >/dev/null 2>&1 \
  && err "unresolvable derived pointer accepted" || ok "derived pointer must resolve to a fact-sheet entry"

# Judge-findings files carry the Story 13.67 attestation (drafts + hash below);
# these two cases must fail through the SEMANTIC layer, not the attestation gate.
printf 'plain draft body\n' > "$work/plain-draft.md"
PLAINH=$(python3 -c "import hashlib;print(hashlib.sha256(open('$work/plain-draft.md',encoding='utf-8').read().encode()).hexdigest())")

# AC2 — a narration sentence the judge flags (asserts a checkable proposition) fails.
{ printf 'attestation: draft-sha256=%s\ngraded: P1.S2,P1.S3\n' "$PLAINH"
  printf 'P1.S3: narration asserts a checkable proposition (falsifiability)\n'; } > "$work/verdicts.txt"
out=$(python3 "$VP" --map "$work/good.txt" --fact-sheet "$work/ids.txt" --draft "$work/plain-draft.md" --judge-findings "$work/verdicts.txt" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'falsifiability' \
  && ok "judge-flagged narration (falsifiability) is a gate failure" || err "judge-flagged narration was not a semantic gate failure (rc=$rc): $out"

# AC3b — a judge-flagged forbidden derivation category fails.
{ printf 'attestation: draft-sha256=%s\ngraded: P1.S2,P1.S3\n' "$PLAINH"
  printf 'P1.S2: derived adds causality (forbidden)\n'; } > "$work/verdicts2.txt"
out=$(python3 "$VP" --map "$work/good.txt" --fact-sheet "$work/ids.txt" --draft "$work/plain-draft.md" --judge-findings "$work/verdicts2.txt" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'causality' \
  && ok "judge-flagged forbidden derivation category is a gate failure" || err "judge-flagged forbidden category was not a semantic gate failure (rc=$rc): $out"

# Structural independence: narration/verify carrying a pointer fails even without a fact sheet.
printf 'P1.S3: narration <- fs-1\n' | python3 "$VP" --map - >/dev/null 2>&1 \
  && err "narration with a pointer accepted" || ok "narration-with-pointer fails (independent structural re-check)"

# The judge worklist is extractable (list narration + derived for grading).
[ "$(python3 "$VP" --map "$work/good.txt" --list-narration)" = "P1.S3" ] \
  && ok "narration positions are listable for the judge" || err "--list-narration wrong"

# --- #304: positions carry a line ANCHOR so the judge matches, never re-derives --
cat > "$work/anch-draft.md" <<'MD'
---
slug: t
audience: en-practitioner
---
# The one claim

Structured discovery halved our token bill.
Under a binary rule, a sentence is either sourced or marked, and connective tissue is neither.
The bench recorded a 2x drop.
MD
cat > "$work/anch-map.txt" <<'MAP'
P1.S1[L7]: sourced <- fs-1
P1.S2[L8]: narration
P2.S1[L9]: sourced <- fs-3
MAP
ANCH=$(python3 -c "import hashlib;print(hashlib.sha256(open('$work/anch-draft.md',encoding='utf-8').read().encode()).hexdigest())")
att() { printf 'attestation: draft-sha256=%s\ngraded: P1.S2\n' "$ANCH"; }
# The hand-off carries the anchored line verbatim — no skip rules to apply.
python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" --list-narration \
  | grep -q 'P1.S2 \[L8\]: Under a binary rule' \
  && ok "hand-off carries each position's anchored line verbatim (#304)" \
  || err "--list-narration --draft did not carry the anchored text"
python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" --list-derived >/dev/null 2>&1 \
  && ok "--list-derived accepts anchored maps" || err "--list-derived broke on anchored map"

# Determinism: every judge spawn receives byte-identical text (the defect was
# three judges deriving three different numberings from the same draft).
n=$(for i in 1 2 3; do python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" --list-narration | cksum; done | sort -u | wc -l)
[ "$n" -eq 1 ] && ok "three independent spawns get an identical hand-off (deterministic)" \
  || err "hand-off differed across spawns ($n variants)"

# A mislocated verdict is detectable from the record alone: the judge echoes the
# sentence it graded, and it does not match the anchor. This is the observed
# case — a confident finding against text that was not at that position.
{ att; printf 'P1.S2 ~ "enumerates six universal derivation rules": asserts a checkable proposition\n'; } \
  > "$work/jf-bad.txt"
python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
  --judge-findings "$work/jf-bad.txt" 2>&1 | grep -q 'ANCHOR MISMATCH' \
  && ok "a judge verdict quoting the wrong sentence is caught mechanically (#304)" \
  || err "anchor mismatch not detected"
# A judge quoting the real anchored sentence is graded as a normal finding.
{ att; printf 'P1.S2 ~ "Under a binary rule, a sentence is either sourced": asserts a checkable proposition\n'; } \
  > "$work/jf-ok.txt"
out=$(python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
      --judge-findings "$work/jf-ok.txt" 2>&1 || true)
printf '%s' "$out" | grep -q 'asserts a checkable proposition' \
  && ! printf '%s' "$out" | grep -q 'ANCHOR MISMATCH' \
  && ok "a correctly-located verdict is graded normally, not discarded" \
  || err "a correct verdict was mishandled: $out"
# A verdict against a position absent from the map cannot be trusted.
{ att; printf 'P9.S9: asserts a checkable proposition\n'; } > "$work/jf-ghost.txt"
python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
  --judge-findings "$work/jf-ghost.txt" 2>&1 | grep -q 'not in the map' \
  && ok "a verdict against an unmapped position is rejected" || err "ghost position accepted"
python3 "$VP" --map "$work/good.txt" --list-derived | grep -q 'P1.S2: fs-12, fs-14' \
  && ok "derived claims are listable for the judge" || err "--list-derived wrong"

# --- Story 13.67 (#364): fail-closed judge attestation ---
# Comment-only file: absence of verdicts is never PASS.
printf '# isolated-judge verdicts: all positions PASS\n' > "$work/att-comment.txt"
out=$(python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
      --judge-findings "$work/att-comment.txt" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'never PASS' \
  && ok "comment-only verdicts file fails closed (13.67)" || err "comment-only file not rejected (rc=$rc)"
# Coverage gap: graded set must cover every narration+derived position.
printf 'attestation: draft-sha256=%s\ngraded: P9.S1\n' "$ANCH" > "$work/att-gap.txt"
out=$(python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
      --judge-findings "$work/att-gap.txt" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'ungraded position(s): P1.S2' \
  && ok "worklist coverage gap fails closed naming the missing positions (13.67)" || err "coverage gap not rejected (rc=$rc): $out"
# Unknown graded position.
printf 'attestation: draft-sha256=%s\ngraded: P1.S2,P9.S9\n' "$ANCH" > "$work/att-ghost.txt"
out=$(python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
      --judge-findings "$work/att-ghost.txt" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'not in the map: P9.S9' \
  && ok "unknown graded position fails closed (13.67)" || err "unknown graded position not rejected (rc=$rc)"
# Draft-hash mismatch: verdicts for a prior draft never validate the current one.
printf 'attestation: draft-sha256=%s\ngraded: P1.S2\n' \
  "0000000000000000000000000000000000000000000000000000000000000000" > "$work/att-stale.txt"
out=$(python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
      --judge-findings "$work/att-stale.txt" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'draft-sha256 mismatch' \
  && ok "draft-hash mismatch fails closed (13.67)" || err "stale-draft attestation not rejected (rc=$rc)"
# Valid attestation with zero failure verdicts = judged clean = PASS.
att > "$work/att-clean.txt"
python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" \
  --judge-findings "$work/att-clean.txt" >/dev/null 2>&1 \
  && ok "valid attestation with no failures passes (judged clean, 13.67)" || err "valid clean attestation rejected"
# The hand-off emits the attestation header the judge echoes.
python3 "$VP" --map "$work/anch-map.txt" --draft "$work/anch-draft.md" --list-narration \
  | grep -q "attestation: draft-sha256=$ANCH" \
  && ok "hand-off emits the attestation header for the judge to echo (13.67)" || err "hand-off missing attestation header"

# SKILL wires the independent check and states it does not share drafting context.
grep -q 'verify-provenance.py' "$SKILL" && grep -qi 'does .*not.*share\|not share this' "$SKILL" \
  && ok "SKILL wires the independent verify-provenance (no shared context)" || err "SKILL does not wire independent verify-provenance"
# NFR13 operationalized (#123): the semantic judge runs in a subagent that never
# saw the drafting turn, spawned via the Task tool — not an inline continuation.
grep -qi 'subagent' "$SKILL" && grep -qi 'never saw the drafting turn' "$SKILL" \
  && ok "SKILL spawns the provenance judge as an isolated subagent (NFR13)" || err "SKILL does not spawn an isolated judge subagent"
# Story 13.67: the SKILL states the attestation grammar and the re-spawn rule.
grep -q 'attestation: draft-sha256=' "$SKILL" \
  && ok "SKILL states the judge attestation grammar verbatim (13.67)" || err "SKILL missing attestation grammar"
grep -qi 're-spawn.*judge\|judge.*re-spawn\|every revision cycle re-spawns' "$SKILL" \
  && ok "SKILL states every revision cycle re-spawns the judge (13.67)" || err "SKILL missing re-spawn-per-cycle rule"

if [ "$fail" -eq 0 ]; then
  printf '\nAll verify-provenance checks passed.\n'; exit 0
else
  printf '\nverify-provenance checks FAILED.\n' >&2; exit 1
fi
