#!/usr/bin/env sh
# check-cross-language-offer.sh — verify a cross-language target is offered as
# "adapt first", never as a direct projection (Story 18.60, #587;
# SPEC-platform-variants CAP-3 as amended 2026-07-22 for #582). POSIX sh +
# stdlib Python; every fixture write lands under mktemp -d.
#
# The invariant: the mixed-language emission is never the silent default again.
# What the owner MAY do is untouched — only what the screen OFFERS moves.
#
# Covers:
#   - an EN canonical with a ja-profile platform declared: that platform is
#     absent from the direct-projection choices and present as "adapt first",
#     naming the route and its concrete effect on the artifact;
#   - same-language platforms are offered exactly as before;
#   - the deliberate mixed-language emission remains REACHABLE, and the shipped
#     language-mismatch publish blocker still reports it;
#   - a derived JA canonical offers zenn normally, as a same-language target;
#   - the composed screen passes validate-proposal-payload.py.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

AC="$root/scripts/adapt-canonical.py"
DP="$root/scripts/draft-pipeline.py"
VP="$root/scripts/validate-proposal-payload.py"
LINT="$root/scripts/lint-platform-variant"
SKILL="skills/emit-variants/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host" "$work/ws"
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
grep -hoE '^\s+[a-z_]+:\s+[a-z0-9_/-]+/?$' "$ppdir"/*.yaml | awk '{print $2}' \
  | grep -E '^[a-z0-9_-]+/?$' | while read -r d; do mkdir -p "$dest/$d"; done

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

# Both platforms configured for `en` — the exact shape that offered the #574
# artifact as an ordinary choice.
cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto","zenn"]},
                          "ja":{"mode":"canonical","variants":["zenn"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"},
             "zenn":{"canonical_url_base":"https://example.com/articles"}}}}
EOF

# --- the EN canonical's screen ------------------------------------------------
python3 "$DP" variants --slug retry-storms --root "$work/host" \
  --config-json "$work/cfg.json" --list-platforms > "$work/en.json" 2>"$work/e-en" \
  || { err "preflight failed: $(cat "$work/e-en")"; printf '\nFAILED.\n' >&2; exit 1; }
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/en.json"))
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check(o["direct"] == ["devto"],
      "the ja-profile platform is absent from the direct-projection choices")
af = {e["platform"]: e for e in o.get("adapt_first", [])}
check("zenn" in af, "zenn is presented as `adapt first`")
z = af.get("zenn", {})
check(z.get("profile_language") == "ja" and z.get("canonical_language") == "en",
      "the adapt-first entry names both languages")
check("adapt canonical retry-storms for zenn" in z.get("route", ""),
      "the adapt-first entry names the route through adaptation")
check("derives a ja canonical" in z.get("effect", "")
      and "Nothing is emitted until" in z.get("effect", "")
      and len(z["effect"]) <= 140,
      "the adapt-first entry states its concrete effect on the artifact")
# Same-language behaviour is untouched: `available` is still the configured set.
check(o["available"] == ["devto", "zenn"],
      "the configured set is reported unchanged (config truth is not rewritten)")
check(o["emitted"] == [] and o["written"] is False,
      "reading the choices still emits nothing")
sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || fail=1

# A canonical with NO cross-language platform: the screen is exactly as before.
cat > "$work/cfg-en-only.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
python3 "$DP" variants --slug retry-storms --root "$work/host" \
  --config-json "$work/cfg-en-only.json" --list-platforms > "$work/en-only.json"
python3 -c "
import json
o=json.load(open('$work/en-only.json'))
assert o['direct']==['devto'], o
assert 'adapt_first' not in o, o
assert 'adapt first' not in o['note'], o
" && ok "a same-language-only screen is unchanged — no adapt-first key, no new note" \
  || err "the same-language case changed"

# --- the deliberate mixed-language emission stays REACHABLE ------------------
python3 "$DP" variants --slug retry-storms --root "$work/host" \
  --config-json "$work/cfg.json" --platforms zenn --ws "$work/ws" \
  > "$work/mixed.json" 2>"$work/e-mixed" \
  || { err "the deliberate mixed-language emission was refused: $(cat "$work/e-mixed")"; }
[ -f "$dest/drafts/retry-storms.zenn.md" ] \
  && ok "an owner who deliberately wants the mixed-language variant still gets it" \
  || err "the mixed-language variant is no longer reachable"
python3 -c "
import json
o=json.load(open('$work/mixed.json'))
assert o['emitted'][0]['lede_retarget'] is True, o
" && ok "the cross-audience retarget trigger still fires on that deliberate emission" \
  || err "the retarget trigger changed"
python3 "$LINT" --platform zenn --profiles-dir "$ppdir" --root "$work/host" \
  "$dest/drafts/retry-storms.zenn.md" > "$work/lint-mixed.txt" 2>&1 \
  && err "the mixed-language variant passed the lint silently" \
  || grep -q 'language-mismatch' "$work/lint-mixed.txt" \
     && ok "the shipped language-mismatch publish blocker still reports the outcome" \
     || err "no language-mismatch blocker: $(cat "$work/lint-mixed.txt")"
rm -f "$dest/drafts/retry-storms.zenn.md"

# --- the derived JA canonical offers zenn NORMALLY ---------------------------
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
EOF
python3 "$AC" payload --slug retry-storms --target zenn --root "$work/host" \
  --profiles-dir "$ppdir" --fill "$work/fill.json" > "$work/payload.json"
ask=$(python3 "$VP" --ws "$work/ws" --surface adaptation-plan "$work/payload.json" \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["ask_id"])')
printf '%s' '{"selection":"approve","free_text":""}' \
  | python3 "$VP" --ws "$work/ws" --answer "$ask" >/dev/null
python3 "$AC" write --slug retry-storms --target zenn --root "$work/host" \
  --profiles-dir "$ppdir" --fill "$work/fill.json" --body "$work/body.ja.md" \
  --ws "$work/ws" >/dev/null
python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg.json" --list-platforms > "$work/ja.json"
python3 -c "
import json
o=json.load(open('$work/ja.json'))
assert o['language']=='ja', o
assert o['direct']==['zenn'], o
assert 'adapt_first' not in o, o
" && ok "the derived JA canonical offers zenn normally, as a same-language target" \
  || err "the derived canonical's screen is wrong: $(cat "$work/ja.json")"

# --- the composed screen is presentable --------------------------------------
python3 - "$work" <<'PY' > "$work/screen.json"
import json, sys
o = json.load(open(sys.argv[1] + "/en.json"))
choices = [{"label": p,
            "effect": f"writes retry-storms.{p}.md at the drafts destination; "
                      "no other platform gets a file"}
           for p in o["direct"]]
for e in o.get("adapt_first", []):
    choices.append({"label": f"adapt first for {e['platform']}",
                    "effect": e["effect"]})
choices.append({"label": "stop here",
                "effect": "emits nothing; no variant file is written anywhere"})
print(json.dumps({"items": [{
    "where": "Emission targets for canonical retry-storms, language en, "
             "at the resolved drafts destination.",
    "why": "Which configured platforms actually get a file is your publish "
           "decision; a platform whose reader speaks another language is "
           "reached by deriving a canonical first, not by projecting this one.",
    "choices": choices}]}, ensure_ascii=False))
PY
python3 "$VP" --surface variant-emission "$work/screen.json" >/dev/null 2>"$work/e-vp" \
  && ok "the composed selection screen passes validate-proposal-payload.py" \
  || err "the screen is not presentable: $(cat "$work/e-vp")"
python3 -c "
import json
o=json.load(open('$work/screen.json'))
labels=[c['label'] for c in o['items'][0]['choices']]
assert 'zenn' not in labels, labels
assert 'adapt first for zenn' in labels, labels
assert 'stop here' in labels, labels
" && ok "the screen offers no direct zenn projection, and \`stop here\` stays first-class" \
  || err "the composed screen still offers a direct cross-language projection"

# --- CAP-1 stays true: emission never invokes adaptation ---------------------
if grep -rn "adapt-canonical\|adapt_canonical" scripts/draft-pipeline.py \
     skills/draft-article/ skills/emit-variants/ >/dev/null 2>&1; then
  err "the emission path invokes adaptation (CAP-1 forbids it)"
else
  ok "the emission path names the route but never invokes adaptation"
fi

# --- the shipped emission harnesses keep passing verbatim --------------------
for c in check-stage5-variants.sh check-platform-lint.sh check-ja-emission.sh \
         check-canonical-adaptation.sh; do
  sh "scripts/$c" >/dev/null 2>&1 && ok "$c passes unchanged" || err "$c regressed"
done

# --- lockstep: the SKILL states the shipped offer ----------------------------
for token in 'adapt first' 'adapt_first' 'direct' 'stop here' \
             'never what the owner may do' 'language-mismatch'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the contract text: $token" \
    || err "SKILL is missing contract text: $token"
done

[ "$fail" -eq 0 ] && printf '\nAll cross-language-offer checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
