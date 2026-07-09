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

if [ "$fail" -eq 0 ]; then
  printf '\nAll harvest checks passed.\n'; exit 0
else
  printf '\nharvest checks FAILED.\n' >&2; exit 1
fi
