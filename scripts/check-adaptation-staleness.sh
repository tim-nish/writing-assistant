#!/usr/bin/env sh
# check-adaptation-staleness.sh — verify staleness CHAINS through the derivation
# (Story 18.58, #589; SPEC-canonical-adaptation CAP-5). POSIX sh + stdlib Python;
# every fixture write lands under mktemp -d.
#
# The chain: EN canonical edit -> JA canonical stale -> its Zenn variant stale.
#
# Covers:
#   CAP-5  a derivation whose recorded source hash no longer matches lands in the
#          PUBLISH-BLOCKER bucket with the hash pair (never a warning, never
#          silent); its variants are reported stale-by-inheritance in the same
#          bucket carrying the upstream link, even when their own recorded hash
#          still matches; a derivation whose source has NOT moved is graded by
#          the shipped variant-staleness mechanism unchanged; the blocker names
#          re-adaptation as a fresh owner decision, never an implicit re-run;
#          a completed re-adaptation records the new source hash and clears it.
#   Scope  the existing single-level variant-staleness behaviour is untouched
#          (check-stale-variant.sh must keep passing — asserted here too).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

AC="$root/scripts/adapt-canonical.py"
DP="$root/scripts/draft-pipeline.py"
VP="$root/scripts/validate-proposal-payload.py"
SKILL="skills/adapt-canonical/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$AC', doraise=True)" 2>/dev/null \
  && ok "adapt-canonical compiles" || { err "syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host" "$work/drafts" "$work/ws"
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $work/drafts/
YAML
# The profiles live where the RESOLVER looks, so `variants` (which has no
# --profiles-dir escape) sees the same declarations the adaptation does.
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"
A="python3 $AC"
ARGS="--root $work/host --profiles-dir $ppdir"

cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
                          "ja":{"mode":"canonical","variants":["zenn"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"},
             "zenn":{"canonical_url_base":"https://example.com/articles"}}}}
EOF

cat > "$work/source.md" <<'EOF'
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
cp "$work/source.md" "$work/drafts/retry-storms.md"

cat > "$work/fill.json" <<'EOF'
{
  "refounded_opening": "The target reader has no context on our billing setup, so the opening states the cost outcome first.",
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

指数バックオフに上限を設け、予算アラートを追加した。

## 何が起きたか

リトライの連鎖でトークン消費が倍増し、発見が遅れた。
EOF

# --- fixture: adapt, then emit the derivation's zenn variant -----------------
$A payload --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" > "$work/payload.json"
ask=$(python3 "$VP" --ws "$work/ws" --surface adaptation-plan "$work/payload.json" \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["ask_id"])')
printf '%s' '{"selection":"approve","free_text":""}' \
  | python3 "$VP" --ws "$work/ws" --answer "$ask" >/dev/null
$A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  --body "$work/body.ja.md" --ws "$work/ws" > "$work/written.json" 2>"$work/e-write" \
  || { err "fixture adaptation failed: $(cat "$work/e-write")"; printf '\nFAILED.\n' >&2; exit 1; }

python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg.json" --platforms zenn --ws "$work/ws" \
  > "$work/emit.json" 2>"$work/e-emit" \
  || { err "fixture emission failed: $(cat "$work/e-emit")"; printf '\nFAILED.\n' >&2; exit 1; }
[ -f "$work/drafts/retry-storms.ja.zenn.md" ] \
  && ok "fixture: the derivation and its zenn variant both exist" \
  || err "fixture emission wrote no variant: $(ls "$work/drafts")"

# --- source unmoved: the shipped mechanism applies to the derivation, unchanged
$A staleness --root "$work/host" > "$work/fresh.json"
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/fresh.json"))
d = o["derivations"]
assert len(d) == 1, d
assert d[0]["status"] == "fresh", d[0]
assert o.get("publish_blockers") is None, o["publish_blockers"]
assert [v["status"] for v in d[0]["variants"]] == ["fresh"], d[0]["variants"]
print("ok:   an unmoved source leaves the derivation and its variants fresh")
PY

# Editing the DERIVATION alone: only its own variants go stale, no upstream
# blocker fires (the source has not moved).
printf '\n追記。\n' >> "$work/drafts/retry-storms.ja.md"
$A staleness --root "$work/host" > "$work/derived-edited.json"
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/derived-edited.json"))
b = o.get("publish_blockers") or []
kinds = {x["blocker"] for x in b}
assert kinds == {"stale-variant"}, kinds
assert o["derivations"][0]["status"] == "fresh", o["derivations"][0]
print("ok:   editing the derivation alone stales only its own variants (existing "
      "mechanism, unchanged)")
print("ok:   no upstream blocker fires when the source canonical has not moved")
PY
# restore the derivation
$A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  --body "$work/body.ja.md" --ws "$work/ws" >/dev/null
python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg.json" --platforms zenn --ws "$work/ws" >/dev/null

# --- CAP-5: edit the SOURCE -> the chain lights up ---------------------------
printf '\n## What it cost\n\nTwo engineer-days.\n' >> "$work/drafts/retry-storms.md"
$A staleness --root "$work/host" > "$work/chained.json"
python3 - "$work" <<'PY' || fail=1
import json, sys, hashlib, os, importlib.util
work = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "dp", os.path.join(os.getcwd(), "scripts", "draft-pipeline.py"))
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
o = json.load(open(work + "/chained.json"))
blockers = o.get("publish_blockers") or []
by = {b["blocker"]: b for b in blockers}
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

check("stale-derivation" in by,
      "an edited source canonical puts the derivation in the publish-blocker bucket")
check("stale-by-inheritance" in by,
      "the derivation's variant is reported stale-by-inheritance in the same bucket")

