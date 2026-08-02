#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# covers: scripts/validate-proposal-payload.py skills/owner-facing-proposal-contract.md
# check-proposal-payload.sh — verify payload integrity validation blocks a
# damaged proposal prompt before presentation (Story 10.1, contract (e)).
# POSIX shell + stdlib Python.
#
# Covers: a clean payload passes; a payload with a MISSING Effect line is
# blocked (dogfood seeded defect 1); a field truncated mid-sentence is blocked
# (dogfood seeded defect 2); an over-budget field is blocked (re-author, never
# clip); and the block is a non-zero exit, like verify-markers gating a stage.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

V="$root/scripts/validate-proposal-payload.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
# blocks JSON MSG : expect non-zero exit
blocks() { printf '%s' "$1" | python3 "$V" >/dev/null 2>&1 && err "$2 (payload was NOT blocked)" || ok "$2"; }
passes() { printf '%s' "$1" | python3 "$V" >/dev/null 2>&1 && ok "$2" || err "$2 (clean payload was blocked)"; }

python3 -c "import py_compile; py_compile.compile('$V', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

CLEAN='{"items":[{"where":"Section 2 (Evidence)","why":"the key result is not stated","choices":[{"label":"approve","effect":"keep the section as drafted"},{"label":"modify","effect":"rewrite the section from your answer"}]}]}'
passes "$CLEAN" "clean payload is presentable"

# Seeded defect 1: a choice with a missing Effect line.
NOEFFECT='{"items":[{"where":"Section 2","why":"the key result is not stated","choices":[{"label":"approve"}]}]}'
blocks "$NOEFFECT" "missing Effect line blocks presentation"

# Seeded defect 2: a field truncated mid-sentence (ellipsis).
TRUNC='{"items":[{"where":"Section 2","why":"the key result is not stated and the","choices":[{"label":"approve","effect":"keep the section as drafted…"}]}]}'
blocks "$TRUNC" "mid-sentence truncation (ellipsis) blocks presentation"

# Empty field blocks.
EMPTY='{"items":[{"where":"","why":"x","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$EMPTY" "empty Where field blocks presentation"

# No choices at all blocks (selective presentation requires options).
NOCHOICES='{"items":[{"where":"Section 2","why":"the key result is not stated","choices":[]}]}'
blocks "$NOCHOICES" "a proposal with no choices blocks presentation"

# Over-budget field blocks (must be re-authored shorter, never clipped).
LONG=$(python3 -c "print('x'*300)")
OVER='{"items":[{"where":"'"$LONG"'","why":"y","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$OVER" "over-budget field blocks (re-author, do not clip)"

# --- Plain-text payload contract (g) (Story 13.47, #300) ---
# Forbidden marker classes: each blocks presentation with a per-field diagnostic.
BOLD='{"items":[{"where":"Section 2","why":"the **key result** is not stated","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$BOLD" "(g) bold emphasis ** blocks presentation"
UNDER='{"items":[{"where":"Section 2","why":"the __key result__ is not stated","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$UNDER" "(g) underline emphasis __ blocks presentation"
TICK='{"items":[{"where":"Section 2 (see `specs/qa.md`)","why":"y","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$TICK" "(g) backtick markup blocks presentation"
HEAD='{"items":[{"where":"Section 2","why":"context follows.\n# Evidence\nthe result","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$HEAD" "(g) # heading marker blocks presentation"
LINK='{"items":[{"where":"Section 2","why":"see [the spec](specs/qa.md) for detail","choices":[{"label":"a","effect":"keep it"}]}]}'
blocks "$LINK" "(g) [text](url) link blocks presentation"
# Markers hide in ANY presented field, not just where/why.
EFFTICK='{"items":[{"where":"Section 2","why":"y","choices":[{"label":"a","effect":"rewrite from `answers.md`"}]}]}'
blocks "$EFFTICK" "(g) marker inside a choice Effect blocks presentation"

# Allowed plain-text conventions are never flagged: indentation, - dashes,
# quoting by indentation, CAPITALIZED emphasis, blank-line separation.
ALLOWED='{"items":[{"where":"Section 2 (Evidence) - currently reads:\n    Throughput rose 2x on the last run.\n\nProposed additions:\n  - state the baseline\n  - name the WORKLOAD explicitly","why":"the single result that matters most is not stated","choices":[{"label":"approve","effect":"keep the section as drafted"}]}]}'
passes "$ALLOWED" "(g) allowed conventions (indent, dashes, CAPS, blank lines) pass"
# Bare path / URL (no [text](url) wrapping) is the sanctioned link form.
BARE='{"items":[{"where":"Section 2, sourced from specs/qa.md and https://example.com/run/7","why":"y","choices":[{"label":"a","effect":"keep it"}]}]}'
passes "$BARE" "(g) bare paths and URLs pass"

# Contract (g) is documented once, in the shared convention.
grep -q 'plain text' "$root/skills/owner-facing-proposal-contract.md" \
  && ok "contract (g) documents the plain-text payload rule" || err "contract missing plain-text section"

