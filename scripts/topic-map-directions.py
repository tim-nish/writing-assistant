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
  brief       --answer PATH [--map PATH]
                                the owner's chosen direction as the brief string
                                for stage-0 `--brief`

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
# two budgets come back with it: each is still declared in exactly one place,
# now beside the function that reads it.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from terrain_text import (  # noqa: E402
    BUDGETS,
    VIEW_LINE_CHARS,
    _clip_line,
    _element_coverage_line,
    _elide,
    _fit,
    _fit_parts,
    _fit_with_path,
    _gloss_disclosure_line,
    _journey_coverage_line,
    _journey_disclosure_line,
    _pin_display,
    _short_path,
    _substituted_paths,
    _substitution_disclosure_line,
    _terrain_size_line,
    _verdict_phrase,
)

# The candidate-directions layer this surface proposes with (Story 20.56,
# #938). A LEAF layer, imported by name so every call site below reads exactly
# as it did before the split — the extraction moved code, not behaviour. Its
# one constant, INTERNAL_VOCAB, travels with `lint_owner_lines`, the only
# function that reads it.
from terrain_directions import (  # noqa: E402
    _direction_lines,
    _element_direction,
    _elements,
    _is_substance_led,
    candidates,
    lint_owner_lines,
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
    axis_members,
    cmd_member,
    compose_full_report,
    compose_member_view,
    load_map,
    member_sections,
)
USAGE = 2

# How many machine-proposed directions the screen carries AT OR UNDER the
# screen budget. A screen is a screen: the map's job is to make the terrain
# legible, not to enumerate it.
MAX_SINGLE = 3
# MAX_COMBINATION went with the deferred combination move (Story 20.7, #809):
# a cap on a list nothing produces is the kind of residue the removal exists
# to stop. It returns with the move, not before.

# THE SCREEN BUDGET (Story 18.66, #601; SPEC-terrain CAP-3 size switch).
# Past this many subtopics one screen stops showing what the map exists to
# show, and the terrain moves into a View file the owner opens while the
# screen becomes a summary.
#
# DECLARED IN EXACTLY ONE PLACE, deliberately: the number is the issue's
# estimate of a screen, not a measurement, so it must be movable by editing
# this line alone. Nothing else — no skill, no harness, no second script —
# restates it.
SCREEN_BUDGET = 7

# The View's filename. "Fixed path" is the CAP-3 property that makes the View
# safe: fully regenerated every invocation, never read back.
#
# Amended 2026-07-23 (Story 18.72, #611): the caller passes a path the PATH
# RESOLVER owns, in the `output.drafts` destination repository — the repo the
# owner actually works in — not a per-run workspace. A per-run path was never
# "fixed": it moved every invocation, so a View opened during a sitting could
# not be reopened. This script still just writes where it is told; the name
# below is help text and a default basename, never a composed path.
VIEW_FILENAME = "topic-map-view.md"


# The screen's shared `why` line — ONE authored copy for both branches, written
# to fit BUDGETS["why"] by construction and measured by
# `check-topic-map-screen.sh` (#832): static template text is never clipped,
# because there is nothing to clip — it is authored inside its budget.
WHY_TEXT = ("Every element is its own selectable idea. Verdicts and depth are "
            "a signal for your judgment, never a gate: gaps are disclosed and "
            "drafted anyway. Your choice becomes the brief, in your words.")


def is_large(map_data):
    """Does this map exceed the screen budget? The ONE predicate the size
    switch turns on (CAP-3 as amended 2026-07-23). Since the pivot (#799) the
    Strands are the only units since the cluster removal (Story 20.7, #809),
    so the budget counts them alone."""
    return len(map_data.get("elements", [])) > SCREEN_BUDGET


