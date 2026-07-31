#!/usr/bin/env python3
"""topic-map-directions.py — the map's ONE screen and its brief hand-off
(Story 18.63, #591; SPEC-terrain CAP-3).

The map ends in a BRIEF, not in a second proposer. This script reads an
assembled map (`terrain_map.py assemble`) and composes exactly two things:

  * `candidates` — machine-proposed candidate DIRECTIONS, each a subject the
    owner might cover, derived from the map's own depth signals. At least one is
    a CROSS-TOPIC COMBINATION when the evidence supports one — the "connect
    these topics along this axis" move that is the reason the map exists;
  * `payload`   — those candidates as ONE owner-facing proposal payload, in the
    shape `validate-proposal-payload.py --surface topic-map` accepts, always
    carrying a FREE-FORM option and a stop option.

THE SIZE SWITCH (Story 18.66, #601; CAP-3 as amended 2026-07-23)
----------------------------------------------------------------
One screen does not scale. At or under the SCREEN BUDGET the flow above is
unchanged, byte for byte. Above it, the terrain is rendered into a **View file**
the owner opens and the screen becomes a short SUMMARY plus that file's path,
with selection by stable index rather than by matching a direction string —
because 20+ directions collapsed into a handful of options hides exactly what
the map exists to show.

The View is a RENDERING of one invocation, at the same status as terrain_map.py's
`--emit-debug`: a fixed filename in the run workspace, fully regenerated every
invocation, and **never read back by any code path** (grep-asserted). Deleting
it loses nothing — the map is derived, and the View is recomposed from it.

WHAT THIS SCRIPT DELIBERATELY DOES NOT DO
-----------------------------------------
It never composes narrative shapes. A candidate names WHAT to cover and, for a
combination, the AXIS connecting two subjects — it never proposes how the piece
is told, ordered, or opened. Proposing shapes downstream remains the shipped
single proposer's job (SPEC-article-draft-pipeline CAP-4, Story 18.45's
single-proposer invariant); a map that started suggesting article shapes would
be the second proposer #554/#583 both forbid. `check-topic-map-screen.sh`
grep-asserts the absence.

THE HAND-OFF
------------
The owner's outcome is a BRIEF IN THE OWNER'S WORDS — machine-proposed text the
owner accepts becomes owner-adopted wording — handed to the EXISTING stage-0
`--brief` path (`draft-pipeline.py stage0 <framework> <sources...> --brief ...`,
Story 18.24 / #505). `brief` emits exactly that string from the recorded answer.
No new entry pipeline exists: downstream, a sitting that started at the map is
indistinguishable from one whose brief the owner typed unaided.

Free-form is offered EVERY time, not only on rejection: the owner naming their
own direction or combination axis is a first-class outcome, not a fallback.

THE BRIEF IS A NAMED ARTIFACT WITH A LIFECYCLE (Story 20.75, #994)
------------------------------------------------------------------
The hand-off above is unchanged — the brief string still goes into the same
stage-0 path and drafting stays entry-agnostic. What is added is consumer-side
surfacing that was missing entirely: the gate names the STEP that produced the
brief, `brief --out` writes it as a DURABLE ARTIFACT under the run workspace,
and its LIFECYCLE — composed → inspected → adopted — is carried with it so the
state is legible at the gate. `brief-open` re-opens one and records forward
transitions. WHAT COMPOSES THE BRIEF IS UNTOUCHED: selection at the screen
composes it, which is ratified and out of scope here.

This artifact is the one thing in this script that IS read back, and the
contrast with the View is deliberate — see the block above
`write_brief_artifact` for why the two rules must stay apart.

THE GATE CARRIES AN ITERATION LOOP OVER THE MEMBER SET (Story 20.77, #997)
--------------------------------------------------------------------------
The gate offered adopt, narrow, or "go back to Screen 2 and pick differently",
so an owner developing a thesis by trying members lost the composition every
time they changed the set. `brief --from <prior brief> --out <next brief>`
with an answer carrying `{"edit": "+L12 −L3", "pin": ...}` resolves the edit
to a member set and then takes the ORDINARY indexed path, so the recomposition
that has existed since Story 20.54 is REACHED rather than re-implemented, with
its pin discipline and its scope-bounding `recomposition` block intact. Prior
compositions are retained in `iteration.compositions` — WITHIN THE SITTING,
carried in this run workspace's own artifacts, so a new invocation begins with
an empty chain. See the block above `_parse_edit`.

INDEXED SELECTION (Story 18.67, #602)
-------------------------------------
From a View, the owner answers `{index: "T3.2", note: "<their angle>", pin:
"<the View's pin>"}`. The composed brief is the subtopic's coverage wording
plus THE NOTE VERBATIM, and it goes into the same stage-0 `--brief` path as any
other brief — no new entry pipeline, and the note reaches the structure
proposer only as brief text.

Indexes are stable WITHIN A PIN, not across repo states, so an index carries
the pin it was read at. A mismatch is REFUSED with the mismatch named rather
than re-resolved: silently reinterpreting `T3.2` against a moved repository
would hand the owner a scope they never chose. Free text still always wins.

Stdlib-only. Subcommands:
  candidates  --map PATH        the candidate directions as JSON
  payload     --map PATH [--view PATH]
                                the one screen, as a proposal payload; --view
                                renders the View when the map is over budget
  view        --map PATH --out PATH
                                the View file alone
  brief       --answer PATH [--map PATH] [--out PATH] [--from PATH]
                                the owner's chosen direction as the brief string
                                for stage-0 `--brief`; --out also writes it as a
                                durable, RE-OPENABLE artifact under the run
                                workspace (Story 20.75), and --from edits that
                                artifact's member set and recomposes over the
                                result (Story 20.77)
  brief-open  --at PATH [--state inspected|adopted]
                                re-open a written brief, and optionally record
                                the lifecycle transition the return represents
  cover       --composed PATH --from PATH
                                count the placement cover of the COMPOSED
                                candidate theses (or the proposed partition)
                                against the brief's member set — every selected
                                Strand placed, or its omission disclosed; run
                                AFTER composition (Story 20.78)

Exit codes: 0 ok · 1 refusal (no usable map / no owner wording) · 2 usage.
"""

import argparse
import json
import os
import re
import sys

# The text and disclosure primitives this surface composes with (Story 20.58,
# #942). A LEAF layer, imported by name so every call site below reads exactly
# as it did before the split — the extraction moved code, not behaviour. The
# screen-composition names that used to be imported here went with the screens
# themselves (Story 20.80, #1029) and are imported by `terrain_screens.py`; what
# remains is what this file still composes with directly.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from terrain_text import (  # noqa: E402
    BRIEF_LIFECYCLE,
    BRIEF_STEP_ID,
    BRIEF_STEP_NAME,
    PARTITION_OPTION_LABEL,
    THESIS_CANDIDATES_OPTION_LABEL,
    VIEW_LINE_CHARS,
    _backlog_line,
    _brief_artifact_line,
    _brief_lifecycle_line,
    _brief_step_line,
    _elide,
    _fit,
    _partition_proposal_line,
    _short_path,
    _substituted_paths,
    _thesis_candidates_line,
    _thesis_state_line,
)

# CANDIDATE THESES over the selected set, and k candidate briefs over a
# proposed partition (Story 20.78, #995/#988). Its own module, beside the file
# rather than inside it, for the reason `strand_cover.py` states: new mechanism
# arrives beside a file at its ratchet. The count it carries is the SAME
# placement cover the drafting composer already runs, counted at the earlier
# gate rather than re-invented there.
from terrain_theses import (  # noqa: E402
    PARTITION_MIN_GROUPS,
    PARTITION_OFFER_MIN,
    THESIS_CANDIDATES_MAX,
    THESIS_CANDIDATES_MIN,
    coverage_statement,
    partition_proposal_block,
    thesis_candidates_block,
    verify_cover,
)

# The candidate-directions layer this surface proposes with (Story 20.56,
# #938). A LEAF layer, imported by name so every call site below reads exactly
# as it did before the split — the extraction moved code, not behaviour.
# `_element_direction` and `lint_owner_lines` are no longer imported here:
# after the #1025 inversion nothing in this file used them, and the three
# checks that reached them through this re-export now load
# terrain_directions.py directly (#1036).
from terrain_directions import (  # noqa: E402
    _direction_lines,
    _elements,
    _is_substance_led,
    candidates,
)
from terrain_members import (  # noqa: E402
    AXES,
    JOURNEY_SUBSTRATE,
    SUBSTRATES,
    SUBSTRATES_UNOFFERED,
    SUBSTRATE_DEFAULT,
    _axis_strands,
    _err,
    _member_record,
    apply_subgroups,
    axis_members,
    cmd_member,
    compose_full_report,
    compose_member_view,
    load_map,
    member_sections,
)

