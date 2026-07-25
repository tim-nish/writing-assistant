#!/usr/bin/env sh
# check-derived-canonical.sh — verify the DERIVED CANONICAL is first-class and
# records its ancestry (Story 18.57, #586; SPEC-canonical-adaptation CAP-2 +
# CAP-4). POSIX sh + stdlib Python; every fixture write lands under mktemp -d.
#
# Covers:
#   CAP-4  the derivation lands at <output.drafts>/{slug}.ja.md with its own
#          slug/mode/language/audience and its own canonical-sha256 trailer,
#          written through the pipeline's ONE canonical write path; the
#          ancestry block records the source slug and the source hash under the
#          variant trailer's hash convention (one hasher, not two); the
#          derivation is accepted by `emit variants --slug {slug}.ja` with no
#          branch distinguishing it from an authored canonical; a corrupted or
#          unresolvable ancestry block is NAMED by the lint.
#   CAP-2  claims-conformance reports an added claim and a silently dropped
#          one, accepts a declared omission, and says NOTHING about structure,
#          section order or title.
#   CAP-3  nothing is written before the owner's recorded answer, and `stop`
#          writes nothing at all.

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
  "refounded_opening": "The target reader has no context on our billing setup, so the opening states the cost outcome first.",
  "structural_mapping": [
    {"source_section": "The incident", "disposition": "move", "note": "moves after the payoff; this reader expects the result first"},
    {"source_section": "What we changed", "disposition": "keep", "note": "the how-to core, unchanged in order"},
    {"source_section": "What it cost", "disposition": "drop", "note": "internal staffing cost carries no meaning for this reader"}
  ],
  "recomposed_title": "リトライ暴走を止める",
  "recomposed_summary": "指数バックオフに上限を設け、予算アラートを追加した経緯と結果をまとめました。",
  "omissions": [
    {"section": "What it cost", "what": "the two engineer-days figure",
     "reason": "an internal staffing number this reader cannot use",
     "pointers": ["retro.md:41"]}
  ]
}
EOF

cat > "$work/body.ja.md" <<'EOF'
## 結論

指数バックオフに上限を設け、予算アラートを追加した。

## 何が起きたか

リトライの連鎖でトークン消費が倍増し、発見が遅れた。
EOF

# --- CAP-3: nothing is written before the recorded answer --------------------
if $A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
     --body "$work/body.ja.md" --ws "$work/ws" >/dev/null 2>"$work/e-noanswer"; then
  err "the derived canonical was written with no recorded answer"
else
  grep -q 'no presented-payload log' "$work/e-noanswer" \
    && ok "write with no gate record is refused (CAP-3)" \
    || err "no-answer refusal wrong: $(cat "$work/e-noanswer")"
fi
ls "$work/drafts" | grep -q '\.ja\.md$' \
  && err "a derived canonical exists before any answer" \
  || ok "no derived canonical exists before the owner answers"

# Present the gate, then record `stop` — still nothing written.
$A payload --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  > "$work/payload.json"
ask=$(python3 "$VP" --ws "$work/ws" --surface adaptation-plan "$work/payload.json" \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["ask_id"])')
printf '%s' '{"selection":"stop","free_text":""}' \
  | python3 "$VP" --ws "$work/ws" --answer "$ask" >/dev/null
if $A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
     --body "$work/body.ja.md" --ws "$work/ws" >/dev/null 2>"$work/e-stop"; then
  err "\`stop\` still wrote a derived canonical"
else
  grep -q 'stays single-canonical' "$work/e-stop" \
    && ok "\`stop\` writes nothing and says so" \
    || err "stop refusal wrong: $(cat "$work/e-stop")"
fi
ls "$work/drafts" | grep -q '\.ja\.md$' \
  && err "\`stop\` left a derived canonical behind" \
  || ok "after \`stop\`, output.drafts still holds no derivation"

# --- CAP-4: approve → the derived canonical is written -----------------------
printf '%s' '{"selection":"approve","free_text":""}' \
  | python3 "$VP" --ws "$work/ws" --answer "$ask" >/dev/null
$A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  --body "$work/body.ja.md" --ws "$work/ws" > "$work/written.json" 2>"$work/e-write" \
  && ok "an approved plan writes the derived canonical" \
  || { err "write failed: $(cat "$work/e-write")"; printf '\nFAILED.\n' >&2; exit 1; }

[ -f "$work/drafts/retry-storms.ja.md" ] \
  && ok "the derivation lands at <output.drafts>/{slug}.ja.md" \
  || err "no retry-storms.ja.md at output.drafts: $(ls "$work/drafts")"

