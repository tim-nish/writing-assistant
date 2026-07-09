#!/usr/bin/env sh
# check-skeleton.sh — verify the repository skeleton and the BMAD/hand-written
# separation invariants (Story 1.1). Zero dependencies beyond POSIX shell + git;
# no JavaScript/TypeScript, no venv. Run from anywhere inside the repo.
#
# It asserts, against what git actually tracks (not just the working tree):
#   1. the required top-level directories and README.md exist;
#   2. the three adopted article specs are vendored with their banners intact;
#   3. BMAD's footprint is confined — nothing BMAD is tracked, and no BMAD
#      output lives under specs/;
#   4. no JavaScript/TypeScript source is tracked (external `npx` invocation of
#      BMAD is a runtime call, not a file, so it does not count).

set -eu

# Resolve repo root so the script works from any subdirectory.
root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2
  exit 1
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 1. Required top-level directories + README.
for d in .claude-plugin skills/draft-article skills/review-article skills/harvest scripts config specs; do
  if [ -d "$d" ]; then ok "dir $d"; else err "missing directory: $d"; fi
done
if [ -f README.md ]; then ok "README.md"; else err "missing README.md"; fi

# 2. Vendored article specs present with "Vendored copy" banner intact.
for s in spec-article-frameworks spec-article-draft-pipeline spec-article-review; do
  f="specs/$s/SPEC.md"
  if [ ! -f "$f" ]; then
    err "missing vendored spec: $f"
  elif grep -q 'Vendored copy' "$f"; then
    ok "vendored banner: $f"
  else
    err "vendored banner missing (spec not marked adopted): $f"
  fi
done

# 3. BMAD footprint confined.
tracked=$(git ls-files)
if printf '%s\n' "$tracked" | grep -Eq '^(_bmad/|_bmad-output/|\.claude/skills/bmad-)'; then
  err "BMAD artifacts are tracked in git (must stay ignored): $(printf '%s\n' "$tracked" | grep -E '^(_bmad/|_bmad-output/|\.claude/skills/bmad-)' | head -3 | tr '\n' ' ')"
else
  ok "no BMAD artifacts tracked"
fi
if printf '%s\n' "$tracked" | grep -Eq '^specs/.*(\.memlog\.md$|_bmad)'; then
  err "BMAD/process output tracked under specs/: $(printf '%s\n' "$tracked" | grep -E '^specs/.*(\.memlog\.md$|_bmad)' | head -3 | tr '\n' ' ')"
else
  ok "specs/ free of BMAD output"
fi

# 4. No JavaScript/TypeScript source tracked.
if printf '%s\n' "$tracked" | grep -Eq '\.(js|jsx|mjs|cjs|ts|tsx)$'; then
  err "JavaScript/TypeScript source tracked: $(printf '%s\n' "$tracked" | grep -E '\.(js|jsx|mjs|cjs|ts|tsx)$' | head -3 | tr '\n' ' ')"
else
  ok "no JS/TS source tracked"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll skeleton checks passed.\n'
  exit 0
else
  printf '\nSkeleton checks FAILED.\n' >&2
  exit 1
fi
