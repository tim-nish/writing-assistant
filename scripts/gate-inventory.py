#!/usr/bin/env python3
"""A run's gate inventory, audited against what it actually emitted
(Story 20.119, #1114/#1122).

WHY THIS EXISTS AFTER THE SITTING. Story 20.118 constrains what this repository
COMPOSES — a gate surface is composed only through the declared registry, so
every code-path gate leaves an ask row. What it cannot constrain is the agent's
own rendering step, which #1102 records as a layer this repository does not own.
So the residue is DETECTED: a gate the run reached with no matching row in
`presented-payloads.jsonl` becomes a defect anyone can find later, rather than
an obligation nobody can check.

WHY THE LEFT-HAND SIDE IS PASSED IN. `reached` is what the run actually got to,
which the log cannot supply — a log missing a row is precisely the case being
audited, so deriving "reached" from the log would make the check vacuous by
construction. The caller (the sitting, or a fixture) names what it reached; the
registry validates that those ids exist at all.

WHAT THIS AUDIT DOES NOT COVER — STATED, BECAUSE A CLEAN AUDIT OTHERWISE READS
AS A CLEAN CLASS (Story 20.136, #1176). This is coverage of DECLARED-ID
EMISSION. It compares the ids a caller says it reached against the ask rows the
run wrote, and both sides are keyed on `draft_gates.GATES` — so an owner-facing
ask that was never declared there is invisible to it, and a run that composed
one still audits clean. That is not a gap to be closed by a better predicate:
the sentence above is the reason. `reached` is supplied by the caller because
deriving it from the log would make the check vacuous, which means the actor
that failed to declare a gate is the actor that reports which gates it reached
— the self-assertion shape already declined upstream as "self-asserted by the
same actor class that made the original error". No mechanical carrier is
possible at the agent's composition step, so THE STATED LIMIT IS THE REMEDY
(`specs/spec-writing-assistant/amendments-2026-07-24--2026-08-01.md`,
2026-08-01 #1176/#1177, clause (a)). Reopen trigger: a harness-level signal
that fires when a turn ends awaiting a reply.

No spec, skill or check may cite this audit as evidence of gate coverage
without that bound.

HARNESS-LAYER ENFORCEMENT (Story 20.142, #1206). The above stated limit is now
partially closable at the harness layer via Claude Code hooks, which run outside
the model and can observe both the tool-call stream and the reply text. The
extended audit (--tool-call-audit) checks interview-events.jsonl for
AskUserQuestion tool-call evidence, not merely payload file presence. A gate is
`presented` only when an AskUserQuestion tool-use event for its payload exists
in the transcript. This closes the gap observed in run 20260802T090323-217675
where payloads for q8 and depth were emitted but no selection event was recorded.
"""

import argparse
import importlib.util
import json
import os
import sys


def _gates():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "draft_gates", os.path.join(here, "draft_gates.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.declared_gates()


def read_asks(ws):
    """The ask rows a run wrote. A missing log is an EMPTY run, not an error —
    the audit's whole job is to report what is absent."""
    path = os.path.join(ws, "presented-payloads.jsonl")
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def read_tool_call_events(ws):
    """Read interview-events.jsonl and return gate ids that have AskUserQuestion
    tool-call evidence. A gate is truly presented only when the tool-call exists
    in the transcript, not merely when a payload file was written.

    This closes the gap documented in run 20260802T090323-217675: payloads for
    q8 and depth were emitted but no AskUserQuestion tool call was recorded —
    only t1/t2 had one. Payload file presence and tool-call evidence diverge
    precisely in the failure mode this class tracks.
    """
    path = os.path.join(ws, "interview-events.jsonl")
    tool_call_gate_ids = set()
    if not os.path.isfile(path):
        return tool_call_gate_ids
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            # Accept any event shape that records an AskUserQuestion tool call
            # with a gate_id or payload gate_id field.
            event_type = event.get("type") or event.get("event_type") or ""
            tool_name = event.get("tool") or event.get("tool_name") or event.get("tool_use", {}).get("name", "")
            if "AskUserQuestion" in str(tool_name):
                # Extract gate id from the event
                gate_id = (
                    event.get("gate_id")
                    or event.get("id")
                    or (event.get("input") or {}).get("gate_id")
                    or (event.get("tool_use", {}).get("input") or {}).get("gate_id")
                    or (event.get("payload") or {}).get("gate_id")
                )
                if gate_id:
                    tool_call_gate_ids.add(gate_id)
            # Also accept selection events as evidence (a selection implies the
            # question was presented through the tool-call path)
            if "selection" in str(event_type).lower() or "selected" in str(event_type).lower():
                gate_id = event.get("gate_id") or event.get("id")
                if gate_id:
                    tool_call_gate_ids.add(gate_id)
    return tool_call_gate_ids


def read_next_stage(ws):
    """Read the current next_stage from the run workspace if available.
    Used by the hook audit to determine which gate was due at turn end."""
    path = os.path.join(ws, "next_stage")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return f.read().strip() or None


def check_intent_gate_capacity(gates):
    """Verify the intent gate is reachable by the question UI.

    The #1102 capacity clause (host control = 2-4 options) made control: "block"
    the only conforming form for a 5-label intent gate, locking the pipeline's
    first and most central closed choice out of the question UI by spec (#1206).
    A >4-option closed choice must degrade to a two-step selection (or
    4 options + "more..."), never to prose block form.

    Returns a list of violation strings (empty = no violations).
    """
    violations = []
    for gate_id, gate in gates.items():
        options = gate.get("options") or gate.get("choices") or []
        control = gate.get("control", "")
        capacity = gate.get("capacity")
        max_options = None
        if capacity:
            # Parse "2-4" style capacity bounds
            if isinstance(capacity, str) and "-" in capacity:
                try:
                    parts = capacity.split("-")
                    max_options = int(parts[-1])
                except (ValueError, IndexError):
                    pass
            elif isinstance(capacity, int):
                max_options = capacity
        if max_options is not None and len(options) > max_options:
            if str(control).lower() == "block":
                violations.append(
                    f"gate {gate_id!r}: {len(options)} options exceeds capacity "
                    f"max {max_options}; control=block makes this gate unreachable "
                    f"by the question UI — must degrade to two-step or 4+more form"
                )
    return violations


def audit(ws, reached, tool_call_audit=False, check_capacity=False):
    """Return (missing, unknown, tool_call_gaps, capacity_violations).

    missing: gate ids in `reached` with no payload row in presented-payloads.jsonl
    unknown: gate ids in `reached` not in the declared registry
    tool_call_gaps: gate ids in `reached` with payload rows but no AskUserQuestion
                    tool-call evidence in interview-events.jsonl (only when
                    tool_call_audit=True)
    capacity_violations: gates whose option count exceeds UI capacity (only when
                         check_capacity=True)
    """
    gates = _gates()
    asks = read_asks(ws)
    emitted_ids = {row.get("gate_id") or row.get("id") for row in asks} - {None}

    unknown = [r for r in reached if r not in gates]
    missing = [r for r in reached if r in gates and r not in emitted_ids]

    tool_call_gaps = []
    if tool_call_audit:
        tool_call_ids = read_tool_call_events(ws)
        # A gap is a gate that emitted a payload but has no tool-call evidence:
        # the payload existed (so the old check passed) but the question UI was
        # never actually invoked