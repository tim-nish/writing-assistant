#!/usr/bin/env sh
# check-stage5-variants.sh — verify variant emission as a PROFILE-DRIVEN
# projection (Story 16.3, SPEC-platform-variants CAP-4) and, since Story 13.69,
# as a STANDALONE POST-REVIEW invocation over the PERSISTED canonical
# (SPEC-platform-variants CAP-1/CAP-3): variants are projections of the
# canonical draft through declared platform profiles; no hardcoded dev.to/Zenn
# builder remains in stage code; frontmatter and visual treatment come from the
# profile's packaging; the profile-resolution log lands in $WS and only variant
# files land at output.drafts; the sanctioned input is `--slug` over
# <output.drafts>/<slug>.md, a workspace copy is refused, and the draft-flow
# SKILL carries no platform decision point. Fixture invocations that feed a
# synthetic draft use the test-only --allow-external-draft escape.
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

# 1. AC1 — no hardcoded platform builders / identifiers survive in stage code.
if grep -nE '_devto_variant|_zenn_variant|VARIANT_BUILDERS' scripts/draft-pipeline.py >/dev/null 2>&1; then
  err "hardcoded variant builders still present in stage code"
else ok "hardcoded variant builders removed"; fi
if grep -niE '\bdevto\b|\bzenn\b' scripts/draft-pipeline.py >/dev/null 2>&1; then
  err "platform identifiers (devto/zenn) still appear in stage code"
else ok "no platform identifiers in stage code (config + profiles carry them)"; fi

# Story 13.69 — the variants contract moved to the standalone skill file; the
# draft-flow SKILL keeps only a pointer section.
VARIANTS="skills/draft-article/variants.md"
[ -f "$VARIANTS" ] && ok "standalone variants.md exists" || err "variants.md missing"
grep -qi 'never a hardcoded' "$VARIANTS" && ok "variants.md states the config-driven (not hardcoded) mapping" || err "config-driven claim missing from variants.md"
grep -q 'output.drafts' "$VARIANTS" && ok "variants.md writes to the resolved output.drafts location" || err "output.drafts wiring missing from variants.md"
grep -q 'persisted canonical' "$VARIANTS" && ok "variants.md consumes the persisted canonical" || err "persisted-canonical substrate missing from variants.md"
grep -q -- '--slug' "$VARIANTS" && ok "variants.md documents the sanctioned --slug form" || err "--slug form missing from variants.md"
for token in 'audience_id' 'lint-platform-variant' 'variant-staleness' 'site-record' 'lede' 'canonical-sha256'; do
  grep -q -- "$token" "$VARIANTS" && ok "variants.md carries the moved contract: $token" \
    || err "variants.md lost contract text: $token"
