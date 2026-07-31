#!/usr/bin/env python3
"""terrain_select.py — resolving what the owner SELECTED, and disclosing what
the selection costs (Story 20.80, #1029; SPEC-writing-assistant, the 2026-07-31
(#1025) amendment).

WHY THIS MODULE EXISTS. `topic-map-directions.py` is HYPHENATED and therefore
unimportable. The #1025 amendment dissolves that constraint rather than working
around it a fifth time: the hyphenated path keeps its name and carries argparse
and dispatch, and the composition moves into importable siblings like this one.

WHAT IT CONTAINS: everything between the owner's typed answer and a resolved set
of Strand indexes — the ordered (operator, id) terms and the set arithmetic
(`_selection_terms`, `_selected_indexes`), the G-id expansion at the screen that
minted it (`_screen_sections`, `_group_expander`), the composite pin's
which-half-moved message (`_which_half_moved`), and the writability gap a
non-matched selection discloses (`_selection_gap`). The set operators travel
with the parser that reads them.

The boundary is deliberate: this module RESOLVES a selection, it never composes
a brief from one. `_brief_from_index` and `brief_from_answer` stay with the
dispatch that reaches them.

This is a MOVE, not a rewrite: every definition below is the one that stood in
`topic-map-directions.py`, unchanged, and composed output is byte-identical for
the same inputs (Story 20.80 AC4).
"""

import re
import sys

import os

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
# The screen a G-id was read at is re-resolved through the member surface's own
# sectioning, at the same pin, so expansion reads the screen that defined the
# group rather than a fresh grouping of the same material.
from terrain_members import (  # noqa: E402
    SUBSTRATE_DEFAULT,
    _err,
    member_sections,
)

def _selection_gap(candidate, recording_target):
    """The gap disclosure a non-matched element selection yields (#799).

    Evidence-independence, enforced end to end: the verdict decided nothing
    about APPEARING, and it decides nothing about DRAFTING either. Selecting
    an element whose episode no declared source carries yields this block —
    the disclosure plus the NEEDS-RECORDING tracking artifact's content for
    the target repo (an Issue, or an append under a NEEDS-RECORDING heading
    in the declared journey doc) — and the brief is composed exactly as for a
    matched one. NEVER a refusal: a mechanism that stops drafting here has
    stopped being an assistant (owner ruling, #799).

    AN EPISODE THE SYSTEM IS CARRYING IS NOT AN ABSENT ONE (Story 20.91, #1044
    AC2). The host-repo journey join is a fact about the HOST REPO and it is
    KEPT, under `host_join`; what was wrong was REPORTING it as the episode's
    absence while the hub was serving that very episode as the Strand's arc —
    three selected Strands were disclosed `episodic-unrecorded` in one sitting
    with their arcs served the whole time. So a served arc changes what this
    block SAYS, and changes nothing about what it DOES:

      * the arc is carried, quoted at its cite — never re-expressed here;
      * `episode.served` and `not_served_reason` keep 20.90's two kinds apart,
        so *"no arc exists"* and *"no arc arrived"* remain different findings
        and never collapse into one;
      * the NEEDS-RECORDING task is still minted (AC4). Recording the episode
        host-side is what eventually feeds EVIDENCE; the served arc is
        material that already existed and was simply never consumed. Adjacent,
        not the fix — neither closes the other, and dropping the task here
        would quietly make an arc a substitute for evidence;
      * the article floor is untouched (AC3): an arc is material, not a Fact.
        Repositories stay harvest scope and never evidence binding, and a
        served arc satisfies nothing at the ship gate.
    """
    if not candidate or candidate.get("kind") != "element":
        return None
    u = candidate.get("usability") or {}
    verdict = u.get("verdict")
    if not verdict or verdict == "matched":
        return None
    target = recording_target or {}
    slug = str(candidate.get("slug") or "").strip()
    arc = candidate.get("journey")
    arc = arc if isinstance(arc, str) and arc.strip() else None
    gap = {"verdict": verdict, "slug": slug,
           "checked": u.get("checked") or [],
           "drafting": "proceeds — the verdict is a disclosure, never a gate"}
    # The EPISODE's own state, stated beside the host join and never merged
    # into it. Carried on every gap, including `no-episode` and
    # `cannot-determine`, so a reader never has to infer which of the two
    # lookups a silence belongs to.
    gap["episode"] = {
        "served": arc is not None,
        "arc": arc,
        "arc_cite": candidate.get("journey_cite") if arc else None,
        "not_served_reason": (None if arc
                              else candidate.get("journey_unavailable")),
    }
    if verdict == "episodic-unrecorded" and arc:
        # NOT an unrecorded episode. The mechanical host-repo verdict is kept
        # verbatim where it belongs — as a fact about the host repo — and the
        # reported finding becomes the true one.
        gap["verdict"] = "episode-served"
        gap["host_join"] = {"verdict": verdict,
                            "checked": u.get("checked") or []}
        gap["disclosure"] = (
            "the hub serves this element's episode as its journey arc, and "
            "the arc crosses into drafting as declared source material at the "
            "recorded pin — so this is NOT an unrecorded episode. What no "
            "declared source in the target repo carries is a HOST-SIDE "
            "recording of it, and that gap is real and unchanged: recording "
            "the episode there is what eventually feeds evidence, while the "
            "served arc is material that already existed and was simply never "
            "consumed. The two are adjacent, not substitutes, and neither "
            "closes the other. The draft proceeds, and the article floor is "
            "unchanged — an arc is material, never a Fact.")
        gap["needs_recording"] = {
            "slug": slug,
            "target_repo": target.get("repo"),
            "target_file": target.get("file"),
            "heading": "NEEDS-RECORDING",
            "entry": (f"{slug} — selected on the terrain (the hub serves its "
                      "arc; no declared source here carries the episode); "
                      "record the episode here so the next run can match it"),
        }
        return gap
    if verdict == "cannot-determine":
        gap["disclosure"] = (
            "the evidence lookup could not determine whether a declared "
            f"source carries this ({u.get('reason') or 'no join key'}); "
            "an absence is asserted only where it was established, so no "
            "recording task is minted from a lookup that did not look")
        return gap
    if verdict == "no-episode":
        gap["disclosure"] = (
            "no episode is locatable for this element, so the draft offers it "
            "on the owner-attributed framing tier: your framing contribution, "
            "stated as such, never sourced claims")
        gap["tier"] = "owner-attributed framing (Story 17.1)"
    else:
        gap["disclosure"] = (
            "the hub records this element but no declared source in the "
            "target repo carries its episode; the draft proceeds, and the "
            "gap is recorded so the next run can locate evidence")
    gap["needs_recording"] = {
        "slug": slug,
        "target_repo": target.get("repo"),
        "target_file": target.get("file"),
        "heading": "NEEDS-RECORDING",
        "entry": (f"{slug} — selected on the terrain "
                  f"({verdict}); record the episode here so the next "
                  f"run can match it"),
    }
    return gap


