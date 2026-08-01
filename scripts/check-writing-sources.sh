#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# covers: scripts/resolve-writing-sources.py config/writing-sources.example.yaml
# check-writing-sources.sh — verify the writing-sources schema/example and the
# draft-location resolver (Story 1.3). POSIX shell + stdlib Python only.
#
# Covers: the example declares sources[{path,include?}] + output.drafts; the
# resolver returns output.drafts, exits 3 when it is undeclared (no hardcoded
# default), writes the key back preserving comments and idempotently, resolves
# paths against the host-repo root, and enforces the CAP-2 read boundary.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

EX="config/writing-sources.example.yaml"
RES="scripts/resolve-writing-sources.py"
PY="python3 $root/$RES"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -q -- "$1" "$2"; then ok "$3"; else err "missing $3 (expected '$1' in $2)"; fi; }

# --- 0. Resolver compiles ---------------------------------------------------
if python3 -c "import py_compile,sys; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null; then
  ok "resolver compiles ($RES)"
else
  err "resolver has a syntax error ($RES)"; printf '\nChecks FAILED.\n' >&2; exit 1
fi

# --- 1. Example schema ------------------------------------------------------
[ -f "$EX" ] && ok "present: $EX" || err "missing $EX"
has 'sources:'   "$EX" 'sources list'
has '- path:'    "$EX" 'source path entry'
has 'path: .'    "$EX" 'host-repo entry (path: .)'
has 'include:'   "$EX" 'optional include globs'
has 'output:'    "$EX" 'output section'
has 'drafts:'    "$EX" 'output.drafts key'

# --- behavioral fixtures ----------------------------------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/host/sub" "$work/research-notes/notes" "$work/other-repo"
# Hermetic config home: set-draft-location migration (13.24, #213) writes to the
# machine-global config — keep it out of the developer's real ~/.config.
XDG_CONFIG_HOME="$work/xdg"; export XDG_CONFIG_HOME

# 2. draft-location resolves the declared value (absolute, host-root-relative
#    for a legacy relative value — Story 13.24, #213).
cat > "$work/host/writing-sources.yaml" <<'YAML'
# my sources
sources:
  - path: .
  - path: ../research-notes
    include: ["notes/**"]
output:
  # where drafts go
  drafts: articles/drafts/
YAML
hostreal=$(realpath "$work/host")
got=$($PY --root "$work/host" draft-location 2>/dev/null)
[ "$got" = "$hostreal/articles/drafts" ] && ok "draft-location resolves a relative value against the host root" \
  || err "draft-location returned '$got', expected '$hostreal/articles/drafts'"

# 2a. ~ and absolute values resolve as-is (external articles repo, #213).
cat > "$work/host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: ~/articles-repo/drafts/
YAML
got=$($PY --root "$work/host" draft-location 2>/dev/null)
[ "$got" = "$HOME/articles-repo/drafts" ] && ok "draft-location expands ~ (external destination)" \
  || err "draft-location tilde expansion returned '$got', expected '$HOME/articles-repo/drafts'"
# restore the original fixture verbatim (later sections rely on its comments
# and the declared sibling source)
cat > "$work/host/writing-sources.yaml" <<'YAML'
# my sources
sources:
  - path: .
  - path: ../research-notes
    include: ["notes/**"]
output:
  # where drafts go
  drafts: articles/drafts/
YAML

# 2b. --root works AFTER the subcommand too (the form the SKILLs document, #138):
#     `resolve-writing-sources.py <cmd> --root <host>` must not error.
# stdout only: the fixture uses legacy in-repo placement, which (correctly)
# emits the O1 deprecation notice on stderr (Story 13.23, #211).
after=$($PY draft-location --root "$work/host" 2>/dev/null)
[ "$after" = "$hostreal/articles/drafts" ] \
  && ok "--root accepted AFTER the subcommand (matches the documented invocation, #138)" \
  || err "--root after the subcommand failed: '$after'"
