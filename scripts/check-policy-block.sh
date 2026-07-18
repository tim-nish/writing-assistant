#!/usr/bin/env sh
# check-policy-block.sh — verify the Stage 2→3 policy-block gate (Story 13.77,
# SPEC-article-draft-pipeline 2026-07-18 amendment, umbrella #365).
# POSIX shell + stdlib Python only.
#
# Covers: an unresolved conflict classification blocks with a publish-blocker
# payload naming BOTH positions with pointers; an answered reconciliation
# (including a reversal routed to staging, and never a skip) unblocks; a plan
# with recorded `policy_conformance: conflict`/`stale` blocks (the resumed-run
# half), naming the moved pin/configVersion for stale; a re-consult recompute
# against a fresh surface whose referenced lines still hold clears a recorded
# stale (the 13.76 conformance machinery, reused — never a second detector);
# `conformant`/`open` proceed; generic mode (no classification, no
# policy-seeded plan) returns {blocked: false, reason: "generic-mode"}; the
# blocked payload carries the block checkpoint
# {"stage": "policy-block", "next_stage": "interview"} (never `fill`); and the
# SKILL wires the gate at the Stage 2→3 boundary with the publish-blockers
# bucket and the generic-mode exemption.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

PIPE="scripts/draft-pipeline.py"
FIX="scripts/fixtures/policy-classification"
SKILL="skills/draft-article/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 -c "import py_compile; py_compile.compile('$root/$PIPE', doraise=True)" 2>/dev/null \
  && ok "pipeline compiles" || { err "pipeline syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

sha=deadbeef4a5b6c7d8e9f0a1b2c3d4e5f6071829
oldsha=aaaa000000000000000000000000000000000000
newsha=bbbb000000000000000000000000000000000000

field() { python3 -c "import json,sys; d=json.load(sys.stdin); v=d
for k in '$2'.split('.'): v=v[k]
print(v)" < "$1"; }

# --- (a) unresolved conflict classification → blocked, both positions named ------
python3 "$PIPE" classify-policy --surface "$FIX/surface.txt" \
  --config-json "$FIX/config.json" --items "$FIX/items.json" \
  --config-version cfgv1 > "$work/classified.json" \
  || err "classify-policy failed on the replay fixtures"
python3 "$PIPE" policy-block-check --classification "$work/classified.json" \
  > "$work/out.json" || err "policy-block-check failed on the conflict case"
[ "$(field "$work/out.json" blocked)" = "True" ] \
  && [ "$(field "$work/out.json" action)" = "publish-blocker" ] \
  && ok "unresolved conflict classification blocks as a publish blocker" \
  || err "unresolved conflict did not block: $(cat "$work/out.json")"
python3 - "$work/out.json" <<'PYEOF' \
  && ok "blocked payload names BOTH positions with pointers, copy-pasteable" \
  || err "blocked payload positions wrong"
import json, sys
d = json.load(open(sys.argv[1]))
auth = {p["authority"]: p for p in d["positions"]}
assert set(auth) == {"policy", "config"}, auth
assert auth["policy"]["pointer"].startswith("topics/articles.md:17@"), auth["policy"]
assert auth["config"]["pointer"] == "syndication.policy.en.mode@cfgv1", auth["config"]
pb = d["publish_blocker"]
assert "topics/articles.md:17@" in pb and "syndication.policy.en.mode@cfgv1" in pb, pb
assert "reference records only" in pb and "canonical" in pb, pb
PYEOF
[ "$(field "$work/out.json" checkpoint.stage)" = "policy-block" ] \
  && [ "$(field "$work/out.json" checkpoint.next_stage)" = "interview" ] \
  && ok "blocked payload suggests the block checkpoint (resume re-presents the reconciliation, never fill)" \
  || err "block checkpoint payload wrong: $(cat "$work/out.json")"
grep -q '"next_stage": "fill"' "$work/out.json" \
  && err "blocked payload must never suggest next_stage: fill" \
  || ok "blocked payload never suggests next_stage: fill"

# The block checkpoint round-trips through the generic checkpoint/resume.
mkdir -p "$work/ws"
python3 - "$work/out.json" <<'PYEOF' | python3 "$PIPE" checkpoint --ws "$work/ws" - >/dev/null
import json, sys
json.dump(json.load(open(sys.argv[1]))["checkpoint"], sys.stdout)
PYEOF
python3 "$PIPE" resume --ws "$work/ws" > "$work/resume.json"
[ "$(field "$work/resume.json" next_stage)" = "interview" ] \
  && ok "block checkpoint round-trips: resume points at the interview (the block re-presents)" \
  || err "block checkpoint resume wrong: $(cat "$work/resume.json")"

# --- (b) answered reconciliation → unblocked -------------------------------------
printf '[{"id":"rc1","disposition":"answered","text":"Config governs: EN is canonical; propose updating the records-only line."}]' \
  > "$work/answers.json"
python3 "$PIPE" policy-block-check --classification "$work/classified.json" \
  --answers "$work/answers.json" > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "False" ] \
  && ok "answered reconciliation unblocks in the same invocation" \
  || err "answered reconciliation still blocked: $(cat "$work/out.json")"
