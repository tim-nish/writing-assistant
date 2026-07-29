#!/usr/bin/env sh
# check-harvest-scope.sh — the term-derived scope PROPOSAL is deterministic,
# explains itself, and never narrows by machine judgment (Story 20.43, #906;
# SPEC-article-draft-pipeline, harvest-scope amendment 2026-07-29, #896).
#
# Runtime tier: inner-loop — assertions run against a fixture repo, with no
# pipeline rerun and no seam invocation.
# Removal signal: retire this check when the scope proposal's determinism and
# its no-ranking property are enforced by a schema over the emitted manifest
# rather than by assertions here, OR when the harvest gate stops proposing
# scope at all.
#
# POSIX shell only — the loop's gate runs every check as `sh "$t"`, so
# `set -o pipefail`, here-strings and process substitution are unavailable.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

S="scripts/harvest-scope.py"
python3 -c "import py_compile; py_compile.compile('$S', doraise=True)" 2>/dev/null \
  && ok "harvest-scope compiles" \
  || { err "harvest-scope syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
h="$work/host"; mkdir -p "$h/docs"; git -C "$h" init -q
printf 'A note about agents and the cost of things.\n' > "$h/docs/one.md"
printf 'Unrelated prose about gardening.\n'            > "$h/docs/two.md"
printf 'The slug carry-the-grade appears here.\n'      > "$h/docs/three.md"
printf 'binary\000payload with agents inside\n'        > "$h/docs/blob.bin"
printf 'sources:\n  - path: .\n    include: ["docs/**"]\noutput:\n  drafts: %s\n' "$h" > "$h/writing-sources.yaml"
git -C "$h" add -A >/dev/null 2>&1; git -C "$h" -c user.email=t@e -c user.name=t commit -qm init >/dev/null 2>&1

SCOPE() { python3 "$S" --root "$h" "$@"; }

SCOPE --terms agents,cost > "$work/a.txt" 2>"$work/a.err" \
  && ok "a scope proposal is produced" \
  || { err "scope proposal failed: $(tail -1 "$work/a.err")"; }

# --- AC1: deterministic, and independent of the caller's term ordering ------
SCOPE --terms cost,agents > "$work/b.txt" 2>/dev/null
if [ "$(cat "$work/a.txt")" = "$(cat "$work/b.txt")" ]; then
  ok "AC1: the proposal is byte-identical when the caller reorders its terms"
else
  err "AC1: term ordering changed the proposal — determinism claim is empty"
fi
SCOPE --terms agents,cost > "$work/c.txt" 2>/dev/null
if [ "$(cat "$work/a.txt")" = "$(cat "$work/c.txt")" ]; then
  ok "AC1: two runs over the same material give the same proposal"
else
  err "AC1: repeated runs differ"
fi

# --- AC2: the terms are visible, and each file names the ones that chose it -
if grep -q '^term: agents$' "$work/a.txt" && grep -q '^term: cost$' "$work/a.txt"; then
  ok "AC2: the derived terms are emitted, so the owner can see why"
else
  err "AC2: the derived terms are not shown"
fi
if grep -q 'docs/one.md [0-9]* agents,cost' "$work/a.txt"; then
  ok "AC2: a proposed file names the terms that put it there"
else
  err "AC2: a proposed file does not name its matching terms"
fi

# --- a term that matches nothing still appears; a non-matching file does not
SCOPE --terms gardening,zzznomatch > "$work/d.txt" 2>/dev/null
if grep -q '^term: zzznomatch$' "$work/d.txt"; then
  ok "AC2: a term that matched nothing is still shown (a silent term is a silent scope)"
else
  err "AC2: an unmatched term vanished from the output"
fi
if grep -q 'docs/one.md' "$work/d.txt"; then
  err "a file with no matching term was proposed anyway"
else
  ok "only files carrying a term are proposed"
fi

# --- whole-word matching: a slug is matched whole, not by its parts ---------
SCOPE --terms grade > "$work/e.txt" 2>/dev/null
if grep -q 'docs/three.md' "$work/e.txt"; then
  err "a hyphenated slug matched on one of its words — scope would over-propose"
else
  ok "matching is whole-word: 'grade' does not match the slug 'carry-the-grade'"
fi
SCOPE --terms carry-the-grade > "$work/f.txt" 2>/dev/null
grep -q 'docs/three.md' "$work/f.txt" \
  && ok "the whole slug matches its own file" \
  || err "a slug term did not match the file containing it"

# --- AC3: free text wins — an owner-named file enters regardless of match ---
SCOPE --terms zzznomatch --include "$h/docs/two.md" > "$work/g.txt" 2>/dev/null
if grep -q 'docs/two.md owner-requested' "$work/g.txt"; then
  ok "AC3: an owner-named file enters scope with no matching term, marked as owner-requested"
else
  err "AC3: an explicitly named file did not enter scope, or was not marked"
fi

# --- AC4/AC5: the manifest discloses what contributed and what was not -------
SCOPE --terms agents --json > "$work/h.json" 2>/dev/null
python3 - "$work/h.json" <<'PYEOF' && ok "AC4/AC5: the manifest names the searched repository and states that nothing out of scope was searched" || err "the coverage manifest is incomplete"
import json, sys
d = json.load(open(sys.argv[1]))
m = d["manifest"]
assert m["out_of_scope_searched"] is False, m
assert len(m["repositories"]) == 1 and m["repositories"][0]["searched"] is True, m
assert d["declared_sources"] >= 4, d["declared_sources"]
# The method is stated so a reader knows it is a term match and not a ranking.
assert "no ranking" in m["method"] and "no scoring" in m["method"], m["method"]
PYEOF

# --- a binary declared source is skipped as a correctness matter, DISCLOSED -
python3 - "$work/h.json" <<'PYEOF' && ok "a binary declared source is skipped and NAMED — a byte coincidence is not a term match" || err "binary handling is wrong or silent"
import json, sys
d = json.load(open(sys.argv[1]))
skipped = d["manifest"]["binary_skipped"]
assert any(p.endswith("blob.bin") for p in skipped), skipped
assert not any(p["path"].endswith("blob.bin") for p in d["proposed"]), d["proposed"]
PYEOF

# --- NO RANKING: the emitted order is the enumerator's, never by hit count ---
python3 - "$work/h.json" <<'PYEOF' && ok "the proposal carries no rank or score field — narrowing by judgment is unreachable" || err "a ranking or scoring field reached the proposal"
import json, sys
d = json.load(open(sys.argv[1]))
for p in d["proposed"]:
    assert set(p) <= {"path", "terms", "hits", "owner_requested"}, p
    assert "rank" not in p and "score" not in p, p
PYEOF
if grep -qE '\brank\b|\bscore\b|sorted\(.*hits|key=lambda.*hits' "$S"; then
  err "harvest-scope.py ranks or scores its proposal (the second-proposer boundary)"
else
  ok "no ranking path exists in the implementation (grep-asserted)"
fi

# --- NEGATIVE TEST: the determinism assertion must be able to fail ----------
if [ "$(printf 'a\n')" = "$(printf 'b\n')" ]; then
  err "negative test: the comparison used for determinism cannot fail"
else
  ok "negative test: the determinism comparison distinguishes different output"
fi

[ "$fail" -eq 0 ] || { printf '\nharvest-scope checks FAILED.\n' >&2; exit 1; }
printf '\nAll harvest-scope checks passed.\n'
