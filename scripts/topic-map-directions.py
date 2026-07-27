#!/usr/bin/env python3
"""topic-map-directions.py — the map's ONE screen and its brief hand-off
(Story 18.63, #591; SPEC-terrain CAP-3).

The map ends in a BRIEF, not in a second proposer. This script reads an
assembled map (`topic-map.py assemble`) and composes exactly two things:

  * `candidates` — machine-proposed candidate DIRECTIONS, each a subject the
    owner might cover, derived from the map's own depth signals. At least one is
    a CROSS-TOPIC COMBINATION when the evidence supports one — the "connect
    these topics along this axis" move that is the reason the map exists;
  * `payload`   — those candidates as ONE owner-facing proposal payload, in the
    shape `validate-proposal-payload.py --surface topic-map` accepts, always
    carrying a FREE-FORM option and a stop option.

THE SIZE SWITCH (Story 18.66, #601; CAP-3 as amended 2026-07-23)
----------------------------------------------------------------
One screen does not scale. At or under the SCREEN BUDGET the flow above is
unchanged, byte for byte. Above it, the terrain is rendered into a **View file**
the owner opens and the screen becomes a short SUMMARY plus that file's path,
with selection by stable index rather than by matching a direction string —
because 20+ directions collapsed into a handful of options hides exactly what
the map exists to show.

The View is a RENDERING of one invocation, at the same status as topic-map.py's
`--emit-debug`: a fixed filename in the run workspace, fully regenerated every
invocation, and **never read back by any code path** (grep-asserted). Deleting
it loses nothing — the map is derived, and the View is recomposed from it.

WHAT THIS SCRIPT DELIBERATELY DOES NOT DO
-----------------------------------------
It never composes narrative shapes. A candidate names WHAT to cover and, for a
combination, the AXIS connecting two subjects — it never proposes how the piece
is told, ordered, or opened. Proposing shapes downstream remains the shipped
single proposer's job (SPEC-article-draft-pipeline CAP-4, Story 18.45's
single-proposer invariant); a map that started suggesting article shapes would
be the second proposer #554/#583 both forbid. `check-topic-map-screen.sh`
grep-asserts the absence.

THE HAND-OFF
------------
The owner's outcome is a BRIEF IN THE OWNER'S WORDS — machine-proposed text the
owner accepts becomes owner-adopted wording — handed to the EXISTING stage-0
`--brief` path (`draft-pipeline.py stage0 <framework> <sources...> --brief ...`,
Story 18.24 / #505). `brief` emits exactly that string from the recorded answer.
No new entry pipeline exists: downstream, a sitting that started at the map is
indistinguishable from one whose brief the owner typed unaided.

Free-form is offered EVERY time, not only on rejection: the owner naming their
own direction or combination axis is a first-class outcome, not a fallback.

INDEXED SELECTION (Story 18.67, #602)
-------------------------------------
From a View, the owner answers `{index: "T3.2", note: "<their angle>", pin:
"<the View's pin>"}`. The composed brief is the subtopic's coverage wording
plus THE NOTE VERBATIM, and it goes into the same stage-0 `--brief` path as any
other brief — no new entry pipeline, and the note reaches the structure
proposer only as brief text.

Indexes are stable WITHIN A PIN, not across repo states, so an index carries
the pin it was read at. A mismatch is REFUSED with the mismatch named rather
than re-resolved: silently reinterpreting `T3.2` against a moved repository
would hand the owner a scope they never chose. Free text still always wins.

Stdlib-only. Subcommands:
  candidates  --map PATH        the candidate directions as JSON
  payload     --map PATH [--view PATH]
                                the one screen, as a proposal payload; --view
                                renders the View when the map is over budget
  view        --map PATH --out PATH
                                the View file alone
  brief       --answer PATH [--map PATH]
                                the owner's chosen direction as the brief string
                                for stage-0 `--brief`

Exit codes: 0 ok · 1 refusal (no usable map / no owner wording) · 2 usage.
"""

