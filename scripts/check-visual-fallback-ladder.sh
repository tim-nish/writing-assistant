#!/usr/bin/env sh
# parallel-safe
# covers: skills/draft-article/stages/stage3.md
# check-visual-fallback-ladder.sh — verify the visual fallback ladder (Story 8.4,
# SPEC-article-visuals CAP-4): when no repo visual fits, produce source in the
# strict order reuse -> Mermaid -> figure spec -> image-gen prompt (with
# "no embedded text" + aspect ratio) -> ASCII (simple only); never a bare
# `[Figure: …]` placeholder; and no mermaid-cli / image tooling / image-gen API is
# invoked (NFR9). POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/draft-article/stages/stage3.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "draft-article SKILL.md exists" \
  || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

sec=$(awk '/^### Visual fallback ladder/{f=1} f && /^#{2,3} / && !/Visual fallback ladder/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "Visual fallback ladder subsection present" \
  || { err "fallback ladder subsection missing"; printf '\nFAILED.\n' >&2; exit 1; }

hasin() { printf '%s\n' "$1" | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

# The strict ladder order (each rung present, in order).
hasin "$sec" 'reuse a repo visual\|reuse.*repo'   "rung 1: reuse repo visual"
hasin "$sec" 'Mermaid'                            "rung 2: Mermaid"
hasin "$sec" 'Vega-Lite'                          "rung 3: Vega-Lite spec for a quantitative role (#983)"
hasin "$sec" 'pinned measurements\|measurements'   "rung 3: its data rows are the pinned measurements"
hasin "$sec" 'figure spec'                        "rung 4: figure spec (elements, relations, emphasis, caption)"
hasin "$sec" 'image-generation prompt\|image-gen' "rung 4: image-generation prompt"
hasin "$sec" 'no embedded text'                   "rung 4: prompt includes 'no embedded text'"
hasin "$sec" 'aspect ratio'                        "rung 4: prompt includes an aspect ratio"
hasin "$sec" 'ASCII'                              "rung 5: ASCII"
hasin "$sec" 'simple structures only\|simple.*only' "rung 5: ASCII simple structures only"

# Verify the order in the numbered list (reuse < mermaid < figure spec < prompt < ascii).
order=$(printf '%s\n' "$sec" | grep -nEi 'reuse a repo|Mermaid|Vega-Lite|figure spec|image-generation prompt|ASCII' | head -20)
lr=$(printf '%s\n' "$order" | grep -i 'reuse a repo'          | head -1 | cut -d: -f1)
lm=$(printf '%s\n' "$order" | grep -i 'Mermaid'               | head -1 | cut -d: -f1)
lf=$(printf '%s\n' "$order" | grep -i 'figure spec'           | head -1 | cut -d: -f1)
lp=$(printf '%s\n' "$order" | grep -i 'image-generation prompt' | head -1 | cut -d: -f1)
la=$(printf '%s\n' "$order" | grep -i 'ASCII'                 | head -1 | cut -d: -f1)
# Story 20.69 (#983): the quantitative rung sits above the figure spec — the
# ladder is ordered by fidelity, and a chart of measured results degrading to
# an image prompt would invent the values it draws.
lv=$(printf '%s\n' "$order" | grep -i 'Vega-Lite'             | head -1 | cut -d: -f1)
if [ "$lr" -lt "$lm" ] && [ "$lm" -lt "$lv" ] && [ "$lv" -lt "$lf" ] \
   && [ "$lf" -lt "$lp" ] && [ "$lp" -lt "$la" ]; then
  ok "ladder order: reuse<Mermaid<Vega-Lite<figure spec<prompt<ASCII"
else
  err "ladder order wrong (reuse=$lr mermaid=$lm vega=$lv figspec=$lf prompt=$lp ascii=$la)"
fi

# Never a bare placeholder; no rendering / tooling invoked (NFR9).
hasin "$sec" 'never a bare .*Figure\|bare .*Figure.*placeholder' "never a bare [Figure: …] placeholder"
hasin "$sec" 'mermaid-cli'                        "NFR9: names mermaid-cli as not invoked"
hasin "$sec" 'never invokes\|no rendering\|source only' "NFR9: source only, no rendering"
hasin "$sec" 'image-generation API\|image tooling' "NFR9: no image tooling / image-gen API"

if [ "$fail" -eq 0 ]; then
  printf '\nAll visual-fallback-ladder checks passed.\n'; exit 0
else
  printf '\nvisual-fallback-ladder checks FAILED.\n' >&2; exit 1
fi
