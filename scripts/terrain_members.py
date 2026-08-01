#!/usr/bin/env python3
"""terrain_members.py — the terrain member surface and the grouping substrates
it closes over (Story 20.65, #974; SPEC-writing-assistant, the 2026-07-30
re-triage amendment).

Extracted from `topic-map-directions.py` when that file returned to its family
line ceiling for the third time in a week. The cut is the screen-2 MEMBER
SURFACE — the boundary the two-screen product actually has — taken after the
watch trigger #942 recorded fired on its own terms.

THE MOVING SET IS A REFERENCE CLOSURE, NOT A SEMANTIC BOUNDARY
---------------------------------------------------------------
`topic-map-directions.py` is HYPHENATED, so no module can import from it —
`from topic-map-directions import load_map` is a SyntaxError. Only the
CHILD -> PARENT direction is blocked; parent -> child is ordinary. So what
moves here is the member surface CLOSED UNDER ITS OWN REFERENCES: nothing in
this file reaches back into `topic-map-directions.py`, by construction, and
the parent imports back the names it still uses.

That is why this module also holds the grouping substrates
(`_substrate_co_tags`, `_substrate_journey_similarity`,
`apply_journey_grouping`) and the axis helper, which are not "member surface"
in any product sense: the closure drags them in, and a closure-shaped cut is
named for what it CONTAINS rather than for the boundary that motivated it.
The alternative — inverting the hyphenated file into a thin CLI shim over
importable modules — would dissolve the constraint instead of working around
it, and is recorded in the amendment as the answer if this file hits its
ceiling again.

This is a MOVE, not a rewrite: every definition below is the one that stood in
`topic-map-directions.py`, unchanged, and composed output is byte-identical for
the same inputs.
"""

import json
import re
import sys

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from terrain_directions import (  # noqa: E402
    candidates,
)
from terrain_text import (
    row_type_legend,  # noqa: E402
    SCREEN_BUDGET,
    VIEW_LINE_CHARS,
    _clip_line,
    _journey_coverage_line,
    _journey_disclosure_line,
    _owner_surface,
    _pin_display,
    _short_path,
    _substituted_paths,
    _substitution_disclosure_line,
)

REFUSED = 1


def _err(msg):
    sys.stderr.write(f"error: {msg}\n")
    return REFUSED


def load_map(path):
    try:
        data = json.load(open(path, encoding="utf-8")) if path != "-" \
            else json.load(sys.stdin)
    except (OSError, ValueError) as exc:
        raise SystemExit(_err(f"unreadable map at {path}: {exc}"))
    if data.get("kind") != "topic-map":
        raise SystemExit(_err(f"{path} is not a topic map (kind={data.get('kind')!r})"))
    return data


# Screen 1's two axes (Story 20.25, #860/#859). Each corpus is keyed by the
# ONLY classification it carries, and BOTH keys are already shard keys on the
# served side — `gloss/lessons/<tag>` and `gloss/decisions/<topic>` — so
# neither axis performs a join. The `noun` is the axis's kind label, which is
# what keeps a member unambiguous: the two vocabularies overlap by name
# (measured: 2 of the 3 served decision topics are also lessons tags), so an
# unlabelled member list would mint a rival key with no declared precedence.
AXES = ({"key": "tag", "noun": "tag"}, {"key": "topic", "noun": "topic"})

# The FIRST-CLASS OWNER-FACING VOCABULARY of this surface (Story 20.26, #861):
# terms the product genuinely asks the owner to think in, each of which must be
# DEFINED WHERE THE OWNER READS IT — `specs/spec-writing-assistant/SPEC.md`,
# owner-surface register, property (d).
#
# This is an ADMISSION list, not a denial list, and the difference is the whole
# point: a denial list's non-member fallback is *admit*, which is why extending
# one is prohibited as the response to a register leak. This list's non-member
# fallback is "not first-class vocabulary", and its members carry a POSITIVE
# obligation — a definition the owner can reach. The failure it catches is an
# ABSENT DEFINITION, which no denial list can express.
#
# Its limit, stated rather than papered over: it binds terms that are DECLARED.
# Detecting an *undeclared* new coinage is the same enumeration problem, and it
# is the typed composition seam's job — deliberately still an open question in
# the spec, with its own reopen trigger.
OWNER_TERMS = ("brief", "Strand", "group claim")

# Where the codebook lives, relative to the repository root. The surface points
# at it rather than restating it: one definition, reachable, never N drifting
# paraphrases.
OWNER_TERMS_DOC = "docs/owner-terms.md"

# The kinds the topic axis is keyed over. The topic axis runs over the DECISION
# corpus only: lesson elements also carry a `topic` field, but their axis is the
# tag — putting them on both would double-count the denominator and silently
# revive the Lesson→Topic join OQ8 declined.
#
# `reversal` is NOT here (#893): it is not a served element kind — the served
# vocabulary is decision/journey/lesson — so enumerating it named something the
# recall surface does not carry. Re-adding reversals is a hub-side manifest
# extension, never a consumer-side inference from rendering prose.
DECISION_KINDS = ("decision",)


def axis_members(map_data):
    """Screen 1's TWO axes (Story 20.25, #860/#859; SPEC-terrain CAP-2 as
    amended 2026-07-28) — the served tag vocabulary over Lessons and Journeys,
    and the served decision topic over decisions.

    Deterministic by construction — no model decides what appears: every tag on
    any Strand is a member of the tag axis, every topic carrying a decision or
    reversal is a member of the topic axis, members sort alphabetically within
    their axis, and the counts are plain arithmetic. A count is a screen
    affordance for choosing where to look (legitimate presentation under the
    no-selection-authority wording), never a gate: every member is offered
    whatever its size, and a large member is served WHOLE downstream.

    NEITHER AXIS JOINS ANYTHING. A decision line's topic IS its shard key, so
    the topic axis reads a classification the corpus already carries — which is
    why this is not the Lesson→Topic join OQ8 declined (that one had to
    manufacture a membership Lessons do not have).

    The denominator is PER AXIS and never pooled (CAP-4 as amended
    2026-07-28): a single count across both would be a completeness claim over
    neither corpus. `unreachable_strands` is the separate, global disclosure —
    Strands outside EVERY axis, which reach no member at all and are named on
    the screen as a line, never hidden, with free-form still reaching them.

    Before this story the decision corpus had no axis and its Strands fell into
    that disclosure wholesale (the shard join, Story 20.22, attaches renderings
    but the served entries carry no per-entry tags — `terrain_map.py`
    `decision_shard_entries`). They are reachable now, so the count they
    inflated is a real residue again rather than a standing 54% of the corpus.
    """
    tag_members, topic_members, unreachable = {}, {}, 0
    for el in map_data.get("elements", []) or []:
        tags = [str(t).strip() for t in (el.get("tags") or []) if str(t).strip()]
        topic = str(el.get("topic") or "").strip()
        reached = False
        for t in tags:
            tag_members[t] = tag_members.get(t, 0) + 1
            reached = True
        if el.get("kind") in DECISION_KINDS and topic:
            topic_members[topic] = topic_members.get(topic, 0) + 1
            reached = True
        if not reached:
            unreachable += 1

    def listing(counts):
        return [{"member": name, "strands": n}
                for name, n in sorted(counts.items())]

    return {
        "axes": [dict(AXES[0], members=listing(tag_members)),
                 dict(AXES[1], members=listing(topic_members))],
        "unreachable_strands": unreachable,
    }


def _axis_strands(map_data, member, axis):
    """The Strands under one member of one axis (Story 20.25, #860).

    Each axis reads the classification its corpus actually carries: the tag
    axis matches a Strand's served tags, the topic axis matches a decision or
    reversal's own topic. Nothing is joined and nothing is derived — this is a
    filter over what the map already holds.
    """
    elements = map_data.get("elements") or []
    if axis == "topic":
        return [el for el in elements
                if el.get("kind") in DECISION_KINDS
                and str(el.get("topic") or "").strip() == member]
    return [el for el in elements
            if member in [str(t).strip() for t in (el.get("tags") or [])]]


# --- grouping substrates (Story 20.36, #890) ---------------------------------
# A substrate is a NAMED function from a member's Strands to named sections.
# Each returns `(sections, placements)`: `{title: [strand, ...]}` and the total
# number of placements, which is the counting unit for the cap — computing it
# against distinct Strands silently under-reports on any multi-valued
# substrate. Adding a substrate here is the whole extension point; nothing
# else in this module knows how many there are.
NO_RELATION_TITLE = "no shared co-tag"


def _substrate_co_tags(strands, tag, axis):
    """Co-tags — the served `tags` field, 100% covered, and MULTI-VALUED: a
    Strand appears under every co-tag it carries, not just its first.

    The single-valued predecessor keyed each Strand on its alphabetically-first
    co-tag, which hid every other relationship it had. A Strand with no co-tag
    lands in an explicitly NAMED section rather than being dropped or folded
    into the member's own name, so "shares nothing here" is legible as itself.
    """
    if axis == "topic":
        # The topic axis's Strands carry no co-tags, so the substrate degrades
        # to the one classification they do carry. Single-valued, so the
        # stronger exactly-once form holds for it.
        sections = {}
        for el in strands:
            sections.setdefault("decisions", []).append(el)
        return sections, sum(len(v) for v in sections.values())
    sections, placements = {}, 0
    for el in strands:
        others = sorted({str(t).strip() for t in (el.get("tags") or [])
                         if str(t).strip() and str(t).strip() != tag})
        if not others:
            sections.setdefault(NO_RELATION_TITLE, []).append(el)
            placements += 1
            continue
        for other in others:
            sections.setdefault(f"also {other}", []).append(el)
            placements += 1
    return sections, placements


# --- journey similarity (Story 20.37, #891; OFFERED, Story 20.82, #1031) -----
# MODEL-JUDGED, so the script owns the inputs and the enforcement and never the
# judgment. It was BUILT AND NOT OFFERED behind SPEC-terrain CAP-2's offering
# gate (#889): a deterministic substrate is inspectable by reading the key it
# grouped on; this one is not, because whether its groups read as one shared
# background is the very thing under test.
#
# THE GATE RAN AND PASSED, 2026-07-31 (#889, offered by #1031). One measurement
# over the `agents` member — 51 Strands, 10 machine-composed shared-path groups,
# 48 of 51 placed and the remaining 3 accounted for in the two named residues,
# permutation checked mechanically (count-in 51 = count-out 51, no drops, no
# duplicates, no invented ids) — and the owner verdicted PASS. The spec clause
# already stated the consequence — *"Pass → it joins the offered set"* — so
# this is the conditional discharging, not a new decision.
#
# What the pass does NOT change: the enforcement below is unchanged (the
# composer still cannot rank, hide or omit), co-tags remains the default
# (offering an axis does not promote it), and both residues stay DISTINCT —
# a Strand with no served arc was never eligible for judgment, one judged into
# nothing was, and merging them would erase which happened.
JOURNEY_SUBSTRATE = "journey-similarity"
NO_ARC_TITLE = "no served journey arc"
NO_SHARED_PATH_TITLE = "no shared path"


