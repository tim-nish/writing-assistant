#!/usr/bin/env sh
# check-plan-conformance.sh — verify the CAP-4 plan policy-conformance gate
# (Story 13.76, SPEC-article-plan CAP-4 added 2026-07-18, umbrella #365).
# POSIX shell + stdlib Python only.
#
# Covers: all four statuses — conformant (checked-clean against the pinned
# surface + config), open (policy-seeded but unclassifiable by the comparable
# table), conflict (the 2026-07-18 EN-topology replay, both positions named
# with pointers), stale (moved pin + a changed referenced line; a moved pin
# with unchanged referenced lines stays conformant); the reversal rule (a
# reversing decision with its staging-candidate block → conformant +
# reversal_as_proposal); the writer's required-when-policy-seeded rule for the
# conformance trio; per-key fail-closed refusals (bad enum, malformed pin, bad
# configVersion); the --write round-trip through the writer's validation; the
# gate's no-hub-write invariant; and the SKILL wiring.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

W="scripts/write-article-plan.py"
FIX="scripts/fixtures/policy-classification"
SKILL="skills/draft-article/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 -c "import py_compile; py_compile.compile('$root/$W', doraise=True)" 2>/dev/null \
  && ok "writer compiles" || { err "writer syntax error"; printf '\nFAILED.\n' >&2; exit 1; }
python3 -c "import py_compile; py_compile.compile('$root/scripts/policy_subjects.py', doraise=True)" 2>/dev/null \
  && ok "shared policy_subjects module compiles" || err "policy_subjects syntax error"

sha=cb43caf4a5b6c7d8e9f0a1b2c3d4e5f607182931
oldsha=aaaa000000000000000000000000000000000000

# A no-conflict config: EN mode is source, not canonical.
printf '{"syndication": {"policy": {"en": {"mode": "source", "variants": []}}}}' \
  > "$work/source-config.json"

# The policy-seeded plan under test: seeded from the served records-only line,
# with the consulted quote recorded on the body pointer.
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
seed: topics/articles.md:17@$sha
---

## Section plan

- keep the site records-only, per "Website stays independent — reference records only." / topics/articles.md:17@$sha
EOF
}

G() { python3 "$W" conformance --plan "$work/plan.md" --surface "$1" \
      --config-json "$2" --config-version cfgv1 ${3:-}; }
status_of() { python3 -c "import json,sys; print(json.load(sys.stdin)['$2'])" < "$1"; }

# --- 1. conformant: checked and clean --------------------------------------------
plan
G "$FIX/surface.txt" "$work/source-config.json" > "$work/out.json" \
  || err "gate failed on the clean case"
[ "$(status_of "$work/out.json" status)" = "conformant" ] \
  && ok "conformant: seeded decision checked against pin + config, clean" \
  || err "clean case not conformant: $(cat "$work/out.json")"
python3 - "$work/out.json" <<'PYEOF' \
  && ok "conformant: findings say checked-clean (not merely unchecked)" \
  || err "conformant lacks a checked-clean finding"
import json, sys
d = json.load(open(sys.argv[1]))
assert any(f["kind"] == "checked-clean" and f["subject"] == "en-topology"
           for f in d["findings"]), d["findings"]
assert d["pin"].startswith("product-lab@") and d["config_version"] == "cfgv1", d
PYEOF

# --- 2. open: policy-seeded but unclassifiable -----------------------------------
# Seeded from a served line no comparable subject classifies (LESSONS.md:41).
sed -e "s|topics/articles.md:17|LESSONS.md:41|g" \
    -e 's|"Website stays independent — reference records only."|"report trust must be enforced"|' \
    "$work/plan.md" > "$work/plan2.md" && mv "$work/plan2.md" "$work/plan.md"
G "$FIX/surface.txt" "$work/source-config.json" > "$work/out.json" \
  || err "gate failed on the open case"
[ "$(status_of "$work/out.json" status)" = "open" ] \
  && ok "open: seeded decision the comparable table cannot classify (nothing to check)" \
  || err "unclassifiable case not open: $(cat "$work/out.json")"
grep -q '"unclassifiable"' "$work/out.json" \
  && ok "open: finding names the unclassifiable pointer" \
  || err "open finding missing"

# --- 3. conflict: the 2026-07-18 EN-topology replay ------------------------------
plan
G "$FIX/surface.txt" "$FIX/config.json" > "$work/out.json" \
  || err "gate failed on the replay"
[ "$(status_of "$work/out.json" status)" = "conflict" ] \
  && ok "conflict: records-only seed vs syndication.policy.en.mode: canonical (the replay)" \
  || err "replay not conflict: $(cat "$work/out.json")"
python3 - "$work/out.json" <<'PYEOF' \
  && ok "conflict: both positions named with pointers" \
  || err "conflict positions wrong"
