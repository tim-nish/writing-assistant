#!/usr/bin/env sh
# check-review-reentry.sh — verify review's post-arbitration re-entry (Story
# 13.70, #371, umbrella #362; SPEC-article-review "Post-arbitration re-entry",
# SPEC-platform-variants CAP-3). An arbitration round that applied >=1 edit
# must persist the reviewed canonical (the completion gate's write path and
# trailer convention), structurally validate the rebuilt provenance map against
# the edited draft, report the scoped regression checks, mark existing variants
# stale, write the done/reviewed checkpoint — and STOP: review never emits or
# re-emits a variant. An INVALID map (the origin failure: anchors dangling on
# blank lines) is a refusal — non-zero, named error, NO checkpoint. A
# zero-edit round is a strict no-op. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/review-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# --- (e) SKILL wiring -------------------------------------------------------
grep -q 'draft-pipeline.py review-reentry' "$SKILL" \
  && ok "SKILL invokes the review-reentry subcommand" || err "review-reentry not wired into the SKILL"
grep -q 'Post-arbitration re-entry' "$SKILL" \
  && ok "SKILL carries the post-arbitration re-entry section" || err "re-entry section missing"
grep -q 'FRESH isolated judge' "$SKILL" && grep -q '13.67' "$SKILL" \
  && ok "SKILL notes the fresh isolated judge + 13.67 attestation" \
  || err "fresh-judge / attestation note missing from the SKILL"
grep -q 'review-authored sentences' "$SKILL" \
  && ok "SKILL states review-authored sentences are classified like any other" \
  || err "review-authored classification note missing"
grep -qi 'never emits or re-emits a variant' "$SKILL" \
  && ok "SKILL states review never emits or re-emits a variant" \
  || err "no-re-emit constraint missing from the SKILL"
grep -q 'variants --slug' "$SKILL" \
  && ok "SKILL names the standalone variants invocation as the re-emission path" \
  || err "re-emission path (variants --slug) missing"
grep -q 'never hand-write the checkpoint' "$SKILL" \
  && ok "hand-written checkpoint is confined to zero-edit rounds" \
  || err "SKILL still allows hand-writing the checkpoint after edits"
grep -q 'Zero applied edits' "$SKILL" \
  && ok "zero-edit rounds keep the hand-written reviewed checkpoint" \
  || err "zero-edit checkpoint branch missing"
# Story 18.21 (#496): the SKILL wires the versioned v2 verdict persistence and
# states the re-entry gate refuses PASS over a missing/partial v2 record.
grep -q 'rubric-verdicts-v2.txt' "$SKILL" \
  && ok "SKILL wires the versioned rubric-verdicts-v2.txt persistence" \
  || err "SKILL does not wire the v2 verdict record"
grep -q 'verdicts-out' "$SKILL" \
  && ok "SKILL runs the re-run gate with --verdicts-out (reuse cmd_quality_gate)" \
  || err "SKILL missing the --verdicts-out re-run gate call"

# --- Fixture: host + articles repo, an OLD variant, an edited draft + map ----
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts"; git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1

slug=retry-storms
ws="$work/ws"; mkdir -p "$ws"
cat > "$ws/edited.md" <<'EOF'
---
slug: retry-storms
generated_by: writing-assistant@0.0.0-test+deadbee   # immutable birth record (#709)
---

The retry storm tripled load before the breaker fired.
Review sharpened this sentence during arbitration.
EOF
# The rebuilt map: anchors resolve to real non-blank lines of the edited draft;
# the review-authored sentence (L7) is classified like any other. NOTE: these
# anchors are line-coupled to the frontmatter above — adding the birth record
# (#709) shifted the body down one line, so L5/L6 became L6/L7.
cat > "$ws/map.txt" <<'EOF'
P1.S1[L6]: sourced <- docs/retries.md:12
P1.S2[L7]: narration
EOF
# A previously emitted variant recording the PRE-EDIT canonical's hash.
old_sha=$(printf 'the pre-edit canonical body\n' | python3 -c \
  "import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())")
variant="$a/drafts/$slug.devto.md"
cat > "$variant" <<EOF
Old variant body.

<!-- writing-assistant: canonical-sha256=$old_sha -->
EOF
v_before=$(python3 -c "import hashlib; print(hashlib.sha256(open('$variant','rb').read()).hexdigest())")
m_before=$(python3 -c "import os; print(os.stat('$variant').st_mtime_ns)")

