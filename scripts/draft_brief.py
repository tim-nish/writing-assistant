#!/usr/bin/env python3
"""draft_brief — resolving the stage-0 coverage brief INPUT (Story 20.91,
#1044).

Extracted from `draft-pipeline.py` per the packaging invariant's scripts-family
clause (`specs/spec-writing-assistant/SPEC.md`, amended 2026-07-29, #914) and
the #1025 amendment's importable-sibling shape: the hyphenated dispatcher keeps
its name and argparse, and composition moves into siblings like this one. The
review, policy-classification and variants COMMAND families moved first; this
is smaller and is not a command family — it is the `--brief` input contract,
which grew a second accepted shape here and had nowhere to grow inside a host
already at its line ratchet.

**The CLI surface is the invariant, and nothing here touches it.** `_read_brief`
is re-exported under its original name, so the dispatcher, `_run_state` and any
check reaching it as a module attribute are untouched. This is a MOVE plus the
new record path — `_read_brief`'s text/file behaviour is byte-identical for the
same inputs.
"""

import json
import os

# --- The brief RECORD as a stage-0 input (Story 20.91, #1044) ----------------
# A `--brief` FILE may be a JSON **brief record**: an object carrying the brief
# string under `brief`, and optionally the selected Strands it was composed
# over under `members`, each with its journey arc.
#
# THIS IS A FORMAT, NEVER A PRODUCER, and that distinction is load-bearing.
# Recognition keys on the record's own shape — a `brief` string — and NOTHING
# here detects, names, imports or resolves who wrote it. Keying on a
# producer's marker instead would make drafting learn which producer ran,
# which is exactly what entry-agnosticism forbids (ratified; restated in the
# 2026-07-31 #1051 amendment). An owner can hand-write this file; the run is
# byte-identical whoever did.


def _brief_record(text):
    """The JSON brief record behind a `--brief` FILE value, or None.

    Gated on the shape alone: an object with a `brief` STRING. Any other file
    — plain text, or JSON that is not a brief record — takes the unchanged
    file path below and is read as text exactly as it always was.
    """
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return None
    if isinstance(data, dict) and isinstance(data.get("brief"), str):
        return data
    return None


def _journey_arcs(record, source=None):
    """THE SELECTED STRANDS' SERVED JOURNEY ARCS, crossing the stage-0 boundary
    as declared source material at the recorded pin (Story 20.91, #1044 AC1).

    THE CARRIER, AND WHY IT IS THIS ONE. The story left the carrier open — an
    added handoff argument, or stage 0 reading the brief record directly — and
    the 2026-07-31 (#1051) amendment answered it: the handoff *"runs with
    `--brief` wired from the artifact"*. So there is exactly ONE carrier and it
    is the one that already ships: `--brief` has accepted a FILE since Story
    18.24 (#505), and the record IS a file. The arcs arrive with the brief
    string they were composed beside — no second argument, no second entry
    path, and nothing new on the owner's surface. A new `--arcs` argument was
    the alternative and is not taken: it would be a second handoff carrier for
    one hand-off, and it would still have to be wired from the same file.
    The brief STRING is unchanged byte for byte, so downstream BEHAVIOUR is
    identical to a brief the owner typed; what the record adds is material
    beside it and an `origin` value, which is the record-not-behaviour split
    #1050 already draws.

    QUOTED, NEVER RE-EXPRESSED (AC5). The arc is copied verbatim from the
    member record 20.90 widened — the served `journey_gloss:` rendering, which
    preserves the arc shape and never collapses to rule-statement register. No
    stage between here and drafting rewrites it into a rule or a claim, and
    nothing here summarises, truncates or re-orders it.

    ABSENCE KEEPS ITS KINDS (AC2). `served` plus `not_served_reason` travel as
    Story 20.90 shipped them, so *"no arc exists"* and *"no arc arrived"* stay
    different findings after the crossing. A member record predating 20.90
    carries no `journey` key at all — a THIRD state, and it is said as itself
    rather than folded into "not served", because an older record must still
    open (the #1048/#1049 cost note) and reporting an unrecorded field as a
    non-service would attribute a consumer's age to the source.
    """
    members = record.get("members")
    if not isinstance(members, list):
        return None
    arcs = []
    for m in members:
        if not isinstance(m, dict):
            continue
        rec = {"index": m.get("index"), "slug": m.get("slug")}
        j = m.get("journey")
        if isinstance(j, dict):
            rec.update({"arc": j.get("arc"), "arc_cite": j.get("arc_cite"),
                        "served": bool(j.get("served")),
                        "not_served_reason": j.get("not_served_reason")})
        else:
            rec.update({"arc": None, "arc_cite": None, "served": False,
                        "not_served_reason": (
                            "this brief predates the arc field (Story 20.90), "
                            "so no arc was recorded either way — not a report "
                            "that the hub served none")})
        arcs.append(rec)
    if not arcs:
        return None
    pins = record.get("pins")
    return {
        "of": ("the selected Strands' served journey arcs, quoted at the pin "
               "the brief recorded"),
        "at": pins if isinstance(pins, dict) else None,
        "source": source,
        # THE BOUNDARY IS UNCHANGED (AC3). Arcs arrive BESIDE the host-repo
        # sources, never in place of them and never as a widening of them:
        # repositories remain harvest SCOPE and never evidence binding, and an
        # arc is material rather than a Fact — the article floor (≥1 sourced or
        # derived claim resolving at the ship gate) is untouched, and an arc
        # alone never satisfies it. New material, not a new licence.
        "boundary": ("declared source material carried BESIDE the host-repo "
                     "sources; the source boundary is unchanged, repositories "
                     "stay harvest scope and never evidence binding, and the "
                     "article floor is neither relaxed nor satisfied by an arc"),
        "register": ("the served rendering, quoted at its cite — no stage "
                     "rewrites an arc into a rule, a summary or a claim"),
        # AC6, stated where a later reader will meet it: this makes the arcs
        # AVAILABLE and decides nothing about how prose uses them. Whether an
        # arc enters as a worked example, a short story, or a standalone
        # paragraph is #1045, PARKED behind the first draft composed with arcs
        # available — a diff that picks one has decided a parked question.
        "incorporation": ("undecided here — availability only; the register "
                          "question is parked (#1045)"),
        "arcs": arcs,
    }


def _read_brief(raw):
    """Resolve a free-form coverage brief (Story 18.24, #505) into its recorded
    form. A value that is an existing file path is read (origin `file`, source
    path retained for provenance); anything else is the brief text inline
    (origin `inline`). A file that is a JSON BRIEF RECORD resolves to the brief
    string it carries plus the selected Strands' journey arcs (origin
    `brief-record`, Story 20.91) — the same file path, read as the shape it
    declares. Provenance is always owner-authored — like an interview answer, the
    brief is the owner's own words. Returns None for an empty value."""
    if raw is None:
        return None
    val = raw.strip()
    if not val:
        return None
    if os.path.isfile(val):
        try:
            text = open(val, encoding="utf-8").read().strip()
        except OSError:
            text = val
        else:
            rec = _brief_record(text)
            if rec is not None:
                state = {"text": str(rec.get("brief") or "").strip(),
                         "provenance": "owner-authored",
                         "origin": "brief-record",
                         "source": os.path.abspath(val)}
                arcs = _journey_arcs(rec, os.path.abspath(val))
                if arcs:
                    state["journey_arcs"] = arcs
                return state
            return {"text": text, "provenance": "owner-authored",
                    "origin": "file", "source": os.path.abspath(val)}
    return {"text": val, "provenance": "owner-authored", "origin": "inline"}