import argparse
import json
import re
import sys

REFUSED = 1
USAGE = 2

# How many machine-proposed directions the screen carries AT OR UNDER the
# screen budget. A screen is a screen: the map's job is to make the terrain
# legible, not to enumerate it.
MAX_SINGLE = 3
# MAX_COMBINATION went with the deferred combination move (Story 20.7, #809):
# a cap on a list nothing produces is the kind of residue the removal exists
# to stop. It returns with the move, not before.

# THE SCREEN BUDGET (Story 18.66, #601; SPEC-terrain CAP-3 size switch).
# Past this many subtopics one screen stops showing what the map exists to
# show, and the terrain moves into a View file the owner opens while the
# screen becomes a summary.
#
# DECLARED IN EXACTLY ONE PLACE, deliberately: the number is the issue's
# estimate of a screen, not a measurement, so it must be movable by editing
# this line alone. Nothing else — no skill, no harness, no second script —
# restates it.
SCREEN_BUDGET = 7

# The View's filename. "Fixed path" is the CAP-3 property that makes the View
# safe: fully regenerated every invocation, never read back.
#
# Amended 2026-07-23 (Story 18.72, #611): the caller passes a path the PATH
# RESOLVER owns, in the `output.drafts` destination repository — the repo the
# owner actually works in — not a per-run workspace. A per-run path was never
# "fixed": it moved every invocation, so a View opened during a sitting could
# not be reopened. This script still just writes where it is told; the name
# below is help text and a default basename, never a composed path.
VIEW_FILENAME = "topic-map-view.md"

# The proposal contract's per-field display budgets. Composing past one produces
# a payload the validator blocks and the owner therefore never sees, so the
# composer stays inside them rather than discovering them at presentation time.
BUDGETS = {"where": 240, "why": 200, "effect": 140}


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
    selection units and carry three namespaces, so a selection is never
    ambiguous: `L<n>` for hub Lessons and `J<n>` for Journey renderings (both
    numbered in the assembler's slug-sorted order, deterministic within a
    pin), and `E<topic>.<n>` for the decision/reversal projection, unchanged.
    """
    rows, seen = [], {}
    counters = {"lesson": 0, "journey": 0}
    hub = [e for e in map_data.get("elements", [])
           if e.get("kind") not in counters]
    topics = sorted({e.get("topic", "") for e in hub})
    index = {name: i for i, name in enumerate(topics, start=1)}
    for el in map_data.get("elements", []):
        kind = el.get("kind")
        if kind in counters:
            counters[kind] += 1
            prefix = "L" if kind == "lesson" else "J"
            rows.append(dict(el, id=f"{prefix}{counters[kind]}"))
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
    mid-word — the View bounds the displayed line itself (`_clip_line`)."""
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
    summary = str(el.get("summary") or "").strip()
    kind = "reversal" if kind == "reversal" else "decision"
    if not summary:
        # Never a bare enum on the owner surface: describe what it is instead.
        return f"cover the {kind} recorded at {el.get('date') or 'an undated line'}"
    return f"cover the {kind} — {summary}"


def is_large(map_data):
    """Does this map exceed the screen budget? The ONE predicate the size
    switch turns on (CAP-3 as amended 2026-07-23). Since the pivot (#799) the
    Strands are the only units since the cluster removal (Story 20.7, #809),
    so the budget counts them alone."""
    return len(map_data.get("elements", [])) > SCREEN_BUDGET


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
            # The claim the slot leads with: the served rendering for a
            # lesson/journey strand, the topic-line summary otherwise.
            "why": el.get("gloss") or el.get("summary"),
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


def _clip(text, budget=BUDGETS["effect"]):
    text = " ".join(str(text).split())
    return text if len(text) <= budget else text[:budget - 1].rstrip() + "."




# No View line is longer than this. The View is a human surface, so its lines
# are budgeted the way the screen payload's fields already are — a list renders
# one item per line, clipped, capped, with the remainder disclosed. Asserted in
# `scripts/check-topic-map-screen.sh`, so the 818-line regression cannot recur
# unnoticed.
VIEW_LINE_CHARS = 200