# THE INVERSION (Story 20.80, #1029; the 2026-07-31 (#1025) amendment). This
# file is HYPHENATED and therefore unimportable, which is the constraint four
# consecutive extractions worked around by closing each moving set under its own
# references. It is dissolved rather than worked around a fifth time: this path
# keeps its name and its ten skill invocations and carries argparse and dispatch,
# and the composition it dispatches to lives in the importable siblings below.
# Imported BY NAME so every call site reads exactly as it did before the split.
#
# The owner-facing SCREEN compositions and the View file. The two constants come
# back with them — each is still declared in exactly one place, now beside the
# function that reads it — because the help text and the over-budget warning
# below are the parent's own.
from terrain_screens import (  # noqa: E402
    SCREEN_BUDGET,
    VIEW_FILENAME,
    compose_axis_payload,
    compose_payload,
    compose_view,
    is_large,
    write_view,
)

# Resolving what the owner SELECTED: the set arithmetic, the G-id expansion at
# the screen that minted it, the composite pin's which-half-moved message, and
# the writability gap a non-matched selection discloses. Composing a brief FROM
# a resolved selection stays here, beside the dispatch that reaches it.
from terrain_select import (  # noqa: E402
    _group_expander,
    _selected_indexes,
    _selection_gap,
    _selection_terms,
    _which_half_moved,
)

# The BRIEF ARTIFACT — its lifecycle, its writer and its sanctioned reader — and
# the edit-set iteration loop that recomposes over a changed member set. They
# are one closure: the loop reads a written artifact, checks the pin it was
# composed at, and writes the next one beside it.
from terrain_brief import (  # noqa: E402
    BRIEF_FILENAME,
    _base_composition_pin,
    _brief_lifecycle,
    _edited_indexes,
    _iteration_block,
    _parse_edit,
    read_brief_artifact,
    write_brief_artifact,
)




def cmd_axis(args):
    m = load_map(args.map)
    out = {"kind": "terrain-axis", "axis": axis_members(m),
           "payload": compose_axis_payload(m)}
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def journey_similarity_inputs(strands, tag):
    """The judgment inputs: each Strand's SERVED arc, quoted verbatim.

    Never a paraphrase and never a lesson body (unservable, OQ3). A Strand
    whose arc is not served is carried with `served: false` and its reason, so
    the composer can tell "no arc exists" from "no arc arrived".
    """
    out = []
    for el in strands:
        arc = el.get("journey")
        out.append({"slug": el.get("slug"),
                    "arc": arc if isinstance(arc, str) and arc.strip() else None,
                    "arc_cite": el.get("journey_cite"),
                    "served": bool(isinstance(arc, str) and arc.strip()),
                    "not_served_reason": el.get("journey_unavailable")})
    return out


def cmd_report(args):
    m = load_map(args.map)
    axis = getattr(args, "axis", "tag") or "tag"
    group_ids = [g for g in re.split(r"[,\s]+", str(args.groups or "")) if g]
    if not group_ids:
        return _err("no group id named. A full report is pulled by naming the "
                    "group ids you want from the current screen.")
    claims = None
    if getattr(args, "claims", None):
        try:
            claims = json.loads(args.claims)
        except ValueError as exc:
            return _err(f"--claims is not readable JSON: {exc}")
    grouping = None
    if getattr(args, "grouping", None):
        try:
            grouping = json.loads(args.grouping)
        except ValueError as exc:
            return _err(f"--grouping is not readable JSON: {exc}")
    subgroups = None
    if getattr(args, "subgroups", None):
        try:
            subgroups = json.loads(args.subgroups)
        except ValueError as exc:
            return _err(f"--subgroups is not readable JSON: {exc}")
    try:
        out = compose_full_report(m, str(args.tag).strip(), candidates(m),
                                  group_ids, axis, claims, grouping,
                                  subgroups=subgroups)
    except ValueError as exc:
        return _err(str(exc))
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0








# THE COHERENCE CONSULTANT'S BINDING RULES (Story 20.55, #939; SPEC-terrain
# CAP-3 §"the brief gate may carry a coherence CONSULTANT").
#
# What is frozen here is the gate SHAPE, the grounding rule, the honesty rule
# and the no-hiding rule — never the assessment itself. That is deliberate and
# is the whole reason this capability is bounded rather than open: the failure
# being avoided is a narrow deterministic procedure that keeps reporting
# success because it satisfied its own constrained steps while failing what
# the owner actually wanted. An instrument over the judgment would be that
# failure, encoded.
#
# The asymmetry in the fourth rule is the second-proposer boundary, applied: a
# combination becomes a proposal exactly when something other than the owner
# NARROWS the candidate set, and the test is whether what reached the owner is
# smaller than what exists. A substitution proposal ADDS, so it is admissible.
# RANKING narrows, so it is not — and adding unselected material is admissible
# ONLY because nothing is hidden.
CONSULTANT_RULES = [
    "nothing is adopted silently — every assessment and every proposal "
    "reaches the owner as a proposal with free-form override, the owner "
    "decides, and nothing enters the brief without the owner adopting it",
    "every claim cites served material at the pin — naming a Strand or a "
    "group means citing that Strand's served rendering or the group's claim "
    "at this pin, and no proposal introduces material outside the served "
    "corpus at that pin",
    "incoherence and uncertainty are both stated — a set that cannot support "
    "a single thesis is said so plainly rather than composed around, and an "
    "unsure consultant discloses the uncertainty rather than emitting a "
    "confident structure",
    "substitutions enumerate their candidates — a proposal to replace a "
    "Strand lists the candidates considered rather than reducing them to one "
    "best swap, and never ranks them and surfaces only the strongest; "
    "ranking is the narrowing the second-proposer boundary bars",
]


def _consultant_block(matches, cands, map_data):
    """The coherence consultant's subject and its unnarrowed candidate pool.

    NEVER RUNS UPSTREAM OF A SELECTION (AC5): this is reached only from the
    brief path, which by construction has one. The owner's having selected is
    what discharges the second-proposer bar, so a consultant running before a
    selection would be a scope originator, not a consultant.

    The substitution pool is EVERY unselected Strand at this pin, enumerated
    and unranked. Trimming it to a promising few would be exactly the
    narrowing the fourth rule bars — the pool is what makes adding material
    admissible at all.
    """
    chosen = {m.get("id") for m in matches}
    return {
        "rules": CONSULTANT_RULES,
        # The subject: what the owner actually selected, with the cites every
        # claim about it has to be grounded in.
        "subject": [_member_record(m) for m in matches],
        # Unranked and complete. The order is the map's own, which is
        # deterministic within a pin; it is not a ranking and must not be
        # relayed as one.
        # THE POOL IS NOT WIDENED, AND THIS IS NOT AN OVERSIGHT (Story 20.90,
        # #1044, AC3). It keeps the four-key record while `subject` above and
        # the brief's `members` carry the arc, on two grounds that both point
        # the same way:
        #   * the pool is OFFERED material, not POINTED-AT material. The
        #     anti-widening bound applies to it exactly — what the owner
        #     selected is the scope, and the arc travels because it is the
        #     selected Strand's own, not because arcs are good to have;
        #   * the pool is the COMPLETE unselected set at this pin, so widening
        #     it is an unbounded payload attached to material the owner did not
        #     choose.
        # A later reader must not mistake this asymmetry for a missed call site.
        "substitution_candidates": [
            _member_record(c, arc=False) for c in cands
            if c.get("kind") == "element" and c.get("id") not in chosen],
        # THIS `ranked: False` IS CORRECT AND STAYS (Story 20.89, #1043 AC4).
        # Two such fields existed and only one was wrong. THIS one is on the
        # PRE-SELECTION members block: it is exactly where the second-proposer
        # boundary binds, because a machine ranking upstream of the owner's
        # selection is the act the boundary exists to prevent. The one that was
        # corrected is the POST-SELECTION candidate-thesis gate field in
        # `terrain_theses.py`, where the owner has already narrowed and a
        # retained-whole ranking narrows nothing further.
        #
        # Stated here so a later reader does not "fix" the two into
        # consistency: they are not two spellings of one property. They are two
        # different moments, and the boundary falls between them.
        "ranked": False,
        "pin": (map_data or {}).get("coverage", {}).get("pin"),
    }