# every subcommand accepts --root in that position (no 'unrecognized arguments').
for c in draft-location sources is-declared files; do
  case "$c" in is-declared) extra=".";; *) extra="";; esac
  $PY "$c" $extra --root "$work/host" >/dev/null 2>&1
  [ $? -ne 2 ] && ok "subcommand '$c' accepts --root after it" \
    || err "subcommand '$c' rejects --root after it (argparse code 2)"
done

# 3. Missing output.drafts -> exit 3 (prompt), no fallback.
cat > "$work/host2.yaml" <<'YAML'
sources:
  - path: .
YAML
mkdir -p "$work/host2"; mv "$work/host2.yaml" "$work/host2/writing-sources.yaml"
set +e; $PY --root "$work/host2" draft-location >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 3 ] && ok "undeclared output.drafts exits 3 (asks, no default)" \
  || err "expected exit 3 for missing output.drafts, got $rc"

# 4. Write-back: lands machine-global (never in the host repo, #211/#213) — a
#    legacy in-repo file is migrated whole so the winning global copy keeps its
#    sources — preserves comments, and is idempotent.
host2real=$(realpath "$work/host2")
gfile="$work/xdg/writing-assistant/repos/$(python3 "$root/scripts/resolve-paths.py" repo-key --root "$work/host2")/writing-sources.yaml"
legacy_before=$(cat "$work/host2/writing-sources.yaml")
$PY --root "$work/host2" set-draft-location "out/drafts/" >/dev/null 2>&1
[ -f "$gfile" ] && grep -q '^sources:' "$gfile" \
  && ok "set-draft-location migrated the legacy file whole to the machine-global config" \
  || err "machine-global file missing or lost the sources block after migration"
[ "$legacy_before" = "$(cat "$work/host2/writing-sources.yaml")" ] \
  && ok "the in-repo file was not modified (nothing new written into the host repo)" \
  || err "set-draft-location wrote into the host repo"
got=$($PY --root "$work/host2" draft-location 2>/dev/null)
[ "$got" = "$host2real/out/drafts" ] && ok "second resolution reads the written key (global wins)" \
  || err "post-write draft-location returned '$got'"
before=$(cat "$gfile")
$PY --root "$work/host2" set-draft-location "out/drafts/" >/dev/null 2>&1
after=$(cat "$gfile")
[ "$before" = "$after" ] && ok "re-writing the same value is a no-op (idempotent)" \
  || err "set-draft-location was not idempotent"

# 5. Update in place preserves the value's own comment line above it (the
#    update lands in the migrated machine-global copy, #211/#213).
$PY --root "$work/host" set-draft-location "new/loc/" >/dev/null 2>&1
gfile_host="$work/xdg/writing-assistant/repos/$(python3 "$root/scripts/resolve-paths.py" repo-key --root "$work/host")/writing-sources.yaml"
grep -q '# where drafts go' "$gfile_host" && ok "inline comment above the key preserved on update" \
  || err "update dropped the key's comment"
got=$($PY --root "$work/host" draft-location 2>/dev/null)
[ "$got" = "$hostreal/new/loc" ] && ok "update replaced the value" || err "update left value '$got'"

# 6. CAP-2 boundary + host-root path resolution.
$PY --root "$work/host" is-declared "sub/file.md"  && ok "declared: file under host root (path: .)" \
  || err "file under host root should be declared"
set +e
$PY --root "$work/host" is-declared "../other-repo/x.md" >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -ne 0 ] && ok "CAP-2: undeclared sibling repo is rejected" \
  || err "undeclared sibling must not be declared"
$PY --root "$work/host" is-declared "../research-notes/notes/a.md" && ok "declared: listed sibling checkout" \
  || err "listed sibling should be declared"

# 6b. #221: a block-style include: list is a hard error, never a silent
#     fall-through to whole-tree scope. The resolver must exit 5, name the
#     offending line, and emit no files.
mkdir -p "$work/host3"
cat > "$work/host3/writing-sources.yaml" <<'YAML'
sources:
  - path: .
    include:
      - "docs/**"
      - "README.md"
output:
  drafts: out/