import json, sys
d = json.load(open(sys.argv[1]))
f = next(f for f in d["findings"] if f["kind"] == "conflict")
auth = {p["authority"]: p for p in f["positions"]}
assert set(auth) == {"policy", "config"}, auth
assert auth["policy"]["pointer"].startswith("topics/articles.md:17@"), auth["policy"]
assert auth["config"]["pointer"] == "syndication.policy.en.mode@cfgv1", auth["config"]
assert d["reversal_as_proposal"] is False
PYEOF

# --- 4. reversal rule: staging-candidate block → conformant as a proposal --------
cat > "$work/staging.md" <<EOF
<!-- staging-candidate -->
---
slug: 2026-07-18-demo-repo-en-topology-rc1
created: 2026-07-18
source_repo: demo-repo
perishable: true
tags: [config-policy-reconciliation]
---
Q: Config↔policy reconciliation decision — which position governs? (positions: policy: "Website stays independent — reference records only." — topics/articles.md:17@$sha; config: "syndication.policy.en.mode: canonical" — syndication.policy.en.mode@cfgv1)
Decision: Config governs; propose updating the records-only line.
EOF
G "$FIX/surface.txt" "$FIX/config.json" "--staging $work/staging.md" > "$work/out.json" \
  || err "gate failed on the reversal case"
[ "$(status_of "$work/out.json" status)" = "conformant" ] \
  && [ "$(status_of "$work/out.json" reversal_as_proposal)" = "True" ] \
  && ok "reversal: with its staging block the reversal is conformant + reversal_as_proposal (proposed change, never current policy)" \
  || err "reversal-with-staging wrong: $(cat "$work/out.json")"
# A staging file that does not cover the subject leaves the conflict standing.
printf '<!-- staging-candidate -->\n---\ntags: [opinion]\n---\nQ: unrelated\nDecision: x\n' \
  > "$work/other-staging.md"
G "$FIX/surface.txt" "$FIX/config.json" "--staging $work/other-staging.md" > "$work/out.json"
[ "$(status_of "$work/out.json" status)" = "conflict" ] \
  && ok "reversal: without a matching staging block the status stays conflict" \
  || err "non-matching staging block cleared the conflict"

# --- 5. stale: moved pin + changed referenced line -------------------------------
newsha=bbbb000000000000000000000000000000000000
cat > "$work/moved-changed.txt" <<EOF
pin: product-lab@$newsha
=== topics/articles.md @ $newsha
15: ## Website
16: updated: 2026-07-19
17: Site syndicates everywhere now.
18: state: ratified
EOF
plan
G "$work/moved-changed.txt" "$work/source-config.json" > "$work/out.json" \
  || err "gate failed on the stale case"
[ "$(status_of "$work/out.json" status)" = "stale" ] \
  && ok "stale: moved pin + the referenced line's text changed since the recorded quote" \
  || err "moved-pin-changed-line not stale: $(cat "$work/out.json")"
grep -q '"stale"' "$work/out.json" && grep -q 'topics/articles.md:17@' "$work/out.json" \
  && ok "stale: finding carries the referenced pointer" || err "stale finding missing pointer"

# Moved pin, unchanged referenced line → stays conformant.
cat > "$work/moved-unchanged.txt" <<EOF
pin: product-lab@$newsha
=== topics/articles.md @ $newsha
15: ## Website
16: updated: 2026-07-19
17: Website stays independent — reference records only.
18: state: ratified
EOF
G "$work/moved-unchanged.txt" "$work/source-config.json" > "$work/out.json" \
  || err "gate failed on the moved-unchanged case"
[ "$(status_of "$work/out.json" status)" = "conformant" ] \
  && ok "stale rule: a moved pin with unchanged referenced lines stays conformant" \
  || err "moved-pin-unchanged-line not conformant: $(cat "$work/out.json")"

# A recorded policy_pin that moved counts too (re-validation of a written plan).
plan
sed -i "s|^policy_seeded: true$|policy_seeded: true\npolicy_pin: product-lab@$oldsha\npolicy_config_version: cfgv1\npolicy_conformance: conformant|" "$work/plan.md" 2>/dev/null || true
G "$work/moved-changed.txt" "$work/source-config.json" > "$work/out.json"
[ "$(status_of "$work/out.json" status)" = "stale" ] \
  && ok "stale: recorded policy_pin differs from the surface's current pin (re-validation)" \
  || err "recorded-pin re-validation not stale: $(cat "$work/out.json")"

# --- 6. writer: the conformance trio is required when policy_seeded --------------
plan   # policy-seeded, trio absent
reason=$(python3 "$W" validate --path plans/demo-plan.md "$work/plan.md" 2>&1) && \
  err "policy-seeded plan without the trio was accepted" || true
