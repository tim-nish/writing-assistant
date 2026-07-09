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
grep -q 'path:line@sha' "$SKILL" && ok "skill documents commit-pinned pointers" || err "pinning not documented"
grep -q 'verbatim' "$SKILL" && ok "skill requires verbatim quotes" || err "verbatim rule not documented"
grep -q 'validate-fact-sheet.py' "$SKILL" && ok "skill wires in the validator" || err "validator not referenced"

# --- git fixture -----------------------------------------------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
h="$work/host"; mkdir -p "$h"
git -C "$h" init -q
printf 'intro line\nThroughput doubled under load\n"exact quoted words"\n' > "$h/notes.md"
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
