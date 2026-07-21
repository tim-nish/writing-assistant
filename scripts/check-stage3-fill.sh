#!/usr/bin/env sh
# check-stage3-fill.sh — verify Stage 3 framework fill + the `[VERIFY]` marker
# contract (Story 4.4). POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Skill documents the fill contract.
grep -q 'render-frontmatter.py' "$SKILL" && ok "frontmatter from the config article schema (not hardcoded)" || err "frontmatter not config-bound"
# Provenance drafting rule amended to the three classes (Story 11.1; harness D1).
grep -qi 'zero-unmarked-claims\|unmarked assertion' "$SKILL" && ok "states the never-unmarked-assertion invariant" || err "invariant not stated"
for cls in sourced derived narration; do
  grep -qi "\*\*$cls\*\*" "$SKILL" || err "provenance class not documented: $cls"
done
ok "documents the three provenance classes (sourced/derived/narration)"
grep -qi 'compress' "$SKILL" && grep -qi 'restate' "$SKILL" \
  && ok "states the derivation rule (compress/combine/restate over ≥2 sourced claims)" || err "derivation rule missing"
grep -q '\[VERIFY: <reason>\]' "$SKILL" && ok "documents the exact marker format" || err "marker format not documented"
grep -q 'verify-markers' "$SKILL" && ok "wires in the marker validator" || err "validator not wired in"

# --- marker contract (machine-detectable, exact) ---------------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# 2. Well-formed markers pass; the count is exact.
cat > "$work/good.md" <<'EOF'
The retry storm doubled token spend [VERIFY: inferred from logs, no exact figure].
We chose JAX [VERIFY: rationale not in sources].
Throughput rose 2x, per the fact sheet.
EOF
python3 "$DP" verify-markers "$work/good.md" >/dev/null 2>&1 && ok "well-formed [VERIFY: reason] markers pass" || err "well-formed markers rejected"
[ "$(python3 "$DP" verify-markers --count "$work/good.md")" -eq 2 ] && ok "--count reports the exact well-formed count (2)" || err "marker count wrong"

# 3. Each malformed shape is caught (exact, machine-detectable format).
for m in '[VERIFY]' '[verify: wrong case]' '[VERIFY no colon]' '[VERIFY: ]'; do
  printf 'A claim %s here.\n' "$m" > "$work/bad.md"
  python3 "$DP" verify-markers "$work/bad.md" >/dev/null 2>&1 \
    && err "malformed marker accepted: $m" || ok "malformed marker rejected: $m"
done

# 4. A VERIFY-like word is not a false positive.
printf 'We are [VERIFYING] the data now.\n' > "$work/word.md"
[ "$(python3 "$DP" verify-markers --count "$work/word.md")" -eq 0 ] \
  && ok "[VERIFYING] is not mistaken for a marker (word boundary)" || err "false-positive on VERIFYING"

# 5. Zero-marker (fully sourced) draft is valid and counts zero.
printf 'Every claim here is sourced.\n' > "$work/clean.md"
python3 "$DP" verify-markers "$work/clean.md" >/dev/null 2>&1 \
  && [ "$(python3 "$DP" verify-markers --count "$work/clean.md")" -eq 0 ] \
  && ok "a fully-sourced draft has zero markers and passes" || err "clean draft mishandled"

# 6. The count is the Stage-4 exit signal (drive markers to zero).
python3 "$DP" verify-markers --count "$work/good.md" | grep -qx 2 \
  && ok "--count is a Stage-4 exit signal (resolve until 0)" || err "count signal wrong"

# 7. Birth record (Story 18.17, hub decision 2026-07-16): the frontmatter
#    render path emits an immutable `generated_by: <tool>@<version>+<commit>`
#    AT CREATION (a real value, not a `{slot}` the author fills), and the lint
#    validates its presence on a canonical draft.
RFM="$root/scripts/render-frontmatter.py"
LINT="$root/scripts/lint-article"
cat > "$work/cfg.json" <<'EOF'
{"owner":{"site_url":"https://ada.dev"},
 "frontmatter":{"schema":["slug","title","date","mode","language","summary","topics","related"],
   "related_keys":["projects","publications","products"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
   "ja":{"mode":"external","variants":["zenn"]}},
   "variants":{"devto":{"canonical_url_base":"https://ada.dev/articles"},
   "zenn":{"external_record_max_lines":20}}}}
EOF
fm_en=$(python3 "$RFM" --config-json "$work/cfg.json" --language en)
printf '%s\n' "$fm_en" | grep -Eq '^generated_by: [^ ]+@[^ ]+\+[^ ]+' \
  && ok "render path emits generated_by <tool>@<version>+<commit> at creation" \
  || err "render path did not emit a well-formed generated_by"
# It is a resolved value, never an author-filled {slot}.
printf '%s\n' "$fm_en" | grep -q '^generated_by: {' \
  && err "generated_by rendered as an unfilled {slot} (must be resolved at creation)" \
  || ok "generated_by is a resolved birth record, not a {slot}"
# The birth record rides on the external-mode (ja) draft too.
python3 "$RFM" --config-json "$work/cfg.json" --language ja | grep -q '^generated_by: ' \
  && ok "generated_by present on the external-mode draft too" || err "generated_by missing on ja draft"

# Lint validates presence: a draft WITHOUT generated_by is a defect; WITH it, clean.
cat > "$work/nb.md" <<'EOF'
---
slug: nb
title: "A draft that forgot to record its birth today"
date: 2026-07-09
mode: canonical
language: en
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
---

## H

Body more at [ada.dev](https://ada.dev).
EOF
python3 "$LINT" "$work/nb.md" --config-json "$work/cfg.json" 2>/dev/null | grep -q '\[birth-record\]' \
  && ok "lint flags a canonical draft missing generated_by" || err "lint did not flag missing generated_by"
# Same draft, now carrying a well-formed birth record from the render path: no birth-record defect.
printf 'generated_by: writing-assistant@0.1.0+abc1234\n' > "$work/inject"
python3 - "$work/nb.md" "$work/inject" > "$work/wb.md" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
inj = open(sys.argv[2]).read().strip()
# insert the birth record just before the closing frontmatter fence
close = [i for i, l in enumerate(lines) if l.strip() == "---"][1]
lines.insert(close, inj)
sys.stdout.write("\n".join(lines))
PY
python3 "$LINT" "$work/wb.md" --config-json "$work/cfg.json" 2>/dev/null | grep -q '\[birth-record\]' \
  && err "lint flagged a draft that carries a valid generated_by" \
  || ok "a draft carrying a valid generated_by has no birth-record defect"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-3 fill checks passed.\n'; exit 0
else
  printf '\nstage-3 fill checks FAILED.\n' >&2; exit 1
fi
