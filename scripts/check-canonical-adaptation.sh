#!/usr/bin/env sh
# check-canonical-adaptation.sh — verify canonical adaptation as a STANDALONE,
# OWNER-GATED invocation (Story 18.56, SPEC-canonical-adaptation CAP-1 + CAP-3):
# the source is the persisted, reviewed canonical (an unreviewed draft, a
# marker-carrying draft and a run-workspace copy are each refused naming the
# remedy); the adaptation target is a POINTER at a platform profile, so no
# language is branched on in code; the plan payload passes the shared proposal
# gate before presentation and offers approve / modify / stop; nothing is
# written before the owner's answer; and no draft-flow stage and no emission
# path invokes adaptation.
# POSIX shell + stdlib Python only. Every fixture write lands under mktemp -d.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

AC="$root/scripts/adapt-canonical.py"
VP="$root/scripts/validate-proposal-payload.py"
SKILL="skills/adapt-canonical/SKILL.md"
CONV="config/language-conventions.yaml"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$AC', doraise=True)" 2>/dev/null \
  && ok "adapt-canonical compiles" || { err "syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# --- fixture: a host repo whose output.drafts lives under the temp tree -------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host" "$work/drafts" "$work/ws"
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $work/drafts/
YAML
ppdir="$work/profiles"; mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"
A="python3 $AC"
ARGS="--root $work/host --profiles-dir $ppdir"

cat > "$work/drafts/retry-storms.md" <<'EOF'
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

## What it cost

Two engineer-days and one weekend.
EOF

cat > "$work/fill.json" <<'EOF'
{
  "refounded_opening": "The target reader has no context on our billing setup, so the opening states the cost outcome first and introduces the retry policy after it.",
  "structural_mapping": [
    {"source_section": "The incident", "disposition": "move", "note": "moves after the payoff; the target reader expects the result first"},
    {"source_section": "What we changed", "disposition": "keep", "note": "the how-to core, unchanged in order"},
    {"source_section": "What it cost", "disposition": "drop", "note": "internal staffing cost carries no meaning for this reader"}
  ],
  "recomposed_title": "Retry policy runaway: capping backoff before the bill arrives",
  "omissions": [
    {"section": "What it cost", "what": "the two engineer-days figure", "reason": "an internal staffing number the target reader cannot use"}
  ]
}
EOF

# --- CAP-1 refusal 1: no persisted canonical (unreviewed / never completed) ---
if $A plan --slug never-completed --target zenn $ARGS >/dev/null 2>"$work/e1"; then
  err "adaptation ran with no persisted canonical"
else
  grep -q 'no persisted canonical' "$work/e1" && grep -q 'complete' "$work/e1" \
    && ok "no persisted canonical is refused, naming the \`complete\` remedy" \
    || err "missing-canonical refusal does not name the remedy: $(cat "$work/e1")"
fi

# --- CAP-1 refusal 2: a run-workspace copy, not the persisted canonical -------
cp "$work/drafts/retry-storms.md" "$work/ws/retry-storms.md"
if $A plan --slug retry-storms --target zenn --draft "$work/ws/retry-storms.md" $ARGS \
     >/dev/null 2>"$work/e2"; then
  err "a run-workspace copy was accepted as the adaptation source"
else
  grep -q 'not the persisted canonical' "$work/e2" && grep -q 'complete --draft' "$work/e2" \
    && ok "a run-workspace copy is refused with the \`complete\` remedy (same as the variant stage)" \
    || err "workspace-copy refusal wrong: $(cat "$work/e2")"
fi

# --- CAP-1 refusal 3: a marker-carrying (unreviewed) canonical ----------------
sed 's/we caught it late./we caught it late [VERIFY: exact detection lag]./' \
  "$work/drafts/retry-storms.md" > "$work/drafts/marked.md"
sed -i 's/^slug: retry-storms$/slug: marked/' "$work/drafts/marked.md"
if $A plan --slug marked --target zenn $ARGS >/dev/null 2>"$work/e3"; then
  err "a [VERIFY]-carrying draft was adapted"
else
  grep -q 'unresolved \[VERIFY\] marker' "$work/e3" && grep -q 'Stage 4' "$work/e3" \
    && ok "a marker-carrying draft is refused, naming Stage 4 as the remedy" \
    || err "marker refusal wrong: $(cat "$work/e3")"
