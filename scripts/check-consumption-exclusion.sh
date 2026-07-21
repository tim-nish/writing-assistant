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

# --- 6. element-id derivation reproduces across runs (the stability guarantee) --
# Story 18.35/#529: ids are derived mechanically from the declared membership
# anchor, so two runs over the same anchor mint a BYTE-IDENTICAL id — the root
# cause of exclusion never firing (`el-weak-driver` vs `weak-driver`) is fixed.
python3 "$W" element-id "Weak driver" > "$work/id1.json" 2>/dev/null
python3 "$W" element-id "Weak driver" > "$work/id2.json" 2>/dev/null
cmp -s "$work/id1.json" "$work/id2.json" \
  && ok "element-id: two runs over the same anchor are byte-identical" \
  || err "element-id is not reproducible across runs"
python3 - "$W" <<'PYEOF' && ok "element-id: variant anchor spellings reconcile to one identity (#529)" || err "element-id normalization is wrong"
import json, subprocess, sys
W = sys.argv[1]
def eid(anchor):
    out = subprocess.run([sys.executable, W, "element-id", anchor],
                         capture_output=True, text=True).stdout
    return json.loads(out)["elements"][0]["id"]
# the exact #529 drift: bare label, slug, and already-derived id are ONE element.
assert eid("Weak driver") == eid("weak-driver") == eid("el-weak-driver") == "el-weak-driver", \
    (eid("Weak driver"), eid("weak-driver"), eid("el-weak-driver"))
# a different declared anchor is a different id (identity is the anchor).
assert eid("kill switch") == "el-kill-switch", eid("kill switch")
assert eid("Weak driver") != eid("kill switch")
# an anchor with no alphanumeric content is a defect, not a minted id.
bad = json.loads(subprocess.run([sys.executable, W, "element-id", "  --  "],
                                capture_output=True, text=True).stdout)["elements"][0]
assert bad["id"] is None and bad["ok"] is False, bad
PYEOF

# --- 7. project-scoped exclusion: a prior plan for the SAME project excludes -----
# Story 18.35/#529: exclusion detects a prior plan by PROJECT identity
# (_plan_project = the pin's repo component), not by pin sha or exact slug.
plan_pin() {  # slug pin consumed
cat > "$work/plan.md" <<EOF
---
kind: article-plan
slug: $1
intent: share engineering lessons
claim: a lesson worth recording
status: drafted
run_id: 20260721T090000-000001
pin: $2
consumed: [$3]
---

## Section plan

- the lesson / host/log.txt:12@$sha
EOF
}
rm -f "$a/plans/"*.md
# same project "host" (basename of $h), DIFFERENT pin sha than any run would use:
plan_pin prior-host "host@ffffffffffffffff" "el-weak-driver, el-kill-switch"
cp "$work/plan.md" "$a/plans/prior-host.md"
# a plan for a DIFFERENT project must NOT leak into this project's exclusion:
plan_pin other-proj "other@$sha" "el-should-not-appear"
cp "$work/plan.md" "$a/plans/other-proj.md"

python3 "$W" consult --root "$h" > "$work/consult3.json" 2>/dev/null
python3 - "$work/consult3.json" <<'PYEOF' && ok "consult: prior plan for THIS project (by _plan_project) supplies the exclusion ids; other project excluded" || err "project-scoped exclusion view wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["project"] == "host", d["project"]
assert d["scanned"] == "plans/*.md", d["scanned"]
pci = d["project_consumed_index"]
# same-project plan's consumed ids appear, keyed by id despite a different pin sha:
assert set(pci) == {"el-weak-driver", "el-kill-switch"}, pci
assert pci["el-weak-driver"] == ["prior-host"], pci
# the other-project plan's id is NOT in the project-scoped view:
assert "el-should-not-appear" not in pci, pci
assert d["project_plans"] == ["prior-host"], d["project_plans"]
PYEOF

# --- 8. the "first article on this project" path is only reachable with no plan --
rm -f "$a/plans/"*.md
# only a DIFFERENT project's plan exists -> for project "host" this is a first article.
plan_pin foreign "other@$sha" "el-x"
cp "$work/plan.md" "$a/plans/foreign.md"
python3 "$W" consult --root "$h" > "$work/consult4.json" 2>/dev/null
python3 - "$work/consult4.json" <<'PYEOF' && ok "first-article claim is reachable ONLY when no project-matching plan exists; names plans/*.md" || err "first-article detection wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["project_plans"] == [], d["project_plans"]          # -> claim emittable
assert d["project_consumed_index"] == {}, d["project_consumed_index"]
assert d["scanned"] == "plans/*.md", d["scanned"]            # claim names the location
PYEOF
# add a plan FOR this project -> the first-article claim is no longer reachable.
plan_pin now-host "host@$sha" "el-y"
cp "$work/plan.md" "$a/plans/now-host.md"
python3 "$W" consult --root "$h" > "$work/consult5.json" 2>/dev/null
python3 - "$work/consult5.json" <<'PYEOF' && ok "first-article claim is NOT reachable once a project plan exists" || err "first-article claim leaked with a project plan present"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["project_plans"] == ["now-host"], d["project_plans"]
PYEOF

