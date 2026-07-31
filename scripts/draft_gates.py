"""Owner-facing gate payloads, built once (Story 20.103, #1081).

THE RULE IS NOT NEW AND THIS DOES NOT DECIDE IT. The owner-facing proposal
contract has held since 2026-07-11 that selective presentation is the primary
interaction model and that collecting free-form answers where choices are
mandated is *a contract violation, not a presentation preference*; the hub
ratified the same on 2026-07-22. Two gates in one dogfood sitting were rendered
as chat prose anyway — and both already had the option lists a selector needs.
Nothing was missing but the rendering, which is the tell that the rule had no
CARRIER.

A rule is enforced only at the layer where it can be broken. That layer is the
agent's own composition step, which this product does not own, so a rule
written into a skill file is advisory, real, worth writing, and not a carrier.
The carrier therefore goes at the last boundary this repository controls: the
composed artifact. A gate emits its question as DATA and the rendering step
QUOTES it.

THE SHAPE IS THE ONE THAT ALREADY SHIPS, deliberately. `where` / `why` /
`choices[{label, effect}]` is the payload `validate-proposal-payload.py` has
gated since Story 10.1, with its budgets, its plain-text rule and its premise
grounding. Inventing a second vocabulary here would be the exact defect #1081
reports — gates without one carrier — committed in the act of fixing it.

WHAT THIS DOES NOT DO: it does not compose candidate theses. That gate's
options are composed by the agent from served material, and its payload is
assembled from those candidates at the point of composition; what is fixed
here is the SHAPE it must arrive in, not the composing.
"""

# Mirrors validate-proposal-payload.py, which is the enforcing copy. Kept here
# so a builder can refuse before emitting rather than after; the validator
# stays the authority and the check asserts the two agree.
BUDGETS = {"where": 240, "why": 200, "effect": 140}
MARKERS = ("**", "__", "`", "](")


def _plain(text, field):
    """The selection surface renders no Markdown, so a marker is a blocking
    defect in any presented field — not a cosmetic one. Ellipsis endings are
    refused for the same reason the validator refuses them: content is made to
    fit by AUTHORSHIP, never by clipping.
    """
    s = " ".join(str(text or "").split())
    if not s:
        raise ValueError(f"{field} is empty; every field is present and non-empty")
    for m in MARKERS:
        if m in s:
            raise ValueError(f"{field} carries the markup {m!r}, which the "
                             "selection surface cannot render")
    if s.endswith(("…", "...")):
        raise ValueError(f"{field} ends in an ellipsis — a mid-sentence cut; "
                         "write it shorter instead")
    budget = BUDGETS.get(field)
    if budget and len(s) > budget:
        raise ValueError(f"{field} is {len(s)} chars over its {budget} budget; "
                         "author it shorter rather than clipping")
    return s


def payload(where, why, choices, free_text=True):
    """One gate item in the shipped payload shape.

    `free_text` is TRUE by default and is the contract's other half: options
    plus a free-form override, never options alone. Options-only is a
    different violation of the same clause that prose-only violates.
    """
    item = {
        "where": _plain(where, "where"),
        "why": _plain(why, "why"),
        "choices": [{"label": _plain(c["label"], "effect"),
                     "effect": _plain(c["effect"], "effect")}
                    for c in choices],
    }
    if not item["choices"]:
        raise ValueError("a gate carries at least one choice")
    if free_text:
        # Recorded on the item so the renderer cannot drop the override
        # channel while faithfully quoting everything else.
        item["free_text"] = True
    return {"items": [item]}


def intent_gate(labels):
    """"What are you writing?" — the gate #1081 saw printed as prose.

    Its options were never missing: the closed intent set is data
    (`INTENT_LABELS`), which is why the issue calls this a rendering change
    rather than a redesign. The set is closed and unranked here — nothing is
    pre-selected, and no nearest-fit guess is made, because an unknown label is
    rejected rather than guessed at the resolving layer.

    THE LABEL IS THE OWNER'S PHRASE, NEVER THE ALIAS. `f1`-`f5` are declared
    internal/expert aliases that "never appear in owner-facing text", so the
    mapping's VALUE is the label and the key stays out of the payload
    entirely. Building the choices from the dict's keys is the obvious
    implementation and would have shipped the alias to the one surface it is
    barred from.
    """
    return payload(
        where="Stage 0, before any workspace is minted: the article type "
              "decides which framework the draft is filled from.",
        why="The category set is ratified and closed, so this is a choice "
            "among five, not free text to be matched.",
        choices=[{"label": phrase,
                  "effect": f"the draft is filled from the framework for "
                            f"'{phrase}'"}
                 for _, phrase in sorted(labels.items())],
    )