def compose_view(map_data, cands):
    """The View: one invocation's terrain, rendered so 20+ directions are
    legible and CAP-2's 'why this depth?' is answerable from the same counts
    the estimate used.

    Leads with the CANDIDATE DIRECTIONS, then the terrain at a glance, then
    per-subtopic detail (#632). The size switch changes where the terrain is
    presented, never whether the map proposes — so `cands` is REQUIRED and is
    the caller's already-derived list. This function never calls `candidates()`
    itself: a second derivation here would be a second proposer, and the
    directions on the View must be the same ones the screen was built from.

    A RENDERING, at the same status as terrain_map.py's --emit-debug: fully
    regenerated every invocation and NEVER read back by any code path. Deleting
    it loses nothing — the map is recomputed, and this is recomposed from it.
    """
    pin = map_data.get("coverage", {}).get("pin")
    lines = [
        "# Terrain",
        "",
        "<!-- Regenerated on every terrain invocation. Never read back by any",
        "     code path; deleting this file loses nothing. Do not edit or commit. -->",
        "",
        f"Pin: {pin}",
        _terrain_size_line(len(map_data.get("topics", [])),
                           len(map_data.get("elements", []))),
        "",
        "Answer with an element's index (for example L3) or a subtopic's",
        "index (for example T1.2) and a short note about the angle you want.",
        "What each row IS, before what covering it would mean: L rows are",
        "Lessons (a rule distilled from experience), J rows are Journeys (how",
        "a position changed over time), and E rows are decisions from the",
        "record. A row's 'cover the ...' wording names what an",
        "article picking it would be about.",
        "Free text always wins. Each element is its own Strand, and its",
        "writability verdict is a disclosure, never a gate: an element whose",
        "evidence is not yet recorded is as pickable as a matched one —",
        "picking it records the gap and the draft still proceeds. Material",
        "you have already written from stays selectable.",
        "",
        "## Candidate directions",
        "",
    ]
    lines += _direction_lines(cands)
    # The element projection's BOUND stays on the surface (CAP-4): the section
    # that used to carry it is gone — elements are directions now (Story 18.81,
    # #647) — but a bounded projection read as the whole record is exactly what
    # the disclosure guards against, so it moves here rather than lapsing.
    lines += ["", _element_coverage_line(map_data)]
    lines += ["", _gloss_disclosure_line(map_data)]
    jline = _journey_disclosure_line(map_data)
    if jline:
        lines += ["", jline]
    # The View renders Strand rows too, so it owes the same denominator
    # (#933/#934) — "every screen rendering Strand rows" admits no exception
    # for the one that is a file.
    cline = _journey_coverage_line(map_data.get("elements") or [])
    if cline:
        lines += ["", cline]
    # THE VIEW ENDS HERE (Story 20.5, #802). What used to follow — "Subtopic
    # clusters", "Maintenance", "Diagnostics" — was ~2,300 of a 2,511-line
    # view serving no function the owner could identify, so the sections AND
    # their emitters are gone: a section deleted at render time is still paid
    # for at assembly time, which was the whole cost.
    #
    # `reading_path` is COLLAPSED DELIBERATELY, not dropped. It existed to
    # mark where the owner-facing surface stopped and upkeep began; with
    # nothing below the boundary, every line is the reading path, so the lint
    # below runs over `lines` itself. Reintroducing a non-owner-facing tail
    # would mean reintroducing the distinction, not just the section.
    #
    # The render-boundary check (Story 18.82, #646) is unchanged in kind: an
    # internal term reaching the owner surface is REPORTED, never laundered.
    # Rewriting the line here would hide the derivation defect that produced
    # it, and the surface would go on looking clean while the adopted brief
    # still carried the term.
    for line, term in lint_owner_lines(lines):
        sys.stderr.write(f"warning: internal vocabulary on the owner surface: "
                         f"{term!r} in {line!r}\n")
    # The budget applies to the composed surface, not to each call site: a
    # field added later is budgeted by construction rather than by remembering.
    # Clipping is the last step, so every list above has already been capped
    # and its remainder disclosed — this bounds a single long VALUE, it never
    # silently drops an item.
    return "\n".join(_clip_line(x) for x in lines).rstrip() + "\n"


