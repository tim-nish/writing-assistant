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
    _clip_line,
    _journey_coverage_line,
    _journey_disclosure_line,
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


# --- journey similarity (Story 20.37, #891) ---------------------------------
# MODEL-JUDGED, so the script owns the inputs and the enforcement and never the
# judgment. It is BUILT AND NOT OFFERED (SPEC-terrain CAP-2's offering gate,
# #889): a deterministic substrate is inspectable by reading the key it grouped
# on; this one is not, because whether its groups read as one shared background
# is the very thing under test. It joins the offered set only after one
# measurement run passes an owner verdict.
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


# OFFERED substrates — what the owner may choose today.
SUBSTRATES = {"co-tags": _substrate_co_tags}
# BUILT BUT NOT OFFERED (#889). Reachable through the dogfood harness only.
SUBSTRATES_UNOFFERED = {JOURNEY_SUBSTRATE: _substrate_journey_similarity}
SUBSTRATE_DEFAULT = "co-tags"


def _substrate_fn(name):
    """Resolve a substrate by name across both sets. Membership of the OFFERED
    set is what the chooser reads; this resolver is what the harness uses."""
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


def compose_member_listing(map_data, tag, cands, axis="tag", claims=None,
                           substrate=SUBSTRATE_DEFAULT, grouping=None):
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
    one invented. With `claims=None` the output is byte-identical to the
    pre-20.66 listing.
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
    by_slug = {c.get("slug"): c for c in cands if c.get("kind") == "element"}
    pin = map_data.get("coverage", {}).get("pin")
    noun = "topic" if axis == "topic" else "tag"
    lines = [f"# {ms['member']} ({noun}) — {ms['count']} Strand(s), shown whole",
             "",
             f"Pin: {_pin_display(map_data)}",
             "Answer with a Strand's index (for example L3) and a short note",
             "about the angle you want. Free text always wins.",
             # Composed from the row types actually on this screen (#978):
             # a legend naming types the screen does not contain primes the
             # reader to look for rows that never appear.
             row_type_legend([e for sec in ms["sections"]
                              for e in sec["strands"]]),
             # The codebook pointer (Story 20.26, #861): the words this screen
             # asks the owner to think in are defined one step away, on a page
             # they can read. A pointer, never a restatement — one definition
             # that cannot drift from N paraphrases.
             f"What the words mean: {OWNER_TERMS_DOC} defines "
             f"{' and '.join(OWNER_TERMS)}.",
             ""]
    if claims is not None:
        # The authoring class is declared ONCE for the screen, never per line
        # (CAP-2 as amended 2026-07-30, #936): repeating it on every line
        # carries nothing per line and costs attention on all of them.
        lines += ["Every `in common:` line below is machine-composed at "
                  "render time from the served claims.", ""]
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
    cline = _journey_coverage_line(
        [e for sec in ms["sections"] for e in sec["strands"]])
    if cline:
        lines += [_clip_line(cline), ""]
    for sec in ms["sections"]:
        gid = sec.get("group_id")
        # In composed mode the id is rendered by the SCRIPT, in the shape the
        # View and report paths already use: the owner names these ids to pull
        # a full report, so an id typed by the relay is the same exposure as a
        # row typed by the relay.
        if claims is not None and gid:
            head = f"## {gid} — {sec['title']} ({len(sec['strands'])})"
        else:
            head = f"## {sec['title']} ({len(sec['strands'])})"
        if sec.get("note"):
            head += f" — {sec['note']}"
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
        for el in sec["strands"]:
            c = by_slug.get(el.get("slug"))
            ident = c["id"] if c else el.get("slug", "?")
            claim = el.get("gloss") or el.get("title") or el.get("slug", "")
            mark = " — already consumed, still selectable" if el.get("consumed") else ""
            # THIS SURFACE KEEPS CLIPPING (Story 20.73, #1011). The size
            # switch binds the selection screens; only the Full Report is a
            # stated exception to it, so the unclipping done in
            # `compose_full_report` stops here deliberately. Removing
            # `_clip_line` from this path would widen that story into the
            # surfaces the switch governs.
            lines.append(_clip_line(f"- **{ident}** — {claim}{mark}"))
            lines.append(_clip_line(_strand_context_line(el, ms["member"], subbed)))
            # The lesson's ARC, on the lesson's own row (Story 20.30, #871).
            # It is displayed, never selectable: the row's index still names
            # the Lesson, so picking it carries the rule and its arc together.
            arc = _journey_arc_line(el)
            if arc:
                lines.append(_clip_line(arc))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def compose_full_report(map_data, tag, cands, group_ids, axis="tag",
                        claims=None, grouping=None):
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
        for el in strands:
            c = by_slug.get(el.get("slug"))
            ident = c["id"] if c else el.get("slug", "?")
            text = el.get("gloss") or el.get("title") or el.get("slug", "")
            mark = (" — already consumed, still selectable"
                    if el.get("consumed") else "")
            # NOTHING ON THE REPORT PATH IS CLIPPED (Story 20.73, #1011;
            # SPEC-terrain CAP-3 as amended 2026-07-31, #986). The whole relay
            # was already the contract — *"it relays whole, a stated exception
            # to the size switch, not an oversight"* — and this renderer was
            # violating it: `_clip_line` cut every line at VIEW_LINE_CHARS, so
            # in the one surface exempted from the size switch the journey arc
            # was the content systematically ending in `…` mid-sentence. The
            # exception is a property of THIS surface, not of the material, so
            # the fix is here at the consumer and not in `_journey_arc_line`
            # (which never truncated) or in VIEW_LINE_CHARS (which still binds
            # the size-switched screens, `compose_member_listing` above).
            lines.append(f"- **{ident}** — {text}{mark}")
            # THE CONTEXT LINE IS NOT ON THE ROW HERE (Story 20.74, #987). It
            # is composed by the SAME function the selection screens use and
            # carried, byte for byte, into the footnote block below: what it
            # says is unchanged, only where it lives. Its three fields —
            # placement, origin pin, attestation — plus the SUBSTITUTED SOURCE
            # and `no-journey` marks therefore all survive the move.
            footnotes.append(
                f"- **{ident}** — {gid} — "
                f"{_strand_context_line(el, ms['member'], subbed).strip()}")
            arc = _journey_arc_line(el)
            if arc:
                lines.append(arc)
        lines.append("")
        groups.append({"group_id": gid, "title": sec["title"],
                       "claim": claim or None,
                       "claim_carried": bool(claim),
                       "strands": [e.get("slug") for e in strands],
                       "count": len(strands)})
    # THE FOOTNOTE BLOCK (Story 20.74, #987). One entry per rendered Strand —
    # never per co-tagged Strand, since the line renders for every Strand and
    # only its first field varies — carrying exactly what the row used to
    # carry. It closes the report because that is the point of the move: the
    # verification material is reachable without standing between the reader
    # and the material it verifies.
    if footnotes:
        lines.append("## Footnotes — placement, origin pins and attestation")
        lines.append("")
        lines.append("One entry per Strand rendered above, in the order it "
                     "was rendered: where else the map places it, where it "
                     "came from, and whether its reasoning travels with it. "
                     "Nothing here is new — this is the row context line, "
                     "moved out of the reading flow.")
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
    cands = candidates(m)
    listing = compose_member_listing(
        m, args.tag, cands, axis, claims,
        substrate=getattr(args, "substrate", SUBSTRATE_DEFAULT),
        grouping=grouping)
    out = {"kind": "terrain-member", "member": ms["member"], "axis": axis,
           "count": ms["count"],
           # The grouping disclosure (Story 20.36, #890): which substrate
           # produced these sections, how many placements it made — the unit
           # the cap is computed against — and its own coverage assertion.
           "substrate": ms["substrate"],
           "substrate_offered": ms["substrate"] in SUBSTRATES,
           "placements": ms["placements"],
           "covered": ms["covered"],
           "sections": [{"title": s["title"],
                         "group_id": s.get("group_id"),
                         "strands": [e.get("slug") for e in s["strands"]],
                         "note": s.get("note")}
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


def _member_record(match):
    """One selected Strand, as the brief records it (Story 20.54 AC4)."""
    return {"index": match.get("id"), "slug": match.get("slug"),
            # The served rendering, as served — never re-expressed here.
            "gloss": match.get("gloss"),
            "cite": match.get("situation")}


def compose_member_view(map_data, ms):
    """One member's WHOLE view, for the file the screen points at (#892).

    The screen carries compact summaries — a derived title, member ids and
    counts — because ~50 Strands reprinted per view is unreadable; the file
    carries the complete rendering, because a view that lives only in a file
    is uninspectable at the moment of selection. Neither alone is the
    requirement; the split is.
    """
    lines = [f"# {ms['member']} — {ms['count']} Strand(s), grouped by "
             f"{ms['substrate']}", "",
             f"{ms['placements']} placement(s) across {len(ms['sections'])} "
             f"group(s). Every Strand appears at least once.", ""]
    for sec in ms["sections"]:
        head = f"## {sec.get('group_id') or ''} {sec['title']} "\
               f"({len(sec['strands'])})".strip()
        lines.append(head)
        if sec.get("note"):
            lines.append(f"_{sec['note']}_")
        lines.append("")
        for el in sec["strands"]:
            lines.append(f"- `{el.get('slug')}` — "
                         f"{el.get('gloss') or el.get('title') or ''}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"
