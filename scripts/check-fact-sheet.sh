#!/usr/bin/env sh
# check-fact-sheet.sh — verify source-pointed fact-sheet extraction (Story 3.2).
# POSIX shell + stdlib Python. Builds a real git fixture so pointer resolution
# (sha exists, path exists at sha, line in range, quote verbatim) is exercised,
# not just the entry syntax.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VAL="scripts/validate-fact-sheet.py"
SKILL="skills/harvest/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 0. Validator compiles.
python3 -c "import py_compile; py_compile.compile('$root/$VAL', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Contract documented in the skill (format, KIND set, pinning, verbatim quote).
grep -q 'CLAIM / SOURCE / KIND' "$SKILL" && ok "skill documents CLAIM / SOURCE / KIND format" || err "format not documented"
grep -q 'result, decision, number, quote, event' "$SKILL" && ok "skill documents the KIND set" || err "KIND set not documented"
# Two-places-together (#438): the harvest SKILL enumeration and the validator's
# KINDS set are the two enforcement copies of the closed set — both must carry
# the four narrative kinds, or they have drifted (a defect).
for nk in chronology motivation cost reversal; do
  grep -q "$nk" "$SKILL" || err "harvest SKILL missing narrative KIND: $nk"
  grep -q "\"$nk\"" "$VAL" || err "validate-fact-sheet.py KINDS missing narrative KIND: $nk"
done
grep -q 'chronology' "$SKILL" && grep -q '"chronology"' "$VAL" \
  && ok "narrative KINDs enforced in lockstep (harvest SKILL + validate-fact-sheet.py, #438)" \
  || err "narrative KINDs not enforced in both places (two-places-together, #438)"
grep -q 'path:line@sha' "$SKILL" && ok "skill documents commit-pinned pointers" || err "pinning not documented"
grep -q 'verbatim' "$SKILL" && ok "skill requires verbatim quotes" || err "verbatim rule not documented"
grep -q 'validate-fact-sheet.py' "$SKILL" && ok "skill wires in the validator" || err "validator not referenced"

# --- git fixture -----------------------------------------------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
h="$work/host"; mkdir -p "$h"
git -C "$h" init -q
# lines 4-5 are a naturally two-line quote (e.g. a wrapped table cell), #119.
# line 6 carries DOUBLED internal whitespace (#154: matching is whitespace-normalized).
printf 'intro line\nThroughput doubled under load\n"exact quoted words"\nfirst half of a wrapped\nsecond half of the cell\nthe  build   cache saved minutes\n' > "$h/notes.md"
git -C "$h" add notes.md
git -C "$h" -c user.email=t@e -c user.name=t commit -q -m init
sha=$(git -C "$h" rev-parse HEAD)
printf 'sources:\n  - path: .\n' > "$h/writing-sources.yaml"
# an undeclared sibling git repo
mkdir -p "$work/secret"; git -C "$work/secret" init -q; echo x > "$work/secret/x.md"
git -C "$work/secret" add x.md; git -C "$work/secret" -c user.email=t@e -c user.name=t commit -q -m s

emit() { printf '%s\n' "$1" > "$work/fs.md"; }
V() { python3 "$root/$VAL" "$work/fs.md" --root "$h" >/dev/null 2>&1; }          # exit 0 = all valid
reason() { python3 "$root/$VAL" "$work/fs.md" --root "$h" 2>&1; }

# 2. Valid entries — each SOURCE form + verbatim quote — all pass.
emit "- Throughput doubled under load / notes.md:2@$sha / result"
V && ok "valid: pinned path:line@sha (result)" || err "valid pinned pointer rejected"
emit '- "exact quoted words" / notes.md:3@'"$sha"' / quote'
V && ok "valid: verbatim quote resolves at the pinned line" || err "verbatim quote rejected"
emit "- Refactor shipped / $sha / decision"
V && ok "valid: bare commit sha in a declared repo" || err "commit-sha source rejected"
emit "- Prior art / https://example.com/a / event"
V && ok "valid: URL source" || err "URL source rejected"

# 2b. den:<ledger-id>@<run> — a Tanuki Den finding (Story 13.51). A pinned
#     pointer type whose pin is the judging RUN, not a commit: the Den ledger
#     is not a git tree, so the FORM is the contract (as for a URL) and the
#     validator never reaches into Tanuki's state to resolve it.
emit "- flaky gate, type friction, recurrence 4, accepted / den:f-19@r-208 / event"
V && ok "valid: den:<ledger-id>@<run> source (Story 13.51)" || err "den pointer rejected"
emit "- finding / den:f_19.a-2@2026-07-17.r3 / decision"
V && ok "valid: den pointer with the full [A-Za-z0-9._-] id/run charset" || err "den charset rejected"
emit "- Unpinned den / den:f-19 / event"
reason | grep -q 'not pinned to a run' && ok "reject: bare den:<id> (unpinned) names the fix" \
  || err "unpinned den pointer accepted"

