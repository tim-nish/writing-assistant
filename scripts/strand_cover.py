"""The placement cover, counted AFTER composition (Story 20.61, #945).

SPEC-article-draft-pipeline CAP-3, "Composition over an owner-selected Strand
set" (2026-07-30, #945): the completeness rule follows the owner-selected
Strand set into DRAFTING, so a proposed structure PLACES every selected Strand
or DISCLOSES the omission BY NAME. Three properties carry the clause, and each
is a property of this code rather than of the composer's intent:

  * ORDERING — the count reads the COMPOSED candidate's actual placements
    (`sections`/`beats`), after `draft-pipeline.py`'s `_narrative_structures`
    has built them. A composer that cannot omit in principle can still omit in
    fact, so an argument about the algorithm discharges nothing.
  * COVER, NOT PARTITION — a Strand placed in two or more sections PASSES. A
    Strand carrying four tags belongs in four co-tag sections, and forcing it
    into one needs a tie-break, i.e. a machine deciding which relationship the
    owner may see. Only ZERO placements is an omission.
  * ANNOTATION, NOT NARROWING — the cover never reorders, filters, drops or
    chooses among candidates, and a candidate with omissions is still OFFERED,
    with the omitted Strands named. Anything that reduces what reaches the
    owner is on the far side of the second-proposer boundary this check exists
    to protect.

The member set counted against is the one the BRIEF records (`members`: index,
slug, served gloss, cite — SPEC-terrain `presentation.md` CAP-3, the
2026-07-30 / #937 selection-is-a-set clause). This module READS that set; it
never re-derives one, because a set derived from the composer's own inputs
could not disclose an omission the composer made. With no member set recorded,
no cover check is imposed and the output is exactly the pre-existing
element-selection path's.

Its own module rather than more of `draft-pipeline.py` for the budgeted-file
reason the check names (#759): the pipeline file is at its ratchet, and its
split shape is a spec decision, so new mechanism arrives beside it.
"""

import re


def selected_strands(brief):
    """The owner-selected Strand set the brief records, or [] when the input
    carries none (the pre-existing element-selection path, untouched)."""
    if not isinstance(brief, dict):
        return []
    members = brief.get("members")
    if not isinstance(members, list):
        return []
    out = []
    for m in members:
        if not isinstance(m, dict):
            continue
        keys = [m[k].strip() for k in ("index", "slug", "id")
                if isinstance(m.get(k), str) and m[k].strip()]
        if not keys:
            continue
        out.append({"name": keys[0], "keys": keys, "member": m})
    return out


def _norm(value):
    """One comparison form for an id: lowercased, with `:`/`_`/`/` folded to
    `-`. Element ids (`lesson:cache-warmth`) and Strand slugs (`cache-warmth`)
    name the same material in two shipped vocabularies, so the match is over
    normalized forms and their suffixes — never a fuzzy similarity, which
    would let a near-miss count as a placement."""
    return re.sub(r"[:_/\s]+", "-", str(value or "").strip().lower())


def candidate_placements(candidate):
    """A composed candidate's ACTUAL placements — its `sections` (one per
    element) or its `beats` (elements as beats of one thread). Read from the
    EMITTED candidate, never from the composer's inputs."""
    for key in ("sections", "beats"):
        seq = candidate.get(key)
        if isinstance(seq, list):
            return seq
    return []


def placement_count(strand, placements):
    """How many times this Strand is placed in a composed candidate. Zero is
    the only omission; two or more is a cover, not a defect."""
    keys = [k for k in (_norm(k) for k in strand["keys"]) if k]
    n = 0
    for p in placements:
        np = _norm(p)
        if np and any(np == k or np.endswith("-" + k) or k.endswith("-" + np)
                      for k in keys):
            n += 1
    return n


def cover_report(candidate, selected):
    """One candidate's cover: placement counts, and the omitted Strands named
    individually. Pure — it returns a report and changes no composition."""
    placements = candidate_placements(candidate)
    counts = {}
    omitted = []
    for s in selected:
        n = placement_count(s, placements)
        counts[s["name"]] = n
        if n == 0:
            omitted.append(s)
    return {
        "counted": "after-composition",
        "selected": len(selected),
        "placed": len(selected) - len(omitted),
        "placements": counts,
        "omitted": [{k: v for k, v in
                     (("index", s["member"].get("index")),
                      ("slug", s["member"].get("slug")),
                      ("gloss", s["member"].get("gloss"))) if v}
                    for s in omitted],
        "complete": not omitted,
    }


def strand_name(member):
    """How an omitted Strand is NAMED to the owner: its index and slug, both
    when both are recorded — an identifier is what makes "disclosed by name"
    checkable rather than a count."""
    idx = member.get("index")
    slug = member.get("slug")
    if idx and slug and idx != slug:
        return f"{idx} ({slug})"
    return str(idx or slug)


def apply_cover(out, brief):
    """Annotate every candidate with its OWN cover result, and disclose each
    omission by name in the rationale the owner reads.

    Per candidate, not just the default: choosing a non-default candidate must
    not silently choose an undisclosed omission. Annotation only: candidate
    order, membership and composition are untouched — the cover adds keys and
    extends rationales, and does nothing else."""
    selected = selected_strands(brief)
    if not selected:
        return out
    for cand in out["candidates"]:
        cover = cover_report(cand, selected)
        cand["cover"] = cover
        base = (cand.get("rationale") or "").rstrip()
        if cover["omitted"]:
            names = ", ".join(strand_name(m) for m in cover["omitted"])
            cand["rationale"] = (
                f"{base} Omits {len(cover['omitted'])} of {cover['selected']} "
                f"selected Strands: {names} — offered anyway, with the "
                "omission disclosed rather than the structure withheld.")
        else:
            cand["rationale"] = (
                f"{base} Places all {cover['selected']} selected Strands.")
    out["strand_cover"] = {
        "counted": "after-composition",
        "selected": [s["name"] for s in selected],
        "complete": all(c["cover"]["complete"] for c in out["candidates"]),
        "candidates": {c["structure"]: {
            "complete": c["cover"]["complete"],
            "omitted": [strand_name(m) for m in c["cover"]["omitted"]],
        } for c in out["candidates"]},
    }
    return out
