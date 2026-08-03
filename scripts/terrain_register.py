"""The Brief's plain-register commitment (Story 20.212; #1411).

A COMMITMENT, NOT A SENTENCE. The 2026-08-03 owner ruling *(owner decision
record — 2026-08-03 (article structure proposed, not templated))* puts a
child-level translation of the adopted thesis — plus a child-level rendering
per selected Strand — on the Brief, decided upstream rather than improvised at
the fill, because BOTH article ends realize it and the close composes the
simplified Strand renderings into its restatement (#1412). What is fixed here
is the proposition a reader must be able to state after either end; every
surface realization stays free, and the draft is never handed a string to
paste.

THE DERIVATION HAZARD IS BUILT OUT, NOT FILTERED AFTER. Asking cold for "a
thesis an elementary-school student can understand" reliably produces
condescension, lossy stock metaphors, or a register that does not match the
article — the owner raised this explicitly and the controls below are the
agreed answer. So plain register is defined as OPERATIONAL CONSTRAINTS (no
term of art without an in-sentence explanation, one relation per sentence, a
concrete subject doing something), never as audience impersonation: the
article's audience is unchanged, the register is the constraint. A composer
told to "write for a child" is being asked to imagine a reader; a composer
told "explain every term of art in the sentence that uses it" is being asked
to satisfy a checkable property.

EVERY CANDIDATE CARRIES ITS ROUND-TRIP CONCESSION. The plain version is
composed FROM the adopted thesis and each Strand's served claim, and the
candidate states what the translation loses: the original claim must be
recoverable from the plain version, and anything lost is restored or conceded
BY NAME. A candidate with no concession clause is asserting losslessness, and
is judged on that assertion rather than excused from it — which is why the
field is required rather than optional.

THE MECHANISM IS #995'S, REUSED A THIRD TIME. This module composes no
candidate: inputs, requirements, and the count that verifies what comes back.

THE BOUNDARY WITH JOURNEY INCORPORATION IS LOAD-BEARING. That gate's arcs are
"quoted as served — never re-expressed". This gate re-expresses the THESIS and
the Strands' CLAIMS — a different artifact with its own gate — and a
plain-register Strand rendering never licenses paraphrasing a served arc where
the arc itself is cited. The two live one gate apart and the distinction is
asserted, not assumed.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from draft_gates import CONTROL_CAPACITY  # noqa: E402
from terrain_theses import _check_over, _refuse  # noqa: E402

REGISTER_CANDIDATES_MIN = 2

REGISTER_OPTION_LABEL = "plain register — the commitment both ends realize"

# What must be TRUE of the candidates that arrive (#1411), in the ruling's
# order. Operational constraints, never audience impersonation.
REGISTER_REQUIREMENTS = [
    "plain register is OPERATIONAL — no term of art without an in-sentence "
    "explanation, one relation per sentence, a concrete subject doing "
    "something; it is never 'write for a child', and the article's audience "
    "is unchanged (the register is the constraint, not the reader)",
    "every candidate is a TRANSLATION of the adopted thesis and carries its "
    "ROUND-TRIP CONCESSION: the original claim must be recoverable from the "
    "plain version, and anything lost is restored or conceded BY NAME — a "
    "candidate claiming no loss is asserting losslessness and is judged on it",
    "every candidate carries a child-level rendering per selected Strand, or "
    "DISCLOSES the omission by name with its reason — completeness is a cover "
    "counted in placements, and the count runs after composition",
    "every rendering is composed from the Strand's SERVED claim at this pin "
    "and cites it; nothing from outside the served corpus enters a candidate",
    "the candidates are ENUMERATED, never ranked-and-trimmed, and free text "
    "wins — the owner's own wording IS the commitment, verbatim",
]


def plain_register_block(members, pin, adopted_thesis, adopted=None):
    """The gate's proposal: inputs, requirements, and the count — or None
    where the gate is not raised.

    None IS THE CONTRACT: before a thesis is adopted there is nothing to
    translate, and an absent block is how a sequenced gate differs from a
    required slot.
    """
    if not str(adopted_thesis or "").strip():
        return None
    return {
        "over": [m.get("index") for m in members],
        "inputs": {"thesis": adopted_thesis, "members": list(members or [])},
        "pin": pin,
        "composed": False,
        "count": {"min": REGISTER_CANDIDATES_MIN, "max": None},
        "payload_contract": {
            "render_required": True,
            "control_capacity": CONTROL_CAPACITY,
            "rule": "control is computed from the choice count against the "
                    "capacity; a recommendation leads at index 0; a block "
                    "carries its own banner and reply line",
        },
        "requirements": REGISTER_REQUIREMENTS,
        "boundary": (
            "journey incorporation's arcs stay QUOTED AS SERVED — this gate "
            "re-expresses the thesis and the Strands' claims, a different "
            "artifact, and a plain-register rendering never licenses "
            "paraphrasing a served arc where the arc itself is cited"),
        "answer": {
            "kind": "plain-register",
            "over": [m.get("index") for m in members],
            "pin": pin,
            "candidates": [{
                "plain": "<the adopted thesis in plain register — satisfying "
                         "the operational constraints, not impersonating a "
                         "reader>",
                "concession": "<what the translation loses, restored or "
                              "conceded by name; state it even when nothing "
                              "is lost, and say so>",
                "renderings": [{"index": "<index>",
                                "plain": "<that Strand's claim in plain "
                                         "register>",
                                "cite": "<its served claim cite>"}],
                "omits": [{"index": "<index>",
                           "why": "<why it carries no rendering>"}],
            }],
        },
        "verify": ("topic-map-directions.py cover --composed <that file> "
                   "--from <this brief artifact> — the count runs AFTER "
                   "composition and is not optional"),
        "adopt": ("pass the chosen candidate's plain thesis back as "
                  "`plain_register` in the answer, with --register <the "
                  "composed candidates file>; it rides the brief as a "
                  "disclosure, and BOTH article ends realize it (#1412)"),
        "state": "adopted" if str(adopted or "").strip() else
                 "candidates-pending",
        **({"adopted": str(adopted).strip()}
           if str(adopted or "").strip() else {}),
    }


def _register_line(n_members):
    return (f"plain register: a child-level translation of the adopted thesis "
            f"and {n_members} Strand rendering(s) — derived under operational "
            "constraints, never an 'explain for a child' prompt")


def composed_register(doc):
    """The composed candidates as the brief records them — the #1079 rule."""
    if not isinstance(doc, dict):
        raise ValueError("composed register candidates must be an object")
    cands = doc.get("candidates")
    if not isinstance(cands, list) or not cands:
        raise ValueError("composed register carries no `candidates` list")
    block = {"composed": True, "candidates": cands}
    for key in ("recommendation", "over", "pin"):
        if doc.get(key) is not None:
            block[key] = doc[key]
    return block