python3 - "$work" <<'PY' || exit 1
import hashlib, json, os, re, sys, importlib.util
work = sys.argv[1]
here = os.path.join(os.getcwd(), "scripts")
def load(f):
    spec = importlib.util.spec_from_file_location(f.replace("-","_")[:-3], os.path.join(here, f))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
dp = load("draft-pipeline.py"); ac = load("adapt-canonical.py")
fail = []
def ok(m): print(f"ok:   {m}")
def bad(m): fail.append(m); print(f"FAIL: {m}", file=sys.stderr)

derived = open(os.path.join(work, "drafts", "retry-storms.ja.md"), encoding="utf-8").read()
fields, body = dp._read_frontmatter(derived)

for key, want in (("slug", "retry-storms.ja"), ("mode", "canonical"),
                  ("language", "ja"), ("audience", "ja-practitioner"),
                  ("audience_id", "ja-practitioner")):
    (ok if fields.get(key) == want else bad)(
        f"derived frontmatter {key} == {want!r} (got {fields.get(key)!r})")
(ok if fields.get("title") == "リトライ暴走を止める" else bad)(
    "the derived title is the plan's re-composed title, not a translation of the source's")
# Schema fields the derivation does not own are carried verbatim.
(ok if fields.get("date") == "2026-07-09" and "llm-ops" in (fields.get("topics") or [])
 else bad)("declared schema fields the derivation does not own are carried verbatim")

# CAP-4: its own trailer, under the ONE hash convention.
m = dp._CANONICAL_SHA.search(derived)
(ok if m else bad)("the derivation carries its own canonical-sha256 trailer")
if m:
    (ok if m.group(1) == hashlib.sha256(
        dp._strip_emission_trailer(derived).encode("utf-8")).hexdigest() else bad)(
        "the derivation's trailer uses the variant trailer's hash convention")

# CAP-4: the ancestry pin records the SOURCE hash, same convention.
anc, defect = ac.parse_ancestry(fields)
(ok if anc and not defect else bad)(f"the ancestry pin parses (defect: {defect})")
src = open(os.path.join(work, "drafts", "retry-storms.md"), encoding="utf-8").read()
src_sha = hashlib.sha256(dp._strip_emission_trailer(src).encode("utf-8")).hexdigest()
if anc:
    (ok if anc["slug"] == "retry-storms" else bad)("ancestry records the source slug")
    (ok if anc["canonical_sha256"] == src_sha else bad)(
        "ancestry records the source hash under the variant trailer's convention")

written = json.load(open(os.path.join(work, "written.json")))
(ok if written["derived"]["slug"] == "retry-storms.ja" else bad)(
    "write reports the derived slug")
(ok if written["adapted_from"]["canonical_sha256"] == src_sha else bad)(
    "write reports the recorded ancestry hash")

sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || fail=1