def _clip_line(line):
    """Bound one View line, preserving its indentation and leaving blank lines
    blank. `_clip` collapses whitespace, which would flatten the list indents
    the View's structure is made of, so it is applied to the value only."""
    if len(line) <= VIEW_LINE_CHARS:
        return line
    indent = line[:len(line) - len(line.lstrip())]
    return indent + _clip(line.strip(), VIEW_LINE_CHARS - len(indent))


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
    return "evidence lookup: cannot-determine"


def _short_path(path):
    """A checked pointer, rendered short enough for a trailing annotation:
    the last two path segments (the full path stays in `map.json`)."""
    parts = [p for p in str(path).replace("\\", "/").split("/") if p]
    return "/".join(parts[-2:]) if parts else str(path)


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
            facts.append(f"{c.get('evidence_pointers', 0)} evidence pointer(s)")
        if c.get("consumed"):
            facts.append("already consumed — still selectable")
        trailer = f" ({', '.join(facts)})" if facts else ""
        head = f"- **{c['id']}** — "
        room = VIEW_LINE_CHARS - len(head) - len(trailer)
        direction = c["direction"]
        if len(direction) > room > 0:
            direction = _clip(direction, room)
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


def _element_coverage_line(map_data):
    """What the element projection does and does NOT cover, stated on the
    surface. A bounded projection read as the whole record is the specific harm
    CAP-4's element bound guards against, so the bound is never silent."""
    cov = map_data.get("coverage", {}) or {}
    read = cov.get("element_topics_read") or []
    skipped = cov.get("element_topics_skipped") or []
    if not read and not skipped:
        return ("No hub topic is declared for this repo, so no decisions or "
                "reversals were projected.")
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


def compose_view(map_data, cands):
    """The View: one invocation's terrain, rendered so 20+ directions are
    legible and CAP-2's 'why this depth?' is answerable from the same counts
    the estimate used.

    Leads with the CANDIDATE DIRECTIONS, then the terrain at a glance, then
    per-subtopic detail (#632). The size switch changes where the terrain is
    presented, never whether the map proposes — so `cands` is REQUIRED and is
    the caller's already-derived list. This function never calls `candidates()`
    itself: a second derivation here would be a second proposer, and the
    directions on the View must be the same ones the screen was built from.

    A RENDERING, at the same status as topic-map.py's --emit-debug: fully
    regenerated every invocation and NEVER read back by any code path. Deleting
    it loses nothing — the map is recomputed, and this is recomposed from it.
    """
    pin = map_data.get("coverage", {}).get("pin")
    lines = [
        "# Terrain",
        "",
        "<!-- Regenerated on every terrain invocation. Never read back by any",
        "     code path; deleting this file loses nothing. Do not edit or commit. -->",
        "",
        f"Pin: {pin}",
        _terrain_size_line(len(map_data.get("topics", [])),
                           len(map_data.get("elements", []))),
        "",
        "Answer with an element's index (for example L3) or a subtopic's",
        "index (for example T1.2) and a short note about the angle you want.",
        "Free text always wins. Each element is its own Strand, and its",
        "writability verdict is a disclosure, never a gate: an element whose",
        "evidence is not yet recorded is as pickable as a matched one —",
        "picking it records the gap and the draft still proceeds. Material",
        "you have already written from stays selectable.",
        "",
        "## Candidate directions",
        "",
    ]
    lines += _direction_lines(cands)
    # The element projection's BOUND stays on the surface (CAP-4): the section
    # that used to carry it is gone — elements are directions now (Story 18.81,
    # #647) — but a bounded projection read as the whole record is exactly what
    # the disclosure guards against, so it moves here rather than lapsing.
    lines += ["", _element_coverage_line(map_data)]
    lines += ["", _gloss_disclosure_line(map_data)]
    # THE VIEW ENDS HERE (Story 20.5, #802). What used to follow — "Subtopic
    # clusters", "Maintenance", "Diagnostics" — was ~2,300 of a 2,511-line
    # view serving no function the owner could identify, so the sections AND
    # their emitters are gone: a section deleted at render time is still paid
    # for at assembly time, which was the whole cost.
    #
    # `reading_path` is COLLAPSED DELIBERATELY, not dropped. It existed to
    # mark where the owner-facing surface stopped and upkeep began; with
    # nothing below the boundary, every line is the reading path, so the lint
    # below runs over `lines` itself. Reintroducing a non-owner-facing tail
    # would mean reintroducing the distinction, not just the section.
    #
    # The render-boundary check (Story 18.82, #646) is unchanged in kind: an
    # internal term reaching the owner surface is REPORTED, never laundered.
    # Rewriting the line here would hide the derivation defect that produced
    # it, and the surface would go on looking clean while the adopted brief
    # still carried the term.
    for line, term in lint_owner_lines(lines):
        sys.stderr.write(f"warning: internal vocabulary on the owner surface: "
                         f"{term!r} in {line!r}\n")
    # The budget applies to the composed surface, not to each call site: a
    # field added later is budgeted by construction rather than by remembering.
    # Clipping is the last step, so every list above has already been capped
    # and its remainder disclosed — this bounds a single long VALUE, it never
    # silently drops an item.
    return "\n".join(_clip_line(x) for x in lines).rstrip() + "\n"


