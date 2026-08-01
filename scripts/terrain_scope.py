#!/usr/bin/env python3
"""terrain_scope.py — the brief's HARVEST SCOPE, derived from the selected
members' served `projects:` (Story 20.144, #1097; SPEC-writing-assistant,
the 2026-08-02 (#1182/#1097/#1185/#1209) amendment).

Scope is DERIVED, NOT CHOSEN: which repositories may be examined for a
selection is the union of the selected Strands' `projects:` as the element
manifest serves them — never composed at a gate, and never re-derived from
lesson bodies, which is the consumer re-derivation class the hub ruled
against ("serve structure so there is nothing to parse"). This module is the
one place the union is computed, beside a file at its ratchet for the reason
`terrain_theses.py` states, so the examination stages consume the derivation
rather than repeating it.
"""


# THE ONE RECOGNIZED NON-REPOSITORY VALUE (Story 20.145, #1185). A
# non-repository `projects:` value is a SCOPE CLAIM, not an attribution
# (owner decision record — 2026-07-28 (projects: axis; portfolio-wide
# rider)): it renders as an explicit named section, never silently dropped
# and never expanded into a repository set. The manifest does not declare
# which values ARE repositories, and no allowlist of known repositories
# exists in this codebase to consult — so the classification of every other
# value is CANNOT-DETERMINE, parked behind the hub-side carrier requested
# for it and never re-derived here.
RECOGNIZED_NON_REPO = ("portfolio-wide",)


def examination_refusal(member, repository):
    """Whether `repository` may be examined for this member (Story 20.145,
    #1185): a Strand is examined only against the repositories its served
    `projects:` names. Returns None when the request is within the served
    attribution; otherwise the REFUSAL — refused, not searched, naming the
    Strand and its served attribution, because grounding a claim in a
    repository the experience did not happen in is a false attribution, the
    read-side counterpart of the hub's write-side deny rule.

    The rule lives here, where scope is derived and validated, so the
    examine stage (story 20.147) consumes it rather than restating it. The
    test is MEMBERSHIP in the served values and needs no classification: a
    scope-claim value like `portfolio-wide` is never a repository set, so it
    admits no repository through this test either.
    """
    p = (member or {}).get("projects") or {}
    vals = p.get("values")
    idx = (member or {}).get("index")
    slug = (member or {}).get("slug")
    who = f"{idx} ({slug})" if slug else str(idx)
    if not p.get("served") or not isinstance(vals, list):
        return {"refused": True, "member": idx, "attribution": None,
                "line": (
                    f"examination of {who} against {repository} is refused: "
                    "the element record at this pin serves no `projects:`, "
                    "so the scope cannot be derived — cannot-determine, "
                    "never searched on a guess")}
    if repository in vals:
        return None
    if not vals:
        return {"refused": True, "member": idx, "attribution": [],
                "line": (
                    f"examination of {who} against {repository} is refused: "
                    "its served `projects:` is empty — hub-only material, "
                    "its served arc is what it has; no repository grounds "
                    "it and none is searched")}
    return {"refused": True, "member": idx, "attribution": list(vals),
            "line": (
                f"examination of {who} against {repository} is refused, not "
                f"searched: its served `projects:` names "
                f"{', '.join(vals)} — grounding a claim in a repository the "
                "experience did not happen in is a false attribution")}


def harvest_scope_block(members):
    """The `harvest_scope` the brief carries: the union of the selected
    members' served `projects:` values, in first-seen member order.

    PER-MEMBER PROVENANCE SURVIVES THE UNION (`by_member`): a later refusal
    must be able to name the Strand whose attribution it enforces, and a bare
    union cannot say which member contributed which value.

    THE ABSENCE SHAPE IS THREE-VALUED AND TRUE OF THE PIN. At an older pin
    whose records do not carry `projects:`, the block states that staleness —
    never the retired "not served by the element manifest" claim, which the
    pinned manifest now falsifies (#1208's second defect died with that
    branch). A served empty list is not absence: it contributes nothing to
    the union and stays a fact about its Strand.
    """
    union, by_member, unserved = [], [], []
    for m in members or []:
        p = m.get("projects") or {}
        vals = p.get("values")
        if p.get("served") and isinstance(vals, list):
            by_member.append({"index": m.get("index"),
                              "projects": list(vals)})
            for v in vals:
                if v not in union:
                    union.append(v)
        else:
            unserved.append(str(m.get("index")))
    if unserved:
        return {
            "projects": None,
            "served": False,
            "not_served_reason": (
                "the element records at this pin carry no `projects:` for "
                + ", ".join(unserved)
                + " — the manifest at this pin predates the served field, "
                  "so the union is stated stale rather than re-derived from "
                  "lesson bodies"),
        }
    block = {"projects": union, "served": True, "by_member": by_member}
    # THE DERIVED EXAMINATION SCOPE (Story 20.145, #1185), per class and
    # never silently collapsed. Each named section is present only where it
    # has carriers — an absent section is absent, never present-and-empty —
    # which is also what keeps an alone-carrier of `portfolio-wide`
    # distinguishable from an empty-carrier.
    hub_only = [b["index"] for b in by_member if not b["projects"]]
    if hub_only:
        # AC2 — stated plainly, and NOTHING is minted from the absence: no
        # work item, no gate, no gap. Its served arc is what it has.
        block["hub_only"] = {
            "members": hub_only,
            "line": ("hub-only material — an empty `projects:` names no "
                     "repository; its served arc is what it has, and no "
                     "work item or gate is minted from the absence")}
    claims = [b["index"] for b in by_member
              if any(v in RECOGNIZED_NON_REPO for v in b["projects"])]
    if claims:
        # AC4 — an explicit named section: a SCOPE CLAIM, never an
        # attribution and never a repository set.
        block["portfolio_wide"] = {
            "members": claims,
            "classification": "scope claim, not an attribution",
            "line": ("`portfolio-wide` is a scope claim over the portfolio, "
                     "not a set of repositories — rendered here by name, "
                     "never silently dropped and never expanded")}
    cand = [v for v in union if v not in RECOGNIZED_NON_REPO]
    if cand:
        # AC5 — the same named-section shape, marked cannot-determine: the
        # manifest does not declare which values are repositories and no
        # repository allowlist exists here to consult, so the class parks
        # behind the upstream carrier. The examination BINDING needs no
        # class — it is membership in the served attribution
        # (`examination_refusal`), so these values still bound the scope.
        block["cannot_determine"] = {
            "values": cand,
            "classification": (
                "cannot-determine — the manifest does not declare which "
                "`projects:` values are repositories; the discriminator is "
                "an upstream carrier and is never re-derived here"),
        }
    # AC3 — the scope question has one answer when the union resolves to a
    # single repository-candidate value, and an answered question is not
    # asked.
    if len(cand) == 1:
        block["scope_question"] = {
            "needed": False, "answer": cand[0],
            "line": ("the scope union resolves to a single repository "
                     "candidate — the which-repository question has one "
                     "answer and is not asked")}
    elif not cand:
        block["scope_question"] = {
            "needed": False, "answer": None,
            "line": ("no repository-valued scope — the selection is "
                     "hub-only and/or portfolio-wide material")}
    else:
        block["scope_question"] = {
            "needed": True, "candidates": cand,
            "line": ("the scope union names more than one repository "
                     "candidate — the which-repository question is the "
                     "owner's")}
    return block