# --- CAP-4: emit variants accepts it by slug with ZERO special-casing ---------
cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
                          "ja":{"mode":"canonical","variants":["zenn"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"},
             "zenn":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
python3 "$DP" variants --slug retry-storms.ja --root "$work/host" \
  --config-json "$work/cfg.json" --list-platforms > "$work/emit.json" 2>"$work/e-emit" \
  && ok "\`emit variants --slug {slug}.ja\` resolves the derivation like any canonical" \
  || err "emit variants refused the derived canonical: $(cat "$work/e-emit")"
python3 -c "
import json,sys
o=json.load(open('$work/emit.json'))
assert o['language']=='ja', o
assert o['available']==['zenn'], o
" && ok "the derivation resolves its own language's emit options" \
  || err "the derivation did not resolve as a ja canonical"

# No branch anywhere distinguishes a derived canonical from an authored one at
# emission: the only mention of ancestry in the pipeline is the presence test
# that keeps staleness from grading a canonical as a variant.
hits=$(grep -c 'adapted_from' "$DP" || true)
[ "$hits" -le 3 ] \
  && ok "no derived-vs-authored branch in the emission path (ancestry mentions: $hits)" \
  || err "the pipeline branches on ancestry $hits times — CAP-4 forbids special-casing"

# --- CAP-4/CAP-5 seam: the derivation is not a stale VARIANT of its source ----
python3 "$DP" variant-staleness "$work/drafts/retry-storms.md" \
  --root "$work/host" --out "$work/drafts" > "$work/stale.json"
python3 -c "
import json,sys
o=json.load(open('$work/stale.json'))
paths=[v['path'] for v in o['variants']]
assert not any(p.endswith('.ja.md') for p in paths), paths
" && ok "the derived canonical is never graded as a stale variant of its source" \
  || err "the derived canonical was listed as a variant of its source"

# --- CAP-4: the ancestry pin is the ratified scalar `<slug>@<sha>` ------------
grep -Eq '^adapted_from: retry-storms@[0-9a-f]{64}$' "$work/drafts/retry-storms.ja.md" \
  && ok "the written ancestry is the scalar pin \`<slug>@<sha>\`, not a mapping" \
  || err "the written ancestry is not the scalar pin: $(grep '^adapted_from:' "$work/drafts/retry-storms.ja.md")"

# --- CAP-4: a corrupted ancestry pin is NAMED, not swallowed ------------------
$A lint-ancestry --derived "$work/drafts/retry-storms.ja.md" --root "$work/host" \
  >/dev/null 2>&1 \
  && ok "a well-formed ancestry pin lints clean" \
  || err "the freshly written ancestry pin failed its own lint"

sed 's/^adapted_from: .*/adapted_from: no-such-article@'"$(printf '0%.0s' $(seq 64))"'/' \
  "$work/drafts/retry-storms.ja.md" > "$work/drafts/orphan.ja.md"
$A lint-ancestry --derived "$work/drafts/orphan.ja.md" --root "$work/host" \
  > "$work/lint-orphan.json" 2>&1 \
  && err "an unresolvable ancestry slug passed the lint" \
  || grep -q 'ancestry-source-missing' "$work/lint-orphan.json" \
     && ok "an ancestry slug resolving to no canonical is named" \
     || err "orphan ancestry not named: $(cat "$work/lint-orphan.json")"
grep -q 'no-such-article' "$work/lint-orphan.json" \
  && ok "the lint names the unresolvable source" \
  || err "the lint does not name the unresolvable source"

sed 's/^adapted_from: .*/adapted_from: not-a-pin/' \
  "$work/drafts/retry-storms.ja.md" > "$work/drafts/malformed.ja.md"
$A lint-ancestry --derived "$work/drafts/malformed.ja.md" --root "$work/host" \
  > "$work/lint-mal.json" 2>&1 \
  && err "a malformed ancestry pin passed the lint" \
  || grep -q 'malformed-ancestry' "$work/lint-mal.json" \
     && ok "a malformed ancestry pin is named" \
     || err "malformed ancestry not named: $(cat "$work/lint-mal.json")"

# A hash matching no source content is named too (the staleness chain, Story
# 18.58, turns this into a publish blocker; the lint's job is to name it).
sed 's/^adapted_from: .*/adapted_from: retry-storms@'"$(printf 'a%.0s' $(seq 64))"'/' \
  "$work/drafts/retry-storms.ja.md" > "$work/drafts/moved.ja.md"
$A lint-ancestry --derived "$work/drafts/moved.ja.md" --root "$work/host" \
  > "$work/lint-moved.json" 2>&1 \
  && err "a hash matching no source content passed the lint" \
  || grep -q 'ancestry-hash-mismatch' "$work/lint-moved.json" \
     && ok "a hash matching no source content is named, with both hashes" \
     || err "hash mismatch not named: $(cat "$work/lint-moved.json")"
grep -q 'recorded_sha256' "$work/lint-moved.json" \
  && grep -q 'current_sha256' "$work/lint-moved.json" \
  && ok "the hash-mismatch defect carries the hash pair" \
  || err "the hash-mismatch defect omits the hash pair"

# --- CAP-2: claims conformance ------------------------------------------------
cat > "$work/src.map" <<'EOF'
P1.S1: sourced <- incident.md:12
P1.S2: sourced <- retro.md:41
P2.S1: derived <- incident.md:12, fix.md:8
P2.S2: narration
EOF
# Conformant: same pointers minus the declared omission, freely reordered.
cat > "$work/ok.map" <<'EOF'
P1.S1: derived <- fix.md:8, incident.md:12
P1.S2: narration
P2.S1: sourced <- incident.md:12
EOF
$A claims-check --source-map "$work/src.map" --derived-map "$work/ok.map" \
  --fill "$work/fill.json" > "$work/claims-ok.json" 2>&1 \
  && ok "a reordered derivation whose omission is declared passes claims-conformance" \
  || err "conformant derivation failed: $(cat "$work/claims-ok.json")"

cat > "$work/added.map" <<'EOF'
P1.S1: sourced <- incident.md:12
P1.S2: sourced <- retro.md:41
P1.S3: sourced <- benchmark.md:3
P2.S1: derived <- incident.md:12, fix.md:8
EOF
$A claims-check --source-map "$work/src.map" --derived-map "$work/added.map" \
  --fill "$work/fill.json" > "$work/claims-added.json" 2>&1 \
  && err "an added claim passed claims-conformance" \
  || grep -q 'added-claim' "$work/claims-added.json" \
     && ok "a claim present in the derivation and absent from the source is a defect" \
     || err "added claim not reported: $(cat "$work/claims-added.json")"
grep -q 'benchmark.md:3' "$work/claims-added.json" \
  && ok "the added-claim defect names the pointer" \
  || err "the added-claim defect does not name the pointer"

# The same derivation with NO declared omission: the dropped claim is a defect.
$A claims-check --source-map "$work/src.map" --derived-map "$work/ok.map" \
  > "$work/claims-dropped.json" 2>&1 \
  && err "a load-bearing claim dropped with no declared omission passed" \
  || grep -q 'dropped-claim' "$work/claims-dropped.json" \
     && ok "a load-bearing claim dropped without a declared omission is a defect" \
     || err "dropped claim not reported: $(cat "$work/claims-dropped.json")"

# CAP-2 explicitly frees structure: nothing the check reports mentions it.
python3 -c "
import json
o=json.load(open('$work/claims-ok.json'))
assert o['defects']==[], o
for f in ('structure','section order','payoff position','framing','register','title'):
    assert f in o['free'], (f, o['free'])
" && ok "structure, order, payoff position, framing, register and title are never reported" \
  || err "the claims check reports something CAP-2 leaves free"

# --- CAP-4: `summary` is authored for the target reader (Story 18.107, #700) --
# A summary is a TELLING, so the derivation re-decides it; every other inherited
# field stays verbatim. The source fixture's `summary:` is a folded BLOCK scalar,
# which is the case that made this more than a dict entry: overriding the key
# without dropping its continuation lines left the old English prose behind.
python3 - "$work" <<'PY' || exit 1
import sys, os, importlib.util
work = sys.argv[1]
here = os.path.join(os.getcwd(), "scripts")
spec = importlib.util.spec_from_file_location("draft_pipeline", os.path.join(here, "draft-pipeline.py"))
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
fail = []
def ok(m): print(f"ok:   {m}")
def bad(m): fail.append(m); print(f"FAIL: {m}", file=sys.stderr)

derived = open(os.path.join(work, "drafts", "retry-storms.ja.md"), encoding="utf-8").read()
fields, body = dp._read_frontmatter(derived)
summary = str(fields.get("summary") or "")
(ok if "予算アラート" in summary else bad)(
    f"derived `summary` is the authored target-language text (got {summary[:40]!r})")
(ok if "innocuous retry policy" not in derived.split("---")[1] else bad)(
    "the source's English summary is GONE from the derived frontmatter (block-scalar "
    "continuation dropped with the value it belonged to)")
# The fields the derivation does NOT own stay inherited, verbatim.
(ok if fields.get("date") == "2026-07-09" else bad)(
    f"`date` is still inherited from the source (OQ3 — got {fields.get('date')!r})")
(ok if "llm-ops" in (fields.get("topics") or []) else bad)("`topics` still inherited")
sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || err "derived summary/inheritance checks failed"

# A plan with no authored summary never reaches the owner.
python3 - "$work/fill.json" > "$work/fill-nosummary.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); d.pop("recomposed_summary", None)
json.dump(d, sys.stdout, ensure_ascii=False)
PY
if $A plan --slug retry-storms --target zenn $ARGS --fill "$work/fill-nosummary.json" \
     >/dev/null 2>"$work/e-nosummary"; then
  err "a plan with no recomposed_summary was accepted"
else
  grep -q 'recomposed_summary' "$work/e-nosummary" \
    && ok "a plan missing recomposed_summary is refused, naming the slot (#700)" \
    || err "wrong refusal: $(cat "$work/e-nosummary")"
fi
python3 - "$work/fill.json" > "$work/fill-emptysummary.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8")); d["recomposed_summary"] = "   "
json.dump(d, sys.stdout, ensure_ascii=False)
PY
$A plan --slug retry-storms --target zenn $ARGS --fill "$work/fill-emptysummary.json" \
  >/dev/null 2>&1 \
  && err "an empty recomposed_summary was accepted" \
  || ok "an empty recomposed_summary is refused (#700)"
