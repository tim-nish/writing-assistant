#!/usr/bin/env sh
# check-complete-gate.sh — verify the dual-product completion gate (Story
# 13.68, SPEC-article-draft-pipeline 2026-07-18 amendment; SPEC-platform-
# variants CAP-1). The `complete` subcommand is the only sanctioned way to
# finish a draft run: the canonical draft (drafts/<slug>.md at output.drafts,
# with the emission trailer) AND the article plan (plans/<slug>.md, or its
# user-scoped fallback) must BOTH be persisted before the `next_stage: done`
# checkpoint is written; a failed write of either is a hard error naming the
# product and path, and no checkpoint is written. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
W="$root/scripts/write-article-plan.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# The SKILL routes completion through the gate, not a hand-written checkpoint.
grep -q 'draft-pipeline.py complete' "$SKILL" \
  && ok "SKILL invokes the complete subcommand" || err "SKILL does not invoke complete"
grep -q '"next_stage":"done"' "$SKILL" \
  && err "SKILL still hand-writes the next_stage: done checkpoint" \
  || ok "hand-written done-checkpoint removed from the SKILL"
grep -q '| `complete` |' "$SKILL" \
  && ok "complete listed in the pipeline command reference" || err "complete missing from the command table"
grep -qi 'both persisted' "$SKILL" \
  && ok "SKILL states the two-product completion gate" || err "two-product gate not stated in the SKILL"

# Fixture: host source repo + a conforming articles repo (drafts/ + INDEX.md),
# output.drafts declared through the sanctioned writer, plan written through
# write-article-plan.py, a run workspace with a draft.
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts"; git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1

ws="$work/ws"; mkdir -p "$ws"
slug=retry-storms
cat > "$ws/draft.md" <<'EOF'
---
slug: retry-storms
title: "Retry storms doubled our token spend"
language: en
audience: en-practitioner
audience_id: en-practitioner
---

## Hook

The retry storm doubled token spend, and we caught it late.
EOF

sha=a1b2c3d4e5f6a7b8
cat > "$work/plan.md" <<EOF
---
kind: article-plan
slug: $slug
intent: share engineering lessons
claim: the retry storm was a policy defect, not a load spike
status: drafted
run_id: 20260718T000000-000000
pin: host@$sha
---

## Section plan

- the retry policy tripled load / docs/retries.md:12@$sha
EOF
python3 "$W" write --slug "$slug" --root "$h" "$work/plan.md" >/dev/null 2>&1 \
  && ok "fixture: plan written to the articles repo" || err "fixture plan write failed"

# 1. Both products present → success: canonical persisted with the emission
#    trailer, done-checkpoint written, both absolute paths in the JSON.
out=$(python3 "$DP" complete --draft "$ws/draft.md" --slug "$slug" --root "$h" --ws "$ws") \
  && ok "complete succeeds with both products" || err "complete failed on the success path"
printf '%s' "$out" | python3 -c "
import json,sys,os
d=json.load(sys.stdin)
assert d['stage']=='complete' and d['next_stage']=='done', d
c=d['products']['canonical']; p=d['products']['plan']
assert os.path.isabs(c['path']) and os.path.isabs(p['path']), d
assert c['path'].endswith('/drafts/$slug.md'), d
assert p['path'].endswith('/plans/$slug.md'), d
assert d['checkpoint'], d
" && ok "completion JSON names both persisted absolute paths" \
  || err "completion JSON shape wrong"
[ -f "$a/drafts/$slug.md" ] && ok "canonical persisted at output.drafts" || err "canonical not persisted"
python3 -c "
import json,sys
d=json.load(open('$ws/checkpoint.json'))
assert d=={'stage':'complete','next_stage':'done'}, d
" && ok "done-checkpoint written only through the gate" || err "done-checkpoint wrong/missing"

# 2. Emission-trailer hash matches the variants-stage convention: the trailer
#    parses with the same regex and equals sha256 over the trailer-stripped
#    draft content (one hash convention, not two).
python3 - "$a/drafts/$slug.md" <<'EOF' && ok "trailer hash = sha256 over content without the trailer (variants convention)" || err "trailer hash convention broken"
import hashlib, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"canonical-sha256=([0-9a-f]{64})", text)      # cmd_variant_staleness's parse
assert m, "no emission trailer"
body = re.sub(r"\n*<!-- writing-assistant: canonical-sha256=[0-9a-f]{64} -->\s*$", "", text)
body = body.rstrip("\n") + "\n"      # the content the trailer hash is over
assert hashlib.sha256(body.encode("utf-8")).hexdigest() == m.group(1)
EOF

