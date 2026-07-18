#!/usr/bin/env sh
# check-framework-f4.sh — verify the F4 research-survey framework (Story 2.5).
# POSIX shell only.
#
# Checks: exact slot order (scope → map → branch unit → my-take → reading-list →
# pointer); the per-branch unit is repeatable with no hardcoded count and its own
# citations; the "My take" GATE requires BOTH owner angle AND a preprint/repo
# link; the My-take and Pointer GATEs are separate and independent; the evidence
# rule is enforced at branch level; the reading list stays distinct from
# per-branch citations; and reuse of Story 2.1's shared conventions.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

F4="skills/draft-article/frameworks/F4-research-survey.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -qF -- "$1" "$F4"; then ok "$2"; else err "$2 (missing: $1)"; fi; }
absent() { if grep -qF -- "$1" "$F4"; then err "$2 (should be absent: $1)"; else ok "$2"; fi; }
line() { grep -nF -- "$1" "$F4" | head -1 | cut -d: -f1; }

[ -f "$F4" ] && ok "present: $F4" || { err "missing $F4"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Exact section order.
prev=0; order_ok=1
check_order() {
  ln=$(line "$1")
  if [ -z "$ln" ]; then err "section missing: $1"; order_ok=0; return; fi
  if [ "$ln" -le "$prev" ]; then err "out of order: $1 (line $ln after $prev)"; order_ok=0; fi
  prev=$ln
}
check_order "## Frontmatter"
check_order "## {Scope and audience}"
check_order "## {The map}"
check_order "## {Branch:"
check_order "## GATE {My take}"
check_order "## {Reading list}"
check_order "## GATE {Pointer block}"
[ "$order_ok" -eq 1 ] && ok "slots appear in the exact F4 order"

# 2. Per-branch unit: repeatable, no hardcoded count, own citations.
has "Branch unit START" "branch-unit START marker"
has "Branch unit END"   "branch-unit END marker"
has "no fixed"          "branch unit repeats with no hardcoded count"
map=$(line "## {The map}"); start=$(line "Branch unit START")
branch=$(line "## {Branch:"); end=$(line "Branch unit END"); mytake=$(line "## GATE {My take}")
{ [ "$map" -lt "$start" ] && [ "$start" -lt "$branch" ] && [ "$branch" -lt "$end" ] && [ "$end" -lt "$mytake" ]; } \
  && ok "branch unit is bracketed; scope/map above, my-take below" \
  || err "branch-unit markers do not bracket the branch slot correctly"
has "branch's OWN" "each branch carries its own citations"

# 2b. Entry GATE: source+artifact pairing (Story 13.87, #391).
has "GATE (entry)" "entry GATE present"
has "source+artifact pairing" "entry GATE names the source+artifact pairing"
has "external papers when the surveyed field is published" \
  "entry GATE covers the external-literature source class"
has "specs, ADRs, issues," "entry GATE covers internal design records"
has "internal system's design space" "entry GATE admits internal design-space surveys"
has "exist or be imminent" "artifact half unchanged (reputation anchor kept)"
absent "spec §6.2" "dangling spec §6.2 pointer retired (rule stated in-repo)"

# 3. "My take" GATE requires BOTH angle AND link.
has "REQUIRES BOTH" "My-take GATE requires both components"
has "link to your preprint/repo" "My-take requires a preprint/repo link"
has "does not satisfy this GATE" "My-take rejects opinion-without-link (or link-without-angle)"

# 4. My-take and Pointer GATEs are separate, independently enforced.
grep -c '^## GATE {' "$F4" | grep -qx 2 && ok "exactly two fill-GATEs (My take, Pointer)" \
  || err "expected 2 '## GATE {' headings"
has "independent of the" "GATEs independent — one does not satisfy the other"

# 5. Evidence rule at branch/map level.
has "must resolve to a citation" "map claims must resolve to a citation"
has "every claim in the branch points to one" "branch claims carry resolvable pointers"

# 6. Reading list distinct from per-branch citations.
has "distinct deliverable" "reading list is a distinct deliverable"
has "not a concatenation" "reading list not conflated with per-branch key papers"

# 7. Reuse of shared conventions; generic engine.
has "CONVENTIONS.md" "references shared CONVENTIONS.md"
absent "I write about" "does not inline the shared pointer-block prose"
if grep -qE '^mode:' "$F4"; then err "hardcodes a frontmatter schema (raw 'mode:' line)"; else ok "frontmatter is config-bound"; fi
if grep -qi 'tim-nish' "$F4"; then err "leaks owner identity"; else ok "no owner identity"; fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll F4 framework checks passed.\n'; exit 0
else
  printf '\nF4 framework checks FAILED.\n' >&2; exit 1
fi
