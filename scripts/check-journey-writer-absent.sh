#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-08-01 (#1183) — this check reads the repository and
# writes nothing at all: no temp dir, no config home, no state root, no host
# tree. It greps tracked files and imports nothing. Two concurrent instances
# collide with nothing.
# tier: inner — pure greps over tracked text; no subprocess, no fixture, no seam
# covers: scripts/terrain_*.py scripts/resolve-writing-sources.py skills/terrain/**
# removal-signal: retire this when the plugin can no longer address a host
# repository's working tree at all — i.e. when every host-side path it composes
# is resolver-owned and outside the tree by construction, so an absence-of-
# writer assertion for one named file has nothing left to add.
#
# check-journey-writer-absent.sh — assert the ABSENCE OF A WRITER for
# `docs/journey.md` in the host repository (Story 20.134, #1183;
# SPEC-writing-assistant, the Host-repo footprint invariant, amended
# 2026-08-01).
#
# WHY AN ABSENCE-OF-WRITER ASSERTION, AND NOT A FILE-ABSENCE TEST. A test that
# `docs/journey.md` does not exist passes on every clean checkout and fails only
# after the harm has already landed in someone's tree — and it cannot even run
# against the host repo the plugin was pointed at. What the amendment retires is
# the CODE PATH: the gap step's file-append branch and the host-repo episode
# join that fed it. So the assertion is over this repository's own text, in the
# shape check-footprint-invariant.sh already uses for the destination write
# surface: no script composes that path to write it, and no skill instructs a
# write of it. The prohibition is carried by there being nothing that can do it,
# never by a rule someone must remember.
#
# SCOPE. This check asserts the absence of a WRITER, not the absence of the
# STRING: a tombstone comment explaining what was removed is exactly the record
# this repository wants to keep, so the patterns below name write ACTS.

set -eu
cd "$(dirname "$0")/.."

fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'err:  %s\n' "$1" >&2; fail=1; }

SRC="scripts skills"

# --- 1. no code path OPENS a journey path for writing ------------------------
# A writer in this codebase looks like `open(<path>, "w"|"a")`, a shell
# redirect, or a resolver-composed path handed to one. Any of those within a
# line naming a journey document is the mechanism returning.
if grep -rnE '(open\([^)]*journey[^)]*,[[:space:]]*["'"'"']?[wa]|>>?[[:space:]]*[^ ]*journey\.md|write_text\([^)]*journey)' \
     $SRC 2>/dev/null; then
  err "a code path writes a journey document — the writer is retired (#1183)"
else
  ok "no script opens, appends to, or redirects into a journey document (#1183)"
fi

# --- 2. no skill INSTRUCTS a write of one ------------------------------------
# Prose is advisory at the tool boundary, which is why the writer had to go;
# but an instruction to write it would be an agent composing the write by hand,
# which the removal of the code path does not by itself prevent.
if grep -rniE '(append|write|create|add)[^.]{0,60}(to|into|in)?[^.]{0,20}(docs/)?journey\.md' \
     skills 2>/dev/null; then
  err "a skill instructs a write into a journey document (#1183)"
else
  ok "no skill instructs a write into a journey document (#1183)"
fi

# --- 3. the retired mechanism has no definitions left ------------------------
# The join, its config key and the recording payload it minted are removed, not
# merely unreferenced: a definition left behind is a writer one call away.
# Scoped to the IMPLEMENTATION and its fixtures — the checks themselves name
# these keys to assert their absence, which is the opposite of emitting one.
IMPL="scripts/*.py scripts/fixtures skills"
for pat in '^def get_journey' '^def journey_join' '^def _recording_form' \
           '"needs_recording"' '"recording_target"'; do
  # shellcheck disable=SC2086
  if grep -rnE "$pat" $IMPL 2>/dev/null; then
    err "the retired mechanism is still defined or emitted: $pat (#1183)"
  else
    ok "retired and gone: $pat"
  fi
done

# --- 4. the config key that named the write target is gone -------------------
# `journey:` in writing-sources.yaml was the only declaration that could name a
# target file for the append. With no reader, a declaration is inert — and a
# reader is what this asserts against.
# shellcheck disable=SC2086
if grep -rnE 'add_parser\("journey"|"journey": cmd_journey|JOURNEY_MALFORMED[[:space:]]*=' \
     scripts/*.py 2>/dev/null; then
  err "the retired journey: config key still has a reader (#1183)"
else
  ok "the journey: config key has no reader anywhere (#1183)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll journey-writer-absence checks passed.\n'; exit 0
else
  printf '\njourney-writer-absence checks FAILED.\n' >&2; exit 1
fi
