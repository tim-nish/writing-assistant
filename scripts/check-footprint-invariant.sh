#!/usr/bin/env sh
# check-footprint-invariant.sh — verify the host-repo footprint invariant is
# enforced end-to-end (Story 9.3). POSIX shell + stdlib Python only.
#
# The invariant (docs/storage-architecture.md D1): the plugin never writes
# state or intermediate artifacts into a host repo's working tree — the only
# files it creates there are declared products at output.drafts.
#
# Covers:
#  - AC1/AC2 (mechanical): against a clean host git repo, the resolver's run
#    workspace lands OUTSIDE the tree, and creating it + writing intermediates
#    leaves `git status` in the host repo empty — no scratch, no stray file.
#  - AC1 (contract): all three run-producing skills (harvest, draft-article,
#    review-article) declare the footprint invariant and route intermediates
#    through the resolver workspace, never the host tree.
#  - Destination-repo write surface (Story 18.44, #550): the `output.drafts`
#    DESTINATION repo — which the lint and footprint check name explicitly,
#    never "host repo" — receives exactly the two GATED products plus one
#    regenerated NON-GATING view (INDEX.md), and nothing else. Story 18.43
#    added that third file with zero destination coverage here, so the surface
#    was unbounded; a stray write is now detected and named, and the view's
#    non-gating asymmetry is asserted so it cannot drift into a gate.
#  - AC3 (as amended by #211/13.23): writing-sources.yaml is machine-global —
#    resolve-paths.py owns its placement, no script composes the per-repo
#    config path itself, and no doc points owners at the host root.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RES="scripts/resolve-paths.py"
PY="python3 $root/$RES"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# --- Isolated fake state root + clean host git repo -----------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_STATE_HOME="$work/state"
HOST="$work/host-repo"; mkdir -p "$HOST"
git -C "$HOST" init -q
git -C "$HOST" config user.email t@e.st
git -C "$HOST" config user.name test
: > "$HOST/README.md"
git -C "$HOST" add -A && git -C "$HOST" commit -qm init

clean() { [ -z "$(git -C "$HOST" status --porcelain)" ]; }

clean && ok "host repo starts clean" || err "host repo not clean at start"

