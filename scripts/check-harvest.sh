#!/usr/bin/env sh
# check-harvest.sh — verify the harvest skill scaffold, standalone invocation,
# and source-scope enforcement (Story 3.1). POSIX shell + stdlib Python.
#
# The mechanical heart is the `files` enumerator (the hard read boundary), which
# is exercised against a fixture host repo with a declared sibling (include-
# filtered), an UNDECLARED sibling, a .git dir, and an escaping symlink.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/harvest/SKILL.md"
RES="scripts/resolve-writing-sources.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -qF -- "$1" "$SKILL"; then ok "$2"; else err "$2 (missing: $1)"; fi; }

# 1. Skill scaffold: exists, has frontmatter, is standalone-invocable.
[ -f "$SKILL" ] && ok "present: $SKILL" || { err "missing $SKILL"; printf '\nFAILED.\n' >&2; exit 1; }
head -1 "$SKILL" | grep -q '^---$' && ok "SKILL.md has YAML frontmatter" || err "no frontmatter"
grep -q '^name: harvest' "$SKILL" && ok "frontmatter name: harvest" || err "missing name"
grep -q '^description:' "$SKILL" && ok "frontmatter description present (invocable)" || err "missing description"
has "Standalone" "documents standalone invocation"

# 2. Scope resolution is delegated to the hard boundary (not advisory prose).
has "resolve-writing-sources.py files" "invokes the files scope enumerator"
grep -q 'CLAUDE_PLUGIN_ROOT' "$SKILL" && ok "references the script via a portable path variable" || err "no portable script path"
has "Read nothing outside this list" "instructs reading only the enumerated files"
has "never read" "states undeclared repos are never read"

# 3. Fail-closed guidance.
has "Fail closed" "documents fail-closed behavior"

# 4. Output contract (same standalone + pipeline; every fact has a pointer).
has "output contract" "defines a fact-sheet output contract"
has "source pointer" "every fact carries a source pointer"
grep -q 'path:line\|path/to/file:line' "$SKILL" && ok "contract shows a file:line pointer" || err "no pointer example"

# 4b. github-issues typed source (Story 13.50): declared opt-in, read-only,
#     URL-sourced facts, data-not-judgment, degrade-never-fail.
has "typed-sources" "enumerates typed entries via the resolver"
has "github-issues" "documents the github-issues source"
has "read-only and one-way" "issue read is read-only, one-way"
has "nothing is ever written" "nothing is written to any issue"
has "SOURCE is the issue URL" "issue facts carry the issue URL as SOURCE"
has "quoted as data with the fact" "recurrence/disposition quoted as data"
has "never used to amplify" "counts never amplify a claim"
has "NEEDS-OWNER" "open/deferred findings route to NEEDS-OWNER"
has "github-issues source skipped" "unreachable API degrades with one logged line"
has "Degrade, never fail" "degrade is never a failure"
# The stage-2 triage side of the rule lives in the draft skill (not inference).
grep -qF "13.50" "skills/draft-article/SKILL.md" \
  && grep -qF "eligible grounding for" "skills/draft-article/SKILL.md" \
  && ok "stage-2 triage states the issue-fact grounding rule" \
  || err "draft-article triage missing the issue-fact rule"

# 4c. tanuki-den typed source (Story 13.51): declared opt-in, bounded read-only
#     reader, den: pointer form documented beside the others, data-not-judgment,
#     degrade-never-fail, no fallback to undeclared producer state.
has "tanuki-den" "documents the tanuki-den source"
has "den:<ledger-id>@<run>" "den pointer form documented"
has "bounded reader" "den read goes through a bounded reader"
has "no write path exists" "no write path into Tanuki's state"
has "never amplifies recurrence into significance" "recurrence is never amplified"
has "tanuki-den source skipped" "missing/unreadable Den degrades with one logged line"
has "fallback to reading undeclared producer state" "never falls back to undeclared producer state"
# The pointer grammar lists den: beside path:line@sha / sha / URL.
grep -qF 'den:<ledger-id>@<run>' "$SKILL" && grep -qF 'path:line@sha' "$SKILL" \
  && ok "den: form documented beside the file/sha/URL pointer forms" \
  || err "den form not documented in the pointer grammar"
# The validator accepts the form (the grammar is shared, not restated).
grep -qF 'den:' "scripts/validate-fact-sheet.py" \
  && ok "validate-fact-sheet accepts the den pointer form" \
  || err "validator missing the den pointer form"
