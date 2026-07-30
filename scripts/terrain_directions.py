#!/usr/bin/env python3
"""terrain_directions.py — the terrain surface's CANDIDATE-DIRECTIONS layer
(Story 20.56, #938; SPEC-writing-assistant, the scripts-family clauses of the
2026-07-29 and 2026-07-30 amendments).

A LEAF LAYER, extracted rather than designed — the second seam drawn in
`topic-map-directions.py` and drawn by the same rule as the first
(`terrain_text.py`, Story 20.58). The breakdown taken for this story over 47
top-level definitions and 2,096 lines shows NO dominant class: selection/brief
19.0%, the screen-2 member surface 15.9%, this layer 11.0%, view composition
11.4%, grouping substrates 8.2%, header and constants 7.3%, screen-1 axis 7.0%,
the full report 6.3%, payload 5.9%, plumbing 5.7%. Under no dominance the seam
goes where COUPLING IS LOWEST, not where the semantics are richest, and this
cluster is the only candidate mechanically verified as a LEAF: zero references
out to any other definition in the parent, and its one module constant
(`INTERNAL_VOCAB`) is used nowhere else, so it travels with the code that reads
it — exactly as `BUDGETS` travelled with `_fit`.

What lives here is how the map proposes DIRECTIONS — subjects the owner might
cover — and how those proposals are read for the tool's own vocabulary:

  * `_elements` — every element with its stable id, the substrate the
    proposals are derived from;
  * `_element_direction` / `candidates` / `_direction_lines` — the proposal
    wording itself, quoting the served rendering and never inventing one;
  * `_is_substance_led`, `INTERNAL_VOCAB` and `lint_owner_lines` — the
    render-time report on internal vocabulary reaching the owner's reading
    path, which reports and never rewrites.

A candidate names WHAT to cover, never how the piece is told — the
single-proposer invariant this module inherits and does not restate.

This is a MOVE, not a rewrite: every definition below is the one that stood in
`topic-map-directions.py`, unchanged, and the composed output is byte-identical
for the same inputs.

Stdlib-only, and imported only. It has no CLI: nothing here is a command.
"""

import os
import sys

# The text primitives this layer composes with — the leaf below it (Story
# 20.58, #942). Imported by name so every call site reads as it did before.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from terrain_text import (  # noqa: E402
    VIEW_LINE_CHARS,
    _elide,
    _verdict_phrase,
)


def _elements(map_data):
    """Every element in the map, each carrying its STABLE ID (Story 18.80,
    #641).

    `E<topic>.<n>` — a namespace of its own, so an indexed selection is never
    ambiguous against the subtopic `T<topic>.<subtopic>` scheme. Topics are
    numbered from the sorted set of topics the elements actually came from, and
    `<n>` follows the assembler's order, which is recency-ranked and
    deterministic within a pin (Story 18.79). Computed here per invocation and
    stored nowhere, exactly as the subtopic IDs are.

    Since the stance-3 pivot (2026-07-27, #799) the elements are the PRIMARY
    selection units. They carry TWO namespaces, not three (Story 20.51, #933):
    `L<n>` for hub Lessons, numbered in the assembler's slug-sorted order and
    deterministic within a pin, and `E<topic>.<n>` for the decision projection.
    `J<n>` was retired with independent Journey selection (#871) and its
    minting code is now gone too — an arc is displayed on its lesson's row and
    the lesson is what the owner selects.
    """
    rows, seen = [], {}
    # `J<n>` is GONE (Story 20.51, #933). The namespace was retired in spec
    # text on 2026-07-28 (#871) and the code that minted it stayed — a
    # `journey` counter and a `J` prefix reachable only on a kind the
    # record-authoritative path never emits. Dead code implementing a retired
    # contract is not inert: it is why a screen could be written as though `J`
    # rows might appear, and then assert their absence as a finding. A
    # Journey's presence is now carried by its lesson's row, not by an id.
    counters = {"lesson": 0}
    hub = [e for e in map_data.get("elements", [])
           if e.get("kind") not in counters]
    topics = sorted({e.get("topic", "") for e in hub})
    index = {name: i for i, name in enumerate(topics, start=1)}
    for el in map_data.get("elements", []):
        kind = el.get("kind")
        if kind in counters:
            counters[kind] += 1
            rows.append(dict(el, id=f"L{counters[kind]}"))
            continue
        topic = el.get("topic", "")
        seen[topic] = seen.get(topic, 0) + 1
        rows.append(dict(el, id=f"E{index[topic]}.{seen[topic]}"))
    return rows


