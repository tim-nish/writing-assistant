#!/usr/bin/env sh
# check-review-diff.sh — verify review's owner-facing before/after comparison and
# the pre-review checkpoint proposal (Story 18.25, #495; SPEC-article-review
# CAP-6). Alt A: the review presents the before/after diff + applied change list
# IN-CONVERSATION (interaction contract #226; the run-workspace pre-arbitration
# snapshot underlies it), and at review start, if the canonical draft is
# UNTRACKED or DIRTY in its destination repo, surfaces a one-line CHECKPOINT
# PROPOSAL (owner commits the pre-review state; the pipeline NEVER writes the
# destination repo — footprint invariant). Declining is allowed; the diff still
# shows this run's edits. POSIX shell + stdlib Python.

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
grep -q 'draft-pipeline.py review-checkpoint-proposal' "$SKILL" \
  && ok "SKILL invokes the review-checkpoint-proposal subcommand at review start" \
  || err "review-checkpoint-proposal not wired into the SKILL"
grep -q 'draft-pipeline.py review-diff' "$SKILL" \
  && ok "SKILL invokes the review-diff subcommand at report time" \
  || err "review-diff not wired into the SKILL"
grep -qi 'before/after' "$SKILL" \
  && ok "SKILL names the before/after comparison" || err "before/after comparison unnamed in the SKILL"
grep -qi 'checkpoint proposal' "$SKILL" \
  && ok "SKILL names the checkpoint proposal" || err "checkpoint proposal unnamed in the SKILL"
grep -qiE 'untracked or dirty|untracked/dirty' "$SKILL" \
  && ok "SKILL keys the proposal on an untracked/dirty destination draft" \
  || err "untracked/dirty trigger missing from the SKILL"
grep -qi 'in-conversation' "$SKILL" \
  && ok "SKILL states the diff is presented in-conversation" \
  || err "in-conversation presentation note missing"
grep -q '#226' "$SKILL" \
  && ok "SKILL cites interaction contract #226" || err "interaction contract #226 not cited"
grep -qi 'never writes the destination' "$SKILL" \
  && ok "SKILL states the pipeline never writes the destination repo" \
  || err "destination-repo footprint note missing from the SKILL"
grep -qi 'declin' "$SKILL" \
  && ok "SKILL states declining the checkpoint is allowed" \
  || err "declinable note missing from the SKILL"
grep -qi 'pre-arbitration' "$SKILL" \
  && ok "SKILL keeps the pre-arbitration snapshot in the run workspace" \
  || err "pre-arbitration snapshot note missing from the SKILL"

# --- Fixture: a destination (articles) repo with an UNTRACKED draft ----------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
a="$work/articles"; mkdir -p "$a/drafts"; git -C "$a" init -q
git -C "$a" config user.email t@e.st
git -C "$a" config user.name test
: > "$a/INDEX.md"
git -C "$a" add INDEX.md && git -C "$a" commit -qm init

slug=retry-storms
draft="$a/drafts/$slug.md"
cat > "$draft" <<'EOF'
---
slug: retry-storms
---

The retry storm tripled load before the breaker fired.
The team shipped the fix on a Friday.
EOF

dstate() { git -C "$a" status --porcelain; }
before_status=$(dstate)

# --- (a) UNTRACKED draft → a checkpoint proposal is surfaced -----------------
out=$(python3 "$DP" review-checkpoint-proposal --draft "$draft" --slug "$slug") \
  && ok "review-checkpoint-proposal succeeds on an untracked draft" \
  || err "review-checkpoint-proposal failed on the untracked path"
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['stage']=='review-checkpoint-proposal', d
assert d['tracked_state']=='untracked', d
assert d['checkpoint_proposed'] is True, d
assert d['proposal'], d
assert 'git' in d['proposal'] and 'commit' in d['proposal'], d
assert d['writes_destination_repo'] is False, d
assert d['declinable'] is True, d
" && ok "untracked draft: one-line checkpoint proposal, pipeline writes nothing, declinable" \
  || err "untracked-draft proposal JSON shape wrong"

