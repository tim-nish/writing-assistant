#!/usr/bin/env sh
# check-article-plan.sh — verify the article-plan writer (Story 13.55,
# SPEC-article-plan CAP-1/CAP-2). POSIX shell + stdlib Python.
#
# Covers: the plan is a deterministic projection (byte-identical regeneration,
# no prompt); fail-closed schema validation with per-key diagnostics (slug
# mismatch, wrong/absent kind, each forbidden field class, prose evidence, an
# unpinned pointer, a non-plans/ path); the schema-less-destination fallback to
# user-scoped state with NO plans/ dir in the destination; and the emission
# invariant — only the plan file lands, never machine state, never the host repo.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

W="$root/scripts/write-article-plan.py"
SPEC="specs/spec-article-plan/SPEC.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$W', doraise=True)" 2>/dev/null \
  && ok "writer compiles" || { err "writer syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

# Host source repo (the target being written about) + a conforming articles repo.
h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts" "$a/backlog"; git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1

plan() { cat > "$work/plan.md"; }
V() { python3 "$W" validate --path "$1" "$work/plan.md" >/dev/null 2>&1; }
reason() { python3 "$W" validate --path "$1" "$work/plan.md" 2>&1; }

sha=$(printf '%s' a1b2c3d4e5f6a7b8)

# A conforming plan: every required key, pinned body pointers, no forbidden field.
good() {
plan <<EOF
---
kind: article-plan
slug: interview-is-the-difference
intent: share engineering lessons
claim: the interview is the difference between a fact sheet and an article
status: outlined
run_id: 20260717T135459-737958
pin: writing-assistant@$sha
audience: solo developers shipping their own tools
audience_id: en-practitioner
policy_seeded: true
seed: topics/articles.md:36@$sha
---

## Section plan

- the interview carries the article / docs/interview-architecture.md:12@$sha
- owner ratified the anchor / q3
- prior finding / den:f-19@r-208

## Unresolved

- declined tension item (slot effect: generic fallback) / a7
EOF
}

# --- CAP-1: deterministic projection --------------------------------------
good
python3 "$W" write --slug interview-is-the-difference --root "$h" "$work/plan.md" >/dev/null 2>&1 \
  && ok "conforming plan is written" || err "conforming plan was refused"
first=$(cat "$a/plans/interview-is-the-difference.md")
python3 "$W" write --slug interview-is-the-difference --root "$h" "$work/plan.md" >/dev/null 2>&1
[ "$first" = "$(cat "$a/plans/interview-is-the-difference.md")" ] \
  && ok "CAP-1: regenerating from the same artifacts is byte-identical" \
  || err "regeneration was not byte-identical"
[ -f "$a/plans/interview-is-the-difference.md" ] \
  && ok "CAP-1: the plan lands at plans/<slug>.md in the articles repo" \
  || err "plan not at plans/<slug>.md"

# Emission invariant: ONLY the plan file — no machine state in the articles
# repo, and nothing written into the host source repo.
[ "$(find "$a/plans" -type f | wc -l)" -eq 1 ] \
  && ok "emission: only the plan file lands in plans/" || err "extra files in plans/"
find "$a" \( -name 'journal*' -o -name 'checkpoint*' -o -name 'provenance-map*' \
  -o -name 'presented-payloads*' -o -name 'rubric-verdicts*' \) | grep -q . \
  && err "machine state landed in the articles repository" \
  || ok "emission: no journal/checkpoint/provenance-map data in the articles repo"
[ -z "$(git -C "$h" status --porcelain)" ] && [ ! -d "$h/plans" ] \
  && ok "emission: nothing written to the host source repo" \
  || err "the writer touched the host source repo"

# --- CAP-2: fail-closed schema validation ---------------------------------
P="plans/interview-is-the-difference.md"

# slug / filename mismatch.
good
reason "plans/some-other-slug.md" | grep -q 'must equal the filename stem' \
  && ok "refuse: slug/filename mismatch (per-key diagnostic)" || err "slug mismatch accepted"

# kind absent / wrong.
good; sed -i 's/^kind: article-plan$/kind: article-skeleton/' "$work/plan.md"
reason "$P" | grep -q "must be the constant" && ok "refuse: wrong kind" || err "wrong kind accepted"
good; sed -i '/^kind: /d' "$work/plan.md"
reason "$P" | grep -q 'kind: required key is missing' && ok "refuse: kind absent" || err "absent kind accepted"

# Each forbidden field class: draft-owned, machine state, draft lifecycle, prose evidence.
for f in title summary topics language published variants_emitted canonical_url; do
  good; printf '%s\n' "$(sed "s|^status: outlined$|status: outlined\n$f: x|" "$work/plan.md")" > "$work/plan.md"
  reason "$P" | grep -q "$f: forbidden" \
    && ok "refuse: draft-owned field '$f'" || err "draft-owned field '$f' accepted"
done
for f in checkpoint journal provenance_map; do
  good; printf '%s\n' "$(sed "s|^status: outlined$|status: outlined\n$f: x|" "$work/plan.md")" > "$work/plan.md"
  reason "$P" | grep -q "$f: forbidden" \
    && ok "refuse: machine-state field '$f'" || err "machine-state field '$f' accepted"
done
good; sed -i 's/^status: outlined$/status: published/' "$work/plan.md"
reason "$P" | grep -q 'DRAFT-lifecycle status' \
  && ok "refuse: draft-lifecycle status on a plan" || err "draft status accepted"
good; printf '%s\n' "$(sed 's|^status: outlined$|status: outlined\nevidence: we measured it and it felt faster|' "$work/plan.md")" > "$work/plan.md"
reason "$P" | grep -q 'evidence: forbidden' \
  && ok "refuse: prose evidence: field" || err "prose evidence field accepted"

# Prose evidence in the BODY (an evidence: line of free text).
good; printf 'evidence: it felt faster in the dogfood run\n' >> "$work/plan.md"
reason "$P" | grep -q 'prose evidence' \
  && ok "refuse: prose evidence line in the body" || err "body prose evidence accepted"

# An unpinned pointer in the body.
good; printf -- '- unpinned claim / docs/notes.md:12\n' >> "$work/plan.md"
reason "$P" | grep -q 'unpinned pointer' \
  && ok "refuse: unpinned body pointer" || err "unpinned pointer accepted"

# A non-plans/ path.
good
reason "drafts/interview-is-the-difference.md" | grep -q 'plans/<slug>.md' \
  && ok "refuse: a plan written outside plans/" || err "non-plans/ path accepted"

# policy_seeded without its audited seed pointer.
good; sed -i "/^seed: /d" "$work/plan.md"
reason "$P" | grep -q 'required when policy_seeded is true' \
  && ok "refuse: policy_seeded without a seed pointer" || err "unaudited policy seed accepted"

# Unknown field (closed schema).
good; printf '%s\n' "$(sed 's|^status: outlined$|status: outlined\nvibes: good|' "$work/plan.md")" > "$work/plan.md"
reason "$P" | grep -q 'unknown field' && ok "refuse: unknown field (closed schema)" || err "unknown field accepted"

# A refused plan writes NOTHING.
good; sed -i 's/^kind: article-plan$/kind: nope/' "$work/plan.md"
before=$(find "$a/plans" -type f | wc -l)
python3 "$W" write --slug interview-is-the-difference --root "$h" "$work/plan.md" >/dev/null 2>&1 \
  && err "refused plan exited 0" || true
[ "$(find "$a/plans" -type f | wc -l)" -eq "$before" ] \
  && ok "fail-closed: a refused plan writes nothing" || err "refused plan still wrote"

# --- Schema-less destination fallback -------------------------------------
n="$work/notarepo"; mkdir -p "$n/out"       # no drafts/, no INDEX.md/backlog/
h2="$work/host2"; mkdir -p "$h2"; git -C "$h2" init -q
python3 "$root/scripts/resolve-writing-sources.py" --root "$h2" \
  set-draft-location "$n/out/" >/dev/null 2>&1
d=$(python3 "$W" dest --slug interview-is-the-difference --root "$h2" 2>/dev/null)
printf '%s' "$d" | grep -q '"conforming": false' \
  && ok "fallback: a schema-less destination is not treated as an articles repo" \
  || err "schema-less destination reported conforming: $d"
good
out=$(python3 "$W" write --slug interview-is-the-difference --root "$h2" "$work/plan.md" 2>/dev/null) \
  && ok "fallback: the plan is still written (association intact)" || err "fallback write failed"
printf '%s' "$out" | grep -q "$work/state" \
  && ok "fallback: lands in user-scoped state (keyed by repo + slug)" \
  || err "fallback did not land in user-scoped state: $out"
[ ! -d "$n/out/plans" ] && [ ! -d "$n/plans" ] \
  && ok "fallback: no plans/ directory created in the non-conforming destination" \
  || err "a plans/ dir was created in the non-conforming destination"

# --- Vocabulary + spec + skill wiring -------------------------------------
grep -q 'article-plan' "$SPEC" && ok "spec names the artifact 'article plan'" || err "spec vocabulary"
grep -rqi 'skeleton' "$W" && err "'skeleton' appears in the writer" \
  || ok "vocabulary: 'skeleton' appears nowhere in the writer"
DSKILL="skills/draft-article/SKILL.md"
grep -q 'write-article-plan.py' "$DSKILL" \
  && ok "draft-article skill emits the article plan at completion" \
  || err "draft-article skill does not wire in the plan writer"
grep -qi 'no new owner interaction\|no new owner interaction' "$DSKILL" \
  && ok "skill states the plan needs no new owner interaction (CAP-1)" \
  || err "skill missing the no-interaction guarantee"

# --- CAP-3: read-only plan consultation at draft start (Story 13.57) --------
# The good plan from CAP-1 is already written at $a/plans/. Consultation reads
# it back read-only and returns its discovery surface.
good
python3 "$W" write --slug interview-is-the-difference --root "$h" "$work/plan.md" >/dev/null 2>&1
pre_snapshot=$(find "$a" -type f | sort; git -C "$a" status --porcelain)
c=$(python3 "$W" consult --root "$h" 2>/dev/null)
printf '%s' "$c" | grep -q '"slug": "interview-is-the-difference"' \
  && ok "CAP-3: consult reads existing plans and returns their discovery surface" \
  || err "consult did not surface the existing plan: $c"
printf '%s' "$c" | grep -q '"claim": "the interview is the difference' \
  && ok "CAP-3: consult carries the plan's claim (proposal-grounding surface)" \
  || err "consult missing the claim surface"
post_snapshot=$(find "$a" -type f | sort; git -C "$a" status --porcelain)
[ "$pre_snapshot" = "$post_snapshot" ] \
  && ok "CAP-3: consultation is read-only — nothing created or modified" \
  || err "consultation modified the articles repo"

# Degrade silently: no plans/ directory -> empty list with a reason, no failure.
a2="$work/articles2"; mkdir -p "$a2/drafts" "$a2/backlog"; : > "$a2/INDEX.md"
git -C "$a2" init -q      # a conforming articles repo that simply has no plans yet
h3="$work/host3"; mkdir -p "$h3"; git -C "$h3" init -q
python3 "$root/scripts/resolve-writing-sources.py" --root "$h3" \
  set-draft-location "$a2/drafts/" >/dev/null 2>&1
c=$(python3 "$W" consult --root "$h3" 2>/dev/null) \
  && ok "CAP-3: consult on a repo with no plans exits 0 (never a failure)" \
  || err "consult failed on a repo with no plans"
printf '%s' "$c" | grep -q '"plans": \[\]' && printf '%s' "$c" | grep -qi 'no plans' \
  && ok "CAP-3: no plans -> empty list with a reason (silent degrade)" \
  || err "consult did not degrade silently: $c"
[ ! -d "$a2/plans" ] && ok "CAP-3: consultation created no plans/ directory" \
  || err "consultation created a plans/ dir"

# Schema-less destination -> degrade silently too.
c=$(python3 "$W" consult --root "$h2" 2>/dev/null) \
  && printf '%s' "$c" | grep -q '"plans": \[\]' \
  && ok "CAP-3: schema-less destination degrades to today's behavior" \
  || err "consult did not degrade on a schema-less destination: $c"

# The skill documents consultation as read-only, proposal-shaped, none auto-applied.
grep -q 'write-article-plan.py consult' "$DSKILL" \
  && ok "CAP-3: draft skill wires in plan consultation" || err "skill missing consult wiring"
grep -qi 'none auto-applied\|never applies a prior plan' "$DSKILL" \
  && ok "CAP-3: skill states no plan is auto-applied" || err "skill missing the no-auto-apply rule"
grep -qi 'no residue' "$DSKILL" \
  && ok "CAP-3: skill states a declined proposal leaves no residue" || err "skill missing no-residue rule"

if [ "$fail" -eq 0 ]; then
  printf '\nAll article-plan checks passed.\n'; exit 0
else
  printf '\narticle-plan checks FAILED.\n' >&2; exit 1
fi