def apply_journey_grouping(strands, grouping):
    """Assemble sections from a model-proposed grouping, enforcing the boundary.

    The composer MAY place Strands and name what they share. It may not rank,
    score, order by strength, surface only the strongest, hide a weak group, or
    omit a Strand — so this function ignores any ordering the proposal carries
    and re-derives it from a declared key, and it re-attaches every Strand the
    proposal left out rather than accepting the shortfall.

    Returns `(sections, placements)` like any substrate. Enforcement happens
    HERE, after composition, because a composer that cannot omit in principle
    can still omit in fact.
    """
    by_slug = {str(el.get("slug")): el for el in strands}
    sections, placed = {}, set()
    for group in grouping or []:
        title = str((group or {}).get("in_common") or "").strip()
        members = [str(x) for x in ((group or {}).get("members") or [])]
        keep = [by_slug[m] for m in members if m in by_slug]
        if not title or not keep:
            continue
        sections.setdefault(title, []).extend(keep)
        placed.update(m for m in members if m in by_slug)
    # Whatever the composer did not place is re-attached, never dropped: an
    # arc-less Strand to its own named section, an arc-bearing one to the
    # explicit "no shared path" residue.
    for slug, el in by_slug.items():
        if slug in placed:
            continue
        arc = el.get("journey")
        key = (NO_SHARED_PATH_TITLE
               if isinstance(arc, str) and arc.strip() else NO_ARC_TITLE)
        sections.setdefault(key, []).append(el)
    placements = sum(len(v) for v in sections.values())
    return sections, placements


def _substrate_journey_similarity(strands, tag, axis, grouping=None):
    """The substrate wrapper. With no proposed grouping every Strand lands in
    the residue — the honest empty state, never an invented grouping."""
    return apply_journey_grouping(strands, grouping)


# OFFERED substrates — what the owner may choose today. Journey similarity
# joined on the 2026-07-31 verdict (Story 20.82, #1031); see the gate note
# above for what was measured.
SUBSTRATES = {"co-tags": _substrate_co_tags,
              JOURNEY_SUBSTRATE: _substrate_journey_similarity}
# BUILT BUT NOT OFFERED — the holding pen for a substrate still behind the
# offering gate. EMPTY today, and kept rather than deleted because the gate is
# a standing rule for model-judged substrates, not a one-off for this one: the
# next judged substrate lands here until its own measurement run passes.
SUBSTRATES_UNOFFERED = {}
# UNCHANGED by the offering (AC6). Offering an axis makes it choosable; it does
# not make it the answer for a run that named no substrate.
SUBSTRATE_DEFAULT = "co-tags"


def _substrate_fn(name):
    """Resolve a substrate by name across both sets. Membership of the OFFERED
    set is what the chooser reads; this resolver also reaches anything still
    behind the offering gate, for its measurement run."""
    if name in SUBSTRATES:
        return SUBSTRATES[name]
    if name in SUBSTRATES_UNOFFERED:
        return SUBSTRATES_UNOFFERED[name]
    raise KeyError(name)


def member_sections(map_data, tag, axis="tag", substrate=SUBSTRATE_DEFAULT,
                    grouping=None):
    """Screen 2's sections for one axis member (Story 20.9, #811; a member of
    either axis since Story 20.25, #860 — Screen 2 itself is unchanged, and no
    third screen exists).

    GROUPING RUNS ON A NAMED SUBSTRATE, and completeness is a COVER counted
    in PLACEMENTS (Story 20.36, #890; SPEC-terrain CAP-2 as amended
    2026-07-29). A substrate is a named function from the member's Strands to
    named sections. Every Strand appears in AT LEAST ONE section — the
    exactly-once wording it replaces was written for a single-valued key and
    is false for a multi-valued one: a Strand carrying four tags belongs in
    four co-tag sections, and forcing it into one needs a tie-break, which is
    a machine deciding which relationship the owner may see. Where a substrate
    IS single-valued, exactly-once still holds and is the stronger check.

    Sections carry NO SELECTION AUTHORITY (the invariant as re-worded upstream
    2026-07-27): a title and a count are presentation; nothing here gates,
    filters, or ranks what is selectable. Section ORDER is a declared
    deterministic key — never a quality judgment — because ranking sections is
    the far side of the second-proposer boundary.
    """
    tag = str(tag).strip()
    strands = _axis_strands(map_data, tag, axis)
    fn = _substrate_fn(substrate)
    sections, placements = (fn(strands, tag, axis, grouping)
                            if substrate == JOURNEY_SUBSTRATE
                            else fn(strands, tag, axis))
    # THE SECTIONING CONTRACT (owner ruling, #850 D4; Story 20.23, #852): no
    # direct parent section holds more than 20% of the member's Strands —
    # subdivide, deterministically, until every one is under the bound. The
    # small-member floor keeps the rule from degenerating into one-Strand
    # sections: a section is never required below SECTION_FLOOR Strands. A
    # section that cannot subdivide further (no additional shared label
    # distinguishes its Strands) keeps its size and DISCLOSES the bound on
    # its title line — the contract is violated visibly, never silently.
    #
    # THE CAP IS COMPUTED AGAINST PLACEMENTS (Story 20.36, #890), not against
    # distinct Strands: under a multi-valued substrate the placement total
    # exceeds the member count, and capping on the smaller number would demand
    # subdivisions the material cannot support — silently under-reporting the
    # bound it claims to enforce.
    total = len(strands)
    cap = max(SECTION_FLOOR, int(placements * SECTION_SHARE_CAP))
    ordered = []
    # Sorted by title — a DECLARED deterministic key. The no-relation section
    # sorts last by construction so the screen ends with what shares nothing,
    # rather than opening on it; that is ordering, never ranking.
    residue = {NO_RELATION_TITLE, NO_ARC_TITLE, NO_SHARED_PATH_TITLE}
    for key in sorted(sections, key=lambda k: (k in residue, k)):
        # SUBDIVISION IS THE CO-TAG SUBSTRATE'S OWN MOVE and does not travel
        # (Story 20.37, #891). Subdividing a judged substrate's sections on
        # co-tags would silently mix two substrates in one screen: the section
        # would carry a title from one and a boundary from another, and the
        # owner could not tell which produced the grouping they are reading.
        # An over-cap section under a judged substrate DISCLOSES instead.
        if substrate != SUBSTRATE_DEFAULT:
            note = (f"over the one-fifth bound ({len(sections[key])} of "
                    f"{placements} placements) — a judged substrate is not "
                    f"subdivided on another substrate's key"
                    if len(sections[key]) > cap else None)
            ordered.append({"title": key, "strands": sections[key],
                            "note": note})
            continue
        used = {tag} | ({key[5:]} if key.startswith("also ") else set())
        for sub_title, group, note in _subdivide_section(
                key, sections[key], used, cap):
            ordered.append({"title": sub_title, "strands": group,
                            "note": note})
    # GROUP IDS ARE A DISPLAY KIND (Story 20.37, #891): a group is addressable
    # so the owner can refer to one, and the surface declares the kind. `G`
    # confers NO selection authority — selection stays by element id, per the
    # presentation-only invariant. Stated because an id that looks selectable
    # and is not is exactly what retired the `J<n>` namespace.
    for n, sec in enumerate(ordered, start=1):
        sec["group_id"] = f"G{n}"
    return {"member": tag, "count": total, "axis": axis, "sections": ordered,
            # The acquisition disclosure: which substrate grouped this, how
            # many placements it made, and whether every Strand is covered.
            # `covered` is the mechanical assertion the contract names — it is
            # computed here rather than trusted, so a substrate that drops a
            # Strand is caught at the point it happens.
            "substrate": substrate,
            "placements": placements,
            "covered": len({id(e) for g in sections.values() for e in g})
                       == total}


# The sectioning contract's constants (Story 20.23, #852): the 20% bound is
# the owner's ruling verbatim; the floor is this implementation's stated
# small-member guard (20% of 5 is 1 — a rule that forces one-Strand sections
# helps nobody, so no section is required smaller than this).
SECTION_SHARE_CAP = 0.2
SECTION_FLOOR = 3


def _subdivide_section(title, group, used_tags, cap):
    """One section, subdivided until under the cap — or disclosed.

    Deterministic: subdivision keys on each Strand's alphabetically-first
    co-tag not already used by the section's ancestry (the same rule that
    named the section), recursing with compound titles. Strands with no
    further co-tag gather under the parent title. Yields
    `(title, strands, note)` triples; `note` is the visible disclosure when a
    group stays over the cap because no further shared label subdivides it.
    """
    if len(group) <= cap:
        yield title, group, None
        return
    subs = {}
    for el in group:
        others = sorted(str(t).strip() for t in (el.get("tags") or [])
                        if str(t).strip() and str(t).strip() not in used_tags)
        subs.setdefault(others[0] if others else "", []).append(el)
    if len(subs) <= 1:
        yield (title, group,
               "over the one-fifth bound — no further shared label "
               "subdivides it")
        return
    for key in sorted(subs):
        if not key:
            note = ("over the one-fifth bound — no further shared label "
                    "subdivides it") if len(subs[key]) > cap else None
            yield title, subs[key], note
            continue
        yield from _subdivide_section(f"{title} + {key}", subs[key],
                                      used_tags | {key}, cap)


# --- The SEMANTIC SUBGROUP LAYER (Story 20.86, #1041) -------------------------
#
# WHAT IT IS. A second, OPTIONAL stratum inside a parent group: the same
# Strands, allocated into sub-groups that each carry their own claim, so the
# differences inside a related set are visible instead of flattened into one
# sentence. It sits BESIDE `_subdivide_section` above and replaces nothing.
#
# WHICH RUNS WHEN (AC8, stated explicitly because two subdivision mechanisms
# now compose):
#   1. `_subdivide_section` runs INSIDE `member_sections`, deterministically,
#      on the co-tag substrate only, keyed on shared labels and bounded by the
#      20%-of-placements cap. It runs BEFORE any prose exists and it FIXES
#      parent membership. Its behaviour is unchanged by this layer.
#   2. This layer runs AFTER claims have been composed, over the sections step
#      1 already fixed. It re-partitions the Strands WITHIN one parent and
#      never across parents, so neither mechanism can override the other: one
#      decides which parent a Strand is in, the other decides nothing about
#      that at all.
#
# WHAT DECIDES A SUBDIVISION (AC2). The TIGHTNESS DIFFERENTIAL, and nothing
# else: a trial subdivision is adopted when its subgroup claims are measurably
# tighter than the parent's, and rejected — the group stays a leaf — when they
# merely restate it. That judgment is SEMANTIC, so it is the composer's, made
# against the rule the surface states (`skills/terrain/steps/screens.md`), and
# only its RESULT arrives here. NO MEMBER COUNT, NO PLACEMENT CAP AND NO
# SCROLL LENGTH PARTICIPATES (AC9): the served position forbids a count
# trigger — *not a count, not a scroll length* (*owner decision record —
# 2026-07-27 (no within-axis cap; a second navigation step)*) — and the
# `~4 members` figure in #1041 is calibration evidence, never a threshold.
# The cap-based reading fails on the reported instance anyway: at 107
# placements the cap was 21, and the two groups being reported held 15 and 13.
#
# THE RECURSIVE STOP IS #980's, UNCHANGED (AC3). A subgroup may carry its own
# `subgroups`: a claim that degenerates into an enumeration splits further, one
# that composes honestly is a leaf. The stop is semantic at every level and no
# depth limit or member-count constant is introduced for it.
#
# COST, MEASURED BEFORE THIS WAS BUILT (AC1 — the criterion that could have
# stopped the story). Speculative subdivision-and-claim composition was run
# across the candidate groups of a recorded real run (51 Strands, 107
# placements, 20 groups, co-tag substrate — the very run #1041 reports, whose
# G10=15 and G12=13 both sat UNDER the 21-placement cap).
#   * Candidate groups (a subdivision is structurally possible at all): 11 of
#     20, carrying 89 of the 107 placements.
#   * TRIAL COMPOSITIONS: 12 trial partitions and 28 trial subgroup claims,
#     against a baseline pass of 20 parent claims — i.e. ~2.4x the claim
#     composition work, in the SAME turn.
#   * ADOPTION RATE: 4 of 11 adopted (including the reported G10), 7 rejected
#     as restatements — so the differential does discriminate rather than
#     always firing.
#   * LATENCY: the script side is unchanged and negligible — `member` over
#     this corpus runs in 0.12s, and the layer adds ZERO extra script round
#     trips because the trials are composed inside the existing two-call flow.
#     The measured end-to-end trial pass was ~87s of composition wall clock.
#   * TOKENS: inputs are already in context from the baseline pass (the 11
#     candidates' claim inputs are 17,857 B of the 22,304 B payload); the
#     marginal cost is OUTPUT — 28 claims at ~200 B, ~5.6 KB, against the
#     baseline's 4,229 B.
# VERDICT: not prohibitive. A ~2.4x output multiplier inside one existing turn,
# with no new round trips and no new corpus reads, is not the cost the triage
# gate reserved the halt for. The recorded fallback (drop to the
# degenerate-claim self-report at `:634-650`) is therefore NOT taken.