def _brief_from_index(answer, cands, map_pin, map_data=None):
    """An INDEXED selection from the View: `{index, note}` (Story 18.67, #602),
    where `index` names a SET (Story 20.54, #937).

    For ONE index the composed brief is the Strand's coverage wording PLUS THE
    OWNER'S NOTE VERBATIM — the machine resolves which Strand `L3` meant, the
    owner supplies the angle, and the result is one ordinary brief string for
    the existing stage-0 `--brief` path. There is no new entry pipeline:
    downstream cannot tell this from a brief the owner typed, and the note
    reaches the structure proposer only as brief text.

    For a SET the claim is RECOMPOSED over exactly the selected members — not
    over a group's original member set, and not over a union of groups. The
    recomposition inputs carried back are those members' served claims and
    nothing else, so a composer at the gate cannot widen the scope past what
    the owner pointed at. An owner-adopted `claim` supersedes the deterministic
    wording; free text at the gate supersedes both (`brief_from_answer`).

    A typed G-id is SHORTHAND that expands here into the group's member
    indexes before anything is composed (Story 20.76, #996), with set
    arithmetic — `G4 + L26, minus L48` — resolved in the same pass. Only
    members are recorded: the brief below carries member indexes and pins and
    no G-id, because a group id is per-screen and per-pin and a rendering is
    not an address. The result is byte-identical to the same set typed member
    by member, which is the test that this is ergonomics and not a second kind
    of address.

    An index is meaningless without the map it was read from, so the answer
    must carry the pin the View was rendered at. A mismatch is REFUSED with the
    mismatch named — never silently re-resolved to whatever `L3` happens to
    mean at the current pin, which would hand the owner a scope they never
    chose. A missing pin is refused for the same reason: it cannot be proven
    not to be stale.
    """
    # AS TYPED, for the refusals below only: a refusal has to quote what the
    # owner actually wrote — operators and all — and nothing is expanded
    # before the pin it was typed against is proven current.
    raw = answer.get("index")
    index = ", ".join(str(p).strip() for p in raw) \
        if isinstance(raw, (list, tuple)) else str(raw or "").strip()
    answer_pin = str(answer.get("pin") or "").strip()
    if not answer_pin:
        raise SystemExit(_err(
            f"the recorded answer selects index {index!r} but carries no pin. An "
            "index only means something against the map it was read from, so "
            "the View's pin must be recorded with the selection; without it a "
            "stale selection cannot be told from a current one. Re-run the map "
            "and choose again."))
    if map_pin and answer_pin != map_pin:
        # The pin is the COMPOSITE of the map's inputs (Story 20.31, #872), so
        # this fires when EITHER the destination repo or the hub moved. Name
        # which, when the answer carried the halves; say plainly that it
        # cannot be named when it did not, rather than guessing.
        moved = _which_half_moved(answer, map_data or {})
        raise SystemExit(_err(
            f"pin mismatch: index {index!r} was chosen against a listing "
            f"rendered at {answer_pin}, but this map is at {map_pin}. "
            f"{moved} That index may now name a different Strand, so it is "
            "refused rather than re-resolved. Re-run the map and choose from "
            "the fresh screens."))
    # EXPAND, THEN THE ARITHMETIC — both entirely before the brief exists
    # (Story 20.76 AC1/AC2). After this line no G-id exists in the flow: only
    # member indexes do, so nothing below can record one.
    indexes, named = _selected_indexes(
        answer, _group_expander(answer, cands, map_data))
    by_id = {c.get("id"): c for c in cands}
    # EVERY named index is resolved, and an unresolvable one refuses the whole
    # selection: dropping it would compose the brief over a set the owner did
    # not choose, silently. `named` and not `indexes`, so a subtracted index
    # that names no Strand is caught too — a `minus` over nothing is a typo
    # the owner should hear about, not a silent no-op.
    missing = [i for i in named if i not in by_id]
    if missing:
        raise SystemExit(_err(
            f"index {', '.join(repr(i) for i in missing)} names no Strand in "
            "this map. The indexes come from the screens rendered at this pin "
            "— re-read them and choose again."))
    if not indexes:
        raise SystemExit(_err(
            f"the selection {index!r} subtracts everything it names, so no "
            "Strand is selected and there is nothing to compose a brief over. "
            "Name the members you want kept."))
    # RECOMPUTED FROM THE MEMBERS (Story 20.76 AC3): what is recorded from
    # here on is the resolved set, never the typed shorthand. A G-id is
    # per-screen and per-pin, so recording one would make a rendering an
    # address — which is the invariant this expansion preserves rather than
    # relaxes.
    index = indexes[0] if len(indexes) == 1 else ", ".join(indexes)
    matches = [by_id[i] for i in indexes]
    note = str(answer.get("note") or "").strip()
    claim = str(answer.get("claim") or "").strip()
    if len(matches) == 1 and not claim:
        # THE DEGENERATE CASE, preserved byte for byte: the coverage wording
        # plus the note verbatim, exactly as before set selection existed.
        base = matches[0]["direction"]
    else:
        # RECOMPOSED OVER EXACTLY THIS SET, and NO LONGER THE SET'S THESIS
        # (Story 20.78, #995). This join was the one thesis composed per
        # selection; it is now what it always literally was — a coverage
        # statement over the selected members — and the thesis arrives as 2–3
        # CANDIDATES composed at the gate from the block below. The string is
        # unchanged byte for byte: what changed is what it claims to be, and
        # `thesis.state` says so rather than leaving the owner to read a
        # semicolon-joined list as a reading of their set. An owner-adopted
        # claim — the candidate they chose — replaces it outright.
        base = claim or coverage_statement(matches)
    brief = f"{base} — {note}" if note else base
    cov = (map_data or {}).get("coverage", {}) or {}
    members = [_member_record(m) for m in matches]
    out = {"brief": brief,
            # The coverage wording is machine-proposed and the owner adopted it
            # by choosing its index; the note is theirs outright. Both are the
            # owner's words under the shipped rule — never a tool-invented scope.
            "provenance": "owner-authored",
            "origin": "adopted-index" if len(matches) == 1 else "adopted-index-set",
            "index": index, "indexes": indexes, "pin": answer_pin, "note": note,
            "adopted_claim": claim or None,
            # THE MEMBER SET IS NOT BOOKKEEPING (Story 20.54 AC4): the
            # completeness invariant follows it into drafting — every selected
            # Strand placed or its omission disclosed — so with no members
            # recorded, omission becomes silent.
            "members": members,
            # Both halves of the pin: the terrain invocation the indexes were
            # read at, and the hub commit the material came from.
            "pins": {"terrain": answer_pin, "hub": cov.get("hub_pin"),
                     "destination": cov.get("destination_pin")},
            # Recomposition inputs are the selected members' served claims and
            # NOTHING else, so a composer at the gate cannot widen the scope.
            "recomposition": {
                "authoring": "machine-composed at render time, marked",
                "over": [m.get("id") for m in matches],
                "claims": [m.get("gloss") or m.get("direction")
                           for m in matches]},
            # THE COHERENCE CONSULTANT (Story 20.55, #939), carried only where
            # it has a subject: a set of two or more. One Strand cannot fail to
            # cohere with itself, and a consultant with nothing to assess would
            # be shape without content.
            **({"consultant": _consultant_block(matches, cands, map_data)}
               if len(matches) > 1 else {})}
    # `candidate` IS GONE (Story 20.99, #1077). It carried `matches[0]` — the
    # raw map element for the FIRST member — beside `members`, so a consumer
    # reading the plausibly-named key saw a one-Strand brief. Both names read as
    # "the selection" and only one was the record, which is worse than an
    # absent field: every future reader had to learn which to distrust.
    #
    # It also dragged the map-element schema across the boundary whole —
    # `element_kind`, `topics`, `subtopics`, `date`, `depth`, `usability`,
    # `consumed`, `evidence_pointers` — map-internal working state, with
    # internal topic vocabulary reaching an artifact that crosses into
    # drafting. Removing the key removes that leak entirely; `_member_record`
    # was already the clean projection.
    #
    # A ONE-MEMBER SELECTION TAKES THE SAME PATH. A set of one is the
    # degenerate case of a set, not a different operation, so it emits the same
    # keys — which is what stops the singular from growing back as a
    # special case.
    if len(matches) > 1:
        # THE THESIS IS A CHOICE FROM CANDIDATES (Story 20.78, #995), and the
        # gate says which state it is in. Carried for a SET only: one Strand's
        # served wording is that Strand's, and proposing readings of it would
        # be a second proposer over a selection with nothing to re-read.
        out["thesis"] = {
            "state": "adopted" if claim else "candidates-pending",
            "text": claim or None,
            "line": _thesis_state_line(
                "adopted" if claim else "candidates-pending"),
            "brief_string_is": (
                "the owner's adopted candidate" if claim else
                "a COVERAGE STATEMENT over the members, not a reading of them"),
        }
        out["candidate_theses"] = {
            "label": THESIS_CANDIDATES_OPTION_LABEL,
            "line": _fit(_thesis_candidates_line(
                len(matches), THESIS_CANDIDATES_MIN, THESIS_CANDIDATES_MAX)),
            **thesis_candidates_block(members, answer_pin, claim or None),
        }
        # k CANDIDATE BRIEFS OVER A PROPOSED PARTITION (#988) — the same
        # machinery over a partition, offered only where a selection is large
        # enough to carry several theses. `None` below the threshold: an
        # unoffered proposal is absent, never present-and-empty, because an
        # empty proposal block reads as a proposal that found nothing.
        part = partition_proposal_block(members, answer_pin, PARTITION_OFFER_MIN)
        if part:
            out["partition_proposal"] = {
                "label": PARTITION_OPTION_LABEL,
                "line": _fit(_partition_proposal_line(
                    len(matches), PARTITION_MIN_GROUPS)),
                "backlog_line": _fit(_backlog_line(PARTITION_MIN_GROUPS)),
                **part,
            }
    return out


