#!/usr/bin/env python3
"""terrain_screens.py — the owner-facing SCREEN compositions and the View file
(Story 20.80, #1029; SPEC-writing-assistant, the 2026-07-31 (#1025) amendment).

WHY THIS MODULE EXISTS. `topic-map-directions.py` is HYPHENATED, so nothing can
import from it — `from topic-map-directions import compose_view` is a
SyntaxError. Every prior cut therefore had to be closed under its own
references, and each one bought about one story. The #1025 amendment discharges
the conditional the #974 block recorded and takes the INVERSION instead: the
hyphenated path keeps its name and its ten skill invocations and carries
argparse and dispatch, while the composition it dispatches to lives here, in
importable siblings.

WHAT IT CONTAINS: everything that composes something for the owner to look at —
the two proposal payloads (`compose_axis_payload` for Screen 1, `compose_payload`
for the one screen, and `_compose_summary_payload` for the over-budget branch)
and the View file itself (`compose_view`, `write_view`). The two constants that
are read only here travel with them: the SCREEN BUDGET the size switch turns on,
and the View's default filename. Both are still declared in exactly one place —
now beside the function that reads them — and the parent imports them back for
its own help text and warning.

This is a MOVE, not a rewrite: every definition below is the one that stood in
`topic-map-directions.py`, unchanged, and composed output is byte-identical for
the same inputs (Story 20.80 AC4).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
# The text and disclosure primitives every screen composes with, and the
# candidate-direction rendering the View leads with.
from terrain_text import (  # noqa: E402
    row_type_legend,
    BUDGETS,
    SCREEN_BUDGET,
    _clip_line,
    _element_coverage_line,
    _fit,
    _fit_parts,
    _fit_with_path,
    _gloss_disclosure_line,
    _journey_coverage_line,
    _journey_disclosure_line,
    _pin_display,
    _substitution_disclosure_line,
    _terrain_size_line,
    _verdict_phrase,
)
from terrain_directions import (  # noqa: E402
    _direction_lines,
    lint_owner_lines,
)
# Screen 1's listing is the member surface's own; the screen composes over it
# rather than re-deriving it.
from terrain_members import (  # noqa: E402
    axis_members,
)

# THE SCREEN BUDGET moved to `terrain_text.py` in Story 20.84 (#1038), where
# both of its readers can reach it — `is_large` here and `member_is_large` on
# the member path, which `terrain_screens.py` imports and therefore cannot be
# imported by. It is imported back above, so it is still declared in exactly
# one place and every call site reads as it did.

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
        # Composed from the row types actually present (#978).
        row_type_legend(map_data.get("elements", []),
                        " A row's 'cover the ...' wording names what an "
                        "article picking it would be about."),
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