# --- Story 18.21 (#496): --rubric-applied requires a PERSISTED, COMPLETE
# versioned verdict record (rubric-verdicts-v2.txt). Missing → refuse, no
# checkpoint; the re-entry may not claim PASS over an unpersisted record.
wsv="$work/wsv"; mkdir -p "$wsv"
if python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
     --slug "$slug" --root "$h" --ws "$wsv" --applied 2 --rubric-applied \
     >/dev/null 2>"$work/e_v2missing"; then
  err "review-reentry claimed PASS with no rubric-verdicts-v2.txt"
else
  grep -q 'rubric-verdicts-v2.txt' "$work/e_v2missing" \
    && grep -q 'not persisted' "$work/e_v2missing" \
    && ok "re-entry refuses --rubric-applied over a missing v2 verdict record" \
    || err "missing-v2 refusal message wrong: $(cat "$work/e_v2missing")"
fi
[ ! -f "$wsv/checkpoint.json" ] && ok "no checkpoint over a missing v2 verdict record" \
  || err "checkpoint written despite a missing v2 verdict record"
# A PARTIAL v2 record (the #492 dim1/dim2-only shape) is refused just the same.
printf 'dim1: pass\ndim2: pass\n' > "$wsv/rubric-verdicts-v2.txt"
if python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
     --slug "$slug" --root "$h" --ws "$wsv" --applied 2 --rubric-applied \
     >/dev/null 2>"$work/e_v2partial"; then
  err "review-reentry claimed PASS over a partial v2 verdict record"
else
  grep -q 'verdict record is partial' "$work/e_v2partial" \
    && grep -q 'dim3, dim4' "$work/e_v2partial" \
    && ok "re-entry refuses a partial v2 verdict record (names the gap)" \
    || err "partial-v2 refusal message wrong: $(cat "$work/e_v2partial")"
fi
[ ! -f "$wsv/checkpoint.json" ] && ok "no checkpoint over a partial v2 verdict record" \
  || err "checkpoint written despite a partial v2 verdict record"

# Persist a COMPLETE v2 record via the SAME gate path the SKILL prescribes
# (reuse cmd_quality_gate --verdicts-out): all four dims, dim3 inventory stamp,
# dim4 measures. The gate may exit non-zero on this fixture (no audience) but
# still writes the complete record — completeness, not all-pass, is the contract.
python3 "$DP" quality-gate --draft "$ws/edited.md" --map "$ws/map.txt" \
  --verdicts-out "$ws/rubric-verdicts-v2.txt" >/dev/null 2>&1 || true
[ -f "$ws/rubric-verdicts-v2.txt" ] \
  && ok "step-3 gate persisted the versioned v2 verdict record" \
  || err "v2 verdict record not written by the gate"
for d in 'dim1:' 'dim2:' 'dim3:' 'dim4:'; do
  grep -q "^$d" "$ws/rubric-verdicts-v2.txt" || err "v2 record missing $d"
done

# --- Story 19.15 (#751): the v2 record is SHA-BOUND, and freshness is refused
# alongside completeness — a complete-but-stale record never authorizes
# done/reviewed, and a pre-19.15 record (no attestation) is partial forever.
grep -q '^attestation: draft-sha256=' "$ws/rubric-verdicts-v2.txt" \
  && ok "#751: the gate stamps the v2 record with the draft sha" \
  || err "#751: v2 record carries no attestation line"
cp "$ws/rubric-verdicts-v2.txt" "$work/v2-good.txt"
printf 'stale-edit\n' >> "$ws/edited.md"
if python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
     --slug "$slug" --root "$h" --ws "$ws" --applied 2 --rubric-applied \
     >/dev/null 2>"$work/e_v2stale"; then
  err "#751: re-entry accepted a v2 record computed from an older draft"
else
  grep -q 'DIFFERENT draft version' "$work/e_v2stale" \
    && ok "#751: a stale v2 record is refused naming both shas" \
    || err "#751: stale-v2 refusal message wrong: $(cat "$work/e_v2stale")"
fi
grep -v '^attestation:' "$work/v2-good.txt" > "$ws/rubric-verdicts-v2.txt"
if python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
     --slug "$slug" --root "$h" --ws "$ws" --applied 2 --rubric-applied \
     >/dev/null 2>"$work/e_v2noatt"; then
  err "#751: re-entry accepted an attestation-less (pre-19.15) v2 record"