def brief_from_answer(answer, cands, map_pin=None, map_data=None):
    """The owner's outcome as the brief string for stage-0 `--brief`.

    Free text ALWAYS wins: machine-proposed wording becomes the brief only when
    the owner adopted it by selecting it — by matching a direction string or by
    naming its index — and then it is owner-adopted wording, not a
    tool-invented scope."""
    free = str(answer.get("free_text") or "").strip()
    if free:
        return {"brief": free, "provenance": "owner-authored", "origin": "free-form"}
    selection = str(answer.get("selection") or "").strip()
    if selection in ("stop here", "stop"):
        raise SystemExit(_err(
            "the owner chose to stop at the map: no brief exists and no run "
            "follows. Stopping is a first-class outcome, not a failure."))
    # ROUTED ON WHAT WAS TYPED, not on what it resolves to: a selection whose
    # arithmetic cancels out is an indexed selection with a mistake in it, and
    # it is refused as one rather than falling through to "that is not a
    # proposed direction".
    if _selection_terms(answer):
        return _brief_from_index(answer, cands, map_pin, map_data)
    for c in cands:
        if selection == c["direction"]:
            return {"brief": c["direction"], "provenance": "owner-authored",
                    "origin": "adopted-candidate", "candidate": c}
    raise SystemExit(_err(
        f"the recorded answer selects {selection!r}, which is neither a proposed "
        "direction nor free-form wording. The brief is the owner's words — it is "
        "never inferred here."))


def cmd_candidates(args):
    print(json.dumps({"stage": "topic-map-directions",
                      "candidates": candidates(load_map(args.map))},
                     indent=2, ensure_ascii=False))
    return 0


def cmd_payload(args):
    data = load_map(args.map)
    view_path = getattr(args, "view", None)
    large = is_large(data)
    # Derived ONCE and shared: the screen and the View must offer the same
    # directions, and deriving twice is how they would silently drift apart.
    cands = candidates(data)
    if view_path and large:
        write_view(view_path, compose_view(data, cands))
    print(json.dumps(compose_payload(data, cands, view_path),
                     indent=2, ensure_ascii=False))
    if large and not view_path:
        sys.stderr.write(
            f"warning: this map has more than {SCREEN_BUDGET} subtopics, which "
            "is past the screen budget — pass --view PATH so the terrain is "
            "rendered into a View file the owner can open. Without it the "
            "screen carries the capped candidate list, which hides most of the "
            "terrain.\n")
    return 0


def cmd_view(args):
    """Render the View alone — the same rendering `payload --view` writes, for
    a caller that wants it without composing a screen.

    With `--tag` it renders ONE VIEW of one member instead (Story 20.38,
    #892): the complete sectioning the screen shows only in summary. The file
    is a rendering of one invocation addressed by path — regenerated every
    time, NEVER read back, and holding no identity the rest of the system can
    refer to. In-invocation memory is not storage; a cross-invocation view
    cache is forbidden.
    """
    data = load_map(args.map)
    tag = getattr(args, "tag", None)
    if tag:
        axis = getattr(args, "axis", "tag") or "tag"
        grouping = None
        if getattr(args, "grouping", None):
            try:
                grouping = json.loads(args.grouping)
            except ValueError as e:
                return _err(f"--grouping is not valid JSON ({e})")
        ms = member_sections(data, str(tag).strip(), axis,
                             substrate=getattr(args, "substrate",
                                               SUBSTRATE_DEFAULT),
                             grouping=grouping)
        # The View file is the surface that holds the WHOLE rendering, so the
        # hierarchy must reach it too (Story 20.87 AC2): three surfaces showing
        # the same grouping differently is the defect #1039 records.
        try:
            apply_subgroups(ms, json.loads(args.subgroups)
                            if getattr(args, "subgroups", None) else None)
        except ValueError as exc:
            return _err(str(exc))
        if not ms["count"]:
            return _err(f"no Strand sits under {tag!r} at this pin")
        # THE CLAIMS REACH THE VIEW PATH (Story 20.83, #1039). `--claims` was
        # parsed on `member` only, so the file could not carry the `in common:`
        # lines even in principle — the plumbing was the missing half of the
        # rendering, not an afterthought to it.
        claims = None
        if getattr(args, "claims", None):
            try:
                claims = json.loads(args.claims)
            except ValueError as exc:
                return _err(f"--claims is not readable JSON: {exc}")
            if not isinstance(claims, dict):
                return _err("--claims must be an object keyed by group id, "
                            'for example {"G1": "..."}')
        # ONE derivation of the candidate ids, shared with the screen: the
        # display indexes in the file must be the ids selection is made by.
        write_view(args.out,
                   compose_member_view(data, ms, candidates(data), claims))
        print(args.out)
        return 0
    write_view(args.out, compose_view(data, candidates(data)))
    print(args.out)
    return 0


def _answer_from_payloads(path, ask_id=None):
    """Select the recorded answer row from a presented-payloads.jsonl capture
    (#831): the row `validate-proposal-payload.py --answer` appended, so the
    skill hands over the capture file itself and nothing is hand-extracted.
    With --ask-id, the row for that ask; otherwise the latest answer row."""
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("kind") == "answer" and \
                    (ask_id is None or str(row.get("ask_id")) == str(ask_id)):
                rows.append(row)
    if not rows:
        which = f"ask {ask_id}" if ask_id is not None else "any ask"
        raise ValueError(f"no recorded answer row for {which} in {path}")
    return rows[-1]


