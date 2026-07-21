#!/usr/bin/env sh
# check-reading-time-depth.sh — verify reading-time bands as a depth expression
# (Story 18.27, SPEC-article-draft-pipeline CAP-8 clause, #506): the stage-0 /
# stage-2 depth question MAY present suggested reading-time bands derived from
# the selected elements (~3 min note / ~7 min standard / ~15 min deep-dive) plus
# a custom value; the owner's pick is recorded AS the depth directive (mapped to
# level/scope), NOT a reading-time target; the estimate stays informational
# (CAP-6); nothing auto-splits/auto-trims — a large band/estimate miss surfaces
# as an informational FYI; NO directive at all -> byte-for-byte pre-CAP-8
# behavior. POSIX shell + stdlib Python only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RT="scripts/reading-time.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$RT', doraise=True)" 2>/dev/null \
  && ok "reading-time compiles" || { err "reading-time syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- 1. --bands offers suggested bands + a custom value -------------------------
python3 "$RT" --bands > "$work/bands.json" 2>/dev/null || err "--bands failed"
python3 - "$work/bands.json" <<'PYEOF' && ok "--bands offers >=3 reading-time bands (note/standard/deep-dive) plus a custom value" || err "bands output wrong"
import json, sys
d = json.load(open(sys.argv[1]))
bands = d["bands"]
levels = [b["level"] for b in bands]
assert {"note", "standard", "deep-dive"} <= set(levels), levels
# minutes increase with depth
mins = [b["minutes"] for b in bands]
assert mins == sorted(mins) and mins[0] < mins[-1], mins
assert d.get("custom") is True, d
# each band carries a human label naming its reading time
assert all("min" in b.get("label", "") for b in bands), bands
PYEOF

# --- 2. the pick is recorded AS the depth directive, NOT a reading-time target ---
python3 - "$work/bands.json" <<'PYEOF' && ok "each band maps to a depth directive (a level), never a reading-time target the pipeline optimizes toward" || err "band->directive mapping wrong"
import json, sys
d = json.load(open(sys.argv[1]))
for b in d["bands"]:
    dd = b["depth_directive"]
    # the directive is a depth level/scope — NOT a minutes target
    assert set(dd) <= {"level", "scope"}, dd
    assert "minutes" not in dd and "target" not in dd and "reading_time" not in dd, dd
    assert dd.get("level") == b["level"], (dd, b)
# the output states, mechanically, that the pick is the depth directive, not a target
blob = json.dumps(d).lower()
assert "target" in blob and ("not" in blob or "never" in blob), \
    "bands output should state the reading time is not a mechanical target"
PYEOF

# --- 3. bands are derived from the selected elements (more elements -> deeper) ---
python3 "$RT" --bands --elements 2 > "$work/b2.json" 2>/dev/null
python3 "$RT" --bands --elements 8 > "$work/b8.json" 2>/dev/null
python3 - "$work/b2.json" "$work/b8.json" <<'PYEOF' && ok "bands scale with the selected-element count (a bigger piece suggests a longer deep-dive)" || err "bands did not scale with elements"
import json, sys
dd = lambda p: {b["level"]: b["minutes"] for b in json.load(open(p))["bands"]}
a, b = dd(sys.argv[1]), dd(sys.argv[2])
assert b["deep-dive"] >= a["deep-dive"], (a, b)
assert b["deep-dive"] > a["deep-dive"], (a, b)
PYEOF

# --- 4. NO directive -> byte-for-byte pre-CAP-8 estimate behavior ----------------
cat > "$work/draft.md" <<'EOF'
---
slug: p
title: t
---
# Body

one two three four five six seven eight nine ten.
EOF
plain=$(python3 "$RT" --language en "$work/draft.md")
[ "$plain" = "~1 min read" ] \
  && ok "plain estimate is unchanged (~N min read, single line — byte-for-byte pre-CAP-8)" \
  || err "plain estimate changed: '$plain'"
# exactly one line of output, no bands/FYI leaking into the estimate path
[ "$(python3 "$RT" --language en "$work/draft.md" | wc -l)" -eq 1 ] \
  && ok "the no-directive estimate emits exactly one line (no band/FYI residue)" \
  || err "estimate path emitted extra lines without a directive"

# --- 5. a large band/estimate miss surfaces as an informational FYI, never a
#        split or trim -----------------------------------------------------------
out=$(python3 "$RT" --language en "$work/draft.md" --band-minutes 15)
printf '%s\n' "$out" | head -1 | grep -q '~1 min read' \
  && ok "the estimate line is unchanged even when a chosen band is passed" \
  || err "band-minutes altered the estimate line"
printf '%s' "$out" | grep -qi 'fyi' \
  && ok "a large band/estimate miss surfaces as an informational FYI" \
  || err "large miss produced no FYI"
printf '%s' "$out" | grep -qiE 'split|trim' \
  && err "the FYI mentions splitting/trimming (it must never auto-split or auto-trim)" \
  || ok "the FYI never proposes an auto-split or auto-trim (CAP-8/CAP-6)"
# a close estimate emits no FYI (informational only when the miss is large)
close=$(python3 "$RT" --language en "$work/draft.md" --band-minutes 1)
printf '%s' "$close" | grep -qi 'fyi' \
  && err "a close estimate still emitted an FYI (should be silent)" \
  || ok "a close estimate emits no FYI (only a large miss is worth surfacing)"

# --- 6. SKILL states the reading-time-as-depth-expression contract --------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qiE 'reading-time band|reading time band' \
  && ok "SKILL names reading-time bands" || err "SKILL missing reading-time bands"
printf '%s' "$S" | grep -qi 'CAP-8' && printf '%s' "$S" | grep -qiE '#506' \
  && ok "SKILL cites CAP-8/#506 for the bands clause" || err "SKILL missing the CAP-8/#506 citation"
printf '%s' "$S" | grep -qiE 'recorded as the depth directive|recorded as a depth directive|as the depth directive' \
  && ok "SKILL: the pick is recorded AS the depth directive (mapped to level/scope)" \
  || err "SKILL missing the recorded-as-directive rule"
printf '%s' "$S" | grep -qiE 'not a reading-time target|never a reading-time target|not a .*target' \
  && ok "SKILL: the pick is NOT a reading-time target the pipeline optimizes toward" \
  || err "SKILL missing the not-a-target rule"
printf '%s' "$S" | grep -qiE 'never auto-split|nothing auto-split|no auto-split|never .*auto-trim' \
  && ok "SKILL: nothing auto-splits or auto-trims to hit the number" \
  || err "SKILL missing the no-auto-split/trim rule"
printf '%s' "$S" | grep -qi 'FYI' \
  && ok "SKILL: a large band/estimate miss surfaces as an informational FYI" \
  || err "SKILL missing the large-miss FYI"
printf '%s' "$S" | grep -qiE 'custom value|or a custom|custom reading' \
  && ok "SKILL: the owner may type a custom value when no band fits" \
  || err "SKILL missing the custom-value option"

if [ "$fail" -eq 0 ]; then
  printf '\nAll reading-time-depth checks passed.\n'; exit 0
else
  printf '\nreading-time-depth checks FAILED.\n' >&2; exit 1
fi