def _element_direction(el):
    """An element as a coverage direction — the wording that becomes the brief
    if the owner adopts it, so it names the material in the owner's terms and
    carries no internal marker (#637's rule, unchanged for the new kind). The
    summary is carried in FULL: clipping is a render-only concern (#651), so
    the string the brief is composed from ends where the source did, never
    mid-word — the View bounds the displayed line itself (`_clip_line`, visible elision)."""
    kind = el.get("kind")
    if kind in ("lesson", "journey"):
        # The slot QUOTES the served `gloss:` / `journey_gloss:` rendering —
        # the plain-register text the hub ratified at its distill gate — never
        # the recall one-liner (#799, the pre-ratified amendment). Where no
        # rendering is served, the slot says so with the reason; nothing is
        # substituted for a ratified rendering.
        noun = "lesson" if kind == "lesson" else "journey"
        gloss = str(el.get("gloss") or "").strip()
        if gloss:
            return f"cover the {noun} — {gloss}"
        reason = str(el.get("gloss_unavailable") or
                     "its rendering was not served").strip()
        name = str(el.get("slug") or el.get("title") or "").strip() or noun
        return (f"cover the {noun} recorded as {name} — its plain-language "
                f"rendering is not being served ({reason})")
    # Decision/reversal rows follow the SAME served-rendering-first rule as
    # lesson rows (Story 20.20, #843): quote a served rendering when one
    # exists, and otherwise DISCLOSE the absence — never substitute the raw
    # recall-register topic line as if it were a rendering. The upstream half
    # (serving renderings for topic decision lines) is the hub's; until it
    # lands, every one of these rows takes the disclosure branch, and when it
    # lands they take the served branch with no change here (detection, not a
    # flag).
    kind = "reversal" if kind == "reversal" else "decision"
    gloss = str(el.get("gloss") or "").strip()
    if gloss:
        return f"cover the {kind} — {gloss}"
    when = str(el.get("date") or "").strip() or "an undated line"
    where = str(el.get("topic") or "").strip()
    named = f"recorded {when}" + (f" in the {where} record" if where else "")
    reason = str(el.get("gloss_unavailable") or
                 "no plain-language rendering of decision records is being "
                 "served yet").strip()
    return (f"cover the {kind} {named} — its plain-language rendering is "
            f"not being served ({reason})")


def candidates(map_data):
    """Machine-proposed candidate DIRECTIONS. Never a narrative shape — what to
    cover, not how to tell it.

    Since the cluster removal (Story 20.7, #809) the STRAND — one Lesson or
    Journey — is the only unit. Subtopic clusters, their ranking and their
    depth estimate are gone; what survives is the strand list plus the
    CROSS-TOPIC COMBINATION move, re-based onto strands rather than deleted
    with the clusters it happened to be built from (re-triage of #809).
    """
    out = []
    strands = _elements(map_data)
    for el in strands:
        out.append({
            "kind": "element",
            "element_kind": el.get("kind"),
            "id": el["id"],
            "slug": el.get("slug"),
            "direction": _element_direction(el),
            "topics": [el.get("topic", "")],
            "subtopics": [],
            "date": el.get("date"),
            "situation": el.get("situation"),
            "depth": None,
            # The claim the slot leads with: the served rendering, only. A
            # decision/reversal strand with no served rendering leads with a
            # disclosure, not a claim (Story 20.20, #843), so its raw topic
            # line never stands in as the substance here — the row is
            # fallback-shaped until the rendering is served.
            "why": el.get("gloss") or (
                el.get("summary") if el.get("kind") in ("lesson", "journey")
                else None),
            "gloss": el.get("gloss"),
            "gloss_unavailable": el.get("gloss_unavailable"),
            # The three-valued writability verdict, VISIBLE on every strand
            # (#799): it surfaces at selection and never filters what appears.
            "usability": el.get("usability"),
            "consumed": bool(el.get("consumed")),
            "evidence_pointers": len(el.get("evidence") or []),
        })

    # CROSS-TOPIC COMBINATIONS — DEFERRED, not derived (Story 20.7, #809;
    # SPEC-terrain corrected 2026-07-27).
    #
    # CAP-3 still promises the move — "at least one cross-topic combination
    # when the evidence supports one" — and the promise stands. What does not
    # exist is evidence that could support one. The rule requires two units
    # that share an evidence SOURCE, and a Strand's only pointer is the
    # surface it was read from: `lesson_item` states it outright, "Its own
    # index line is its evidence pointer". So pairing on shared sources makes
    # every cross-topic pair share `LESSONS.md`. Measured before this code was
    # removed: three unrelated lessons in three distinct topics produced two
    # combinations, both with axis `LESSONS.md`, growing quadratically — the
    # same junk class the cluster removal exists to delete.
    #
    # The blocker is OQ3: lesson bodies are unservable, so the Evidence
    # pointers that would name a shared SUBJECT never reach this consumer.
    # REOPEN when a Strand carries an evidence pointer naming something other
    # than the surface it was read from.
    #
    # Pairing on tags or shard membership instead was offered and DECLINED: a
    # shared tag is not a shared subject (`workflow` alone has 53 members),
    # and CAP-3's own rule is that "a combination with nothing shared is a
    # hunch, and a hunch is the owner's to voice at the free-form entry, not
    # the machine's to propose".
    return out


