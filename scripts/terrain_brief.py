#!/usr/bin/env python3
"""terrain_brief.py — the BRIEF ARTIFACT and the edit-set iteration loop over
the member set (Story 20.80, #1029; SPEC-writing-assistant, the 2026-07-31
(#1025) amendment).

WHY THIS MODULE EXISTS. `topic-map-directions.py` is HYPHENATED and therefore
unimportable, which is the constraint the #1025 amendment dissolves by making
that path a thin CLI shim: argparse and dispatch stay there, the composition
moves into importable siblings like this one.

WHAT IT CONTAINS: the artifact half of the brief — its lifecycle block, its
writer and its SANCTIONED READER — together with the edit-set loop that
recomposes over a changed member set (`_parse_edit`, `_edited_indexes`,
`_base_composition_pin`, `_composition_record`, `_iteration_block`). They move
together because they are one closure: the loop reads a written artifact, checks
the pin it was composed at, and writes the next one beside it. What COMPOSES a
brief is not here — `brief_from_answer` and `_brief_from_index` stay with the
dispatch that reaches them.

The two contract blocks below travel with the code they govern, unedited: the
brief is read back BY DESIGN, and the View beside it never is. Read them
together — the point is that the two rules are opposite and must stay apart.

This is a MOVE, not a rewrite: every definition below is the one that stood in
`topic-map-directions.py`, unchanged, and composed output is byte-identical for
the same inputs (Story 20.80 AC4).
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from terrain_text import (  # noqa: E402
    BRIEF_EDIT_OPTION_LABEL,
    BRIEF_LIFECYCLE,
    _brief_edit_option_effect,
    _brief_iteration_line,
    _brief_lifecycle_line,
    _fit,
)
# The refusal helper the whole terrain surface refuses through.
from terrain_members import (  # noqa: E402
    _err,
)
# The pin-half naming the edited composition's mismatch message uses — the same
# one the answer's own pin check uses, so both halves of the loop's pin
# discipline read identically.
from terrain_select import (  # noqa: E402
    _which_half_moved,
)

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