def write_view(path, text):
    """Write the View. WRITE-ONLY BY CONTRACT (CAP-3/CAP-1): no code path in
    this script — or any flag it accepts — ever reads it back, so it can never
    become a stored index."""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def _fit_with_path(prefix, path, budget):
    """`prefix` then `path`, inside `budget` — shortening the PREFIX, never the
    path. A clipped path is an unopenable View, which would make the whole
    >budget branch useless; the summary around it is the part that can give."""
    tail = f" Open the View: {path}"
    room = budget - len(tail)
    prefix = " ".join(str(prefix).split())
    if len(prefix) > room:
        prefix = prefix[:max(0, room - 1)].rstrip() + "."
    return prefix + tail


def axis_members(map_data):
    """Screen 1's axis: the SERVED TAG VOCABULARY, derived from the tags the
    elements already carry (Story 20.8, #810; SPEC-terrain as resolved
    2026-07-27).

    Deterministic by construction — no model decides what appears: every tag
    on any Strand is a member, members sort alphabetically, and the count is
    plain arithmetic. The count is a screen affordance for choosing where to
    look (legitimate presentation under the no-selection-authority wording),
    never a gate: every member is offered whatever its size, and a large
    member is served WHOLE downstream — no within-axis cap.

    Strands carrying NO tag (a lesson whose rendering was not served has an
    empty tag list) would be reachable through no member, so their count is
    returned as a DISCLOSURE the screen must carry as a line — the
    named-denominator rule (CAP-4): they are named as outside the axis, never
    hidden, and free-form still reaches them.
    """
    members, untagged = {}, 0
    for el in map_data.get("elements", []) or []:
        tags = [str(t).strip() for t in (el.get("tags") or []) if str(t).strip()]
        if not tags:
            untagged += 1
            continue
        for t in tags:
            members[t] = members.get(t, 0) + 1
    listing = [{"member": name, "strands": n}
               for name, n in sorted(members.items())]
    return {"members": listing, "untagged_strands": untagged}