# A reversal disposition (routed to staging as a proposed change) unblocks too.
printf '[{"id":"rc1","disposition":"replaced","text":"Reverse the recorded position: the site syndicates EN."}]' \
  > "$work/reversal.json"
python3 "$PIPE" policy-block-check --classification "$work/classified.json" \
  --answers "$work/reversal.json" > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "False" ] \
  && ok "a reversal disposition (routed to staging) unblocks — proposed change, not current policy" \
  || err "reversal disposition still blocked: $(cat "$work/out.json")"
# A skip records no decision — the conflict stays unresolved and blocking.
printf '[{"id":"rc1","disposition":"skipped"}]' > "$work/skip.json"
python3 "$PIPE" policy-block-check --classification "$work/classified.json" \
  --answers "$work/skip.json" > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "True" ] \
  && ok "a skipped reconciliation stays blocked (a skip is not an answer)" \
  || err "skip unblocked the conflict: $(cat "$work/out.json")"

# --- (c) plan with recorded conflict/stale → blocked; re-consult clears stale ----
plan() {
cat > "$work/plan.md" <<EOF
---
kind: article-plan
slug: demo-plan
intent: introduce the project
claim: the site record model shapes the article
status: outlined
run_id: 20260718T090000-000001
pin: product-lab@$sha
policy_seeded: true
seed: topics/articles.md:17@$oldsha
policy_pin: product-lab@$oldsha
policy_config_version: cfgv1
policy_conformance: $1
---

- keep the site records-only, per "Website stays independent — reference records only." / topics/articles.md:17@$oldsha
EOF
}
plan conflict
python3 "$PIPE" policy-block-check --plan "$work/plan.md" > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "True" ] \
  && [ "$(field "$work/out.json" action)" = "publish-blocker" ] \
  && ok "plan with recorded policy_conformance: conflict blocks (resumed-run half)" \
  || err "recorded conflict plan did not block: $(cat "$work/out.json")"

plan stale
python3 "$PIPE" policy-block-check --plan "$work/plan.md" > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "True" ] \
  && ok "plan with recorded policy_conformance: stale blocks" \
  || err "recorded stale plan did not block: $(cat "$work/out.json")"
[ "$(field "$work/out.json" pin_delta.recorded_pin)" = "product-lab@$oldsha" ] \
  && grep -q "product-lab@$oldsha" "$work/out.json" \
  && ok "stale block names the recorded (moved) pin/configVersion" \
  || err "stale block pin_delta wrong: $(cat "$work/out.json")"

# Re-consult at the current pin: fresh surface, referenced line unchanged →
# the 13.76 conformance recompute clears the recorded stale.
printf '{"syndication": {"policy": {"en": {"mode": "source", "variants": []}}}}' \
  > "$work/source-config.json"
cat > "$work/fresh-surface.txt" <<EOF
pin: product-lab@$newsha
=== topics/articles.md @ $newsha
15: ## Website
16: updated: 2026-07-19
17: Website stays independent — reference records only.
18: state: ratified
EOF
python3 "$PIPE" policy-block-check --plan "$work/plan.md" \
  --surface "$work/fresh-surface.txt" --config-json "$work/source-config.json" \
  --config-version cfgv1 > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "False" ] \
  && ok "re-consult recompute clears a recorded stale when the referenced lines still hold" \
  || err "re-consult did not clear the stale: $(cat "$work/out.json")"

# Recompute against a moved+changed surface re-blocks, naming the current pin.
cat > "$work/moved-changed.txt" <<EOF
pin: product-lab@$newsha
=== topics/articles.md @ $newsha
17: Site syndicates everywhere now.
EOF
python3 "$PIPE" policy-block-check --plan "$work/plan.md" \
  --surface "$work/moved-changed.txt" --config-json "$work/source-config.json" \
  --config-version cfgv1 > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "True" ] \
  && [ "$(field "$work/out.json" pin_delta.current_pin)" = "product-lab@$newsha" ] \
  && grep -q "topics/articles.md:17@$oldsha" "$work/out.json" \
  && ok "recompute against a moved+changed surface re-blocks, naming recorded vs current pin + changed pointer" \
  || err "moved+changed recompute wrong: $(cat "$work/out.json")"