def cmd_brief(args):
    try:
        if getattr(args, "payloads", None):
            answer = _answer_from_payloads(args.payloads, args.ask_id)
        else:
            answer = json.load(open(args.answer, encoding="utf-8")) if args.answer != "-" \
                else json.load(sys.stdin)
    except (OSError, ValueError) as exc:
        src = getattr(args, "payloads", None) or args.answer
        return _err(f"unreadable answer at {src}: {exc}")
    if answer.get("kind") == "answer":            # a presented-payloads.jsonl row
        answer = answer.get("answer") or {}
    map_data = load_map(args.map) if args.map else None
    cands = candidates(map_data) if map_data else []
    map_pin = (map_data or {}).get("coverage", {}).get("pin")
    # THE ITERATION LOOP (Story 20.77, #997). An edit is resolved to a member
    # set BEFORE composition, so everything below is the ordinary indexed
    # path: recomposition is REACHED here, never re-implemented.
    base, edit, prior, inherited_note = None, None, [], False
    if not str(answer.get("free_text") or "").strip():
        # AC5 — free text wins at ANY point in the loop, so an edit is not
        # even parsed when the owner wrote their own words: the set it would
        # edit never reaches the brief, and a malformed edit beside free text
        # must not refuse a brief the owner authored outright.
        try:
            edit = _parse_edit(answer)
        except SystemExit as exc:
            return exc.code
        src = getattr(args, "from_brief", None)
        out_path = getattr(args, "out", None)
        if edit and not src:
            return _err(
                "the recorded answer edits a member set, but nothing names "
                "the composition it edits: pass --from <the brief artifact "
                "this recomposes>. An edit is relative to a set, and there is "
                "no ambient 'current' one — that would be the cross-invocation "
                "state this loop is built to avoid.")
        if src and not edit:
            return _err(
                f"--from {src} names a composition to edit, but the recorded "
                "answer carries no edit. Name what changes — `+L12 −L3` — or "
                "drop --from and compose from a fresh selection.")
        if edit:
            if not out_path:
                return _err(
                    "an edit-set recomposition is RETAINED for the sitting, "
                    "and the retention IS the artifacts it writes: pass --out "
                    "<a path in the same run workspace as --from> so this "
                    "composition can be compared against the ones before it.")
            if os.path.abspath(src) == os.path.abspath(out_path):
                return _err(
                    f"--from and --out are both {out_path}: this "
                    "recomposition would overwrite the composition it edits, "
                    "and the comparison the loop exists for needs both. Write "
                    "it beside the one it came from — the artifact's identity "
                    "is its path, so any other name in this workspace will do.")
            if os.path.dirname(os.path.abspath(src)) != \
                    os.path.dirname(os.path.abspath(out_path)):
                return _err(
                    f"--from {src} and --out {out_path} are in different "
                    "workspaces. Retention is WITHIN-SITTING: the chain of "
                    "compositions lives in one run workspace, and an edit "
                    "reaching across workspaces would be the cross-invocation "
                    "store the never-read-back rule forbids. Edit a "
                    "composition from THIS sitting, or select afresh.")
            try:
                base = read_brief_artifact(src)
            except (OSError, ValueError) as exc:
                return _err(f"unreadable brief artifact at {src}: {exc}")
            try:
                _base_composition_pin(base, map_pin, map_data)
                indexes = _edited_indexes(
                    list(base.get("indexes") or []), edit)
            except SystemExit as exc:
                return exc.code
            prior = list((base.get("iteration") or {}).get("compositions") or [])
            # The NOTE is the owner's angle, not a claim over the set, so it
            # survives an edit they did not restate — with the inheritance
            # disclosed below. The adopted CLAIM does NOT: a claim belongs to
            # the set it was composed over (AC2), and carrying one across an
            # edit would leave a composition attached to a set it was never
            # composed from. It is recomposed instead.
            note = str(answer.get("note") or "").strip()
            if not note:
                note = str(base.get("note") or "").strip()
                inherited_note = bool(note)
            # Built from the ANSWER, never from the base: an adopted claim
            # the owner did not restate simply is not there to inherit.
            answer = dict(answer, index=indexes, note=note)
    out = brief_from_answer(answer, cands, map_pin, map_data)
    # Evidence-independence at the hand-off (#799): a selected element's
    # writability gap is DISCLOSED beside the brief — with the tracking
    # artifact's content for the target repo — and the run proceeds. There is
    # no refusal path here on evidence.
    # EVERY member's gap, in `gaps`, at every set size (Story 20.99, #1077).
    # `gap` — the FIRST member's, computed from the deleted `candidate` — used
    # to sit beside `gaps`, byte-identical to `gaps[0]` minus its `index`. One
    # fact twice, under two names that both read as "the gap".
    #
    # The size condition went with it. It existed only because `gap` covered
    # the one-member case, and dropping it without dropping the condition would
    # have left a single-member selection disclosing no gap at all — the silent
    # omission the member record exists to prevent, arriving through the fix.
    by_id = {c.get("id"): c for c in cands}
    gaps = []
    for m in out.get("members") or []:
        g = _selection_gap(by_id.get(m.get("index")),
                           (map_data or {}).get("recording_target"))
        if g:
            gaps.append(dict(g, index=m.get("index")))
    if gaps:
        out["gaps"] = gaps
    elif out.get("candidate"):
        # THE ADOPTED-CANDIDATE PATH IS UNCHANGED and still discloses its gap.
        # That path (`:626-629`) is a different brief shape — the owner adopted
        # a proposed direction string rather than indexes, so it has no member
        # set — and #1077 is about the SET path, where `candidate` sat beside
        # `members` claiming to be the selection. Dropping the disclosure here
        # while removing the key there would fix a naming defect by creating an
        # evidence one.
        g = _selection_gap(out["candidate"],
                           (map_data or {}).get("recording_target"))
        if g:
            out["gap"] = g
    out["stage"] = "topic-map-brief"
    # THE NAMED STEP IDENTITY (Story 20.75 AC1): the act that produced this
    # brief, named, so the owner refers to it rather than to "the message
    # above". Owner-facing wording comes from the register seam.
    out["step"] = {"id": BRIEF_STEP_ID, "name": BRIEF_STEP_NAME,
                   "line": _brief_step_line()}
    # THE LIFECYCLE (AC5), stated whether or not an artifact is written: a
    # brief that was composed and not written is still `composed`, and saying
    # so is more honest than omitting the field.
    out["lifecycle"] = _brief_lifecycle(BRIEF_LIFECYCLE[0])
    out["next"] = ("draft-pipeline.py stage0 <framework> <sources...> --brief "
                   "<this brief> — the existing stage-0 path, unchanged")
    # THE DURABLE ARTIFACT (AC2/AC4). Written only when the caller passes a
    # path, exactly as `--view` works: the resolver owns the workspace and
    # this script writes where it is told, so no storage path is composed here
    # (D1). NOTHING DOWNSTREAM CHANGES (AC6) — the hand-off is still the brief
    # STRING into the existing stage-0 `--brief` path, and drafting never
    # learns that terrain produced it.
    path = os.path.abspath(args.out) if getattr(args, "out", None) else None
    if path:
        out["artifact"] = {
            "id": os.path.splitext(os.path.basename(path))[0],
            "path": path,
            "line": _brief_artifact_line(path),
            "reopen": f"topic-map-directions.py brief-open --at {path}",
            "read_back": ("by design — this is the owner's decision, not a "
                          "rendering; the never-read-back rule does not bind "
                          "here (CAP-3, 2026-07-31)")}
    # THE EDIT THAT PRODUCED THIS COMPOSITION (Story 20.77 AC2), recorded
    # beside the member set it produced, so a recomposition can be read
    # against the one it came from rather than only compared with it.
    if edit:
        out["edit"] = {
            "add": edit["add"], "drop": edit["drop"],
            "from": {"artifact": os.path.abspath(getattr(args, "from_brief")),
                     "indexes": list((base or {}).get("indexes") or []),
                     "brief": (base or {}).get("brief")},
            "note": ("inherited from the composition being edited — the note "
                     "is the owner's angle, not a claim over the set"
                     if inherited_note else "as recorded in this answer"),
            "claim": ("recomposed over the edited set; an adopted claim is "
                      "never carried across an edit, because a claim belongs "
                      "to the set it was composed over"),
        }
    # THE LOOP AT THE GATE (AC1/AC3/AC4). Carried wherever there is a member
    # set to edit — including the FIRST composition, or the loop could never
    # start. A free-form brief has no set, and claiming an editable one would
    # be shape without content.
    if out.get("indexes"):
        out["iteration"] = _iteration_block(out, prior, out.get("edit"), path)
    if path:
        try:
            # THE ARTIFACT PERSISTS THE DECISION; THE STDOUT PAYLOAD CARRIES
            # THE GATE (Story 20.93, #1048/#1049). `out` is unchanged and is
            # what gets printed — the gate sees exactly what it saw before,
            # undiminished, including the COMPLETE unranked substitution pool
            # the consultant's rule 4 requires. What is written is the decision
            # record alone.
            write_brief_artifact(path, _decision_record(out))
        except OSError as exc:
            return _err(f"could not write the brief artifact at {path}: {exc}")
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


