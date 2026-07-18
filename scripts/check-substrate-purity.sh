#!/usr/bin/env sh
# check-substrate-purity.sh — enforce that platforms live ONLY in profiles and
# config, never in the platform-agnostic substrate (Story 16.8, FR54 success
# criterion / SPEC-platform-variants CAP-1). Grepping stages 0–3 code and the
# substrate skill sections for platform identifiers finds none; and an
# "add a fresh platform" gate proves a synthetic third profile emits with zero
# stage-code change. Platform knowledge leaking back into stage code fails a
# test here instead of surviving as drift. POSIX sh + stdlib Python.

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

# The platform identifiers that must never appear in substrate code.
PAT='\bdevto\b|\bzenn\b'

# 1. The pipeline stage code carries zero platform identifiers (they live in
#    config + profiles). This covers stages 0–3 (and, since Story 16.3, stage 5).
if grep -niE "$PAT" scripts/draft-pipeline.py >/dev/null 2>&1; then
  err "platform identifiers in draft-pipeline.py:"
  grep -niE "$PAT" scripts/draft-pipeline.py >&2
else
  ok "draft-pipeline.py stage code carries no platform identifiers (FR54)"
fi

# 2. The generic profile machinery names no platform (it is parameterized by
#    profiles, not hardcoded). Config-layer helpers (validate-config.py,
#    render-frontmatter.py) legitimately reference owner config KEYS like
#    `syndication.variants.devto` and are deliberately out of scope here.
offenders=$(grep -lniE "$PAT" scripts/resolve-platform-profiles.py \
            scripts/lint-platform-variant 2>/dev/null || true)
if [ -n "$offenders" ]; then
  err "platform identifiers in the generic profile machinery: $offenders"
else
  ok "the profile machinery is generic (no hardcoded platform)"
fi

# 3. The draft-flow skill names no platform anywhere (Story 13.69: variant
#    emission moved to the standalone variants.md, which alone may reference
#    platforms in prose).
if grep -niE "$PAT" "$SKILL" >/dev/null 2>&1; then
  err "platform identifiers in the draft-flow skill (they belong in variants.md):"
  grep -niE "$PAT" "$SKILL" >&2
else
  ok "draft-flow skill (stages 0–4 + completion) names no platform"
fi

# 4. "Add a fresh platform" gate — a synthetic third platform emits with ZERO
#    stage-code change: only a new profile file and a config entry.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host"
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cat > "$ppdir/hashnode.yaml" <<'EOF'
platform: hashnode
audience: en-practitioner
audience_id: en-practitioner
language: en
packaging:
  frontmatter: [title, tags]
  tag_cap: 5
  canonical_url:
    policy: point-to-site
    format: "{base}/{slug}"
  visuals: mermaid-embedded
distribution_hook: newsletter-follow
EOF
cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
"syndication":{"policy":{"en":{"mode":"canonical","variants":["hashnode"]}},
"variants":{"hashnode":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
cat > "$work/draft.md" <<'EOF'
---
slug: p
title: A claim
date: 2026-07-09
mode: canonical
language: en
audience: en-practitioner
audience_id: en-practitioner
summary: s
topics: [a, b]
---
# Body

Prose.
EOF
mkdir -p "$work/o"
out=$(python3 "$DP" variants "$work/draft.md" --allow-external-draft \
        --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/o" --platforms hashnode)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert [e["platform"] for e in d["emitted"]]==["hashnode"], d' \
  && [ -f "$work/o/p.hashnode.md" ] \
  && ok "a synthetic third platform emits with zero stage-code change (FR54/CAP-2)" \
  || err "fresh-platform gate: hashnode did not emit"

# The success signal is structural: because the substrate is platform-free, one
# canonical draft reaches every platform through one harvest / interview / review
# / lede decision — the emission choice (Story 16.4) is the only per-platform fan-out.

if [ "$fail" -eq 0 ]; then
  printf '\nAll substrate-purity checks passed.\n'; exit 0
else
  printf '\nsubstrate-purity checks FAILED.\n' >&2; exit 1
fi