# The owner sees it at the gate they already answer — no second screen.
$A payload --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  | grep -q '予算アラート' \
  && ok "the re-composed summary rides the CAP-3 gate payload (#700)" \
  || err "the gate payload does not carry the summary the owner approves"

# --- CAP-4 re-derivation: the recorded answer is the ownership token ---------
# Story 18.105 (#693): the first derivation succeeded and EVERY re-derivation was
# refused, because `write` passed no ownership to the shared writer — the write
# path failed only when it was needed. The recorded approve at the CAP-3 gate is
# the authorization; the conjunction (approve/modify AND an ask naming THIS
# derived slug) is what keeps it from being a bare flag.
sed 's/発見が遅れた。/発見が遅れた。これは書き直した本文である。/' "$work/body.ja.md" > "$work/body2.ja.md"
grep -q '書き直した本文' "$work/body2.ja.md" \
  || { err "fixture: the revised ja body is identical to the first — the re-derivation test would be vacuous"; printf '\nFAILED.\n' >&2; exit 1; }
$A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
  --body "$work/body2.ja.md" --ws "$work/ws" > "$work/rewritten.json" 2>"$work/e-rewrite" \
  && ok "a re-derivation of an already-derived slug persists (#693)" \
  || err "re-derivation refused: $(cat "$work/e-rewrite")"