# --- The brief persists the DECISION, not the gate inputs (Story 20.93) -------
#
# THE GROUND IS CLASS, NOT VOLUME. Measured before deciding: `brief-adopted.json`
# was 161,693 B of which `consultant.substitution_candidates` was 130,493 B
# (88.5%), against ~10 KB of decision content. But all terrain runs together
# total 3.4 MB, so nothing here is justified on disk. The artifact is *the
# durable record of a selection decision*, and gate INPUTS are not that: they
# are recomputable from `map.json` at the recorded pin, which
# `docs/storage-architecture.md` retains in the same workspace ("discharged by
# relocation, not by GC") — and that retention is exactly what makes dropping
# them safe.
#
# WHAT IS DROPPED, and only this: `consultant` (subject + the complete
# substitution pool), `candidate_theses.inputs` (the same member records
# again), and `recomposition` (the members' served claims, a third time). The
# four-copy duplication one run produced across `brief.json`,
# `brief-result.json`, `brief-adopted.json` and `brief-adopted-result.json`
# resolves as a CONSEQUENCE of that (AC8) — no deduplication mechanism exists
# or is needed, and if one seemed necessary this rule was not fully applied.
GATE_ONLY_BLOCKS = ("consultant", "recomposition")


def _decision_record(payload):
    """The brief artifact: the decision, and nothing recomputable.

    A shallow copy — the payload printed to stdout is untouched, because the
    gate must see what it always saw (AC2). Shrinking the artifact must never
    shrink what reaches the owner.
    """
    rec = {k: v for k, v in payload.items() if k not in GATE_ONLY_BLOCKS}
    ct = rec.get("candidate_theses")
    if isinstance(ct, dict):
        rec["candidate_theses"] = {k: v for k, v in ct.items()
                                   if k != "inputs"}
    return rec


def _recompose_gate_blocks(payload, at):
    """The dropped gate blocks, recomposed from `map.json` at the recorded pin.

    THE STORY QUESTION IN AC3, DECIDED: `brief-open` RECOMPOSES rather than
    simply not printing. Not printing is simpler and matches the artifact's new
    definition, but it makes re-opening a strictly poorer act than it was —
    and the whole reason dropping the blocks is safe is that `map.json` is
    retained beside the brief, so a path that never exercises that retention
    leaves the safety argument untested. Recomposing keeps `brief-open` output
    equivalent to today's AND turns the premise into a running code path.

    It is CONDITIONAL AND HONEST. The map must sit in the artifact's own
    workspace and carry the pin the brief recorded; on any other outcome the
    blocks are stated as absent with the reason, never approximated. A
    recomposition that is merely plausible is worse than none.
    """
    note = {"attempted": True, "recomposed": [], "from": None, "why": None}
    ws = os.path.dirname(os.path.abspath(at))
    map_path = os.path.join(ws, "map.json")
    if not os.path.isfile(map_path):
        note["why"] = (
            f"no map.json in this brief's workspace ({ws}), so the gate-time "
            "blocks cannot be recomposed. They are not printed rather than "
            "approximated — the artifact records the decision, and the inputs "
            "are recomputable only where the map they were computed from is "
            "still retained.")
        return note
    try:
        map_data = load_map(map_path)
    except SystemExit:
        note["why"] = f"map.json at {map_path} is unreadable"
        return note
    map_pin = (map_data.get("coverage") or {}).get("pin")
    want = payload.get("pin")
    if want and map_pin and want != map_pin:
        note["why"] = (
            f"the brief was composed at {want} and the retained map is at "
            f"{map_pin}. Recomposing across a moved pin would present material "
            "the owner never saw as though they had, so the blocks are stated "
            "absent instead.")
        return note
    cands = candidates(map_data)
    by_id = {c.get("id"): c for c in cands}
    indexes = list(payload.get("indexes") or [])
    matches = [by_id[i] for i in indexes if i in by_id]
    if len(matches) != len(indexes) or not matches:
        note["why"] = (
            "the recorded member set does not fully resolve against the "
            "retained map, so the blocks are stated absent rather than "
            "recomposed over a different set.")
        return note
    note["from"] = map_path
    note["pin"] = map_pin
    if len(matches) > 1:
        payload["consultant"] = _consultant_block(matches, cands, map_data)
        note["recomposed"].append("consultant")
        ct = payload.get("candidate_theses")
        if isinstance(ct, dict):
            ct["inputs"] = [_member_record(m) for m in matches]
            note["recomposed"].append("candidate_theses.inputs")
    payload["recomposition"] = {
        "authoring": "machine-composed at render time, marked",
        "over": [m.get("id") for m in matches],
        "claims": [m.get("gloss") or m.get("direction") for m in matches]}
    note["recomposed"].append("recomposition")
    return note


def _brief_label(payload):
    """An owner-meaningful name for a brief, DERIVED and never stored (AC7).

    Date, member set, and the thesis's first words — every part computed from
    fields the artifact already carries. No naming store, no id field and no
    slug is added: a stored name is a second identity to keep in sync with the
    one the path already provides.
    """
    life = payload.get("lifecycle") or {}
    when = ""
    for h in reversed(list(life.get("history") or [])):
        if h.get("at"):
            when = str(h["at"])[:10]
            break
    ids = list(payload.get("indexes") or [])
    if not ids and payload.get("index"):
        ids = [payload["index"]]
    who = ", ".join(str(i) for i in ids[:3]) + ("…" if len(ids) > 3 else "")
    text = str((payload.get("thesis") or {}).get("text")
               or payload.get("adopted_claim")
               or payload.get("brief") or "").strip()
    words = " ".join(text.split()[:8])
    parts = [p for p in (when, who and f"[{who}]", words) if p]
    return " — ".join(parts) or "an unnamed brief"


BRIEF_ARTIFACT_NAME = "brief.json"