fi

# --- CAP-1 refusal 4: an unresolved audience_id ------------------------------
sed 's/^audience_id: en-practitioner$/audience_id: "{audience_id}"/' \
  "$work/drafts/retry-storms.md" | sed 's/^slug: retry-storms$/slug: noaud/' \
  > "$work/drafts/noaud.md"
if $A plan --slug noaud --target zenn $ARGS >/dev/null 2>"$work/e4"; then
  err "a draft with an unresolved audience_id was adapted"
else
  grep -q 'audience_id' "$work/e4" \
    && ok "an unresolved audience_id is refused, naming the field" \
    || err "audience refusal wrong: $(cat "$work/e4")"
fi

# --- OQ1 / CAP-6: the target is a profile pointer; register comes from data ---
$A plan --slug retry-storms --target zenn $ARGS > "$work/skel.json" 2>"$work/e5" \
  || err "skeleton plan failed: $(cat "$work/e5")"
python3 - "$work/skel.json" <<'PY' && ok "the target's reader/language come from the pointed-at profile; register + terminology from the language declaration" || err "target/convention resolution wrong"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["target"] == {"platform":"zenn","audience":"ja-practitioner","language":"ja"}, d["target"]
assert "です/ます" in d["register"], d["register"]
assert d["terminology"], d
assert d["filled"] is False and d["written"] is False, d
assert d["source"]["sections"] == ["The incident","What we changed","What it cost"], d["source"]
PY
if grep -nE "==\s*[\"']ja[\"']|[\"']ja[\"']\s*==|elif .*[\"']ja[\"']" scripts/adapt-canonical.py >/dev/null 2>&1; then
  err "a hardcoded language branch survives in the adaptation implementation (CAP-6)"
else ok "CAP-6: no hardcoded language branch in the adaptation implementation"; fi
grep -q '^  ja:' "$CONV" && grep -q '^  en:' "$CONV" \
  && ok "a second target is declaration: languages are keys in $CONV" \
  || err "$CONV declares no per-language conventions"

# A target whose profile does not exist is a pointed refusal (not a silent ja).
$A plan --slug retry-storms --target hashnode $ARGS >/dev/null 2>"$work/e6" \
  && err "an unknown target was accepted" \
  || { grep -q 'no platform profile' "$work/e6" \
       && ok "an unknown target names the missing profile" \
       || err "unknown-target refusal wrong: $(cat "$work/e6")"; }

# A same-reader target is not an adaptation — it is packaging.
$A plan --slug retry-storms --target devto $ARGS >/dev/null 2>"$work/e7" \
  && err "a same-reader target was accepted as an adaptation" \
  || { grep -q 'nothing to adapt' "$work/e7" \
       && ok "a same-reader/same-language target routes to emit variants instead" \
       || err "same-reader refusal wrong: $(cat "$work/e7")"; }

# --- CAP-3 plan discipline: unaccounted sections and silent drops are defects -
python3 - <<PY > "$work/badfill.json"
import json
f=json.load(open("$work/fill.json"))
f["structural_mapping"]=f["structural_mapping"][:2]
json.dump(f,open("$work/badfill.json","w"))
PY
$A plan --slug retry-storms --target zenn $ARGS --fill "$work/badfill.json" \
  >/dev/null 2>"$work/e8" \
  && err "a plan leaving a source section unaccounted was accepted" \
  || { grep -q 'does not account for source section' "$work/e8" \
       && ok "every source section must be accounted for in the structural mapping" \
       || err "unmapped-section message wrong: $(cat "$work/e8")"; }

python3 - <<PY > /dev/null
import json
f=json.load(open("$work/fill.json"))
f["omissions"]=[]
json.dump(f,open("$work/silentdrop.json","w"))
PY
$A plan --slug retry-storms --target zenn $ARGS --fill "$work/silentdrop.json" \
  >/dev/null 2>"$work/e9" \
  && err "a silently dropped section was accepted" \
  || { grep -q 'no declared omission' "$work/e9" \
       && ok "a dropped section must be a DECLARED omission, never implicit" \
       || err "silent-drop message wrong: $(cat "$work/e9")"; }

