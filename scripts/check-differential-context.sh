#!/usr/bin/env sh
# check-differential-context.sh — verify the differential-context prior-coverage
# digest (Story 18.23, #504): when prior published/drafted articles share the
# project (related.projects), the argument plan receives a prior-coverage digest
# (slugs + summaries + their Context/warning spans) so Stage 3 can compress-and-
# link repeated context instead of re-explaining it. Built on the existing
# carriers (plans/*.md + continuation-mode canonical reads); the prior body
# never enters harvest evidence; no prior article sharing the project -> no
# digest (unchanged behavior). POSIX shell + stdlib Python only.

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

# A prior plan pinned to a source repo (the project proxy) + its canonical draft.
prior() { # slug project claim
cat > "$a/plans/$1.md" <<EOF
---
kind: article-plan
slug: $1
intent: share engineering lessons
claim: $3
status: drafted
run_id: 20260720T090000-000001
pin: $2@$sha
---

## Section plan

- the lesson / host/log.txt:12@$sha
EOF
}

canonical() { # slug
cat > "$a/drafts/$1.md" <<EOF
---
slug: $1
title: A $1 article
summary: $1 explains what Tanuki is and how retries storm.
language: en
---

## Context

Tanuki is a loop-driving harness. This section introduces the terms and the
project so a reader new to it can follow along.

## The lesson

> [!WARNING]
> Do not trust the loop's self-reported success without an independent judge.

Body prose here.
EOF
}

# Two prior articles share the "tanuki" project; one belongs to another project.
prior tanuki-one   tanuki      "structured discovery paid off"
canonical tanuki-one
prior tanuki-two   tanuki      "the retry storm taught batching"
canonical tanuki-two
prior other-proj   product-lab "unrelated project lesson"
canonical other-proj

DC() { python3 "$W" differential-context --root "$h" --project "$1"; }

# --- 1. the digest carries every prior article sharing the project --------------
DC tanuki > "$work/dc.json" 2>/dev/null \
  || err "differential-context command failed"
python3 - "$work/dc.json" <<'PYEOF' && ok "digest lists the prior articles sharing the project (slugs + summaries)" || err "digest membership wrong"
import json, sys
d = json.load(open(sys.argv[1]))
cov = d.get("prior_coverage")
assert isinstance(cov, list), d
slugs = {e["slug"] for e in cov}
assert slugs == {"tanuki-one", "tanuki-two"}, slugs
byslug = {e["slug"]: e for e in cov}
# summary comes from the canonical frontmatter (framing context, like continuation mode)
assert "explains what Tanuki is" in byslug["tanuki-one"]["summary"], byslug["tanuki-one"]
PYEOF

# --- 2. the digest carries Context and warning spans ----------------------------
python3 - "$work/dc.json" <<'PYEOF' && ok "digest carries the Context span and the warning span (compress-and-link material)" || err "context/warning spans missing"
import json, sys
d = json.load(open(sys.argv[1]))
e = {x["slug"]: x for x in d["prior_coverage"]}["tanuki-one"]
assert e.get("context_span") and "introduces the terms" in e["context_span"], e.get("context_span")
warns = e.get("warnings")
assert isinstance(warns, list) and any("independent judge" in w for w in warns), warns
PYEOF

# --- 3. an article from a DIFFERENT project is excluded --------------------------
python3 - "$work/dc.json" <<'PYEOF' && ok "an article from another project is excluded from the digest" || err "cross-project article leaked into the digest"
import json, sys
d = json.load(open(sys.argv[1]))
slugs = {e["slug"] for e in d["prior_coverage"]}
assert "other-proj" not in slugs, slugs
PYEOF

# --- 4. no prior article sharing the project -> empty digest (unchanged behavior)-
DC lonely-project > "$work/dc2.json" 2>/dev/null
python3 - "$work/dc2.json" <<'PYEOF' && ok "no prior article sharing the project -> empty digest (no re-introduction machinery kicks in)" || err "empty-project case not empty"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["prior_coverage"] == [], d
PYEOF

# --- 5. the command is read-only: it writes nothing to the articles repo --------
before=$(cd "$a" && git status --porcelain; find "$a" -type f | sort)
DC tanuki >/dev/null 2>&1
after=$(cd "$a" && git status --porcelain; find "$a" -type f | sort)
[ "$before" = "$after" ] \
  && ok "differential-context writes nothing (read-only, like plan consultation)" \
  || err "the command created or modified files in the articles repo"

# --- 6. a schema-less destination degrades silently -----------------------------
hbare="$work/host-bare"; mkdir -p "$hbare"; git -C "$hbare" init -q
python3 "$W" differential-context --root "$hbare" --project x > "$work/dc3.json" 2>/dev/null \
  && python3 - "$work/dc3.json" <<'PYEOF' && ok "no articles-repo schema -> empty digest + a degraded reason (never a failure)" || err "schema-less destination did not degrade cleanly"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["prior_coverage"] == [] and d.get("degraded"), d
PYEOF

# --- 7. SKILL states the differential-context contract --------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qi 'differential context' \
  && ok "SKILL names differential context" || err "SKILL missing the differential-context section"
printf '%s' "$S" | grep -qi 'prior-coverage digest' \
  && ok "SKILL: the argument plan receives a prior-coverage digest" \
  || err "SKILL missing the prior-coverage digest wiring"
printf '%s' "$S" | grep -qi 'compress-and-link' \
  && ok "SKILL: Stage 3 treats repeated context as compress-and-link (recap + pointer)" \
  || err "SKILL missing the compress-and-link rule"
printf '%s' "$S" | grep -qiE 'related.projects|share the project|shares the project' \
  && ok "SKILL: the digest is built for prior articles sharing the project" \
  || err "SKILL missing the shared-project trigger"
printf '%s' "$S" | grep -qiE 'load-bearing' \
  && ok "SKILL: a warning repeats only when load-bearing for THIS article's claim" \
  || err "SKILL missing the load-bearing-warning rule"
printf '%s' "$S" | grep -qiE 'never enters (the )?harvest|body never enters' \
  && ok "SKILL: the prior body never enters the harvest evidence stream (13.56 fences hold)" \
  || err "SKILL missing the harvest-fence invariant"
printf '%s' "$S" | grep -qiE 'no prior article|no digest|unchanged' \
  && ok "SKILL: no prior article sharing the project -> unchanged behavior" \
  || err "SKILL missing the no-prior-unchanged clause"

if [ "$fail" -eq 0 ]; then
  printf '\nAll differential-context checks passed.\n'; exit 0
else
  printf '\ndifferential-context checks FAILED.\n' >&2; exit 1
fi
