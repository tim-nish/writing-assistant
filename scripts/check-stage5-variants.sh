#!/usr/bin/env sh
# check-stage5-variants.sh — verify Stage 5 as a PROFILE-DRIVEN projection
# (Story 16.3, SPEC-platform-variants CAP-4): variants are projections of the
# canonical draft through declared platform profiles; no hardcoded dev.to/Zenn
# builder remains in stage code; frontmatter and visual treatment come from the
# profile's packaging; the profile-resolution log lands in $WS and only variant
# files land at output.drafts. POSIX shell + stdlib Python.

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

# 1. AC1 — no hardcoded platform builders / identifiers survive in stage code.
if grep -nE '_devto_variant|_zenn_variant|VARIANT_BUILDERS' scripts/draft-pipeline.py >/dev/null 2>&1; then
  err "hardcoded variant builders still present in stage code"
else ok "hardcoded variant builders removed"; fi
if grep -niE '\bdevto\b|\bzenn\b' scripts/draft-pipeline.py >/dev/null 2>&1; then
  err "platform identifiers (devto/zenn) still appear in stage code"
else ok "no platform identifiers in stage code (config + profiles carry them)"; fi

# Skill still documents the Stage-5 contract.
grep -q 'Stage 5 — platform-ready variants' "$SKILL" && ok "documents Stage 5" || err "Stage 5 not documented"
grep -qi 'never a hardcoded' "$SKILL" && ok "states the config-driven (not hardcoded) mapping" || err "config-driven claim missing"
grep -q 'output.drafts' "$SKILL" && ok "writes to the resolved output.drafts location" || err "output.drafts wiring missing"

# Fixture: a controlled config home with resolvable platform profiles, and a
# host root the resolver keys profiles to.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host"
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"

cat > "$work/cfg.json" <<'EOF'
{"syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
"ja":{"mode":"external","variants":["zenn"]}},
"variants":{"devto":{"canonical_url_base":"https://example.com/articles"}}}}
EOF

# 2. EN/canonical → dev.to projection: profile frontmatter + composed canonical_url,
#    body carried over unchanged (mermaid embedded per the profile's visuals).
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

```mermaid
graph TD; A-->B
```
EOF
out=$(python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/o" --ws "$work")
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["mode"]=="canonical" and d["language"]=="en", d
assert [e["platform"] for e in d["emitted"]]==["devto"], d
assert d["next_stage"]=="review", d
assert "render_blockers" not in d, d  # dev.to embeds mermaid, no blocker
' && ok "EN emits exactly a dev.to variant (config-selected, profile-projected)" \
  || err "EN variant selection/shape wrong"

DEVTO="$work/o/retry-storms.devto.md"
[ -f "$DEVTO" ] && ok "dev.to file written to the output location" || err "dev.to file not written"
grep -q '^canonical_url: https://example.com/articles/retry-storms$' "$DEVTO" \
  && ok "dev.to canonical_url composed from owner value + profile format" || err "canonical_url wrong"
grep -q 'The retry storm doubled token spend' "$DEVTO" \
  && ok "projection carries the article body unchanged" || err "dev.to body missing"
grep -q '```mermaid' "$DEVTO" \
  && ok "dev.to visuals=mermaid-embedded leaves the diagram inline" || err "dev.to mermaid handling wrong"

# 2b. NFR17 — the profile-resolution log is an intermediate in $WS, not a product.
[ -f "$work/platform-profiles.resolution.json" ] \
  && ok "profile-resolution log lands in \$WS" || err "no profile-resolution log in \$WS"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert sorted(d["resolved"])==["devto","zenn"], d' \
  "$work/platform-profiles.resolution.json" \
  && ok "resolution log records the resolved profiles" || err "resolution log content wrong"

# 3. JA/external → Zenn projection + profile-declared visual treatment (mermaid
#    HTML-commented, a render publish blocker raised).
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

```mermaid
graph TD; A-->B
```
EOF
out=$(python3 "$DP" variants "$work/ja.md" --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/o")
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["mode"]=="external", d
assert [e["platform"] for e in d["emitted"]]==["zenn"], d
assert d.get("render_blockers")==[{"platform":"zenn","blocker":"unrendered-mermaid"}], d
' && ok "JA emits a Zenn variant with a profile-declared render blocker" || err "JA variant/blocker wrong"

ZENN="$work/o/retry-arashi.zenn.md"
grep -q '^type: "tech"$' "$ZENN" && grep -q '^emoji:' "$ZENN" && grep -q '^published: false$' "$ZENN" \
  && ok "Zenn frontmatter (emoji/type/published) from the profile" || err "Zenn frontmatter wrong"
grep -q '本文。' "$ZENN" && ok "Zenn projection carries the full body" || err "Zenn body missing"
grep -q '<!-- render blocker' "$ZENN" \
  && ok "Zenn visuals=html-comment-blocked wraps the diagram" || err "Zenn visual treatment wrong"

# 4. A configured platform with no profile is a clear, actionable error.
cat > "$work/cfg-noprofile.json" <<'EOF'
{"syndication":{"policy":{"en":{"mode":"canonical","variants":["hashnode"]}}}}
EOF
if python3 "$DP" variants "$work/en.md" --config-json "$work/cfg-noprofile.json" \
     --root "$work/host" --out "$work/o" >/dev/null 2>"$work/e_np"; then
  err "a configured platform with no profile was not rejected"
else
  grep -q 'no platform profile' "$work/e_np" \
    && ok "a configured platform with no profile is rejected, names the fix" \
    || err "missing-profile message wrong: $(cat "$work/e_np")"
fi

# 5. Verified-draft precondition: an unresolved [VERIFY] marker aborts Stage 5.
cat > "$work/bad.md" <<'EOF'
---
slug: x
language: en
topics: [a]
---
Body [VERIFY: still unresolved].
EOF
python3 "$DP" variants "$work/bad.md" --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/o" >/dev/null 2>&1 \
  && err "emitted variants for an unverified draft" || ok "unresolved [VERIFY] aborts Stage 5"

# 6. External output.drafts guard (#213): a config-resolved destination OUTSIDE
#    the host repo that does not exist is refused without --create-out.
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $work/external-drafts/
YAML
if python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
     --root "$work/host" >/dev/null 2>"$work/e_ext"; then
  err "external missing output dir was not refused"
else
  grep -q 'outside the host repo' "$work/e_ext" \
    && ok "external missing output dir refused, names the boundary" \
    || err "external refusal message wrong: $(cat "$work/e_ext")"
fi
[ ! -d "$work/external-drafts" ] && ok "refusal created nothing" || err "refusal created the directory"
python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
  --root "$work/host" --create-out >/dev/null 2>/dev/null \
  && [ -f "$work/external-drafts/retry-storms.devto.md" ] \
  && ok "--create-out consents to creating the external destination" \
  || err "--create-out did not create/write the external destination"
rm -f "$work/host/writing-sources.yaml"

# 7. --dry-run reports without writing.
rm -rf "$work/dry"
python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/dry" --dry-run | python3 -c '
import json,sys; d=json.load(sys.stdin); assert d["written"] is False, d'
[ ! -d "$work/dry" ] && ok "--dry-run writes nothing" || err "--dry-run wrote files"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-5 variant checks passed.\n'; exit 0
else
  printf '\nstage-5 variant checks FAILED.\n' >&2; exit 1
fi