def _direction_lines(cands):
    """The candidate directions, as pickable one-line rows (#632).

    COMBINATIONS FIRST, then singles in rank order. The large branch derives
    one single per subtopic, so on a 25-subtopic terrain the singles alone fill
    the first screenful and would push the cross-topic combinations — "the move
    the map exists for", and the scarcer of the two — below the fold. Ordering
    them first costs nothing (there are few) and is what keeps the combination
    move visible where the owner actually looks.

    Every row carries its INDEX, because selection is by index against the pin.
    """
    # ELEMENTS FIRST (the stance-3 pivot, 2026-07-27, #799): the typed
    # elements — hub Lessons and Journeys, then decisions/reversals — are the
    # PRIMARY selection units, so they open the list. Cross-topic combinations
    # follow (still ahead of the cluster singles, #632's rationale unchanged
    # within the demoted grouping), and the subtopic singles close it.
    elements = [c for c in cands if c.get("kind") == "element"]
    combos = [c for c in cands if c.get("kind") == "combination"]
    rest = [c for c in cands if c.get("kind") not in ("combination", "element")]
    rest.sort(key=lambda c: 0 if _is_substance_led(c) else 1)
    out = []
    for c in elements + combos + rest:
        # COUNTS DEMOTE (CAP-3, substance-led rendering): a count may trail a
        # line that leads with a claim, but it is never what the line says. A
        # fallback line carries its subject alone — "subject plus counts" is
        # the exact shape the clause forbids, and the counts stay one section
        # down in the subtopic's own block.
        facts = []
        verdict = _verdict_phrase(c)
        if verdict:
            # The writability verdict is VISIBLE on every element row (#799):
            # it surfaces, it never filters, and it may not be clipped away —
            # the claim gives way to it below, never the other way round.
            facts.append(verdict)
        if _is_substance_led(c):
            # Declared, not checked (#842): this counts the source references
            # the material declares; whether they resolve is the verdict's to
            # say, so the two never share one phrase.
            n = c.get("evidence_pointers", 0)
            facts.append(f"{n} source reference{'' if n == 1 else 's'} "
                         "declared")
        if c.get("consumed"):
            facts.append("already consumed — still selectable")
        trailer = f" ({', '.join(facts)})" if facts else ""
        head = f"- **{c['id']}** — "
        room = VIEW_LINE_CHARS - len(head) - len(trailer)
        direction = c["direction"]
        if len(direction) > room > 0:
            direction = _elide(direction, room)
        out.append(f"{head}{direction}{trailer}")
    return out or ["- none: this map proposes no directions"]


def _is_substance_led(cand):
    """Does this candidate's wording carry the material's own claim?

    True for an element (its summary IS the claim) and for a subtopic whose
    material yielded one; False where no claim was found and the
    wording fell back to coverage. Combinations name an axis derived from
    shared evidence and are ordered first regardless, so they never reach here.
    """
    if cand.get("kind") == "element":
        return bool(str(cand.get("why") or "").strip())
    return bool(cand.get("claim"))


# The map's OWN internal lexicon, enumerated (Story 18.82, #646). CAP-3's
# owner-readable clause is only lintable because this list is finite: cluster
# and track states, the depth ladder's enum keys, the density counter names,
# and the source-family ids. Every one of them is a legitimate value in
# `map.json` — the defect is presenting it on the surface the owner reads.
#
# A term added to the assembler and not registered here would silently stop
# being gated, which is why `check-topic-map-screen.sh` derives the depth keys
# and family names from the map itself and fails on a term this list misses.
INTERNAL_VOCAB = (
    "(unclustered)", "(untracked)", "(unnamed)",
    "seed-only", "short-note", "full-article", "article-series",
    "hub-lessons", "host-sources", "articles-items",
    "unclustered", "subtopic:", "cluster:", "frontmatter",
    " ptr,", " ptr)", "unconsumed", "live item", "density",
    # The 2026-07-27 owner-flagged spellings (#842): the verdict-fallback
    # enum and the pointer-count trailer. Registered so a regression FAILS
    # the render-boundary check instead of passing as unlisted.
    "evidence lookup: cannot-determine", " evidence pointer",
    # Retired vocabulary is NOT banned here — see check-retired-vocabulary.sh.
    # This lint runs over composed lines that QUOTE THE MATERIAL'S OWN WORDS
    # (CAP-3 substance-led rendering), so it cannot tell the tool's vocabulary
    # from the owner's content on the same line. Banning a common word here
    # fires on content: "seed" flagged a fixture subtopic named "seed-heavy".
    # The retired-vocabulary rule belongs at the layer where the TOOL's words
    # are written, which is the source text.
)


def lint_owner_lines(lines):
    """Internal vocabulary found on the owner's reading path — the render-time
    check CAP-3's owner-readable clause implies (Story 18.82, #646).

    Returns `(line, term)` pairs. Reporting, never rewriting: a line the tool
    silently launders would hide the derivation defect that produced it, and
    #637 already established that the fix belongs in the derivation. The caller
    decides what to do with a defect; `compose_view` reports it on stderr so it
    cannot be emitted unnoticed.
    """
    found = []
    for line in lines:
        low = line.lower()
        for term in INTERNAL_VOCAB:
            if term.lower() in low:
                found.append((line.strip(), term))
    return found