def compose_axis_payload(map_data):
    """Screen 1 as ONE owner-facing proposal payload (Story 20.8, #810).

    The same contract every other screen honours: machine-proposed selectable
    options, free-form every time, stop last, plain text, validated before
    presentation. The member word is the TAG'S OWN NAME — the UI word "Topic"
    is retired for the axis (upstream ruling, 2026-07-27) and never appears
    in the composed copy.
    """
    axis = axis_members(map_data)
    pin = map_data.get("coverage", {}).get("pin")
    choices = []
    for m in axis["members"]:
        n = m["strands"]
        plural = "s" if n != 1 else ""
        choices.append({
            "label": f"{m['member']} ({n} Strand{plural})",
            "effect": _clip(f"shows all {n} of this tag's Strands, whole — "
                            f"nothing capped, nothing ranked; you pick the "
                            f"material there"),
        })
    choices.append({
        "label": "name your own direction or combination axis",
        "effect": _clip("skips the listing and starts the run with your "
                        "wording as the brief"),
    })
    choices.append({
        "label": "stop here",
        "effect": _clip("nothing is drafted and no brief is recorded; the "
                        "axis is recomputed fresh next time"),
    })
    where = (f"Terrain at {pin}: {len(axis['members'])} tag(s) from the "
             f"served vocabulary, each individually selectable.")
    if axis["untagged_strands"]:
        # The disclosure is a LINE, never a section (CAP-4): strands outside
        # the axis are named, not hidden, and free-form still reaches them.
        where += (f" {axis['untagged_strands']} Strand(s) carry no served "
                  f"tag and sit outside this axis — name one at free-form "
                  f"to reach it.")
    return {"items": [{
        "where": _clip(where, BUDGETS["where"]),
        "why": _clip("Pick where to look first. The count is a signal for "
                     "your judgment, never a gate: every tag is offered "
                     "whatever its size, and its material is shown whole.",
                     BUDGETS["why"]),
        "choices": choices,
    }]}


def cmd_axis(args):
    m = load_map(args.map)
    out = {"kind": "terrain-axis", "axis": axis_members(m),
           "payload": compose_axis_payload(m)}
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def compose_payload(map_data, cands, view_path=None):
    """The ONE screen.

    At or under the screen budget: the terrain, the candidate directions, a
    free-form response, and stopping — the shipped composition, unchanged.

    Above it: a short SUMMARY plus the View file's path, because one screen
    does not scale — 20+ directions collapsed into a handful of options hides
    the terrain the map exists to show. Selection then happens by index from
    the View rather than by matching a proposed direction string.

    Plain text either way — the payload the validator accepts is the payload
    the owner sees.
    """
    if view_path and is_large(map_data):
        return _compose_summary_payload(map_data, view_path)
    topics = map_data.get("topics", [])
    # The terrain line was a histogram of depth ESTIMATES per subtopic. Both
    # are gone (Story 20.7, #809), so it states what the terrain now holds:
    # how many strands, and how many are already written from. A count is a
    # screen affordance for choosing where to look, never a gate.
    strands = map_data.get("elements", []) or []
    terrain = f"{len(strands)} strand(s)"
    consumed = sum(1 for e in strands if e.get("consumed"))

    choices = []
    for c in cands:
        verdict = _verdict_phrase(c)
        effect = (f"starts a normal drafting run with this as your coverage "
                  f"brief; {verdict}" if verdict else
                  f"starts a normal drafting run with this as your coverage "
                  f"brief; {c['evidence_pointers']} evidence pointer(s) "
                  f"behind it")
        choices.append({"label": c["direction"], "effect": _clip(effect)})
    # Free-form is offered EVERY time, not only on rejection.
    choices.append({
        "label": "name your own direction or combination axis",
        "effect": _clip("starts the same run with your wording as the brief; "
                        "nothing above is adopted unless you say so"),
    })
    choices.append({
        "label": "stop here",
        "effect": _clip("nothing is drafted and no brief is recorded; the map is "
                        "recomputed fresh next time"),
    })

    els = map_data.get("elements", [])
    item = {
        "where": _clip(
            f"Terrain at {map_data.get('coverage', {}).get('pin')}: "
            f"{len(els)} element(s) — each its own Strand — and "
            f"{len(topics)} topic(s), {terrain}; "
            f"{consumed} already consumed and still selectable.", BUDGETS["where"]),
        "why": _clip(
            "Every element is its own selectable idea. Verdicts and depth "
            "are a signal for your judgment, never a gate: a gap is "
            "disclosed, recorded, and drafted anyway. Your choice becomes "
            "the brief, in your words.", BUDGETS["why"]),
        "choices": choices,
    }
    return {"items": [item]}


