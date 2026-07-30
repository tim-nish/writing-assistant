#!/usr/bin/env python3
"""terrain_text.py — the terrain surface's text and disclosure primitives
(Story 20.58, #942; SPEC-writing-assistant, the 2026-07-30 scripts-family
amendment).

A LEAF LAYER, extracted rather than designed. `topic-map-directions.py` reached
its family line ceiling with four stories queued against it, and its definition
breakdown showed no dominant content class — so the seam was drawn where
COUPLING IS LOWEST and in-flight work is least disturbed, not where the
semantics are richest. That rule, and the measurement behind it, are recorded in
the amendment; they are not restated here.

What lives here is everything the terrain surface uses to make text FIT and to
say what a screen does and does not cover:

  * the fitting primitives — `_fit`, `_elide`, `_clip_line`, `_fit_parts`,
    `_fit_with_path`, `_short_path` — which give by AUTHORSHIP inside a budget
    and never by a mid-word slice wearing a period (#832);
  * the disclosure lines — coverage, gloss, size, journey, substitution — each
    of which names a bound or an abnormal condition ON THE SURFACE, because a
    bounded projection read as the whole record is the harm the bound exists to
    guard against;
  * `_verdict_phrase` and `_pin_display`, the two owner-facing renderings whose
    wording is fixed by ratified decisions rather than by this module.

This is a MOVE, not a rewrite: every definition below is the one that stood in
`topic-map-directions.py`, unchanged, and the composed output is byte-identical
for the same inputs. The budgets travel with the code that reads them —
`BUDGETS` is `_fit`'s author-time declaration and `VIEW_LINE_CHARS` is
`_clip_line`'s bound — and `topic-map-directions.py` imports both back, so each
number is still declared in exactly one place.

Stdlib-only, and imported only. It has no CLI: nothing here is a command.
"""


# The proposal contract's per-field display budgets. Composing past one produces
# a payload the validator blocks and the owner therefore never sees, so the
# composer stays inside them rather than discovering them at presentation time.
BUDGETS = {"where": 240, "why": 200, "effect": 140}


def _fit(text, budget=BUDGETS["effect"]):
    """A payload field is AUTHORED within its budget, never truncated (#832;
    SPEC-writing-assistant owner-facing proposal contract, clause (e)). This
    collapses whitespace only: an over-budget value flows to
    `validate-proposal-payload.py`, which blocks presentation naming the field
    — the sanctioned failure — instead of a mid-word slice wearing a period
    ("Too many to f.") reaching the owner as if it were a sentence. `budget`
    is kept in the signature as the author-time declaration of which budget
    the text was written against."""
    del budget  # authorship contract, not a truncation input
    return " ".join(str(text).split())


def _elide(text, room):
    """Bound a VIEW line's value — a rendered file line, not a payload field.
    The cut is visible ('…') and lands on a word boundary, never a fake
    sentence end (#832)."""
    text = " ".join(str(text).split())
    if len(text) <= room:
        return text
    cut = text[:max(0, room - 1)]
    if " " in cut:
        cut = cut[:cut.rfind(" ")]
    return cut.rstrip() + "…"


# No View line is longer than this. The View is a human surface, so its lines
# are budgeted the way the screen payload's fields already are — a list renders
# one item per line, clipped, capped, with the remainder disclosed. Asserted in
# `scripts/check-topic-map-screen.sh`, so the 818-line regression cannot recur
# unnoticed.
VIEW_LINE_CHARS = 200


def _clip_line(line):
    """Bound one View line, preserving its indentation and leaving blank lines
    blank. `_elide` collapses whitespace, which would flatten the list indents
    the View's structure is made of, so it is applied to the value only."""
    if len(line) <= VIEW_LINE_CHARS:
        return line
    indent = line[:len(line) - len(line.lstrip())]
    return indent + _elide(line.strip(), VIEW_LINE_CHARS - len(indent))