# The Den triage rule reaches the draft skill too (same rules as 13.50).
grep -qF "13.51" "skills/draft-article/SKILL.md" \
  && grep -qF "recurrence count is data" "skills/draft-article/SKILL.md" \
  && ok "stage-2 triage states the Den-fact rule (recurrence never amplified)" \
  || err "draft-article triage missing the Den-fact rule"

# --- behavioral: the source-scope enumerator (the enforced boundary) --------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/host/src" "$work/host/.git" \
         "$work/research-notes/notes/deep" "$work/research-notes/private" \
         "$work/secret-repo"
echo code   > "$work/host/src/a.py"
echo gitmeta> "$work/host/.git/HEAD"
echo n1     > "$work/research-notes/notes/n1.md"
echo n2     > "$work/research-notes/notes/deep/n2.md"
echo priv   > "$work/research-notes/private/p.md"
echo SECRET > "$work/secret-repo/s.md"
ln -s "$work/secret-repo/s.md" "$work/host/escape.md"   # symlink escaping declared scope
cat > "$work/host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
  - path: ../research-notes
    include: ["notes/**"]
YAML
files=$(python3 "$root/$RES" --root "$work/host" files)
inlist()   { printf '%s\n' "$files" | grep -qF -- "$1"; }

inlist "/host/src/a.py"                && ok "reads declared host-repo files" || err "host file missing"
inlist "/research-notes/notes/n1.md"   && ok "reads declared sibling under include glob" || err "sibling include missing"
inlist "/research-notes/notes/deep/n2.md" && ok "include glob is recursive (notes/**)" || err "recursive glob failed"
inlist "/research-notes/private/p.md"  && err "read a sibling file OUTSIDE the include glob" || ok "include acts as an allowlist (private/ excluded)"
inlist "/secret-repo/"                 && err "read an UNDECLARED sibling repo" || ok "undeclared sibling repo never read"
inlist "/host/.git/"                   && err "descended into .git/" || ok ".git/ pruned"
inlist "/secret-repo/s.md"             && err "followed a symlink escaping the declared root" || ok "escaping symlink excluded"

# 5. Fail-closed: no / non-existent sources -> read nothing (not the filesystem).
mkdir "$work/bare"
n=$(python3 "$root/$RES" --root "$work/bare" files | wc -l | tr -d ' ')
[ "$n" -eq 0 ] && ok "no writing-sources.yaml -> zero files (fail closed)" || err "fail-open: $n files with no sources"
printf 'sources:\n  - path: ../nope-does-not-exist\n' > "$work/bare/writing-sources.yaml"
n=$(python3 "$root/$RES" --root "$work/bare" files | wc -l | tr -d ' ')
[ "$n" -eq 0 ] && ok "non-existent declared path -> zero files (fail closed)" || err "fail-open on non-existent path: $n"

# 6. Backing helper is stdlib-only Python (no JS/TS) — compiles clean.
python3 -c "import py_compile; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null \
  && ok "harvest's backing helper is stdlib-only Python (compiles)" || err "helper syntax error"
python3 -c "import py_compile; py_compile.compile('$root/scripts/pin-source.py', doraise=True)" 2>/dev/null \
  && ok "pin-source.py is stdlib-only Python (compiles)" || err "pin-source.py syntax error"

# 7. @sha pin helper (Story 13.15, #159): path:line -> path:line@HEAD keeping the
#    caller's OWN line numbers, verified committed-at-HEAD, and the emitted pointer
#    validates against the fact-sheet contract.
has "pin-source.py" "documents the @sha pin helper in the skill"

# 7b. Validator convergence (Story 13.22, #206): the emitter is the only
#     sanctioned construction path, validation is a confirmation pass, and
#     repair is bounded at two passes with NEEDS-OWNER routing — the skill
#     never instructs an unbounded validate-loop.
has "--emit-entry" "skill routes entry construction through the emitter"
has "only sanctioned construction path" "emitter is stated as the only sanctioned path"
has "confirmation pass" "validator run is framed as a confirmation pass"
has "bounded at two validator passes" "repair loop is bounded at two passes"
grep -q "never a third" "$SKILL" && ok "third repair pass is explicitly forbidden" \
  || err "no explicit never-a-third-pass rule"
