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
# two budgets come back with it: each is still declared in exactly one place,
# now beside the function that reads it.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from terrain_text import (
    row_type_legend,  # noqa: E402
    BRIEF_EDIT_OPTION_LABEL,
    BRIEF_LIFECYCLE,
    BRIEF_STEP_ID,
    BRIEF_STEP_NAME,
    BUDGETS,
    PARTITION_OPTION_LABEL,
    THESIS_CANDIDATES_OPTION_LABEL,
    VIEW_LINE_CHARS,
    _backlog_line,
    _brief_artifact_line,
    _brief_edit_option_effect,
    _brief_iteration_line,
    _brief_lifecycle_line,
    _brief_step_line,
    _clip_line,
    _element_coverage_line,
    _elide,
    _fit,
    _fit_parts,
    _fit_with_path,
    _gloss_disclosure_line,
    _journey_coverage_line,
    _journey_disclosure_line,
    _partition_proposal_line,
    _pin_display,
    _short_path,
    _substituted_paths,
    _substitution_disclosure_line,
    _terrain_size_line,
    _thesis_candidates_line,
    _thesis_state_line,
    _verdict_phrase,
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


# --------------------------------------------------------------------------
# THE BRIEF ARTIFACT (Story 20.75, #994; SPEC-terrain CAP-3, the named-artifact
# clause added 2026-07-31)
#
# READ THIS BESIDE `write_view` ABOVE, BECAUSE THE CONTRACTS ARE OPPOSITE.
# Every neighbouring artifact this script emits is write-only by contract: the
# View is a RENDERING regenerated per invocation, never read back, and deleting
# it loses nothing, because it can always be recomposed from the map.
#
# The brief is not a rendering. It is THE OWNER'S DECISION — what they selected
# and what they said about it — and it cannot be recomposed from anything: the
# map does not contain it. So **re-opening it is the requirement, not a cache**
# (CAP-3: "The never-read-back rule does not bind here, and the difference is
# the point"). `read_brief_artifact` below is a sanctioned reader, and its
# existence is the difference, stated here so nobody "fixes" it into agreement
# with its neighbours.
#
# What is NOT licensed by that difference, so the two rules stay apart:
#   * no rendering is cached across invocations — screens, Views and reports
#     are still recomposed every time, and nothing here reads one back;
#   * the artifact never becomes an index or a lookup — it is read by the
#     owner returning to their own brief, addressed by the path they were told.
#
# WHERE IT LIVES: the per-run workspace, minted by
# `resolve-paths.py new-run --terrain` (D1 — the resolver owns every storage
# path; this script still just writes where it is told, exactly as `--view`
# does). That is machine state, outside every working tree, which is also what
# keeps the publication boundary intact: the artifact carries `pins.hub`, a
# real hub sha, and #935 relocated Terrain's run workspaces out of this public
# repository for precisely that reason.
# --------------------------------------------------------------------------

# The artifact's default basename. A caller may pass any path under the run
# workspace — Story 20.77's iteration loop holds several briefs in one sitting,
# one per member-set variant — so the NAME is the artifact's identity and this
# is only the default. Declared once, like VIEW_FILENAME.
BRIEF_FILENAME = "brief.json"


def _brief_lifecycle(state, history=None):
    """The lifecycle block carried inside the artifact and printed at the gate.

    Carries the whole ordered sequence and not just the current state: AC5's
    "composed → inspected → adopted" is legible only if the owner can see what
    follows what.
    """
    return {"state": state, "states": list(BRIEF_LIFECYCLE),
            "line": _brief_lifecycle_line(state),
            "history": list(history or [{"state": state}])}


def write_brief_artifact(path, payload):
    """Write the brief artifact. READ BACK BY DESIGN — see the block above.

    Deliberately not `write_view`'s `_ensure_view_dir`: that helper drops a
    self-ignoring `.gitignore` because the View lands inside a working tree.
    This lands in a run workspace under the machine state root, where there is
    no tree to keep clean and an ignore file would be noise.
    """
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    return path


def read_brief_artifact(path):
    """Re-open a written brief (AC4). The sanctioned reader — see the block
    above for why one exists here and nowhere else in this script."""
    with open(path, encoding="utf-8") as fh:
        payload = json.load(fh)
    if not isinstance(payload, dict) or "brief" not in payload:
        raise ValueError("not a brief artifact (no `brief` key)")
    return payload