else
  grep -q 'no .attestation' "$work/e_v2noatt" \
    && ok "#751: an attestation-less v2 record is partial, never grandfathered" \
    || err "#751: no-attestation refusal message wrong: $(cat "$work/e_v2noatt")"
fi
# restore the good record + draft for the steps below
python3 "$DP" quality-gate --draft "$ws/edited.md" --map "$ws/map.txt" \
  --verdicts-out "$ws/rubric-verdicts-v2.txt" >/dev/null 2>&1 || true
grep -q '^dim3:.*dim3_inventory:' "$ws/rubric-verdicts-v2.txt" \
  && ok "v2 record is complete (four dims + dim3 inventory stamp)" \
  || err "v2 record missing its dim3 inventory stamp"

# --- (a) full sequence success ----------------------------------------------
out=$(python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
        --slug "$slug" --root "$h" --ws "$ws" --applied 2 --rubric-applied) \
  && ok "review-reentry succeeds on a valid map" || err "review-reentry failed on the success path"
[ -f "$a/drafts/$slug.md" ] && ok "reviewed canonical persisted at output.drafts" \
  || err "reviewed canonical not persisted"
printf '%s' "$out" | python3 -c "
import json,sys,os
d=json.load(sys.stdin)
assert d['stage']=='review-reentry' and d['next_stage']=='done', d
assert os.path.isabs(d['canonical']['path']), d
assert d['map_validation']['ok'] is True, d
checks=[c['check'] for c in d['required_checks']]
assert 'verify-provenance' in checks, d
assert 'quality-gate-mechanical' in checks, d
stale=[v['path'] for v in d['stale_variants']]
assert any(p.endswith('$slug.devto.md') for p in stale), d
assert all(v['status']=='stale' for v in d['stale_variants']), d
assert d['emitted_variants']==[], d
assert 'variants --slug $slug' in d['re_emission'], d
assert d['checkpoint'], d
assert os.path.isabs(d['verdicts_v2']) and d['verdicts_v2'].endswith('rubric-verdicts-v2.txt'), d
" && ok "re-entry JSON: valid map, scoped checks, stale variant listed, nothing emitted, v2 record path" \
  || err "re-entry JSON shape wrong"
# Story 18.21 (#496): the summary's dimension count is the RUBRIC's own, carried
# as rubric_dimensions — never a hardcoded literal. It must equal the count of
# `## Dimension N` sections in quality-rubric.md (four).
rn=$(grep -cE '^## Dimension [0-9]' "$root/skills/draft-article/quality-rubric.md")
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['rubric_dimensions']==$rn, (d.get('rubric_dimensions'), $rn)
" && ok "re-entry surfaces rubric_dimensions from the rubric ($rn), not a literal" \
  || err "rubric_dimensions does not match the rubric's dimension count"
# The canonical carries the completion gate's trailer convention: the trailer
# hash equals sha256 over the trailer-stripped content (one write path).
python3 - "$a/drafts/$slug.md" <<'EOF' && ok "canonical trailer follows the complete-gate hash convention" || err "trailer convention broken"
import hashlib, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"canonical-sha256=([0-9a-f]{64})", text)
assert m, "no emission trailer"
body = re.sub(r"\n*<!-- writing-assistant: canonical-sha256=[0-9a-f]{64} -->\s*$", "", text)
body = body.rstrip("\n") + "\n"
assert hashlib.sha256(body.encode("utf-8")).hexdigest() == m.group(1)
EOF
python3 -c "
import json
d=json.load(open('$ws/checkpoint.json'))
# The checkpoint records WHICH evidence class it was written on (#704), so
# 'reviewed' never silently means two different things. An authored canonical's
# is the provenance map.
assert d=={'stage':'review','next_stage':'done','reviewed':True,
           'review_evidence_class':'provenance-map'}, d
" && ok "done/reviewed checkpoint written by the re-entry gate, naming its evidence class" \
  || err "done/reviewed checkpoint wrong/missing"
# Without --rubric-applied the mechanical-dims re-check is not required.
rm -f "$ws/checkpoint.json"
out=$(python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
        --slug "$slug" --root "$h" --ws "$ws" --applied 1)
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
checks=[c['check'] for c in d['required_checks']]
assert checks==['verify-provenance'], d
" && ok "quality-gate mechanical dims required only with --rubric-applied" \
  || err "required-checks scoping wrong"