grep -q "REJECT reason as the REASON" "$SKILL" \
  && ok "post-bound rejects route to NEEDS-OWNER with their REJECT reason" \
  || err "NEEDS-OWNER routing for post-bound rejects not stated"
grep -q "budget-triage signal" "$SKILL" && ok "breach surfaces the budget-triage signal" \
  || err "budget-triage signal on breach not stated"
grep -q "completion" "$SKILL" && ok "rerouted entries surface in the completion summary" \
  || err "completion-summary surfacing not stated"

PIN="$root/scripts/pin-source.py"
VFS="$root/scripts/validate-fact-sheet.py"
pin=$(mktemp -d); trap 'rm -rf "$work" "$pin"' EXIT
(
  cd "$pin"
  git init -q
  git config user.email t@e.st; git config user.name t
  printf 'sources:\n  - path: .\n' > writing-sources.yaml
  printf 'alpha line one\nwe deliberately leak no test scenarios\ngamma line three\n' > doc.md
  git add -A; git commit -qm init
) >/dev/null 2>&1

# a) single line -> path:line@sha, preserving the CALLER's line number (#159).
out=$(python3 "$PIN" --root "$pin" doc.md:2 2>/dev/null)
printf '%s\n' "$out" | grep -Eq '^doc\.md:2@[0-9a-f]{7,40}$' \
  && ok "pins path:line to path:line@sha with the caller's line number preserved" \
  || err "pin form/line wrong: '$out' (expected doc.md:2@sha)"

# b) batched: two lines in one file -> two pointers, one call
out=$(python3 "$PIN" --root "$pin" doc.md:1 doc.md:3 2>/dev/null | grep -c '@') || true
[ "$out" = "2" ] && ok "batches multiple lines from one file" || err "expected 2 pinned, got $out"

# c) the emitted pointer validates as a quote against validate-fact-sheet.py
pinned=$(python3 "$PIN" --root "$pin" doc.md:2 2>/dev/null)
sheet="# Fact sheet: t

- we deliberately leak no test scenarios / $pinned / quote
"
if printf '%s' "$sheet" | python3 "$VFS" --root "$pin" >/dev/null 2>&1; then
  ok "pinned pointer validates against the fact-sheet contract"
else
  err "pinned pointer rejected by validate-fact-sheet.py ($pinned)"
fi

# d) an uncommitted line cannot be pinned -> skipped, non-zero, nothing emitted
printf 'brand new uncommitted line\n' >> "$pin/doc.md"
if python3 "$PIN" --root "$pin" doc.md:4 >/tmp/pin_out.$$ 2>/dev/null; then
  err "uncommitted line was pinned (should fail)"
else
  [ -s /tmp/pin_out.$$ ] && err "emitted a pointer for an uncommitted line" \
    || ok "uncommitted line is skipped, not pinned"
fi
rm -f /tmp/pin_out.$$

# e) #159 regression: when a line's CURRENT number differs from its blame-origin
#    number (an insertion shifted it), the pointer must carry the CURRENT line, not
#    the origin line, and still validate. Reset d)'s edit, then prepend + commit so
#    the quote moves from line 2 to line 4 (origin line stays 2).
git -C "$pin" checkout -- doc.md 2>/dev/null
{ printf 'inserted top A\ninserted top B\n'; cat "$pin/doc.md"; } > "$pin/doc.md.new"
mv "$pin/doc.md.new" "$pin/doc.md"
git -C "$pin" add doc.md >/dev/null 2>&1
git -C "$pin" commit -qm "prepend two lines (shifts the quote to line 4)" >/dev/null 2>&1
out=$(python3 "$PIN" --root "$pin" doc.md:4 2>/dev/null)
printf '%s\n' "$out" | grep -Eq '^doc\.md:4@[0-9a-f]{7,40}$' \
  && ok "#159: emitted line is the caller's current line (4), not the blame-origin line (2)" \
  || err "#159 regression: expected doc.md:4@sha, got '$out'"
printf '%s\n' "# Fact sheet: t
" "- we deliberately leak no test scenarios / $out / quote" \
  | python3 "$VFS" --root "$pin" >/dev/null 2>&1 \
  && ok "#159: caller-line HEAD pointer resolves/validates at the shifted line" \
  || err "#159: shifted-line pointer rejected ($out)"
rm -f /tmp/pin_out.$$