SUBGROUP_ID_SEP = "-"


def _subgroup_strands(parent_strands, slugs, where):
    """Resolve a trial subgroup's slugs against its parent's Strands.

    Returns the parent's own element dicts — never a re-derived Strand — so a
    subgroup is literally a view of the parent's membership.
    """
    by_slug = {}
    for el in parent_strands:
        by_slug.setdefault(el.get("slug"), el)
    out = []
    for slug in slugs:
        if slug not in by_slug:
            raise ValueError(
                f"{where}: {slug!r} is not a Strand of this group. A "
                "subdivision allocates the parent's OWN members; it never "
                "moves a Strand between parent groups (Story 20.86 AC7)")
        out.append(by_slug[slug])
    return out


def _validate_subgroups(parent_id, parent_strands, proposed, depth=1):
    """One parent's adopted subdivision, validated and given its ids.

    PRESENTATION-ONLY (AC7). The only thing checked here is that the proposal
    is an EXACT PARTITION of the parent's Strands: nothing added, nothing
    dropped, nothing moved between parents, and no Strand in two subgroups of
    one parent. A machine judgment about prose quality must never move a
    Strand — Story 20.67 AC3's rule, inherited — so a proposal that would is
    refused rather than silently repaired.

    IDS FOLLOW THE DISPLAY-ID DISCIPLINE (AC4): `G<n>-<m>`, and `G<n>-<m>-<k>`
    where a subgroup subdivides again. Per-screen and per-pin, usable to ask
    for a full report, and conferring NO SELECTION AUTHORITY — selection stays
    by Strand index, exactly as `G<n>` itself does at `:395-402`.

    The `len(...) < 2` guard below is a check on the SHAPE OF A PROPOSAL — a
    one-part "partition" is not a subdivision — and is not a member-count
    trigger: it never looks at how many Strands a group holds, only at how many
    parts the composer returned.
    """
    if not isinstance(proposed, list):
        raise ValueError(f"{parent_id}: a subdivision is a list of subgroups")
    if len(proposed) < 2:
        raise ValueError(
            f"{parent_id}: a subdivision has at least two parts — one part is "
            "the group itself, which is the leaf case and is expressed by "
            "sending no subdivision for this group at all")
    seen = {}
    out = []
    for i, sub in enumerate(proposed, start=1):
        if not isinstance(sub, dict):
            raise ValueError(f"{parent_id}: each subgroup is an object with "
                             '"strands" and "claim"')
        sub_id = f"{parent_id}{SUBGROUP_ID_SEP}{i}"
        slugs = sub.get("strands") or []
        if not isinstance(slugs, list) or not slugs:
            raise ValueError(f"{sub_id}: names no Strand")
        for slug in slugs:
            if slug in seen:
                raise ValueError(
                    f"{sub_id}: {slug!r} is already in {seen[slug]} — a "
                    "subdivision partitions the parent, so a Strand sits in "
                    "exactly one part of it")
            seen[slug] = sub_id
        strands = _subgroup_strands(parent_strands, slugs, sub_id)
        # THE THREE CLAIM STATES, carried at every level (they are asserted on
        # the surface by Story 20.87, and preserved as DATA here): a composed
        # claim travels verbatim; a composer that tried and found no
        # commonality self-reports; a claim never asked for is absent, never
        # invented.
        claim = sub.get("claim")
        record = {"subgroup_id": sub_id,
                  "claim": claim if isinstance(claim, str) and claim.strip()
                           else None,
                  # WHICH OF THE THREE STATES this is, kept as data rather than
                  # inferred from a falsy claim: `"claim": null` is a composer
                  # that TRIED and found no commonality; no `claim` key at all
                  # is one that was never asked. Collapsing them hides the
                  # signal #980 was decided on (Story 20.87 AC4).
                  "claim_declared": "claim" in sub,
                  "claim_absent_reason": sub.get("claim_absent_reason"),
                  "strands": strands}
        nested = sub.get("subgroups")
        if nested:
            record["subgroups"] = _validate_subgroups(sub_id, strands, nested,
                                                      depth + 1)
        out.append(record)
    missing = [el.get("slug") for el in parent_strands
               if el.get("slug") not in seen]
    if missing:
        raise ValueError(
            f"{parent_id}: the subdivision drops {', '.join(map(str, missing))}"
            " — every Strand of the parent appears in exactly one part. "
            "Completeness is never a composer's choice (Story 20.86 AC5)")
    return out


def _leaf_sections(ms):
    """Every LEAF of the composed hierarchy, as `(id, strands)` pairs.

    A section with no adopted subdivision is its own leaf; a subdivided one
    contributes its deepest parts and never itself. This is what the cover is
    counted over (AC5).
    """
    def walk(node_id, node):
        subs = node.get("subgroups")
        if not subs:
            yield node_id, node["strands"]
            return
        for sub in subs:
            yield from walk(sub["subgroup_id"], sub)
    for sec in ms["sections"]:
        yield from walk(sec.get("group_id"), sec)


def apply_subgroups(ms, subgroups):
    """Attach an adopted semantic subdivision to the sections, and re-assert
    the cover AT THE LEAVES.

    `subgroups` is the composer's ADOPTED result only, keyed by group id:
    `{"G10": [{"claim": str, "strands": [slug, ...], "subgroups": [...]}, ...]}`.
    A group the tightness differential left as a leaf simply does not appear —
    there is no "rejected" record to carry, and a group's absence is its leaf
    state.

    THE COUNT CHECK RUNS AFTER COMPOSITION (AC6), which is the only ordering
    that catches the failure: a composer that cannot omit *in principle* can
    still omit *in fact*, and a cover asserted before the prose exists asserts
    it about a structure the prose has not touched yet. So the cover is
    recomputed here, over the leaves, in PLACEMENTS
    (`specs/spec-terrain/SPEC.md:277-289`) — the same unit the parent cover
    uses, because a subdivided multi-valued substrate still places one Strand
    in several parents.

    Returns `ms`, mutated in place, with `subdivided` and `leaf_covered`
    disclosures beside the existing `covered`.
    """
    ms["subdivided"] = []
    if subgroups:
        if not isinstance(subgroups, dict):
            raise ValueError('--subgroups is an object keyed by group id, for '
                             'example {"G10": [{"claim": "...", "strands": '
                             '["slug"]}]}')
        by_id = {s.get("group_id"): s for s in ms["sections"]}
        for gid in sorted(subgroups):
            if gid not in by_id:
                raise ValueError(
                    f"{gid} is not a group on this screen. Group ids are "
                    "PER-SCREEN and PER-PIN; re-read them from the listing "
                    "you are composing against")
            sec = by_id[gid]
            sec["subgroups"] = _validate_subgroups(gid, sec["strands"],
                                                   subgroups[gid])
            ms["subdivided"].append(gid)
    # The cover, recomputed over the leaves AFTER composition (AC5/AC6). A
    # Strand with no relation under the active substrate still sits in its own
    # explicit named section, so it is counted here like any other — the
    # no-relation section is a leaf, never a silent drop.
    leaves = list(_leaf_sections(ms))
    ms["leaf_placements"] = sum(len(s) for _, s in leaves)
    ms["leaf_covered"] = (
        len({id(e) for _, s in leaves for e in s}) == ms["count"])
    return ms


# --- RENDERING THE SUBGROUP HIERARCHY (Story 20.87, #1041) --------------------
#
# THE PARENT CLAIM STAYS, ABOVE ITS SUBGROUPS (AC1), per the owner's 2026-07-30
# ruling: the parent claim is supporting information for why the members belong
# together at all, and *"showing only G10-X claims makes the subgroups' relation
# to one another illegible"* — while the Full Report's purpose is surveying the
# material as a whole. So the hierarchy is VISIBLE: parent header, parent claim,
# then each subgroup with its own.
#
# THREE SURFACES, ONE WALK (AC2). `compose_member_listing` and
# `compose_member_view` are already one rendering (Story 20.83, #1039); the Full
# Report is the third and is a separate composer. Both call the SAME walk below
# and differ only in how a Strand ROW is drawn — which is a real difference
# between the surfaces (the selection screens clip, the report does not, and the
# report moves the context line to a footnote), not a second implementation of
# the hierarchy. A second walk is exactly the drift #1039 records.

# THE SELECTION CONTRACT IS STATED ONCE, HERE (Story 20.96, #1074). The screen
# used to carry only the refusing half — "conferring no selection authority" —
# while `skills/terrain/SKILL.md` and `skills/terrain/steps/screens.md` carried
# the expansion half, so Screen 2 presented an owner with instructions that
# appeared to contradict each other and no way to tell which was live. The
# contract itself was never in doubt: `SPEC-terrain` presentation.md states it,
# and `terrain_select.py:_group_expander` implements it. What was missing was
# saying the whole of it where the owner reads.
#
# The two USES are named as different acts on purpose. "Ask for a full report by
# group id" selects nothing; "type it where you would type a Strand index" is
# shorthand that expands. One id serving two acts is what the screen must
# disambiguate — collapsing them is how the contradiction read as one.
# EACH LINE STAYS INSIDE THE VIEW LINE BUDGET, so these are separate lines
# rather than one long sentence: the listing renders one list entry per line and
# every line is bounded, which `check-terrain-report-inner.sh` asserts.
GROUP_ID_KIND_LINES = (
    "`G<n>` is a DISPLAY id: per-screen, per-pin, and NEVER recorded.",
    "It has two uses, and they are different acts. ASK for a full report by "
    "group id — that is inspection and selects nothing.",
    "Or TYPE it where you would type a Strand index — there it expands to its "
    "members at this screen, and the members are what is recorded.",
    "Selection is always by Strand index.")

SUBGROUP_ID_KIND_LINES = (
    "`G<n>-<m>` is a DISPLAY id like `G<n>` and carries the same contract: "
    "per-screen, per-pin, and never recorded.",
    "It is askable for a full report and typable as shorthand that expands to "
    "its members. Selection is always by Strand index.")