done

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
audience: en-practitioner
audience_id: en-practitioner
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
out=$(python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/o" --ws "$work" --platforms devto)
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["mode"]=="canonical" and d["language"]=="en", d
assert [e["platform"] for e in d["emitted"]]==["devto"], d
assert d["chosen"]==["devto"], d
assert d["next_stage"]=="review", d
assert d.get("render_blockers")==[{"platform":"devto","blocker":"unrendered-mermaid"}], d
' && ok "EN emits exactly a dev.to variant (config-selected, profile-projected)" \
  || err "EN variant selection/shape wrong"

DEVTO="$work/o/retry-storms.devto.md"
[ -f "$DEVTO" ] && ok "dev.to file written to the output location" || err "dev.to file not written"
grep -q '^canonical_url: https://example.com/articles/retry-storms$' "$DEVTO" \
  && ok "dev.to canonical_url composed from owner value + profile format" || err "canonical_url wrong"
grep -q 'The retry storm doubled token spend' "$DEVTO" \
  && ok "projection carries the article body unchanged" || err "dev.to body missing"
grep -q '<!-- render blocker' "$DEVTO" \
  && ok "dev.to visuals=html-comment-blocked wraps the diagram (dev.to has no Mermaid)" || err "dev.to visual treatment wrong"

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
audience: ja-practitioner
audience_id: ja-practitioner
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
out=$(python3 "$DP" variants "$work/ja.md" --allow-external-draft --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/o" --platforms zenn)
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["mode"]=="external", d
assert [e["platform"] for e in d["emitted"]]==["zenn"], d
assert "render_blockers" not in d, d  # Zenn renders Mermaid natively — no blocker
' && ok "JA emits a Zenn variant, Mermaid embedded (no blocker)" || err "JA variant/blocker wrong"

ZENN="$work/o/retry-arashi.zenn.md"
grep -q '^type: "tech"$' "$ZENN" && grep -q '^emoji:' "$ZENN" && grep -q '^published: false$' "$ZENN" \
  && ok "Zenn frontmatter (emoji/type/published) from the profile" || err "Zenn frontmatter wrong"
grep -q '本文。' "$ZENN" && ok "Zenn projection carries the full body" || err "Zenn body missing"
grep -q '```mermaid' "$ZENN" \
  && ok "Zenn visuals=mermaid-embedded leaves the diagram inline (native render)" || err "Zenn visual treatment wrong"

# 4. A configured platform with no profile is a clear, actionable error.
cat > "$work/cfg-noprofile.json" <<'EOF'
{"syndication":{"policy":{"en":{"mode":"canonical","variants":["hashnode"]}}}}
EOF
if python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg-noprofile.json" \
     --root "$work/host" --out "$work/o" --platforms hashnode >/dev/null 2>"$work/e_np"; then
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
python3 "$DP" variants "$work/bad.md" --allow-external-draft --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/o" --platforms devto >/dev/null 2>&1 \
  && err "emitted variants for an unverified draft" || ok "unresolved [VERIFY] aborts Stage 5"

# 6. External output.drafts guard (#213): a config-resolved destination OUTSIDE
#    the host repo that does not exist is refused without --create-out.
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $work/external-drafts/
YAML
if python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg.json" \
     --root "$work/host" --platforms devto >/dev/null 2>"$work/e_ext"; then
  err "external missing output dir was not refused"
else
  grep -q 'outside the host repo' "$work/e_ext" \
    && ok "external missing output dir refused, names the boundary" \
    || err "external refusal message wrong: $(cat "$work/e_ext")"
fi
[ ! -d "$work/external-drafts" ] && ok "refusal created nothing" || err "refusal created the directory"
python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg.json" \
  --root "$work/host" --create-out --platforms devto >/dev/null 2>/dev/null \
  && [ -f "$work/external-drafts/retry-storms.devto.md" ] \
  && ok "--create-out consents to creating the external destination" \
  || err "--create-out did not create/write the external destination"
rm -f "$work/host/writing-sources.yaml"

# 7. --dry-run reports without writing.
rm -rf "$work/dry"
python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/dry" --dry-run --platforms devto | python3 -c '
import json,sys; d=json.load(sys.stdin); assert d["written"] is False, d'
[ ! -d "$work/dry" ] && ok "--dry-run writes nothing" || err "--dry-run wrote files"

# 8. Story 16.4 — emission is the owner's explicit choice; never auto-emit all.
#    Config where EN offers BOTH platforms, to prove selection.
cat > "$work/cfg-both.json" <<'EOF'
{"syndication":{"policy":{"en":{"mode":"canonical","variants":["devto","zenn"]}},
"variants":{"devto":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
rm -rf "$work/e8"
# 8a. No choice → reports the options and emits NOTHING (never auto-emit all).
out=$(python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg-both.json" \
        --root "$work/host" --out "$work/e8")
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["available"]==["devto","zenn"] and d["emitted"]==[], d' \
  && ok "no explicit choice reports options and emits nothing (never auto-emit all)" \
  || err "auto-emit guard wrong"
[ ! -d "$work/e8" ] && ok "no files written without an explicit choice" || err "files written without a choice"

# 8b. --list-platforms reports the choices for the in-conversation selection.
python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg-both.json" \
  --root "$work/host" --list-platforms | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["available"]==["devto","zenn"] and d["emitted"]==[], d' \
  && ok "--list-platforms reports the emission choices" || err "--list-platforms wrong"

# 8c. Owner picks only dev.to → no Zenn file exists anywhere; choice recorded.
out=$(python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg-both.json" \
        --root "$work/host" --out "$work/e8" --platforms devto)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["chosen"]==["devto"] and [e["platform"] for e in d["emitted"]]==["devto"], d' \
  && ok "owner picks dev.to only; choice recorded in the summary" || err "single-choice emission wrong"
[ -f "$work/e8/retry-storms.devto.md" ] && [ ! -f "$work/e8/retry-storms.zenn.md" ] \
  && ok "picking dev.to leaves no Zenn file anywhere (FR57)" || err "unwanted variant file present"

# 8d. Emission metadata: the canonical draft's content hash rides with the variant.
grep -q 'canonical-sha256=[0-9a-f]\{64\}' "$work/e8/retry-storms.devto.md" \
  && ok "emitted variant carries the canonical content hash (for 16.7 stale detection)" \
  || err "canonical-sha256 metadata missing from the variant"

# 8e. A platform not in the configured set is rejected.
python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg-both.json" \
  --root "$work/host" --out "$work/e8" --platforms medium >/dev/null 2>"$work/e_bad" \
  && err "an unconfigured platform choice was accepted" \
  || { grep -q 'not configured' "$work/e_bad" && ok "unconfigured platform choice rejected" \
       || err "unconfigured-choice message wrong"; }

# 9. Story 16.5 (amended 13.71) — deterministic lede-retarget trigger over
#    audience_id/language/register. The EN draft (audience_id en-practitioner,
#    language en) matches the dev.to profile → no proposal; it differs from the
#    Zenn profile (ja-practitioner, ja) → exactly one lede proposal (です/ます).
rm -rf "$work/e9"
out=$(python3 "$DP" variants "$work/en.md" --allow-external-draft --config-json "$work/cfg-both.json" \
        --root "$work/host" --out "$work/e9" --platforms all)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
rt={e["platform"]:e["lede_retarget"] for e in d["emitted"]}
assert rt=={"devto":False,"zenn":True}, d
props=d.get("lede_proposals",[])
assert len(props)==1 and props[0]["platform"]=="zenn", d
assert props[0]["register"]=="です/ます", d' \
  && ok "lede trigger: match=no proposal, audience/language mismatch=one proposal" \
  || err "lede-retarget trigger wrong"

# 9b. The pipeline-internal audience field is stripped from emitted variants.
grep -q '^audience:' "$work/e9/retry-storms.devto.md" \
  && err "audience field leaked into the emitted variant" \
  || ok "audience is stripped from emitted variant frontmatter"

# 9c. A draft with an unfilled audience is a hard stop before any variant.
sed 's/^audience:.*/audience: {audience}/' "$work/en.md" > "$work/noaud.md"
python3 "$DP" variants "$work/noaud.md" --allow-external-draft --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/e9" --platforms devto >/dev/null 2>"$work/e_aud" \
  && err "a draft with an unfilled audience was accepted" \
  || { grep -q 'no resolved `audience`' "$work/e_aud" \
       && ok "unfilled audience is a hard stop (presence enforced)" \
       || err "audience-presence message wrong: $(cat "$work/e_aud")"; }

# --- Story 13.71 (#363): audience_id compatibility trigger ---
# 9d. Free-text named reader + matching audience_id → pure packaging (the
#     2026-07-18 spurious-touchpoint case is dead: free text is never compared).
sed 's/^audience:.*/audience: Solo technical builders with low visibility/' "$work/en.md" > "$work/freetext.md"
rm -rf "$work/e9d"
out=$(python3 "$DP" variants "$work/freetext.md" --allow-external-draft --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/e9d" --platforms devto)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["emitted"][0]["lede_retarget"] is False, d
assert not d.get("lede_proposals"), d' \
  && ok "free-text named reader with matching audience_id fires no touchpoint (13.71)" \
  || err "same-reader emission still fired the lede trigger"

# 9e. audience_id is stripped from emitted variants like audience.
grep -q '^audience_id:' "$work/e9d/retry-storms.devto.md" \
  && err "audience_id leaked into the emitted variant" \
  || ok "audience_id is stripped from emitted variant frontmatter (13.71)"

# 9f. A draft with an unfilled audience_id is a hard stop (never re-inferred).
sed 's/^audience_id:.*/audience_id: {audience_id}/' "$work/en.md" > "$work/noaudid.md"
python3 "$DP" variants "$work/noaudid.md" --allow-external-draft --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/e9" --platforms devto >/dev/null 2>"$work/e_audid" \
  && err "a draft with an unfilled audience_id was accepted" \
  || { grep -q 'no resolved `audience_id`' "$work/e_audid" \
       && ok "unfilled audience_id is a hard stop — never inferred at emission (13.71)" \
       || err "audience_id-presence message wrong: $(cat "$work/e_audid")"; }

# 9g. Register is the third compared field: a declared register delta at the
#     same audience_id/language still fires exactly one proposal.
sed 's/^audience_id:.*/audience_id: en-practitioner\nregister: です\/ます/' "$work/en.md" > "$work/reg.md"
rm -rf "$work/e9g"
out=$(python3 "$DP" variants "$work/reg.md" --allow-external-draft --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/e9g" --platforms devto)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert d["emitted"][0]["lede_retarget"] is True, d
assert len(d.get("lede_proposals",[]))==1, d' \
  && ok "register delta alone fires the trigger (13.71)" \
  || err "register comparison not part of the trigger"

# --- Story 13.69 (#370): standalone post-review invocation over the persisted
#     canonical (SPEC-platform-variants CAP-1/CAP-3) ---
# 10. The sanctioned `--slug` form loads <output.drafts>/<slug>.md. Persist a
#     canonical with the 13.68 emission trailer (complete's convention), then
#     emit; the variant must record the SAME hash the trailer carries (one hash
#     convention) and carry exactly one trailer (the inherited one is stripped).
mkdir -p "$work/drafts"
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $work/drafts/
YAML
python3 - "$work/en.md" "$work/drafts/retry-storms.md" <<'EOF'
import hashlib, sys
body = open(sys.argv[1], encoding="utf-8").read().rstrip("\n") + "\n"
sha = hashlib.sha256(body.encode("utf-8")).hexdigest()
open(sys.argv[2], "w", encoding="utf-8").write(
    body + f"\n<!-- writing-assistant: canonical-sha256={sha} -->\n")
EOF
rm -rf "$work/e10"
out=$(python3 "$DP" variants --slug retry-storms --config-json "$work/cfg.json" \
        --root "$work/host" --out "$work/e10" --platforms devto)
printf '%s' "$out" | python3 -c '
import json,sys; d=json.load(sys.stdin)
assert [e["platform"] for e in d["emitted"]]==["devto"], d' \
  && [ -f "$work/e10/retry-storms.devto.md" ] \
  && ok "sanctioned --slug form emits from the persisted canonical (13.69)" \
  || err "--slug form did not emit from the persisted canonical"
python3 - "$work/drafts/retry-storms.md" "$work/e10/retry-storms.devto.md" <<'EOF' \
  && ok "variant records the persisted canonical trailer's own hash (one convention)" \
  || err "variant hash differs from the persisted canonical trailer"
import re, sys
rx = re.compile(r"canonical-sha256=([0-9a-f]{64})")
canon = rx.findall(open(sys.argv[1], encoding="utf-8").read())
var = rx.findall(open(sys.argv[2], encoding="utf-8").read())
assert len(var) == 1, var        # inherited trailer stripped, one trailer only
assert canon == var, (canon, var)
EOF

# 10b. A positional path that IS the persisted canonical needs no escape flag.
python3 "$DP" variants "$work/drafts/retry-storms.md" --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/e10" --platforms devto >/dev/null 2>&1 \
  && ok "positional path inside output.drafts accepted (it is the canonical)" \
  || err "persisted canonical rejected when passed positionally"

# 11. A workspace-style path (outside output.drafts) without the escape flag is
#     a hard error naming the expected persisted path and the complete remedy —
#     never a silent fallback to the workspace copy.
if python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
     --root "$work/host" --out "$work/e10" --platforms devto >/dev/null 2>"$work/e_ws"; then
  err "a workspace draft outside output.drafts was accepted without the escape flag"
else
  grep -q 'retry-storms.md' "$work/e_ws" && grep -q 'complete' "$work/e_ws" \
    && ok "workspace draft refused; error names the persisted path + complete remedy" \
    || err "workspace refusal message wrong: $(cat "$work/e_ws")"
fi

# 11b. The sanctioned form over a slug with NO persisted canonical refuses,
#      pointing at the draft flow's completion.
if python3 "$DP" variants --slug never-completed --config-json "$work/cfg.json" \
     --root "$work/host" --out "$work/e10" --platforms devto >/dev/null 2>"$work/e_nc"; then
  err "--slug with no persisted canonical was accepted"
else
  grep -q 'no persisted canonical' "$work/e_nc" && grep -q 'complete' "$work/e_nc" \
    && ok "missing persisted canonical refused with the complete remedy (AC3)" \
    || err "missing-canonical message wrong: $(cat "$work/e_nc")"
fi
rm -f "$work/host/writing-sources.yaml"

# 12. AC1/AC4 — the draft-flow SKILL carries no platform decision point: the
#     Stage-5 emission flow is gone, no platform identifiers or emission flags
#     remain, and only a short pointer section references the standalone
#     invocation.
grep -q '^## Stage 5' "$SKILL" \
  && err "SKILL still carries a Stage-5 section (variants must be post-review)" \
  || ok "Stage-5 heading gone from the draft-flow SKILL"
if grep -nE -e 'dev\.to|[Dd]evto|[Zz]enn|--platforms|--list-platforms' "$SKILL" >/dev/null 2>&1; then
  err "platform decision point survives in the draft-flow SKILL:"
  grep -nE -e 'dev\.to|[Dd]evto|[Zz]enn|--platforms|--list-platforms' "$SKILL" >&2
else
  ok "no platform decision point in the draft-flow stages (AC1)"
fi
ptr=$(awk '/^## Platform variants — a separate post-review invocation/{f=1;next} f && /^## /{exit} f{print}' "$SKILL")
[ -n "$ptr" ] && ok "SKILL keeps a pointer section to the standalone invocation" \
  || err "pointer section missing from the SKILL"
printf '%s\n' "$ptr" | grep -q 'variants.md' \
  && printf '%s\n' "$ptr" | grep -q -- '--slug' \
  && ok "pointer names variants.md and the sanctioned --slug form" \
  || err "pointer section incomplete"
[ "$(printf '%s\n' "$ptr" | wc -l)" -le 30 ] \
  && ok "pointer section is a pointer (≤30 lines), not the emission flow" \
  || err "pointer section too large — emission flow leaked back into the SKILL"

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage-5 variant checks passed.\n'; exit 0
else
  printf '\nstage-5 variant checks FAILED.\n' >&2; exit 1
fi
