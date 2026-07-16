#!/usr/bin/env sh
# check-site-record.sh — verify the post-publish site external-record proposal
# (Story 16.9, FR62): after the owner confirms the published URL, the pipeline
# PROPOSES a ready-to-paste `mode: external` record conforming to the user-config
# site schema (<= line budget, body forbidden), writing it to $WS only — never
# the site tree; it consults no platform profile; a canonical-mode language needs
# no record; and without a confirmed URL the offer is re-presentable, never
# dropped. POSIX sh + stdlib Python.

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
# No platform-profiles set up on purpose: the site record consults no profile.
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/ws"

cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","date","mode","language","summary","topics","related"],
"related_keys":["projects","publications","products"]},
"syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
"ja":{"mode":"external","variants":["zenn"]}}},
"site_record":{"external_record_max_lines":20,"body_forbidden":true}}
EOF
cat > "$work/ja.md" <<'EOF'
---
slug: my-ja-post
title: リトライ嵐
date: 2026-07-09
mode: external
language: ja
audience: ja-practitioner
summary: 要約
topics: [llm-ops]
---
本文。
EOF
cat > "$work/en.md" <<'EOF'
---
slug: en-post
title: An EN piece
date: 2026-07-09
mode: canonical
language: en
audience: en-practitioner
---
Body.
EOF

sr() { python3 "$DP" site-record "$1" --config-json "$work/cfg.json" --root "$work"; }

# 1. A canonical-mode language needs no external record.
sr "$work/en.md" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["applicable"] is False, d' \
  && ok "a canonical-mode language needs no external record" || err "canonical case wrong"

# 2. AC4 — the re-presentable offer: decline (no URL) → pending, nothing written;
#    re-invoke with a confirmed URL → the proposal appears.
python3 "$DP" site-record "$work/ja.md" --config-json "$work/cfg.json" --root "$work" \
  --ws "$work/ws" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["applicable"] is True and d["url_confirmed"] is False, d'
[ -z "$(ls "$work/ws" 2>/dev/null)" ] \
  && ok "no confirmed URL → offer pending, nothing written (re-runnable)" \
  || err "something written before URL confirmation"
out=$(python3 "$DP" site-record "$work/ja.md" --config-json "$work/cfg.json" --root "$work" \
        --ws "$work/ws" --url "https://zenn.dev/u/articles/my-ja-post")
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["url_confirmed"] is True and d["applicable"] is True, d
assert d["lines"] <= d["max_lines"] and not d["over_line_budget"], d
assert "mode: external" in d["record"] and "canonical_url: https://zenn.dev" in d["record"], d' \
  && ok "confirming the URL yields a ready-to-paste record within the line budget" \
  || err "post-confirm proposal wrong"

# 3. The proposal lands in $WS only — never the site tree; applying is the owner's.
[ -f "$work/ws/site-record.my-ja-post.md" ] \
  && ok "proposal written to \$WS (never the site tree)" || err "proposal not in \$WS"

# 4. Content is metadata only — no audience, no lede, no body (body forbidden).
REC="$work/ws/site-record.my-ja-post.md"
grep -q '^audience:' "$REC" && err "record leaked the audience field" \
  || ok "record carries no audience (index-facing metadata only)"
# body forbidden: the file ends at the closing frontmatter fence.
[ "$(tail -n1 "$REC")" = "---" ] && ok "record has no body (body forbidden)" \
  || err "record has a body"

# 5. No platform profile is consulted (this ran with no profiles dir configured).
ok "site record generated with no platform profile configured (site is not a platform)"

if [ "$fail" -eq 0 ]; then
  printf '\nAll site-record checks passed.\n'; exit 0
else
  printf '\nsite-record checks FAILED.\n' >&2; exit 1
fi