# --- (d) variants untouched on disk; staleness reports, never rewrites ------
v_after=$(python3 -c "import hashlib; print(hashlib.sha256(open('$variant','rb').read()).hexdigest())")
m_after=$(python3 -c "import os; print(os.stat('$variant').st_mtime_ns)")
[ "$v_before" = "$v_after" ] && [ "$m_before" = "$m_after" ] \
  && ok "variant file untouched on disk (content and mtime unchanged)" \
  || err "re-entry modified a variant file"
python3 "$DP" variant-staleness "$a/drafts/$slug.md" --variants "$variant" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['variants'][0]['status']=='stale', d
assert d['publish_blockers'][0]['blocker']=='stale-variant', d
" && ok "standalone staleness check agrees: variant is stale (publish blocker)" \
  || err "staleness disagreement after re-entry"

# --- (b) INVALID map → non-zero, named error, NO checkpoint -----------------
# The origin failure: an anchor dangling on a blank line (L4 is blank).
# The dangling anchor: L5 is the BLANK line after the frontmatter (the #362
# origin failure). Line-coupled to the frontmatter above like the good map —
# adding the birth record (#709) shifted the blank line from L4 to L5.
cat > "$ws/bad-map.txt" <<'EOF'
P1.S1[L5]: sourced <- docs/retries.md:12
EOF
ws2="$work/ws2"; mkdir -p "$ws2"
if python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/bad-map.txt" \
     --slug "$slug" --root "$h" --ws "$ws2" --applied 1 >/dev/null 2>"$work/e_map"; then
  err "review-reentry accepted an invalid map"
else
  grep -q 'invalid-provenance-map' "$work/e_map" && grep -q 'blank line' "$work/e_map" \
    && ok "invalid map refused with the named error" \
    || err "invalid-map error not named: $(cat "$work/e_map")"
fi
[ ! -f "$ws2/checkpoint.json" ] \
  && ok "no done/reviewed checkpoint over an INVALID map" \
  || err "checkpoint written despite an invalid map"

# --- (c) --applied 0 → strict no-op -----------------------------------------
h2="$work/host2"; mkdir -p "$h2"; git -C "$h2" init -q
a2="$work/articles2"; mkdir -p "$a2/drafts"; git -C "$a2" init -q
: > "$a2/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h2" \
  set-draft-location "$a2/drafts/" >/dev/null 2>&1
ws3="$work/ws3"; mkdir -p "$ws3"
out=$(python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
        --slug "$slug" --root "$h2" --ws "$ws3" --applied 0) \
  && ok "--applied 0 exits 0" || err "--applied 0 exited non-zero"
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['noop'] is True and d['applied']==0, d
" && ok "--applied 0 reports the strict no-op" || err "no-op JSON wrong"
[ -z "$(ls -A "$a2/drafts")" ] && ok "no-op persisted nothing" || err "no-op wrote into output.drafts"
[ ! -f "$ws3/checkpoint.json" ] && ok "no-op wrote no checkpoint" || err "no-op wrote a checkpoint"

