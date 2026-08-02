#!/usr/bin/env python3
"""Stop hook: a gate that was due leaves tool-call evidence, or the turn is
blocked (Story 20.151, #1221).

WHY THIS EXISTS AT THIS LAYER, WHICH IS THE WHOLE POINT.
`specs/spec-writing-assistant/SPEC.md:76` recorded on 2026-07-28 that the
failing layer is "the agent's own composition step, WHICH THIS PRODUCT DOES NOT
OWN", and concluded that the carrier must stop at the composed artifact. The
premise nobody checked was the factual one: no `.claude/settings.json` existed
in this repository, so that conclusion described a harness with no observation
point. It is a file this repository owns and commits. The amendment of
2026-08-02 (#1221/#1222/#1225) bounds the ruling on exactly that ground, and
this file is the carrier it licenses.

Twelve issues (#226 -> #1206) shipped carriers that each bound a layer UPSTREAM
of the one that fails. Every one of them passed while the owner read prose.
This one runs outside the model.

WHAT IT ASSERTS — AN ABSENCE, AND NOTHING ELSE.
For a turn at which a declared gate was due, an `AskUserQuestion` tool-use
event exists in the transcript for that gate. That is it. It does not read
reply prose, does not classify text, and does not judge wording — those are
the payload layer's job (stories 20.152, 20.153) and the relay limit #1176
records still stands. What this removes is the last way to reach the owner
without leaving evidence.

THREE-VALUED, BY OWNER DECISION 2026-08-02.
The harness writes the transcript asynchronously and its docs say the file
"may lag the in-memory conversation". Blocking is expensive — it holds the
owner's turn open — so a read that raced the writer must never block. If the
transcript has not caught up, this reports CANNOT-DETERMINE and lets the turn
end. It fails toward silence, never toward a wrong block.

The cost is stated rather than hidden: coverage is "settled turns", not "all
turns", and the thing to watch is the cannot-determine RATE. A rising rate
means the evidence is being missed, and it is visible in the transcript output
rather than inferred from a suspiciously clean pass rate.

EXIT CODES ARE THE HARNESS'S, NOT OURS. Exit 2 blocks the turn and feeds
stderr back to the model; exit 0 lets it end. Anything this hook cannot do
safely exits 0 — a hook that crashes must not take the session with it.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
INVENTORY = os.path.join(HERE, "..", "gate-inventory.py")


def _run_workspace(payload):
    """The run workspace this turn belongs to, or None.

    Resolved from the environment the pipeline already sets, never guessed by
    scanning for the newest directory: picking "the most recent workspace"
    would silently audit a different run than the one that is speaking, and a
    wrong-run block is indistinguishable at the owner's screen from a real one.
    """
    ws = os.environ.get("WA_RUN_WS") or payload.get("cwd_run_ws")
    if ws and os.path.isdir(ws):
        return ws
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        # No parseable hook input: assert nothing, block nothing.
        return 0

    ws = _run_workspace(payload)
    if not ws:
        # Not a pipeline turn at all — the overwhelming majority. Silence here
        # is correct: this hook has no subject, which is different from having
        # a subject and finding it clean.
        return 0

    cmd = [sys.executable, INVENTORY, "--audit", "--ws", ws,
           "--reached-from-state"]
    transcript = payload.get("transcript_path")
    if transcript:
        cmd += ["--transcript", transcript]
        marker = payload.get("last_assistant_message")
        if marker:
            # Opaque settledness token only — see gate-inventory.read_tool_calls.
            cmd += ["--settle-marker", marker]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        # The auditor could not run. That is a cannot-determine, not a finding.
        return 0

    if proc.returncode == 0:
        return 0

    # A real finding. stderr goes back to the model as the reason it may not
    # stop, naming the gate so the next turn can present it through the
    # control rather than narrating it again.
    sys.stderr.write(
        "A declared gate was due this turn and no AskUserQuestion tool call "
        "carries it, so the ask reached the owner as prose.\n"
        "Present it through the selection control, quoting its emitted "
        "payload.\n\n" + (proc.stderr or proc.stdout or "").strip() + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