def row_type_legend(elements, suffix=""):
    """"What each row IS", composed from the row types ACTUALLY present.

    A legend is a reading aid, and one that names row types the screen does not
    contain primes the reader to look for something that never appears (#978).
    The screen is composed at render time from the served elements, so the row
    types on it are known — there is no reason to state them from a constant.

    Only TWO row types exist. `J<n>` was retired with the Journey namespace
    (#871, its minting code removed in #933): a Journey is an arc on its
    lesson's row, so it is never a row of its own. `terrain_directions.py`
    records that keeping the dead prefix alive is exactly why a screen could be
    written as though `J` rows might appear — this composes the sentence from
    what mints ids instead, so the two cannot drift again.
    """
    kinds = {("lesson" if e.get("kind") == "lesson" else "decision")
             for e in elements}
    parts = []
    if "lesson" in kinds:
        parts.append("L rows are Lessons (a rule distilled from experience)")
    if "decision" in kinds:
        parts.append("E rows are decisions from the record")
    if not parts:
        return ""
    if len(parts) == 1:
        body = parts[0]
    else:
        body = ", and ".join([parts[0], parts[1]])
    return f"What each row IS: {body}.{suffix}"


def _verdict_phrase(cand):
    """A candidate's writability verdict as one short owner-readable phrase
    (#799). The three-valued verdict SURFACES on every element — matched /
    episodic-unrecorded / no-episode are the ratified verdict names, spoken as
    themselves — and it is surfacing only: an unmatched element stays
    selectable, and the phrase says what selecting one does instead of hiding
    it. `cannot-determine` is the lookup's honest fourth outcome (2026-07-26
    correction), never rendered as "none"."""
    u = cand.get("usability") or {}
    verdict = u.get("verdict")
    if not verdict or cand.get("kind") != "element":
        return ""
    if verdict == "matched":
        checked = [_short_path(p) for p in (u.get("checked") or [])]
        where = f" — evidence at {', '.join(checked[:2])}" if checked else ""
        return f"matched{where}"
    if verdict == "episodic-unrecorded":
        return ("episodic-unrecorded — selectable; picking it records the "
                "gap, never blocks the draft")
    if verdict == "no-episode":
        return "no-episode — offerable as your own framing, stated as such"
    # The lookup's honest fourth outcome, said in the owner's register (#842;
    # the fix belongs in the derivation, #637): the lookup did not look, so
    # neither presence nor absence is asserted.
    return ("whether this can be evidenced was not checked — "
            "still selectable")


def _short_path(path):
    """A checked pointer, rendered short enough for a trailing annotation:
    the last two path segments (the full path stays in `map.json`)."""
    parts = [p for p in str(path).replace("\\", "/").split("/") if p]
    return "/".join(parts[-2:]) if parts else str(path)


def _element_coverage_line(map_data):
    """What the element projection does and does NOT cover, stated on the
    surface. A bounded projection read as the whole record is the specific harm
    CAP-4's element bound guards against, so the bound is never silent."""
    cov = map_data.get("coverage", {}) or {}
    read = cov.get("element_topics_read") or []
    skipped = cov.get("element_topics_skipped") or []
    if not read and not skipped:
        return ("The policy source served no decision topics, so no "
                "decisions were projected.")
    line = f"From: {', '.join(read) if read else 'no topic'}."
    if skipped:
        line += (f" NOT covered: {', '.join(skipped)} — past the seam's read "
                 f"bound, so these are absent, not empty.")
    return line


def _gloss_disclosure_line(map_data):
    """Whether the plain-language renderings the element slots quote were
    actually served — stated on the surface (#799). A terrain whose lesson
    lines fell back to identification must say why, or the fallback reads as
    the rendering."""
    gloss = map_data.get("gloss", {}) or {}
    if gloss.get("served"):
        return (f"Renderings served: {gloss.get('lesson_renderings', 0)} "
                f"lesson(s), {gloss.get('journey_renderings', 0)} "
                f"journey arc(s).")
    # The reason used to be deferred to the maintenance section; Story 20.5
    # (#802) deleted that section, so the pointer would dangle. The fact and
    # its reason now travel together on the one line — which is what CAP-4's
    # disclosure-is-a-LINE rule asks for anyway: name the denominator, do not
    # expand it into a section.
    #
    # The boilerplate is kept SHORT on purpose: the reason is the actionable
    # half, and `_clip_line` bounds the whole line at VIEW_LINE_CHARS — so
    # verbose framing here is paid for by truncating the remedy mid-word. The
    # check asserts the composed line fits without clipping.
    reason = gloss.get("reason") or "not enumerated"
    return (f"Renderings not served — lesson lines carry names, not "
            f"renderings: {reason}")


