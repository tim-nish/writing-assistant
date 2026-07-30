"""A declared default resolves a single-axis choice — visibly, overridably
(Story 20.62, #945).

SPEC-article-draft-pipeline CAP-3, "Composition over an owner-selected Strand
set", second clause (2026-07-30, #945): the gate budget's discriminator is
**single-axis**, a property of the CHOICE. A one-axis choice resolves by
**declared default** with the resolved value **visible and overridable in the
plan** rather than merely logged; *several coherent structures with no policy
basis* is multi-outcome-with-no-policy-basis and **fires the gate**.

Four properties carry the clause:

  * VISIBLE IN THE PLAN — the resolution is a PLAN field
    (`resolved_defaults:`, schema in `write-article-plan.py`), not a journal
    line. "Merely logged" is the failure the clause names by name, so a log
    entry discharges nothing.
  * OVERRIDABLE WHERE SHOWN — the entry carries both the declared default and
    the VALUE IN EFFECT. Editing the value in the plan is the override, and
    composition proceeds on `resolved_choices` (the effective values) —
    no brief gate re-run, no re-selection of the Strand set.
  * THE AXIS COUNT IS THE TEST — `classify` reads `axes` and the declaration,
    and nothing else. The rejected alternative is named in the clause so it is
    not re-proposed: an "is this important enough to ask?" test degrades under
    time pressure while an axis count does not. No importance, confidence or
    severity judgment appears in this module, deliberately.
  * AN UNDECLARED DEFAULT IS NOT A DEFAULT — a single-axis choice with no
    declared default is NOT silently resolved; it fires the gate too, because
    silently privileging one resolution is exactly what the clause forbids.

Scope, stated: this module records and polices resolutions. It ships no
multi-axis arbitration — the clause deliberately lands before one exists, so
that the component is constrained before it is written rather than after.
"""


def classify(choice):
    """Resolve-by-default, or gate? The test is the choice's AXIS COUNT.

    `choice` is `{"name": …, "axes": <int>, "declared_default": {"value": …,
    "declared_in": …} | None, "policy_basis": <str|None>}`. Returns
    `{"resolution": "default"|"policy"|"gate", "axes": …, "why": …}`.

    Reads `axes`, `declared_default` and `policy_basis` — never how important,
    confident or severe the choice looks."""
    axes = choice.get("axes")
    name = choice.get("name") or "(unnamed choice)"
    if not isinstance(axes, int) or isinstance(axes, bool) or axes < 1:
        return {"resolution": "gate", "axes": axes,
                "why": f"{name}: no axis count is recorded, and the axis count "
                       "IS the test — an unclassified choice is asked, never "
                       "defaulted"}
    declared = choice.get("declared_default") or {}
    basis = str(choice.get("policy_basis") or "").strip()
    if axes > 1:
        if basis:
            return {"resolution": "policy", "axes": axes,
                    "why": f"{name}: {axes} axes, resolved by the policy basis "
                           f"{basis!r} — recorded visibly, not defaulted"}
        return {"resolution": "gate", "axes": axes,
                "why": f"{name}: {axes} axes with no policy basis — several "
                       "coherent outcomes fire the gate; no default is applied "
                       "to it, visibly or otherwise"}
    if not (declared.get("declared_in") and str(declared.get("value") or "").strip()):
        return {"resolution": "gate", "axes": axes,
                "why": f"{name}: one axis, but no default is DECLARED anywhere "
                       "— an undeclared default is not a default, so the choice "
                       "is asked rather than silently resolved"}
    return {"resolution": "default", "axes": axes,
            "why": f"{name}: one axis, resolved by the default declared in "
                   f"{declared['declared_in']!r} — visible and overridable in "
                   "the plan"}


def entries(fields, wap):
    """The plan's recorded resolutions, through the plan writer's OWN parser
    (one parser, never a second — the same posture `structure-record` takes to
    `STRUCTURE_PROVENANCE_RE`). Returns [] when the plan records none, which
    is the ideal path: nothing recorded, nothing asked."""
    if not wap or not fields or "resolved_defaults" not in fields:
        return []
    try:
        return wap.parse_resolved_defaults(fields["resolved_defaults"])
    except ValueError:
        return []


def plan_defects(fields, wap):
    """Defects a run must not report completion over. The writer refuses a
    malformed record at write; this is the read-side guard for a plan that
    reached the run some other way."""
    out = []
    if not wap or not fields or "resolved_defaults" not in fields:
        return out
    try:
        recorded = wap.parse_resolved_defaults(fields["resolved_defaults"])
    except ValueError as e:
        return [f"the plan's `resolved_defaults` is malformed — {e}"]
    for r in recorded:
        verdict = classify({"name": r["choice"], "axes": r["axes"],
                            "declared_default": {"value": r["default"],
                                                 "declared_in": r["declared_in"]}})
        if verdict["resolution"] != "default":
            out.append(
                f"the plan records {r['choice']!r} as resolved by a default, "
                f"but {verdict['why']}")
    return out


def disclosure(fields, wap):
    """What the run states about its defaulted choices — the payload the
    completion summary carries.

    `resolved_choices` is the EFFECTIVE value per choice: the owner's edited
    value when the plan's `value` differs from the declared `default`, the
    declared default otherwise. Composition proceeds on this, which is what
    makes the plan the place the override happens."""
    recorded = entries(fields, wap)
    if not recorded:
        return {}
    shown = []
    for r in recorded:
        shown.append({
            "choice": r["choice"], "value": r["value"],
            "default": r["default"], "declared_in": r["declared_in"],
            "resolved_by": "declared default" if r["value"] == r["default"]
                           else "owner override in the plan",
            "overridden": r["value"] != r["default"],
            "axes": r["axes"],
        })
    return {
        "resolved_defaults": shown,
        "resolved_choices": {r["choice"]: r["value"] for r in recorded},
        # Overridable WHERE SHOWN: the plan record itself. Changing the value
        # there re-runs neither the brief gate nor the Strand-set selection.
        "resolved_defaults_overridable_in": "plan:resolved_defaults",
    }