# Kept as single strings for callers that render one paragraph; both are the
# same words as the line forms above, joined — never a second wording.
GROUP_ID_KIND = " ".join(GROUP_ID_KIND_LINES)
SUBGROUP_ID_KIND = " ".join(SUBGROUP_ID_KIND_LINES)


def _node_ids(strands, by_slug):
    """The display ids of a node's Strands, in placement order.

    One resolver for both levels — the group heading and the subgroup line —
    because Story 20.128 (#1139) makes them one format, and two resolvers is
    how two formats come back.
    """
    out = []
    for el in strands:
        c = by_slug.get(el.get("slug"))
        out.append(c["id"] if c else el.get("slug", "?"))
    return out


def _summary_head(head, sec, by_slug=None):
    """The summary heading — count, indexes, and any adopted subdivision.

    ONE FORMAT FOR BOTH LEVELS (Story 20.128, #1139). The indexes used to ride
    a standalone `N Strand(s): L5, L71` line beneath the heading, and the owner
    ruled that line out: *"They make the Display difficult to read. I requested
    Lesson Index visibility, but this was not a good implementation."* The
    requirement was index visibility; a second line per node was the bad
    implementation of it. So the indexes move INTO the heading's count
    parenthesis — `(3: L59, L60, L61)` — and the subgroup line takes the same
    shape, which is what makes them one format rather than two that resemble
    each other.

    A SUBDIVIDED group lists its members per subgroup, so its own parenthesis
    carries the counts alone: repeating fifteen ids in the parent and again
    across its subgroups is the density the ruling objected to.

    The subdivision count itself is unchanged and still required (Story 20.97,
    #1075): a screen that defines the `G<n>-<m>` family and exhibits no member
    of it leaves the owner facing the parent's members exactly as before
    subdivision shipped. This is a COUNT, not composer prose, so the
    screen-height argument that governed the claim never reached it.
    """
    n_strands = len(sec["strands"])
    subs = sec.get("subgroups") or []
    if subs:
        n = len(subs)
        return head.replace(f"({n_strands})",
                            f"({n_strands}, {n} subgroup"
                            f"{'' if n == 1 else 's'})", 1)
    ids = _node_ids(sec["strands"], by_slug or {})
    if not ids:
        return head
    return head.replace(f"({n_strands})", f"({n_strands}: {', '.join(ids)})", 1)


def _summary_index_lines(sec, by_slug, claims=None):
    """The group's Strand indexes on the summary — per subgroup where the group
    is subdivided (Story 20.114, #1115).

    SUBDIVISION IS SHOWN, NOT JUST COUNTED. `_summary_head` annotates a
    subdivided group with a count, which Story 20.97 (#1075) states as the
    MINIMUM — *"a screen that defines the `G<n>-<m>` id family and exhibits no
    member of it leaves the owner facing the parent's fifteen members exactly
    as before the mechanism shipped"*. That argument does not stop at a count:
    it asks for a member of the family to be exhibited. A subgroup rendered
    with its id, its claim and its indexes is that member.

    ONE FORMAT WITH THE HEADING (Story 20.128, #1139): a subgroup renders as
    `G2-1 — <claim> (3: L59, L60, L61)`, the same shape `_summary_head` gives
    a group, and the standalone `N Strand(s): …` line is retired at both
    levels. An unsubdivided group emits nothing here — its indexes are in its
    own heading.
    """
    subs = sec.get("subgroups") or []
    if not subs:
        # NOTHING (Story 20.128, #1139): an unsubdivided group's indexes are in
        # its heading's parenthesis now. This used to emit the standalone
        # `N Strand(s): …` line the owner ruled out.
        return []
    out = []
    for sub in subs:
        ids = _node_ids(sub["strands"], by_slug)
        # The subgroup's own claim, in the same three states the parent's uses:
        # declared, tried-and-found-nothing, or never asked. Read from the
        # record, never composed here.
        claim = str(sub.get("claim") or "").strip()
        if claim:
            head = f"  {sub['subgroup_id']} — {claim}"
        elif sub.get("claim_declared"):
            head = (f"  {sub['subgroup_id']} — no single commonality found; "
                    f"grouped as placed")
        else:
            head = f"  {sub['subgroup_id']}"
        if ids:
            head += f" ({len(ids)}: {', '.join(ids)})"
        out.append(_clip_line(head))
    return out


def _summary_claim_line(claims, gid):
    """One group's `in common:` claim on the SUMMARY, bounded (Story 20.97).

    The three claim states are the same three the whole listing renders — a
    composer that TRIED and found nothing is not one that was never asked — so
    this states which absence it is rather than rendering a bare heading.

    THE BOUND, because claim length has no cap and #976 forbids clipping one:
    whole where it fits a line, otherwise FIRST SENTENCE VERBATIM plus a
    pointer to the whole. That is the same sanctioned reduction the spec states
    for served renderings (#1076) — a mid-sentence ellipsis is not an available
    rendering of a claim on any surface, which is why this never calls
    `_clip_line`. Where even the first sentence is over the line, it renders
    whole: over-budget beats cut.
    """
    if gid not in claims:
        return "  in common: not composed for this group — stated as absent " \
               "rather than invented here."
    claim = str(claims.get(gid) or "").strip()
    if not claim:
        return "  in common: no single commonality found — grouped as placed, " \
               "with nothing regrouped, reordered or dropped on account of it."
    body = " ".join(claim.split())
    line = f"  in common: {body}"
    if len(line) <= VIEW_LINE_CHARS:
        return line
    first = re.split(r"(?<=[.!?])\s+", body, maxsplit=1)[0]
    return f"  in common: {first} — full claim in the View."


def _subgroup_claim_line(sub, prefix):
    """One subgroup's claim, in whichever of the THREE STATES it is (AC4).

    The states are the parent's, unchanged (`:634-650`): a composed claim
    renders VERBATIM — never re-derived, never shortened and never clipped,
    because clipping it re-creates #976 one layer up (AC3); a composer that
    tried and found no commonality SELF-REPORTS; and a claim never asked for is
    stated as absent rather than invented.
    """
    if sub.get("claim"):
        return f"{prefix}: {sub['claim']}"
    if sub.get("claim_declared"):
        reason = str(sub.get("claim_absent_reason") or "").strip()
        return (f"{prefix}: no single commonality found — the composer reports "
                "these Strands share no one denominator it could state. They "
                "are grouped as placed; nothing here has been regrouped, "
                "reordered or dropped on account of it."
                + (f" ({reason})" if reason else ""))
    return (f"{prefix}: not composed for this subgroup — stated as absent "
            "rather than invented here.")


def _render_subgroups(lines, subs, render_strands, prefix, level):
    """The hierarchy walk both surfaces share.

    `render_strands(strands)` appends a leaf's Strand rows in the calling
    surface's own row contract. Nothing here touches membership, order or
    counts (AC7): the walk reads the structure `apply_subgroups` validated and
    renders it.
    """
    head = "#" * min(level, 6)
    for sub in subs:
        lines.append(f"{head} {sub['subgroup_id']} ({len(sub['strands'])})")
        lines.append("")
        lines.append(_subgroup_claim_line(sub, prefix))
        lines.append("")
        if sub.get("subgroups"):
            _render_subgroups(lines, sub["subgroups"], render_strands,
                              prefix, level + 1)
        else:
            render_strands(sub["strands"])
            lines.append("")


def _any_subgroups(ms):
    return any(s.get("subgroups") for s in ms["sections"])


def _subgroups_payload(subs):
    """The subdivision, as data: ids, claims and slugs, recursively.

    Slugs, not element dicts — the payload names Strands the way every other
    section field does, so a consumer joins on the same key.
    """
    out = []
    for sub in subs:
        row = {"subgroup_id": sub["subgroup_id"],
               "claim": sub.get("claim"),
               "claim_declared": sub.get("claim_declared"),
               "claim_absent_reason": sub.get("claim_absent_reason"),
               "strands": [e.get("slug") for e in sub["strands"]]}
        if sub.get("subgroups"):
            row["subgroups"] = _subgroups_payload(sub["subgroups"])
        out.append(row)
    return out


def _strand_context_line(el, member_tag, substituted=()):
    """One deterministic context line per Strand (Story 20.21, #845).

    Every field is READ from the map — the Topics beyond the member's own
    tag, where the Strand originated, and whether its claim travels with its
    recorded reasoning — never composed at render time: section background
    prose is pre-ratified or absent (SPEC-terrain CAP-2, amended 2026-07-27,
    #844), so a Strand's context lives on the Strand's own line and section
    headers stay a title and a count. An absent field is stated as absent,
    never guessed and never filled in.
    """
    others = sorted({str(t).strip() for t in (el.get("tags") or [])
                     if str(t).strip() and str(t).strip() != member_tag})
    topics = ("also in: " + ", ".join(others)) if others else "in no other Topic"
    origin = el.get("situation") or el.get("surface") or ""
    where = f"from {_short_path(origin)}" if origin else "origin not recorded"
    # Presence is read, not judged: the claim is the served rendering (or the
    # title standing in for one); the reasoning counts as present only when
    # the map carries recorded backing for this Strand.
    reasoning = ("claim and reasoning both recorded"
                 if (el.get("evidence") or [])
                 else "claim only — its reasoning is not recorded here")
    # A Strand read from a SUBSTITUTED path says so on its own row: the
    # screen-level line names the substitution, and the row names which
    # material it affected (#873).
    mark = ""
    if origin and any(str(origin).startswith(p) for p in substituted):
        mark = " · SUBSTITUTED SOURCE — not the path requested"
    # ABSENCE is marked; presence is silent (SPEC-terrain CAP-2, amended
    # 2026-07-30, #933/#934). Presence-marking was designed against ~50%
    # coverage and inverts at 109/117: a marker on nearly every row carries
    # nothing per row, while the thin Strands are the actionable set. Read from
    # the paired record (`journey_recorded`), never from the arc rendering or
    # the shard pointer — those answer "was it addressable?", not "does it
    # exist?". The screen-level denominator is what keeps this readable as
    # coverage drifts; see `_journey_coverage_line`.
    if el.get("kind") == "lesson" and not el.get("journey_recorded"):
        mark += " · no-journey"
    return f"  ({topics} · {where} · {reasoning}{mark})"


def _cotags_replace_if_redundant(context_line, group_title):
    """Replace the footnote's co-tag LIST with a pointer to the group's axis
    when the two are the same set (#1129).

    THE FIELD SURVIVES; THE REPETITION DOES NOT. Dropping the list outright was
    implemented first and reverted: `check-terrain-report-inner.sh` requires
    *"every footnote entry carries a placement field, co-tagged or not"*
    unconditionally (#987), and #987 made the footnote a SELF-CONTAINED
    relocation of the row's context line — a footnote missing a field is no
    longer that. The amendment's justification (the group heading already
    carries the axis) is true of the HEADING and does not reach the footnote's
    own contract.

    So the placement field stays and stops restating what the heading says. A
    Strand whose tags reach BEYOND the group's axis keeps its list whole: that
    is information the heading does not have.

    Comparison is on the SET, never on rendered text — the heading joins with
    `+` and the footnote with `,`, so a string compare would silently keep
    everything. Anything unparseable is kept: a footnote is not worth losing to
    a title format this does not recognise.
    """
    m = re.match(r"^\(also in: (.+?) ·", context_line)
    if not m:
        return context_line
    strand_tags = {t.strip() for t in m.group(1).split(",") if t.strip()}
    axis = {t.strip() for t in re.split(r"[+,]", str(group_title).replace(
        "also ", "", 1)) if t.strip()}
    if not axis or not strand_tags <= axis:
        return context_line
    return context_line[:m.start(1)] + "(group axis)" + context_line[m.end(1):]