def _compose_summary_payload(map_data, view_path):
    """The >budget screen: a summary and the View's path. Still ONE item, still
    free-form every time, still `stop here` last — the size switch changes what
    the screen SHOWS, never the shape of the contract it is presented under."""
    topics = map_data.get("topics", [])
    strands = map_data.get("elements", []) or []
    terrain = f"{len(strands)} strand(s)"
    consumed = sum(1 for e in strands if e.get("consumed"))

    choices = [
        {"label": "choose a direction by its index from the View",
         "effect": _clip("answer with the index (for example L3 or T1.2) and "
                         "a short note about the angle you want; your note is "
                         "carried into the brief word for word")},
        # Free-form is offered EVERY time, not only on rejection.
        {"label": "name your own direction or combination axis",
         "effect": _clip("starts the same run with your wording as the brief; "
                         "nothing in the View is adopted unless you say so")},
        {"label": "stop here",
         "effect": _clip("nothing is drafted and no brief is recorded; the map "
                         "and the View are regenerated fresh next time")},
    ]
    els = map_data.get("elements", [])
    item = {
        "where": _fit_with_path(
            f"Terrain at {map_data.get('coverage', {}).get('pin')}: "
            f"{len(els)} element(s) — each its own Strand — and "
            f"{len(topics)} topic(s), {terrain}; "
            f"{consumed} already consumed and still selectable. Too many to "
            f"fit on one screen.", view_path, BUDGETS["where"]),
        "why": _clip(
            "Every element is its own selectable idea. Verdicts and depth "
            "are a signal for your judgment, never a gate: a gap is "
            "disclosed, recorded, and drafted anyway. Your choice becomes "
            "the brief, in your words.", BUDGETS["why"]),
        "choices": choices,
    }
    return {"items": [item]}


def _selection_gap(candidate, recording_target):
    """The gap disclosure a non-matched element selection yields (#799).

    Evidence-independence, enforced end to end: the verdict decided nothing
    about APPEARING, and it decides nothing about DRAFTING either. Selecting
    an element whose episode no declared source carries yields this block —
    the disclosure plus the NEEDS-RECORDING tracking artifact's content for
    the target repo (an Issue, or an append under a NEEDS-RECORDING heading
    in the declared journey doc) — and the brief is composed exactly as for a
    matched one. NEVER a refusal: a mechanism that stops drafting here has
    stopped being an assistant (owner ruling, #799).
    """
    if not candidate or candidate.get("kind") != "element":
        return None
    u = candidate.get("usability") or {}
    verdict = u.get("verdict")
    if not verdict or verdict == "matched":
        return None
    target = recording_target or {}
    slug = str(candidate.get("slug") or "").strip()
    gap = {"verdict": verdict, "slug": slug,
           "checked": u.get("checked") or [],
           "drafting": "proceeds — the verdict is a disclosure, never a gate"}
    if verdict == "cannot-determine":
        gap["disclosure"] = (
            "the evidence lookup could not determine whether a declared "
            f"source carries this ({u.get('reason') or 'no join key'}); "
            "an absence is asserted only where it was established, so no "
            "recording task is minted from a lookup that did not look")
        return gap
    if verdict == "no-episode":
        gap["disclosure"] = (
            "no episode is locatable for this element, so the draft offers it "
            "on the owner-attributed framing tier: your framing contribution, "
            "stated as such, never sourced claims")
        gap["tier"] = "owner-attributed framing (Story 17.1)"
    else:
        gap["disclosure"] = (
            "the hub records this element but no declared source in the "
            "target repo carries its episode; the draft proceeds, and the "
            "gap is recorded so the next run can locate evidence")
    gap["needs_recording"] = {
        "slug": slug,
        "target_repo": target.get("repo"),
        "target_file": target.get("file"),
        "heading": "NEEDS-RECORDING",
        "entry": (f"{slug} — selected on the terrain "
                  f"({verdict}); record the episode here so the next "
                  f"run can match it"),
    }
    return gap