def _which_half_moved(answer, map_data):
    """Which input moved, for the mismatch message — named, or honestly not.

    The composite pin proves that SOMETHING moved; it cannot by itself say
    what. When the recorded answer carried the halves, this names them. When
    it did not (a selection made from the View, which never carries the hub
    half), it says so — an unnameable half is disclosed, never inferred.
    """
    cov = map_data.get("coverage", {}) or {}
    a_dest = str(answer.get("destination_pin") or "").strip()
    a_hub = str(answer.get("hub_pin") or "").strip()
    if not a_dest and not a_hub:
        return ("Which input moved is not recorded in the selection, so it "
                "cannot be named here.")
    moved = []
    if a_dest and a_dest != (cov.get("destination_pin") or ""):
        moved.append("the destination repository")
    if a_hub and a_hub != (cov.get("hub_pin") or ""):
        moved.append("the hub")
    if not moved:
        return ("Neither recorded half differs, so the change is in a part "
                "the selection did not record.")
    return f"Moved: {' and '.join(moved)}."


# The set operators the selection accepts (Story 20.76, #996; SPEC-terrain
# CAP-3 §"G-ids are owner-facing SHORTHAND that expands at the screen"). There
# was no set arithmetic here at all before this story: `minus` is new syntax,
# added because a selection typed off a Full Report is naturally "that group,
# without the two that do not belong".
ADD_OPS = ("+", "plus")
REMOVE_OPS = ("-", "−", "minus", "without", "except")


def _selection_terms(answer):
    """The owner's typed selection as ORDERED (operator, id) terms.

    `index` is accepted as a list or as one string naming several — the
    payload shape is the owner's convenience — and the string form is split on
    the same `[,\\s]+` it always was. What is new is that a token may be a set
    OPERATOR rather than an id: `G4 + L26, minus L48` reads as add-add-remove.

    An operator token governs every id AFTER it until the next operator, so
    `minus L48, L50` removes both; the attached forms `+L26` / `-L48` govern
    their own token only and leave the standing operator alone. Absent any
    operator the selection reads exactly as it did before this story existed —
    a plain list of ids, all added.
    """
    raw = answer.get("index")
    parts = raw if isinstance(raw, (list, tuple)) else re.split(
        r"[,\s]+", str(raw or ""))
    terms, op = [], "add"
    for p in parts:
        p = str(p).strip()
        if not p:
            continue
        low = p.lower()
        if low in ADD_OPS:
            op = "add"
            continue
        if low in REMOVE_OPS:
            op = "remove"
            continue
        if len(p) > 1 and p[0] in "+-−":
            terms.append(("remove" if p[0] in "-−" else "add",
                          p[1:].strip()))
            continue
        terms.append((op, p))
    return terms


