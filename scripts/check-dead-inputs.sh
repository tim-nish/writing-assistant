#!/usr/bin/env sh
# parallel-safe
# tier: inner — a static enumeration over the suite and the hook chain, no
#   pipeline execution; runs in well under a second
# covers: scripts/check-* scripts/hooks/* scripts/gate-inventory.py scripts/turn_budget.py scripts/dead-input-inventory.py
# removal-signal: check inputs become DECLARED at the member (a `# reads:`
#   header the runner enforces, the same declare-once-in-the-check shape as
#   `# tier:`), at which point an undeclared input is unrepresentable and this
#   repo-wide extraction pass is redundant; or the suite stops being a
#   budgeted family in specs/spec-writing-assistant/SPEC.md.
#
# check-dead-inputs.sh — the writerless-input invariant (Story 20.159,
# #1245/#1254; amendments.md clause (6)).
#
# ONE MEMBER, NOT A FAMILY — deliberately, and this line is the contract. The
# check suite grew at roughly one member per incident, which the served
# position names as the checkable tell of being on the wrong side of the
# constrain/detect line. This invariant exists to END that pattern for the
# dead-input class: a NEW check reading an input nothing writes fails HERE,
# so no future incident in this class mints a new checker. Do not add a
# sibling check for a new input kind — extend the inventory's extraction and
# keep the one member.
#
# WHAT FAILS: any suite member or runtime-chain file reading an environment
# variable, harness payload field, or run-workspace artifact that has NO
# writer — not in this repository, not in the documented harness schema, not
# on any owner-reachable doc surface. `WA_RUN_WS`, `cwd_run_ws` and
# `gates_reached` were exactly this, and the checks reading them stayed green
# for thirteen cycles because the only writer was a fixture.
#
# THE ENUMERATION IS RECOMPUTED EVERY RUN, never read from a stored report —
# a committed inventory would drift from the suite, which is the
# fixture-that-lied defect one level up. dead-input-inventory.py is the data
# source and this check is its only failing consumer.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if python3 "$ROOT/scripts/dead-input-inventory.py" --fail-on-dead --dead-only; then
  echo
  echo "dead-input invariant holds: every enumerated check input has a writer."
else
  echo >&2
  echo "dead-input checks FAILED: an input with no writer marks its reader" >&2
  echo "dead on arrival — remove the reader or give the input a real writer;" >&2
  echo "a comment saying it cannot fire does not discharge this (clause (6))." >&2
  exit 1
fi