def _brief_from_index(answer, cands, map_pin):
    """An INDEXED selection from the View: `{index, note}` (Story 18.67, #602).

    The composed brief is the subtopic's coverage wording PLUS THE OWNER'S NOTE
    VERBATIM — the machine resolves which subtopic `T3.2` meant, the owner
    supplies the angle, and the result is one ordinary brief string for the
    existing stage-0 `--brief` path. There is no new entry pipeline: downstream
    cannot tell this from a brief the owner typed, and the note reaches the
    structure proposer only as brief text.

    An index is meaningless without the map it was read from, so the answer
    must carry the pin the View was rendered at. A mismatch is REFUSED with the
    mismatch named — never silently re-resolved to whatever `T3.2` happens to
    mean at the current pin, which would hand the owner a scope they never
    chose. A missing pin is refused for the same reason: it cannot be proven
    not to be stale.
    """
    index = str(answer.get("index") or "").strip()
    answer_pin = str(answer.get("pin") or "").strip()
    if not answer_pin:
        raise SystemExit(_err(
            f"the recorded answer selects index {index!r} but carries no pin. An "
            "index only means something against the map it was read from, so "
            "the View's pin must be recorded with the selection; without it a "
            "stale selection cannot be told from a current one. Re-run the map "
            "and choose again."))
    if map_pin and answer_pin != map_pin:
        raise SystemExit(_err(
            f"pin mismatch: index {index!r} was chosen against a View rendered "
            f"at {answer_pin}, but this map is at {map_pin}. The repository "
            "moved, so that index may now name a different subtopic — it is "
            "refused rather than re-resolved. Re-run the map and choose from "
            "the fresh View."))
    match = next((c for c in cands if c.get("id") == index), None)
    if match is None:
        raise SystemExit(_err(
            f"index {index!r} names no subtopic in this map. The indexes come "
            "from the View rendered at this pin — re-read it and choose again."))
    note = str(answer.get("note") or "").strip()
    brief = f"{match['direction']} — {note}" if note else match["direction"]
    return {"brief": brief,
            # The coverage wording is machine-proposed and the owner adopted it
            # by choosing its index; the note is theirs outright. Both are the
            # owner's words under the shipped rule — never a tool-invented scope.
            "provenance": "owner-authored", "origin": "adopted-index",
            "index": index, "pin": answer_pin, "note": note,
            "candidate": match}


def brief_from_answer(answer, cands, map_pin=None):
    """The owner's outcome as the brief string for stage-0 `--brief`.

    Free text ALWAYS wins: machine-proposed wording becomes the brief only when
    the owner adopted it by selecting it — by matching a direction string or by
    naming its index — and then it is owner-adopted wording, not a
    tool-invented scope."""
    free = str(answer.get("free_text") or "").strip()
    if free:
        return {"brief": free, "provenance": "owner-authored", "origin": "free-form"}
    selection = str(answer.get("selection") or "").strip()
    if selection in ("stop here", "stop"):
        raise SystemExit(_err(
            "the owner chose to stop at the map: no brief exists and no run "
            "follows. Stopping is a first-class outcome, not a failure."))
    if str(answer.get("index") or "").strip():
        return _brief_from_index(answer, cands, map_pin)
    for c in cands:
        if selection == c["direction"]:
            return {"brief": c["direction"], "provenance": "owner-authored",
                    "origin": "adopted-candidate", "candidate": c}
    raise SystemExit(_err(
        f"the recorded answer selects {selection!r}, which is neither a proposed "
        "direction nor free-form wording. The brief is the owner's words — it is "
        "never inferred here."))


def cmd_candidates(args):
    print(json.dumps({"stage": "topic-map-directions",
                      "candidates": candidates(load_map(args.map))},
                     indent=2, ensure_ascii=False))
    return 0


