#!/usr/bin/env python3
"""mandated_audience — the audience declaration's mandated-tier ask (Story
20.172, #1283).

**The defect this closes.** The stage 3→4 quality gate hard-fails when the
draft's frontmatter `audience` or `audience_id` is missing or still carries its
placeholder (`draft_variants.py:219-237`), with the variant stage as backstop
(`:579-598`) — but the interview item that produced the answer (`q5`) was
deleted with the framework generator's question bank (Story 20.131, #1147).
What was left were the backlog item's declared audience, a draft-start
declaration, or **the agent composing the field at the fill** — the last
observed in run 20260802T185710-622820, and exactly the untraceable path the
provenance design refuses everywhere else. A hard gate on a field with no live
producer is the defect, so the resolution is to give the field a producer
rather than to soften the gate.

**The shape, which is the depth offer's and not a new one.** The declaration is
the third member of the host's `MANDATED_RATIONALES`: not a NEEDS-OWNER
candidate, so it never competes for the ≤5 cap or the #302 reserved policy-seed
slot; partitioned out before the cap and the reservation run; and GENERATED
from run state inside `cmd_interview` rather than left to prompt instruction,
so no invocation path — fresh, resumed, re-opened, scope-narrowed — can
silently omit it. It is an obligation and not a blocking gate (nothing between
the interview and the fill consumes it), so it stays OUT of `BLOCKING_MANDATED`
and TRAILS the capped set: leading with a non-blocking obligation would push
the claim/angle question out of presentation slot 1, the slot CAP-4 pins and
the editorial anchor reads.

**One ask, two fields, and the selection half is load-bearing.** The free-form
half names the ONE NAMED READER (`audience`); the selection half fixes
`audience_id` from the installed platform profiles' `audience` vocabulary.
Machine-proposed selectable options plus a free-form field is the human-gate
presentation contract (the #554 clause in CAP-9) — a raw text prompt would not
satisfy it. Story 13.71 is what makes it ONE ask: the compatibility identifier
is declared WITH the audience answer and never re-inferred downstream.

**Extracted rather than inlined** because `draft-pipeline.py` sits at its size
ratchet: this is helper code with no CLI surface of its own, the shape
`strand_cover.py` already has, not a command-family split.

Stdlib-only. Imported directly (no host binding): nothing here borrows a host
helper.


THE TIER'S HISTORY, CARRIED HERE FROM `draft-pipeline.py` (Story 20.172): the
CAP-7 config<->policy reconciliation gate is a blocking gate ("surfaced and
answered -> gate cleared"); the CAP-8 depth offer is an "offer it once"
obligation. Conflating them with owner-knowledge candidates produced both #545
(a reconciliation item consumed the #302 RESERVED policy-seed slot, starving a
valid tension item) and #542 (a mandated depth offer silently absent). They are
partitioned out of the candidate pool BEFORE the cap and the reservation run,
and presented as their own guaranteed tier ahead of the capped set — so the cap
and the #302 reserved slot govern only NEEDS-OWNER candidates and policy-seeds,
exactly as SPEC-article-draft-pipeline (2026-07-22, #542/#545) states.

The tier is bounded by construction — reconciliation + depth offer + the
audience declaration. THE GROWTH IS REAL AND IS THE PRICE OF THAT DECISION:
every fresh run pays one more owner-paced question, and a FOURTH member needs
the <=10-minute owner-attention budget RE-DERIVED, never asserted.
"""

import importlib.util
import os

RATIONALE = "audience-declaration"
ITEM_ID = "audience"
TOPIC = "audience"

TEXT = ("Who is this draft for? Name the ONE reader in your own words, and pick "
        "the audience id that matches from your installed platform profiles.")

# DEGRADATION, DECIDED EXPLICITLY RATHER THAN ABSORBED. With no resolvable
# profile there is no vocabulary to select over, so the ask DEGRADES TO FREE
# TEXT for both halves rather than refusing. Refusing would halt every run in a
# repo that has not installed a profile, while the field the gate demands is
# still perfectly declarable by hand — and a degraded ask still produces a
# traceable owner answer, which is the whole point of the item.
TEXT_NO_PROFILES = (
    "Who is this draft for? Name the ONE reader in your own words, and give the "
    "audience compatibility id in the same answer — no platform profile is "
    "installed, so there is no audience vocabulary to pick from.")


def state_audience(state):
    """The run's already-resolved audience declaration, or None. Mirrors the
    host's `_state_depth`: accepts a top-level `audience` (stage-0 run state)
    and a nested `run_state.audience` (a consume/interview state that folded the
    run state in), so the ask is never re-presented merely because the
    declaration travelled under a different key.

    NAMED SO ITS ABSENCE IS NOT READ AS AN OVERSIGHT: no shipped path writes
    either key today, and there is no `--audience` counterpart to `--depth`.
    Reading the state actually held at the call site is what keeps a future
    writer from double-asking. Where a DECLARED audience default should live —
    and whether it pre-fills the ask (visible and overridable in the plan, per
    CAP-3) or skips it (per `_state_depth`) — is the open question the
    2026-08-02 amendment deliberately left open: the declared-default resolver
    (Story 20.62, #945) is shipped, but no configuration key declares an
    audience default and nothing wires that resolver into `cmd_interview` — its
    only consumer is plan validation. Until the question is answered the ask is
    presented on every run, and NO declaration site is invented here."""
    if not isinstance(state, dict):
        return None
    declared = state.get("audience")
    if declared:
        return declared
    run_state = state.get("run_state")
    if isinstance(run_state, dict) and run_state.get("audience"):
        return run_state["audience"]
    return None


