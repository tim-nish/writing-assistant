"""Sitting-bounded automatic resume (Story 20.104, #1082).

Extracted from `draft-pipeline.py` at introduction rather than after growth:
that file sits exactly on its declared line ratchet, whose remedy names
shrinking the file and forbids raising the number to absorb growth. This is a
relocation — the reasoning below travels with the code it explains, never
compacted — and it follows the `terrain_*.py` precedent for helper modules
beside their caller.

WHAT THIS BOUNDS, and what it deliberately does not touch. #142 ratified that
resumption is automatic and not opt-in, so a turn-ceiling casualty is
recoverable rather than a total loss, and a large draft completing across
several invocations is the normal model. That purpose is retained whole. What
failed is the reach of the phrase "an in-progress run": the run adopted in the
reported incident had been halted FOURTEEN DAYS, and stage 0 attached to it
with no announcement and no confirmation. Across a gap that is stale-state
adoption — the class *proposals carry the state they were computed against*
exists to prevent, arriving in its worst form, because a resumed workspace
carries no pin to mismatch on at all.
"""

import datetime


def run_id_started(run_id):
    """When a run began, from its own id.

    Run ids are timestamps by construction — `YYYYmmddTHHMMSS-uuuuuu` — so the
    start time is RECORDED rather than inferred. Returns None for an id that
    does not parse, and the caller then states the age as unknown rather than
    assuming one.
    """
    head = str(run_id or "").split("-")[0]
    try:
        return datetime.datetime.strptime(head, "%Y%m%dT%H%M%S")
    except ValueError:
        return None


def predates_sitting(run_id, state, sitting, now=None):
    """Does this resumable run belong to the CURRENT sitting?

    Returns `(predates, why)` — `predates` True when the run must not be
    adopted silently.

    THE PRECISE ANSWER IS DECLARED, because nothing recorded identifies a
    sitting: a checkpoint carries `next_stage`, `stage`, framework and sources,
    and no session id or timestamp of its own (measured 2026-07-31, across the
    checkpoints on this machine). So when the caller declares a sitting the
    recorded value is compared and the answer is exact — the same shape the
    judge pin uses, the fact supplied at the boundary that holds it.

    THE FALLBACK IS A STATED RULE OVER RECORDED DATA, never a tuned threshold:
    a run that STARTED ON A DIFFERENT CALENDAR DAY than now did not begin in
    this sitting. The day boundary is not a knob to be adjusted toward a better
    number; it is the coarsest honest reading of the only temporal fact
    recorded. The fourteen-day case fires on it, and a draft continuing across
    several invocations the same day does not — which is #142's normal
    completion model and must keep working.

    An unparseable run id is CANNOT-DETERMINE and is treated as predating:
    disclosure costs a confirmation, and silent adoption of stale state is what
    this exists to prevent.
    """
    recorded = (state or {}).get("sitting")
    if sitting and recorded:
        if str(recorded) == str(sitting):
            return False, "same sitting (declared and recorded)"
        return True, (f"a different sitting: this run recorded {recorded!r}, "
                      f"the current invocation declares {sitting!r}")
    started = run_id_started(run_id)
    if started is None:
        return True, ("the run id does not parse as a timestamp, so its "
                      "sitting cannot be determined")
    now = now or datetime.datetime.now()
    if started.date() == now.date():
        return False, "started today (no sitting was declared; day-boundary rule)"
    days = (now.date() - started.date()).days
    return True, (f"started {days} day(s) ago, on {started.date()} — a "
                  "different calendar day, so not this sitting (no sitting was "
                  "declared; day-boundary rule)")


def confirmation(run_id, ws, state, why):
    """The run is NOT adopted; the caller is handed the question instead.

    Nothing attaches to this workspace until the answer comes back, which is
    the whole correction: the incident's failure was not a wrong choice but a
    choice nobody was offered.

    Emitted as a QUESTION PAYLOAD rather than prose (#1081). The observed
    failure was that nobody noticed, and a notice composed into chat is exactly
    the layer that failed — so the options travel as data and the rendering
    step quotes them.
    """
    started = run_id_started(run_id)
    return {
        "resumed": False,
        "resume_requires_confirmation": True,
        "candidate_run_id": run_id,
        "candidate_ws": ws,
        "candidate_next_stage": state.get("next_stage"),
        "started": started.isoformat() if started else None,
        "why": why,
        "question": {
            "ask": (f"Resume run {run_id}? It {why}, and stops at "
                    f"`{state.get('next_stage')}`."),
            "options": [
                {"label": "resume it",
                 "effect": "continue that run from its checkpoint; nothing is "
                           "re-done"},
                {"label": "start fresh",
                 "effect": "mint a new run; that one is left untouched and "
                           "stays resumable (pass --fresh)"},
            ],
            "free_text": "or say what you want instead",
        },
    }


def disclosure_line(run_id, ws, state):
    """One line naming what a resumed run IS (Story 19.10, #746): id, age, and
    subject from checkpointed state — so a topic mismatch (tanuki F86: a
    tutorial invocation adopting a q_a-gateway run) is visible at turn one."""
    age = ""
    try:
        ts = datetime.datetime.strptime(run_id.split("-")[0], "%Y%m%dT%H%M%S")
        mins = int((datetime.datetime.now() - ts).total_seconds() // 60)
        age = f", started {mins // 60}h{mins % 60:02d}m ago" if mins >= 60 else f", started {mins}m ago"
    except (ValueError, IndexError):
        pass
    rs = state.get("run_state") or state
    bits = []
    if rs.get("framework"):
        bits.append(f"framework {rs['framework']}")
    ent = (rs.get("entry") or {}).get("request") or rs.get("element")
    if ent:
        bits.append(f"entry {str(ent)[:60]!r}")
    srcs = rs.get("sources_raw") or [s.get("value") for s in rs.get("sources", []) if isinstance(s, dict)]
    if srcs:
        bits.append(f"sources {', '.join(map(str, srcs))[:60]}")
    subject = "; ".join(bits) or "subject unrecorded in checkpoint"
    return (f"resuming run {run_id}{age} — {subject}; stage {state.get('next_stage')}. "
            f"Not your topic? re-run with --fresh (this run stays untouched).")