# --- re-entry evidence is typed by ARTIFACT CLASS (Story 18.110, #704) --------
# A DERIVED canonical owns no claims of its own (CAP-2), so it has no provenance
# map by design — and --map was unconditionally required, which made a reviewed
# derivation permanently unable to checkpoint.
d="$work/derived"; mkdir -p "$d/host" "$d/a/drafts" "$d/ws"
cat > "$d/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $d/a/drafts/
YAML
mk_src() {   # the EN source the derivation pins to
  cat > "$d/a/drafts/retry-storms.md" <<'EOF'
---
slug: retry-storms
title: "Retry storms doubled our token spend"
date: 2026-07-09
mode: canonical
language: en
audience: en-practitioner
audience_id: en-practitioner
generated_by: writing-assistant@0.0.0-test+deadbee   # immutable birth record (#709)
summary: s.
topics: [llm-ops]
related: { projects: [], publications: [], products: [] }
---

## The incident

The retry storm doubled token spend.
EOF
}
mk_src
src_sha=$(python3 -c "
import hashlib,sys
t=open('$d/a/drafts/retry-storms.md',encoding='utf-8').read().rstrip('\n')+'\n'
print(hashlib.sha256(t.encode()).hexdigest())")
mk_derived() {   # $1 = the pin sha to record
  cat > "$d/edited.ja.md" <<EOF
---
slug: retry-storms.ja
title: "リトライ暴走を止める"
date: 2026-07-09
mode: canonical
language: ja
audience: ja-practitioner
audience_id: ja-practitioner
generated_by: writing-assistant@0.0.0-test+deadbee   # immutable birth record (#709)
summary: "指数バックオフに上限を設けました。"
topics: [llm-ops]
related: { projects: [], publications: [], products: [] }
adapted_from: retry-storms@$1
---

## 結論

指数バックオフに上限を設け、予算アラートを追加しました。
EOF
}

# (1) A derived draft re-enters with NO --map and checkpoints on ancestry.
mk_derived "$src_sha"
out=$(python3 "$DP" review-reentry --draft "$d/edited.ja.md" --slug retry-storms.ja \
        --root "$d/host" --ws "$d/ws" --applied 3 2>"$d/e1") \
  && ok "#704: a derived canonical re-enters with no --map" \
  || err "#704: derived re-entry refused: $(cat "$d/e1")"
printf '%s' "$out" | python3 -c "
import json,sys
o=json.load(sys.stdin)
assert o['review_evidence_class']=='ancestry', o
assert o['ancestry_validation']['ok'] is True, o
assert o['ancestry_validation']['pin_shape'] == 'well-formed', o
assert 'map_validation' not in o, o
" && ok "#704: it reports the ancestry evidence class and no map validation" \
  || err "#704: re-entry JSON wrong"
python3 -c "
import json
c=json.load(open('$d/ws/checkpoint.json'))
assert c['reviewed'] is True and c['next_stage']=='done', c
assert c['review_evidence_class']=='ancestry', c
" && ok "#704: the checkpoint records the ancestry evidence class" \
  || err "#704: checkpoint missing or wrong evidence class"
# The sanctioned write re-stamped the trailer over the reviewed content.
python3 - "$d/a/drafts/retry-storms.ja.md" <<'PYT' && ok "#704: the reviewed derivation's trailer is re-stamped by the write path" || err "#704: trailer not re-stamped"
import hashlib, re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"canonical-sha256=([0-9a-f]{64})", t)
assert m, "no trailer"
body = re.sub(r"\n*<!-- writing-assistant: canonical-sha256=[0-9a-f]{64} -->\s*$", "", t)
assert hashlib.sha256((body.rstrip("\n") + "\n").encode()).hexdigest() == m.group(1)
PYT

# (2) A MALFORMED pin refuses, fail-closed, with no checkpoint. Shape is what
#     the gate can judge alone; whether the pin RESOLVES is the reported check's
#     job (#704 re-triage — the gate may not call the ancestry lint).
rm -rf "$d/ws2"; mkdir -p "$d/ws2"
sed 's/^adapted_from: .*/adapted_from: not-a-valid-pin/' "$d/edited.ja.md" \
  > "$d/malformed.ja.md"
if python3 "$DP" review-reentry --draft "$d/malformed.ja.md" --slug retry-storms.ja \
     --root "$d/host" --ws "$d/ws2" --applied 3 >/dev/null 2>"$d/e2"; then
  err "#704: a derivation with a malformed ancestry pin was checkpointed"
else
  grep -q 'invalid-ancestry' "$d/e2" \
    && [ ! -f "$d/ws2/checkpoint.json" ] \
    && ok "#704: a malformed ancestry pin refuses by name and writes no checkpoint" \
    || err "#704: wrong refusal: $(cat "$d/e2")"
fi

# (2b) The RESOLUTION check is reported, not run — the same status
#      verify-provenance has for an authored draft.
rm -rf "$d/ws2b"; mkdir -p "$d/ws2b"
mk_derived "$src_sha"
python3 "$DP" review-reentry --draft "$d/edited.ja.md" --slug retry-storms.ja \
  --root "$d/host" --ws "$d/ws2b" --applied 3 2>/dev/null \
  | python3 -c "
import json,sys
o=json.load(sys.stdin)
checks=[c['check'] for c in o['required_checks']]
assert 'lint-ancestry' in checks, o
assert 'verify-provenance' not in checks, o
" && ok "#704: the ancestry RESOLUTION check is reported in the worklist, not run" \
  || err "#704: the worklist does not carry lint-ancestry for a derived draft"
# And the pipeline never names the adaptation module — CAP-1's boundary, which
# is why the resolution check is reported rather than executed here.
[ "$(grep -c 'adapt-canonical' "$DP" || true)" -eq 0 ] \
  && ok "#704: the pipeline still never references the adaptation invocation" \
  || err "#704: the pipeline now references adaptation — CAP-1's boundary broken"