def _terrain_size_line(topics, strands):
    """How big this terrain is, in one unambiguous line (#645).

    `Subtopics: 25 across 4 topic(s)` read as a FRACTION — "four topics out of
    twenty-five" — to anyone who did not already know that topics contained
    subtopics, and it was the first line of the artifact, so the map failed the
    owner-readable bar before the owner reached anything selectable. Leading
    with the containing unit fixed that.

    Subtopics are gone (Story 20.7, #809), so the line now carries the two
    counts that remain: strands, and the topics they came from. The count is a
    screen affordance for choosing where to look — never a gate, and never the
    content of a direction line (CAP-3 counts-demote).
    """
    def plural(n, word):
        return f"{n} {word}" if n == 1 else f"{n} {word}s"

    return (f"{plural(strands, 'Strand')} — each individually selectable — "
            f"from {plural(topics, 'topic')}")


def _journey_disclosure_line(map_data, terse=False):
    """The Journey shortfall, named on the screen (Story 20.10, #812).

    `terse` selects a SHORTER AUTHORED wording of the same disclosure, for
    callers composing a budgeted payload field beside other disclosures
    (#832: give by authorship, never by truncation). It never withdraws the
    disclosure — only the elaboration of why the absence is three-valued.

    Journeys are article material equally with Lessons, but their shard tags
    are shadowed by same-named lesson shards upstream, so a run may be unable
    to address them at all. DETECTION-BASED, never a flag someone must flip:
    the line keys off what this pin actually served —

      * journey renderings served  -> None (no gap; silence by detection, so
        the disclosure retires itself the moment the upstream fix lands);
      * gloss served, zero journey renderings -> the shortfall named as
        CANNOT-DETERMINE — an honest three-valued absence: from here, "no
        journeys exist" and "journeys are shadowed" are indistinguishable,
        so the line says absent-from-this-listing, never judged-empty;
      * gloss not served at all -> None (the existing gloss disclosure line
        already names that larger gap; two lines for one outage would be
        the volume-not-legibility defect CAP-4 retired).
    """
    gloss = map_data.get("gloss", {}) or {}
    if not gloss.get("served") or gloss.get("journey_renderings", 0) > 0:
        return None
    requested = gloss.get("journeys_requested") or []
    misses = gloss.get("journey_misses") or {}
    if not requested:
        # NOT REQUESTED. Never reported as not served: the two are facts about
        # different parties, and the old line said the second while meaning the
        # first (Story 20.30, #871).
        if terse:
            return ("No journey shard was requested at this pin — no lesson "
                    "on the served index names one.")
        return ("No journey shard was requested at this pin: no lesson on the "
                "served index names one, so no arc was asked for. This is a "
                "statement about what this run asked, NOT about what the hub "
                "serves — an unasked corpus is never reported as an unserved "
                "one.")
    named = ", ".join(sorted(misses)) if misses else ", ".join(requested)
    if terse:
        return (f"Requested {len(requested)} journey shard(s); none arrived "
                f"({named}).")
    return (f"Requested {len(requested)} journey shard(s) and none carried a "
            f"rendering ({named}). A requested shard that does not arrive is "
            "an abnormal condition to fix, not a tolerated gap — it is a "
            "different fact from a shard nobody asked for.")


def _journey_coverage_line(elements):
    """The coverage denominator for one screen's Strand rows (#933/#934).

    LOAD-BEARING, not decoration: absence-marking is correct only while
    coverage stays high, so the denominator is what makes the next inversion
    visible on the screen rather than discovered late. A screen that renders
    the marker without this line is incomplete.

    Counted over the Lessons on THIS screen — a denominator borrowed from the
    corpus would describe a set the reader is not looking at.

    DE-DUPLICATED BY SLUG, and that is not a detail: sections are a COVER
    counted in placements, so a Strand carrying four co-tags appears on four
    section lists. Counting placements here would report "103 of 107 Strands"
    for a member holding 51 — a figure that is arithmetically true of
    placements and false of the noun it names. A count owes its enumeration at
    the point of measurement, so this one enumerates Strands.
    """
    by_slug = {}
    for e in elements:
        if e.get("kind") == "lesson":
            by_slug.setdefault(e.get("slug") or id(e), e)
    lessons = list(by_slug.values())
    if not lessons:
        return None
    n = sum(1 for e in lessons if e.get("journey_recorded"))
    m = len(lessons)
    line = (f"{n} of {m} Strand{'' if m == 1 else 's'} carry journey "
            f"material (how the position changed)")
    if n == m:
        return line + " — every row on this screen has it."
    return line + f" — the {m - n} without it are marked `no-journey`."