python3 - <<PY > /dev/null
import json
f=json.load(open("$work/fill.json"))
f["register"]="proposed per article"
json.dump(f,open("$work/proposedreg.json","w"))
PY
$A plan --slug retry-storms --target zenn $ARGS --fill "$work/proposedreg.json" \
  >/dev/null 2>"$work/e10" \
  && err "register was accepted as a per-article proposal" \
  || { grep -q 'declared data' "$work/e10" \
       && ok "register/terminology are declared invariants, not per-article proposals" \
       || err "declared-only message wrong: $(cat "$work/e10")"; }

# --- CAP-3: one screen, through the shared proposal gate, approve/modify/stop -
$A payload --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  > "$work/payload.json" 2>"$work/e11" || err "payload composition failed: $(cat "$work/e11")"
python3 "$VP" --ws "$work/ws" --surface adaptation-plan "$work/payload.json" \
  > "$work/ask.json" 2>"$work/e12" \
  && ok "the plan payload passes validate-proposal-payload.py (presentable)" \
  || err "plan payload BLOCKED by the shared gate: $(cat "$work/e12")"
python3 - "$work/payload.json" <<'PY' && ok "one screen carrying opening, mapping, register, terminology, title and omissions; options approve/modify/stop, each naming its effect" || err "payload shape wrong"
import json,sys
d=json.load(open(sys.argv[1]))
items=d["items"]
assert len(items)==1, "one gate, one screen"
it=items[0]
plan=it["plan"]
for k in ("refounded opening","structural mapping","register","terminology",
          "recomposed title","declared omissions"):
    assert plan.get(k), k
assert "です/ます" in plan["register"], plan["register"]
assert [c["label"] for c in it["choices"]]==["approve","modify","stop"], it["choices"]
for c in it["choices"]:
    assert c["effect"].strip(), c
assert "retry-storms.ja.md" in it["choices"][0]["effect"], it["choices"][0]
assert "writes nothing" in it["choices"][2]["effect"], it["choices"][2]
PY

# --- CAP-3: nothing is written before the owner answers ----------------------
[ "$(ls "$work/drafts")" = "$(printf 'marked.md\nnoaud.md\nretry-storms.md')" ] \
  && ok "no derived canonical is written at the gate (output.drafts unchanged)" \
  || err "the gate wrote into output.drafts: $(ls "$work/drafts")"
ls "$work/drafts" | grep -q '\.ja\.md$' && err "a derived canonical appeared before the answer" \
  || ok "no <slug>.ja.md exists before an answer is recorded"

# The answer is recorded in the RUN WORKSPACE, against the returned ask_id.
ask=$(python3 -c "import json;print(json.load(open('$work/ask.json'))['ask_id'])")
printf '%s' '{"selection":"approve","free_text":""}' \
  | python3 "$VP" --ws "$work/ws" --answer "$ask" >/dev/null 2>&1 \
  && ok "the owner's answer is recorded in the run workspace against the ask_id" \
  || err "answer recording failed"
grep -q '"kind": "answer"' "$work/ws/presented-payloads.jsonl" \
  && ok "the recorded answer lands in the run workspace log, not the host tree" \
  || err "no answer record in the run workspace"

# --- CAP-1: no draft-flow stage and no emission path invokes adaptation -------
if grep -rn "adapt-canonical\|adapt_canonical" scripts/draft-pipeline.py \
     skills/draft-article/ skills/emit-variants/ >/dev/null 2>&1; then
  err "a draft-flow stage or emission path invokes adaptation (CAP-1 forbids it)"
else
  ok "no draft-flow stage and no emission path invokes adaptation"
fi
if grep -rn "draft-pipeline.py" "$SKILL" >/dev/null 2>&1; then
  grep -q 'never a stage' "$SKILL" || err "the skill does not state it is never a draft-flow stage"
fi

# --- lockstep: the SKILL prose describes exactly the mechanics checked above --
[ -f "$SKILL" ] && ok "the adapt-canonical skill exists" || err "$SKILL missing"
for token in 'never a stage of the draft flow' 'persisted canonical' 'complete' \
             'validate-proposal-payload.py' 'approve' 'modify' 'stop' \
             'adapt-canonical.py' '--target' 'language-conventions.yaml' \
             'nothing is written'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the contract text: $token" \
    || err "SKILL is missing contract text: $token"
done

[ "$fail" -eq 0 ] && printf '\nAll canonical-adaptation checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