PIN_IN_POINTER = re.compile(r"@([0-9a-f]{7,40})\b")


def _footnotes_state_shared_pin_once(footnotes):
    """Strip the pin from footnote lines when the whole report shares ONE.

    Returns `(lines, shared_pin_or_None)`.

    THE ASSUMPTION IS ASSERTED, NEVER ASSUMED (Story 20.113, #1116). A View is
    served at one hub commit by construction today, which is exactly why the
    pin repeated 110 times on the 2026-08-01 run. But "by construction today"
    is not a licence to render one pin as though it covered every Strand: if
    the set of pins is ever larger than one, every line keeps its own and the
    header states nothing. The single-pin claim is therefore MEASURED from the
    lines themselves, per report — the cheapest possible check, and the only
    one that cannot go stale.

    A line with no pin at all (an unrecorded origin) is untouched: it makes no
    claim to strip.
    """
    pins = {m.group(1) for ln in footnotes for m in PIN_IN_POINTER.finditer(ln)}
    if len(pins) != 1:
        return footnotes, None
    shared = pins.pop()
    return [PIN_IN_POINTER.sub("", ln) for ln in footnotes], shared


def _journey_arc_line(el):
    """A Lesson's Journey arc, rendered on the Lesson's own row.

    A Journey is not a Strand of its own (CAP-2 as amended 2026-07-28, #871):
    correspondence is 1:0..1 and the hub's discovery marker is per-lesson, so
    the arc is shown WITH the rule it belongs to and the Lesson is what gets
    selected. The text is the served `journey_gloss:` rendering, quoted — a
    consumer never re-expresses it and never synthesises an arc from a
    headline. An absent arc states which of the three absences it is, rather
    than being silently omitted.
    """
    if el.get("kind") != "lesson":
        return None
    arc = el.get("journey")
    if arc:
        return f"  how it changed: {arc}"
    absent = el.get("journey_unavailable")
    return f"  how it changed: not shown — {absent}" if absent else None


def member_is_large(ms):
    """Is THIS MEMBER over the screen budget? (Story 20.84, #1038.)

    The predicate the size switch turns on for Screen 2. The budget was re-based
    per axis member on 2026-07-27 (#803) — *"the budget is now measured over one
    axis member's Screen 2, not over the whole terrain"* — and never reached the
    code: the only predicate was `is_large`, which counts `map_data["elements"]`,
    the WHOLE terrain, and `compose_member_listing` had no over-budget branch at
    all. So a member of 51 Strands rendered 51 rows with their context lines,
    claims and journey arcs, because the terrain around it happened to be small.

    It counts the member's Strands — `count`, the distinct-Strand number the
    heading discloses, NOT `placements`. A cover places one Strand in several
    sections, and the reader's cost is the Strands they must read, not the number
    of times the substrate mentioned them.
    """
    return int(ms.get("count") or 0) > SCREEN_BUDGET


def compose_member_listing(map_data, tag, cands, axis="tag", claims=None,
                           substrate=SUBSTRATE_DEFAULT, grouping=None,
                           view_path=None, subgroups=None):
    """Screen 2 as a LISTING: the member's Strands, WHOLE, in sections.

    Served whole with the count disclosed — no within-member cap, no
    truncation (upstream ruling 2026-07-27). Lines reuse the View's own
    `- **<id>** — <claim>` convention so selection stays the shipped
    `{index, note, pin}` hand-off: ids here are the SAME ids `candidates()`
    assigns, so `brief` resolves a Screen-2 pick with no new entry pipeline.

    COMPOSED MODE (Story 20.66, #976/#977). Passing `claims` returns the FINAL
    screen — section ids, `in common:` lines and rows together — so the
    presenting agent relays one block and never retypes a Strand row. The rows
    were always deterministic; what was missing was any reason for them to
    survive the relay intact, and a reworded headline (#976) or a dropped
    `no-journey` mark (#977) is what a hand-relay produces. Claims are CARRIED
    verbatim, never recomposed, exactly as `compose_full_report` carries them;
    a section whose claim was not passed states the absence rather than having
    one invented. With `claims=None` the output is the pre-20.66 listing plus
    the placement disclosure Story 20.83 (#1039) moved onto both surfaces.

    THE RENDERING ITSELF LIVES IN `_compose_member_rendering` (Story 20.83),
    which the View file also calls. This function is now the console's entry to
    it: it resolves the sections, nothing more.
    """
    # The substrate and grouping are THREADED, not defaulted (#1017). This
    # call used to be `member_sections(map_data, tag, axis)`, so a judged
    # substrate reached the JSON `sections` field correctly while the composed
    # `listing` beside it rendered CO-TAG sections — two answers to one
    # question, from one response. It went unnoticed because every fixture
    # exercised the co-tag axis, where omitting the arguments happens to
    # produce the right answer, so no check could see it; the journey-similarity
    # measurement (#889) was the first run to ask for anything else.
    #
    # This matters most exactly where it is least visible: Story 20.66 made the
    # script compose the screen end to end so a hand-relay could not reword a
    # row. A screen composed from the wrong substrate is that remedy defeated
    # at the source — faithfully relayed, and wrong.
    ms = member_sections(map_data, tag, axis, substrate=substrate,
                         grouping=grouping)
    # The adopted semantic subdivision, applied to THIS composer's own sections
    # (Story 20.87). It is threaded like `grouping` and `substrate` above and
    # for the same reason: a rendering composed from a different structure than
    # the JSON beside it is two answers to one question.
    apply_subgroups(ms, subgroups)
    return _compose_member_rendering(map_data, ms, cands, claims,
                                     view_path=view_path,
                                     summarise=member_is_large(ms))