YAML
mkdir -p "$work/host3/docs"; : > "$work/host3/docs/a.md"; : > "$work/host3/stray.txt"
set +e
out=$($PY --root "$work/host3" files 2>"$work/host3.err"); rc=$?
set -e
[ "$rc" -eq 5 ] && ok "block-style include exits 5 (SOURCES_MALFORMED, #221)" \
  || err "block-style include: expected exit 5, got $rc"
[ -z "$out" ] && ok "block-style include reads nothing (no silent whole-tree scope)" \
  || err "block-style include still emitted files: $(printf '%s' "$out" | head -2 | tr '\n' ' ')"
grep -q 'line 3' "$work/host3.err" && grep -q 'inline form' "$work/host3.err" \
  && ok "error names the offending line and the supported form" \
  || err "error message missing line pointer or supported-form hint: $(cat "$work/host3.err" | tr '\n' ' ')"
# the valid inline form still parses (regression guard around the new branch)
got=$($PY --root "$work/host" sources 2>/dev/null | head -1)
[ -n "$got" ] && ok "inline include form still parses after #221 guard" \
  || err "inline include form broke"

# 6c. Typed source entries (Story 13.49): `type: path` default, explicit
#     types, unknown-type refusal, misplaced-key refusal, writer round-trip.
mkdir -p "$work/host4/docs"; : > "$work/host4/docs/a.md"
cat > "$work/host4/writing-sources.yaml" <<'YAML'
sources:
  - path: .
    include: ["docs/**"]
  - type: github-issues
    labels: ["tanuki:*"]
  - type: tanuki-den
output:
  drafts: out/
YAML
# Untyped {path, include} entries behave exactly as before (default typing):
# file scope comes from path entries only; typed entries never widen it.
files4=$($PY --root "$work/host4" files 2>/dev/null)
[ "$(printf '%s\n' "$files4" | grep -c .)" -eq 1 ] && printf '%s' "$files4" | grep -q 'docs/a.md' \
  && ok "typed entries never widen file scope (files = path sources only)" \
  || err "files with typed entries returned: $files4"
typed=$($PY --root "$work/host4" typed-sources 2>/dev/null)
printf '%s' "$typed" | grep -q '"type": "path"' \
  && printf '%s' "$typed" | grep -q '"type": "github-issues"' \
  && printf '%s' "$typed" | grep -q '"tanuki:\*"' \
  && printf '%s' "$typed" | grep -q '"type": "tanuki-den"' \
  && ok "typed-sources reports all three types (labels carried)" \
  || err "typed-sources output wrong: $typed"

# Unknown type -> refused fail-closed (exit 5) with a per-key diagnostic.
cat > "$work/host4/writing-sources.yaml" <<'YAML'
sources:
  - path: .
  - type: rss-feed
output:
  drafts: out/
YAML
set +e; out=$($PY --root "$work/host4" sources 2>"$work/host4.err"); rc=$?; set -e
[ "$rc" -eq 5 ] && [ -z "$out" ] && grep -q "unknown type" "$work/host4.err" \
  && grep -q "valid types" "$work/host4.err" \
  && ok "unknown type refused fail-closed with a per-key diagnostic (exit 5)" \
  || err "unknown type: rc=$rc out='$out' err=$(cat "$work/host4.err" | tr '\n' ' ')"

# Misplaced key (include on a non-path entry) -> refused with a per-key error.
cat > "$work/host4/writing-sources.yaml" <<'YAML'
sources:
  - path: .
  - type: github-issues
    include: ["docs/**"]
output:
  drafts: out/
YAML
set +e; out=$($PY --root "$work/host4" files 2>"$work/host4.err"); rc=$?; set -e
[ "$rc" -eq 5 ] && [ -z "$out" ] && grep -q 'only applies to `type: path`' "$work/host4.err" \
  && ok "misplaced include on a typed entry refused (per-key diagnostic)" \
  || err "misplaced key: rc=$rc err=$(cat "$work/host4.err" | tr '\n' ' ')"