# 3. Structural rejections.
emit "- Missing the other fields"
reason | grep -q 'malformed' && ok "reject: missing SOURCE/KIND (malformed)" || err "malformed entry accepted"
emit "- Some claim / notes.md:2@$sha / opinion"
reason | grep -q "invalid KIND" && ok "reject: KIND outside the closed set" || err "bad KIND accepted"

# 4. Pinning + resolution rejections.
emit "- Unpinned / notes.md:2 / result"
reason | grep -q 'not pinned to a commit' && ok "reject: bare path:line (unpinned)" || err "unpinned pointer accepted"
emit "- Past end / notes.md:99@$sha / number"
reason | grep -q 'out of range' && ok "reject: line number past end of file at sha" || err "out-of-range line accepted"
emit "- Drifted / Throughput TRIPLED / notes.md:2@$sha / quote"
# (quote text differs from the source line)
emit '- "words that are not there" / notes.md:2@'"$sha"' / quote'
reason | grep -q 'verbatim' && ok "reject: quote not matching the source line verbatim" || err "non-verbatim quote accepted"

# 5. Scope consistency with Story 3.1 — undeclared repo is unsourceable.
emit "- Leaked / ../secret/x.md:1@$sha / event"
reason | grep -q 'outside the declared repos' && ok "reject: pointer into an undeclared repo" || err "undeclared-repo pointer accepted"

# 5b. SOURCE grammar (#119): single-line for facts, multi-line spans for quotes.
emit "- Ranged fact / notes.md:2-3@$sha / result"
reason | grep -Eq 'single line|split 2-3' && ok "reject: line range on a non-quote KIND names the fix" || err "range on a fact accepted"
emit '- "first half of a wrapped second half of the cell" / notes.md:4-5@'"$sha"' / quote'
V && ok "valid: multi-line quote span matches joined physical lines" || err "valid multi-line quote span rejected"
emit '- "text that is not on those lines" / notes.md:4-5@'"$sha"' / quote'
reason | grep -q 'verbatim' && ok "reject: multi-line quote not matching the span verbatim" || err "non-verbatim multi-line quote accepted"
emit "- Collapsed range / notes.md:4-4@$sha / quote"
reason | grep -q 'single line' && ok "reject: single-line range steered to path:line@sha" || err "collapsed range accepted"
emit '- "wrapped" / notes.md:5-4@'"$sha"' / quote'
reason | grep -q 'backwards' && ok "reject: backwards quote range" || err "backwards range accepted"
emit "- Unpinned range / notes.md:4-5 / quote"
reason | grep -q 'not pinned to a commit' && ok "reject: unpinned line range" || err "unpinned range accepted"

# 5c. Narrative KINDs (#438): the closed set is nine; the four narrative kinds
#     accept a span pointer like quote; an out-of-set KIND is still rejected.
emit "- Chose backoff because throughput doubled / notes.md:2@$sha / motivation"
V && ok "valid: narrative KIND (motivation) with a single-line pointer (#438)" || err "narrative single-line rejected"
emit "- Rollout unfolded over two steps / notes.md:4-5@$sha / chronology"
V && ok "valid: narrative KIND (chronology) may span physical lines (#438)" || err "narrative span rejected"
emit "- Ranged rationale / notes.md:2-3@$sha / motivation"
V && ok "valid: 2-3 range accepted for motivation though rejected for result (span-eligibility, #438)" || err "narrative KIND span on real lines rejected"
emit "- Bad / notes.md:2@$sha / narrative"
reason | grep -q "invalid KIND" && ok "reject: a KIND outside the nine is still rejected (#438)" || err "out-of-set KIND accepted"

# 5d. Verbatim REJECT names the cause + prefixed quotes are rejected (#137).
emit '- Decision from batch 16: "exact quoted words" / notes.md:3@'"$sha"' / quote'
reason | grep -qi 'verbatim source text only' \
  && ok "reject: prefixed/labelled quote rejected with the verbatim-only cause named (#137)" \
  || err "prefixed quote accepted or REJECT message generic"
# a partial quote (CLAIM is a sub-span of the source line) still passes.
emit '- exact quoted / notes.md:3@'"$sha"' / quote'
V && ok "valid: partial quote (CLAIM is a sub-span of the source line) still accepted" || err "partial quote wrongly rejected"
# the non-quote range REJECT names the constraint AND the fix.
emit "- Ranged fact / notes.md:2-3@$sha / number"
reason | grep -Eq 'single line for KIND|split 2-3' && ok "reject: non-quote range names constraint + fix (#137)" || err "non-quote range REJECT generic"

# 5e. Whitespace-normalized quote matching (#154, Story 13.17).
# a) a claim with single spaces matches a source line carrying doubled whitespace.
emit '- "the build cache saved minutes" / notes.md:6@'"$sha"' / quote'
V && ok "valid: quote matches across normalized whitespace (doubled spaces collapsed)" \
  || err "whitespace-normalized single-line quote rejected"
# b) a real sentence spanning a physical-line wrap is quotable by its true boundary.
emit '- "first half of a wrapped second half of the cell" / notes.md:4-5@'"$sha"' / quote'
V && ok "valid: wrapped-sentence quote matches its true boundary (normalized span)" \
  || err "wrapped-sentence quote rejected"
