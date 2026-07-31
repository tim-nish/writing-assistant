"""Candidate theses over the selected set, and k candidate briefs over a
proposed partition (Story 20.78; #995 and #988).

SPEC-terrain `presentation.md` CAP-3, two clauses added 2026-07-31: *"the gate
proposes 2–3 CANDIDATE THESES over the selected set, not one"* (#995) and *"a
large selection may be proposed as k article-scoped groups"* (#988). One module
for both, because #988 is this machinery applied to a **partition** rather than
to one set.

THE GROUNDING CORRECTION THIS MODULE EXISTS NOT TO INHERIT. #995 states that
*"today's coherence-consultant pass already computes the material"* for
candidate theses. **It does not.** `_consultant_block` computes exactly two
things — a `subject` list of member records and a complete, explicitly unranked
`substitution_candidates` pool — and nothing else. The core-vs-adjacent split
the owner observed at the gate was unpersisted judgment. Candidate theses are
therefore **new composition**, and what this module supplies is the composition
INPUTS, the REQUIREMENTS the output must satisfy, and the count that verifies
the result. It composes no thesis, because a thesis is a reading of material
and no deterministic join produces one — that is what the pre-20.78 join
proved, by producing a semicolon-joined coverage statement and calling it the
selection's thesis.

REQUIREMENTS ARE NOT A PROCEDURE, and the difference is the property an
existing check grep-asserts (`check-terrain-consultant-inner.sh`, the
no-fixed-procedure assertion). A procedure says how to arrive at candidates —
which is the narrow mechanism that reports success for satisfying its own steps
while failing what the owner wanted. A requirement says what must be true of
what arrives, and is checkable AFTER the fact without constraining the judgment
that produced it. Everything frozen here is of the second kind; the consultant
keeps its four rules and gains no steps.

THE COUNT RUNS AFTER COMPOSITION. `verify_cover` reads the COMPOSED candidates
— never the inputs they were composed from — because a composer that cannot
omit in principle can still omit in fact. It reuses `strand_cover.py`, the
downstream placement cover shipped by Story 20.61 (#945), rather than growing a
second cover with its own idea of what a placement is: the same discipline,
counted at the earlier gate.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from strand_cover import cover_report, strand_name  # noqa: E402

# HOW MANY CANDIDATES. Two is the smallest number that makes the step a
# CHOICE — one candidate is the pre-20.78 gate with a new label. Three is where
# it stops being a choice and becomes a reading task, which is the complaint
# the clause answers. Declared here, in one place, like every other terrain
# number.
THESIS_CANDIDATES_MIN = 2
THESIS_CANDIDATES_MAX = 3

# WHEN THE PARTITION IS OFFERED. Below this the k groups would hold two or
# three Strands each, which one thesis already carries — the observed instance
# was fifteen. THE THRESHOLD IS WHEN IT IS OFFERED, NEVER A GATE: a smaller
# selection may still be proposed as groups if the owner asks, and a larger one
# is never partitioned without the proposal being approved.
PARTITION_OFFER_MIN = 6

# The smallest proposal that IS a partition. One group restates the selection,
# so a k of one is not a modest proposal — it is no proposal, and `decline` is
# already the first-class way to say that.
PARTITION_MIN_GROUPS = 2

# What must be TRUE of the candidates that arrive. Not how to arrive at them.
THESIS_REQUIREMENTS = [
    "every candidate is composed over the SAME COMPLETE selected set — the "
    "candidates are alternative readings of one set, never a narrowing of it, "
    "and a candidate that silently drops a selected Strand is the failure "
    "this requirement exists to catch",
    "every candidate PLACES every selected Strand or DISCLOSES the omission "
    "by name with its reason — completeness here is a cover counted in "
    "placements, and the count runs after composition, not before",
    "every candidate cites the served rendering of each Strand it places, at "
    "this pin, and introduces no material from outside the served corpus",
    "the candidates are ENUMERATED, never ranked-and-trimmed — offering the "
    "strongest while discarding the rest is the narrowing the owner's own "
    "selection already did and the map does not",
    "free text wins at this step as at every other — the owner's own thesis "
    "is the brief, and every candidate is discarded when they write one",
    # THE RECOMMENDATION IS CONTRACT (Story 20.89, #1043). Added at the END so
    # the existing indices are stable — the 2026-07-31 amendment cites
    # THESIS_REQUIREMENTS[3] by number, and that clause is RETAINED: it bans
    # ranking COUPLED WITH TRIMMING, which this requirement does not license.
    # This is a requirement on the ARRIVING RECOMMENDATION, never on how the
    # assessment is reached — the list's own stated design, `:65` above.
    #
    # Why it must be here and not only in a host repository's CLAUDE.md: this
    # gate ships as a plugin drawn into host repos, which load their own
    # CLAUDE.md and never this one, so the ranked-recommendation guarantee held
    # only at home. That is the gap #1043 closes.
    "a RECOMMENDATION is offered BESIDE the candidates and never instead of "
    "any of them — machine-proposed and never machine-final; it NAMES THE "
    "AXES it assessed on and STATES WHAT WOULD OVERTURN it; and rank confers "
    "no default: no candidate is trimmed, hidden, reordered away, or "
    "abbreviated for having ranked lower",
]

# The same discipline over a partition. The one asymmetry against the list
# above is deliberate and is the clause's own wording: a thesis MAY omit a
# Strand as long as it says so, because a reading can leave material out and
# stay honest; a partition MAY NOT, because a proposed grouping that leaves a
# Strand nowhere has filtered the owner's selection.
PARTITION_REQUIREMENTS = [
    "the proposal runs under the proposal contract — approve / modify / "
    "decline — and is NEVER a silent restructure",
    "IT MUST NOT FILTER: every selected Strand lands in some proposed group. "
    "The owner may drop members, and only explicitly — a drop the machine "
    "made is filtering under another name",
    "each group is pinned to its own member subset and carries that subset's "
    "served cites, exactly as any composition over a set is",
    "a Strand that belongs in two groups is placed in both — this is a cover "
    "counted in placements, and forcing a tie-break would be the map deciding "
    "which relationship the owner is allowed to see",
    "k accepted briefs feed the DRAFTING BACKLOG, one run at a time — never k "
    "simultaneous publishes",
]


def coverage_statement(matches):
    """The members' served wordings, joined.

    THIS IS NOT A THESIS AND NO LONGER CLAIMS TO BE ONE (Story 20.78, #995).
    Until this story the identical join WAS the one thesis composed per
    selection, which is how the gate came to offer one thesis plus a narrowing
    option and the owner came to design the article from scratch in chat. It is
    kept, byte for byte, as what it always literally was: a coverage statement
    over the selected members, and the string the existing stage-0 `--brief`
    path carries until a candidate thesis is adopted. What changed is what it
    claims to be — the thesis now arrives as candidates, composed at the gate.
    """
    return "; ".join(m["direction"] for m in matches)


def thesis_candidates_block(members, pin, adopted_claim=None):
    """The gate's candidate-thesis proposal: inputs, requirements, and the
    count that will verify what comes back.

    NOTHING HERE IS A COMPOSED THESIS, and the block says so on its face
    (`composed: false`). The composition is the gate's, from `inputs` — the
    members' served claims and cites and nothing else, which is the same scope
    bound the `recomposition` block already carries, so a composer at the gate
    cannot widen the scope past what the owner pointed at.
    """
    return {
        "count": {"min": THESIS_CANDIDATES_MIN, "max": THESIS_CANDIDATES_MAX},
        # THE SAME COMPLETE SET, once, for every candidate. Stated as a field
        # rather than left implicit in the inputs, because it is what the cover
        # is counted against and what a candidate is refused for restating.
        "over": [m.get("index") for m in members],
        "inputs": list(members),
        "pin": pin,
        "composed": False,
        # WHAT IS TRUE OF THIS GATE, replacing `"ranked": False` (Story 20.89,
        # #1043). That field asserted a STRICTLY STRONGER property than the
        # requirement behind it: THESIS_REQUIREMENTS[3] bans ranked-AND-trimmed,
        # while `ranked: False` claimed no ordering exists at all. A run that
        # ranked, retained all three candidates whole and disclosed what would
        # overturn its pick therefore satisfied the requirement and contradicted
        # the field — and the field was the false carrier, not the behaviour.
        #
        # A STRUCTURED OBJECT rather than a scalar, decided in implementation:
        # the field's job is to state what the gate GUARANTEES, and four
        # properties cannot be carried by one boolean without the reader
        # inferring three of them. There is exactly one shipped reader
        # (`check-terrain-theses-inner.sh`), so legibility costs one assertion.
        #
        # The key is RENAMED, not re-valued: a key called `ranked` holding a
        # recommendation contract would preserve the vocabulary that made the
        # false claim readable in the first place.
        "recommendation": {
            # Offered beside the candidates, always — a gate presenting options
            # owes its own comparison, and the hardest input at a fork is the
            # comparison, not the options.
            "required": True,
            # Rank confers NO DEFAULT. Nothing is trimmed, hidden, reordered
            # away or abbreviated for ranking lower — which is the whole of
            # what THESIS_REQUIREMENTS[3] bans, retained and unweakened.
            "trims": False,
            "declares_axes": True,
            "declares_overturn": True,
            # Machine-PROPOSED, never machine-final: the owner chooses, and
            # nothing is pre-selected. Rank is not pre-selection.
            "machine_final": False,
        },
        "requirements": THESIS_REQUIREMENTS,
        # The form the composed candidates come back in, so the gate does not
        # invent one and the count has something fixed to read.
        "answer": {
            "kind": "candidate-theses",
            "over": [m.get("index") for m in members],
            "pin": pin,
            "candidates": [{
                "thesis": "<the reading, in one or two sentences>",
                "places": ["<index>", "..."],
                "omits": [{"index": "<index>", "why": "<why it is left out>"}],
                "grounds": [{"index": "<index>", "cite": "<its served cite>"}],
            }],
        },
        "verify": ("topic-map-directions.py cover --composed <that file> "
                   "--from <this brief artifact> — the count runs AFTER "
                   "composition and is not optional"),
        "adopt": ("pass the chosen candidate's thesis back as `claim` in the "
                  "answer; it supersedes the coverage statement and is pinned "
                  "to this same member set"),
        "state": "adopted" if adopted_claim else "candidates-pending",
    }


def partition_proposal_block(members, pin, offer_min=PARTITION_OFFER_MIN):
    """k candidate briefs over a proposed partition — or None, below the
    threshold at which the proposal is offered.

    POST-SELECTION, AND THAT IS THE WHOLE LICENCE. Subdividing an oversized
    group on the SERVING screens is a different capability (#980), bound by the
    terrain invariants rather than by the proposal contract; conflating them
    would put a machine partition upstream of the owner's selection, which is
    the one place the no-second-proposer boundary does engage. Here the owner
    has already narrowed, by selecting, so proposing that their selection is
    really k coherent theses narrows nothing.
    """
    if len(members) < offer_min:
        return None
    indexes = [m.get("index") for m in members]
    return {
        "offered": True,
        "n": len(members),
        "threshold": {
            "at": offer_min,
            "note": ("the threshold decides when this is OFFERED, never "
                     "whether it is allowed: a smaller selection may be "
                     "proposed as groups on request, and a larger one is "
                     "never partitioned without the proposal being approved"),
        },
        "over": indexes,
        "inputs": list(members),
        "pin": pin,
        "composed": False,
        "contract": {
            "options": ["approve", "modify", "decline"],
            "note": ("a proposal, never a silent restructure — declining "
                     "leaves the selection exactly as the owner made it"),
        },
        "requirements": PARTITION_REQUIREMENTS,
        "answer": {
            "kind": "partition",
            "over": indexes,
            "pin": pin,
            "groups": [{
                "label": "<what this group is about>",
                "members": ["<index>", "..."],
                "thesis": "<optional: the reading this group carries>",
            }],
            "dropped": [{"index": "<index>", "why": "<the owner's reason>",
                         "by": "owner"}],
        },
        "verify": ("topic-map-directions.py cover --composed <that file> "
                   "--from <this brief artifact> — the same count, over the "
                   "partition; a group set that leaves a Strand nowhere is "
                   "refused as filtering"),
        "handoff": ("one brief per approved group: run `brief` again with that "
                    "group's members as the selection and its own `--out` in "
                    "this same run workspace, so each brief is pinned to the "
                    "subset it was composed over"),
    }


# --------------------------------------------------------------------------
# THE COUNT, AFTER COMPOSITION
# --------------------------------------------------------------------------

def _selected(brief):
    """The member set the count is against: the one the BRIEF records.

    Never re-derived from the composed file, and never from the composer's own
    inputs — a set read back from the composition could not disclose an
    omission the composition made, which is the whole failure being guarded.
    """
    out = []
    for m in brief.get("members") or []:
        if isinstance(m, dict) and m.get("index"):
            out.append({"name": m["index"], "keys": [m["index"]], "member": m})
    return out


def _refuse(refusals, msg):
    refusals.append(msg)


def _check_over(composed, selected, refusals):
    over = [str(i) for i in (composed.get("over") or [])]
    names = [s["name"] for s in selected]
    if sorted(over) != sorted(names):
        _refuse(refusals,
                f"the composition states it is over {over or '[]'}, but the "
                f"brief's selected set is {names}. The cover is counted "
                "against the OWNER'S selection, never against a set the "
                "composer restated — a candidate composed over a different "
                "set is not a reading of this one.")


def _check_grounds(cand, selected, refusals, label):
    """AC4 — every placement carries the member's SERVED cite at this pin.

    An invented cite and a missing one fail the same way and for the same
    reason: a candidate is a reading of served material, and a placement
    nothing grounds is a claim the corpus does not carry.
    """
    cites = {s["name"]: (s["member"].get("cite") or "") for s in selected}
    got = {}
    for g in cand.get("grounds") or []:
        if isinstance(g, dict):
            got[str(g.get("index"))] = str(g.get("cite") or "")
        elif isinstance(g, str) and ":" in g:          # "L3: LESSONS.md:12@abc"
            i, _, c = g.partition(":")
            got[i.strip()] = c.strip()
    for idx in [str(p) for p in (cand.get("places") or [])]:
        if idx not in got or not got[idx]:
            _refuse(refusals,
                    f"{label} places {idx} and grounds it in nothing. Every "
                    "placement cites the Strand's served rendering at this "
                    "pin.")
        elif cites.get(idx) and got[idx] != cites[idx]:
            _refuse(refusals,
                    f"{label} cites {got[idx]!r} for {idx}, but the served "
                    f"cite at this pin is {cites[idx]!r}. A cite that is not "
                    "the served one is invented material.")


def _check_known(indexes, selected, refusals, label, what):
    names = {s["name"] for s in selected}
    for idx in indexes:
        if idx not in names:
            _refuse(refusals,
                    f"{label} {what} {idx}, which is not in the owner's "
                    f"selected set ({sorted(names)}). Nothing may enter here "
                    "that the owner did not select.")


def verify_theses(composed, selected):
    """The cover over 2–3 candidate theses (AC1-AC4).

    ANNOTATION, NEVER NARROWING: a candidate that omits a Strand AND SAYS SO
    is complete-with-disclosure and is still offered, with the omission named.
    What is refused is the whole proposal, back to the composer — never one
    candidate while the rest are offered, which would be the map choosing.
    """
    refusals = []
    _check_over(composed, selected, refusals)
    cands = composed.get("candidates") or []
    if not (THESIS_CANDIDATES_MIN <= len(cands) <= THESIS_CANDIDATES_MAX):
        _refuse(refusals,
                f"{len(cands)} candidate thesis/theses were composed; the gate "
                f"proposes {THESIS_CANDIDATES_MIN}–{THESIS_CANDIDATES_MAX}. "
                "One is the single-thesis gate this clause replaced; more is a "
                "reading task rather than a choice.")
    reports = []
    for n, cand in enumerate(cands, 1):
        label = f"candidate {n}"
        places = [str(p) for p in (cand.get("places") or [])]
        omits = cand.get("omits") or []
        _check_known(places, selected, refusals, label, "places")
        _check_known([str(o.get("index")) for o in omits if isinstance(o, dict)],
                     selected, refusals, label, "omits")
        for o in omits:
            if not isinstance(o, dict) or not str(o.get("why") or "").strip():
                _refuse(refusals,
                        f"{label} omits {o.get('index') if isinstance(o, dict) else o!r} "
                        "with no reason. An omission is admissible only "
                        "DISCLOSED — an undisclosed one is the silent drop "
                        "this count exists to catch.")
        _check_grounds(cand, selected, refusals, label)
        # THE COUNT ITSELF, over the EMITTED placements.
        cover = cover_report({"sections": places}, selected)
        disclosed = {str(o.get("index")) for o in omits if isinstance(o, dict)}
        undisclosed = [m for m in cover["omitted"]
                       if str(m.get("index")) not in disclosed]
        if undisclosed:
            _refuse(refusals,
                    f"{label} places {cover['placed']} of {cover['selected']} "
                    f"selected Strands and says nothing about "
                    f"{', '.join(strand_name(m) for m in undisclosed)}. Every "
                    "selected Strand is placed or its omission is disclosed; "
                    "silence is neither.")
        reports.append({
            "n": n,
            "thesis": cand.get("thesis"),
            "counted": "after-composition",
            "selected": cover["selected"],
            "placed": cover["placed"],
            "placements": cover["placements"],
            "omitted": [strand_name(m) for m in cover["omitted"]],
            "disclosed": sorted(disclosed),
            "undisclosed": [strand_name(m) for m in undisclosed],
            "complete": cover["complete"],
        })
    return {"kind": "candidate-theses", "candidates": reports,
            "complete": all(r["complete"] for r in reports) if reports else False,
            "refusals": refusals}


def verify_partition(composed, selected, brief_path=None):
    """The cover over a proposed partition (AC5-AC7).

    THE ASYMMETRY AGAINST `verify_theses` IS THE CLAUSE'S OWN: a thesis may
    omit a Strand with disclosure, a partition may not. A group set that leaves
    a Strand nowhere has filtered the owner's selection, and the only admissible
    absence is a drop the OWNER made, recorded as theirs.
    """
    refusals = []
    _check_over(composed, selected, refusals)
    groups = composed.get("groups") or []
    if len(groups) < PARTITION_MIN_GROUPS:
        _refuse(refusals,
                f"{len(groups)} group(s) proposed. A partition into fewer than "
                f"{PARTITION_MIN_GROUPS} groups proposes nothing — decline "
                "instead, which is a first-class outcome of the proposal "
                "contract.")
    dropped, drop_names = [], set()
    for d in composed.get("dropped") or []:
        idx = str(d.get("index")) if isinstance(d, dict) else str(d)
        if not isinstance(d, dict) or str(d.get("by") or "") != "owner" \
                or not str(d.get("why") or "").strip():
            _refuse(refusals,
                    f"{idx} is dropped without being recorded as the owner's "
                    "explicit act, with their reason. The owner may drop "
                    "members and only explicitly — an unattributed drop is "
                    "the machine filtering the selection.")
        else:
            dropped.append({"index": idx, "why": d.get("why")})
            drop_names.add(idx)
    placed_all, reports = [], []
    for n, g in enumerate(groups, 1):
        label = f"group {n}"
        mem = [str(x) for x in (g.get("members") or [])]
        _check_known(mem, selected, refusals, label, "holds")
        if not mem:
            _refuse(refusals, f"{label} holds no members.")
        if not str(g.get("label") or "").strip():
            _refuse(refusals,
                    f"{label} carries no label, so the owner cannot tell what "
                    "is being proposed about it.")
        placed_all.extend(mem)
        reports.append({"n": n, "label": g.get("label"), "thesis": g.get("thesis"),
                        "members": mem, "size": len(mem)})
    cover = cover_report({"sections": placed_all + sorted(drop_names)}, selected)
    if cover["omitted"]:
        _refuse(refusals,
                "the partition leaves "
                f"{', '.join(strand_name(m) for m in cover['omitted'])} in no "
                "group and records no owner drop for them. IT MUST NOT FILTER: "
                "every selected Strand lands in some proposed group.")
    # A COVER, NOT A PARTITION IN THE STRICT SENSE: a Strand in two groups is
    # reported, never refused. Forcing a tie-break would be the map deciding
    # which relationship the owner is allowed to see.
    shared = sorted({i for i in placed_all if placed_all.count(i) > 1})
    return {
        "kind": "partition",
        "counted": "after-composition",
        "selected": cover["selected"],
        "placed": cover["placed"],
        "placements": cover["placements"],
        "groups": reports,
        "shared": shared,
        "dropped": dropped,
        "complete": not cover["omitted"],
        "backlog": backlog_block(reports, brief_path),
        "refusals": refusals,
    }


def backlog_block(groups, brief_path=None):
    """AC7 — where k accepted briefs go.

    The hub's drip-not-dump policy, stated at the surface that produces the k:
    one run at a time. Nothing here starts a run; it names the order and the
    command, which is what makes "feeds the backlog" an observable outcome
    rather than an intention.
    """
    where = brief_path or "<this brief artifact>"
    return {
        "k": len(groups),
        "policy": ("k accepted briefs enter the drafting backlog ONE AT A "
                   "TIME — never k simultaneous publishes"),
        "order": [g.get("label") for g in groups],
        "briefs": [{
            "label": g.get("label"),
            "members": g.get("members"),
            "command": ("topic-map-directions.py brief --answer <answer "
                        f"selecting {', '.join(g.get('members') or [])}> "
                        "--map <map> --out <its own path in this workspace>"),
        } for g in groups],
        "from": where,
    }


def verify_cover(composed, brief, brief_path=None):
    """Route to the count the composed file asks for, and refuse an unrouteable
    one rather than guessing which discipline applies to it."""
    selected = _selected(brief)
    if not selected:
        return {"kind": "none", "complete": False,
                "refusals": ["the brief records no member set, so there is "
                             "nothing to count a cover against. A cover is "
                             "counted against the owner's selection."]}
    pin = str(composed.get("pin") or "").strip()
    bpin = str((brief.get("pins") or {}).get("terrain")
               or brief.get("pin") or "").strip()
    if pin and bpin and pin != bpin:
        return {"kind": composed.get("kind"), "complete": False,
                "refusals": [f"the composition is pinned at {pin} and the "
                             f"brief at {bpin}. Indexes only mean something "
                             "against the map they were read from, so the "
                             "count is refused rather than re-resolved."]}
    kind = str(composed.get("kind") or "").strip()
    if kind == "candidate-theses":
        return verify_theses(composed, selected)
    if kind == "partition":
        return verify_partition(composed, selected, brief_path)
    return {"kind": kind or None, "complete": False,
            "refusals": ["the composed file names no `kind`: it is either "
                         "`candidate-theses` or `partition`, and the two are "
                         "counted differently — a thesis may omit a Strand it "
                         "discloses, a partition may not."]}