def _fit_with_path(prefixes, path, budget):
    """Prefix then `path`, inside `budget` — shortening the PREFIX, never the
    path. A clipped path is an unopenable View, which would make the whole
    >budget branch useless. The prefix gives by AUTHORSHIP (#832): `prefixes`
    is a longest-first list of authored wordings and the first that fits is
    used — never a mid-word slice wearing a period. If even the tersest form
    cannot fit beside the path, the full form is returned over budget and the
    validator blocks presentation naming the field (clause (e)) — a named
    failure, not garbled boilerplate on the owner's screen."""
    tail = f" Open the View: {path}"
    room = budget - len(tail)
    cands = [prefixes] if isinstance(prefixes, str) else list(prefixes)
    cands = [" ".join(str(p).split()) for p in cands]
    for p in cands:
        if len(p) <= room:
            return p + tail
    return cands[0] + tail


def _fit_parts(parts, budget):
    """Join authored sentence-parts inside `budget` by CHOOSING SHORTER
    AUTHORED WORDINGS, never by cutting (#832).

    `parts` is a list of parts, each a longest-first list of authored variants
    of the same content. Degradation is deterministic and rightmost-last: the
    field steps the longest-saving trailing part down first, so the leading
    orientation line keeps its full wording as long as anything can. If even
    the tersest combination is over budget, the tersest is returned and the
    validator blocks presentation naming the field — a named failure, never a
    disclosure silently dropped."""
    levels = [0] * len(parts)

    def render(levels):
        return " ".join(p[min(i, len(p) - 1)] for p, i in zip(parts, levels))

    for idx in range(len(parts) - 1, -1, -1):
        if len(render(levels)) <= budget:
            break
        levels[idx] = len(parts[idx]) - 1
    return render(levels)


def _substituted_paths(map_data):
    """The served paths this run got INSTEAD of what it asked for."""
    subs = (map_data.get("coverage", {}) or {}).get("substitutions") or []
    return {str(x.get("served")) for x in subs if x.get("served")}


def _substitution_disclosure_line(map_data, terse=False):
    """A served path that differs from the requested one, announced.

    An abnormal condition, named at the point of substitution (CAP-4 as
    amended 2026-07-29, #873). Nothing is missing in this failure — the wrong
    thing arrives and reads as the right one — so no other check fires and no
    absence is felt. Silence here is what let archived decisions display as
    the live record.
    """
    subs = (map_data.get("coverage", {}) or {}).get("substitutions") or []
    if not subs:
        return None
    pairs = "; ".join(f"asked for {x.get('requested')}, got {x.get('served')}"
                      for x in subs)
    if terse:
        return f"SUBSTITUTED: {pairs}. Material below is marked."
    return (f"ABNORMAL — a served path differs from the one requested "
            f"({pairs}). Material from it is marked below and is NOT what was "
            "asked for; this is a condition to fix, not a gap to tolerate.")


def _pin_display(map_data, in_conversation=True):
    """The pin as the owner sees it: the composite, with both halves named.

    A single displayed sha taught its reader the wrong thing — it was read as
    a statement about hub freshness, which it never was, and sent one triage
    after a stale hub pin that did not exist (#872). So each half is LABELLED
    with the source it names.

    `in_conversation=False` is the artifact form (the View): the composite and
    the destination half only. A real hub commit sha is a publication-boundary
    value, so it is spoken, never written into a file this tool emits.
    """
    cov = map_data.get("coverage", {}) or {}
    pin = cov.get("pin")
    dest = cov.get("destination_pin")
    hub = cov.get("hub_pin")
    if not dest and not hub:
        return str(pin)
    parts = [f"destination {dest or 'unpinned'}"]
    if in_conversation:
        parts.append(f"hub {hub[:7] if hub else 'unknown'}")
    else:
        parts.append("hub pin shown in conversation only")
    return f"{pin} — " + ", ".join(parts)