# (3) An AUTHORED canonical still requires --map — the class was typed, not
#     weakened.
rm -rf "$d/ws3"; mkdir -p "$d/ws3"
if python3 "$DP" review-reentry --draft "$d/a/drafts/retry-storms.md" --slug retry-storms \
     --root "$d/host" --ws "$d/ws3" --applied 1 >/dev/null 2>"$d/e3"; then
  err "#704: an authored canonical re-entered with no --map"
else
  grep -q 'required for an AUTHORED canonical' "$d/e3" \
    && [ ! -f "$d/ws3/checkpoint.json" ] \
    && ok "#704: an authored canonical still requires --map, and says why" \
    || err "#704: wrong authored-class refusal: $(cat "$d/e3")"
fi

# --- Story 19.17 (#757): re-entry re-projects the plan --------------------------
# The fixture's articles repo gets a plan whose audience contradicts the edited
# canonical; re-entry must mirror it and report the change.
plansdir=$(dirname "$(dirname "$ws")")
adir="$work/articles"
mkdir -p "$adir/plans"
# the schema markers resolve_dest requires (drafts/ + INDEX.md-or-backlog/)
touch "$adir/INDEX.md"
python3 - "$ws/edited.md" <<'PY757'
import sys
p = sys.argv[1]; t = open(p).read()
if "audience:" not in t:
    t = t.replace("generated_by:", "audience: the NEW audience\ngenerated_by:", 1)
if "## " not in t:
    t = t.replace("The retry storm tripled load",
                  "## Old heading\n\nThe retry storm tripled load", 1)
open(p, "w").write(t)
PY757
# the edit moved lines, so re-derive the map from the segmentation skeleton —
# the exact workflow 19.16 prescribes after any draft edit (#755)
python3 "$DP" provenance-segment --draft "$ws/edited.md" > "$ws/skeleton.json"
python3 - "$ws/skeleton.json" "$ws/map.txt" <<'PY757B'
import json, sys
rows = json.load(open(sys.argv[1]))["positions"]
classes = ["sourced <- docs/retries.md:12", "narration"]
with open(sys.argv[2], "w") as fh:
    for i, r in enumerate(rows):
        cls = classes[i] if i < len(classes) else "narration"
        fh.write(f"{r['pos']}[L{r['anchor']}]: {cls}\n")
PY757B
cat > "$adir/plans/$slug.md" <<'PLAN757'
---
kind: article-plan
slug: SLUG757
intent: share engineering lessons
claim: "A claim."
status: drafted
run_id: r1
pin: host@8f3c2d1000000000000000000000000000000000
audience: the OLD audience
consumed: [el-one]
sections: [{"title": "Old heading", "elements": ["el-one"]}]
---

# Plan body carried unchanged.
PLAN757
sed -i "s/SLUG757/$slug/" "$adir/plans/$slug.md"
python3 "$DP" quality-gate --draft "$ws/edited.md" --map "$ws/map.txt" \
  --verdicts-out "$ws/rubric-verdicts-v2.txt" >/dev/null 2>&1 || true
python3 "$DP" review-reentry --draft "$ws/edited.md" --map "$ws/map.txt" \
  --slug "$slug" --root "$h" --ws "$ws" --applied 1 --rubric-applied \
  > "$work/re757.json" 2>/dev/null || true
python3 - "$work/re757.json" "$adir/plans/$slug.md" "$ws/edited.md" <<'PYEOF' \
  && ok "#757: re-entry re-projected the plan (audience mirrored, change reported)" \
  || err "#757: plan re-projection missing or wrong: $(python3 -c "import json;print(json.load(open('$work/re757.json')).get('plan_reprojection'))" 2>&1)"
import json, sys, re
d = json.load(open(sys.argv[1]))
pr = d.get("plan_reprojection") or {}
assert pr.get("reprojected") is True, pr
plan = open(sys.argv[2]).read()
draft = open(sys.argv[3]).read()
m = re.search(r"^audience: (.+)$", plan, re.M)
dm = re.search(r"^audience: ([^#\n]+)", draft, re.M)
assert m and dm and m.group(1).strip() == dm.group(1).strip(), (m, dm)
assert "# Plan body carried unchanged." in plan
PYEOF

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-reentry checks passed.\n'; exit 0
else
  printf '\nreview-reentry checks FAILED.\n' >&2; exit 1
fi
