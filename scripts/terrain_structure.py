"""Structure candidates over an adopted brief (Story 20.211; #1410).

STRUCTURE IS COMPOSED, NEVER SELECTED FROM A STOCK. The 2026-08-03 owner
ruling *(owner decision record — 2026-08-03 (article structure proposed, not
templated))* ends the framework-menu shape: the system maintains no list of
predefined structures to pick from per article. Candidates are composed at the
brief gate, per brief, by inspecting THIS brief's state — the adopted thesis,
the selected member set with served glosses, and each member's served arc —
and each candidate is stated OPERATIONALLY: ordered moves with a one-line
rationale naming the material that motivates it ("open with the failure case:
J2 is the strongest concrete anchor for the thesis"). A framework name is
never a candidate; it may appear as a CITATION on one ("close to
ki-shō-ten-ketsu") when that helps the owner evaluate it — the #911 window
keeps governing the framework assets while the menu path is gone.

THE MECHANISM IS #995'S, REUSED RATHER THAN PARALLELED, exactly as the
journey sibling reuses it: this module composes NO candidate. It supplies the
composition INPUTS, the REQUIREMENTS the arriving candidates must satisfy,
and the count that verifies what comes back — a structure candidate is a
reading of the material against an adopted thesis, and no deterministic join
produces one. What is frozen is what must be TRUE of the candidates that
arrive, never how the composer arrives at them.

A BRIEF DISCLOSURE, IN SEQUENCE. The gate sits AFTER journey incorporation
(the registry order in `draft_gates.GATES` is load-bearing): a journey-shaped
candidate — failure-case-first, reversal-led — folds in here and names which
served arc licenses it, so the register decision precedes the structure that
may lean on it. The block is raised once a thesis is adopted; before one
exists there is nothing to compose against and the block is absent rather
than present-and-empty. The adopted structure crosses into drafting as a
disclosure — direction at the brief; placement to the outline; concrete
design to realization — and a brief carrying one means the stage-3
`narrative-structure` gate is NOT re-raised: a decided owner question is
asked exactly once.

PROVENANCE IS RECORDED WITH AN EXPLICIT `bespoke` VALUE (#911's corrected
instrument): the failure mode under watch is the composer ignoring the
reference frameworks entirely, and an instrument keyed on match events falls
silent exactly as that happens — so every adoption carries
`framework_matched`, with `bespoke` when nothing was matched, and silence is
impossible.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
# One capacity, imported rather than restated (the #1102 render contract).
from draft_gates import CONTROL_CAPACITY  # noqa: E402
# The shared refusal grammar of the after-composition counts — imported, never
# copied, for the reason terrain_journey states: a drifting copy would let the
# sibling disciplines disagree about what a set is.
from terrain_theses import _check_over, _refuse  # noqa: E402
from terrain_journey import members_with_arcs  # noqa: E402

# Two is the smallest number that makes the step a CHOICE, and there is
# deliberately no ceiling — enumerated, never ranked-and-trimmed.
STRUCTURE_CANDIDATES_MIN = 2

STRUCTURE_OPTION_LABEL = "structure — how THIS article moves"

# What must be TRUE of the candidates that arrive (#1410, in the ruling's own
# order; the first four are the standing gate requirements inherited whole).
STRUCTURE_REQUIREMENTS = [
    "every candidate is composed over the same complete selected set and "
    "PLACES every selected Strand or DISCLOSES the omission by name with its "
    "reason — completeness is a cover counted in placements, after "
    "composition",
    "every placement cites the Strand's served rendering at this pin; a "
    "journey-shaped candidate additionally names the served arc that "
    "licenses its shape",
    "every candidate is stated OPERATIONALLY — ordered moves with a one-line "
    "rationale naming the material that motivates it — never a framework "
    "name; a framework may be cited on a candidate as vocabulary, and no "
    "list of frameworks is enumerated for selection anywhere",
    "candidates are ENUMERATED, never ranked-and-trimmed, and free text "
    "wins — the owner's own structure becomes the recorded disclosure, and "
    "every candidate is discarded when they write one",
    "the adoption records `framework_matched` with an explicit `bespoke` "
    "value when no reference framework was matched — the #911 instrument, "
    "under which silence is impossible",
]


def structure_candidates_block(members, pin, adopted_thesis, adopted=None,
                               adopted_register=None):
    """The gate's composition proposal: inputs, requirements, and the count
    that verifies what comes back — or None where the gate is not raised.

    None IS THE CONTRACT: before a thesis is adopted there is no state to
    compose structure against, and an absent block is how a sequenced gate
    differs from a required slot. Unlike the journey sibling this block does
    NOT require served arcs — structure is composed from thesis + members,
    and arcs enrich the candidate pool when present.
    """
    if not str(adopted_thesis or "").strip():
        return None
    with_arcs = members_with_arcs(members)
    return {
        "over": [m.get("index") for m in members],
        "with_journey": [m.get("index") for m in with_arcs],
        "inputs": {
            "thesis": adopted_thesis,
            "members": list(members or []),
            # The adopted register rides in when one exists: a candidate that
            # leans on a journey shape must agree with the register the owner
            # already chose, and hiding that choice from the composer would
            # invite candidates the sequence already ruled out.
            **({"journey_incorporation": str(adopted_register).strip()}
               if str(adopted_register or "").strip() else {}),
        },
        "pin": pin,
        "composed": False,
        "count": {"min": STRUCTURE_CANDIDATES_MIN, "max": None},
        "payload_contract": {
            "render_required": True,
            "control_capacity": CONTROL_CAPACITY,
            "rule": "control is computed from the choice count against the "
                    "capacity; a recommendation leads at index 0; a block "
                    "carries its own banner and reply line",
        },
        "requirements": STRUCTURE_REQUIREMENTS,
        "answer": {
            "kind": "structure-candidates",
            "over": [m.get("index") for m in members],
            "pin": pin,
            "candidates": [{
                "structure": "<the ordered moves of THIS article, "
                             "operationally stated — e.g. 'open with the "
                             "failure case; ...; close by composing the "
                             "members' claims'>",
                "rationale": "<one line naming the material that motivates "
                             "this shape>",
                "framework_note": "<optional: 'close to <name>' as "
                                  "vocabulary — never the candidate itself>",
                "arc_license": "<required on a journey-shaped candidate: the "
                               "served arc cite that licenses the shape>",
                "places": ["<index>", "..."],
                "omits": [{"index": "<index>",
                           "why": "<why it is left out>"}],
                "grounds": [{"index": "<index>",
                             "cite": "<its served rendering cite>"}],
            }],
        },
        "verify": ("topic-map-directions.py cover --composed <that file> "
                   "--from <this brief artifact> — the count runs AFTER "
                   "composition and is not optional"),
        "adopt": ("pass the chosen candidate's structure back as `structure` "
                  "in the answer, with `structure_framework_matched` "
                  "(explicit `bespoke` when nothing was matched) and "
                  "--structures <the composed candidates file>; it rides the "
                  "brief as a disclosure, and a brief carrying one means the "
                  "stage-3 narrative-structure gate is not re-raised"),
        "state": "adopted" if str(adopted or "").strip() else
                 "candidates-pending",
        **({"adopted": str(adopted).strip()}
           if str(adopted or "").strip() else {}),
    }


def _structure_line(n_members, n_with_arcs):
    if n_with_arcs:
        return (f"structure: composed for THIS article from the adopted "
                f"thesis, {n_members} member(s), and {n_with_arcs} served "
                "arc(s) — never selected from a framework stock")
    return (f"structure: composed for THIS article from the adopted thesis "
            f"and {n_members} member(s) — never selected from a framework "
            "stock")


def verify_structures(composed, selected):
    """The cover over the composed structure candidates.

    THE SAME DISCIPLINE AS THE SIBLING COUNTS: counted against the owner's
    selected set; an omission is admissible only disclosed, by name, with its
    reason; a refusal returns the WHOLE proposal to the composer, never one
    candidate while the rest go on. Two checks are this count's own: a
    candidate stated as a bare framework name (no operational moves) is
    refused — the menu returning through the answer file — and a
    journey-shaped candidate must carry its licensing arc cite.
    """
    refusals = []
    _check_over(composed, selected, refusals)
    candidates = composed.get("candidates") or []
    if len(candidates) < STRUCTURE_CANDIDATES_MIN:
        _refuse(refusals,
                f"{len(candidates)} structure candidate(s) were composed; "
                f"the gate offers at least {STRUCTURE_CANDIDATES_MIN}. One "
                "candidate is the machine deciding the structure with a "
                "question mark after it.")
    names = {str(s.get("name")) for s in selected}
    for n, cand in enumerate(candidates, 1):
        label = f"candidate {n}"
        structure = str(cand.get("structure") or "").strip()
        if not structure:
            _refuse(refusals,
                    f"{label} states no structure — a candidate with no "
                    "moves offers nothing to select.")
        elif len(structure.split()) < 4 and not cand.get("rationale"):
            # A bare token where ordered moves belong is the menu shape
            # returning through the answer file.
            _refuse(refusals,
                    f"{label} is a name, not a structure: candidates are "
                    "stated as ordered operational moves with a rationale "
                    "naming the material — a framework name alone is the "
                    "menu this gate removed (#1410).")
        if not str(cand.get("rationale") or "").strip():
            _refuse(refusals,
                    f"{label} carries no rationale — the ruling requires a "
                    "one-line reason naming the material that motivates the "
                    "shape, or the owner is evaluating taste against taste.")
        placed = {str(p) for p in (cand.get("places") or [])}
        omitted = {str(o.get("index")): str(o.get("why") or "").strip()
                   for o in (cand.get("omits") or [])}
        for s in selected:
            nm = str(s.get("name"))
            if nm in placed:
                continue
            if nm in omitted:
                if not omitted[nm]:
                    _refuse(refusals,
                            f"{label} omits {nm} without a reason — an "
                            "omission is admissible only disclosed, by "
                            "name, with why.")
                continue
            _refuse(refusals,
                    f"{label} neither places nor discloses {nm} — a silent "
                    "drop is the narrowing the cover exists to catch.")
        for p in placed | set(omitted):
            if p not in names:
                _refuse(refusals,
                        f"{label} names {p}, which is not in the brief's "
                        "selected set — the composition widened the scope "
                        "past what the owner selected.")
        grounds = {str(g.get("index")): str(g.get("cite") or "").strip()
                   for g in (cand.get("grounds") or [])}
        for p in placed:
            if not grounds.get(p):
                _refuse(refusals,
                        f"{label} places {p} with no served-rendering cite — "
                        "a placement nothing grounds is a claim the corpus "
                        "does not carry.")
    return {"kind": "structure-candidates",
            "candidates": [str(c.get("structure") or "")[:80]
                           for c in candidates],
            "complete": not refusals, "refusals": refusals}


def composed_structures(doc):
    """The composed candidates as the brief records them — the #1079 rule a
    third time: the whole offer survives, read from the same file `cover`
    reads, so there is one composed artifact and not two."""
    if not isinstance(doc, dict):
        raise ValueError("composed structure candidates must be an object")
    cands = doc.get("candidates")
    if not isinstance(cands, list) or not cands:
        raise ValueError("composed structures carry no `candidates` list")
    block = {"composed": True, "candidates": cands}
    for key in ("recommendation", "over", "pin"):
        if doc.get(key) is not None:
            block[key] = doc[key]
    return block


def structures_recording(structures_path, answer):
    """(block, error) for the adoption path: the #1079 provenance rule plus
    the #911 instrument, refused with the missing half named."""
    block = None
    if structures_path:
        try:
            with open(structures_path, encoding="utf-8") as fh:
                block = composed_structures(__import__("json").load(fh))
        except (OSError, ValueError) as exc:
            return None, ("unreadable composed structure candidates at "
                          f"{structures_path}: {exc}")
    if str(answer.get("structure") or "").strip():
        if block is None:
            return None, (
                "this answer adopts a structure (`structure`) but no composed "
                "candidates were given, so the brief would record an ADOPTED "
                "structure with no record of what it was adopted from. Pass "
                "`--structures <the candidates file>` — the same file `cover` "
                "reads. The rejected candidates are the provenance of the "
                "choice (#1079 rule).")
        if not str(answer.get("structure_framework_matched") or "").strip():
            return None, (
                "this answer adopts a structure with no "
                "`structure_framework_matched` value. The #911 instrument "
                "requires explicit provenance on EVERY accepted structure — "
                "pass the matched framework's name, or the literal `bespoke` "
                "when nothing was matched. Silence is the state the "
                "instrument exists to make impossible.")
    return block, None