def _compose_member_rendering(map_data, ms, cands, claims=None,
                              view_path=None, summarise=False, whole=False):
    """THE complete rendering of one member — the ONE code path both surfaces
    draw from (Story 20.83, #1039).

    `compose_member_listing` (the console) and `compose_member_view` (the file
    the console points at) used to be two implementations of one rendering, and
    they drifted exactly as two implementations do: the View carried a heading,
    a placement count and a bare ``- `slug` — gloss`` per Strand, while the
    screen beside it had gained display indexes, the pin, the `in common:`
    claims, the journey arcs, the row-type legend and the disclosure block. The
    spec's split is *screen summarises, file holds the whole*
    (`specs/spec-terrain/presentation.md:218-221`) — so the file being the
    POORER surface inverted the requirement it was built to serve.

    The split is a split of WHICH surface is shown, never of what the complete
    rendering IS. Keeping one function is therefore the fix: a second copy would
    re-earn the drift the moment either surface gains a line.

    `summarise` IS THE SIZE SWITCH (Story 20.84, #1038), and it is the ONE thing
    the two surfaces differ on. The console passes `member_is_large(ms)`; the
    View file never passes it, because the file is the surface that holds the
    whole — that is the split, not a second rendering. Under budget the console
    output is byte-identical to what it was before this switch existed
    (`presentation.md:311-312` names that branch *"the shipped behaviour and must
    not regress"*), and above it the rows move to the file the summary names.
    """
    by_slug = {c.get("slug"): c for c in cands if c.get("kind") == "element"}
    pin = map_data.get("coverage", {}).get("pin")
    noun = "topic" if ms.get("axis") == "topic" else "tag"
    if summarise:
        lines = [f"# {ms['member']} ({noun}) — {ms['count']} Strand(s), "
                 f"summarised — over the {SCREEN_BUDGET}-Strand screen budget",
                 "",
                 f"Pin: {_pin_display(map_data)}"]
        # THE PATH IS THE SCREEN'S OTHER HALF, so its absence is stated rather
        # than papered over. The switch must NOT fail open into the whole dump
        # it exists to remove: with no path the screen is still a summary, and
        # it says the complete rendering was not written anywhere.
        if view_path:
            # THE POINTER IS RENDERED WHOLE (#1073). It was passed through
            # `_short_path`, which keeps the last two segments — so the one
            # line whose purpose is *open this* named a path that cannot be
            # opened. That helper's own justification ("the full path stays in
            # `map.json`") holds for a trailing annotation and not for an
            # instruction to the owner; `_fit_with_path` states the same rule
            # for the summary payload — shorten the PREFIX, never the path,
            # because a clipped path is an unopenable View.
            # AND IT IS ON ITS OWN LINE (Story 20.115, #1117). Rendering it
            # whole was necessary and not sufficient: the path still sat
            # inline between two clauses of a sentence, and on the 2026-08-01
            # run it reached the owner cut mid-path anyway. A path alone on
            # its line is the form that survives composition and wrapping —
            # which is why the rule is "on its own line", not merely "whole".
            lines += [_owner_surface().artifact_block(
                "The complete rendering — every Strand with its claim, its "
                "`in common:` line and its journey — is in the View file",
                view_path,
                note="Open it, then answer with a Strand's index (for example "
                     "L3) and a short note about the angle you want. Free "
                     "text always wins.")]
        else:
            lines += ["NO VIEW PATH WAS GIVEN, so the complete rendering was "
                      "written nowhere. Re-run `member --view PATH`.",
                      "Nothing below is narrowed; the Strand rows are simply "
                      "not on this screen. Selection is still by Strand "
                      "index, and free text always wins."]
        lines += [
            # The codebook pointer (Story 20.26, #861): see the note below.
            f"What the words mean: {OWNER_TERMS_DOC} defines "
            f"{' and '.join(OWNER_TERMS)}.",
            ""]
        # NO ROW-TYPE LEGEND HERE, deliberately (#978's rule, applied): this
        # screen contains no Strand rows, and a legend naming row types the
        # screen does not contain primes the reader to look for rows that never
        # appear. The legend belongs to the surface that has the rows — the
        # View file, which composes it from its own.
    else:
        lines = [f"# {ms['member']} ({noun}) — {ms['count']} Strand(s), "
                 f"shown whole",
                 "",
                 f"Pin: {_pin_display(map_data)}",
                 "Answer with a Strand's index (for example L3) and a short note",
                 "about the angle you want. Free text always wins.",
                 # Composed from the row types actually on this screen (#978):
                 # a legend naming types the screen does not contain primes the
                 # reader to look for rows that never appear.
                 row_type_legend([e for sec in ms["sections"]
                                  for e in sec["strands"]]),
                 # The codebook pointer (Story 20.26, #861): the words this
                 # screen asks the owner to think in are defined one step away,
                 # on a page they can read. A pointer, never a restatement —
                 # one definition that cannot drift from N paraphrases.
                 f"What the words mean: {OWNER_TERMS_DOC} defines "
                 f"{' and '.join(OWNER_TERMS)}.",
                 ""]
    if claims is not None:
        # The authoring class is declared ONCE for the screen, never per line
        # (CAP-2 as amended 2026-07-30, #936): repeating it on every line
        # carries nothing per line and costs attention on all of them.
        #
        # ANNOUNCED IFF RENDERED (Story 20.97, #1075). This used to be gated on
        # `not summarise` while the summary rendered no claims — correct then.
        # The observed defect was the pairing coming apart the other way: a
        # screen announcing that every `in common:` line is machine-composed,
        # above twenty headings carrying none. Now both are gated on the same
        # condition, so they cannot separate again.
        lines += ["Every `in common:` line below is machine-composed at "
                  "render time from the served claims.", ""]
    # THE `G` KIND IS DECLARED WHERE IT IS RENDERED (Story 20.82, #1031,
    # carrying #889's verified constraints onto the offered axis). An id that
    # looks selectable and is not is exactly what retired the `J<n>` namespace —
    # so the surface says what kind `G` is rather than leaving the owner to
    # infer it from the one screen that happens to explain it (the Full Report).
    #
    # UNCONDITIONAL AS OF STORY 20.83 (#1039). This used to ride with `claims`,
    # on the reading that composed mode was "the only screen-2 path that prints
    # group ids" — which was already false: the View file printed them on every
    # render, and printed them with no declaration of their kind. Now that the
    # two surfaces are one rendering, the ids are shown always and the kind is
    # declared always, which is the pairing the rule actually asks for.
    # HELD BACK, NOT REMOVED (#1115 AC1). The owner reports this block
    # separating them from the groups they are choosing among — *"drop the
    # instruction boilerplate from the Display view"*. Dropping it was checked
    # against the record and refused: FOUR shipped amendments require these
    # lines on this screen, each written against an observed defect — the
    # `G<n>` kind declaration is UNCONDITIONAL (#1031/#1039: *"an id that looks
    # selectable and is not is exactly what retired the `J<n>` namespace"*),
    # the subgroup kind is declared where it is rendered (20.87 AC6), the
    # claim-recomposition notice is announced iff rendered (#1075/#936), and
    # BOTH halves of the selection contract are asserted together (#1074,
    # *"because either alone is what the defect looked like"*).
    #
    # So the ORDER changes and the content does not: every declaration still
    # reaches the owner on this screen, after the groups instead of in front of
    # them. That answers the complaint — the boilerplate is no longer between
    # the owner and their judgment — while all four amendments hold, which no
    # amount of deleting could have done.
    declarations = [*GROUP_ID_KIND_LINES, ""]
    if _any_subgroups(ms):
        declarations += [*SUBGROUP_ID_KIND_LINES, ""]
    if ms["substrate"] != SUBSTRATE_DEFAULT:
        # THE ACQUISITION DISCLOSURE, on the reading surface (Story 20.82,
        # #1031). A judged substrate groups on something the owner cannot
        # recover by reading a served field, so the screen states which
        # substrate placed these Strands, that NOTHING was narrowed away, and
        # that the order is a declared key rather than a strength ranking —
        # the three constraints #889's measurement verified. The co-tag screen
        # is left byte-identical: its key is readable on every row.
        lines += [f"Grouped by: {ms['substrate']} — a model-judged substrate. "
                  f"All {len(ms['sections'])} group(s) are shown, none "
                  f"narrowed away, ordered by section title (a declared key, "
                  f"never a strength ranking). Sections are presentation "
                  f"only: nothing here gates, filters or ranks what is "
                  f"selectable.", ""]
    subbed = _substituted_paths(map_data)
    sline = _substitution_disclosure_line(map_data)
    if sline:
        lines += [_clip_line(sline), ""]
    jline = _journey_disclosure_line(map_data)
    if jline:
        lines += [_clip_line(jline), ""]
    # The coverage denominator for THIS screen's rows (#933/#934). It sits with
    # the other disclosures and above the sections, because it states what the
    # `no-journey` markers below are a fraction of — a marker whose denominator
    # arrives after the rows it qualifies is read as a verdict, not a ratio.
    # It travels with the rows, so the summary branch does NOT carry it: on a
    # screen with no `no-journey` markers the ratio has nothing to be a ratio of,
    # and it reads as a verdict on the member — the exact misreading #933/#934
    # placed it above the rows to prevent. It is on the View, with the markers.
    cline = None if summarise else _journey_coverage_line(
        [e for sec in ms["sections"] for e in sec["strands"]])
    if cline:
        lines += [_clip_line(cline), ""]
    # The placement disclosure, carried onto BOTH surfaces (Story 20.83, #1039).
    # It was the one line the View had and the console did not — and under a
    # multi-valued substrate placements exceed the Strand count, so a reader
    # counting rows against the heading needs it wherever the rows are.
    lines += [_clip_line(f"{ms['placements']} placement(s) across "
                         f"{len(ms['sections'])} group(s); "
                         + ("every Strand is placed at least once."
                            if ms.get("covered")
                            else "NOT every Strand was placed — the substrate "
                                 "dropped one, which is a defect, not a "
                                 "narrowing you may rely on.")), ""]
    for sec in ms["sections"]:
        gid = sec.get("group_id")
        # The id is rendered by the SCRIPT, in the shape the View and report
        # paths already use: the owner names these ids to pull a full report, so
        # an id typed by the relay is the same exposure as a row typed by the
        # relay. Unconditional as of Story 20.83 (#1039) — see the `G<n>`
        # declaration above, which now travels with it on every render.
        if gid:
            head = f"## {gid} — {sec['title']} ({len(sec['strands'])})"
        else:
            head = f"## {sec['title']} ({len(sec['strands'])})"
        if sec.get("note"):
            head += f" — {sec['note']}"
        if summarise:
            # THE COMPACT GROUP SUMMARY (Story 20.84, #1038): group id, derived
            # title, count, and the section's own note.
            #
            # THE CLAIM NOW RIDES ALONG (Story 20.97, #1075), reversing #1038's
            # recorded AC4 on that decision's own ground. AC4 held that N
            # unclipped composer sentences is unbounded screen height. Measured
            # on the run that produced the finding: 20 claims, median 173 chars,
            # longest 215, ~25 lines against a summary of about thirty. Height
            # is bounded by group COUNT — which the 20%-of-placements sectioning
            # cap already bounds — and never was bounded by prose length, which
            # is the step "unclipped" → "unbounded" skipped.
            #
            # Without the claim, this screen's whole information content over
            # the tag name is a member count, so every judgment required opening
            # the View: a judgment surface that is a table of contents.
            lines.append(_clip_line(_summary_head(head, sec, by_slug)))
            cl = _summary_claim_line(claims, gid) if claims is not None else None
            if cl:
                lines.append(cl)
            # THE GROUP↔STRAND MAPPING, ON THE SUMMARY (Story 20.114, #1115).
            # A group id is answer shorthand that expands to member indexes, and
            # until now no surface carried the expansion compactly: the summary
            # showed groups without members, the View showed members at full
            # length. So the owner could read what a group MEANS and never what
            # it EXPANDS TO without opening a file. Indexes are what the id
            # stands for, so they belong beside it. This is a list of ids, not
            # composer prose — the screen-height argument that governed the
            # claim does not reach it, exactly as it does not reach the
            # subgroup count above.
            lines += _summary_index_lines(sec, by_slug, claims)
            continue
        lines.append(head)
        lines.append("")
        if claims is not None:
            # THREE states, not two (Story 20.67, #979/#980). A composer that
            # TRIED and found no commonality is not the same as one that was
            # never asked, and collapsing them would hide the signal #980
            # actually found: a claim degenerating into an enumeration is the
            # composer reporting that the group has no single common
            # denominator. It is a SELF-REPORT — `{"G12": null}` — never a
            # machine judgment about the quality of a produced sentence, and
            # it changes NOTHING about membership (see the note below).
            claim = str(claims.get(gid) or "").strip()
            if gid in claims and not claim:
                lines.append(
                    "in common: no single commonality found — the composer "
                    "reports these Strands share no one denominator it could "
                    "state. They are grouped as placed; nothing here has been "
                    "regrouped, reordered or dropped on account of it.")
            elif claim:
                # VERBATIM, as composed. Not re-derived, not shortened, and
                # deliberately NOT clipped: the claim is the composer's own
                # sentence and clipping it would re-create #976 one layer up.
                lines.append(f"in common: {claim}")
            else:
                lines.append("in common: not composed for this group — "
                             "stated as absent rather than invented here.")
            lines.append("")
            # AC3: the disclosure above is rendering ONLY. Section membership,
            # order and counts are fixed by `member_sections` before any prose
            # exists, and no branch here touches them — a machine judgment
            # about prose must never move a Strand, or grouping stops being
            # navigation and becomes a gate.
        def rows(strands, _lines=lines):
            for el in strands:
                c = by_slug.get(el.get("slug"))
                ident = c["id"] if c else el.get("slug", "?")
                claim = el.get("gloss") or el.get("title") or el.get("slug", "")
                mark = (" — already consumed, still selectable"
                        if el.get("consumed") else "")
                # THE SELECTION SCREEN KEEPS CLIPPING (Story 20.73, #1011); the
                # VIEW FILE does not clip a SERVED rendering (Story 20.98,
                # #1076). The exemption is a property of the surface, not of
                # the material, so it is applied here at the consumer and never
                # in `_journey_arc_line` (which never truncated) or in
                # VIEW_LINE_CHARS (which still binds the screens).
                #
                # The discriminator is COMPOSED versus SERVED. A composed line
                # always has a shorter authored wording available; a served
                # rendering has none, because it is relocatable and never
                # re-expressible — so clipping one is the only cut available,
                # and it is the worst one: an arc's shape is belief → break →
                # new position, and a tail cut reliably keeps the belief and
                # drops the break.
                _lines.append(_clip_line(f"- **{ident}** — {claim}{mark}"))
                _lines.append(_clip_line(
                    _strand_context_line(el, ms["member"], subbed)))
                # The lesson's ARC, on the lesson's own row (Story 20.30,
                # #871). It is displayed, never selectable: the row's index
                # still names the Lesson, so picking it carries the rule and
                # its arc together.
                arc = _journey_arc_line(el)
                if arc:
                    _lines.append(arc if whole else _clip_line(arc))

        # THE HIERARCHY RENDERS UNDER THE PARENT CLAIM (Story 20.87 AC1), and
        # ONLY where a subdivision was adopted: an unsubdivided group takes the
        # branch below and its output is byte-identical to what it has always
        # been (AC8).
        if sec.get("subgroups"):
            _render_subgroups(lines, sec["subgroups"], rows, "in common", 3)
        else:
            rows(sec["strands"])
            lines.append("")
    if summarise:
        # THE ABOVE-BUDGET BRANCH PROPOSES NO LESS (AC5; `presentation.md:316`,
        # *"the size switch changes where the terrain is presented, never
        # whether the map proposes"*). On the whole listing the standing exits
        # arrive with the rows on the relayed surface; here the summary IS the
        # whole of what is relayed, so the exits are composed onto it rather
        # than left to a relay that has nothing else to carry them.
        lines += ["",
                  "Every exit stays open: switch substrate · back to the "
                  "member list · name your own direction · stop here.",
                  "Selection is by Strand index, exactly as on the whole "
                  "listing. Nothing here is capped, truncated or ordered by "
                  "any measure of strength — every group is above, and every "
                  "Strand is in the View.",
                  # THE ANSWER SHAPE, on the screen where the answer is given
                  # (Story 20.96, #1074). The owner's question at this gate is
                  # "do I answer L1, L2, L3 or may I answer G1?" — so the screen
                  # answers it rather than leaving them to reconcile the id-kind
                  # paragraph above with the instruction lines.
                  "You may answer with one index, a set (`L3, L7`), or a group "
                  "id as shorthand — and you may mix them (`G4 + L26, minus "
                  "L48`).",
                  "A group id expands to its members first, so what is "
                  "recorded is always Strands.",
                  # THE CLAIM IS PINNED TO ITS SET, so a set the owner changes
                  # gets its claim recomposed and re-offered rather than
                  # silently kept — carrying a group claim over absent members
                  # would assert commonality the material does not support.
                  "A group's `in common:` claim was composed over its whole "
                  "membership: change the set and the claim is recomposed and "
                  "re-offered, never carried over unchanged."]

    # AND THE DECLARATIONS LAND HERE (#1115 AC1) — after the groups, never
    # before them. See the note where `declarations` is built: the content is
    # unchanged and all four amendments requiring these lines on this screen
    # still hold; only their position moved, which is what the owner's
    # complaint was actually about.
    if declarations:
        lines += ["", *declarations]

    return "\n".join(lines).rstrip() + "\n"


