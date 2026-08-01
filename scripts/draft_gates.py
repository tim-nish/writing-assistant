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
    """
    control = "selection" if len(choices) <= CONTROL_CAPACITY else "block"
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
    "sources": {
        "stage": "stage 0",
        "owner_decision": "sources — the scope harvest reads",
    },
    "harvest-completion": {
        "stage": "after harvest",
        # NOT None (Story 20.129, #1143). It read "next-step options; nothing
        # is carried forward" — but a two-option owner choice recorded as no
        # owner decision is invisible to the pending-decision map, which is
        # why nothing forced it through the selection UI and it reached the
        # owner as prose answered by free text on 2026-08-01.
        "owner_decision": "continue into drafting, or stop with the fact "
                          "sheet kept",
    },
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
    # ONLY THE COLD-RUN BRANCH IS DECLARED HERE, and the absence is deliberate
    # rather than an oversight. The #1144 amendment ratifies a SECOND branch —
    # for a brief-carrying run the set is DERIVED and rendered as a disclosure,
    # which would carry `owner_decision: None` on the `resume-confirmation`
    # shape. That branch is not implemented: its `Strand → lesson → served
    # topic` derivation needs a join the hub does not serve (screen 1's axis is
    # tags precisely because no served Lesson→Topic join exists), so declaring
    # its id now would put a gate in the inventory that no code path can reach.
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
# (`harvest-completion` LEFT this list at Story 20.129, #1143 — it has a
# builder below, so its surface can no longer be composed without an ask row)
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
            banner=None, reply_line=None, gate=None, ws=None):
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
    because the skill files had no function to name — `stage0.md:73` instructs
    the agent by naming `draft_gates.sources_gate(...)`, and the sources gate is
    the one surface the 2026-08-01 run confirms reached the host control. The
    five that leaked had nothing to call.

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

    THIS GATE IS THE CAPACITY BOUNDARY'S FIRST INSTANCE (Story 20.107, #1102).
    The closed set has FIVE members and the host control admits four, so the
    gate 20.103 converted is itself over capacity and renders as a block. That
    is the boundary being real rather than hypothetical: had the render form
    been left to the renderer, this gate would have had to invent a form on the
    spot, which is the prose the whole carrier exists to prevent.
    """
    choices = [{"label": phrase,
                "effect": f"the draft is filled from the framework for "
                          f"'{phrase}'"}
               for _, phrase in sorted(labels.items())]
    return payload(
        where="Stage 0, before any workspace is minted: the article type "
              "decides which framework the draft is filled from.",
        why="The category set is ratified and closed, so this is a choice "
            "among five, not free text to be matched.",
        choices=choices,
        gate="intent", ws=ws,
        banner="Choose the article type before drafting starts.",
        reply_line="Reply with one article type from the list, or describe "
                   "the piece you have in mind.",
    )


def harvest_completion_gate(fact_count, needs_owner_count, ws=None,
                            blockers=0):
    """"Continue, or stop with the fact sheet?" — the gate #1143 saw as prose.

    THE CONTRACT EXISTED TWICE AND THE EMITTER DID NOT. `GATES` declared this
    gate, `skills/harvest/SKILL.md` mandated the carrier and even recorded the
    2026-08-01 failure shape, and `skills/completion-summary.md` named the
    selection UI — and the choice still reached the owner as two prose bullets
    answered by typing, on a run at code that already carried all three. A
    surface with no builder to call is composed freely every time, however many
    documents say it should not be.

    THE COUNTS ARE THE WHY, NOT DECORATION. What makes this answerable without
    opening the fact sheet is knowing what the harvest produced — so the counts
    ride in the `why`, which is the field the owner reads before choosing. That
    is the interaction contract's own requirement: the choice is "drafted from
    what this run produced… so the owner decides by selecting, not by opening
    the fact sheet".

    A run with publish blockers says so HERE. Continuing past one is a
    different decision from continuing past none, and a gate that renders both
    identically has hidden the difference at the moment it mattered.
    """
    why = (f"Harvest produced {fact_count} sourced fact(s) and "
           f"{needs_owner_count} item(s) only you can answer.")
    if blockers:
        why += f" {blockers} publish blocker(s) are open."
    return payload(
        where="After harvest: the fact sheet is written and validated; "
              "drafting has not started.",
        why=why,
        choices=[
            {"label": "continue into draft-article",
             "effect": f"runs the gap interview over the {needs_owner_count} "
                       f"open item(s), then framework fill and verification"},
            {"label": "stop here",
             "effect": "keeps the fact sheet as it is; the run stays "
                       "resumable from harvest and nothing is discarded"},
        ],
        gate="harvest-completion", ws=ws,
        recommended=0,
    )