def vocabulary(root=None, profiles_dir_override=None):
    """The installed platform profiles' `audience` values, de-duplicated and
    ordered by platform id — the closed vocabulary `audience_id` is selected
    from. Every valid profile declares one (`resolve-platform-profiles.py`
    REQUIRED_KEYS) and an invalid profile is not a usable declaration, so it
    contributes nothing. Returns [] when nothing resolves (see TEXT_NO_PROFILES
    above); resolution failure is never fatal to the interview."""
    try:
        here = os.path.dirname(os.path.realpath(__file__))
        spec = importlib.util.spec_from_file_location(
            "resolve_platform_profiles",
            os.path.join(here, "resolve-platform-profiles.py"))
        pp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pp)
        pdir = (os.path.realpath(profiles_dir_override) if profiles_dir_override
                else pp.profiles_dir(pp.host_root(root), None))
        profiles, _ = pp.load_profiles(pdir)
    except (Exception, SystemExit):
        # SystemExit is caught deliberately: `host_root` EXITS when it cannot
        # resolve a git toplevel, and an interview run outside a repo must
        # still ask — degrading to the free-text half, never refusing.
        return []
    out = []
    for platform in sorted(profiles):
        audience = (profiles.get(platform) or {}).get("audience")
        if isinstance(audience, str) and audience.strip() and audience not in out:
            out.append(audience)
    return out


def attach(state, root, profiles_dir_override, mandated, survivors):
    """Add the audience declaration to the interview's mandated tier, in place.

    Called from `cmd_interview` after the tier is partitioned out of the
    candidate pool and before the ≤5 cap runs, so the ask can neither consume a
    capped slot nor the #302 reserved policy-seed slot, and nothing can displace
    it. `mandated` is appended to (never inserted at the front — the item is an
    obligation, not a blocking gate, so it trails the capped set); `survivors`
    is edited IN PLACE to remove the questions absorbed into the ask.

    Returns `(declaration, vocabulary)` for the caller's accounting: a run
    either already carried a declaration or was asked, and there is no third
    state in which the agent composed the field at the fill."""
    declaration = state_audience(state)
    vocab = vocabulary(root, profiles_dir_override)
    if not declaration and not any(r.get("rationale") == RATIONALE for r in mandated):
        absorbed = [r for r in survivors if r.get("topic") == TOPIC]
        survivors[:] = [r for r in survivors if r.get("topic") != TOPIC]
        mandated.append(mandated_item(vocab, absorbed))
    return declaration, vocab


def mandated_item(vocab, absorbed=()):
    """The mandated-tier interview item. `vocab` is `vocabulary()`'s result (the
    selection half's options; empty = the degraded free-text ask). `absorbed`
    is every capped-set question the caller removed on this item's behalf.

    ABSORPTION IS THE NO-DOUBLE-ASK RULE (AC-5). `audience` is also an
    editorial-judgment class eligible for a policy-seeded recommended default
    and a valid NEEDS-OWNER topic, so a run can raise it in the capped set too.
    Where it does, that question is carried HERE as this ask's recommended
    default under the propose-ratify contract rather than asked again: the
    clause is "the owner answers the audience exactly once per run", which is
    once per RUN and not once per rationale — a NEEDS-OWNER `audience` re-raise
    is just as literally a second audience ask as a policy-seeded one. Its
    seed / positions / grounding ride along so nothing auditable is dropped."""
    item = {"id": ITEM_ID, "text": TEXT if vocab else TEXT_NO_PROFILES,
            "topic": TOPIC, "outcome": "open", "rationale": RATIONALE,
            # The selection half: `audience_id` is chosen from these and only
            # from these.
            "options": list(vocab)}
    absorbed = list(absorbed)
    if absorbed:
        for key in ("seed", "positions", "grounding"):
            for record in absorbed:
                if key in record and key not in item:
                    item[key] = record[key]
        item["recommended_from"] = [r["id"] for r in absorbed]
    return item


def accounting(directive, vocab):
    """The two run-output keys, composed here so the ratcheted host keeps one line.

    Declared or asked, never a third state in which the agent composed the
    audience at the fill. The vocabulary is echoed so an off-vocabulary
    `audience_id` is attributable, and so the degraded free-text ask (an empty
    list) is visible rather than indistinguishable from an unasked run.
    """
    return {"audience_declaration": "directive-present" if directive else "presented",
            "audience_vocabulary": vocab}


def item_extras(item):
    """The human-gate contract's SELECTION half plus the asks absorbed into it.

    Today only the audience declaration carries either, so they are optional on
    the emitted question dict rather than always-present nulls.
    """
    out = {}
    for key in ("options", "recommended_from"):
        if key in item:
            out[key] = item[key]
    return out
