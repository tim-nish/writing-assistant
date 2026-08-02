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

THE PAYLOAD DECLARES ITS RENDER FORM (Story 20.107, #1102). The clause above
ended at "the rendering step QUOTES it" and said nothing about what a
conforming rendering IS — so one sitting later, seven minutes after 20.103
merged, five gates still reached the owner as prose. Measured rather than
assumed: the reporting run's `intent.payload.json` exists and its
`presented-payloads.jsonl` records the ask with its choices. The payload was
emitted, validated, and then narrated.

Worse, the clause was UNSATISFIABLE at a shipped surface: the host control
admits four options and terrain's Strand pick offers roughly fifty. A clause
that cannot be obeyed where it governs is not strict but absent, because the
first gate that cannot comply teaches that compliance is optional everywhere.
So `render` is emitted with every payload — `control` COMPUTED from the choice
count against the capacity, never authored, so a builder cannot declare the
wrong one; `recommended` an INDEX rather than a label, because a label drifts
the moment wording changes.

THE HONEST LIMIT, recorded because it is what the next instance is measured
against: nothing here can force the rendering step to call the control. Where
the violating layer belongs to another system the remedy is to SHRINK the
free-form surface rather than lint it, and a payload declaring its own render
form leaves nothing free-form to compose. The excuse is removed, not the
possibility.
"""

import os

# The host selection control admits 2-4 options. This is the capacity the
# render form is computed against, declared once here and imported by the
# check rather than restated in it.
CONTROL_CAPACITY = 4

# A closed set overflowing the capacity by AT MOST this margin still renders
# as a selection, with the members past the capacity declared in
# `render.overflow` and named in the question text (amended 2026-08-02,
# #1206). Block form was written for the ≈50-Strand terrain listing and
# silently claimed the intent gate, whose ratified closed set is exactly
# five — permanently above capacity by one, by construction. Above the
# margin, block form stands unchanged.
OVERFLOW_MARGIN = 2

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


def render_form(choices, recommended=None, banner=None, reply_line=None):
    """The `render` directive for a choice set (Story 20.107, #1102).

    `control` is COMPUTED, never accepted as an argument: it follows from the
    choice count against `CONTROL_CAPACITY`, so the invalid states — declaring
    `selection` for a six-option payload, or `block` for a three-option one —
    are unrepresentable rather than caught after the fact.

    `banner` and `reply_line` are REQUIRED for a block and refused for a
    selection. A block is a rendering of the payload, not a licence to narrate
    it, so the fields a decision block needs are carried BY the payload — if
    the renderer had to invent them, the block would be exactly the free-form
    composition this whole carrier exists to remove.

    A SMALL OVERFLOW IS STILL A SELECTION (amended 2026-08-02, #1206). A set
    exceeding the capacity by at most `OVERFLOW_MARGIN` declares `overflow`:
    the top-ranked members fill the control with the recommendation first,
    and the remainder are full citizens of the choice whose only difference
    is the entry path — the control's built-in free-text entry, with each
    member named in the question text (which `payload` enforces). Above the
    margin, the block form stands exactly as #1102 wrote it.
    """
    n = len(choices)
    control = "selection" if n <= CONTROL_CAPACITY + OVERFLOW_MARGIN else "block"
    form = {"control": control, "recommended": None}
    if recommended is not None:
        if not isinstance(recommended, int) or isinstance(recommended, bool):
            raise ValueError("recommended is an INDEX into choices, not a "
                             "label — a label drifts when wording changes")
        if not 0 <= recommended < len(choices):
            raise ValueError(f"recommended index {recommended} is outside the "
                             f"{len(choices)} choices")
        # The recommended option leads. Rank is not pre-selection: nothing is
        # selected, and the free-text channel is untouched.
        form["recommended"] = 0
    if control == "selection" and n > CONTROL_CAPACITY:
        # Computed from the recommendation-first order, never authored: the
        # members past the capacity are exactly the tail of the ordered set.
        ordered = choices
        if recommended:
            ordered = [choices[recommended]] + [c for i, c in
                                                enumerate(choices)
                                                if i != recommended]
        form["overflow"] = [" ".join(str(c["label"]).split())
                            for c in ordered[CONTROL_CAPACITY:]]
    if control == "block":
        if not banner or not reply_line:
            raise ValueError(
                f"{len(choices)} choices exceed the control capacity of "
                f"{CONTROL_CAPACITY}, so this renders as a block and owes a "
                "banner and a reply_line; without them the renderer would "
                "compose them itself")
        form["banner"] = _plain(banner, "banner")
        form["reply_line"] = _plain(reply_line, "reply_line")
    elif banner or reply_line:
        raise ValueError("banner/reply_line belong to the block form; this "
                         "payload fits the selection control")
    return form


# --------------------------------------------------------------------------
# THE GATE REGISTRY (Story 20.118, #1114) — every owner-facing gate this
# repository composes, declared in one place.
#
# WHY A REGISTRY AND NOT ONLY AN EMIT CALL. #1114's CONSTRAIN half asks that a
# gate surface be composed only by the emitter that writes its payload — but an
# emit call still lets a NEW surface be written that never calls it, which is
# exactly how the thesis gate came to reach the owner with no payload at all
# and nothing failing. A declared id closes that: `payload()` refuses an
# undeclared gate, so composing a surface the registry does not know is an
# error at the moment of composition rather than an absence discovered later.
#
# IT IS ALSO THE INVENTORY TWO OTHER STORIES NEED. Story 20.119 asserts a run's
# gates against its payload log and needs the left-hand side; story 20.117
# renders the owner decisions still pending and its AC3 forbids a hand-listed
# map — *"a hardcoded list is a conformance copy with no precedence rule and
# drifts the first time a gate moves"*. Both derive from here, so the three
# stories share one authority instead of three copies of one list.
#
# `owner_decision` is what 20.117 renders: the decision the owner still owes at
# that gate, or None where the gate asks nothing the owner must carry forward.
GATES = {
    # IN PIPELINE ORDER, and the order is load-bearing: story 20.117 renders
    # this as "where each decision is asked", so a registry sorted any other
    # way would tell the owner that sources comes before the terrain screens.
    "terrain-axis": {
        "stage": "terrain screen 1",
        "owner_decision": "where to look first — one axis member",
    },
    "terrain-member": {
        "stage": "terrain screen 2",
        "owner_decision": "which Strands the brief is composed from",
    },
    "thesis": {
        "stage": "terrain step 3",
        "owner_decision": "the thesis — which candidate the brief adopts",
    },
    "resume-confirmation": {
        "stage": "stage 0",
        "owner_decision": None,   # asked only when a run predates the sitting
    },
    "intent": {
        "stage": "stage 0",
        "owner_decision": "intent — which article type the draft is filled from",
    },
    # `sources` WAS HERE (stage 0) and is retired (Story 20.147, #1209): the
    # scope-selection ask retired with harvest — scope is derived from the
    # brief's examine_scope, never composed or approved at a gate. See the
    # retirement note at the end of this module.
    # THE TRANSITION *INTO* HARVEST (Story 20.136, #1176). It was outside the
    # registry entirely: a terrain sitting ends at a STAGED stage-0 run, and the
    # ask that decides whether stage 1 runs at all reached the owner as chat
    # prose — *"Say the word and I'll run harvest"* — answered in free text,
    # with no ask row anywhere. `harvest-completion` covered the transition
    # OUT of harvest, covered nothing here, and is itself retired below.
    #
    # DECLARING IT IS NOT THE REMEDY FOR THE CLASS, and the amendment that
    # orders this story says so in as many words (`specs/spec-writing-assistant/
    # amendments-2026-07-24--2026-08-01.md`, 2026-08-01 #1176/#1177, clause
    # (a)): this is the sixth surface closed by declaring the missing id, and
    # persistence through one remedy class is evidence about the attribution
    # rather than the dose. The entry closes this INSTANCE. What is done about
    # the CLASS is the STATED LIMIT — no carrier is possible at the agent's own
    # composition step, so `gate-inventory.py` and the checks that iterate this
    # dict now say what they do not cover, rather than reading as clean.
    "probe-entry": {
        "stage": "after stage 0, before probe",
        "owner_decision": "run probe now, or stop with the brief kept",
    },
    # `harvest-completion` WAS HERE and is RETIRED (Story 20.148, #1223).
    # It declared `owner_decision: "continue into drafting, or stop with the
    # fact sheet kept"` — an owner choice about leaving a stage that no longer
    # exists, and the last remnant of harvest reaching the owner's screen
    # verbatim (observed in the 2026-08-02 run). There is no fact sheet to keep
    # and no transition out of harvest to gate, so the entry is deleted rather
    # than reworded: a gate is retired at the registry that declares it, never
    # at the surface that renders it.
    #
    # The gate id above was `harvest-entry` until the same story. It has always
    # named the transition into stage 1; stage 1 has been `probe` since Story
    # 20.146 (#1210), and the id reached the owner as a `gate:` field, so the
    # stale name was owner-facing rather than internal.
    # BEFORE `gap-interview`, and the order is the pipeline's: the policy-topic
    # selection runs *before* questions are selected, because it fixes which
    # recorded positions may raise a tension at all
    # (`skills/draft-article/stages/stage2.md` — "Before selecting questions").
    #
    # IT WAS OUTSIDE THE REGISTRY ENTIRELY (Story 20.127, #1144). CAP-2's
    # two-step selection has asked the owner to pick ≤2 topic files since #230,
    # and declared nothing here — so it sat outside the payload audit and the
    # pending-decision map, which is what "a run's gates are auditable"
    # (#1132) forbids. An owner screen with no declared id leaves no event, so
    # nothing could assert it emitted; that is the #1114 defect, reached by a
    # surface old enough that no story had looked at it.
    #
    # THE COLD-RUN BRANCH IS THE ONLY BRANCH — the second one was RETRACTED
    # (2026-08-01, #1168), not left pending. The #1144 amendment had ratified a
    # DERIVED disclosure for a brief-carrying run, carrying `owner_decision:
    # None` on the `resume-confirmation` shape. Its `Strand → lesson → served
    # topic` derivation needs a join the hub does not serve — screen 1's axis
    # is tags precisely because no served Lesson→Topic join exists — so the
    # premise was measured false and the derivation half was withdrawn; see
    # `specs/spec-policy-topic-at-draft/amendments.md`. Declaring a second id
    # here would put a gate in the inventory that no code path can reach.
    # The registry states what a run can actually present.
    "policy-topics": {
        "stage": "stage 2",
        "owner_decision": "which ≤2 policy topics this article's tension "
                          "questions may be seeded from",
    },
    "gap-interview": {
        "stage": "stage 2",
        "owner_decision": "the gap interview — what only you can answer",
    },
    "narrative-structure": {
        "stage": "stage 3",
        "owner_decision": "narrative structure — which arc the article takes",
    },
    "visual-set": {
        "stage": "stage 3",
        "owner_decision": "the visual set — which figures the article carries",
    },
}

# DECLARED BUT NOT YET CODE-COMPOSED (Story 20.118 step 3, #1114): `thesis`,
# `policy-topics`, `gap-interview`, `narrative-structure`, `visual-set`
# (`policy-topics` JOINED this list at Story 20.127, #1144 — it is declared so
# the audit can report it as reached-but-never-emitted, which is the honest
# state of a surface that has reached owners since #230 with no ask row at all)
# (`harvest-completion` LEFT this list at Story 20.129, #1143 when it gained a
# builder, and the gate itself is RETIRED at Story 20.148, #1223 — the stage
# it gated no longer exists)
# reach the owner from the SKILL prompt, not from a script — which is the whole
# of what #1114 reports: a surface with no code site leaves no event, so nothing
# can assert it emitted. They are declared here anyway, deliberately: story
# 20.117's map must name the stage-3 gates or it hands the owner a map missing
# exactly the decisions they went looking for, and story 20.119's audit now
# reports each as reached-but-never-emitted — a FINDING, which is the honest
# state, rather than the silence that shipped.


def declared_gates():
    """The registry, for consumers that render or assert over it.

    Returned as a copy so a reader cannot mutate the authority it is reading —
    the failure mode a shared dict invites, and the reason this is a function
    rather than the bare name.
    """
    return {k: dict(v) for k, v in GATES.items()}


def emit(built, ws, gate):
    """Record that a gate was PRESENTED, in the run's own payload log.

    Best-effort on the write and strict on the id: an unwritable workspace
    degrades the receipt, which is a worse run rather than a wrong one, while
    an undeclared gate is a programming error that must not reach an owner.

    RECORDING IS NOT ANSWERING. This row says a question was put; the answer
    row is a separate act by whoever collects it. A reader of the log can tell
    the two apart by `kind`.
    """
    if gate not in GATES:
        raise ValueError(
            f"gate {gate!r} is not declared in GATES — declare it beside the "
            f"others so the inventory (Story 20.119) and the pending-decision "
            f"map (Story 20.117) can see it")
    if not ws:
        return built
    import json
    import os
    try:
        with open(os.path.join(ws, "presented-payloads.jsonl"), "a",
                  encoding="utf-8") as f:
            f.write(json.dumps({"kind": "ask", "gate": gate,
                                "stage": GATES[gate]["stage"],
                                "items": built.get("items", [])},
                               ensure_ascii=False) + "\n")
    except OSError:
        pass
    return built


def payload(where, why, choices, free_text=True, recommended=None,
            banner=None, reply_line=None, gate=None, ws=None,
            no_recommendation=None):
    """One gate item in the shipped payload shape.

    `free_text` is TRUE by default and is the contract's other half: options
    plus a free-form override, never options alone. Options-only is a
    different violation of the same clause that prose-only violates.

    `recommended` names the index of the option this gate recommends, and the
    builder MOVES it to the front rather than trusting the caller to have
    ordered it — the render directive then reads `recommended: 0`, so the
    directive and the ordering cannot disagree.
    """
    choices = list(choices)
    if not choices:
        raise ValueError("a gate carries at least one choice")
    form = render_form(choices, recommended, banner, reply_line)
    if recommended:
        choices = [choices[recommended]] + [c for i, c in enumerate(choices)
                                            if i != recommended]
    item = {
        "where": _plain(where, "where"),
        "why": _plain(why, "why"),
        "choices": [{"label": _plain(c["label"], "effect"),
                     "effect": _plain(c["effect"], "effect")}
                    for c in choices],
        "render": form,
    }
    if no_recommendation:
        # THE DECLARED ABSENCE (Story 20.152, #1222). An ask with several
        # options owes the machine's comparison; where the machine genuinely
        # has no basis to rank — an owner's editorial intent, say — the
        # honest form is to SAY SO in the payload rather than to leave the
        # field empty, because an empty field and a considered "I cannot
        # rank these" are indistinguishable to every reader and every check.
        item["no_recommendation"] = _plain(no_recommendation,
                                           "no_recommendation")
    if form.get("overflow"):
        # DISCLOSED, NEVER HIDDEN (#1206): an overflow member's entry path is
        # the free-text channel, so the channel must exist and the member must
        # be named where the owner reads the question — otherwise the option
        # is hidden, not overflowed.
        if not free_text:
            raise ValueError("an overflow member is reachable only through "
                             "the free-text entry; free_text cannot be "
                             "disabled on an overflowing selection")
        question = f"{item['where']} {item['why']}"
        for label in form["overflow"]:
            if label not in question:
                raise ValueError(f"the overflow member {label!r} is not named "
                                 "in the question text — an overflow is "
                                 "disclosed, never hidden")
    if free_text:
        # Recorded on the item so the renderer cannot drop the override
        # channel while faithfully quoting everything else.
        item["free_text"] = True
    built = {"items": [item]}
    # ASKING IS EMITTING (Story 20.118, #1114). A declared gate id is checked
    # even when no workspace is available to write to: the check that matters
    # is that the surface is KNOWN, and it must not be skippable just because
    # a caller happens to have nowhere to record.
    if gate is not None:
        built = emit(built, ws, gate)
    return built


def gate(gate_id, where, why, choices, ws=None, free_text=True,
         recommended=None, banner=None, reply_line=None):
    """Compose ANY declared gate (Story 20.122, #1135).

    ONE BUILDER, NOT FIVE. The gates that reached the owner as prose did so
    because the skill files had no function to name — a skill instructs the
    agent by naming a `draft_gates` builder, and the one gate the 2026-08-01
    run confirms reached the host control was the one with a builder to call.
    The five that leaked had nothing to call.

    Five near-identical builders would have been five places for the NEXT gate
    to be added without one. The registry declares *what* gates exist; this
    emits *any* of them, so adding a gate is one entry in `GATES` plus a call —
    and the entry is what `payload()` validates against, so the call cannot
    exist without the declaration.

    Content-shaped arguments are the caller's because they genuinely differ: a
    thesis gate carries composed candidates, the harvest completion carries
    next steps, the gap interview carries questions. What does NOT differ is
    that composing means emitting, and that is what lives here.
    """
    return payload(where=where, why=why, choices=choices, free_text=free_text,
                   recommended=recommended, banner=banner,
                   reply_line=reply_line, gate=gate_id, ws=ws)


def intent_gate(labels, ws=None):
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

    THIS GATE IS THE CAPACITY BOUNDARY'S FIRST INSTANCE (Story 20.107, #1102),
    AND THE MARGIN'S (amended 2026-08-02, #1206). The closed set has FIVE
    members and the host control admits four, so #1102 made block form this
    gate's permanent fate — not a degraded path but the only path, on every
    run, by construction. Within the margin the selection stands: the first
    four labels fill the control and the remainder ride in `render.overflow`,
    each named in the question text and entered through the control's own
    free-text channel.
    """
    ordered = [phrase for _, phrase in sorted(labels.items())]
    choices = [{"label": phrase,
                "effect": f"the draft is filled from the framework for "
                          f"'{phrase}'"}
               for phrase in ordered]
    why = (f"The category set is ratified and closed, so this is a choice "
           f"among {len(ordered)}, not free text to be matched.")
    if CONTROL_CAPACITY < len(ordered) <= CONTROL_CAPACITY + OVERFLOW_MARGIN:
        named = "; ".join(f"'{p}'" for p in ordered[CONTROL_CAPACITY:])
        why += f" Also on offer, entered as free text: {named}."
    return payload(
        where="Before any drafting starts: the article type decides which "
              "shape the draft is written in.",
        why=why,
        choices=choices,
        gate="intent", ws=ws,
        # NO RECOMMENDATION, DECLARED (Story 20.152, #1222). An ask offering
        # several options owes the machine's own comparison — that is the
        # standing fork-gate rule and this validator now enforces it. This is
        # the honest exception rather than a waiver: the five article types are
        # the OWNER'S EDITORIAL INTENT, and nothing the machine has read ranks
        # "introduce the project" against "share engineering lessons". A
        # recommendation here would be a default wearing a suggestion's
        # clothes, which is exactly what that rule forbids.
        no_recommendation="the article type is the owner's editorial intent; "
                          "nothing the machine has read ranks one against "
                          "another",
    )


def probe_entry_gate(source_count, ws=None, brief=True):
    """"Run probe now, or stop?" — the ask #1176 saw as chat prose.

    THE STAGE BEHIND THE GATE CHANGED, NOT THE GATE (amended 2026-08-02,
    #1182): stage 1 is `probe` — a feasibility verdict plus a handful of
    anchors, no fact sheet — so the ask names what actually runs. The id
    keeps its registry name; renaming it would touch every audit row for a
    surface whose decision is unchanged.

    THE RUN KIND NO ENUMERATION NAMED. `skills/completion-summary.md` mandated
    a selection for four run kinds — draft, standalone harvest, review,
    partially-completed — and a terrain sitting ending at a STAGED stage-0 run
    is none of them, so the mandate had no case to bind and the surface fell
    through to prose (*"Say the word and I'll run harvest"*). The list's
    non-member fallback was `admit`; that is the defect, not the list's
    contents, and the rule is now total. This builder is what the total rule
    has to call at this boundary.

    NOTHING IS LOST ON EITHER BRANCH, and the `why` says so, because that is
    the fact that makes the choice answerable without opening anything: the
    brief and the staged run are already written, so stopping is a pause rather
    than a discard. The scope is named as a COUNT of declared sources, never as
    a file list — which files carry the evidence is the reading step's own
    business, never an answer owed at a gate (#1209).
    """
    kept = "brief" if brief else "staged run"
    return payload(
        where="The run is set up with its article type and its sources, and "
              "nothing has been read yet.",
        why=f"Probe checks whether the {source_count} declared source(s) can "
            f"ground this brief, and points at where the evidence sits. The "
            f"{kept} and the staged run are already written, so stopping "
            f"loses nothing.",
        choices=[
            {"label": "run probe now",
             "effect": f"judges feasibility against the {source_count} "
                       f"declared source(s); a doomed article dies here, a "
                       f"grounded one carries on into drafting"},
            {"label": f"stop with the {kept} kept",
             "effect": "keeps everything written so far exactly as it is; "
                       "nothing is read and the run stays resumable"},
        ],
        gate="probe-entry", ws=ws,
        recommended=0,
    )


# `harvest_completion_gate` WAS HERE and is RETIRED with its registry entry
# (Story 20.148, #1223). It was built at Story 20.129 (#1143) to give the
# "continue into drafting, or stop with the fact sheet kept" surface a builder,
# because a surface with no builder is composed freely every time. That reason
# was right and is now moot: the surface itself is gone with the stage, so
# there is nothing left to compose. The counts-in-the-`why` pattern it
# introduced survives in the gates that still exist.

# THE SOURCES GATE IS RETIRED (Story 20.147, #1209; amended 2026-08-02,
# #1182/#1097/#1185/#1209). `sources_gate`, its scope vocabulary
# (`SCOPE_KINDS`) and its in-gate enumeration (`declared_scope`, #1178) lived
# here until the stage that owed the ask retired with harvest. The gate's own
# premise — a human-approved enumeration of what may be read — is the
# circularity the upstream ruling names: the 2026-08-01 defect (recommending
# "all declared sources", 423 files, 78% code, to an episode-claims article)
# is not fixable AT a gate whose question should not exist. The owner supplies
# at most a REGION at the brief; which repositories may be examined is DERIVED
# (`terrain_scope.py` — the union of the selected Strands' served
# `projects:`), and the per-claim examine step (`examine.py`) does its own
# enumerating at the read. No gate asks the owner to compose or approve a
# file list, so the #1209 shape is unconstructible rather than discouraged.
