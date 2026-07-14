#!/usr/bin/env sh
# check-stage5-variants.sh — verify Stage 5 platform-ready variants (Story 4.6):
# config-driven dev.to (EN/canonical) and Zenn (JA/external) emission, the
# verified-draft precondition, and output to the resolved drafts location.
# POSIX shell + stdlib Python.

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

# 1. Skill documents the Stage-5 contract.
grep -q 'Stage 5 — platform-ready variants' "$SKILL" && ok "documents Stage 5" || err "Stage 5 not documented"
grep -qi 'never a hardcoded' "$SKILL" && ok "states the config-driven (not hardcoded) mapping" || err "config-driven claim missing"
grep -qi 'canonical_url' "$SKILL" && ok "documents the dev.to canonical_url placeholder" || err "canonical_url not documented"
grep -qi 'Zenn' "$SKILL" && ok "documents the Zenn repo-sync variant" || err "Zenn variant not documented"
grep -q 'output.drafts' "$SKILL" && ok "writes to the resolved output.drafts location" || err "output.drafts wiring missing"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

cat > "$work/cfg.json" <<'EOF'
{"syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
"ja":{"mode":"external","variants":["zenn"]}},
"variants":{"devto":{"canonical_url_base":"https://example.com/articles"},
"zenn":{"external_record_max_lines":20}}}}
EOF

# 2. EN/canonical -> dev.to copy: full text + canonical_url placeholder.
cat > "$work/en.md" <<'EOF'
---
slug: retry-storms
title: "Retry storms doubled our token spend"
date: 2026-07-09
mode: canonical
language: en
summary: >
  How an innocuous retry policy tripled load and what we changed.
topics: [llm-ops, reliability]
related: { projects: [], publications: [], products: [] }
---

## Hook

The retry storm doubled token spend, and we caught it late.
EOF
out=$(python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" --out "$work/o")
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["mode"]=="canonical" and d["language"]=="en", d
assert [e["platform"] for e in d["emitted"]]==["devto"], d
assert d["next_stage"]=="review", d
' && ok "EN emits exactly a dev.to variant (config-driven)" || err "EN variant selection wrong"

DEVTO="$work/o/retry-storms.devto.md"
[ -f "$DEVTO" ] && ok "dev.to file written to the output location" || err "dev.to file not written"
grep -q '^canonical_url: https://example.com/articles/retry-storms$' "$DEVTO" \
  && ok "dev.to canonical_url placeholder built from config + slug" || err "canonical_url wrong"
grep -q 'The retry storm doubled token spend' "$DEVTO" \
  && ok "dev.to copy carries the full article body" || err "dev.to body missing"

# 3. JA/external -> Zenn repo-sync copy with Zenn frontmatter.
cat > "$work/ja.md" <<'EOF'
---
slug: retry-arashi
title: "リトライ嵐"
date: 2026-07-09
mode: external
language: ja
summary: 本文の要約。
topics: [llm-ops]
related: { projects: [], publications: [], products: [] }
---

## フック

本文。
EOF
python3 "$DP" variants "$work/ja.md" --config-json "$work/cfg.json" --out "$work/o" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["mode"]=="external", d
assert [e["platform"] for e in d["emitted"]]==["zenn"], d
' && ok "JA emits exactly a Zenn variant (config-driven)" || err "JA variant selection wrong"

ZENN="$work/o/retry-arashi.zenn.md"
grep -q '^type: "tech"$' "$ZENN" && grep -q '^emoji:' "$ZENN" && grep -q '^published: false$' "$ZENN" \
  && ok "Zenn frontmatter (emoji/type/published) emitted" || err "Zenn frontmatter wrong"
grep -q '本文。' "$ZENN" && ok "Zenn copy carries the full body (repo-sync canonical)" || err "Zenn body missing"

# 4. Verified-draft precondition: an unresolved [VERIFY] marker aborts Stage 5.
cat > "$work/bad.md" <<'EOF'
---
slug: x
language: en
topics: [a]
---
Body [VERIFY: still unresolved].
EOF
python3 "$DP" variants "$work/bad.md" --config-json "$work/cfg.json" --out "$work/o" >/dev/null 2>&1 \
  && err "emitted variants for an unverified draft" || ok "unresolved [VERIFY] aborts Stage 5"

# 4b. External output.drafts guard (Story 13.24, #213): a config-resolved
#     destination OUTSIDE the host repo that does not exist is refused without
#     --create-out (nothing created); --create-out creates it. An in-host
#     relative value keeps auto-creating. Hermetic config home.
XDG_CONFIG_HOME="$work/xdg"; export XDG_CONFIG_HOME
mkdir -p "$work/exthost"
cat > "$work/exthost/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $work/external-drafts/
YAML
if python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
     --root "$work/exthost" >/dev/null 2>"$work/e_ext"; then
  err "external missing output dir was not refused"
else
  grep -q 'outside the host repo' "$work/e_ext" \
    && ok "external missing output dir refused, names the boundary" \
    || err "external refusal message wrong: $(cat "$work/e_ext")"
fi
[ ! -d "$work/external-drafts" ] && ok "refusal created nothing" || err "refusal still created the directory"
python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
  --root "$work/exthost" --create-out >/dev/null 2>/dev/null \
  && [ -f "$work/external-drafts/retry-storms.devto.md" ] \
  && ok "--create-out consents to creating the external destination" \
  || err "--create-out did not create/write the external destination"
cat > "$work/exthost/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
YAML
python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
  --root "$work/exthost" >/dev/null 2>/dev/null \
  && [ -f "$work/exthost/articles/drafts/retry-storms.devto.md" ] \
  && ok "in-host relative output.drafts still auto-creates under the host root" \
  || err "in-host relative output.drafts failed"

# 5. --dry-run reports without writing.
rm -rf "$work/dry"
python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" --out "$work/dry" --dry-run | python3 -c '
import json,sys; d=json.load(sys.stdin); assert d["written"] is False, d'
[ ! -d "$work/dry" ] && ok "--dry-run writes nothing" || err "--dry-run wrote files"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-5 variant checks passed.\n'; exit 0
else
  printf '\nstage-5 variant checks FAILED.\n' >&2; exit 1
fi