# The scope vocabulary the stage-0 sources ask offers (Story 20.109, #1103).
# EVERY MEMBER NARROWS. "all declared sources" is the whole of the host's
# writing-sources.yaml, never the whole filesystem — the stage-0 selection is a
# filter and never a scope widener, and that invariant is restated here rather
# than re-decided, because a scope vocabulary is exactly where a widener would
# enter unnoticed.
SCOPE_KINDS = ("all", "subtree", "commit-range")


def sources_gate(declared_count, default_kind="all", default_detail=None, ws=None,
                 candidates=(), reason=None, repo_root=None,
                 declaring_file="writing-sources.yaml"):
    """"Where does the evidence live?" — the gate #1103 saw as a typing exercise.

    THE OWNER'S DECISION IS WHERE THE EVIDENCE LIVES, and identifying which
    files carry it is harvest's job rather than this gate's precondition. The
    served allocation has a home for each granularity — repositories are
    harvest SCOPE, and file scope is proposed at the HARVEST gate under
    proposal-plus-free-form — and the observed gate asked for file scope at a
    third location licensed for neither.

    CANDIDATES INFORM THE DEFAULT AND ARE NEVER THE ANSWER FORMAT. A
    terrain-originated run arrives holding what no cold run has, and that
    evidence state is preserved in full: it is what makes the default
    non-arbitrary. What it may not do is come back as a list of paths for the
    owner to retype — that reads the 2026-07-31 licence to "name candidate
    sources" as a licence to demand them.

    WHOSE DECLARATION (#1141). "all declared sources" is unanswerable without
    knowing which repository declared them: the owner read it as "all of it"
    and could not tell what it referred to. The scope is a property of ONE
    host repo's `writing-sources.yaml`, so the gate names that repo and the
    declaring file rather than presuming the owner holds the declared-boundary
    concept and its host binding — designer-level knowledge at an owner gate.
    Multi-repo is not the current case; the label shape is written so it does
    not become wrong when it is.

    `default_kind` is moved to the front by `payload`, so the recommendation
    leads and the directive reads `recommended: 0`.
    """
    if default_kind not in SCOPE_KINDS:
        raise ValueError(f"{default_kind!r} is not a scope; expected one of "
                         f"{', '.join(SCOPE_KINDS)}")
    # The repo is named by its DIRECTORY NAME, never by its absolute path:
    # #1117 ruled that an owner-facing path renders whole on its own line and
    # never inline in a sentence, so putting the root into a label would fix
    # one owner-surface defect by committing another. The full path reaches the
    # owner through `owner_surface.artifact_block`, on the surface that owns it.
    repo_name = os.path.basename(str(repo_root).rstrip("/")) if repo_root else None
    whose = f" of {repo_name}" if repo_name else ""
    labels = {
        "all": f"all declared sources{whose}",
        "subtree": (f"just {default_detail}" if default_detail
                    else "a directory subtree"),
        "commit-range": (f"the commit range {default_detail}"
                         if default_detail else "a commit range"),
    }
    effects = {
        "all": f"harvests the whole set {declaring_file} declares "
               f"({declared_count} file(s)) — the widest scope that "
               f"boundary allows",
        "subtree": "narrows the declared set to one subtree; files outside it "
                   "are counted as unexamined, never read",
        "commit-range": "narrows the declared set to what that range touched; "
                        "the rest is counted as unexamined",
    }
    choices = [{"label": labels[k], "effect": effects[k]} for k in SCOPE_KINDS]
    why = reason or ("Scope decides where harvest looks. Which files carry the "
                     "evidence is harvest's own step, not an answer owed here.")
    if candidates:
        # The candidates are EVIDENCE FOR THE DEFAULT, carried in the prose the
        # owner reads — never promoted into the choice set, which is the whole
        # correction.
        shown = ", ".join(list(candidates)[:3])
        why = f"{why} Seen so far: {shown}."
    where_repo = repo_name or "this repo"
    return payload(
        where=f"Stage 0: the article type is chosen and harvest needs its "
              f"scope; {declared_count} file(s) are declared for "
              f"{where_repo} in {declaring_file}.",
        why=why,
        choices=choices,
        gate="sources", ws=ws,
        recommended=SCOPE_KINDS.index(default_kind),
    )