def register_recording(register_path, answer):
    """(block, error) for the adoption path — the #1079 provenance rule."""
    block = None
    if register_path:
        try:
            import json
            with open(register_path, encoding="utf-8") as fh:
                block = composed_register(json.load(fh))
        except (OSError, ValueError) as exc:
            return None, (f"unreadable composed register candidates at "
                          f"{register_path}: {exc}")
    if str(answer.get("plain_register") or "").strip() and block is None:
        return None, (
            "this answer adopts a plain-register commitment "
            "(`plain_register`) but no composed candidates were given, so the "
            "brief would record an ADOPTED commitment with no record of what "
            "it was adopted from. Pass `--register <the candidates file>` — "
            "the same file `cover` reads. The rejected candidates are the "
            "provenance of the choice (#1079 rule).")
    return block, None


def verify_register(composed, selected):
    """The cover over the composed plain-register candidates.

    THE SAME DISCIPLINE AS ITS SIBLINGS, plus two checks this count owns: a
    candidate with no round-trip concession is refused (losslessness asserted
    silently is the derivation hazard's quiet form), and a rendering with no
    served cite is refused (a plain rendering of a claim the corpus does not
    carry is invention wearing simplicity's clothes).
    """
    refusals = []
    _check_over(composed, selected, refusals)
    candidates = composed.get("candidates") or []
    if len(candidates) < REGISTER_CANDIDATES_MIN:
        _refuse(refusals,
                f"{len(candidates)} register candidate(s) were composed; the "
                f"gate offers at least {REGISTER_CANDIDATES_MIN}. One "
                "candidate is the machine deciding the commitment with a "
                "question mark after it.")
    names = {str(s.get("name")) for s in selected}
    for n, cand in enumerate(candidates, 1):
        label = f"candidate {n}"
        if not str(cand.get("plain") or "").strip():
            _refuse(refusals,
                    f"{label} states no plain thesis — a candidate with no "
                    "translation offers nothing to commit to.")
        if not str(cand.get("concession") or "").strip():
            _refuse(refusals,
                    f"{label} carries no round-trip concession. State what "
                    "the translation loses — or that it loses nothing, and "
                    "say so: an unstated concession asserts losslessness "
                    "without being judged on it, which is the derivation "
                    "hazard in its quiet form (#1411).")
        rendered = {}
        for r in cand.get("renderings") or []:
            idx = str(r.get("index"))
            rendered[idx] = r
            if not str(r.get("plain") or "").strip():
                _refuse(refusals,
                        f"{label} renders {idx} with no plain text.")
            if not str(r.get("cite") or "").strip():
                _refuse(refusals,
                        f"{label} renders {idx} with no served-claim cite — a "
                        "plain rendering of a claim the corpus does not carry "
                        "is invention wearing simplicity's clothes.")
        omitted = {str(o.get("index")): str(o.get("why") or "").strip()
                   for o in (cand.get("omits") or [])}
        for s in selected:
            nm = str(s.get("name"))
            if nm in rendered:
                continue
            if nm in omitted:
                if not omitted[nm]:
                    _refuse(refusals,
                            f"{label} omits {nm} without a reason — an "
                            "omission is admissible only disclosed, by name.")
                continue
            _refuse(refusals,
                    f"{label} neither renders nor discloses {nm} — the close "
                    "composes these renderings, so a silent drop is a gap "
                    "the article's own ending will inherit.")
        for p in set(rendered) | set(omitted):
            if p not in names:
                _refuse(refusals,
                        f"{label} names {p}, which is not in the brief's "
                        "selected set.")
    return {"kind": "plain-register",
            "candidates": [str(c.get("plain") or "")[:80] for c in candidates],
            "complete": not refusals, "refusals": refusals}