# --- 9. the #529 scenario: two same-day tanuki plans, overlapping clusters -------
# The prior plan consumed [el-weak-driver, el-kill-switch]; the second run derives
# ids from the SAME declared anchors -> the same ids -> the overlap is excluded.
rm -f "$a/plans/"*.md
plan_pin tanuki-engineering-lessons "tanuki@1111111111111111" \
  "el-weak-driver, el-relocated-gate, el-host-snapshot, el-kill-switch"
cp "$work/plan.md" "$a/plans/tanuki-engineering-lessons.md"
python3 "$W" consult --root "$h" --project tanuki > "$work/consult6.json" 2>/dev/null
python3 - "$W" "$work/consult6.json" <<'PYEOF' && ok "#529: second tanuki run's anchors resolve to the prior ids and are excluded" || err "#529 scenario not excluded"
import json, subprocess, sys
W, path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
assert d["project"] == "tanuki", d["project"]
assert d["project_plans"] == ["tanuki-engineering-lessons"], d["project_plans"]
excluded = set(d["project_consumed_index"])
# the second run re-derives ids from the same declared anchors (the #529 drift set)
def eid(anchor):
    out = subprocess.run([sys.executable, W, "element-id", anchor],
                         capture_output=True, text=True).stdout
    return json.loads(out)["elements"][0]["id"]
# run-2 wrote these anchors freely last time ("weak-driver", "coverage-removal");
# now they are derived from the declared cluster labels:
run2 = {"weak driver": None, "kill switch": None}
for a in run2:
    run2[a] = eid(a)
# both overlapping clusters resolve to ids the prior plan already consumed:
assert run2["weak driver"] == "el-weak-driver" and run2["weak driver"] in excluded, (run2, excluded)
assert run2["kill switch"] == "el-kill-switch" and run2["kill switch"] in excluded, (run2, excluded)
PYEOF

# --- 10. SKILL states the CAP-9/#430 consumption contract -----------------------
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

# Story 18.35/#529: the mechanical id-derivation rule must be documented concretely.
printf '%s' "$S" | grep -qi 'element-id' \
  && printf '%s' "$S" | grep -qiE 'declared membership anchor|membership anchor' \
  && ok "SKILL: element ids are derived mechanically from the declared membership anchor" \
  || err "SKILL missing the mechanical element-id derivation rule"
printf '%s' "$S" | grep -qiE 'never free-choose|never a token you invent|free-chosen' \
  && ok "SKILL: forbids free-choosing the id token (the #529 root cause)" \
  || err "SKILL missing the no-free-choice-token rule"
# Project-scoped exclusion + evidenced first-article claim.
printf '%s' "$S" | grep -qi 'project_consumed_index' \
  && ok "SKILL: exclusion reads the PROJECT-scoped consumed view" \
  || err "SKILL missing the project_consumed_index wiring"
printf '%s' "$S" | grep -qi 'first article on this project' \
  && printf '%s' "$S" | grep -qi 'project_plans' \
  && ok "SKILL: first-article claim gated on empty project_plans" \
  || err "SKILL missing the project-scoped first-article gating"
printf '%s' "$S" | grep -qi 'names the scanned location' \
  && printf '%s' "$S" | grep -qi 'plans/\*.md' \
  && ok "SKILL: the first-article claim names the scanned location (plans/*.md)" \
  || err "SKILL missing the scanned-location naming"

# The completion summary discloses skipped-because-consumed elements + names plans/*.md.
SUM=$(norm "skills/completion-summary.md")
printf '%s' "$SUM" | grep -qiE 'skipped because a prior article|elements skipped' \
  && ok "completion summary discloses which elements were skipped and why (CAP-9)" \
  || err "completion summary missing the skipped-element disclosure"
printf '%s' "$SUM" | grep -qi 'first article on this project' \
  && printf '%s' "$SUM" | grep -qi 'plans/\*.md' \
  && ok "completion summary: first-article claim is project-scoped and names plans/*.md" \
  || err "completion summary missing the project-scoped first-article claim"

if [ "$fail" -eq 0 ]; then
  printf '\nAll consumption-exclusion checks passed.\n'; exit 0
else
  printf '\nconsumption-exclusion checks FAILED.\n' >&2; exit 1
fi