def _resolve_newest_brief(root=None):
    """The brief a bare `open the brief` reaches (Story 20.92, #1042).

    THE RULE IS STATED AND DETERMINISTIC, never a heuristic the owner cannot
    predict: the NEWEST terrain run workspace — run ids are timestamps, so the
    newest is the last one in sorted order, and the `latest` symlink is skipped
    because it is a shorthand rather than a distinct run — and inside it the
    artifact named `brief.json`.

    A workspace may hold several brief artifacts: the edit-set iteration loop
    writes each recomposition to its own name in the same workspace. Those are
    NOT guessed between. `brief.json` is the composed brief; when it is absent
    the other brief-shaped artifacts present are NAMED so the owner picks one,
    which is a stated ambiguity rather than a silent pick.

    Returns `(path, why)`. `path` is None when nothing resolves, and `why` then
    says so plainly — this never falls through to starting Step 0 and never
    composes anything.
    """
    # THE RESOLVER OWNS THE LAYOUT (D1). No storage path is composed here: the
    # run root is ASKED FOR, exactly as every other caller asks for it, and
    # only the run-id ordering and the artifact name are this function's.
    import subprocess
    cmd = [sys.executable,
           os.path.join(os.path.dirname(os.path.realpath(__file__)),
                        "resolve-paths.py"),
           "terrain-runs-root"] + (["--root", root] if root else [])
    try:
        base = subprocess.run(cmd, capture_output=True, text=True,
                              check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        return None, f"the terrain run root could not be resolved ({exc})"
    if not os.path.isdir(base):
        return None, ("no terrain run workspace exists yet, so there is no "
                      "brief to open. A brief comes from a terrain sitting: "
                      "say `show the terrain` to start one.")
    runs = sorted(r for r in os.listdir(base)
                  if not os.path.islink(os.path.join(base, r))
                  and os.path.isdir(os.path.join(base, r)))
    if not runs:
        return None, ("no terrain run workspace exists yet, so there is no "
                      "brief to open. Say `show the terrain` to start one.")
    ws = os.path.join(base, runs[-1])
    path = os.path.join(ws, BRIEF_ARTIFACT_NAME)
    if os.path.isfile(path):
        return path, (f"the newest terrain run workspace ({runs[-1]}) and its "
                      f"{BRIEF_ARTIFACT_NAME}")
    others = sorted(f for f in os.listdir(ws)
                    if f.startswith("brief") and f.endswith(".json"))
    if others:
        return None, (
            f"the newest terrain run workspace ({runs[-1]}) holds no "
            f"{BRIEF_ARTIFACT_NAME}, but it does hold "
            f"{', '.join(others)}. Those are recompositions from the "
            "edit-set loop and are not guessed between — name the one you "
            "want.")
    return None, (f"the newest terrain run workspace ({runs[-1]}) holds no "
                  "brief artifact, so there is nothing to open. A brief is "
                  "written when a selection is composed with `--out`.")


def cmd_brief_open(args):
    """Re-open a written brief (Story 20.75 AC4/AC5).

    The re-entry point the gate advertises: the owner returns to a brief by
    the path they were told, and optionally records the lifecycle transition
    the return represents. Transitions are FORWARD-ONLY along
    `composed → inspected → adopted` — a backwards move is refused rather than
    recorded, because a lifecycle that can run backwards states nothing.
    """
    # THE NAMED TRIGGER'S BARE FORM (Story 20.92, #1042). With no path the
    # brief is RESOLVED by the stated rule rather than asked for: an owner
    # holding no path had no words that reached this move at all. Nothing else
    # about the move changes — this is discovery for an existing capability,
    # not a new one.
    at = getattr(args, "at", None)
    resolved_by = None
    if not at:
        at, why = _resolve_newest_brief(getattr(args, "root", None))
        if not at:
            # Said PLAINLY, and it does not start Step 0 or compose anything:
            # a trigger that silently walked the screens would answer a
            # question the owner did not ask.
            return _err(f"no brief to open — {why}")
        resolved_by = why
    try:
        payload = read_brief_artifact(at)
    except (OSError, ValueError) as exc:
        return _err(f"unreadable brief artifact at {at}: {exc}")
    args.at = at
    life = payload.get("lifecycle") or _brief_lifecycle(BRIEF_LIFECYCLE[0])
    state = life.get("state")
    if args.state:
        try:
            now = BRIEF_LIFECYCLE.index(state)
        except ValueError:
            now = -1
        if BRIEF_LIFECYCLE.index(args.state) < now:
            return _err(
                f"the brief is already `{state}`; `{args.state}` is earlier in "
                f"{' → '.join(BRIEF_LIFECYCLE)}. The lifecycle only moves "
                f"forward — compose a new brief instead of rewinding this one.")
        history = list(life.get("history") or [])
        if args.state != state:
            history.append({"state": args.state})
        state = args.state
        payload["lifecycle"] = _brief_lifecycle(state, history)
        try:
            write_brief_artifact(args.at, payload)
        except OSError as exc:
            return _err(f"could not record the transition at {args.at}: {exc}")
    else:
        payload["lifecycle"] = _brief_lifecycle(state, life.get("history"))
    payload["lifecycle"]["line"] = _brief_lifecycle_line(state)
    # THE OWNER-MEANINGFUL LABEL, derived here and never written (AC7): the
    # transition above wrote the artifact, and this is composed after it so
    # nothing derived can leak into what is stored.
    payload["label"] = _brief_label(payload)
    # THE GATE-TIME BLOCKS, recomposed from the retained map (AC3/AC4) — or
    # stated absent, with the reason, when the map is not there to recompose
    # from. Never approximated.
    payload["recomposed_from_map"] = _recompose_gate_blocks(payload, at)
    payload["opened"] = {
        "at": os.path.abspath(at),
        # How this brief was reached, stated: a resolved open says which rule
        # resolved it, so the owner can predict the next one.
        "resolved_by": resolved_by or "the path given",
        # THE STANDING EXITS (Story 20.92 AC6). An entry INTO the surface
        # offers what every other gate on it offers — a trigger that landed the
        # owner somewhere with no way onward would be a side door out of the
        # surface rather than a door into it.
        "exits": ["edit the member set — +Lxx −Lyy → recompose",
                  "back to the member list",
                  "name your own direction",
                  "stop here"],
    }
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


def cmd_cover(args):
    """THE PLACEMENT COUNT, RUN AFTER COMPOSITION (Story 20.78 AC3/AC6).

    ITS OWN INVOCATION, DELIBERATELY. The count cannot live inside the
    composition it checks — a composer that cannot omit in principle can still
    omit in fact, and a check reading the composer's own inputs would confirm
    the composer's own belief about them. So the composed candidates arrive as
    a FILE, written by whoever composed them, and this reads what was actually
    emitted against the member set the BRIEF records.

    A refusal returns the WHOLE proposal to its composer. It never drops one
    candidate and offers the rest: reducing what reaches the owner is the
    narrowing the second-proposer boundary bars, and it is not made admissible
    by being done in the name of completeness.
    """
    try:
        with open(args.composed, encoding="utf-8") as fh:
            composed = json.load(fh)
    except (OSError, ValueError) as exc:
        return _err(f"unreadable composed candidates at {args.composed}: {exc}")
    try:
        brief = read_brief_artifact(args.from_brief)
    except (OSError, ValueError) as exc:
        return _err(
            f"unreadable brief artifact at {args.from_brief}: {exc}. The cover "
            "is counted against the OWNER'S selected set, which only the brief "
            "records — counting against the composition's own idea of the set "
            "would confirm whatever it believed.")
    report = verify_cover(composed, brief, os.path.abspath(args.from_brief))
    report["stage"] = "topic-map-cover"
    report["counted"] = "after-composition"
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if report.get("refusals"):
        for line in report["refusals"]:
            print(f"refused: {line}", file=sys.stderr)
        return 1
    return 0


def cmd_journey_inputs(args):
    """The judgment inputs for the journey-similarity substrate (#891).

    Emitted as data so the composer judges from SERVED arcs and nothing else.
    The count is carried so the caller can verify the grouping it gets back
    covers what it was given.
    """
    m = load_map(args.map)
    axis = getattr(args, "axis", "tag") or "tag"
    strands = _axis_strands(m, str(args.tag).strip(), axis)
    if not strands:
        return _err(f"no Strand sits under {args.tag!r} at this pin")
    inputs = journey_similarity_inputs(strands, str(args.tag).strip())
    print(json.dumps({"kind": "journey-similarity-inputs",
                      "member": str(args.tag).strip(), "axis": axis,
                      "count": len(inputs),
                      "served": sum(1 for x in inputs if x["served"]),
                      "substrate": JOURNEY_SUBSTRATE,
                      "offered": JOURNEY_SUBSTRATE in SUBSTRATES,
                      "inputs": inputs}, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    ax = sub.add_parser("axis", help="Screen 1: the two served axis listings "
                        "(by tag, by topic) with per-member Strand counts, "
                        "as JSON + payload")
    ax.add_argument("--map", required=True)
    mb = sub.add_parser("member", help="Screen 2: one axis member's Strands, "
                        "whole, in presentation-only sections")
    mb.add_argument("--map", required=True)
    mb.add_argument("--tag", required=True, metavar="MEMBER",
                    help="the member's name, within the axis named by --axis")
    mb.add_argument("--axis", choices=[a["key"] for a in AXES], default="tag",
                    help="which axis MEMBER belongs to (default: tag). The two "
                         "vocabularies overlap by name, so this is what keeps "
                         "a member unambiguous.")
    # Journey similarity is OFFERED (Story 20.82, #1031) — its measurement gate
    # ran on 2026-07-31 and the owner verdicted pass, so naming it here is an
    # ordinary choice rather than a measurement-only reach. `--grouping`
    # carries the model's proposal; without one every Strand lands in the
    # residue, which is the honest empty state rather than an invented
    # grouping. The default is unchanged: offering is not promoting.
    mb.add_argument("--substrate", default=SUBSTRATE_DEFAULT,
                    choices=sorted(set(SUBSTRATES) | set(SUBSTRATES_UNOFFERED)),
                    help="grouping substrate (default: %(default)s). Any "
                         "substrate still behind the offering gate is "
                         "reachable for its measurement run only, until an "
                         "owner verdict admits it.")
    mb.add_argument("--claims", metavar="JSON",
                    help='the `in common:` claims you composed, as {"G1": '
                         '"..."}. Passing them returns the FINAL screen — ids, '
                         "claims and rows together — which is what you relay: "
                         "the rows are never retyped by hand (#976/#977). "
                         "Carried VERBATIM, never recomposed; a group whose "
                         "claim is absent says so. Omit for the pre-20.66 "
                         "listing, byte-identical.")
    mb.add_argument("--subgroups", metavar="JSON",
                    help="the semantic subdivisions you ADOPTED, as {\"G10\": "
                         "[{\"claim\": \"...\", \"strands\": [\"slug\", ...]}, "
                         "...]} (Story 20.86, #1041). Send a group only when "
                         "its subgroup claims came out measurably TIGHTER than "
                         "the parent's; a group whose trial merely restated "
                         "the parent is a leaf and is simply omitted. A "
                         "subdivision partitions the parent exactly — nothing "
                         "added, dropped, or moved between parent groups — and "
                         "a part may carry its own `subgroups` when its claim "
                         "degenerates into an enumeration. No member count "
                         "triggers this and none is accepted.")
    mb.add_argument("--view", metavar="PATH",
                    help="the View file's path, as `resolve-paths.py` resolved "
                         "it. Pass it ALWAYS: the composer switches on the "
                         "member's size and names this path only when the "
                         "member is over the screen budget, so passing it is "
                         "not a decision that the screen overflowed. Over "
                         "budget without it, the screen still summarises — the "
                         "switch never fails open — but the rows are nowhere.")
    mb.add_argument("--grouping", metavar="JSON",
                    help="a model-proposed grouping for a judged substrate: "
                         "[{\"in_common\": str, \"members\": [slug, ...]}]. "
                         "Placement only — any ordering it carries is ignored "
                         "and any Strand it omits is re-attached.")
    # THE FULL REPORT (Story 20.56, #938). Inspection by group id — a
    # different operation from selection by Strand index, and they stay
    # different: `G` is a display kind conferring no selection authority.
    rp = sub.add_parser("report", help="a FULL REPORT for named group ids: "
                        "each group's claim, then its members whole")
    rp.add_argument("--map", required=True)
    rp.add_argument("--tag", required=True, metavar="MEMBER",
                    help="the member whose screen the group ids were read from")
    rp.add_argument("--axis", choices=[a["key"] for a in AXES], default="tag")
    rp.add_argument("--groups", required=True, metavar="IDS",
                    help="the group ids to report, comma- or space-separated "
                         "(for example 'G1,G3'). Rendered separately, in the "
                         "order asked — never flattened into a union.")
    rp.add_argument("--claims", metavar="JSON",
                    help='the claims the screen already composed, as {"G1": '
                         '"..."}. Carried VERBATIM — this path never '
                         "recomposes a claim, and a group whose claim is not "
                         "carried states the absence instead.")
    rp.add_argument("--subgroups", metavar="JSON",
                    help="the subdivisions the screen adopted, in the shape "
                         "`member --subgroups` takes (Story 20.87, #1041). "
                         "Carried VERBATIM like the parent claims, and the "
                         "parent claim stays ABOVE them: a subdivided group "
                         "shows why its Strands share a screen at all, then "
                         "what separates the strata inside them.")
    rp.add_argument("--grouping", metavar="JSON",
                    help="the same model-proposed grouping the screen was "
                         "composed with, so the ids resolve to the same "
                         "sections")
    ji = sub.add_parser("journey-inputs",
                        help="the judgment inputs for the journey-similarity "
                             "substrate: each Strand's SERVED arc, verbatim")
    ji.add_argument("--map", required=True)
    ji.add_argument("--tag", required=True, metavar="MEMBER")
    ji.add_argument("--axis", choices=[a["key"] for a in AXES], default="tag")
    c = sub.add_parser("candidates", help="candidate directions as JSON")
    c.add_argument("--map", required=True, help="assembled map JSON, or - for stdin")
    pa = sub.add_parser("payload", help="the one screen, as a proposal payload")
    pa.add_argument("--map", required=True, help="assembled map JSON, or - for stdin")
    pa.add_argument("--view", metavar="PATH",
                    help=f"where to render the View when the map exceeds the "
                         f"screen budget ({SCREEN_BUDGET} subtopics). Pass the "
                         f"run workspace's {VIEW_FILENAME}. A map at or under "
                         f"the budget writes nothing and the screen is "
                         f"unchanged. The View is WRITE-ONLY: nothing reads it "
                         f"back.")
    v = sub.add_parser("view", help="render the View file alone")
    v.add_argument("--tag", metavar="MEMBER",
                   help="render ONE member's whole view instead of the terrain "
                        "View: the complete sectioning the screen summarises")
    v.add_argument("--axis", choices=[a["key"] for a in AXES], default="tag")
    v.add_argument("--substrate", default=SUBSTRATE_DEFAULT,
                   choices=sorted(set(SUBSTRATES) | set(SUBSTRATES_UNOFFERED)))
    v.add_argument("--grouping", metavar="JSON")
    v.add_argument("--claims", metavar="JSON",
                   help='the `in common:` claims you composed, as {"G1": '
                        '"..."}, so the View carries them too. Same contract '
                        "as `member --claims`: carried VERBATIM, never "
                        "recomposed, and a group whose claim is absent says so "
                        "rather than having one invented.")
    v.add_argument("--subgroups", metavar="JSON",
                   help="the subdivisions the screen adopted, in the shape "
                        "`member --subgroups` takes. The View is the surface "
                        "that holds the WHOLE rendering, so the hierarchy "
                        "belongs here too — three surfaces showing one "
                        "grouping differently is the defect #1039 records.")
    v.add_argument("--map", required=True, help="assembled map JSON, or - for stdin")
    v.add_argument("--out", required=True, metavar="PATH",
                   help=f"where to write it (the run workspace's {VIEW_FILENAME})")
    b = sub.add_parser("brief", help="the owner's outcome as the stage-0 brief")
    src = b.add_mutually_exclusive_group(required=True)
    src.add_argument("--answer",
                     help="the recorded answer JSON, or - for stdin")
    src.add_argument("--payloads",
                     help="the run's presented-payloads.jsonl; the answer row "
                          "is selected here, never hand-extracted (#831)")
    b.add_argument("--ask-id",
                   help="with --payloads: select this ask's answer row "
                        "(default: the latest answer row)")
    b.add_argument("--map", help="the same map, so an adopted candidate resolves")
    b.add_argument("--from", dest="from_brief", metavar="PATH",
                   help="the composition this one EDITS (Story 20.77): the "
                        "brief artifact whose member set the answer's `edit` "
                        "(`+L12 −L3`) applies to. Its `--out` must land in the "
                        "SAME run workspace — retention is within-sitting, and "
                        "an edit across workspaces is refused.")
    b.add_argument("--out", metavar="PATH",
                   help=f"write the brief as a durable artifact here — pass "
                        f"the run workspace's {BRIEF_FILENAME} (Story 20.75). "
                        f"Unlike the View, this artifact IS read back: it is "
                        f"the owner's decision, and re-opening it with "
                        f"`brief-open` is the requirement, not a cache. The "
                        f"stage-0 hand-off is unchanged either way.")
    bo = sub.add_parser("brief-open",
                        help="re-open a written brief, and optionally record "
                             "its lifecycle transition")
    bo.add_argument("--at", metavar="PATH",
                    help="the artifact written by `brief --out`. OPTIONAL "
                         "(Story 20.92, #1042): with no path the newest "
                         "terrain run workspace's brief.json is resolved by a "
                         "stated rule — run ids are timestamps, so the newest "
                         "sorts last, and a workspace holding only "
                         "recompositions names them rather than guessing "
                         "between them. With no brief anywhere it says so "
                         "plainly and starts nothing.")
    bo.add_argument("--root", metavar="PATH",
                    help="host-repo root, when resolving the newest brief "
                         "from somewhere other than the host working tree")
    bo.add_argument("--state", choices=list(BRIEF_LIFECYCLE[1:]),
                    help="record the transition this return represents "
                         f"({' → '.join(BRIEF_LIFECYCLE)}); forward-only")
    cv = sub.add_parser("cover",
                        help="count the placement cover of COMPOSED candidate "
                             "theses (or a proposed partition) against the "
                             "brief's member set — after composition")
    cv.add_argument("--composed", required=True, metavar="PATH",
                    help="the composed candidates as JSON: `kind` is "
                         "`candidate-theses` (2–3 candidates, each with its "
                         "`places`, `omits` and `grounds`) or `partition` "
                         "(k groups, plus any `dropped` the owner named). "
                         "Read as EMITTED — never re-derived from the inputs "
                         "it was composed from.")
    cv.add_argument("--from", dest="from_brief", required=True, metavar="PATH",
                    help="the brief artifact whose `members` the cover is "
                         "counted against (written by `brief --out`)")
    args = p.parse_args(argv)
    return {"candidates": cmd_candidates, "payload": cmd_payload,
            "view": cmd_view, "brief": cmd_brief,
            "brief-open": cmd_brief_open, "cover": cmd_cover,
            "axis": cmd_axis, "member": cmd_member,
            "report": cmd_report,
            "journey-inputs": cmd_journey_inputs}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