# The proposal step MUST NOT write the destination repo (footprint invariant).
[ "$(dstate)" = "$before_status" ] \
  && ok "review-checkpoint-proposal left the destination repo git status unchanged" \
  || { err "review-checkpoint-proposal dirtied the destination repo:"; dstate >&2; }

# --- (a') DIRTY (tracked-but-modified) draft → still proposes ----------------
git -C "$a" add "drafts/$slug.md" && git -C "$a" commit -qm "add draft"
printf 'An extra edited line.\n' >> "$draft"
out=$(python3 "$DP" review-checkpoint-proposal --draft "$draft" --slug "$slug")
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['tracked_state']=='dirty', d
assert d['checkpoint_proposed'] is True, d
" && ok "dirty (tracked-but-modified) draft also surfaces the checkpoint proposal" \
  || err "dirty-draft proposal JSON shape wrong"

# --- (a'') CLEAN (committed, unmodified) draft → NO proposal ----------------
git -C "$a" checkout -- "drafts/$slug.md"
out=$(python3 "$DP" review-checkpoint-proposal --draft "$draft" --slug "$slug")
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['tracked_state']=='clean', d
assert d['checkpoint_proposed'] is False, d
assert d['proposal'] in (None,''), d
" && ok "clean committed draft surfaces NO checkpoint proposal" \
  || err "clean-draft branch wrong (proposal offered when git already has the pre-review state)"

# --- (b) before/after diff + change list, in-conversation --------------------
ws="$work/ws"; mkdir -p "$ws"
snap="$ws/pre-arbitration-$slug.md"          # the run-workspace snapshot (machine-state)
cp "$draft" "$snap"
# Apply this run's arbitration edit to the destination draft copy under review.
cat > "$draft" <<'EOF'
---
slug: retry-storms
---

The retry storm tripled load before the circuit breaker fired.
The team shipped the fix on a Friday.
EOF
out=$(python3 "$DP" review-diff --before "$snap" --after "$draft" --slug "$slug") \
  && ok "review-diff succeeds on an edited draft" || err "review-diff failed"
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['stage']=='review-diff', d
assert d['identical'] is False, d
assert d['added']>=1 and d['removed']>=1, d
assert d['diff'].strip(), 'diff text must be present for in-conversation display'
assert 'circuit breaker' in d['diff'], d
assert isinstance(d['change_list'], list) and len(d['change_list'])>=1, d
" && ok "before/after diff + non-empty change list produced for in-conversation display" \
  || err "review-diff JSON shape wrong"

# --- (b') identical before/after → no diff, empty change list ----------------
cp "$draft" "$ws/same.md"
out=$(python3 "$DP" review-diff --before "$ws/same.md" --after "$draft" --slug "$slug")
printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['identical'] is True, d
assert d['added']==0 and d['removed']==0, d
assert d['change_list']==[], d
" && ok "identical before/after reports no change (nothing to show)" \
  || err "identical-diff branch wrong"

# --- (c) footprint: neither subcommand writes into the destination repo ------
# The diff reads the workspace snapshot and the draft; it must not create a
# reviews/ artifact or any other file in the destination (articles) repo.
git -C "$a" checkout -- "drafts/$slug.md" 2>/dev/null || true
[ ! -d "$a/reviews" ] \
  && ok "no reviews/ (or any diff) artifact written into the destination repo" \
  || err "a review artifact leaked into the destination repo (footprint breach)"
new=$(git -C "$a" status --porcelain --untracked-files=all | grep -v "drafts/$slug.md" || true)
[ -z "$new" ] \
  && ok "destination repo carries no new plugin-authored files after review-diff" \
  || { err "review-diff leaked files into the destination repo:"; printf '%s\n' "$new" >&2; }

if [ "$fail" -eq 0 ]; then
  printf '\nAll review-diff checks passed.\n'; exit 0
else
  printf '\nreview-diff checks FAILED.\n' >&2; exit 1
fi