def _selected_indexes(answer, expand=None):
    """The owner's selection as a SET of Strand indexes, however assembled
    (Story 20.54, #937; set arithmetic and G-id expansion, Story 20.76, #996).
    Returns `(selected, named)`.

    A selection is a set because exploring is how the owner decides what to
    write about: pointing at the Strands that belong together and having the
    brief composed from exactly those is the outcome the terrain exists for,
    and a single index is that set's degenerate case, not a different
    operation.

    EXPAND-THEN-SET-ARITHMETIC (Story 20.76 AC2): `expand` maps one typed
    token to the ids it names — identity for a Strand index, the group's
    members for a G-id — and the arithmetic runs over the expanded ids, in
    order. That order matters: `G4 minus L48` must drop L48 when L48 is one of
    G4's members, which it can only do if G4 became its members first.

    `selected` is the resulting set in the owner's order, de-duplicated: a
    repeated index is one member, and reordering their pointers would quietly
    restate what they chose. `named` is every id the selection MENTIONED,
    added or removed — carried so a removed id that names no Strand is
    refused rather than silently doing nothing, which is the same rule as NO
    named index being silently dropped.
    """
    selected, named = [], []
    for op, token in _selection_terms(answer):
        for i in (expand(token) if expand else [token]):
            if i not in named:
                named.append(i)
            if op == "remove":
                if i in selected:
                    selected.remove(i)
            elif i not in selected:
                selected.append(i)
    return selected, named


def _screen_sections(answer, map_data):
    """The screen the ids were read at, re-resolved at its own pin.

    A G-id is meaningless without the screen that minted it, so the answer
    records that screen — `member` (or `tag`) plus `axis`, and `substrate` /
    `grouping` when the screen used a non-default one. The pin is already
    proven equal to the map's before this runs, and `member_sections` is
    deterministic at a pin, so this IS the screen that defined the groups
    rather than a fresh grouping of the same material.

    Returns `None` when the answer records no screen — the honest answer is
    that this screen cannot be shown to have defined anything, which the
    caller turns into a refusal rather than a guess.
    """
    member = str(answer.get("member") or answer.get("tag") or "").strip()
    if not member or map_data is None:
        return None
    axis = str(answer.get("axis") or "tag").strip() or "tag"
    substrate = str(answer.get("substrate") or SUBSTRATE_DEFAULT).strip()
    grouping = answer.get("grouping")
    try:
        return member_sections(map_data, member, axis, substrate=substrate,
                               grouping=grouping)
    except KeyError:
        raise SystemExit(_err(
            f"the selection records substrate {substrate!r}, which names no "
            f"grouping substrate. The screen's group ids cannot be resolved "
            "against a substrate that did not produce them."))


def _group_expander(answer, cands, map_data):
    """A typed G-id EXPANDS to its member Strand indexes (Story 20.76, #996).

    The reasoning the old refusal carried survives exactly, re-scoped: `G` is
    a DISPLAY kind conferring no selection authority (SPEC-terrain, the
    display-kind clause), addressing INSPECTION and never selection. A group
    id is per-screen and per-pin and is gone when the screen is — so it may be
    TYPED and must never be RECORDED. Expansion is therefore a typing
    convenience over ids the owner just read: from this point only the members
    exist, the selection stays per-Strand, and nothing downstream can tell an
    expanded selection from the same one typed member by member. That is what
    keeps grouping presentation-only instead of a gate — no group is SELECTED
    here, its members are.

    Expansion happens AT THE SCREEN THAT DEFINED THE GROUP. A G-id this
    screen and pin did not define is refused with the reason named, exactly as
    a pin mismatch is: an id resolved against some other grouping would hand
    the owner a set they never read.
    """
    by_slug = {c.get("slug"): c.get("id") for c in cands
               if c.get("kind") == "element"}
    state = {}

    def expand(token):
        if not re.fullmatch(r"G\d+", token):
            return [token]
        if "ms" not in state:
            state["ms"] = _screen_sections(answer, map_data)
        ms = state["ms"]
        pin = (map_data or {}).get("coverage", {}).get("pin")
        if ms is None:
            raise SystemExit(_err(
                f"{token} names a group, and a group id is PER-SCREEN and "
                "PER-PIN — it names members only on the screen that minted "
                "it. This selection records no screen, so there is nothing "
                "here that defined "
                f"{token} and it is refused rather than resolved against some "
                "other grouping. Record the screen the ids were read at "
                "(`member` and `axis`) with the selection, or name the "
                "Strands inside the group."))
        by_gid = {s.get("group_id"): s for s in ms["sections"]}
        sec = by_gid.get(token)
        if sec is None:
            known = ", ".join(sorted(g for g in by_gid if g)) or "none"
            raise SystemExit(_err(
                f"{token} names no group on the screen this selection was "
                f"made at ({ms['member']} by {ms['axis']}). Group ids are "
                "PER-SCREEN and PER-PIN — they do not survive a re-run — so "
                f"this screen's ids are {known} at pin {pin}. It is refused "
                "rather than re-resolved, exactly as a stale index is. "
                "Re-read the screen and name the groups from it."))
        members, unknown = [], []
        for el in sec["strands"]:
            ident = by_slug.get(el.get("slug"))
            (members if ident else unknown).append(ident or el.get("slug"))
        if unknown:
            raise SystemExit(_err(
                f"{token} expands to Strand(s) this map does not offer as an "
                f"index ({', '.join(str(u) for u in unknown)}). The whole "
                "selection is refused rather than composed over a group's "
                "members minus the ones that would not resolve."))
        return members

    return expand
