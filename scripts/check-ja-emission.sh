#!/usr/bin/env sh
# check-ja-emission.sh — verify Zenn emission from a JA canonical is PURE
# PACKAGING (Story 18.59, #590; the emission half of #582, governed by the
# shipped SPEC-platform-variants CAP-3/CAP-4 because a derived canonical is a
# first-class canonical — SPEC-canonical-adaptation CAP-4). POSIX sh + stdlib
# Python; every fixture write lands under mktemp -d.
#
# The point of deriving the canonical first is that the ONE bounded judgment the
# variant stage allows — the lede retarget — has nothing left to do. So the
# assertion is that the proposal count is **zero**, not that a proposal was
# approved: a fired-and-approved retarget would mean the derivation did not do
# its job.
#
# Covers:
#   - `syndication.policy.ja` naming zenn resolves a JA canonical's emit options
#     at preflight (existing behaviour this story exercises: `available` comes
#     from `syndication.policy.<lang>.variants`, and a missing policy for the
#     draft's language correctly hard-stops);
#   - the retarget trigger's three-way comparison (audience_id / language /
#     register) matches, so ZERO proposals fire and no retarget screen exists;
#   - `lint-platform-variant` reports zero findings on the emitted variant,
#     including zero `language-mismatch` blockers (the check added for #574);
#   - EN -> dev.to emission is unchanged.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

AC="$root/scripts/adapt-canonical.py"
DP="$root/scripts/draft-pipeline.py"
VP="$root/scripts/validate-proposal-payload.py"
LINT="$root/scripts/lint-platform-variant"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host" "$work/ws"