printf '%s' "$reason" | grep -q 'required when policy_seeded is true' \
  && printf '%s' "$reason" | grep -q 'conformance --write' \
  && ok "writer refuses a policy-seeded plan missing the trio, pointing at the gate" \
  || err "missing-trio refusal wrong: $reason"

trio() {
plan
sed -i "s|^policy_seeded: true$|policy_seeded: true\npolicy_pin: ${1}\npolicy_config_version: ${2}\npolicy_conformance: ${3}|" "$work/plan.md"
}
# Bad enum value.
trio "product-lab@$sha" cfgv1 fine
python3 "$W" validate --path plans/demo-plan.md "$work/plan.md" 2>&1 \
  | grep -q "unknown conformance status 'fine'" \
  && ok "refuse: bad policy_conformance enum (named)" || err "bad enum accepted"
# Malformed pin.
trio "not a pin" cfgv1 conformant
python3 "$W" validate --path plans/demo-plan.md "$work/plan.md" 2>&1 \
  | grep -q 'policy_pin: must be the consulted policy pin' \
  && ok "refuse: malformed policy_pin (named)" || err "malformed policy_pin accepted"
# Bad configVersion characters.
trio "product-lab@$sha" 'cfg v1!' conformant
python3 "$W" validate --path plans/demo-plan.md "$work/plan.md" 2>&1 \
  | grep -q 'policy_config_version: must match' \
  && ok "refuse: bad policy_config_version (named)" || err "bad configVersion accepted"
# The complete, well-formed trio validates.
trio "product-lab@$sha" cfgv1 conformant
python3 "$W" validate --path plans/demo-plan.md "$work/plan.md" >/dev/null 2>&1 \
  && ok "well-formed trio validates" || err "well-formed trio refused"

# --- 7. --write round-trip through the writer's validation -----------------------
plan   # trio absent; the gate records it
surface_before=$(cat "$FIX/surface.txt")
G "$FIX/surface.txt" "$work/source-config.json" --write > "$work/out.json" \
  || err "conformance --write failed"
grep -q "^policy_pin: product-lab@$sha$" "$work/plan.md" \
  && grep -q '^policy_config_version: cfgv1$' "$work/plan.md" \
  && grep -q '^policy_conformance: conformant$' "$work/plan.md" \
  && ok "--write records the trio in the plan's frontmatter" \
  || err "--write did not record the trio: $(cat "$work/plan.md")"
python3 "$W" validate --path plans/demo-plan.md "$work/plan.md" >/dev/null 2>&1 \
  && ok "--write round-trip: the written plan passes the writer's validation" \
  || err "written plan fails validation"
# Idempotent: writing again replaces, never duplicates.
G "$FIX/surface.txt" "$work/source-config.json" --write > /dev/null
[ "$(grep -c '^policy_pin:' "$work/plan.md")" -eq 1 ] \
  && ok "--write is idempotent (keys replaced, not duplicated)" \
  || err "--write duplicated the trio"
# No-hub-write invariant: the surface (the policy side) is untouched.
[ "$surface_before" = "$(cat "$FIX/surface.txt")" ] \
  && ok "the gate writes nothing to any policy surface/hub (plan file only)" \
  || err "the gate modified the policy surface"
# A --write whose result the schema refuses writes nothing (fail-closed).
plan
sed -i 's/^status: outlined$/status: outlined\ntitle: a draft-owned field/' "$work/plan.md"
before=$(cat "$work/plan.md")
python3 "$W" conformance --plan "$work/plan.md" --surface "$FIX/surface.txt" \
  --config-json "$work/source-config.json" --config-version cfgv1 --write \
  >/dev/null 2>&1 && err "--write on a schema-refused plan exited 0" || true
[ "$before" = "$(cat "$work/plan.md")" ] \
  && ok "fail-closed: a refused --write leaves the plan untouched" \
  || err "refused --write still modified the plan"

# --- 8. SKILL wiring -------------------------------------------------------------
grep -q 'write-article-plan.py conformance' "$SKILL" \
  && ok "SKILL runs the conformance gate at plan emission" \
  || err "SKILL missing the conformance step"
grep -q -- '--staging' "$SKILL" && grep -qi 'reversal_as_proposal' "$SKILL" \
  && ok "SKILL states the reversal-as-proposal rule" \
  || err "SKILL missing the reversal rule"
grep -qi 'recorded, not blocking' "$SKILL" \
  && ok "SKILL: conflict/stale is recorded, not blocking (the block is Story 13.77)" \
  || err "SKILL missing the record-not-block note"
grep -qi 'nothing to any policy hub' "$SKILL" \
  && ok "SKILL states the no-hub-write invariant" \
  || err "SKILL missing the no-hub-write invariant"

if [ "$fail" -eq 0 ]; then
  printf '\nAll plan-conformance checks passed.\n'; exit 0
else
  printf '\nplan-conformance checks FAILED.\n' >&2; exit 1
fi
