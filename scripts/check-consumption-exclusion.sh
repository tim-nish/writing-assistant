#!/usr/bin/env sh
# check-consumption-exclusion.sh — verify CAP-9 consumption exclusion (#430):
# consumed story-element ids recorded in the article plan (no new store), and
# the consult-time `consumed_index` view regenerated from plans/*.md that a new
# lesson-based selection defaults away from (Story 18.9, depends 18.8).
# POSIX shell + stdlib Python only.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

W="scripts/write-article-plan.py"
SKILL="skills/draft-article/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$W', doraise=True)" 2>/dev/null \
  && ok "writer compiles" || { err "writer syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

# Host source repo + a conforming articles repo (drafts/ + INDEX.md + backlog/).
h="$work/host"; mkdir -p "$h"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts" "$a/backlog" "$a/plans"; git -C "$a" init -q
: > "$a/INDEX.md"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  set-draft-location "$a/drafts/" >/dev/null 2>&1

sha=a1b2c3d4e5f6a7b8

# A plan carrying a `consumed:` list of two story-element ids.
plan_with_consumed() {
cat > "$work/plan.md" <<EOF
---
kind: article-plan
slug: $1
intent: share engineering lessons
claim: structured discovery paid off
status: drafted
run_id: 20260720T090000-000001
pin: host@$sha
consumed: [$2]
---

## Section plan

- the retry-storm lesson / host/log.txt:12@$sha
EOF
}

V() { python3 "$W" validate --path "plans/$1.md" "$work/plan.md" >/dev/null 2>&1; }
reason() { python3 "$W" validate --path "plans/$1.md" "$work/plan.md" 2>&1; }

# --- 1. a well-formed consumed list validates -----------------------------------
plan_with_consumed one "lesson:retry-storm, lesson:token-budget"
V one && ok "consumed: a well-formed story-element id list validates" \
  || err "well-formed consumed list refused: $(reason one)"

# --- 2. a malformed id is refused (never prose / never a pointer set) ------------
plan_with_consumed two "lesson:retry-storm, host/log.txt:12@$sha"
V two && err "consumed accepted a pointer as an element id (should refuse)" \
  || ok "consumed refuses a pointer masquerading as an element id"
reason two | grep -q 'malformed story-element id' \
  && ok "consumed: the refusal names the malformed id" \
  || err "malformed-id refusal message missing"

plan_with_consumed three "has space"
V three && err "consumed accepted an id with whitespace" \
  || ok "consumed refuses a whitespace-bearing (prose-like) id"

# --- 3. duplicate ids are refused (consumption is a set) ------------------------
plan_with_consumed four "lesson:dup, lesson:dup"
V four && err "consumed accepted a duplicate id" \
  || ok "consumed refuses duplicate ids (a set keyed by id)"
reason four | grep -qi 'duplicate' && ok "duplicate refusal is named" \
  || err "duplicate refusal message missing"

# --- 4. consult regenerates consumed_index across plans/*.md --------------------
plan_with_consumed a-story "lesson:retry-storm, lesson:token-budget"
cp "$work/plan.md" "$a/plans/a-story.md"
plan_with_consumed b-story "lesson:cache-warmth"
cp "$work/plan.md" "$a/plans/b-story.md"

python3 "$W" consult --root "$h" > "$work/consult.json" 2>/dev/null
python3 - "$work/consult.json" <<'PYEOF' && ok "consult returns a consumed_index aggregating every plan's consumed ids" || err "consumed_index wrong"
import json, sys
d = json.load(open(sys.argv[1]))
idx = d.get("consumed_index")
assert isinstance(idx, dict), d
assert set(idx) == {"lesson:retry-storm", "lesson:token-budget", "lesson:cache-warmth"}, idx
assert idx["lesson:retry-storm"] == ["a-story"], idx
assert idx["lesson:cache-warmth"] == ["b-story"], idx
# each plan's own summary carries its consumed list
byslug = {p["slug"]: p for p in d["plans"]}
assert byslug["a-story"]["consumed"] == ["lesson:retry-storm", "lesson:token-budget"], byslug["a-story"]
PYEOF

# --- 5. the index is a REGENERATED view: delete a plan, it vanishes; no ledger ---
rm "$a/plans/b-story.md"
python3 "$W" consult --root "$h" > "$work/consult2.json" 2>/dev/null
python3 - "$work/consult2.json" <<'PYEOF' && ok "consumed_index is regenerated from plans (a removed plan drops out; no stored ledger)" || err "index did not regenerate after a plan was removed"
import json, sys
idx = json.load(open(sys.argv[1]))["consumed_index"]
assert "lesson:cache-warmth" not in idx, idx
PYEOF
# No second store was written anywhere in the articles repo.
[ ! -e "$a/.consumed" ] && [ ! -e "$a/plans/.index" ] && [ ! -e "$a/consumed-index.json" ] \
  && ok "no second consumption store is created (C1: the plans ARE the record)" \
  || err "a second consumption store appeared"

# --- 6. SKILL states the CAP-9/#430 consumption contract ------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qi 'default' && printf '%s' "$S" | grep -qi 'unconsumed' \
  && ok "SKILL: lesson-based selection defaults to unconsumed elements" \
  || err "SKILL missing the default-to-unconsumed rule"
printf '%s' "$S" | grep -qi 'no new store' \
  && ok "SKILL: consumption is recorded in the plan, no new store (C1)" \
  || err "SKILL missing the no-new-store invariant"
printf '%s' "$S" | grep -qi 'consumed_index' \
  && ok "SKILL: exclusion reads the regenerated consumed_index view" \
  || err "SKILL missing the consumed_index wiring"
printf '%s' "$S" | grep -qi 'survives re-harvest' \
  && ok "SKILL: consumption keyed by id survives re-harvest drift" \
  || err "SKILL missing the survives-re-harvest property"
printf '%s' "$S" | grep -qiE 'owner may re-cover|owner-overridable|re-cover a consumed' \
  && ok "SKILL: the default is owner-overridable (re-cover a consumed element)" \
  || err "SKILL missing the owner override"

if [ "$fail" -eq 0 ]; then
  printf '\nAll consumption-exclusion checks passed.\n'; exit 0
else
  printf '\nconsumption-exclusion checks FAILED.\n' >&2; exit 1
fi