# --- Presented-payload capture (Story 13.28, SPEC-draft-article-ux CAP-2) ---
ws=$(mktemp -d); trap 'rm -rf "$ws"' EXIT
GOOD='{"items":[{"where":"Section 2 (Evidence)","why":"the key result is not stated","choices":[{"label":"approve","effect":"keep the section as drafted"}]}]}'
LOG="$ws/presented-payloads.jsonl"

# Presentable payload with --ws -> captured verbatim, ask_id 1.
out=$(printf '%s' "$GOOD" | python3 "$V" --ws "$ws" --surface interview -) \
  && ok "capture: presentable payload accepted with --ws" || err "capture call failed"
echo "$out" | grep -q '"ask_id": 1' && ok "capture: first ask gets ask_id 1" || err "ask_id missing/wrong"
python3 - "$LOG" "$GOOD" <<'EOF' && echo verbatim-ok || exit 1
import json, sys
rec = json.loads(open(sys.argv[1], encoding="utf-8").readline())
assert rec["kind"] == "ask" and rec["surface"] == "interview"
assert rec["payload"] == json.loads(sys.argv[2]), "payload not verbatim"
EOF
[ $? -eq 0 ] && ok "capture: payload stored verbatim (no normalization)" || err "capture not verbatim"

# Blocked payload with --ws -> never captured.
printf '%s' "$EMPTY" | python3 "$V" --ws "$ws" - >/dev/null 2>&1 \
  && err "blocked payload exited 0" || true
[ "$(wc -l < "$LOG")" -eq 1 ] && ok "capture: blocked payload never captured" || err "blocked payload was captured"

# Answer records against the same ask_id; log is append-only.
printf '%s' '{"selection":"approve","free_text":"ship it"}' | python3 "$V" --ws "$ws" --answer 1 - >/dev/null \
  && ok "capture: answer recorded" || err "answer recording failed"
[ "$(wc -l < "$LOG")" -eq 2 ] && ok "capture: append-only (2 records after ask+answer)" || err "log not append-only"
tail -1 "$LOG" | grep -q '"kind": "answer"' && tail -1 "$LOG" | grep -q '"ask_id": 1' \
  && ok "capture: answer correlates to its ask_id" || err "answer record malformed"

# Second ask appends with ask_id 3 (line-numbered, never overwritten).
printf '%s' "$GOOD" | python3 "$V" --ws "$ws" --surface verification - >/dev/null \
  && [ "$(wc -l < "$LOG")" -eq 3 ] \
  && ok "capture: resumed/subsequent asks append, never overwrite" || err "second ask did not append"

# (g) markers are blocked on every ask surface the validator serves, and a
# blocked payload is never captured (Story 13.47).
for surface in interview visual-proposal verification arbitration; do
  printf '%s' "$BOLD" | python3 "$V" --ws "$ws" --surface "$surface" - >/dev/null 2>&1 \
    && err "(g) marker payload NOT blocked on surface $surface" \
    || ok "(g) marker payload blocked on surface $surface"
done
[ "$(wc -l < "$LOG")" -eq 3 ] && ok "(g) blocked marker payloads never captured" || err "(g) a blocked marker payload was captured"

# Convention documents the capture (contract (f)).
grep -q 'presented-payloads.jsonl' "$root/skills/owner-facing-proposal-contract.md" \
  && ok "contract (f) documents presented-payload capture" || err "contract missing capture section"


# --- Story 18.51 (#567): premise grounding on the shared proposal gate ---------
# This ONE gate is the presentation path for four surfaces -- gap interview,
# review arbitration, Stage-4 verification, and visual proposals -- so wiring
# it here reaches all of them.
printf '{"items":[{"where":"Section 2","why":"the module, described internally as the demo path, lacks evidence","choices":[{"label":"approve","effect":"keep it"}]}]}' > "$ws/premise-bad.json"
python3 "$V" "$ws/premise-bad.json" 2>&1 | grep -q 'confabulated-premise' \
  && ok "#567: an ungrounded premise in an owner-facing field blocks presentation" \
  || err "ungrounded premise presented to the owner"

printf '{"items":[{"where":"Section 2","why":"the module, described internally (unverified — no declared source) as the demo path, lacks evidence","choices":[{"label":"approve","effect":"keep it"}]}]}' > "$ws/premise-marked.json"
python3 "$V" "$ws/premise-marked.json" >/dev/null 2>&1 \
  && ok "#567: an inline \`unverified —\` marker at the point of use is presentable" \
  || err "a correctly marked premise was blocked"

printf '{"items":[{"where":"Section 2","why":"the evidence is thin","choices":[{"label":"approve","effect":"keep it as originally built for replay"}]}]}' > "$ws/premise-effect.json"
python3 "$V" "$ws/premise-effect.json" 2>&1 | grep -q 'choices\[0\].effect' \
  && ok "#567: the rule reaches choice EFFECT text, not just where/why" \
  || err "choice effect text escapes the premise rule"