# 8. --emit-entry (Story 13.21, #207): the helper emits entry-ready
#    `- CLAIM / SOURCE / KIND` lines with the verbatim committed text, and the
#    round-trip through validate-fact-sheet.py rejects nothing — acceptance is
#    reached by copying tool output, never by guessing (validator convergence).
git -C "$pin" checkout -- doc.md 2>/dev/null

# a) single line, default KIND quote -> complete entry that validates unchanged
out=$(python3 "$PIN" --root "$pin" --emit-entry doc.md:4 2>/dev/null)
[ "$out" = "- we deliberately leak no test scenarios / $(python3 "$PIN" --root "$pin" doc.md:4 2>/dev/null) / quote" ] \
  && ok "emit-entry: single-line quote entry carries the verbatim text" \
  || err "emit-entry single-line wrong: '$out'"

# b) round-trip: emitted entries (single + range) validate with zero rejects
{ printf '# Fact sheet: t\n\n'
  python3 "$PIN" --root "$pin" --emit-entry doc.md:4 doc.md:1-2 2>/dev/null
} | python3 "$VFS" --root "$pin" >/dev/null 2>&1 \
  && ok "emit-entry: emitted entries round-trip through validate-fact-sheet.py (0 rejected)" \
  || err "emit-entry round-trip: an emitted entry was rejected"

# c) range entry joins the spanned lines verbatim with the range SOURCE form
out=$(python3 "$PIN" --root "$pin" --emit-entry doc.md:1-2 2>/dev/null)
printf '%s\n' "$out" | grep -Eq '^- inserted top A inserted top B / doc\.md:1-2@[0-9a-f]{7,40} / quote$' \
  && ok "emit-entry: range quote joins spanned lines verbatim" \
  || err "emit-entry range wrong: '$out'"

# d) --kind overrides KIND, keeps a single-line pinned SOURCE, and says on
#    stderr that the CLAIM is a placeholder to replace
out=$(python3 "$PIN" --root "$pin" --emit-entry --kind number doc.md:4 2>/dev/null)
printf '%s\n' "$out" | grep -Eq '^- .+ / doc\.md:4@[0-9a-f]{7,40} / number$' \
  && ok "emit-entry: --kind number emits a number entry" \
  || err "emit-entry --kind wrong: '$out'"
python3 "$PIN" --root "$pin" --emit-entry --kind number doc.md:4 2>&1 >/dev/null | grep -q "placeholder" \
  && ok "emit-entry: non-quote KIND flags the CLAIM as a placeholder to replace" \
  || err "emit-entry: no placeholder note for non-quote KIND"

# e) a range with a non-quote KIND is refused (the validator would reject it)
if python3 "$PIN" --root "$pin" --emit-entry --kind number doc.md:1-2 >/tmp/emit_out.$$ 2>/dev/null; then
  err "emit-entry: range with non-quote KIND was emitted (should be refused)"
else
  [ -s /tmp/emit_out.$$ ] && err "emit-entry: emitted an entry for a non-quote range" \
    || ok "emit-entry: range with non-quote KIND is refused, nothing emitted"
fi
rm -f /tmp/emit_out.$$

# f) an uncommitted line is skipped in emit mode too (same degradation as pinning)
printf 'uncommitted emit line\n' >> "$pin/doc.md"
if python3 "$PIN" --root "$pin" --emit-entry doc.md:6 >/tmp/emit_out.$$ 2>/dev/null; then
  err "emit-entry: uncommitted line produced an entry (should fail)"
else
  [ -s /tmp/emit_out.$$ ] && err "emit-entry: emitted an entry for an uncommitted line" \
    || ok "emit-entry: uncommitted line is skipped, not emitted"
fi
rm -f /tmp/emit_out.$$
git -C "$pin" checkout -- doc.md 2>/dev/null

# g) stdin batching works in emit mode (one entry per piped pointer)
out=$(printf 'doc.md:4\ndoc.md:5\n' | python3 "$PIN" --root "$pin" --emit-entry 2>/dev/null | grep -c '^- ') || true
[ "$out" = "2" ] && ok "emit-entry: stdin pointers emit one entry each" \
  || err "emit-entry: expected 2 entries from stdin, got $out"

if [ "$fail" -eq 0 ]; then
  printf '\nAll harvest checks passed.\n'; exit 0
else
  printf '\nharvest checks FAILED.\n' >&2; exit 1
fi
