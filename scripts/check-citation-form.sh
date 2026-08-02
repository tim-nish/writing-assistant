#!/usr/bin/env sh
# parallel-safe
# tier: inner — one branch-diff read, one check-skill-budget.sh invocation,
#   and two mktemp fixture repos; measured at adoption (2026-08-02) well
#   under the runner's INNER_MS ceiling.
# covers: specs/** skills/**
# removal-signal: the "Durable citation form, denied at the write layer"
#   clause (SPEC-writing-assistant §Constraints, #1322) is overturned per its
#   own recorded conditions — an anchor class is shown to rot here (a CAP-n
#   renumbering, an issue-number reuse), or a ruling puts amendment-block
#   citations outside the convention. The guard retires with the clause.
# check-citation-form.sh — a NEW unpinned `file:line` may not enter
# relocatable text (Story 20.184, #1324; umbrella #1322; SPEC-writing-assistant
# §Constraints "Durable citation form, denied at the write layer", amendment
# 2026-08-02 (#1322) clauses (1)-(6)).
#
# THE SUBJECT IS INTRODUCED TEXT, NEVER STANDING CONTENT: only added lines of
# the branch diff against its merge-base (plus the uncommitted working tree)
# are inspected, and an added line whose exact text appears among the same
# diff's REMOVED lines is a relocation, not an introduction — admitted, or
# this guard would forbid the one remedy a ceiling trip permits.
# RELOCATABLE IS DERIVED, never enumerated: the files check-skill-budget.sh
# itself reports on. THE EXEMPTION SET IS CLOSED AT THREE — the pinned form
# `path:line@sha` (>=7 hex, shape-checked, never resolved), fenced code
# blocks, and an adjacent `<!-- positional-cite: <why> -->` with a non-empty
# reason. A fourth exemption is an AMENDMENT to the clause, not a code change
# here. A clean run reports the SCOPE it inspected (diff range, file and line
# counts) and never a claim about the class: silence means "no introduced
# violation in this diff", never "no violation".
#
# POSIX sh + awk only — the loop's gate runs every check as `sh "$t"` (#866).

set -u

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
SELF="$SCRIPTDIR/$(basename "$0")"
BUDGET="$SCRIPTDIR/check-skill-budget.sh"