sd = by.get("stale-derivation", {})
cur = hashlib.sha256(dp._strip_emission_trailer(
    open(work + "/drafts/retry-storms.md", encoding="utf-8").read()
).encode("utf-8")).hexdigest()
check(sd.get("current_sha256") == cur and len(sd.get("recorded_sha256", "")) == 64
      and sd["recorded_sha256"] != cur,
      "the derivation blocker carries the hash pair (recorded vs current)")
detail = sd.get("detail", "").lower()
check("fresh owner decision" in detail
      and "never an implicit re-run" in detail
      and "never an in-place edit" in detail,
      "the blocker names re-adaptation as a fresh owner decision")

sbi = by.get("stale-by-inheritance", {})
check(sbi.get("upstream", "").endswith("retry-storms.ja.md"),
      "the inherited blocker carries the upstream link")
check(sbi.get("recorded_sha256") == sd.get("recorded_sha256")
      and sbi.get("current_sha256") == cur,
      "the inherited blocker carries the same hash pair as its upstream")
check(sbi.get("path", "").endswith(".zenn.md"),
      "the inherited blocker names the variant file")

# The variant's OWN hash still matches its derivation — inheritance is the only
# reason it is stale, which is precisely the failure this chain prevents.
d = o["derivations"][0]
check(all(v["status"] == "fresh" for v in d["variants"]),
      "the variant's own recorded hash still matches; only inheritance stales it")
check(d["status"] == "stale", "the derivation itself is reported stale")
sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || fail=1

# The EN canonical's own variant check is untouched by any of this.
python3 "$DP" variant-staleness "$work/drafts/retry-storms.md" \
  --root "$work/host" --out "$work/drafts" > "$work/en-stale.json"
python3 -c "
import json
o=json.load(open('$work/en-stale.json'))
assert not any(v['path'].endswith('.ja.md') for v in o['variants']), o['variants']
" && ok "the source's own variant check never grades the derivation as its variant" \
  || err "the derivation leaked into the source's variant list"

# --- CAP-5: a fresh re-adaptation records the new hash and clears the blocker --
printf '%s' '{"selection":"approve","free_text":""}' \
  | python3 "$VP" --ws "$work/ws" --answer "$ask" >/dev/null
cat > "$work/fill2.json" <<'EOF'
{
  "refounded_opening": "The target reader has no context on our billing setup, so the opening states the cost outcome first.",
  "structural_mapping": [
    {"source_section": "The incident", "disposition": "move", "note": "moves after the payoff; this reader expects the result first"},
    {"source_section": "What we changed", "disposition": "keep", "note": "the how-to core, unchanged in order"},
    {"source_section": "What it cost", "disposition": "drop", "note": "internal staffing cost carries no meaning for this reader"}
  ],
  "recomposed_title": "リトライ暴走を止める",
  "omissions": [
    {"section": "What it cost", "what": "the engineer-days figure",
     "reason": "an internal staffing number this reader cannot use"}
  ]
}
EOF
$A write --slug retry-storms --target zenn $ARGS --fill "$work/fill2.json" \
  --body "$work/body.ja.md" --ws "$work/ws" >/dev/null 2>"$work/e-re" \
  || { err "re-adaptation failed: $(cat "$work/e-re")"; }
python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg.json" --platforms zenn --ws "$work/ws" >/dev/null
$A staleness --root "$work/host" > "$work/cleared.json"
python3 -c "
import json
o=json.load(open('$work/cleared.json'))
assert o.get('publish_blockers') is None, o['publish_blockers']
assert o['derivations'][0]['status']=='fresh', o['derivations'][0]
" && ok "a completed re-adaptation records the new source hash and clears the blocker" \
  || err "the blocker survived a fresh re-adaptation: $(cat "$work/cleared.json")"

# --- re-adaptation is never implicit: the check WRITES nothing ---------------
before=$(ls "$work/drafts" | sort)
$A staleness --root "$work/host" >/dev/null
[ "$before" = "$(ls "$work/drafts" | sort)" ] \
  && ok "the staleness check writes nothing — re-adaptation is never implicit" \
  || err "the staleness check mutated output.drafts"

# --- a derivation whose source cannot be resolved is never silently fresh ----
sed 's/^adapted_from: .*/adapted_from: no-such-article@'"$(printf '0%.0s' $(seq 64))"'/' \
  "$work/drafts/retry-storms.ja.md" > "$work/drafts/orphan.ja.md"
$A staleness --root "$work/host" > "$work/orphan.json"
python3 -c "
import json
o=json.load(open('$work/orphan.json'))
b=[x for x in (o.get('publish_blockers') or []) if x['blocker']=='ancestry-source-missing']
assert b, o
s=[d for d in o['derivations'] if d['derived'].endswith('orphan.ja.md')][0]
assert s['status']=='unverifiable', s
" && ok "a derivation whose source will not resolve is a blocker, never silently fresh" \
  || err "an unresolvable derivation was not blocked: $(cat "$work/orphan.json")"
rm "$work/drafts/orphan.ja.md"

# --- the shipped single-level check keeps passing verbatim -------------------
sh scripts/check-stale-variant.sh >/dev/null 2>&1 \
  && ok "the shipped variant-staleness harness passes unchanged" \
  || err "check-stale-variant.sh regressed"

# --- lockstep: the SKILL states the chain ------------------------------------
for token in 'adapt-canonical.py staleness' 'stale-by-inheritance' \
             'publish blocker' 'fresh owner decision'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the contract text: $token" \
    || err "SKILL is missing contract text: $token"
done

[ "$fail" -eq 0 ] && printf '\nAll adaptation-staleness checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