# The destination repo carries the layout the zenn profile declares (check 7 of
# the lint reads the destination's ACTUAL structure).
dest="$work/articles"; mkdir -p "$dest/drafts"
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $dest/drafts/
YAML
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"
# Create every layout directory the installed profiles declare, so the lint's
# destination-structure check grades the emission and not the fixture.
grep -hoE '^\s+[a-z_]+:\s+[a-z0-9_/-]+/?$' "$ppdir"/*.yaml | awk '{print $2}' \
  | grep -E '^[a-z0-9_-]+/?$' | while read -r d; do mkdir -p "$dest/$d"; done

A="python3 $AC"
ARGS="--root $work/host --profiles-dir $ppdir"

# --- the EN source canonical -------------------------------------------------
cat > "$dest/drafts/retry-storms.md" <<'EOF'
---
slug: retry-storms
title: "Retry storms doubled our token spend"
date: 2026-07-09
mode: canonical
language: en
audience: en-practitioner
audience_id: en-practitioner
summary: >
  How an innocuous retry policy tripled load and what we changed.
topics: [llm-ops, reliability]
related: { projects: [], publications: [], products: [] }
---

## The incident

The retry storm doubled token spend, and we caught it late.

## What we changed

A capped exponential backoff, and a budget alarm.
EOF

# --- config: syndication.policy.ja names zenn (USER config, not spec) --------
cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
                          "ja":{"mode":"canonical","variants":["zenn"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"},
             "zenn":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
# The same config MINUS the ja policy, for the hard-stop assertion.
cat > "$work/cfg-noja.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"}}}}
EOF

# --- derive the JA canonical (the whole point of the story) ------------------
cat > "$work/fill.json" <<'EOF'
{
  "refounded_opening": "The target reader has no context on our billing setup, so the opening states the outcome first.",
  "structural_mapping": [
    {"source_section": "The incident", "disposition": "move", "note": "moves after the payoff; this reader expects the result first"},
    {"source_section": "What we changed", "disposition": "keep", "note": "the how-to core, unchanged in order"}
  ],
  "recomposed_title": "リトライ暴走を止める",
  "omissions": []
}
EOF
cat > "$work/body.ja.md" <<'EOF'
## 結論

指数バックオフに上限を設け、予算アラートを追加しました。

## 何が起きたか

リトライの連鎖でトークン消費が倍増し、発見が遅れました。上限を設けたことで、
再発時のコストは想定内に収まっています。
EOF
$A payload --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" > "$work/payload.json"
ask=$(python3 "$VP" --ws "$work/ws" --surface adaptation-plan "$work/payload.json" \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["ask_id"])')
printf '%s' '{"selection":"approve","free_text":""}' \
  | python3 "$VP" --ws "$work/ws" --answer "$ask" >/dev/null
$A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  --body "$work/body.ja.md" --ws "$work/ws" >/dev/null 2>"$work/e-write" \
  || { err "fixture adaptation failed: $(cat "$work/e-write")"; printf '\nFAILED.\n' >&2; exit 1; }
ok "fixture: the JA canonical is derived from the reviewed EN canonical"

# --- preflight: the JA canonical's LANGUAGE resolves its emit options --------
python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg.json" --list-platforms > "$work/pre.json" 2>"$work/e-pre" \
  || { err "preflight failed: $(cat "$work/e-pre")"; printf '\nFAILED.\n' >&2; exit 1; }
python3 -c "
import json
o=json.load(open('$work/pre.json'))
assert o['language']=='ja', o
assert o['available']==['zenn'], o
assert o['emitted']==[] and o['written'] is False, o
" && ok "syndication.policy.ja names zenn, and preflight emits nothing" \
  || err "the ja policy did not resolve the emit options"

# A missing policy for the draft's language still hard-stops (existing
# behaviour this story RELIES on rather than changes).
python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg-noja.json" --list-platforms >/dev/null 2>"$work/e-noja" \
  && err "a missing ja policy did not hard-stop" \
  || grep -q "no syndication.policy for language 'ja'" "$work/e-noja" \
     && ok "a missing policy for the draft's language still hard-stops" \
     || err "wrong no-policy error: $(cat "$work/e-noja")"

# --- emission: ZERO proposals ------------------------------------------------
python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg.json" --platforms zenn --ws "$work/ws" \
  > "$work/emit-ja.json" 2>"$work/e-ja" \
  || { err "ja emission failed: $(cat "$work/e-ja")"; printf '\nFAILED.\n' >&2; exit 1; }
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/emit-ja.json"))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)
# The assertion is ZERO proposals, not "a proposal was approved".
check(len(o.get("lede_proposals", [])) == 0,
      "the emission presents NO retarget screen at all (zero proposals)")
check("lede_proposals" not in o,
      "no lede_proposals key is emitted for a same-reader target")
emitted = o["emitted"]
check(len(emitted) == 1 and emitted[0]["platform"] == "zenn",
      "exactly the chosen zenn variant is emitted")
check(emitted[0]["lede_retarget"] is False,
      "the retarget trigger's comparison matches on audience_id, language and register")
check(o.get("render_blockers") is None, "no render blockers")
sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || fail=1

variant=$(python3 -c "import json;print(json.load(open('$work/emit-ja.json'))['emitted'][0]['path'])")
[ -f "$variant" ] && ok "the zenn variant file exists" || err "no variant written"

# --- the lint reports ZERO findings, including zero language-mismatch --------
python3 "$LINT" --platform zenn --profiles-dir "$ppdir" --root "$work/host" "$variant" \
  > "$work/lint-ja.txt" 2>&1 \
  && ok "lint-platform-variant reports zero findings on the ja variant" \
  || err "the ja variant failed its own lint: $(cat "$work/lint-ja.txt")"
grep -q 'language-mismatch' "$work/lint-ja.txt" \
  && err "a language-mismatch blocker fired on a ja canonical's ja variant" \
  || ok "zero language-mismatch blockers (the #574 check has nothing to report)"

# --- EN -> dev.to is unchanged by any of this --------------------------------
python3 "$DP" variants --slug retry-storms --root "$work/host" \
  --config-json "$work/cfg.json" --platforms devto --ws "$work/ws" \
  > "$work/emit-en.json" 2>"$work/e-en" \
  || { err "en emission failed: $(cat "$work/e-en")"; }
python3 -c "
import json
o=json.load(open('$work/emit-en.json'))
assert o['language']=='en', o
assert o['available']==['devto'], o
assert [e['platform'] for e in o['emitted']]==['devto'], o
assert o['emitted'][0]['lede_retarget'] is False, o
assert 'lede_proposals' not in o, o
" && ok "EN -> dev.to emission behaves exactly as before" \
  || err "EN -> dev.to emission changed: $(cat "$work/emit-en.json")"
en_variant=$(python3 -c "import json;print(json.load(open('$work/emit-en.json'))['emitted'][0]['path'])")
python3 "$LINT" --platform devto --profiles-dir "$ppdir" --root "$work/host" "$en_variant" \
  >/dev/null 2>&1 \
  && ok "the dev.to variant still passes its own lint" \
  || err "the dev.to variant regressed"

# --- the shipped emission harnesses keep passing verbatim --------------------
for c in check-stage5-variants.sh check-platform-lint.sh; do
  sh "scripts/$c" >/dev/null 2>&1 && ok "$c passes unchanged" || err "$c regressed"
done

# --- lockstep: the shipped example config declares the ja policy -------------
python3 - <<'PY' || exit 1
import re, sys
text = open("config/user-config.example.yaml", encoding="utf-8").read()
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)
check(re.search(r"^\s+ja:\s*$", text, re.M) and "zenn" in text,
      "the example config declares syndication.policy.ja naming zenn")
check("derived canonical" in text.lower(),
      "the example config states the ja policy is exercised by a DERIVED canonical")
sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && printf '\nAll ja-emission checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