# Writers round-trip the type key (set-sources accepts typed entries).
mkdir -p "$work/host5"
printf '%s' '[{"path":"."},{"type":"github-issues","labels":["tanuki:*"]},{"type":"tanuki-den"}]' \
  | $PY --root "$work/host5" set-sources >/dev/null 2>&1 \
  && ok "set-sources accepts typed entries" || err "set-sources refused typed entries"
rt=$($PY --root "$work/host5" typed-sources 2>/dev/null)
printf '%s' "$rt" | grep -q '"type": "github-issues"' && printf '%s' "$rt" | grep -q '"type": "tanuki-den"' \
  && ok "typed entries round-trip through the writer" \
  || err "round-trip lost the type key: $rt"
# Typed write-time validation is fail-closed too.
set +e
printf '%s' '[{"type":"tanuki-den","include":["x/**"]}]' | $PY --root "$work/host5" set-sources >/dev/null 2>"$work/host5.err"; rc=$?
set -e
[ "$rc" -eq 5 ] && grep -q 'only applies to' "$work/host5.err" \
  && ok "writer refuses a misplaced key on a typed entry" \
  || err "writer accepted a misplaced key (rc=$rc)"

# The example documents every type.
has 'type: github-issues' "$EX" 'github-issues type documented in the example'
has 'type: tanuki-den'    "$EX" 'tanuki-den type documented in the example'
has 'den:'                "$EX" 'den pointer form documented in the example'
has 'type: commits'       "$EX" 'commits type documented in the example'
has 'time_axis'           "$EX" 'the derived time axis documented in the example'

# --- 6d. Sources are TYPED BY TIME AXIS (Story 20.138, #1184) ---------------
# The axis is DERIVED from the type and never declared by hand; `commits` is a
# declared source type reading the host repo's own history; and the reading a
# declaration grounds is reported as a FACT, never as an error.
mkdir -p "$work/host6"
cat > "$work/host6/writing-sources.yaml" <<'YAML'
sources:
  - path: .
    include: ["docs/**"]
  - type: github-issues
  - type: tanuki-den
  - type: commits
    since: "2026-07-01"
    paths: ["scripts/**"]
output:
  drafts: out/