# c) the no-extra-text guarantee still holds under normalization (prefix rejected).
emit '- Decision: "the build cache saved minutes" / notes.md:6@'"$sha"' / quote'
reason | grep -qi 'verbatim source text only' \
  && ok "reject: prefixed quote still rejected under whitespace normalization (#137 preserved)" \
  || err "prefixed quote accepted under normalization"
# d) a genuine mismatch REJECT shows the ACTUAL source line so the fix is visible.
emit '- "words that are simply not present" / notes.md:6@'"$sha"' / quote'
reason | grep -q 'cache saved minutes' \
  && ok "reject: mismatch REJECT includes the actual source line (#154)" \
  || err "mismatch REJECT does not show the source line"
# and the same for a multi-line span mismatch.
emit '- "text that is not on those lines" / notes.md:4-5@'"$sha"' / quote'
reason | grep -q 'first half of a wrapped second half of the cell' \
  && ok "reject: multi-line mismatch REJECT shows the spanned source lines" \
  || err "multi-line mismatch REJECT does not show the span"

# 5f. Coverage manifest (#514): disclose read-vs-skipped, accounting closes.
grep -q 'require-coverage' "$SKILL" && ok "skill documents the coverage manifest / --require-coverage" || err "coverage manifest not documented in skill"
COV_OK='# Fact sheet: t

## Coverage
pin: '"$sha"'
matched: 2
read: notes.md (1)
skipped: other.md (over the read ceiling — surfaced to owner)

- Throughput doubled under load / notes.md:2@'"$sha"' / result'
# a) a well-formed manifest passes, entries still validated
printf '%s\n' "$COV_OK" > "$work/fs.md"
python3 "$root/$VAL" "$work/fs.md" --root "$h" --require-coverage >/dev/null 2>&1 \
  && ok "valid: well-formed coverage manifest + entry passes under --require-coverage" \
  || err "well-formed coverage manifest rejected"
# b) missing manifest is rejected only under --require-coverage
printf -- '- Throughput doubled under load / notes.md:2@%s / result\n' "$sha" > "$work/fs.md"
python3 "$root/$VAL" "$work/fs.md" --root "$h" >/dev/null 2>&1 \
  && ok "no manifest passes WITHOUT --require-coverage (back-compat)" \
  || err "missing manifest rejected without the flag (back-compat broken)"
python3 "$root/$VAL" "$work/fs.md" --root "$h" --require-coverage 2>&1 | grep -q 'missing.*Coverage' \
  && ok "reject: missing manifest under --require-coverage names the fix" \
  || err "missing manifest accepted under --require-coverage"
# c) accounting must close (read + skipped == matched)
printf '# Fact sheet: t\n\n## Coverage\npin: %s\nmatched: 5\nread: notes.md (1)\nskipped: none\n\n- Throughput doubled under load / notes.md:2@%s / result\n' "$sha" "$sha" > "$work/fs.md"
python3 "$root/$VAL" "$work/fs.md" --root "$h" 2>&1 | grep -q 'accounting does not close' \
  && ok "reject: coverage accounting that does not close (matched != read+skipped)" \
  || err "unbalanced coverage accounting accepted"
# d) `skipped: none` with a skipped file is contradictory
printf '# Fact sheet: t\n\n## Coverage\npin: %s\nmatched: 1\nread: notes.md (1)\nskipped: none\nskipped: x.md (r)\n' "$sha" > "$work/fs.md"
python3 "$root/$VAL" "$work/fs.md" --root "$h" 2>&1 | grep -q 'cannot coexist' \
  && ok "reject: 'skipped: none' contradicting a skipped-file line" \
  || err "contradictory skipped accounting accepted"
# e) a malformed manifest line is rejected even without the flag (validate-if-present)
printf '# Fact sheet: t\n\n## Coverage\npin: %s\nmatched: 1\nread: notes.md 1 entry\n' "$sha" > "$work/fs.md"
python3 "$root/$VAL" "$work/fs.md" --root "$h" 2>&1 | grep -q 'unrecognized line' \
  && ok "reject: malformed manifest line rejected even without --require-coverage" \
  || err "malformed manifest line accepted"

# 6. Exit status is a hard gate + --rejected lists rejects for Story 3.3.
printf -- '- Good / notes.md:2@%s / result\n- Bad / nope:1 / result\n' "$sha" > "$work/fs.md"
python3 "$root/$VAL" "$work/fs.md" --root "$h" >/dev/null 2>&1 && err "exit 0 despite a rejected entry" \
  || ok "non-zero exit when any entry is rejected (hard gate)"
python3 "$root/$VAL" "$work/fs.md" --root "$h" --rejected 2>/dev/null | grep -q 'Bad' \
  && ok "--rejected lists the rejects (feeds the needs-owner list, Story 3.3)" || err "--rejected did not list rejects"

if [ "$fail" -eq 0 ]; then
  printf '\nAll fact-sheet checks passed.\n'; exit 0
else
  printf '\nfact-sheet checks FAILED.\n' >&2; exit 1
fi