grep -q '書き直した本文' "$work/drafts/retry-storms.ja.md" \
  && ok "the re-derivation's content actually replaced the earlier derivation" \
  || err "the re-derivation reported success without replacing the content"

# A FOREIGN canonical minting the same derived slug is still refused: the gate
# record must name this slug, so an approve recorded for another article
# authorizes nothing here (#666 preserved).
wsf="$work/wsforeign"; mkdir -p "$wsf"
cp "$work/drafts/retry-storms.ja.md" "$work/foreign-backup.md"
python3 - "$work/drafts/retry-storms.ja.md" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t2 = t.replace("書き直した本文", "全く別の記事の本文")
assert t2 != t, "fixture: nothing to replace — the foreign-collision test would be vacuous"
open(p, "w", encoding="utf-8").write(t2)
PY
# A well-formed gate record in a FRESH workspace, but presented for a different
# derived slug — mechanically the same shape, semantically not this artifact.
python3 - "$wsf" <<'PY'
import json, os, sys
ws = sys.argv[1]
ask = {"kind": "ask", "ask_id": 1, "surface": "adaptation-plan",
       "payload": {"items": [{"where": "Adaptation of canonical other-article for target zenn",
                              "why": "w",
                              "choices": [{"label": "approve",
                                           "effect": "writes the derived canonical other-article.ja.md"}]}]}}
ans = {"kind": "answer", "ask_id": 1, "answer": {"selection": "approve", "free_text": ""}}
with open(os.path.join(ws, "presented-payloads.jsonl"), "w", encoding="utf-8") as fh:
    fh.write(json.dumps(ask) + "\n" + json.dumps(ans) + "\n")
PY
before_foreign=$(cat "$work/drafts/retry-storms.ja.md")
if $A write --slug retry-storms --target zenn $ARGS --fill "$work/fill.json" \
     --body "$work/body.ja.md" --ws "$wsf" >/dev/null 2>"$work/e-foreign"; then
  err "an approve recorded for a DIFFERENT slug authorized this write (#666 broken)"
else
  grep -q 'slug collision' "$work/e-foreign" \
    && [ "$before_foreign" = "$(cat "$work/drafts/retry-storms.ja.md")" ] \
    && ok "an approve for another slug authorizes nothing; collision still refused (#666)" \
    || err "foreign-collision refusal wrong: $(cat "$work/e-foreign")"
fi
# The refusal must not advertise an override this surface does not expose.
grep -q 'replace-canonical' "$work/e-foreign" \
  && err "the refusal names --replace-canonical, which \`adapt-canonical write\` has no flag for" \
  || ok "the refusal names the gate, not a nonexistent --replace-canonical flag (#693)"
grep -q 'present the adaptation gate' "$work/e-foreign" \
  && ok "the refusal names the sanctioned path: present the gate for this slug" \
  || err "the refusal does not say how to proceed legitimately"
$A write --help 2>&1 | grep -q 'replace-canonical' \
  && err "\`adapt-canonical write\` grew a --replace-canonical flag (#693 forbids it)" \
  || ok "no override flag on the adaptation surface (authorization is the gate)"
cp "$work/foreign-backup.md" "$work/drafts/retry-storms.ja.md"

# --- lockstep: the SKILL states the shipped mechanics ------------------------
for token in 'adapt-canonical.py write' 'adapted_from' 'claims-check' \
             'lint-ancestry' 'emit variants' 'zero special-casing'; do
  grep -q -- "$token" "$SKILL" && ok "SKILL carries the contract text: $token" \
    || err "SKILL is missing contract text: $token"
done

[ "$fail" -eq 0 ] && printf '\nAll derived-canonical checks passed.\n' \
  || { printf '\nFAILED.\n' >&2; exit 1; }