def cmd_payload(args):
    data = load_map(args.map)
    view_path = getattr(args, "view", None)
    large = is_large(data)
    # Derived ONCE and shared: the screen and the View must offer the same
    # directions, and deriving twice is how they would silently drift apart.
    cands = candidates(data)
    if view_path and large:
        write_view(view_path, compose_view(data, cands))
    print(json.dumps(compose_payload(data, cands, view_path),
                     indent=2, ensure_ascii=False))
    if large and not view_path:
        sys.stderr.write(
            f"warning: this map has more than {SCREEN_BUDGET} subtopics, which "
            "is past the screen budget — pass --view PATH so the terrain is "
            "rendered into a View file the owner can open. Without it the "
            "screen carries the capped candidate list, which hides most of the "
            "terrain.\n")
    return 0


def cmd_view(args):
    """Render the View alone — the same rendering `payload --view` writes, for
    a caller that wants it without composing a screen."""
    data = load_map(args.map)
    write_view(args.out, compose_view(data, candidates(data)))
    print(args.out)
    return 0


def cmd_brief(args):
    try:
        answer = json.load(open(args.answer, encoding="utf-8")) if args.answer != "-" \
            else json.load(sys.stdin)
    except (OSError, ValueError) as exc:
        return _err(f"unreadable answer at {args.answer}: {exc}")
    if answer.get("kind") == "answer":            # a presented-payloads.jsonl row
        answer = answer.get("answer") or {}
    map_data = load_map(args.map) if args.map else None
    cands = candidates(map_data) if map_data else []
    map_pin = (map_data or {}).get("coverage", {}).get("pin")
    out = brief_from_answer(answer, cands, map_pin)
    # Evidence-independence at the hand-off (#799): a selected element's
    # writability gap is DISCLOSED beside the brief — with the tracking
    # artifact's content for the target repo — and the run proceeds. There is
    # no refusal path here on evidence.
    gap = _selection_gap(out.get("candidate"),
                         (map_data or {}).get("recording_target"))
    if gap:
        out["gap"] = gap
    out["stage"] = "topic-map-brief"
    out["next"] = ("draft-pipeline.py stage0 <framework> <sources...> --brief "
                   "<this brief> — the existing stage-0 path, unchanged")
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    ax = sub.add_parser("axis", help="Screen 1: the served-tag axis listing "
                        "with per-member Strand counts, as JSON + payload")
    ax.add_argument("--map", required=True)
    c = sub.add_parser("candidates", help="candidate directions as JSON")
    c.add_argument("--map", required=True, help="assembled map JSON, or - for stdin")
    pa = sub.add_parser("payload", help="the one screen, as a proposal payload")
    pa.add_argument("--map", required=True, help="assembled map JSON, or - for stdin")
    pa.add_argument("--view", metavar="PATH",
                    help=f"where to render the View when the map exceeds the "
                         f"screen budget ({SCREEN_BUDGET} subtopics). Pass the "
                         f"run workspace's {VIEW_FILENAME}. A map at or under "
                         f"the budget writes nothing and the screen is "
                         f"unchanged. The View is WRITE-ONLY: nothing reads it "
                         f"back.")
    v = sub.add_parser("view", help="render the View file alone")
    v.add_argument("--map", required=True, help="assembled map JSON, or - for stdin")
    v.add_argument("--out", required=True, metavar="PATH",
                   help=f"where to write it (the run workspace's {VIEW_FILENAME})")
    b = sub.add_parser("brief", help="the owner's outcome as the stage-0 brief")
    b.add_argument("--answer", required=True,
                   help="the recorded answer JSON, or - for stdin")
    b.add_argument("--map", help="the same map, so an adopted candidate resolves")
    args = p.parse_args(argv)
    return {"candidates": cmd_candidates, "payload": cmd_payload,
            "view": cmd_view, "brief": cmd_brief,
            "axis": cmd_axis}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
