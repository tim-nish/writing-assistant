#!/usr/bin/env sh
# check-platform-variant-visuals.sh — verify platform variants handle visual
# rendering divergence as PROFILE-DRIVEN behavior (Story 16.8 rewrite of the
# Story 8.5 check; SPEC-article-visuals CAP-5 amended 2026-07-16): the treatment
# is declared by each profile's `packaging.visuals` and applied by the emitter,
# never a hardcoded per-platform builder. The shipped example profiles carry the
# ratified per-platform behavior (dev.to does not render Mermaid → HTML-comment +
# render blocker; Zenn renders it natively → embedded). POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
PROF="$root/scripts/resolve-platform-profiles.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host"
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"

# 1. The ratified per-platform behavior is pinned in the shipped example
#    profiles (a profile is a conformance record of the platform; the spec is
#    authoritative — 2026-07-16 layout/visuals authority).
got=$(python3 "$PROF" get devto --root "$work/host" --profiles-dir "$ppdir" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["packaging"]["visuals"])')
[ "$got" = "html-comment-blocked" ] \
  && ok "shipped dev.to profile: html-comment-blocked (dev.to renders no Mermaid)" \
  || err "dev.to profile visuals should be html-comment-blocked (got '$got')"
got=$(python3 "$PROF" get zenn --root "$work/host" --profiles-dir "$ppdir" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["packaging"]["visuals"])')
[ "$got" = "mermaid-embedded" ] \
  && ok "shipped Zenn profile: mermaid-embedded (Zenn renders Mermaid natively)" \
  || err "Zenn profile visuals should be mermaid-embedded (got '$got')"

# Fixtures: an EN draft (→ dev.to) and a JA draft (→ Zenn), each with a Mermaid
# diagram, and configs selecting one platform each.
cat > "$work/en.md" <<'EOF'
---
slug: p
title: A claim
date: 2026-07-09
mode: canonical
language: en
audience: en-practitioner
audience_id: en-practitioner
summary: s
topics: [a]
---
# Body

Prose.

```mermaid
graph TD; A-->B
```
EOF
sed -e 's/^language: en/language: ja/' -e 's/^audience: en-practitioner/audience: ja-practitioner/' -e 's/^audience_id: en-practitioner/audience_id: ja-practitioner/' \
    -e 's/^mode: canonical/mode: external/' "$work/en.md" > "$work/ja.md"
cat > "$work/cfg-en.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
"syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]}},
"variants":{"devto":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
cat > "$work/cfg-ja.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
"syndication":{"policy":{"ja":{"mode":"external","variants":["zenn"]}}}}
EOF
mkdir -p "$work/o"

# 2. Profile-driven mechanism — html-comment-blocked (dev.to): the emitter wraps
#    the Mermaid block and raises a render blocker.
out=$(python3 "$DP" variants "$work/en.md" --config-json "$work/cfg-en.json" \
        --root "$work/host" --out "$work/o" --platforms devto)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d.get("render_blockers")==[{"platform":"devto","blocker":"unrendered-mermaid"}], d' \
  && ok "html-comment-blocked profile → emitter raises a render blocker" \
  || err "html-comment-blocked mechanism wrong"
grep -q '<!-- render blocker' "$work/o/p.devto.md" \
  && ok "html-comment-blocked profile → Mermaid wrapped in an HTML comment" \
  || err "Mermaid not HTML-commented"

# 3. Profile-driven mechanism — mermaid-embedded (Zenn): the emitter leaves the
#    Mermaid block inline and raises no blocker.
out=$(python3 "$DP" variants "$work/ja.md" --config-json "$work/cfg-ja.json" \
        --root "$work/host" --out "$work/o" --platforms zenn)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert "render_blockers" not in d, d' \
  && ok "mermaid-embedded profile → no render blocker" || err "mermaid-embedded mechanism wrong"
grep -q '```mermaid' "$work/o/p.zenn.md" \
  && ok "mermaid-embedded profile → Mermaid left inline" || err "Mermaid not left inline"

# 4. The SKILL still documents the ratified per-platform behavior (unchanged).
sec=$(awk '/^### Visual rendering per platform/{f=1} f && /^#{2,3} / && !/Visual rendering per platform/{exit} f{print}' "$SKILL")
printf '%s\n' "$sec" | grep -qi 'Zenn' && printf '%s\n' "$sec" | grep -qi 'embeds.*Mermaid' \
  && ok "SKILL documents Zenn embeds Mermaid natively" || err "SKILL Zenn behavior missing"
printf '%s\n' "$sec" | grep -qi 'dev.to' && printf '%s\n' "$sec" | grep -qi 'HTML comment' \
  && ok "SKILL documents dev.to HTML-comment + blocker" || err "SKILL dev.to behavior missing"

if [ "$fail" -eq 0 ]; then
  printf '\nAll platform-variant-visual checks passed.\n'; exit 0
else
  printf '\nplatform-variant-visual checks FAILED.\n' >&2; exit 1
fi