# ---------------------------------------------------------------------------
# Scan mode (internal recursion): sh check-citation-form.sh --scan <root>
#   <base> [<head>]. With <head>: the committed range base..head. Without:
#   base..working-tree, untracked Markdown included. Prints violations as
#   "FAIL: ..." to stderr and one machine-readable SUMMARY line to stdout;
#   exits 1 iff a violation was introduced.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--scan" ]; then
  sroot=$2; sbase=$3; shead=${4:-}
  cd "$sroot" || { printf 'FAIL: scan root %s unreachable\n' "$sroot" >&2; exit 1; }
  ws=$(mktemp -d) || exit 1
  trap 'rm -rf "$ws"' EXIT INT TERM

  # Relocatable set, DERIVED (clause (1)): exactly the tracked-tree Markdown
  # files the budget check itself reports a line about. The report is the
  # coupling — one path token per ok:/warn:/FAIL: line — so a tree brought
  # under the budget check becomes covered here the same day, with no edit.
  sh "$BUDGET" 2>&1 | awk '/^(ok|warn|FAIL):/ {
      for (i = 2; i <= NF; i++)
        if ($i ~ /\.md$/ && $i !~ /\*/) { print $i; break }
    }' | sort -u > "$ws/reloc"

  if [ -n "$shead" ]; then
    git diff -U0 "$sbase" "$shead" -- > "$ws/diff" 2>/dev/null
    git diff --name-only "$sbase" "$shead" -- 2>/dev/null | grep '\.md$' > "$ws/changed"
    : > "$ws/untracked"
  else
    git diff -U0 "$sbase" -- > "$ws/diff" 2>/dev/null
    git diff --name-only "$sbase" -- 2>/dev/null | grep '\.md$' > "$ws/changed"
    git ls-files --others --exclude-standard 2>/dev/null | grep '\.md$' > "$ws/untracked"
  fi

  # The relocation pool (clause (4)): every removed line of the SAME diff,
  # exact text. An added line found here verbatim introduces nothing.
  sed -n '/^---/!s/^-//p' "$ws/diff" > "$ws/pool"

  nchanged=$(sort -u "$ws/changed" "$ws/untracked" | grep -c . )
  nfiles=0; nadded=0; nviol=0

  scan_one() {  # $1 = path, $2 = "tracked" | "untracked"
    f=$1
    grep -Fxq "$f" "$ws/reloc" || return 0
    nfiles=$((nfiles + 1))
    if [ "$2" = "untracked" ]; then
      [ -f "$f" ] || return 0
      cp "$f" "$ws/content"
      awk 'END { for (i = 1; i <= NR; i++) print i }' "$f" > "$ws/added"
    else
      if [ -n "$shead" ]; then
        git show "$shead:$f" > "$ws/content" 2>/dev/null || return 0
        git diff -U0 "$sbase" "$shead" -- "$f" > "$ws/fdiff" 2>/dev/null
      else
        [ -f "$f" ] || return 0   # deleted in the working tree: nothing introduced
        cp "$f" "$ws/content"
        git diff -U0 "$sbase" -- "$f" > "$ws/fdiff" 2>/dev/null
      fi
      awk '/^@@/ {
          plus = $3; sub(/^\+/, "", plus)
          n = split(plus, p, ",")
          start = p[1] + 0; len = (n < 2 ? 1 : p[2] + 0)
          for (j = 0; j < len; j++) print start + j
        }' "$ws/fdiff" > "$ws/added"
    fi
    na=$(grep -c . "$ws/added"); nadded=$((nadded + na))
    [ "$na" -gt 0 ] || return 0
    awk -v addedfile="$ws/added" -v poolfile="$ws/pool" -v fname="$f" '
      function pc(s) { return s ~ /<!--[ \t]*positional-cite:[ \t]*[A-Za-z0-9].*-->/ }
      BEGIN {
        while ((getline l < addedfile) > 0) addset[l + 0] = 1
        close(addedfile)
        while ((getline l < poolfile) > 0) pool[l] = 1
        close(poolfile)
        v = 0
      }
      { line[NR] = $0 }
      END {
        fence = 0
        for (i = 1; i <= NR; i++) {
          t = line[i]
          if (t ~ /^ ? ? ?(```|~~~)/) { fence = 1 - fence; continue }
          if (fence) continue                    # exemption (b): fenced literal
          if (!(i in addset)) continue           # standing content, not subject
          if (t in pool) continue                # verbatim relocation, admitted
          if (pc(t) || pc(line[i - 1]) || pc(line[i + 1])) continue  # (c) marked
          rest = t
          while (match(rest, /[A-Za-z0-9_\/.-]+\.[A-Za-z][A-Za-z0-9]*:[0-9]+/)) {
            tok = substr(rest, RSTART, RLENGTH)
            rest = substr(rest, RSTART + RLENGTH)
            if (match(rest, /^-[0-9]+/)) {       # the N-M range form
              tok = tok substr(rest, 1, RLENGTH)
              rest = substr(rest, RLENGTH + 1)
            }
            pinned = 0                           # exemption (a): shape, not resolution
            if (substr(rest, 1, 1) == "@") {
              hex = substr(rest, 2)
              if (match(hex, /^[0-9a-fA-F]+/) && RLENGTH >= 7) pinned = 1
            }
            if (!pinned) {
              v++
              printf "FAIL: %s line %d introduces unpinned citation %s — pin it (%s@<sha7+>), anchor it (CAP-n / #issue), or mark a positional use with an adjacent <!-- positional-cite: <why> --> (#1322)\n", fname, i, tok, tok | "cat 1>&2"
            }
          }
        }
        close("cat 1>&2")
        exit v > 0 ? 1 : 0
      }' "$ws/content" || nviol=$((nviol + 1))
    return 0
  }

  sort -u "$ws/changed" | while read -r f; do echo "T $f"; done > "$ws/plan"
  sort -u "$ws/untracked" | while read -r f; do echo "U $f"; done >> "$ws/plan"
  while read -r kind f; do
    [ -n "$f" ] || continue
    case "$kind" in
      T) scan_one "$f" tracked ;;
      U) scan_one "$f" untracked ;;
    esac
  done < "$ws/plan"

  rangelabel="$sbase..${shead:-worktree}"
  printf 'SUMMARY range=%s reloc_files=%d changed_md=%d added_lines=%d violating_files=%d\n' \
    "$rangelabel" "$nfiles" "$nchanged" "$nadded" "$nviol"
  [ "$nviol" -eq 0 ] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Main mode: fixtures first (the check's own assertions), then the host diff.
# ---------------------------------------------------------------------------
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

WS=$(mktemp -d) || { printf 'FAIL: mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$WS"' EXIT INT TERM

commit_all() { git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" -c user.name=fixture -c user.email=fixture@invalid \
    -c commit.gpgsign=false commit -q -m "$2"; }

# --- Fixture R1: everything the guard must ADMIT (AC-1/AC-2/AC-3/AC-4) -------
R1="$WS/r1"; mkdir -p "$R1/specs/spec-a" "$R1/docs"
git init -q "$R1" || err "git init fixture R1 failed"
cat > "$R1/specs/spec-a/SPEC.md" <<'EOF'
# spec-a

Pre-existing violation, standing content: see notes.md:12 for detail.
The parser contract: the map is rejected empty, see terrain_text.py:88.
The range form too: terrain_text.py:90-99 carries the loop.
EOF
commit_all "$R1" base
# Head: an innocent edit beside the standing violation; a verbatim relocation
# of the two citation-carrying lines into a sibling file; a pinned add with a
# declared synthetic sha; a fenced literal; a marked positional use; and an
# unpinned add in docs/ (no ceiling -> not relocatable -> not selected).
cat > "$R1/specs/spec-a/SPEC.md" <<'EOF'
# spec-a

Pre-existing violation, standing content: see notes.md:12 for detail.
An unrelated innocent clarification, added on the branch.
Dated testimony: scripts/probe.py:12@8f3c2d1 and scripts/probe.py:40-44@abc1234.

```
a fenced literal is shown, not followed: example.md:10
```

<!-- positional-cite: the line number is the subject of the sentence, not an address -->
The shebang occupies script.sh:1 by definition.
EOF
cat > "$R1/specs/spec-a/amendments.md" <<'EOF'
# amendments

The parser contract: the map is rejected empty, see terrain_text.py:88.
The range form too: terrain_text.py:90-99 carries the loop.
EOF
printf 'A docs file carries no ceiling: see parser.py:40 unpinned.\n' > "$R1/docs/note.md"
r1base=$(git -C "$R1" rev-parse HEAD)
commit_all "$R1" head
r1out=$(cd "$R1" && sh "$SELF" --scan "$R1" "$r1base" 2>"$WS/r1err")
r1rc=$?
if [ "$r1rc" -eq 0 ]; then
  ok "fixture R1 admits: innocent edit beside a standing violation, verbatim relocation of unpinned citations, synthetic-sha pins, fenced literal, marked positional use, and an out-of-scope docs/ add ($r1out)"
else
  err "fixture R1 must PASS but failed — the guard is binding standing content, or denying relocation/pins/exemptions: $(cat "$WS/r1err" | tr '\n' ' ')"
fi
case "$r1out" in
  *"reloc_files=2"*) ok "fixture R1 selected exactly the 2 ceiling-covered files; docs/note.md was not selected (derived scope, clause (1))" ;;
  *) err "fixture R1 scope wrong — expected reloc_files=2 (SPEC.md + amendments.md, docs/ excluded), got: $r1out" ;;
esac

# --- Fixture R2: everything the guard must DENY (AC-2/AC-4), incl. worktree --
R2="$WS/r2"; mkdir -p "$R2/specs/spec-b"
git init -q "$R2" || err "git init fixture R2 failed"
printf '# spec-b\n\nBody.\n' > "$R2/specs/spec-b/SPEC.md"
commit_all "$R2" base
r2base=$(git -C "$R2" rev-parse HEAD)
cat >> "$R2/specs/spec-b/SPEC.md" <<'EOF'
New pointer, introduced fresh: scripts/draft-pipeline.py:100 has the loop.
Short pin: scripts/probe.py:9@abc12 is not a pin (under 7 hex).
<!-- positional-cite: --> a bare marker does not admit helper.sh:3.
EOF
commit_all "$R2" head
printf 'Uncommitted working-tree add: scripts/terrain_text.py:5 also new.\n' >> "$R2/specs/spec-b/SPEC.md"
r2out=$(cd "$R2" && sh "$SELF" --scan "$R2" "$r2base" 2>"$WS/r2err")
r2rc=$?
if [ "$r2rc" -ne 0 ]; then
  ok "fixture R2 denies the introduced grammar and exits nonzero ($r2out)"
else
  err "fixture R2 must FAIL but passed — a fresh unpinned citation reached relocatable text unchallenged"
fi
for want in "scripts/draft-pipeline.py:100" "scripts/probe.py:9" "helper.sh:3" "scripts/terrain_text.py:5"; do
  if grep -qF "$want" "$WS/r2err"; then
    ok "fixture R2 names the offender $want (file, line, token)"
  else
    err "fixture R2 did not name expected offender $want — got: $(cat "$WS/r2err" | tr '\n' ' ')"
  fi
done

# --- The host repository's own diff (the guard's real subject) ---------------
HOSTROOT=$(git -C "$SCRIPTDIR" rev-parse --show-toplevel 2>/dev/null) || {
  err "not inside a git repository"; exit 1; }
BASEREF=""
for cand in origin/main origin/master main master; do
  if git -C "$HOSTROOT" rev-parse -q --verify "$cand^{commit}" >/dev/null 2>&1; then
    BASEREF=$cand; break
  fi
done
if [ -n "$BASEREF" ]; then
  BASE=$(git -C "$HOSTROOT" merge-base HEAD "$BASEREF" 2>/dev/null) || BASE=HEAD
else
  BASE=HEAD   # no default-branch ref: the uncommitted working tree is the subject
fi
hostout=$(cd "$HOSTROOT" && sh "$SELF" --scan "$HOSTROOT" "$BASE" 2>"$WS/hosterr")
if [ $? -eq 0 ]; then
  # Scope, never class (clause (3)): this reports what was inspected in THIS
  # diff; it asserts nothing about citations already standing in the tree.
  ok "host diff clean — no introduced unpinned file:line citation in this diff ($hostout)"
else
  err "introduced unpinned citation(s) in this diff ($hostout):"
  cat "$WS/hosterr" >&2
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll citation-form checks passed (scope: this branch diff + fixtures; standing content not asserted).\n'
  exit 0
else
  printf '\ncitation-form checks FAILED.\n' >&2
  exit 1
fi
