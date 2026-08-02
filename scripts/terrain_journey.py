"""Journey-incorporation options over an adopted brief (Story 20.166; #1045).

THE REGISTER IS DECIDED WHERE THE ARTICLE'S DESIGN IS DECIDED. #1045 asked how
a served journey arc enters article prose and the 2026-07-31 owner ruling
answered the MECHANISM, not the menu: the options are composed at the brief
gate, per brief, by inspecting THIS brief's state — the adopted thesis, the
member set, and each member's served journey material — at a professional
editor's calibration. A fixed register enumeration is exactly what must not
ship: the park that preceded the ruling records that the three registers it
happened to name "are not renderings of one choice — they produce structurally
different articles", and freezing any list here would be taste recorded as
contract.

THE MECHANISM IS #995'S, REUSED RATHER THAN PARALLELED. Like the candidate
theses one gate earlier, this module composes NO option: it supplies the
composition INPUTS (the members with their served arcs, quoted verbatim at the
pin), the REQUIREMENTS the arriving options must satisfy, and the count that
verifies what comes back — because an incorporation option is a reading of
served material against an adopted thesis, and no deterministic join produces
one. Requirements are not a procedure, for the reason `terrain_theses.py`
states at its head and this module inherits whole: what is frozen is what must
be TRUE of the options that arrive, never how the composer arrives at them.

A DISCLOSURE ON THE BRIEF, NEVER A REQUIRED SLOT (the ruling's own sorting:
direction at the brief as disclosure, placement at the outline, concrete
design at realization). `journey_incorporation_block` returns None when no
selected member carries a served arc, and the gate is simply not raised — a
mandatory slot for a contingent property would manufacture the property. The
same rule puts this AFTER thesis adoption: the options read the adopted
thesis, so before one exists there is nothing to compose against, and the
block is absent rather than present-and-empty.

THE COUNT RUNS AFTER COMPOSITION, exactly as the thesis cover does and through
the same `cover` invocation: `verify_incorporation` reads the COMPOSED options
— never the inputs they were composed from — and reuses `strand_cover.py`
rather than growing a second idea of what a placement is.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
# One capacity, imported rather than restated (the #1102 render contract).
from draft_gates import CONTROL_CAPACITY  # noqa: E402
from strand_cover import cover_report, strand_name  # noqa: E402
# The shared refusal grammar of the after-composition counts. Imported from
# the thesis module rather than restated: the two counts run at the same gate
# over the same brief record, and a drifting copy of "the composition is over
# the owner's set" would let the two disciplines disagree about what a set is.
from terrain_theses import _check_known, _check_over, _refuse  # noqa: E402

# HOW MANY OPTIONS. Two is the smallest number that makes the step a CHOICE —
# one option is the machine deciding the register with a question mark after
# it. There is deliberately NO upper bound here: the ratified requirement is
# that options are ENUMERATED, never ranked-and-trimmed, so a ceiling in this
# module would order the composer to trim — the exact move the requirement
# bars. The render contract copes: past the control capacity the payload
# declares overflow or block form, computed rather than authored.
INCORPORATION_OPTIONS_MIN = 2

# What must be TRUE of the options that arrive. Not how to arrive at them.
# These four are the ratified frozen requirements (#1045, the 2026-07-31
# ruling and hub ratification), in the ruling's own order.
INCORPORATION_REQUIREMENTS = [
    "every option PLACES every selected member's journey material or "
    "DISCLOSES the omission by name with its reason — completeness is a "
    "cover counted in placements, and the count runs after composition, "
    "not before",
    "every option cites the SERVED arc rendering at this pin for each "
    "placement — the arc is quoted as served, never re-expressed, and a "
    "placement nothing grounds is a claim the corpus does not carry",
    "every register offered keeps the ARC SHAPE — before-position, what "
    "broke, after-position — and never collapses to rule-statement register "
    "(the hub's served-position constraint, applied with more force here: "
    "an article is where a flattened arc would be read as a rule)",
    "the options are ENUMERATED, never ranked-and-trimmed, and free text "
    "wins — the owner's own incorporation direction becomes the recorded "
    "disclosure, and every option is discarded when they write one",
]


def members_with_arcs(members):
    """The selected members whose journey material is SERVED at this pin.

    Read from the brief's own member records — the `journey` block
    `_member_record` carries, with its three-valued absence — never from the
    map, so the composer and the count see the same material the owner saw.
    """
    out = []
    for m in members or []:
        j = (m or {}).get("journey") or {}
        if j.get("served") and str(j.get("arc") or "").strip():
            out.append(m)
    return out


def journey_incorporation_block(members, pin, adopted_thesis,
                                adopted=None):
    """The gate's incorporation proposal: inputs, requirements, and the count
    that will verify what comes back — or None where the gate is not raised.

    None IS THE CONTRACT, not a degenerate value: a brief whose members carry
    no served journey material has nothing to incorporate, and a brief with no
    adopted thesis has nothing to compose against. In both states the register
    question does not exist yet, and an absent block is how a disclosure
    differs from a required slot.

    NOTHING HERE IS A COMPOSED OPTION (`composed: false`). The composition is
    the gate's, from `inputs` — the brief's own adopted thesis and its
    members' served arcs, and nothing else — so a composer at this gate cannot
    widen the scope past what the owner selected and adopted.
    """
    if not str(adopted_thesis or "").strip():
        return None
    with_arcs = members_with_arcs(members)
    if not with_arcs:
        return None
    return {
        "over": [m.get("index") for m in members],
        # The members whose material the cover is counted over, named so an
        # option's omission disclosure has a fixed set to be checked against.
        "with_journey": [m.get("index") for m in with_arcs],
        # And the members with nothing servable to place, disclosed by the
        # BLOCK rather than owed per option: an option cannot place material
        # the hub does not serve, and asking it to disclose that per option
        # would blame the composition for the corpus.
        "without_journey": [
            {"index": m.get("index"),
             "reason": ((m.get("journey") or {}).get("not_served_reason")
                       or "no served arc at this pin")}
            for m in members or [] if m not in with_arcs],
        "inputs": {"thesis": adopted_thesis, "members": list(members or [])},
        "pin": pin,
        "composed": False,
        "count": {"min": INCORPORATION_OPTIONS_MIN, "max": None},
        # The shape the composed payload owes when it is assembled at the
        # point of composition — the same render contract the thesis gate
        # carries, for the same reason: the options do not exist here, so no
        # payload can be built here, and what CAN be fixed is what a
        # conforming rendering is.
        "payload_contract": {
            "render_required": True,
            "control_capacity": CONTROL_CAPACITY,
            "rule": "control is computed from the choice count against the "
                    "capacity; a recommendation leads at index 0; a block "
                    "carries its own banner and reply line",
        },
        "requirements": INCORPORATION_REQUIREMENTS,
        # The form the composed options come back in, so the gate does not
        # invent one and the count has something fixed to read.
        "answer": {
            "kind": "journey-incorporation",
            "over": [m.get("index") for m in members],
            "pin": pin,
            "options": [{
                "incorporation": "<how the journey material enters THIS "
                                 "article, composed against its adopted "
                                 "thesis — one or two sentences, in arc "
                                 "shape>",
                "places": ["<index>", "..."],
                "omits": [{"index": "<index>",
                           "why": "<why its material is left out>"}],
                "grounds": [{"index": "<index>",
                             "cite": "<its served arc cite>"}],
            }],
        },
        "verify": ("topic-map-directions.py cover --composed <that file> "
                   "--from <this brief artifact> — the count runs AFTER "
                   "composition and is not optional"),
        "adopt": ("pass the chosen option's incorporation back as "
                  "`journey_incorporation` in the answer, with --incorporation "
                  "<the composed options file>; it rides the brief as a "
                  "disclosure beside the adopted thesis"),
        "state": "adopted" if str(adopted or "").strip() else "options-pending",
        **({"adopted": str(adopted).strip()}
           if str(adopted or "").strip() else {}),
    }


def verify_incorporation(composed, selected):
    """The cover over the composed incorporation options.

    THE SAME DISCIPLINE AS THE THESIS COUNT, over the material this gate is
    about: the cover is counted against the members whose arcs are SERVED —
    an option cannot place material the hub does not serve — and an omission
    is admissible only DISCLOSED, by name, with its reason. A refusal returns
    the WHOLE proposal to the composer, never one option while the rest are
    offered, which would be the map choosing.
    """
    refusals = []
    _check_over(composed, selected, refusals)
    servable = []
    arc_cites = {}
    for s in selected:
        j = (s.get("member") or {}).get("journey") or {}
        if j.get("served") and str(j.get("arc") or "").strip():
            servable.append(s)
            arc_cites[s["name"]] = str(j.get("arc_cite") or "")
    if not servable:
        _refuse(refusals,
                "no selected member carries a served arc at this pin, so "
                "there is no journey material to incorporate and the gate is "
                "not raised. A brief without journey material carries no "
                "incorporation disclosure — the register is contingent, and "
                "a slot for it here would manufacture the property.")
        return {"kind": "journey-incorporation", "options": [],
                "complete": False, "refusals": refusals}
    options = composed.get("options") or []
    if len(options) < INCORPORATION_OPTIONS_MIN:
        _refuse(refusals,
                f"{len(options)} incorporation option(s) were composed; the "
                f"gate offers at least {INCORPORATION_OPTIONS_MIN}. One "
                "option is the machine deciding the register with a question "
                "mark after it — and there is no ceiling, because trimming "
                "the enumeration is what the requirement bars.")
    reports = []
    for n, opt in enumerate(options, 1):
        label = f"option {n}"
        if not str(opt.get("incorporation") or "").strip():
            _refuse(refusals,
                    f"{label} states no incorporation — an option with no "
                    "register stated offers nothing to select, and the owner "
                    "would be choosing between placements alone.")
        places = [str(p) for p in (opt.get("places") or [])]
        omits = opt.get("omits") or []
        _check_known(places, selected, refusals, label, "places")
        _check_known([str(o.get("index")) for o in omits
                      if isinstance(o, dict)],
                     selected, refusals, label, "omits")
        for o in omits:
            if not isinstance(o, dict) or not str(o.get("why") or "").strip():
                _refuse(refusals,
                        f"{label} omits "
                        f"{o.get('index') if isinstance(o, dict) else o!r} "
                        "with no reason. An omission is admissible only "
                        "DISCLOSED, by name — an undisclosed one is the "
                        "silent drop this count exists to catch.")
        # Every placement grounds in the member's SERVED ARC cite at this pin
        # — the arc's own address, not the Strand's index-line cite, because
        # what is being placed is the arc.
        got = {}
        for g in opt.get("grounds") or []:
            if isinstance(g, dict):
                got[str(g.get("index"))] = str(g.get("cite") or "")
        for idx in places:
            if idx not in arc_cites:
                _refuse(refusals,
                        f"{label} places {idx}, whose arc is not served at "
                        "this pin. An option places served journey material "
                        "— material the hub does not serve cannot be placed, "
                        "only its absence stated.")
                continue
            if idx not in got or not got[idx]:
                _refuse(refusals,
                        f"{label} places {idx} and grounds it in nothing. "
                        "Every placement cites the member's served arc "
                        "rendering at this pin.")
            elif arc_cites.get(idx) and got[idx] != arc_cites[idx]:
                _refuse(refusals,
                        f"{label} cites {got[idx]!r} for {idx}, but the "
                        f"served arc cite at this pin is {arc_cites[idx]!r}. "
                        "A cite that is not the served one is invented "
                        "material.")
        # THE COUNT ITSELF, over the EMITTED placements, against the members
        # whose material is servable.
        cover = cover_report({"sections": places}, servable)
        disclosed = {str(o.get("index")) for o in omits if isinstance(o, dict)}
        undisclosed = [m for m in cover["omitted"]
                       if str(m.get("index")) not in disclosed]
        if undisclosed:
            _refuse(refusals,
                    f"{label} places {cover['placed']} of "
                    f"{cover['selected']} members' served arcs and says "
                    f"nothing about "
                    f"{', '.join(strand_name(m) for m in undisclosed)}. "
                    "Every selected member's journey material is placed or "
                    "its omission is disclosed by name; silence is neither.")
        reports.append({
            "n": n,
            "incorporation": opt.get("incorporation"),
            "counted": "after-composition",
            "selected": cover["selected"],
            "placed": cover["placed"],
            "placements": cover["placements"],
            "omitted": [strand_name(m) for m in cover["omitted"]],
            "disclosed": sorted(disclosed),
            "undisclosed": [strand_name(m) for m in undisclosed],
            "complete": cover["complete"],
        })
    return {"kind": "journey-incorporation", "options": reports,
            "complete": all(r["complete"] for r in reports)
                        if reports else False,
            "refusals": refusals}
