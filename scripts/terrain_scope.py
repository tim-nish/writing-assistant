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
    return {"projects": union, "served": True, "by_member": by_member}
