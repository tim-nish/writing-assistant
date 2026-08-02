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


def candidate_state(run_dir, checkpoint_file):
    """The resume-scan's per-run-dir predicate: the state to consider, or None.

    It lives here rather than inline in the scan because it is a resume
    SEMANTIC — what counts as a run worth resuming — and because
    `draft-pipeline.py` is at its size ratchet, where the sanctioned remedy is
    moving code to the module that owns it, never raising the ceiling.

    CHECKPOINT-LESS BUT NOT EMPTY (Story 20.111, #1119). A run that captured an
    owner answer before it could checkpoint is the one workspace a later
    sitting must NOT walk past: it holds a record of what the owner said, and
    skipping it mints a second workspace while the answers sit in the first.
    That is the observed knock-on — one run captured the intent ask, was
    invisible to this scan, and the retry minted a second workspace with the
    ask log copied across by hand.

    The ask log is the evidence, so it is the predicate. Such a run resumes at
    the START: no checkpoint means no stage has declared itself complete, and
    claiming otherwise would be inventing progress from a file that records
    questions.
    """
    import json
    import os
    cp = os.path.join(run_dir, checkpoint_file)
    if not os.path.isfile(cp):
        if not os.path.isfile(os.path.join(run_dir, "presented-payloads.jsonl")):
            return None
        return {"next_stage": "stage0", "checkpoint_absent": True}
    try:
        with open(cp, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def brief_mismatch(state, brief):
    """Same-brief-only on a brief-carrying entry (amended 2026-08-02, #1207).

    True when the entry carries a brief and the candidate run's checkpoint
    records a different one — or none. Identity is `draft_brief.brief_pin`,
    the recorded artifact, never text similarity: the terrain handoff arrives
    holding a just-adopted brief, and auto-resuming a run minted from any
    other brief discards the sitting's own output in favor of stale state. A
    cold entry (no brief) never mismatches, so the ratified cold default —
    automatic, not opt-in — is untouched.
    """
    if not brief:
        return False
    import os
    import sys
    sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
    import draft_brief
    return (draft_brief.brief_pin((state or {}).get("brief"))
            != draft_brief.brief_pin(brief))


def fresh_note(run_id, other_brief):
    """The skip's one-line receipt. Both branches say what is KEPT: skipping
    is `--fresh`'s semantics — by owner keystroke, or by brief data (#1207) —
    and nothing is deleted on either."""
    if other_brief:
        return (f"same-brief-only (#1207): minted a new run; in-progress run "
                f"{run_id} was minted from a different brief and left "
                "untouched (resumable later; nothing deleted)")
    return (f"--fresh: minted a new run; in-progress run {run_id} "
            "left untouched (resumable later; nothing deleted)")


def confirmation(run_id, ws, state, why):
    """The run is NOT adopted; the caller is handed the question instead.

    Nothing attaches to this workspace until the answer comes back, which is
    the whole correction: the incident's failure was not a wrong choice but a
    choice nobody was offered.

    THE SHAPE IS THE SHIPPED ONE (Story 20.103, #1081). This first emitted its
    own `ask`/`options`/`free_text` object — which worked, was checked, and was
    a SECOND payload vocabulary in a codebase whose open defect is precisely
    that gates lack one carrier. It now builds through `draft_gates.payload`,
    so it passes the same validator every other proposal surface passes.
    """
    import importlib.util
    import os
    spec = importlib.util.spec_from_file_location(
        "draft_gates", os.path.join(os.path.dirname(os.path.realpath(__file__)),
                                    "draft_gates.py"))
    dg = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dg)
    started = run_id_started(run_id)
    stage = state.get("next_stage")
    out = dg.payload(
        gate="resume-confirmation",
        where=f"Run {run_id} is already in progress and stopped part-way.",
        why=f"It {why}, so adopting it silently would resume another "
            f"sitting's work.",
        choices=[
            {"label": "resume it",
             "effect": "continue that run from its checkpoint; nothing is "
                       "re-done"},
            {"label": "start fresh",
             "effect": "mint a new run; that one is left untouched and stays "
                       "resumable"},
        ],
        # A GROUNDED RECOMMENDATION, not a default (Story 20.152, #1222).
        # This gate fires only ACROSS a sitting gap — #1082 bounded automatic
        # resume to the same sitting precisely because "across a gap it becomes
        # stale-state adoption". So the served reasoning that licenses
        # resume-by-default inside a sitting is the same reasoning that
        # recommends AGAINST it here, and the age this payload already carries
        # is the evidence. Nothing is pre-selected and the other option is a
        # full citizen; what would overturn it is the owner knowing the older
        # run's work is still wanted, which the machine cannot see.
        recommended=1,
    )
    out.update({
        "resumed": False,
        "resume_requires_confirmation": True,
        "candidate_run_id": run_id,
        "candidate_ws": ws,
        "candidate_next_stage": stage,
        "started": started.isoformat() if started else None,
        "age_days": _age_days(started),
        "why": why,
    })
    # THE ASK IS RECORDED WHERE IT CAN BE AUDITED (Story 20.111, #1119). The
    # contract states the candidate's id and AGE and confirms the resume
    # (SPEC-article-draft-pipeline amendments, #1082) — but a gate that only
    # prints has left no evidence it fired, which is the absence-shape #1081
    # names and #1114 makes checkable. `candidate_ws` is the only workspace in
    # existence at this point, so the record goes there.
    #
    # RECORDING IS NOT ADOPTING, and the distinction is the whole gate: an ask
    # row says a question was posed ABOUT that run. Nothing reads it back as
    # progress, and no checkpoint is written — stage 0 returns immediately on
    # this shape precisely so the run is not attached to.
    _emit_ask(ws, out)
    return out


def _age_days(started):
    """How old the candidate run is, in whole days — the quantity the
    sitting-boundary contract says to STATE, kept beside the timestamp rather
    than left for each caller to recompute (and disagree about)."""
    if started is None:
        return None
    import datetime
    return (datetime.datetime.now() - started).days


def _emit_ask(ws, out):
    """Append the gate's payload to the workspace's presented-payloads log.

    Best-effort by construction: a workspace that cannot be written is a
    degraded record, never a reason to swallow the owner's question. The gate
    firing matters more than its receipt, so a failure here is silent and the
    confirmation still returns.
    """
    import json
    import os
    try:
        with open(os.path.join(ws, "presented-payloads.jsonl"), "a",
                  encoding="utf-8") as f:
            f.write(json.dumps({"kind": "ask", "gate": "resume-confirmation",
                                "candidate_run_id": out["candidate_run_id"],
                                "age_days": out["age_days"],
                                "items": out["items"]},
                               ensure_ascii=False) + "\n")
    except OSError:
        pass


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