def compose_full_report(map_data, tag, cands, group_ids, axis="tag",
                        claims=None, grouping=None, subgroups=None):
    """The FULL REPORT for the group ids the owner named (Story 20.56, #938;
    SPEC-terrain CAP-3 §"the owner may pull a FULL REPORT for named group ids").

    Each named group is rendered SEPARATELY, in the order asked, keyed by its
    screen id — never flattened into a union, because the whole point is
    judging whether a grouping makes sense, and a union destroys exactly the
    boundary being judged.

    Claims are CARRIED, never recomposed (AC3). Recomposition belongs to subset
    selection, which is a different operation on a different input: it runs
    over the owner's chosen subset, while this runs over the group's full,
    unaltered member set. So the claim arrives from the screen that already
    composed it and is echoed verbatim; a group whose claim was not carried
    says so rather than having one invented for it here.

    NOTHING IS SELECTED (AC4). This is inspection: no Strand is picked, no
    brief is composed, and the standing exits stay exactly where they were.

    The whole-relay is a STATED EXCEPTION to the size switch (AC7), bounded by
    the owner's own pointers: it relays whole rather than collapsing to a
    summary plus a path, and it covers exactly the groups named — never the
    whole member. The reported defect was a relay doing its best and flattening
    nineteen Strands into headline one-liners, which is why the rendering lives
    here in code rather than in a prose obligation.

    WHOLE MEANS UNTRUNCATED (Story 20.73, #1011; CAP-3 as amended 2026-07-31,
    #986). No line composed here is clipped: not the group definition, not a
    gloss row, not a context line, and above all not a journey arc — the
    material screen 2 advertises 49 of 51 Strands as carrying, and the only
    content this surface was systematically cutting. A rendered line ending in
    the elision marker is therefore the served material's own. The surface also
    NAMES ITS JOURNEY LABEL in the header legend, because the owner asked what
    `how it changed:` was and nothing here answered.

    THE DETERMINISTIC CONTEXT LINE LIVES IN A FOOTNOTE (Story 20.74, #987;
    CAP-3 as amended 2026-07-31). It bundles three fields with three different
    audiences — cross-group placement, which serves *selection-screen*
    navigation; the origin pin, which serves verification; and a completeness
    attestation with no reader action attached — and between a claim and the
    material it stands for, all three are noise. It is RELOCATED, NEVER
    DROPPED: the same composed line, unchanged in what it says, is collected
    verbatim at the end of the report, so the pins the report rendered are
    still restated (a CAP-3 constraint this story must not regress) and the
    reading flow no longer pays for them per row. `_strand_context_line` is
    SHARED with `compose_member_listing`, which keeps the line ON the row —
    that is the surface it was designed for, where placement is navigation.
    Only this call site moves.

    The reported "inconsistent presence" is NOT a defect and is not fixed
    here: presence was never conditional. The composer emits the line for
    every Strand and only its first field varies — a Strand with no co-tags
    renders `in no other Topic`. The groups that looked inconsistent differ in
    CO-TAGGING, not in row contract.
    """
    ms = member_sections(map_data, tag, axis, grouping=grouping)
    apply_subgroups(ms, subgroups)
    by_id = {s.get("group_id"): s for s in ms["sections"]}
    unknown = [g for g in group_ids if g not in by_id]
    if unknown:
        raise SystemExit(_err(
            f"{', '.join(unknown)} names no group on this screen. Group ids "
            f"are PER-SCREEN and PER-PIN — they do not survive a re-run — so "
            f"this screen's ids are {', '.join(sorted(by_id))} at pin "
            f"{map_data.get('coverage', {}).get('pin')}. Re-read the screen "
            "and name the groups from it."))
    by_slug = {c.get("slug"): c for c in cands if c.get("kind") == "element"}
    subbed = _substituted_paths(map_data)
    claims = claims or {}
    noun = "topic" if axis == "topic" else "tag"
    # THE PIN AND THE GROUP DEFINITIONS ARE RESTATED (AC6): group ids are
    # per-screen, per-pin identifiers, so a report naming `G2` alone is
    # unreadable one invocation later.
    lines = [f"# Full report — {ms['member']} ({noun}), "
             f"{len(group_ids)} group(s) of {len(ms['sections'])}",
             "",
             f"Pin: {_pin_display(map_data)}",
             f"Grouped by: {ms['substrate']}. Group ids are per-screen and "
             "per-pin; each is defined below where it is rendered.",
             "This is inspection only — nothing here selects a Strand or "
             "composes a brief.",
             # THE JOURNEY LABEL IS NAMED ON THE SURFACE (amended 2026-07-31,
             # #986). The owner asked whether `how it changed:` shows
             # journeys — it does, and nothing here said so, while screen 2's
             # legend is composed from the row types that actually mint ids
             # and so never speaks the word here. The ratified vocabulary and
             # the rendered label were disconnected on the one surface whose
             # purpose is reading, so the report states the mapping itself
             # rather than borrowing a spelling from another screen.
             "Legend: a Strand's `how it changed:` line is its JOURNEY — the "
             "arc recorded for that Lesson, rendered on the Lesson's own row. "
             "A Journey is never a row of its own, so no separate journey row "
             "appears here; an absent arc says which absence it is.",
             # THE RELAY IS WHOLE, and that is stated where the reader meets
             # it: nothing below is clipped by this renderer, so a line ending
             # in an elision marker is the served material's own.
             "Every line below is relayed whole — this report does not "
             "shorten a gloss, a context line or a journey arc.",
             # WHERE THE AUDIT METADATA WENT, said before the reader misses it
             # (amended 2026-07-31, #987). Relocated, never dropped: a reader
             # who wants the placement, the origin pin or the attestation is
             # told, at the top, exactly where every one of them is.
             "Each Strand's placement, origin pin and attestation are "
             "collected in the FOOTNOTES at the end of this report, out of "
             "the reading flow and none of them dropped.",
             ""]
    # The subgroup id kind, declared where it is rendered and only where it is
    # (Story 20.87 AC6) — the same pairing the `G<n>` declaration follows on
    # the selection screens.
    if any(by_id[g].get("subgroups") for g in group_ids if g in by_id):
        lines += [*SUBGROUP_ID_KIND_LINES, "",
                  "A subdivided group shows its parent claim first — why "
                  "these Strands share a screen at all — and then each "
                  "subgroup's own claim beneath it. Both are carried verbatim "
                  "from the screen that composed them.", ""]
    groups = []
    # Collected as the body renders, emitted once at the end: one entry per
    # rendered Strand, in the order the report rendered them, so the footnote
    # is a relocation of the row's own line and not a second derivation of it.
    footnotes = []
    for gid in group_ids:
        sec = by_id[gid]
        strands = sec["strands"]
        claim = str(claims.get(gid) or "").strip()
        lines.append(f"## {gid} — {sec['title']} ({len(strands)})")
        lines.append("")
        # THE DEFINITION of the id, restated: which Strands this id names on
        # this screen, so the report is readable without the screen beside it.
        # UNCLIPPED, like every other line on this path: the note it carries
        # is the disclosure that a group stayed over the one-fifth bound, and
        # a clipped disclosure is the failure mode the disclosure exists for.
        lines.append(
            f"Group definition: the {len(strands)} Strand(s) the "
            f"{ms['substrate']} substrate placed under "
            f"{sec['title']!r}" + (f" — {sec['note']}" if sec.get("note") else ""))
        lines.append("")
        if claim:
            # VERBATIM, as the screen showed it. Not re-derived, not shortened.
            lines.append(f"In common: {claim}")
        else:
            # Never invented here. A missing claim is a stated absence, which
            # is the same rule the rest of this surface follows.
            lines.append("In common: not carried from the screen for this "
                         "group — stated as absent rather than recomposed "
                         "here, because recomposition belongs to subset "
                         "selection.")
        lines.append("")

        def report_rows(els, _gid=gid):
            for el in els:
                c = by_slug.get(el.get("slug"))
                ident = c["id"] if c else el.get("slug", "?")
                text = el.get("gloss") or el.get("title") or el.get("slug", "")
                mark = (" — already consumed, still selectable"
                        if el.get("consumed") else "")
                # NOTHING ON THE REPORT PATH IS CLIPPED (Story 20.73, #1011;
                # SPEC-terrain CAP-3 as amended 2026-07-31, #986). The whole
                # relay was already the contract — *"it relays whole, a stated
                # exception to the size switch, not an oversight"* — and this
                # renderer was violating it: `_clip_line` cut every line at
                # VIEW_LINE_CHARS, so in the one surface exempted from the size
                # switch the journey arc was the content systematically ending
                # in `…` mid-sentence. The exception is a property of THIS
                # surface, not of the material, so the fix is here at the
                # consumer and not in `_journey_arc_line` (which never
                # truncated) or in VIEW_LINE_CHARS (which still binds the
                # size-switched screens, `compose_member_listing` above).
                lines.append(f"- **{ident}** — {text}{mark}")
                # THE CONTEXT LINE IS NOT ON THE ROW HERE (Story 20.74, #987).
                # It is composed by the SAME function the selection screens use
                # and carried, byte for byte, into the footnote block below:
                # what it says is unchanged, only where it lives. Its three
                # fields — placement, origin pin, attestation — plus the
                # SUBSTITUTED SOURCE and `no-journey` marks therefore all
                # survive the move.
                footnotes.append(
                    f"- **{ident}** — {_gid} — "
                    f"{_cotags_replace_if_redundant(_strand_context_line(el, ms['member'], subbed).strip(), sec['title'])}")
                arc = _journey_arc_line(el)
                if arc:
                    lines.append(arc)

        # THE PARENT CLAIM IS RETAINED AS THE HEADER and the subgroups render
        # beneath it (Story 20.87 AC1) — the Full Report is the surface whose
        # purpose is surveying the material as a whole, which is the ruling's
        # own reason for keeping the parent. An UNSUBDIVIDED group takes the
        # else branch and its output is byte-identical to today's (AC8).
        if sec.get("subgroups"):
            _render_subgroups(lines, sec["subgroups"], report_rows,
                              "In common", 3)
        else:
            report_rows(strands)
        lines.append("")
        groups.append({"group_id": gid, "title": sec["title"],
                       "claim": claim or None,
                       "claim_carried": bool(claim),
                       "strands": [e.get("slug") for e in strands],
                       "count": len(strands),
                       **({"subgroups": _subgroups_payload(sec["subgroups"])}
                          if sec.get("subgroups") else {})})
    # THE FOOTNOTE BLOCK (Story 20.74, #987). One entry per rendered Strand —
    # never per co-tagged Strand, since the line renders for every Strand and
    # only its first field varies — carrying exactly what the row used to
    # carry. It closes the report because that is the point of the move: the
    # verification material is reachable without standing between the reader
    # and the material it verifies.
    if footnotes:
        footnotes, shared_pin = _footnotes_state_shared_pin_once(footnotes)
        lines.append("## Footnotes — placement, origin pins and attestation")
        lines.append("")
        lines.append("One entry per Strand rendered above, in the order it "
                     "was rendered: where else the map places it, where it "
                     "came from, and whether its reasoning travels with it. "
                     "Nothing here is new — this is the row context line, "
                     "moved out of the reading flow.")
        if shared_pin:
            # WHAT IS UNIFORM IS STATED ONCE (Story 20.113, #1116). Measured on
            # the 2026-08-01 run: 110 footnotes, every one carrying the same
            # 40-character pin, because a View is served at ONE hub commit by
            # construction — only the line number ever varied. Repetition at
            # that ratio is the log-file failure the View's own budget clause
            # names, and the remedy it already states is aggregation with the
            # shared part stated once. Nothing is dropped: the pin is here, and
            # it is here EXPLICITLY rather than implied, so a reader can still
            # resolve any line below to a commit.
            lines.append("")
            lines.append(f"Every origin below is served at one pin: "
                         f"`{shared_pin}`. Lines carry the file and line only.")
        lines.append("")
        lines += footnotes
        lines.append("")
    return {"kind": "terrain-full-report", "member": ms["member"], "axis": axis,
            "pin": map_data.get("coverage", {}).get("pin"),
            "substrate": ms["substrate"],
            "asked": list(group_ids),
            "groups": groups,
            # Inspection, asserted as data as well as said in prose.
            "selected": [], "brief": None, "recomposed": False,
            # Asserted as data too: the count a consumer can compare against
            # the rendered Strands, so "relocated, never dropped" is checkable
            # without parsing prose.
            "footnotes": len(footnotes),
            "relay": "whole",
            "report": "\n".join(lines).rstrip() + "\n"}