YAML
typed6=$($PY --root "$work/host6" typed-sources 2>/dev/null)
axes=$(printf '%s' "$typed6" | python3 -c 'import json,sys
print(" ".join(e["type"] + "=" + str(e["time_axis"]) for e in json.load(sys.stdin)))' 2>/dev/null)
[ "$axes" = "path=False github-issues=True tanuki-den=True commits=True" ] \
  && ok "time_axis is DERIVED per type (path false; commits/github-issues/tanuki-den true)" \
  || err "derived time_axis wrong: '$axes'"
printf '%s' "$typed6" | grep -q '"read": "thread"' \
  && printf '%s' "$typed6" | grep -q 'body-only (partial' \
  && ok "a github-issues read declares the THREAD, with the body-only projection marked partial (#1184)" \
  || err "github-issues entry does not declare the thread read / partial marker: $typed6"
printf '%s' "$typed6" | grep -q '"since": "2026-07-01"' \
  && printf '%s' "$typed6" | grep -q '"paths": \["scripts/\*\*"\]' \
  && ok "a commits entry carries its optional since:/paths: bounds" \
  || err "commits bounds lost: $typed6"

# A hand-written time_axis: is REFUSED at read time, never silently honoured.
cat > "$work/host6/writing-sources.yaml" <<'YAML'
sources:
  - path: .
    time_axis: true
output:
  drafts: out/
YAML
set +e; out=$($PY --root "$work/host6" typed-sources 2>"$work/host6.err"); rc=$?; set -e
[ "$rc" -eq 5 ] && [ -z "$out" ] && grep -q 'DERIVED FROM `type`' "$work/host6.err" \
  && ok "a hand-written time_axis: is refused at read time (exit 5, per-key diagnostic)" \
  || err "hand-written time_axis: rc=$rc out='$out' err=$(tr '\n' ' ' < "$work/host6.err")"
# ... and at write time too, so it cannot be smuggled in through the writer.
set +e
printf '%s' '[{"path":".","time_axis":true}]' | $PY --root "$work/host6" set-sources \
  >/dev/null 2>"$work/host6w.err"; rc=$?
set -e
[ "$rc" -eq 5 ] && grep -q 'DERIVED FROM `type`' "$work/host6w.err" \
  && ok "the writer refuses a hand-written time_axis too" \
  || err "writer accepted time_axis (rc=$rc)"

# `commits` reads the HOST repo's own history and pins to the sha.
mkdir -p "$work/host7"
git -C "$work/host7" init -q 2>/dev/null
git -C "$work/host7" config user.email t@e && git -C "$work/host7" config user.name t
mkdir -p "$work/host7/scripts"; printf 'x\n' > "$work/host7/scripts/a.py"
git -C "$work/host7" add -A >/dev/null 2>&1
git -C "$work/host7" commit -q -m "seed: the stated reason for the change" >/dev/null 2>&1
cat > "$work/host7/writing-sources.yaml" <<'YAML'
sources:
  - type: commits
output:
  drafts: out/
YAML
cm=$($PY --root "$work/host7" commits 2>/dev/null)
printf '%s' "$cm" | python3 -c '
import json,sys,re
d = json.load(sys.stdin)
c = d["commits"]
assert d["time_axis"] is True, d
assert len(c) == 1 and re.match(r"^[0-9a-f]{40}$", c[0]["sha"]), c
assert "stated reason" in c[0]["subject"], c
' 2>/dev/null && ok "commits reads the host repo history and pins to the commit sha" \
  || err "commits read wrong: $cm"
# No commits entry declared: an empty read, exit 0 — absence is not an error.
cat > "$work/host7/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: out/
YAML
set +e; noc=$($PY --root "$work/host7" commits 2>/dev/null); rc=$?; set -e
[ "$rc" -eq 0 ] && printf '%s' "$noc" | grep -q '"commits": \[\]' \
  && ok "no declared commits entry is an empty read, exit 0 (absence is not an error)" \
  || err "undeclared commits scope: rc=$rc out=$noc"

# The time-axis READING is a fact about the declaration, not an error: a
# declaration of `path` sources alone grounds NO episode claim and exits 0.
cat > "$work/host6/writing-sources.yaml" <<'YAML'
sources:
  - path: .
    include: ["docs/**"]
output:
  drafts: out/
YAML
set +e; rep=$($PY --root "$work/host6" time-axis 2>/dev/null); rc=$?; set -e
[ "$rc" -eq 0 ] && ok "time-axis exits 0 over a declaration that grounds no episode claim" \
  || err "time-axis exited $rc over an all-path declaration (a reading is never an error)"
printf '%s' "$rep" | grep -q 'EPISODE CLAIMS: NOT GROUNDABLE' \
  && printf '%s' "$rep" | grep -q 'FACT ABOUT THE DECLARATION' \
  && printf '%s' "$rep" | grep -q 'STATE CLAIMS: admissible against either class' \
  && ok "the reading names the fact (no episode claim, state claims unaffected)" \
  || err "time-axis report wrong: $(printf '%s' "$rep" | tr '\n' ' ')"
jrep=$($PY --root "$work/host6" time-axis --json 2>/dev/null)
printf '%s' "$jrep" | grep -q '"grounds_episode_claims": false' \
  && ok "the JSON reading carries grounds_episode_claims: false" \
  || err "time-axis --json wrong: $jrep"

# 7. Negative invariant: the resolver has no hardcoded 'drafts/' default path.
if grep -F 'drafts/' "$RES" >/dev/null 2>&1; then
  err "resolver contains a literal 'drafts/' path (possible hardcoded default): $(grep -nF 'drafts/' "$RES" | head -2 | tr '\n' ' ')"
else
  ok "no hardcoded 'drafts/' default in the resolver"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll writing-sources checks passed.\n'; exit 0
else
  printf '\nwriting-sources checks FAILED.\n' >&2; exit 1
fi
