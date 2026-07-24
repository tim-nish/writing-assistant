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
assert d['stage']=='complete' and d['next_stage']=='done', d
assert d.get('canonical_slug')=='$slug', d   # no-clobber ownership record (#666)
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

# 3b. No-clobber gate (Story 18.92, #666): a DIFFERENT canonical minting a
#     colliding slug is refused, not silently overwritten.
# (a) A different run (fresh workspace, no ownership) writing DIFFERENT content
#     to the same slug is refused; the on-disk canonical is untouched.
wsc="$work/wsc"; mkdir -p "$wsc"
sed 's/late\./late again — a wholly different draft body\./' "$ws/draft.md" > "$wsc/draft.md"
before=$(cat "$a/drafts/$slug.md")
if python3 "$DP" complete --draft "$wsc/draft.md" --slug "$slug" --root "$h" --ws "$wsc" \
     >/dev/null 2>"$work/e_clobber"; then
  err "no-clobber gate: an unowned slug collision was allowed to overwrite"
else
  grep -q 'slug collision' "$work/e_clobber" \
    && [ "$before" = "$(cat "$a/drafts/$slug.md")" ] \
    && ok "no-clobber gate: unowned slug collision refused, canonical untouched (#666)" \
    || err "no-clobber refusal wrong: $(cat "$work/e_clobber")"
fi
[ ! -f "$wsc/checkpoint.json" ] \
  && ok "no-clobber gate: no checkpoint on a refused collision" \
  || err "checkpoint written despite refused collision"
# (b) --replace-canonical overrides the refusal deliberately.
python3 "$DP" complete --draft "$wsc/draft.md" --slug "$slug" --root "$h" --ws "$wsc" --replace-canonical >/dev/null \
  && grep -q 'wholly different draft body' "$a/drafts/$slug.md" \
  && ok "no-clobber gate: --replace-canonical overwrites deliberately" \
  || err "--replace-canonical did not override the collision refusal"
# (c) The owning run (ws checkpoint records the slug) may revise its own canonical.
sed 's/late\./late — revised by the owning run\./' "$ws/draft.md" > "$ws/draft2.md"
python3 "$DP" complete --draft "$ws/draft2.md" --slug "$slug" --root "$h" --ws "$ws" >/dev/null \
  && grep -q 'revised by the owning run' "$a/drafts/$slug.md" \
  && ok "no-clobber gate: the owning run's revision loop proceeds (#666)" \
  || err "owned same-run revision was refused"

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

# 7. F82: a missing output.drafts INSIDE the host is auto-created (the ratified
#    #213 variants convention: create inside-host, consent outside), so a fresh
#    host no longer hard-errors 'directory does not exist' on the first draft.
h5="$work/host5"; mkdir -p "$h5"; git -C "$h5" init -q
d5="$h5/articles/drafts"                       # inside the host, NOT created
python3 "$root/scripts/resolve-writing-sources.py" --root "$h5" \
  set-draft-location "$d5/" >/dev/null 2>&1
python3 "$W" write --slug "$slug" --root "$h5" "$work/plan.md" >/dev/null 2>&1 \
  && ok "fixture: plan written for the inside-host auto-create case" || err "inside-host plan write failed"
ws5="$work/ws5"; mkdir -p "$ws5"
[ ! -d "$d5" ] || err "fixture bug: inside-host drafts dir already exists"
out=$(python3 "$DP" complete --draft "$ws/draft.md" --slug "$slug" --root "$h5" --ws "$ws5") \
  && ok "inside-host missing output.drafts is auto-created — complete succeeds (F82)" \
  || err "inside-host missing output.drafts still refused (F82 regression)"
[ -f "$d5/$slug.md" ] \
  && ok "canonical persisted into the auto-created inside-host drafts dir" \
  || err "canonical not persisted after auto-create"

# --- INDEX.md browsing-surface view (Story 18.43, #540) ----------------------
# The articles repo declares INDEX.md "regenerated — one line per
# backlog/draft/newsletter item"; nothing carried it out, so a repo with 4
# drafts read `_Empty._`. It is a VIEW (files win, idempotent), never a third
# completion-gated product.
RI="$root/scripts/regenerate-index.py"
python3 -c "import py_compile; py_compile.compile('$RI', doraise=True)" 2>/dev/null \
  && ok "regenerate-index.py is stdlib-only Python (compiles)" || err "regenerate-index.py syntax error"

# end-to-end: the completion gate above persisted `$slug` into $a — its INDEX
# must now list it (the #540 defect was exactly this line being absent).
if grep -q "\`$slug\`" "$a/INDEX.md" 2>/dev/null; then
  ok "complete regenerated the articles-repo INDEX.md to list the persisted draft (#540)"
else
  err "INDEX.md does not list the persisted draft after complete: $(cat "$a/INDEX.md" 2>/dev/null | tr '\n' ' ')"
fi

# unit: a repo whose items are present but whose INDEX says _Empty._ (the #540 state)
ai="$work/articles-idx"; mkdir -p "$ai/drafts" "$ai/backlog"
printf -- '---\nslug: alpha\ntitle: "Alpha draft"\ndate: 2026-07-22\n---\nbody\n' > "$ai/drafts/alpha.md"
printf -- '---\none_liner: "Beta idea"\nstatus: evidenced\n---\nbody\n' > "$ai/backlog/beta.md"
printf '# INDEX\n\nRegenerated — one line per backlog/draft/newsletter item.\n\n_Empty._\n' > "$ai/INDEX.md"
python3 "$RI" check --repo "$ai" >/dev/null 2>&1 \
  && err "index check passed on a stale INDEX.md (#540 state)" \
  || ok "index check detects a stale INDEX.md (#540 state)"
python3 "$RI" write --repo "$ai" >/dev/null 2>&1 || err "index write failed"
if grep -q '`alpha`' "$ai/INDEX.md" && grep -q '`beta`' "$ai/INDEX.md"; then
  ok "regenerated INDEX.md lists both draft and backlog items"
else
  err "INDEX.md missing items after regeneration"
fi
python3 "$RI" write --repo "$ai" 2>/dev/null | grep -q '"changed": false' \
  && ok "index regeneration is idempotent (a current index is a no-op)" \
  || err "index regeneration not idempotent"
python3 "$RI" check --repo "$ai" >/dev/null 2>&1 \
  && ok "index check reports current after regeneration" || err "index still stale after write"
# contract: wired at complete, and stated as a view rather than a third product
grep -q 'regenerate-index.py' "$root/scripts/draft-pipeline.py" \
  && ok "complete wires INDEX regeneration" || err "complete does not wire index regeneration"
grep -q 'regenerate-index.py' "$SKILL" && grep -qi 'never a third declared product\|not a third declared product' "$SKILL" \
  && ok "SKILL states INDEX is a view, never a third declared product" \
  || err "SKILL missing the INDEX view/disclosure contract"

if [ "$fail" -eq 0 ]; then
  printf '\nAll completion-gate checks passed.\n'; exit 0
else
  printf '\ncompletion-gate checks FAILED.\n' >&2; exit 1
fi