def cmd_member(args):
    m = load_map(args.map)
    axis = getattr(args, "axis", "tag") or "tag"
    grouping = None
    if getattr(args, "grouping", None):
        try:
            grouping = json.loads(args.grouping)
        except ValueError as e:
            return _err(f"--grouping is not valid JSON ({e})")
    ms = member_sections(m, args.tag, axis,
                         substrate=getattr(args, "substrate", SUBSTRATE_DEFAULT),
                         grouping=grouping)
    if not ms["count"]:
        noun = "topic" if axis == "topic" else "tag"
        return _err(f"no Strand sits under the {noun} {args.tag!r} at this "
                    f"pin — re-run the axis and pick from the fresh listing")
    claims = None
    if getattr(args, "claims", None):
        try:
            claims = json.loads(args.claims)
        except ValueError as exc:
            return _err(f"--claims is not readable JSON: {exc}")
        if not isinstance(claims, dict):
            return _err("--claims must be an object keyed by group id, "
                        'for example {"G1": "..."}')
    # THE SEMANTIC SUBGROUP LAYER (Story 20.86, #1041) — the composer's ADOPTED
    # subdivisions only, applied AFTER the parent sectioning is fixed and after
    # the claims exist. Absent, the screen is exactly what it was.
    subgroups = None
    if getattr(args, "subgroups", None):
        try:
            subgroups = json.loads(args.subgroups)
        except ValueError as exc:
            return _err(f"--subgroups is not readable JSON: {exc}")
    try:
        apply_subgroups(ms, subgroups)
    except ValueError as exc:
        return _err(str(exc))
    cands = candidates(m)
    view_path = getattr(args, "view", None)
    over = member_is_large(ms)
    listing = compose_member_listing(
        m, args.tag, cands, axis, claims,
        substrate=getattr(args, "substrate", SUBSTRATE_DEFAULT),
        grouping=grouping, view_path=view_path, subgroups=subgroups)
    if over and not view_path:
        # Mirrors `cmd_payload`'s warning on the terrain path: the screen has
        # already switched — it does NOT fail open into the dump — but the half
        # that holds the whole was never named, so the caller is told at the
        # only moment it can still fix it.
        sys.stderr.write(
            f"warning: {ms['member']!r} holds {ms['count']} Strands, past the "
            f"screen budget of {SCREEN_BUDGET} — pass --view PATH (resolve it "
            f"with `resolve-paths.py`) so the complete rendering is written to "
            f"a View file the owner can open. Without it the screen carries "
            f"group summaries and the rows are nowhere.\n")
    out = {"kind": "terrain-member", "member": ms["member"], "axis": axis,
           "count": ms["count"],
           # THE SIZE SWITCH, ASSERTED AS DATA (Story 20.84, #1038). The
           # composer switches; the skill relays what comes back and decides
           # nothing — so what it switched on is readable rather than inferred
           # from the shape of the prose.
           "over_budget": over,
           "screen_budget": SCREEN_BUDGET,
           "view": view_path,
           # AC6 — THE SCREEN IS COMPOSED AND RELAYED ONCE PER SELECTION. The
           # two-call flow's FIRST call is an inputs call: it exists to hand
           # over `background.inputs` so claims can be composed, and its
           # `listing` is a by-product. Relaying both calls is what produced the
           # identical screen twice back-to-back in the observed sitting, and
           # nothing in the response said which one was the screen. Now it does.
           "relay": "whole" if claims is not None else
                    "inputs-only — compose the claims and call again; do NOT "
                    "relay this listing, it is not the screen",
           # The grouping disclosure (Story 20.36, #890): which substrate
           # produced these sections, how many placements it made — the unit
           # the cap is computed against — and its own coverage assertion.
           "substrate": ms["substrate"],
           "substrate_offered": ms["substrate"] in SUBSTRATES,
           "placements": ms["placements"],
           "covered": ms["covered"],
           # THE LEAF COVER, ASSERTED AFTER COMPOSITION (Story 20.86, #1041,
           # AC5/AC6). `covered` above is the parent-level assertion the
           # substrate owes; this one is counted over the LEAVES of the
           # composed hierarchy, in placements, and it is computed after the
           # subdivision arrives — a composer that cannot omit in principle can
           # still omit in fact. With no subdivision the two agree, which is
           # the honest reading of an unsubdivided screen rather than a
           # special case.
           "leaf_placements": ms["leaf_placements"],
           "leaf_covered": ms["leaf_covered"],
           "subdivided": ms["subdivided"],
           "sections": [{"title": s["title"],
                         "group_id": s.get("group_id"),
                         "strands": [e.get("slug") for e in s["strands"]],
                         "note": s.get("note"),
                         **({"subgroups": _subgroups_payload(s["subgroups"])}
                            if s.get("subgroups") else {})}
                        for s in ms["sections"]],
           # Section-background composition inputs (Story 20.24, #853;
           # CAP-2 as amended 2026-07-27, #850). The SCRIPT owns the
           # sections — their membership is fixed before any prose exists —
           # and the presenting agent composes ONLY the background prose,
           # from these served claims, bound by the rules below. That split
           # is what keeps a model in the loop from becoming a gate: a
           # composer that receives sections as fixed input cannot omit,
           # merge, or rank a Strand, only narrate what is already there.
           "background": {
               "authoring": "machine-composed at render time, marked",
               "inputs": [{"title": s["title"],
                           "claims": [str(e.get("gloss") or e.get("title")
                                          or e.get("slug") or "")
                                      for e in s["strands"]]}
                          for s in ms["sections"]],
               "rules": [
                   "background only — never a substitute for a Strand's "
                   "served rendering or its disclosure",
                   "every Strand stays exactly once and selectable — "
                   "composition never omits, merges, ranks, or gates",
                   # ONCE PER SURFACE, not once per line (CAP-2 as amended
                   # 2026-07-30, #936). The obligation is unchanged in force;
                   # only its carrier is bounded. A constant repeated on
                   # every line of a declared class carries zero information
                   # per line while costing attention on each — so where the
                   # whole class is composed, one preamble declaration
                   # discharges it. The marker is owed again the moment a
                   # screen MIXES composed and quoted lines of the same
                   # visual class, and then it marks the MINORITY, because
                   # that is where the reader's default is wrong.
                   "declare the authoring class once on the surface: where "
                   "every line of a visual class is machine-composed, one "
                   "preamble declaration discharges it and no per-line "
                   "parenthetical is used; where a screen mixes composed "
                   "and quoted lines of the same class, mark the minority "
                   "class per line",
                   "gateway unavailable or composition skipped: say so and "
                   "relay the deterministic titles — never silent",
               ]},
           "listing": listing}
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def _member_record(match, arc=True):
    """One selected Strand, as the brief records it (Story 20.54 AC4).

    THE ARC TRAVELS WITH THE STRAND (Story 20.90, #1044). This projection was
    the single drop point: it flattened a selected Strand to four keys while
    the element it projects from carried `journey` and `journey_cite`, so the
    material the owner had just been shown on Screen 2 was not in the brief
    they composed from it. The arc is the SERVED `journey_gloss:` rendering,
    QUOTED VERBATIM — never re-expressed, never paraphrased, never synthesised
    from a headline, and never rewritten into a rule, a summary or a claim by
    any later stage. That is the same rule `:500-507` states for the row.

    ABSENCE IS CARRIED IN ITS THREE KINDS (AC2), never as a missing key: the
    shape is the one `journey_similarity_inputs` already ships — `served:
    false` plus the `not_served_reason` the element carries as
    `journey_unavailable` — so "no arc exists" and "no arc arrived" stay
    different findings downstream. It is nested under `journey` so those field
    names keep their meaning beside the record's own `cite`.

    `arc=False` IS FOR ONE CALLER AND ITS GROUND IS AT THAT CALL SITE
    (AC3): the substitution pool. Widening is not a default here — the
    anti-widening bound is real, it simply never excluded a SELECTED Strand's
    own arc, which is material the owner pointed at.
    """
    rec = {"index": match.get("id"), "slug": match.get("slug"),
           # The served rendering, as served — never re-expressed here.
           "gloss": match.get("gloss"),
           "cite": match.get("situation")}
    if arc:
        served = match.get("journey")
        served = served if isinstance(served, str) and served.strip() else None
        rec["journey"] = {
            "arc": served,
            "arc_cite": match.get("journey_cite"),
            "served": served is not None,
            "not_served_reason": match.get("journey_unavailable"),
        }
    return rec


def compose_member_view(map_data, ms, cands=None, claims=None):
    """One member's WHOLE view, for the file the screen points at (#892).

    The screen carries compact summaries — a derived title, member ids and
    counts — because ~50 Strands reprinted per view is unreadable; the file
    carries the complete rendering, because a view that lives only in a file
    is uninspectable at the moment of selection. Neither alone is the
    requirement; the split is.

    AS OF STORY 20.83 (#1039) THIS IS A DELEGATION, NOT A RENDERING. It used to
    compose its own, poorer output — no display indexes, no pin, no `in common:`
    claim, no journey line — so the file the owner was pointed at was the worse
    of the two surfaces and could not even be selected from. The complete
    rendering is `_compose_member_rendering`, and both surfaces draw from it.

    `cands` is accepted so the caller can pass the SAME `candidates(map_data)`
    the screen used — deriving it twice is how the two would drift again.
    """
    if cands is None:
        cands = candidates(map_data)
    # `whole=True` IS THE ONE THING THIS SURFACE ASKS FOR (Story 20.98, #1076).
    # Both surfaces still draw from one rendering — this is a parameter, not a
    # second copy, which is the drift #1039 records. It says only *this output
    # is the file*, and the file is what the spec's "the path holds the whole"
    # clause names.
    return _compose_member_rendering(map_data, ms, cands, claims, whole=True)
