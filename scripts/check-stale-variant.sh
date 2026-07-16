#!/usr/bin/env sh
# check-stale-variant.sh — verify stale-variant detection (Story 16.7,
# SPEC-platform-variants "variants are views"): a variant whose canonical draft
# has changed since emission is a publish blocker (CAP-6 bucket), never a silent
# inconsistency; routing the change to the draft and re-emitting clears it.
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host"
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"

cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
"syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]}},
"variants":{"devto":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
cat > "$work/draft.md" <<'EOF'
---
slug: retry-storms
title: A real claim
date: 2026-07-09
mode: canonical
language: en
summary: A short summary.
topics: [llm-ops]
---
# Body

A claim.
EOF
mkdir -p "$work/o"

emit() { python3 "$DP" variants "$work/draft.md" --config-json "$work/cfg.json" \
           --root "$work/host" --out "$work/o" --platforms devto >/dev/null; }
staleness() { python3 "$DP" variant-staleness "$work/draft.md" --out "$work/o" --root "$work/host"; }

# 1. A freshly emitted variant is fresh, no blocker.
emit
staleness | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert [v["status"] for v in d["variants"]]==["fresh"], d
assert "publish_blockers" not in d, d' \
  && ok "a freshly emitted variant is fresh (no blocker)" || err "fresh detection wrong"

# 2. Change the canonical draft without re-emitting → the variant is a publish
#    blocker (stale), never a silent inconsistency.
printf '\nAn added paragraph that changes the draft.\n' >> "$work/draft.md"
staleness | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert [v["status"] for v in d["variants"]]==["stale"], d
b=d.get("publish_blockers"); assert b and b[0]["blocker"]=="stale-variant", d' \
  && ok "a changed canonical draft makes its variant a stale publish blocker (FR60)" \
  || err "stale detection wrong"

# 3. Route the change through the draft and RE-EMIT → the blocker clears.
emit
staleness | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert [v["status"] for v in d["variants"]]==["fresh"], d
assert "publish_blockers" not in d, d' \
  && ok "re-emitting from the updated draft clears the blocker" || err "re-emit did not clear"

# 4. A variant with no recorded canonical hash cannot be verified fresh → blocker.
printf '%s\n' '---' 'slug: retry-storms' '---' 'body, no recorded hash' > "$work/o/retry-storms.medium.md"
staleness | python3 -c '
import json,sys; d=json.load(sys.stdin)
blk={b["blocker"] for b in d.get("publish_blockers",[])}
assert "unrecorded-canonical-hash" in blk, d' \
  && ok "a variant with no recorded hash is a blocker (re-emit to record one)" \
  || err "unrecorded-hash detection wrong"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stale-variant checks passed.\n'; exit 0
else
  printf '\nstale-variant checks FAILED.\n' >&2; exit 1
fi