# --- the ANSWER envelope is validated at record time (Story 18.106, #694) -----
# `--answer` appended whatever JSON arrived and reported ok:true, so a
# selection-less answer was captured and failed stages later at its consumer.
aws="$ws/answers"; mkdir -p "$aws"
log="$aws/presented-payloads.jsonl"
# An ask to answer (kept minimal — the ask side is covered above).
printf '{"items":[{"where":"Where it is","why":"Why it matters","choices":[{"label":"approve","effect":"keeps it"}]}]}' \
  | python3 "$V" --ws "$aws" --surface test >/dev/null

# The observed defect, by name: the exact payload recorded ok:true on 2026-07-25
# during the #683 adaptation run, and only failed at `adapt-canonical write`.
if printf '%s' '{"choice":"approve"}' | python3 "$V" --ws "$aws" --answer 1 >/dev/null 2>"$ws/e-choice"; then
  err "#694: a selection-less answer ({\"choice\":...}) was recorded as ok"
else
  grep -q 'answer.selection' "$ws/e-choice" \
    && ok "#694: an answer with no \`selection\` is blocked, naming the field" \
    || err "#694: wrong diagnostic: $(cat "$ws/e-choice")"
fi
grep -q '"kind": "answer"' "$log" 2>/dev/null \
  && err "#694: a blocked answer was captured anyway" \
  || ok "#694: a blocked answer is never appended to the capture log"

printf '%s' '{"selection":"   ","free_text":"x"}' | python3 "$V" --ws "$aws" --answer 1 >/dev/null 2>&1 \
  && err "#694: an empty/whitespace selection was recorded" \
  || ok "#694: an empty selection is blocked"
printf '%s' '{"selection":["approve"]}' | python3 "$V" --ws "$aws" --answer 1 >/dev/null 2>&1 \
  && err "#694: a non-string selection was recorded" \
  || ok "#694: a non-string selection is blocked"
printf '%s' '{"selection":"approve","free_text":3}' | python3 "$V" --ws "$aws" --answer 1 >/dev/null 2>&1 \
  && err "#694: a non-string free_text was recorded" \
  || ok "#694: a non-string free_text is blocked"
printf '%s' '["approve"]' | python3 "$V" --ws "$aws" --answer 1 >/dev/null 2>&1 \
  && err "#694: a non-object answer envelope was recorded" \
  || ok "#694: a non-object envelope is blocked"
# An ask payload piped into --answer names the cause, not the symptom.
printf '{"items":[{"where":"w","why":"y","choices":[{"label":"approve","effect":"e"}]}]}' \
  | python3 "$V" --ws "$aws" --answer 1 >/dev/null 2>"$ws/e-askpayload" \
  && err "#694: an ask payload was recorded as an answer" \
  || grep -q 'ASK payload' "$ws/e-askpayload" \
    && ok "#694: an ask payload misrouted into --answer is named as such" \
    || err "#694: misrouted ask payload not diagnosed: $(cat "$ws/e-askpayload")"

# The shipped convention passes, unchanged.
printf '%s' '{"selection":"approve","free_text":""}' | python3 "$V" --ws "$aws" --answer 1 >/dev/null \
  && ok "#694: the shipped {selection, free_text} envelope still records" \
  || err "#694: a well-formed answer was blocked"
grep -q '"selection": "approve"' "$log" \
  && ok "#694: the accepted answer is captured verbatim (CAP-2)" \
  || err "#694: accepted answer not captured"
# SHAPE, not VOCABULARY: a selection this gate would reject is still recordable.
printf '%s' '{"selection":"maybe later","free_text":""}' | python3 "$V" --ws "$aws" --answer 1 >/dev/null \
  && ok "#694: vocabulary stays with the consuming gate (any non-empty selection records)" \
  || err "#694: the validator started policing selection values"
# An extra key the topic-map surface already writes is not an unknown shape.
printf '%s' '{"selection":"stop here","index":"T1.1","free_text":""}' \
  | python3 "$V" --ws "$aws" --answer 1 >/dev/null \
  && ok "#694: a surface-specific extra key (index) is accepted" \
  || err "#694: an existing writer's envelope was rejected"
# Owner prose is not machine-authored text: the marker/budget rules must not
# reach it (an owner may type backticks, or write at length).
long_free=$(python3 -c "print('とても長い自由記述。'*40)")
printf '%s' "{\"selection\":\"modify\",\"free_text\":\"use \`retry\` and $long_free\"}" \
  | python3 "$V" --ws "$aws" --answer 1 >/dev/null \
  && ok "#694: presented-text budgets/markers do not police the owner's own words" \
  || err "#694: the answer path applied the ask side's plain-text/budget rules"

if [ "$fail" -eq 0 ]; then
  printf '\nAll proposal-payload checks passed.\n'; exit 0
else
  printf '\nproposal-payload checks FAILED.\n' >&2; exit 1
fi
