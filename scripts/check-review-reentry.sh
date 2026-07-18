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
---

The retry storm tripled load before the breaker fired.
Review sharpened this sentence during arbitration.
EOF
# The rebuilt map: anchors resolve to real non-blank lines of the edited draft;
# the review-authored sentence (L6) is classified like any other.
cat > "$ws/map.txt" <<'EOF'
P1.S1[L5]: sourced <- docs/retries.md:12
P1.S2[L6]: narration
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
" && ok "re-entry JSON: valid map, scoped checks, stale variant listed, nothing emitted" \
  || err "re-entry JSON shape wrong"
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
assert d=={'stage':'review','next_stage':'done','reviewed':True}, d
" && ok "done/reviewed checkpoint written by the re-entry gate" \
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
cat > "$ws/bad-map.txt" <<'EOF'
P1.S1[L4]: sourced <- docs/retries.md:12
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

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-reentry checks passed.\n'; exit 0
else
  printf '\nreview-reentry checks FAILED.\n' >&2; exit 1
fi