# 1. The run workspace lands OUTSIDE the host tree (AC1/AC2 mechanical).
ws=$(cd "$HOST" && $PY new-run --root "$HOST")
case "$ws" in
  "$HOST"/*) err "run workspace is INSIDE the host tree ($ws)" ;;
  *) ok "run workspace is outside the host tree" ;;
esac
case "$ws" in
  "$XDG_STATE_HOME"/*) ok "run workspace is under the state root" ;;
  *) err "run workspace not under the state root ($ws)" ;;
esac

# 2. Creating the workspace left the host tree clean (AC2: git status empty).
clean && ok "host git status clean after new-run" || {
  err "new-run dirtied the host tree:"; git -C "$HOST" status --porcelain >&2;
}

# 3. Writing intermediates into the workspace still leaves the host tree clean.
printf '# fact sheet\n' > "$ws/fact-sheet.md"
printf 'scratch\n'     > "$ws/scratch.txt"
clean && ok "host tree clean after intermediates written to the workspace" || {
  err "intermediates leaked into the host tree:"; git -C "$HOST" status --porcelain >&2;
}

# 4. Contract: each run-producing skill declares the footprint invariant and
#    routes intermediates through the resolver workspace (AC1 surface).
#    topic-map joined this set in Story 18.71 (#611). It was absent while it
#    already wrote intermediates, and the omission is exactly what went
#    unnoticed: the skill used `$WS` six times and never minted it, so its
#    files landed wherever the caller's shell pointed. A run-producing skill
#    missing from this list is unguarded, so the list must grow with them.
for f in skills/harvest/SKILL.md skills/draft-article/SKILL.md \
         skills/review-article/SKILL.md skills/topic-map/SKILL.md; do
  if grep -q 'resolve-paths.py' "$f" \
     && grep -qiE 'output\.drafts|host (working )?tree|host repo' "$f" \
     && grep -qi 'workspace' "$f"; then
    ok "footprint contract stated in $f"
  else
    err "footprint contract missing/incomplete in $f"
  fi
  # A skill that WRITES to "$WS/..." must also SAY WHERE $WS COMES FROM
  # (Story 18.71, #611). The check above only greps for `resolve-paths.py`
  # anywhere in the file, which topic-map satisfied with an unrelated
  # `resolve-paths.py target` call while never minting a workspace — so the
  # contract read as stated while the intermediates went to the caller's
  # scratchpad. Either mint it (`new-run`) or document receiving it from the
  # pipeline's Stage 0; using it unexplained is the defect.
  if grep -q '\$WS/' "$f"; then
    if grep -q 'resolve-paths.py new-run' "$f" \
       || grep -qE "\\\$WS.*(Stage 0|stage 0|passes its run workspace)" "$f"; then
      ok "\$WS is minted or explicitly received in $f"
    else
      err "$f writes to \$WS but never mints it (resolve-paths.py new-run) nor documents receiving it"
    fi
  fi
done

# 5. AC3 (amended by Story 13.23, #211 — storage O1 resolved): writing-sources.yaml
#    is machine-global per-repo config, and the RESOLVER owns its placement.
#    5a. plugin-layout documents the machine-global location, not a host-root file.
if grep -q 'repos/<repo-key>/' specs/spec-writing-assistant/plugin-layout.md \
   && ! grep -q '<host-repo>/writing-sources.yaml' specs/spec-writing-assistant/plugin-layout.md; then
  ok "plugin-layout documents machine-global writing-sources.yaml (no host-root contract)"
else
  err "plugin-layout does not document the machine-global writing-sources.yaml contract (#211)"
fi
#    5b. storage-architecture records O1 as resolved.
if grep -q 'Resolved 2026-07-15 (#211)' docs/storage-architecture.md; then
  ok "storage-architecture records the O1 resolution"
else
  err "storage-architecture O1 resolution record is missing (#211)"
fi
#    5c. the resolver is the single owner of writing-sources placement.
if grep -q 'def sources_file' scripts/resolve-paths.py; then
  ok "resolver owns writing-sources.yaml placement (sources_file)"
else
  err "resolve-paths.py does not own writing-sources placement (#211 expects sources_file)"
fi
#    5d. Story 13.25: no production script composes the per-repo config-root
#        layout itself — the `repos/<repo-key>` segment under the config home is
#        resolve-paths.py's alone. (Docs/skills may NAME the location for
#        humans; composing it in code is the violation. check-*.sh fixtures
#        assert resolver behavior and are excluded.)
offenders=$(grep -RnoI 'writing-assistant/repos\|"repos"' scripts/*.py 2>/dev/null \
  | grep -v '^scripts/resolve-paths.py:' || true)
if [ -z "$offenders" ]; then
  ok "single-source: no script outside resolve-paths.py composes the per-repo config path"
else
  err "per-repo config path composed outside the resolver:"
  printf '%s\n' "$offenders" >&2
fi
#    5e. Issue #218: README never claims writing-sources.yaml lives in the host
#        repo. The 13.25 text sweep caught the skills but missed README's
#        at-a-glance config table ("Lives at | host repo root"), which led a
#        reader to commit the config into a host repo the same day. Guard the
#        stale claim pattern; the legacy-migration note ("A legacy in-repo
#        writing-sources.yaml is still read…") is allowed — it names the old
#        location as deprecated, not as the place to put the file.
stale=$(grep -n 'host repo root\|host-repo root' README.md || true)
if [ -z "$stale" ]; then
  ok "README makes no host-repo-root placement claim for writing-sources.yaml (#218)"
else
  err "README still claims a host-repo-root location (#218):"
  printf '%s\n' "$stale" >&2
fi

# --- Destination-repo write surface (Story 18.44, #550) ----------------------
# Everything above bounds the HOST SOURCE repo. The `output.drafts` DESTINATION
# repo had zero coverage — which is how Story 18.43 added a third file there
# (INDEX.md) without the two-product invariant noticing. The permitted surface
# is now named exhaustively (SPEC-writing-assistant, 2026-07-22 #550): the two
# GATED products plus exactly one regenerated NON-GATING view. Assert it against
# a real `complete` run, so a write outside the set fails here and is named.
DEST="$work/articles"; mkdir -p "$DEST/drafts"
git -C "$DEST" init -q
git -C "$DEST" config user.email t@e.st
git -C "$DEST" config user.name test
printf '# INDEX\n\nRegenerated — one line per backlog/draft/newsletter item.\n\n_Empty._\n' > "$DEST/INDEX.md"
git -C "$DEST" add -A && git -C "$DEST" commit -qm scaffold
python3 "$root/scripts/resolve-writing-sources.py" --root "$HOST" \
  set-draft-location "$DEST/drafts/" >/dev/null 2>&1
dslug=footprint-probe
wsd="$work/ws-dest"; mkdir -p "$wsd"
cat > "$wsd/draft.md" <<EOF
---
slug: $dslug
title: "A probe draft"
language: en
audience: en-practitioner
audience_id: en-practitioner
---

## Hook

A probe body line.
EOF
cat > "$work/plan-dest.md" <<EOF
---
kind: article-plan
slug: $dslug
intent: probe
claim: probe claim
status: drafted
run_id: 20260722T000000-000000
pin: host@a1b2c3d4e5f6a7b8
---

## Section plan

- probe / README.md:1@a1b2c3d4e5f6a7b8
EOF
python3 "$root/scripts/write-article-plan.py" write --slug "$dslug" --root "$HOST" \
  "$work/plan-dest.md" >/dev/null 2>&1 \
  && ok "destination fixture: plan written" || err "destination fixture plan write failed"
python3 "$root/scripts/draft-pipeline.py" complete --draft "$wsd/draft.md" --slug "$dslug" \
  --root "$HOST" --ws "$wsd" >/dev/null 2>&1 \
  && ok "destination fixture: complete succeeded" || err "destination fixture complete failed"

# The write surface, exhaustively: the two products + the one regenerated view.
dsurface() { git -C "$DEST" status --porcelain -uall | awk '{print $2}' | sort | tr '\n' ' '; }
expected="INDEX.md drafts/$dslug.md plans/$dslug.md "
actual=$(dsurface)
[ "$actual" = "$expected" ] \
  && ok "destination surface is exactly the 2 gated products + the INDEX view" \
  || err "destination write surface unexpected: got [$actual], expected [$expected]"

# Not vacuous: a write outside the declared set is detected and NAMED.
: > "$DEST/stray-artifact.md"
stray=$(dsurface)
if [ "$stray" != "$expected" ] && printf '%s' "$stray" | grep -q 'stray-artifact.md'; then
  ok "destination: a write outside the declared set is detected and named"
else
  err "a stray destination write went undetected: [$stray]"
fi
rm -f "$DEST/stray-artifact.md"

# --- The topic-map View: the SECOND regenerated non-gating view (18.72, #611) --
# D1's destination surface grew from three files to four. The View is the only
# artifact the topic-map flow puts in the destination repo, it is fixed (not
# per-run), and it must leave the tree CLEAN — a regenerated debug artifact that
# shows up as untracked would hand the owner a dirty repo on every invocation.
vpath=$(python3 "$root/scripts/resolve-paths.py" topic-map-view --root "$HOST")
case "$vpath" in
  "$DEST"/*) ok "View resolves inside the output.drafts destination repo" ;;
  *) err "View resolved outside the destination repo ($vpath)" ;;
esac
vpath2=$(python3 "$root/scripts/resolve-paths.py" topic-map-view --root "$HOST")
[ "$vpath" = "$vpath2" ] \
  && ok "View path is FIXED across invocations (not per-run)" \
  || err "View path changed between invocations: [$vpath] vs [$vpath2]"
case "$vpath" in
  */runs/*) err "View path still points into a per-run workspace ($vpath)" ;;
  *) ok "View path is not a per-run workspace path" ;;
esac
printf '# probe view\n' > "$vpath"
after=$(dsurface)
[ "$after" = "$expected" ] \
  && ok "writing the View leaves the destination tree clean (self-ignoring dir)" \
  || err "the View dirtied the destination tree: got [$after], expected [$expected]"
# Not vacuous: the guard is the tool-owned ignore, not luck.
[ -f "$(dirname "$vpath")/.gitignore" ] \
  && ok "the View's directory carries its own ignore rule" \
  || err "the View's directory has no .gitignore; the destination tree will go dirty"
# The View is never read back — CAP-1's derived-never-stored property, at the
# same strength it held when the file lived in a run workspace.
if grep -nE '(open|read_text|json\.load|cat)[^)]*VIEW_FILENAME' \
     "$root/scripts/topic-map-directions.py" >/dev/null 2>&1; then
  err "topic-map-directions.py appears to READ the View back"
else
  ok "no code path reads the View back (write-only, CAP-1)"
fi
rm -rf "$DEST/topic-map"
rm -f "$DEST/stray-artifact.md"

# INDEX is NON-GATING: its failure leaves the run complete, with a warning —
# the asymmetry that keeps a view from being promoted into a gate (or a gated
# product from being quietly demoted into a view).
# Fail ONLY the index write: make the destination ROOT unwritable (INDEX.md
# lives there) while drafts/ and plans/ stay writable, so the two products still
# persist. INDEX.md itself must remain a regular file — `write-article-plan.py`
# keys the articles-repo layout on `isfile(INDEX.md)`, so replacing it with a
# directory would perturb plan RESOLUTION rather than the index write.
if [ "$(id -u)" -ne 0 ]; then
  # The index must be STALE, or regeneration is an idempotent no-op that never
  # attempts a write (and so could never fail).
  printf '# INDEX\n\nRegenerated — one line per backlog/draft/newsletter item.\n\n_Empty._\n' > "$DEST/INDEX.md"
  chmod a-w "$DEST"
  set +e
  iout=$(python3 "$root/scripts/draft-pipeline.py" complete --draft "$wsd/draft.md" \
         --slug "$dslug" --root "$HOST" --ws "$wsd" 2>/dev/null)
  irc=$?
  set -e
  chmod u+w "$DEST"
  if [ "$irc" -eq 0 ] && printf '%s' "$iout" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['next_stage'] == 'done', d
assert (d.get('index') or {}).get('warning'), d.get('index')
" 2>/dev/null; then
    ok "destination: a failed INDEX write is a disclosed warning, run still completes"
  else
    err "INDEX write failure changed completion — the view must stay non-gating"
  fi
else
  ok "destination: non-gating INDEX check skipped (running as root; chmod is a no-op)"
fi

# The host SOURCE repo is still untouched by all of the above.
clean && ok "host source repo still clean after destination writes" \
  || { err "a destination-bound run dirtied the host source repo:";
       git -C "$HOST" status --porcelain >&2; }

# --- A test-declared run never writes to a destination it does not own (#573) -
# `output.drafts` is machine-wide but reads at the call site like a per-run
# value. The predicate is the DESTINATION, not the invocation shape (corrected
# at the 2026-07-22 re-triage): a destination inside the run's own disposable
# tree resolves normally, which is what keeps the #213 --create-out consent path
# testable. The guard lives at the ONE chokepoint both writers call.
DP="$root/scripts/draft-pipeline.py"
# variants needs a resolvable platform profile for the configured `en` variant;
# seed it the same way the destination fixture above seeds output.drafts.
tppdir="$(python3 "$root/scripts/resolve-paths.py" repo-config-dir --root "$HOST")/platform-profiles"
mkdir -p "$tppdir"
cp "$root/config/platform-profiles/devto.example.yaml" "$tppdir/devto.yaml"
tdraft="$work/td.md"
cat > "$tdraft" <<'EOF'
---
slug: test-declared-probe
title: "A probe"
date: 2026-07-22
mode: canonical
language: en
audience: en-practitioner
audience_id: en-practitioner
summary: A short summary.
topics: [probes]
---
# Body

A claim.
EOF

# 1. Destination OUTSIDE the temp tree: refused, names what it refused, writes
#    nothing there. $HOME is the stand-in for the owner's real articles repo —
#    the actual #573 leak destination class. Nothing is ever written to it: the
#    assertion is that the run aborts BEFORE any write.
outside="$HOME/.writing-assistant-check-573"
python3 "$root/scripts/resolve-writing-sources.py" --root "$HOST" \
  set-draft-location "$outside" >/dev/null 2>&1
tout=$(python3 "$DP" variants "$tdraft" --allow-external-draft --root "$HOST" \
         --platforms devto 2>&1) && trc=0 || trc=$?
if [ "${trc:-0}" -ne 0 ] \
   && printf '%s' "$tout" | grep -q 'refusing the configured output.drafts' \
   && printf '%s' "$tout" | grep -q "$outside"; then
  ok "test-declared run refuses a destination outside the temp tree, naming it"
else
  err "outside-tmp destination was not refused/named: $tout"
fi
[ ! -e "$outside" ] && ok "the refusal created nothing at that destination" \
  || { err "the refused destination was created at $outside"; rm -rf "$outside"; }

# 2. Destination INSIDE the temp tree resolves normally — this is the case
#    check-stage5-variants.sh check 6 (#213 --create-out consent) depends on,
#    and the reason the first formulation of this clause was withdrawn.
python3 "$root/scripts/resolve-writing-sources.py" --root "$HOST" \
  set-draft-location "$DEST/drafts/" >/dev/null 2>&1
if python3 "$DP" variants "$tdraft" --allow-external-draft --root "$HOST" \
     --platforms devto >/dev/null 2>&1 \
   && [ -f "$DEST/drafts/test-declared-probe.devto.md" ]; then
  ok "test-declared run resolves a destination inside the temp tree normally"
else
  err "an in-temp destination was refused; the #213 consent path stays testable"
fi

# 3. An explicit --out is honoured regardless.
mkdir -p "$work/tout-dir"
python3 "$DP" variants "$tdraft" --allow-external-draft --root "$HOST" \
  --out "$work/tout-dir" --platforms devto >/dev/null 2>&1 \
  && [ -f "$work/tout-dir/test-declared-probe.devto.md" ] \
  && ok "test-declared run with an explicit --out writes under --out" \
  || err "--out given but no variant written there"

# 4. An ORDINARY run (no test marker) is untouched by the guard: it resolves a
#    destination outside the temp tree exactly as before.
python3 "$root/scripts/resolve-writing-sources.py" --root "$HOST" \
  set-draft-location "$outside" >/dev/null 2>&1
mkdir -p "$outside"
cp "$tdraft" "$outside/test-declared-probe.md"
if python3 "$DP" variants "$outside/test-declared-probe.md" --root "$HOST" \
     --platforms devto >/dev/null 2>&1; then
  ok "ordinary run still resolves an out-of-temp destination (guard is test-only)"
else
  err "the guard changed ordinary-run behaviour"
fi
rm -rf "$outside"

# 5. The #213 consent harness passes UNMODIFIED — the mechanical proof that the
#    withdrawn predicate's regression cannot recur.
if sh "$root/scripts/check-stage5-variants.sh" >/dev/null 2>&1; then
  ok "check-stage5-variants.sh passes unmodified (#213 consent path intact)"
else
  err "check-stage5-variants.sh regressed: $(sh "$root/scripts/check-stage5-variants.sh" 2>&1 | grep FAIL | head -3)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll footprint-invariant checks passed.\n'; exit 0
else
  printf '\nfootprint-invariant checks FAILED.\n' >&2; exit 1
fi