# Recompute against the conflict config re-blocks with positions (live conflict).
python3 "$PIPE" policy-block-check --plan "$work/plan.md" \
  --surface "$work/fresh-surface.txt" --config-json "$FIX/config.json" \
  --config-version cfgv1 > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "True" ] \
  && grep -q '"authority": "policy"' "$work/out.json" \
  && grep -q '"authority": "config"' "$work/out.json" \
  && ok "recompute detecting a live conflict re-blocks with both positions" \
  || err "live-conflict recompute wrong: $(cat "$work/out.json")"

# --- (d) conformant / open plan proceeds -----------------------------------------
plan conformant
python3 "$PIPE" policy-block-check --plan "$work/plan.md" > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "False" ] \
  && ok "conformant plan proceeds unchanged" \
  || err "conformant plan blocked: $(cat "$work/out.json")"
plan open
python3 "$PIPE" policy-block-check --plan "$work/plan.md" > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "False" ] \
  && ok "open plan proceeds unchanged" \
  || err "open plan blocked: $(cat "$work/out.json")"

# --- (e) generic mode: the gate never fires --------------------------------------
python3 "$PIPE" policy-block-check > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "False" ] \
  && [ "$(field "$work/out.json" reason)" = "generic-mode" ] \
  && ok "no inputs at all → {blocked: false, reason: generic-mode}" \
  || err "bare generic mode wrong: $(cat "$work/out.json")"
cat > "$work/generic-plan.md" <<EOF
---
kind: article-plan
slug: generic-plan
intent: share engineering lessons
claim: a plain non-policy run
status: outlined
run_id: 20260718T090000-000002
pin: demo-repo@$sha
---

- a decision with no policy seeding at all
EOF
python3 "$PIPE" policy-block-check --plan "$work/generic-plan.md" > "$work/out.json"
[ "$(field "$work/out.json" reason)" = "generic-mode" ] \
  && ok "non-policy-seeded plan → generic-mode (the gate never touches a generic run)" \
  || err "generic plan not exempt: $(cat "$work/out.json")"

# No-conflict classification (nothing to reconcile) proceeds, but is NOT generic.
printf '{"syndication": {"policy": {"en": {"mode": "source", "variants": []}}}}' \
  > "$work/no-conflict-config.json"
python3 "$PIPE" classify-policy --surface "$FIX/surface.txt" \
  --config-json "$work/no-conflict-config.json" --items "$FIX/items.json" \
  > "$work/clean-classified.json"
python3 "$PIPE" policy-block-check --classification "$work/clean-classified.json" \
  > "$work/out.json"
[ "$(field "$work/out.json" blocked)" = "False" ] \
  && [ "$(field "$work/out.json" reason)" != "generic-mode" ] \
  && ok "conflict-free classification proceeds (checked, not generic)" \
  || err "conflict-free classification wrong: $(cat "$work/out.json")"

# --- (f) SKILL wiring ------------------------------------------------------------
grep -q 'policy-block-check' "$SKILL" \
  && ok "SKILL runs policy-block-check" || err "SKILL missing policy-block-check"
awk '/### Stage 2→3 policy-block gate/,/^## Stage 3/' "$SKILL" \
  | grep -q 'policy-block-check' \
  && ok "SKILL wires the block at the Stage 2→3 boundary (before any Stage 3 fill)" \
  || err "SKILL block not at the Stage 2→3 boundary"
grep -q '"stage": "policy-block", "next_stage": "interview"' "$SKILL" \
  && ok "SKILL states the block checkpoint payload (resume at the block, next_stage: interview)" \
  || err "SKILL missing the block checkpoint payload"
grep -qi 'never `next_stage: fill`' "$SKILL" \
  && ok "SKILL forbids checkpointing past the gate (never next_stage: fill)" \
  || err "SKILL missing the never-fill rule"
grep -qi 'publish-blockers bucket.*carries the payload' "$SKILL" \
  && grep -qi 'positions with' "$SKILL" \
  && ok "SKILL: the publish-blockers bucket carries the payload's positions + resume path" \
  || err "SKILL missing the publish-blocker bucket wiring"
grep -qi 'Generic mode never touches the gate' "$SKILL" \
  && grep -q 'reason: "generic-mode"' "$SKILL" \
  && ok "SKILL states the generic-mode exemption" \
  || err "SKILL missing the generic-mode exemption"
grep -qi 're-consult at the current pin' "$SKILL" \
  && ok "SKILL states the stale in-run repair (re-consult at the current pin)" \
  || err "SKILL missing the stale repair"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-block checks passed.\n'; exit 0
else
  printf '\npolicy-block checks FAILED.\n' >&2; exit 1
fi