# 3. Idempotent re-run: over already-persisted products, complete verifies and
#    succeeds, and the canonical stays byte-identical (same hash, same trailer).
first=$(cat "$a/drafts/$slug.md")
python3 "$DP" complete --draft "$ws/draft.md" --slug "$slug" --root "$h" --ws "$ws" >/dev/null \
  && ok "re-run over persisted products succeeds (idempotent)" || err "idempotent re-run failed"
[ "$first" = "$(cat "$a/drafts/$slug.md")" ] \
  && ok "re-run leaves the canonical byte-identical" || err "re-run changed the canonical"
# Re-running over the PERSISTED canonical itself (trailer already present)
# strips before hashing — the trailer is never hashed into its own hash.
python3 "$DP" complete --draft "$a/drafts/$slug.md" --slug "$slug" --root "$h" --ws "$ws" >/dev/null \
  && [ "$first" = "$(cat "$a/drafts/$slug.md")" ] \
  && ok "complete over the persisted canonical re-verifies to the same bytes" \
  || err "trailer was hashed into its own hash on re-run"

# 4. Plan missing → hard error naming product + path, NO checkpoint, even
#    though the canonical write succeeded (partial success still hard-errors).
ws2="$work/ws2"; mkdir -p "$ws2"
sed 's/^slug: retry-storms$/slug: no-plan-yet/' "$ws/draft.md" > "$ws2/draft.md"
if python3 "$DP" complete --draft "$ws2/draft.md" --slug no-plan-yet --root "$h" --ws "$ws2" \
     >/dev/null 2>"$work/e_plan"; then
  err "completion reported with no plan persisted"
else
  grep -q 'article plan' "$work/e_plan" && grep -q 'plans/no-plan-yet.md' "$work/e_plan" \
    && ok "missing plan is a hard error naming the product and path" \
    || err "plan hard-error message wrong: $(cat "$work/e_plan")"
fi
[ ! -f "$ws2/checkpoint.json" ] \
  && ok "no checkpoint on plan failure (canonical-only is never done)" \
  || err "checkpoint written despite missing plan"

# 5. Canonical write failure (missing output.drafts directory) → hard error
#    naming product + path, NO checkpoint.
h3="$work/host3"; mkdir -p "$h3"; git -C "$h3" init -q
python3 "$root/scripts/resolve-writing-sources.py" --root "$h3" \
  set-draft-location "$work/nowhere/drafts/" >/dev/null 2>&1 || true
ws3="$work/ws3"; mkdir -p "$ws3"
if python3 "$DP" complete --draft "$ws/draft.md" --slug "$slug" --root "$h3" --ws "$ws3" \
     >/dev/null 2>"$work/e_canon"; then
  err "completion reported with an unwritable canonical destination"
else
  grep -q 'canonical draft' "$work/e_canon" && grep -q "$slug.md" "$work/e_canon" \
    && ok "failed canonical write is a hard error naming the product and path" \
    || err "canonical hard-error message wrong: $(cat "$work/e_canon")"
fi
[ ! -f "$ws3/checkpoint.json" ] \
  && ok "no checkpoint on canonical failure" || err "checkpoint written despite canonical failure"

# 6. Schema-less destination: the plan's user-scoped fallback COUNTS as a
#    successful plan write (write-article-plan.py's actual fallback behavior).
h4="$work/host4"; mkdir -p "$h4"; git -C "$h4" init -q
d4="$work/plain-drafts"; mkdir -p "$d4"       # no articles-repo schema around it
python3 "$root/scripts/resolve-writing-sources.py" --root "$h4" \
  set-draft-location "$d4/" >/dev/null 2>&1
python3 "$W" write --slug "$slug" --root "$h4" "$work/plan.md" >/dev/null 2>&1 \
  && ok "fixture: plan landed at the user-scoped fallback" || err "fallback plan write failed"
ws4="$work/ws4"; mkdir -p "$ws4"
out=$(python3 "$DP" complete --draft "$ws/draft.md" --slug "$slug" --root "$h4" --ws "$ws4") \
  && ok "fallback plan counts — complete succeeds" || err "fallback plan rejected by the gate"
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["products"]["plan"]["conforming"] is False, d
assert d["products"]["plan"]["fallback"], d
' && ok "completion JSON records the fallback plan destination" \
  || err "fallback not reflected in the completion JSON"
[ -f "$ws4/checkpoint.json" ] && ok "done-checkpoint written on the fallback path" \
  || err "no checkpoint despite both products verified"

if [ "$fail" -eq 0 ]; then
  printf '\nAll completion-gate checks passed.\n'; exit 0
else
  printf '\ncompletion-gate checks FAILED.\n' >&2; exit 1
fi