def _ensure_view_dir(path):
    """Create the View's directory and its self-ignoring `.gitignore`.

    Lives HERE, at the write, and not in the path resolver (#935): resolving a
    path is a query, and a query that created a directory left a repo-key
    directory behind for every host repo whose View path was merely ASKED for —
    including the check suite's temporary ones. That was the accumulation's
    second source, invisible beside the run workspaces.

    Kept out of `write_view` deliberately: that function's body is grep-asserted
    to contain no `open(` other than its own write (`check-terrain-member.sh`,
    CAP-3's never-read-back rule), and preparing a directory is not writing the
    View. The guard keeps its exact strength.
    """
    d = os.path.dirname(path)
    if not d:
        return
    os.makedirs(d, exist_ok=True)
    # The View is regenerated every invocation and belongs to nobody's history,
    # so the tree must never report it as untracked. A self-ignoring directory
    # (`*` matches this file too) keeps the tree clean without asking the owner
    # to maintain an ignore rule for a tool-owned path.
    ignore = os.path.join(d, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8") as fh:
            fh.write("# Regenerated per invocation by the terrain skill;\n"
                     "# never read back, safe to delete. Ignores itself too.\n*\n")


def write_view(path, text):
    """Write the View. WRITE-ONLY BY CONTRACT (CAP-3/CAP-1): no code path in
    this script — or any flag it accepts — ever reads it back, so it can never
    become a stored index."""
    _ensure_view_dir(path)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def compose_axis_payload(map_data):
    """Screen 1 as ONE owner-facing proposal payload (Story 20.8, #810).

    The same contract every other screen honours: machine-proposed selectable
    options, free-form every time, stop last, plain text, validated before
    presentation. The member word is the TAG'S OWN NAME — the UI word "Topic"
    is retired for the axis (upstream ruling, 2026-07-27) and never appears
    in the composed copy.
    """
    axis = axis_members(map_data)
    pin = map_data.get("coverage", {}).get("pin")
    choices = []
    # Every member of EITHER axis is individually selectable and leads to the
    # same Screen 2. The label carries its axis's kind word, which is what
    # keeps two same-named members apart — `claude-code-ops` is both a served
    # tag and a served decision topic, and they are different material.
    for ax in axis["axes"]:
        for m in ax["members"]:
            n = m["strands"]
            plural = "s" if n != 1 else ""
            choices.append({
                "label": f"by {ax['noun']} — {m['member']} ({n} Strand{plural})",
                "effect": _fit(f"shows all {n} Strands under this "
                                f"{ax['noun']}, whole — nothing capped, "
                                f"nothing ranked; you pick the material there"),
            })
    choices.append({
        "label": "name your own direction or combination axis",
        "effect": _fit("skips the listing and starts the run with your "
                        "wording as the brief"),
    })
    choices.append({
        "label": "stop here",
        "effect": _fit("nothing is drafted and no brief is recorded; the "
                        "axis is recomputed fresh next time"),
    })
    # Each part is a longest-first list of AUTHORED wordings; the field takes
    # the longest combination that fits (#832). Disclosures are never dropped
    # — only stated more tersely — so a screen carrying both the Journey
    # shortfall and the untagged count stays inside the budget instead of
    # blocking presentation on a field nobody can shorten at the gate.
    # The denominator is stated PER AXIS and never pooled (CAP-4 as amended
    # 2026-07-28): one count across both would be a completeness claim over
    # neither corpus.
    counts = {ax["noun"]: len(ax["members"]) for ax in axis["axes"]}
    # The pin is LABELLED here (Story 20.31, #872): an unlabelled sha was read
    # as a statement about hub freshness. Longest-first, so the labels are the
    # first thing the budget gives up rather than the counts.
    parts = [[f"Terrain at {_pin_display(map_data)}: {counts['tag']} tag(s) and "
              f"{counts['topic']} topic(s) from the served vocabularies, each "
              f"individually selectable.",
              f"Terrain at {_pin_display(map_data)}: {counts['tag']} tag(s), "
              f"{counts['topic']} topic(s), each selectable.",
              f"Terrain at {pin}: {counts['tag']} tag(s), {counts['topic']} "
              f"topic(s), each selectable."]]
    sline = _substitution_disclosure_line(map_data)
    if sline:
        parts.append([sline, _substitution_disclosure_line(map_data, terse=True)])
    jline = _journey_disclosure_line(map_data)
    if jline:
        parts.append([jline, _journey_disclosure_line(map_data, terse=True)])
    if axis["unreachable_strands"]:
        # The disclosure is a LINE, never a section (CAP-4): Strands outside
        # EVERY axis are named, not hidden, and free-form still reaches them.
        # This is no longer the pre-2026-07-28 "carry no served tag" line,
        # which asserted an unreachability the topic axis makes false — that
        # line is retired, not reworded.
        parts.append([f"{axis['unreachable_strands']} Strand(s) sit outside "
                      f"both listings — name one at free-form to reach it.",
                      f"{axis['unreachable_strands']} Strand(s) sit outside "
                      f"both — reach one at free-form."])
    where = _fit_parts(parts, BUDGETS["where"])
    return {"items": [{
        "where": _fit(where, BUDGETS["where"]),
        "why": _fit("Pick where to look first, by tag or by topic. The count "
                     "is a signal for your judgment, never a gate: every "
                     "member is offered whatever its size, and its material "
                     "is shown whole.",
                     BUDGETS["why"]),
        "choices": choices,
    }]}


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
    out = compose_full_report(m, str(args.tag).strip(), candidates(m),
                              group_ids, axis, claims, grouping)
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def compose_payload(map_data, cands, view_path=None):
    """The ONE screen.

    At or under the screen budget: the terrain, the candidate directions, a
    free-form response, and stopping — the shipped composition, unchanged.

    Above it: a short SUMMARY plus the View file's path, because one screen
    does not scale — 20+ directions collapsed into a handful of options hides
    the terrain the map exists to show. Selection then happens by index from
    the View rather than by matching a proposed direction string.

    Plain text either way — the payload the validator accepts is the payload
    the owner sees.
    """
    if view_path and is_large(map_data):
        return _compose_summary_payload(map_data, view_path)
    topics = map_data.get("topics", [])
    # The terrain line was a histogram of depth ESTIMATES per subtopic. Both
    # are gone (Story 20.7, #809), so it states what the terrain now holds:
    # how many strands, and how many are already written from. A count is a
    # screen affordance for choosing where to look, never a gate.
    strands = map_data.get("elements", []) or []
    terrain = f"{len(strands)} strand(s)"
    consumed = sum(1 for e in strands if e.get("consumed"))

    choices = []
    for c in cands:
        verdict = _verdict_phrase(c)
        n = c["evidence_pointers"]
        effect = (f"starts a normal drafting run with this as your coverage "
                  f"brief; {verdict}" if verdict else
                  f"starts a normal drafting run with this as your coverage "
                  f"brief; {n} source reference{'' if n == 1 else 's'} "
                  f"behind it")
        choices.append({"label": c["direction"], "effect": _fit(effect)})
    # Free-form is offered EVERY time, not only on rejection.
    choices.append({
        "label": "name your own direction or combination axis",
        "effect": _fit("starts the same run with your wording as the brief; "
                        "nothing above is adopted unless you say so"),
    })
    choices.append({
        "label": "stop here",
        "effect": _fit("nothing is drafted and no brief is recorded; the map is "
                        "recomputed fresh next time"),
    })

    els = map_data.get("elements", [])
    item = {
        "where": _fit(
            f"Terrain at {_pin_display(map_data)}: "
            f"{len(els)} element(s) — each its own Strand — and "
            f"{len(topics)} topic(s), {terrain}; "
            f"{consumed} already consumed and still selectable.", BUDGETS["where"]),
        "why": _fit(WHY_TEXT, BUDGETS["why"]),
        "choices": choices,
    }
    return {"items": [item]}


def _compose_summary_payload(map_data, view_path):
    """The >budget screen: a summary and the View's path. Still ONE item, still
    free-form every time, still `stop here` last — the size switch changes what
    the screen SHOWS, never the shape of the contract it is presented under."""
    topics = map_data.get("topics", [])
    strands = map_data.get("elements", []) or []
    terrain = f"{len(strands)} strand(s)"
    consumed = sum(1 for e in strands if e.get("consumed"))

    choices = [
        {"label": "choose a direction by its index from the View",
         "effect": _fit("answer with the index (for example L3 or T1.2) and "
                         "a short note about the angle you want; your note is "
                         "carried into the brief word for word")},
        # Free-form is offered EVERY time, not only on rejection.
        {"label": "name your own direction or combination axis",
         "effect": _fit("starts the same run with your wording as the brief; "
                         "nothing in the View is adopted unless you say so")},
        {"label": "stop here",
         "effect": _fit("nothing is drafted and no brief is recorded; the map "
                         "and the View are regenerated fresh next time")},
    ]
    els = map_data.get("elements", [])
    pin = map_data.get("coverage", {}).get("pin")
    item = {
        "where": _fit_with_path([
            # Longest-first authored variants (#832); the View path already
            # says the screen overflowed, so no "too many to fit" sentence.
            f"Terrain at {_pin_display(map_data, in_conversation=False)}: "
            f"{len(els)} element(s) — each its own Strand "
            f"— and {len(topics)} topic(s), {terrain}; "
            f"{consumed} already consumed and still selectable.",
            f"Terrain at {pin}: {len(els)} Strands, {len(topics)} topic(s); "
            f"{consumed} consumed, still selectable.",
            f"Terrain: {len(els)} Strands.",
        ], view_path, BUDGETS["where"]),
        "why": _fit(WHY_TEXT, BUDGETS["why"]),
        "choices": choices,
    }
    return {"items": [item]}


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
    """
    if not candidate or candidate.get("kind") != "element":
        return None
    u = candidate.get("usability") or {}
    verdict = u.get("verdict")
    if not verdict or verdict == "matched":
        return None
    target = recording_target or {}
    slug = str(candidate.get("slug") or "").strip()
    gap = {"verdict": verdict, "slug": slug,
           "checked": u.get("checked") or [],
           "drafting": "proceeds — the verdict is a disclosure, never a gate"}
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


def _selected_indexes(answer):
    """The owner's selection as a SET of Strand indexes, however assembled
    (Story 20.54, #937).

    A selection is a set because exploring is how the owner decides what to
    write about: pointing at the Strands that belong together and having the
    brief composed from exactly those is the outcome the terrain exists for,
    and a single index is that set's degenerate case, not a different
    operation. `index` is therefore accepted as a list or as one string
    naming several — the payload shape is the owner's convenience, and NO
    named index is silently dropped or collapsed to the first.

    Order is the owner's, de-duplicated: a repeated index is one member, and
    reordering their pointers would quietly restate what they chose.
    """
    raw = answer.get("index")
    parts = raw if isinstance(raw, (list, tuple)) else re.split(
        r"[,\s]+", str(raw or ""))
    out = []
    for p in parts:
        p = str(p).strip()
        if p and p not in out:
            out.append(p)
    return out


def _refuse_group_ids(indexes):
    """A group id addresses INSPECTION, never selection (Story 20.54 AC7).

    `G` is a DISPLAY kind conferring no selection authority (SPEC-terrain, the
    display-kind clause). Accepting one here would make grouping a gate — the
    owner would be choosing a machine's partition rather than Strands — so it
    is refused with the distinction stated rather than resolved to the group's
    members.
    """
    groups = [i for i in indexes if re.fullmatch(r"G\d+", i)]
    if not groups:
        return
    raise SystemExit(_err(
        f"{', '.join(groups)} name group(s), and a group id carries no "
        "selection authority: `G` is a display kind, so it addresses "
        "INSPECTION (pull a full report for it) and never selection. "
        "Selection is by Strand index — name the Strands inside the group "
        "you want, and the claim is recomposed over exactly those."))


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
        "substitution_candidates": [
            _member_record(c) for c in cands
            if c.get("kind") == "element" and c.get("id") not in chosen],
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

    An index is meaningless without the map it was read from, so the answer
    must carry the pin the View was rendered at. A mismatch is REFUSED with the
    mismatch named — never silently re-resolved to whatever `L3` happens to
    mean at the current pin, which would hand the owner a scope they never
    chose. A missing pin is refused for the same reason: it cannot be proven
    not to be stale.
    """
    indexes = _selected_indexes(answer)
    index = indexes[0] if len(indexes) == 1 else ", ".join(indexes)
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
    _refuse_group_ids(indexes)
    by_id = {c.get("id"): c for c in cands}
    # EVERY named index is resolved, and an unresolvable one refuses the whole
    # selection: dropping it would compose the brief over a set the owner did
    # not choose, silently.
    missing = [i for i in indexes if i not in by_id]
    if missing:
        raise SystemExit(_err(
            f"index {', '.join(repr(i) for i in missing)} names no Strand in "
            "this map. The indexes come from the screens rendered at this pin "
            "— re-read them and choose again."))
    matches = [by_id[i] for i in indexes]
    note = str(answer.get("note") or "").strip()
    claim = str(answer.get("claim") or "").strip()
    if len(matches) == 1 and not claim:
        # THE DEGENERATE CASE, preserved byte for byte: the coverage wording
        # plus the note verbatim, exactly as before set selection existed.
        base = matches[0]["direction"]
    else:
        # RECOMPOSED OVER EXACTLY THIS SET. The deterministic wording is a
        # coverage statement over the selected members, never a narrative
        # shape; an owner-adopted claim replaces it outright.
        base = claim or "; ".join(m["direction"] for m in matches)
    brief = f"{base} — {note}" if note else base
    cov = (map_data or {}).get("coverage", {}) or {}
    return {"brief": brief,
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
            "members": [_member_record(m) for m in matches],
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
               if len(matches) > 1 else {}),
            "candidate": matches[0]}


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
    if _selected_indexes(answer):
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
        if not ms["count"]:
            return _err(f"no Strand sits under {tag!r} at this pin")
        write_view(args.out, compose_member_view(data, ms))
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
    out = brief_from_answer(answer, cands, map_pin, map_data)
    # Evidence-independence at the hand-off (#799): a selected element's
    # writability gap is DISCLOSED beside the brief — with the tracking
    # artifact's content for the target repo — and the run proceeds. There is
    # no refusal path here on evidence.
    gap = _selection_gap(out.get("candidate"),
                         (map_data or {}).get("recording_target"))
    if gap:
        out["gap"] = gap
    # A SET discloses every member's gap, not just the first one's (Story
    # 20.54): the completeness invariant follows the selected set into
    # drafting, so a gap disclosed for one member and silent for four would
    # be exactly the silent omission the member record exists to prevent.
    if len(out.get("members") or []) > 1:
        by_id = {c.get("id"): c for c in cands}
        gaps = []
        for m in out["members"]:
            g = _selection_gap(by_id.get(m.get("index")),
                               (map_data or {}).get("recording_target"))
            if g:
                gaps.append(dict(g, index=m.get("index")))
        if gaps:
            out["gaps"] = gaps
    out["stage"] = "topic-map-brief"
    out["next"] = ("draft-pipeline.py stage0 <framework> <sources...> --brief "
                   "<this brief> — the existing stage-0 path, unchanged")
    print(json.dumps(out, indent=2, ensure_ascii=False))
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
    # The dogfood harness (Story 20.37, #891): the substrate is BUILT and NOT
    # OFFERED, so it is reachable only by naming it here. `--grouping` carries
    # the model's proposal; without one every Strand lands in the residue,
    # which is the honest empty state rather than an invented grouping.
    mb.add_argument("--substrate", default=SUBSTRATE_DEFAULT,
                    choices=sorted(set(SUBSTRATES) | set(SUBSTRATES_UNOFFERED)),
                    help="grouping substrate (default: %(default)s). Substrates "
                         "outside the offered set are reachable for measurement "
                         "only, until an owner verdict admits them.")
    mb.add_argument("--claims", metavar="JSON",
                    help='the `in common:` claims you composed, as {"G1": '
                         '"..."}. Passing them returns the FINAL screen — ids, '
                         "claims and rows together — which is what you relay: "
                         "the rows are never retyped by hand (#976/#977). "
                         "Carried VERBATIM, never recomposed; a group whose "
                         "claim is absent says so. Omit for the pre-20.66 "
                         "listing, byte-identical.")
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
    args = p.parse_args(argv)
    return {"candidates": cmd_candidates, "payload": cmd_payload,
            "view": cmd_view, "brief": cmd_brief,
            "axis": cmd_axis, "member": cmd_member,
            "report": cmd_report,
            "journey-inputs": cmd_journey_inputs}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
