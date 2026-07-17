#!/usr/bin/env sh
# check-visual-proposals.sh — verify visuals are PROPOSED, not inserted, under the
# owner-facing proposal contract (Story 8.2, SPEC-article-visuals CAP-2): each
# framework slot plus up to 2 opportunistic extras is proposed with rationale, a
# preview (a plain-text structural sketch; concrete source in the run workspace,
# referenced by path — Story 13.48), and concrete-effect choices; nothing is
# inserted without explicit approval; opportunistic visuals are capped at 2.
# POSIX shell.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$SKILL" ] && ok "draft-article SKILL.md exists" \
  || { err "SKILL.md missing"; printf '\nFAILED.\n' >&2; exit 1; }

# Extract the Visual proposals subsection (### heading to the next ## or ###).
sec=$(awk '/^### Visual proposals/{f=1} f && /^#{2,3} / && !/Visual proposals/{exit} f{print}' "$SKILL")
[ -n "$sec" ] && ok "Visual proposals subsection present" \
  || { err "Visual proposals subsection missing"; printf '\nFAILED.\n' >&2; exit 1; }

hasin() { printf '%s\n' "$1" | grep -qi -- "$2" && ok "$3" || err "$3 — missing"; }

hasin "$sec" 'owner-facing-proposal-contract' "proposals follow the owner-facing contract"
hasin "$sec" 'declared visual slot'           "proposes the framework's declared slot (Story 8.1)"
hasin "$sec" 'rationale\|why.*proposed'       "proposal shows a rationale"
hasin "$sec" 'preview'                        "proposal shows a preview"
hasin "$sec" 'plain-text structural sketch'   "preview is a plain-text structural sketch (Story 13.48)"
hasin "$sec" 'never raw Mermaid'              "raw/fenced Mermaid never appears in the payload"
hasin "$sec" 'run workspace'                  "concrete source is written to the run workspace"
hasin "$sec" 'path.*in the payload\|show.*path' "payload references the source by workspace path"
hasin "$sec" 'exactly as written'             "approved source is used exactly as written (sketch never re-derived)"
hasin "$sec" 'exemption'                      "visual payloads pass the plain-text validator without exemption"
hasin "$sec" 'figure-spec\|figure spec'       "sketch is figure-spec style (elements, relations, emphasis)"
hasin "$sec" 'concrete effect'               "choices state their concrete effect"
hasin "$sec" 'never insert\|Insert nothing\|without explicit' "inserts nothing without approval"
hasin "$sec" 'capped at 2\|at most two'       "opportunistic visuals capped at 2"
hasin "$sec" 'omitted entirely\|no.*residue\|placeholder residue' "declined proposal leaves no residue"

# Two-step intent-before-source (Story 13.29, SPEC-draft-article-ux CAP-3).
hasin "$sec" 'Step 1.*intent\|step 1 — intent' "step 1 asks the visual's intent"
hasin "$sec" 'communicate'                     "intent question asks what the visual should communicate"
hasin "$sec" 'draft-grounded'                  "intent options are draft-grounded, not a fixed menu"
hasin "$sec" 'table-vs-diagram\|table over a diagram' "table-vs-diagram decided at the intent step"
hasin "$sec" 'skips step 2\|skip step 2'       "declining at step 1 skips step 2"
hasin "$sec" 'same two-step'                   "opportunistic extras follow the same two-step"

# Story 13.48: a conforming step-2 payload (plain-text sketch + workspace path)
# passes the contract-(e)/(g) validator; raw fenced Mermaid in the payload blocks.
V="scripts/validate-proposal-payload.py"
SKETCH='{"items":[{"where":"Section 3 (Architecture) - declared visual slot","why":"the pipeline stages and their order are argued in prose but never shown","choices":[{"label":"approve","effect":"insert the source at ws/visuals/architecture.mmd exactly as written"},{"label":"decline","effect":"omit the visual; the slot leaves no residue"}],"preview":"Sketch: boxes for harvest, draft, review; arrows left to right;\nemphasis on the gate between draft and review.\nSource: ws/visuals/architecture.mmd"}]}'
printf '%s' "$SKETCH" | python3 "$V" >/dev/null 2>&1 \
  && ok "plain-text sketch + workspace path payload is presentable" \
  || err "conforming sketch payload was blocked"
FENCED='{"items":[{"where":"Section 3","why":"y","choices":[{"label":"a","effect":"insert it"}],"preview":"```mermaid\ngraph LR; A-->B\n```"}]}'
printf '%s' "$FENCED" | python3 "$V" >/dev/null 2>&1 \
  && err "raw fenced Mermaid payload was NOT blocked" \
  || ok "raw fenced Mermaid in the payload is blocked (no exemption)"

if [ "$fail" -eq 0 ]; then
  printf '\nAll visual-proposal checks passed.\n'; exit 0
else
  printf '\nvisual-proposal checks FAILED.\n' >&2; exit 1
fi