# --------------------------------------------------------------------------
# THE ITERATION LOOP OVER THE MEMBER SET (Story 20.77, #997; SPEC-terrain
# CAP-3, the iteration-loop clause added 2026-07-31)
#
# THE SEMANTICS WERE ALREADY RATIFIED AND SHIPPED, AND NOTHING HERE
# RE-IMPLEMENTS THEM: a claim is pinned to the member set it was composed over
# and RECOMPOSES when that set changes — a set change being a gate EVENT
# rather than a refresh — which `_brief_from_index` has done since Story
# 20.54. What was missing was the MOVE. The gate offered adopt, narrow, or "go
# back to Screen 2 and pick differently", so an owner developing a thesis by
# trying members had to leave the gate and lose the composition. What is added
# is therefore ONE option class — `+Lxx −Lyy → recompose` — that RESOLVES TO A
# MEMBER SET AND THEN TAKES THE EXISTING PATH.
#
# That routing is the whole design, and it is what preserves the properties
# the path already carries: the pin discipline (a missing or mismatched pin
# refused, with `_which_half_moved` naming which half of the composite pin
# moved), and the `recomposition` block whose inputs are the selected members'
# served claims AND NOTHING ELSE, so a composer at the gate cannot widen the
# scope past what the owner pointed at. An edit changes WHAT the owner pointed
# at; it does not loosen the rule that only that reaches the composer.
#
# AN EDIT NEVER RE-RANKS OR FILTERS. The owner names what changes: an addition
# nobody asked for is the second proposer, and a silent drop breaks the
# completeness invariant that follows the member set into drafting. So a drop
# of a non-member and an add of an existing member are both REFUSED with the
# current set stated, rather than absorbed as no-ops — a no-op edit means the
# owner believes something false about the set, and proceeding would compose
# over that belief.
#
# RETENTION IS WITHIN-SITTING, AND THAT IS WHAT KEEPS IT CLEAR OF THE
# NEVER-READ-BACK RULE (AC4). The chain of prior compositions is carried in
# the brief artifacts THEMSELVES, inside ONE run workspace: `--from` names the
# composition being edited and must sit beside the `--out` this one writes.
# There is no index, no store and no key a later invocation could look up —
# and a new invocation mints a new workspace at Step 0, so it begins with an
# empty chain and can carry nothing forward. That is the difference between
# comparison held for a sitting and a cache, and it is enforced by the
# same-workspace refusal below rather than left to convention.
# --------------------------------------------------------------------------

_EDIT_TOKEN = re.compile(r"^([+\-−])(\S+)$")


def _parse_edit(answer):
    """The owner's edit to the member set: `+L12 −L3`, or `add`/`drop` lists.

    An UNSIGNED token is REFUSED rather than guessed at: `L12` on its own
    could mean add it or select only it, and choosing between those for the
    owner is the move this option class exists to remove.
    """
    adds = [str(x).strip() for x in (answer.get("add") or []) if str(x).strip()]
    drops = [str(x).strip() for x in (answer.get("drop") or []) if str(x).strip()]
    raw = str(answer.get("edit") or "").strip()
    if raw:
        # The option's own label ends `→ recompose`, so an answer that echoes
        # the label is naming the option, not a Strand called "recompose".
        raw = re.sub(r"([+\-−])\s+", r"\1", raw.split("→")[0])
        for tok in re.split(r"[,\s]+", raw):
            if not tok:
                continue
            m = _EDIT_TOKEN.match(tok)
            if not m:
                raise SystemExit(_err(
                    f"{tok!r} in the edit {answer.get('edit')!r} carries no "
                    "+ or −. An edit names what CHANGES about the set — "
                    "`+L12 −L3` — and an unsigned index cannot be told from a "
                    "fresh selection, so it is refused rather than guessed at."))
            (adds if m.group(1) == "+" else drops).append(m.group(2))
    if not adds and not drops:
        return None
    return {"add": adds, "drop": drops}


def _edited_indexes(base_indexes, edit):
    """The edited member set: the base set, minus the drops, plus the adds.

    Order is the owner's throughout — the surviving members keep the order
    they were selected in and the additions land after them, because
    re-ordering would quietly restate a set they did not restate.
    """
    adds, drops = edit["add"], edit["drop"]
    both = [i for i in adds if i in drops]
    if both:
        raise SystemExit(_err(
            f"{', '.join(both)} is both added and dropped in one edit. An "
            "edit states what changes, and an index that changes in both "
            "directions states nothing — name it once."))
    absent = [i for i in drops if i not in base_indexes]
    if absent:
        raise SystemExit(_err(
            f"{', '.join(absent)} is not in the set being edited "
            f"({', '.join(base_indexes)}), so dropping it would change "
            "nothing. An edit names what changes — a drop of a member that is "
            "not there is a mistake about the set, not a no-op, so it is "
            "refused with the set stated."))
    already = [i for i in adds if i in base_indexes]
    if already:
        raise SystemExit(_err(
            f"{', '.join(already)} is already in the set being edited "
            f"({', '.join(base_indexes)}). Adding it would change nothing, "
            "and an edit that changes nothing recomposes the same claim over "
            "the same set — the set is stated here so you can see it."))
    out = [i for i in base_indexes if i not in drops]
    for i in adds:
        if i not in out:
            out.append(i)
    if not out:
        raise SystemExit(_err(
            "this edit empties the member set, and there is no claim to "
            "recompose over nothing. Drop fewer members, or stop here — "
            "stopping is a first-class outcome."))
    return out


def _base_composition_pin(base, map_pin, map_data):
    """The pin discipline, applied to the composition being EDITED (AC6).

    The answer's own pin is checked by `_brief_from_index` exactly as before.
    This is the second half the loop makes possible: the base composition was
    itself pinned, and editing a set composed at a pin the map has since moved
    past would attach the recomposition to indexes that no longer mean what
    they meant. Refused, with which half moved named where the artifact
    recorded the halves.
    """
    pins = base.get("pins") or {}
    base_pin = str(pins.get("terrain") or base.get("pin") or "").strip()
    if not base_pin:
        raise SystemExit(_err(
            "the brief being edited records no pin, so its member set cannot "
            "be proven to name the same Strands as this map. It is refused "
            "rather than re-resolved — select afresh from the screens."))
    if map_pin and base_pin != map_pin:
        moved = _which_half_moved(
            {"destination_pin": pins.get("destination"),
             "hub_pin": pins.get("hub")}, map_data or {})
        raise SystemExit(_err(
            f"pin mismatch: the brief being edited was composed at "
            f"{base_pin}, but this map is at {map_pin}. {moved} Its indexes "
            "may now name different Strands, so the edit is refused rather "
            "than re-resolved. Re-run the map and choose from the fresh "
            "screens."))
    return base_pin


def _composition_record(payload, n, edit=None, artifact=None):
    """One composition, as the loop retains it (AC3).

    Enough to COMPARE theses across set variants — the claim, the set it was
    composed over, its pins, the edit that produced it, where it lives — and
    no more. Never the whole payload: each artifact would then carry every
    earlier one whole, and a comparison the owner cannot read is not one.
    """
    return {"n": n,
            "brief": payload.get("brief"),
            "origin": payload.get("origin"),
            "indexes": list(payload.get("indexes") or []),
            "members": list(payload.get("members") or []),
            "pins": payload.get("pins"),
            "edit": edit,
            "artifact": artifact}


def _iteration_block(out, prior, edit, artifact_path):
    """The loop's state at the gate: the option (AC1), the chain (AC3), and
    the scope of the retention (AC4), stated rather than implied."""
    n = len(prior) + 1
    record = _composition_record(out, n, edit, artifact_path)
    return {
        "n": n,
        "line": _brief_iteration_line(n, len(prior)),
        # AC1 — the option class as DATA, so the gate offers it without
        # inventing either its wording or the form the answer takes. It sits
        # beside the existing options; nothing it replaces is removed, and
        # "go back to Screen 2" simply stops being the only way to change the
        # set.
        "option": {
            "label": BRIEF_EDIT_OPTION_LABEL,
            "effect": _fit(_brief_edit_option_effect()),
            "editable": list(out.get("indexes") or []),
            "answer": {"edit": "+<index> −<index>", "pin": out.get("pin")},
            "command": ("topic-map-directions.py brief --answer <answer> "
                        "--map <map> --from "
                        f"{artifact_path or '<this brief, written with --out>'}"
                        " --out <the next brief in this same workspace>"),
        },
        # AC3 — every composition of this sitting, this one last.
        "compositions": prior + [record],
        # AC4 — said on the surface, because retention that does not state its
        # scope reads as a cache.
        "retention": ("within this sitting only — the chain lives in this run "
                      "workspace's own brief artifacts, and a new invocation "
                      "mints a new workspace, so nothing is carried across "
                      "invocations. Comparison held for the sitting, never a "
                      "cache"),
    }


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
               if len(matches) > 1 else {}),
            "candidate": matches[0]}
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
            write_brief_artifact(path, out)
        except OSError as exc:
            return _err(f"could not write the brief artifact at {path}: {exc}")
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


def cmd_brief_open(args):
    """Re-open a written brief (Story 20.75 AC4/AC5).

    The re-entry point the gate advertises: the owner returns to a brief by
    the path they were told, and optionally records the lifecycle transition
    the return represents. Transitions are FORWARD-ONLY along
    `composed → inspected → adopted` — a backwards move is refused rather than
    recorded, because a lifecycle that can run backwards states nothing.
    """
    try:
        payload = read_brief_artifact(args.at)
    except (OSError, ValueError) as exc:
        return _err(f"unreadable brief artifact at {args.at}: {exc}")
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
    bo.add_argument("--at", required=True, metavar="PATH",
                    help="the artifact written by `brief --out`")
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
