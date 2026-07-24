#!/usr/bin/env python3
"""topic-map-directions.py — the map's ONE screen and its brief hand-off
(Story 18.63, #591; SPEC-topic-map CAP-3).

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
MAX_COMBINATION = 2

# THE SCREEN BUDGET (Story 18.66, #601; SPEC-topic-map CAP-3 size switch).
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


def _subtopics(map_data):
    """Every subtopic in the map, each carrying its topic and its STABLE ID —
    flat, in a deterministic order, with nothing filtered out. Consumed
    subtopics are included: they are MARKED, never hidden, and the owner may
    still pick one.

    The ID is `T<topic>.<subtopic>`, both 1-based, from a deterministic
    ordering: topics in the map's own sorted order, subtopics by the shipped
    `_rank`. The same repo state at the same pin therefore yields the same IDs,
    which is what lets a large View be answered by index. It is computed here
    per invocation and stored nowhere — a recorded index vocabulary is exactly
    the stored state CAP-1 exists to prevent.
    """
    rows = []
    for t_i, topic in enumerate(map_data.get("topics", []), start=1):
        ranked = sorted(topic.get("subtopics", []), key=_rank)
        order = {s["subtopic"]: i for i, s in enumerate(ranked, start=1)}
        for sub in topic.get("subtopics", []):
            rows.append(dict(sub, topic=topic["topic"],
                             id=f"T{t_i}.{order[sub['subtopic']]}"))
    return rows


def _elements(map_data):
    """Every element in the map, each carrying its STABLE ID (Story 18.80,
    #641).

    `E<topic>.<n>` — a namespace of its own, so an indexed selection is never
    ambiguous against the subtopic `T<topic>.<subtopic>` scheme. Topics are
    numbered from the sorted set of topics the elements actually came from, and
    `<n>` follows the assembler's order, which is recency-ranked and
    deterministic within a pin (Story 18.79). Computed here per invocation and
    stored nowhere, exactly as the subtopic IDs are.
    """
    rows, seen = [], {}
    topics = sorted({e.get("topic", "") for e in map_data.get("elements", [])})
    index = {name: i for i, name in enumerate(topics, start=1)}
    for el in map_data.get("elements", []):
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
    summary = str(el.get("summary") or "").strip()
    kind = "reversal" if el.get("kind") == "reversal" else "decision"
    if not summary:
        # Never a bare enum on the owner surface: describe what it is instead.
        return f"cover the {kind} recorded at {el.get('date') or 'an undated line'}"
    return f"cover the {kind} — {summary}"


def _rank(sub):
    """Richest first, ties broken by name so a run is reproducible."""
    d = sub.get("density", {})
    return (-d.get("evidence_pointers", 0), -d.get("unconsumed_lessons", 0),
            -d.get("live_items", 0), sub["subtopic"])


def _shared_pointer_subjects(a, b):
    """What two subtopics visibly have in common: evidence pointers naming the
    same source. This is the only evidence a combination is ever proposed on —
    a combination with nothing shared is a hunch, and a hunch is the owner's to
    voice at the free-form entry, not the machine's to propose."""
    def subjects(sub):
        out = set()
        for p in sub.get("density", {}).get("pointers", []):
            head = str(p).split("#")[0].split(":")[0].strip()
            stem = head.rsplit("/", 1)[-1]
            if stem:
                out.add(stem)
        return out
    return sorted(subjects(a) & subjects(b))


def is_large(map_data):
    """Does this map exceed the screen budget? The ONE predicate the size
    switch turns on (CAP-3 as amended 2026-07-23)."""
    return len(_subtopics(map_data)) > SCREEN_BUDGET


def candidates(map_data):
    """Machine-proposed candidate DIRECTIONS, derived from the map's own depth
    signals. Never a narrative shape — what to cover, not how to tell it.

    At or under the screen budget the fixed caps apply, unchanged. ABOVE it the
    caps stop being fixed constants: the terrain goes to a View file, so every
    subtopic is a candidate and combinations are bounded by the terrain itself
    (one per distinct axis) rather than by a number chosen for a screen.
    """
    subs = sorted(_subtopics(map_data), key=_rank)
    large = len(subs) > SCREEN_BUDGET
    out = []
    for sub in (subs if large else subs[:MAX_SINGLE]):
        d = sub.get("density", {})
        depth = sub.get("depth", {})
        claim = _subtopic_claim(sub)
        out.append({
            "kind": "single",
            "id": sub["id"],
            "direction": _coverage_direction(sub),
            "claim": claim,
            "topics": [sub["topic"]],
            "subtopics": [sub["subtopic"]],
            "depth": depth.get("level"),
            "why": depth.get("why"),
            "consumed": sub.get("consumed", False),
            "evidence_pointers": d.get("evidence_pointers", 0),
        })

    # Cross-topic combinations: the move the map exists for. Only pairs from
    # DIFFERENT topics that share evidence qualify, so the axis is named from
    # something real rather than asserted.
    combos = []
    for i, a in enumerate(subs):
        for b in subs[i + 1:]:
            if a["topic"] == b["topic"]:
                continue
            shared = _shared_pointer_subjects(a, b)
            if not shared:
                continue
            combos.append({
                "kind": "combination",
                "id": f"{a['id']}+{b['id']}",
                "direction": (f"connect {_coverage_subject(a)} and "
                              f"{_coverage_subject(b)} along {shared[0]}"),
                "topics": sorted({a["topic"], b["topic"]}),
                "subtopics": [a["subtopic"], b["subtopic"]],
                "axis": shared[0],
                "shared_evidence": shared,
                "why": (f"{a['subtopic']} ({a['topic']}) and {b['subtopic']} "
                        f"({b['topic']}) both cite {', '.join(shared)}"),
                "evidence_pointers": (a.get("density", {}).get("evidence_pointers", 0)
                                      + b.get("density", {}).get("evidence_pointers", 0)),
            })
    # Elements (Story 18.80): the second projection reaches the SAME candidate
    # list, so index selection, the screen and the View all resolve against one
    # derivation. Unbounded like the singles above — the terrain bounds them,
    # not a screen constant, and the seam already bounded which topics they
    # came from.
    for el in _elements(map_data):
        out.append({
            "kind": "element",
            "element_kind": el.get("kind"),
            "id": el["id"],
            "direction": _element_direction(el),
            "topics": [el.get("topic", "")],
            "subtopics": [],
            "date": el.get("date"),
            "situation": el.get("situation"),
            "depth": None,
            "why": el.get("summary"),
            "consumed": bool(el.get("consumed")),
            "evidence_pointers": len(el.get("evidence") or []),
        })

    combos.sort(key=lambda c: (-len(c["shared_evidence"]), -c["evidence_pointers"],
                               c["direction"]))
    if large:
        # Bounded by the terrain, not by a screen constant: the strongest
        # combination per distinct axis. Every axis the evidence supports is
        # offered exactly once, so the View lists connections without listing
        # the same one N times.
        seen, kept = set(), []
        for c in combos:
            if c["axis"] in seen:
                continue
            seen.add(c["axis"])
            kept.append(c)
        out.extend(kept)
    else:
        out.extend(combos[:MAX_COMBINATION])
    return out


def _clip(text, budget=BUDGETS["effect"]):
    text = " ".join(str(text).split())
    return text if len(text) <= budget else text[:budget - 1].rstrip() + "."


def _lesson_seed_names(sub):
    """The lesson seeds under a subtopic, by name. They are what makes a
    widened corpus legible: 'why this depth?' is answered partly by which hub
    Lessons sit behind the subtopic."""
    return sorted({i.get("title") or i.get("slug")
                   for i in sub.get("items", [])
                   if i.get("family") == "hub-lessons"} - {None, ""})


UNNAMED = "(unnamed)"

# The placeholder states the ASSEMBLER records when nothing named a thing
# (`scripts/topic-map.py:825`, `:866`). They are legitimate map values — the
# spec is deliberate that an undeclared cluster falls to the derived path
# family and that the fallback is NAMED, never silently smoothed. What is a
# defect is presenting the bare enum in a headline position, where a machine
# state reads as if it were the owner's own vocabulary. The View renders the
# same state as prose that says what to do about it; `map.json` keeps the enum.
PLACEHOLDER_PROSE = {
    "(unclustered)": ("not yet clustered — declare `subtopic:` in the item's "
                      "backlog frontmatter to name it"),
    "(untracked)": ("not yet mapped to a topic — declare the track's topic in "
                    "the articles repo to name it"),
    UNNAMED: ("nothing named this yet — declare `subtopic:` in the item's "
              "backlog frontmatter to name it"),
}


def as_prose(name):
    """A placeholder state, rendered for a person. Any other name is its own."""
    return PLACEHOLDER_PROSE.get(str(name).strip(), name)


def _coverage_subject(sub):
    """What a direction says it covers — OWNER-READABLE BY CONSTRUCTION (#637).

    A candidate's wording becomes the owner's brief the moment they adopt it
    (`_brief_from_index`), so an internal placeholder must never reach it: a
    brief reading `cover (unclustered)` hands the tool's own enum back to the
    owner as their words. Fixing that only where the View prints would leave
    the adopted brief carrying the enum — so the constraint lives here, in the
    derivation both branches share.

    A declared or successfully derived name is returned untouched: the articles
    repo owns subject NAMES (OQ1), and this only governs the wording composed
    when the repo named nothing. In that case the subject DESCRIBES the
    cluster's contents rather than inventing a name for it.
    """
    name = _subtopic_name(sub)
    if str(name).strip() not in PLACEHOLDER_PROSE:
        return name
    count = sub.get("density", {}).get("items") or len(sub.get("items", []))
    topic = str(sub.get("topic") or "").strip()
    where = f" under {topic}" if topic and topic not in PLACEHOLDER_PROSE else ""
    return f"the not-yet-clustered items{where} ({count} item(s))"


# A claim is a sentence a source actually made. A path family's items carry
# their own filename as a title (`docs/stories`, `!/usr/bin/env python3`),
# which names a subject but claims nothing — so a title only qualifies when it
# differs from its slug AND reads as a sentence. Set deliberately conservative:
# the cost of rejecting a real claim is a coverage-worded line, while the cost
# of accepting a filename is a line that pretends a source said something.
CLAIM_MIN_WORDS = 5

# The one family whose lines are claims by construction: a hub Lesson IS a
# sentence the owner already committed to. CAP-3's clause names exactly this
# source — "an element's own summary or why, and for a subtopic a claim drawn
# from its strongest element or Lesson line".
CLAIM_FAMILY = "hub-lessons"


def _subtopic_claim(sub):
    """The claim a subtopic's own material makes, or None (Story 18.81, #647).

    CAP-3's substance-led clause: a ranked slot is filled by the material's own
    words. This QUOTES the strongest claim-bearing member — never composes one
    about it — so a subtopic with nothing claim-bearing returns None and its
    caller falls back to coverage wording explicitly. The tool never invents a
    claim a source did not make.

    Strongest = unconsumed before consumed (unconsumed material is what an
    article would be written from), hub Lessons before other families (a Lesson
    line IS a claim by construction), then assembler order, which is
    deterministic within a pin.
    """
    def rank(pair):
        i, item = pair
        return (bool(item.get("consumed")), i)

    for _, item in sorted(enumerate(sub.get("items", [])), key=rank):
        # Only a Lesson line qualifies. A declared-source or backlog title
        # NAMES its subject ("Spec: /tanuki-loop — …"); quoting it beside a
        # subtopic would read as if that one member characterised the whole
        # cluster, which is a claim the map would be making, not the material.
        if item.get("family") != CLAIM_FAMILY:
            continue
        title = str(item.get("title") or "").strip()
        slug = str(item.get("slug") or "").strip()
        if title and title != slug and len(title.split()) >= CLAIM_MIN_WORDS:
            return title
    return None


def _coverage_direction(sub):
    """A subtopic's direction — SUBSTANCE-LED where the material allows it.

    `cover <subject> — <claim>`: still a coverage statement naming what to
    cover, never a thesis or an article shape (the no-second-proposer boundary,
    `specs/spec-topic-map/SPEC.md:125`). The claim lives in the DERIVATION, not
    in the rendering, because this wording becomes the owner's brief the moment
    they adopt it — the same reason #637's placeholder rule lives here. It is
    carried in FULL for the same reason: a length clip is a render-only concern
    (#651), so the brief ends at a boundary the source wrote, never mid-word;
    the View bounds the displayed line itself (`_clip_line`).
    """
    subject = _coverage_subject(sub)
    claim = _subtopic_claim(sub)
    if not claim:
        return f"cover {subject}"
    return f"cover {subject} — {claim}"


def _id_order(sub):
    """Sort key for a stable ID (`T3.2`) by its NUMERIC components (#612).

    Sorting the ID as a string renders T3.1, T3.10, T3.11 … T3.19, T3.2 —
    which scatters the ranking that assigned the IDs in the first place, so an
    85-pointer article series lands below nineteen four-pointer short notes.
    For a file whose whole purpose is owner observation, the ordering IS the
    signal.

    By construction the numeric order equals the shipped rank order (`_rank`),
    so this restores "richest terrain first" without re-deriving it. Handles
    topic numbers past 9 too, which a string sort would break next.
    """
    parts = re.findall(r"\d+", str(sub.get("id", "")))
    return tuple(int(p) for p in parts) or (0,)


def _subtopic_name(sub):
    """A heading the owner can steer by (Story 18.70, #616). An empty name
    renders as a dangling dash and names nothing, so fall back to a member's
    slug and then to an explicit placeholder — never to blank."""
    name = str(sub.get("subtopic") or "").strip()
    if name:
        return name
    for item in sub.get("items", []):
        alt = str(item.get("slug") or item.get("title") or "").strip()
        if alt:
            return alt
    return UNNAMED


# How many source files one subtopic lists before the rest are disclosed as a
# count. Declared here alone: it is an estimate of a readable block, not a
# measurement. The remainder is always DISCLOSED, never silently truncated.
VIEW_POINTER_FILES = 12

# The same convention, for lesson seeds (#634). One subtopic rendered 65
# complete lesson texts joined onto ONE physical line — ~10,000 characters —
# while every other subtopic showed `lesson seeds: none`, so the single
# subtopic where seeds existed was the one where they could not be read. A seed
# is a NAME here; its full text is reachable through the evidence pointers.
VIEW_SEED_ITEMS = 8
VIEW_SEED_CHARS = 110

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


def _seed_lines(seeds):
    """Lesson seeds, ONE PER LINE, clipped and capped — the convention
    `_pointer_lines` already applies to evidence (#615), applied to the field
    that was still unbounded (#634)."""
    if not seeds:
        return ["none"]
    shown = [_clip(s, VIEW_SEED_CHARS) for s in seeds[:VIEW_SEED_ITEMS]]
    rest = len(seeds) - len(shown)
    if rest:
        shown.append(f"… and {rest} more seed(s)")
    return shown


def _pointer_lines(pointers):
    """Evidence pointers AGGREGATED PER SOURCE FILE, `path ×N` (#615).

    The View listed every pointer on its own line: one subtopic ran to 121
    lines, another 85, and runs like `tools/tanuki-ledger:1403` through `:1408`
    took six lines to say one thing. Over half a 1781-line View was pointer
    dump. Line-granular pointers are machine provenance; the View's job is to
    let the owner distinguish 20+ directions and answer "why this depth?" from
    the counts — and burying that under provenance is the exact failure the
    size switch exists to fix.

    The total is unchanged and still printed beside this list, so the depth
    estimate stays explainable from the same numbers it was derived from. Past
    the cap the remainder is disclosed as `… and N more files`, the same
    disclosure convention CAP-4 uses for an over-bound enumeration — a silent
    truncation would read as "that was everything".
    """
    if not pointers:
        return ["none"]
    counts = {}
    for p in pointers:
        path = str(p).split("#")[0].rsplit(":", 1)[0].strip() or str(p)
        counts[path] = counts.get(path, 0) + 1
    # Most-cited first, ties broken by path so a run is reproducible.
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    shown = [f"{path} ×{n}" if n > 1 else path for path, n in ranked[:VIEW_POINTER_FILES]]
    rest = len(ranked) - len(shown)
    if rest:
        shown.append(f"… and {rest} more file(s)")
    return shown


def _member_lines(sub):
    """The subtopic's members, by name, with status — what an entry carrying
    only counts never told the owner. Consumed members are MARKED, never
    hidden: the owner may still pick them."""
    out = []
    for item in sub.get("items", []):
        label = str(item.get("slug") or item.get("title") or "").strip() or UNNAMED
        facts = [str(f) for f in (item.get("status"), item.get("family")) if f]
        mark = " — consumed" if item.get("consumed") else ""
        out.append(label + (f" ({', '.join(facts)})" if facts else "") + mark)
    return out or ["none"]


# How much of a subtopic's glance the at-a-glance summary carries. The full
# text stays one line further down, in the subtopic's own block.
VIEW_SUMMARY_GLANCE = 70


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
    combos = [c for c in cands if c.get("kind") == "combination"]
    # Elements are candidates like any other, and since Story 18.81 (#647) they
    # are presented HERE rather than in a section of their own: two lists split
    # by internal derivation kind is an implementation detail on the owner
    # surface. An element's wording is claim-bearing by construction, so it
    # sorts with the other substance-led rows.
    rest = [c for c in cands if c.get("kind") != "combination"]
    rest.sort(key=lambda c: 0 if _is_substance_led(c) else 1)
    out = []
    for c in combos + rest:
        # COUNTS DEMOTE (CAP-3, substance-led rendering): a count may trail a
        # line that leads with a claim, but it is never what the line says. A
        # fallback line carries its subject alone — "subject plus counts" is
        # the exact shape the clause forbids, and the counts stay one section
        # down in the subtopic's own block.
        facts = []
        if _is_substance_led(c):
            facts.append(f"{c.get('evidence_pointers', 0)} evidence pointer(s)")
        if c.get("consumed"):
            facts.append("already consumed — still selectable")
        trailer = f" ({', '.join(facts)})" if facts else ""
        out.append(f"- **{c['id']}** — {c['direction']}{trailer}")
    return out or ["- none: this map proposes no directions"]


def _is_substance_led(cand):
    """Does this candidate's wording carry the material's own claim?

    True for an element (its summary IS the claim) and for a subtopic whose
    material yielded one; False where `_subtopic_claim` found nothing and the
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


def _summary_lines(subs):
    """The terrain, one line per subtopic — the at-a-glance map (#632). Index,
    name, glance, consumed mark: enough to choose from, with the per-subtopic
    block below carrying the rest.

    The DEPTH WORD is on the line inside the glance, not beside it: `_glance`
    renders `[bar] <level> - <counts>` (`scripts/topic-map.py:1092`), so
    printing the level separately rendered "short note · [##..] short note -
    3 ptr" — the same word twice on a line whose whole job is to be scannable.
    """
    out = []
    for sub in sorted(subs, key=_id_order):
        mark = " · consumed" if sub.get("consumed") else ""
        claim = _subtopic_claim(sub)
        if claim:
            # SUBSTANCE-LED (Story 18.81, #647): the line IS what the material
            # says, and the count trails it. `glance` renders `[bar] level -
            # N ptr, …` — a description of the corpus, which is what this
            # section stopped carrying: it stays in the block below.
            n = sub.get("density", {}).get("evidence_pointers", 0)
            out.append(f"- **{sub['id']}** — {_clip(claim, VIEW_SUMMARY_GLANCE)} "
                       f"({n} evidence pointer(s)){mark}")
        else:
            # Nothing claim-bearing to quote, so the line names the subject and
            # stops. Never a fabricated claim, and never subject-plus-counts.
            # The SUBJECT is the coverage description (Story 18.82, #646): a
            # remediation prompt ("declare `subtopic:` …") is an instruction to
            # repo upkeep, not something the owner reads a terrain by, so it
            # lives in the maintenance section instead of on this line.
            out.append(f"- **{sub['id']}** — {_coverage_subject(sub)}{mark}")
    return out or ["- none"]


def _maintenance_lines(subs, map_data):
    """What the repo must declare for the map to name things properly — OUT of
    the reading path (Story 18.82, #646).

    These prompts are real and stay on the surface: an undeclared cluster is a
    configuration gap only the owner can close. But they are addressed to repo
    upkeep, not to someone choosing what to write, and inside a terrain line
    they read as if the map were the thing needing attention.
    """
    out = []
    for sub in sorted(subs, key=_id_order):
        name = str(_subtopic_name(sub)).strip()
        if name in PLACEHOLDER_PROSE:
            out.append(f"- **{sub['id']}** — {PLACEHOLDER_PROSE[name]}")
    for topic in sorted({str(s.get("topic") or "").strip() for s in subs}):
        if topic in PLACEHOLDER_PROSE:
            out.append(f"- topic — {PLACEHOLDER_PROSE[topic]}")
    for defect in map_data.get("subtopic_defects") or []:
        out.append(f"- declaration defect — {defect}")
    return out or ["- none: every cluster and track is declared"]


# The estimator's promotion rule, appended to the depth explanation by
# `scripts/topic-map.py:1045` as "; the next level needs evidence_pointers
# 24 < 25". It answers "what would the NEXT level require?" — the estimator's
# question, not the question of an owner choosing what to write.
DEPTH_PREDICATE_MARKER = "; the next level needs "


def _depth_line(sub):
    """The depth estimate as the View shows it (#633): the level plus the
    counts it was derived from, without the promotion arithmetic.

    The counts STAY — CAP-2's success clause promises the owner can ask "why
    this depth?" and be answered from them (`specs/spec-topic-map/SPEC.md`).
    Only the unmet predicate leaves, and only from the RENDERING: `depth.why`
    in `map.json` is untouched, which is where `check-topic-map-depth.sh`
    asserts the predicate is named. Trimming in `estimate_depth` would break
    that; trimming here cannot.

    A `why` carrying no predicate — notably the "no depth-threshold declaration
    is readable" DISCLOSURE (`scripts/topic-map.py:1027`) — passes through
    unchanged. A trim must never swallow a disclosure.
    """
    why = str(sub.get("depth", {}).get("why", ""))
    return why.split(DEPTH_PREDICATE_MARKER)[0].rstrip()


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


def _terrain_size_line(topics, subs):
    """How big this terrain is, in one unambiguous line (#645).

    `Subtopics: 25 across 4 topic(s)` reads as a FRACTION — "four topics out of
    twenty-five" — to anyone who does not already know that topics contain
    subtopics. It was the first line of the artifact, so the map failed the
    owner-readable bar before the owner reached anything selectable.

    Leading with topics puts the containing unit first, which is the order the
    relationship actually runs in, and `containing` names the relationship
    instead of leaving `across` to imply it.
    """
    def plural(n, word):
        return f"{n} {word}" if n == 1 else f"{n} {word}s"

    return f"{plural(topics, 'topic')} containing {plural(subs, 'subtopic')}"


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
    subs = _subtopics(map_data)
    pin = map_data.get("coverage", {}).get("pin")
    lines = [
        "# Topic map — the terrain",
        "",
        "<!-- Regenerated on every topic-map invocation. Never read back by any",
        "     code path; deleting this file loses nothing. Do not edit or commit. -->",
        "",
        f"Pin: {pin}",
        _terrain_size_line(len(map_data.get("topics", [])), len(subs)),
        "",
        "Answer with a subtopic's index (for example T1.2) and a short note",
        "about the angle you want. Free text always wins. How much material",
        "sits behind a line is a signal for your judgment, never a gate:",
        "a lone note is as pickable as a rich subject, and material you have",
        "already written from stays selectable.",
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
    lines += ["", "## The terrain at a glance", ""]
    lines += _summary_lines(subs)
    lines.append("")
    # END OF THE READING PATH (Story 18.82, #646). Everything below is upkeep
    # and machine detail, labeled as such: the owner chooses from what is
    # above, and the counters that used to sit inside those lines are two
    # headings down where they read as data rather than as the terrain.
    reading_path = list(lines)
    lines += ["## Maintenance — repo upkeep, not part of choosing", ""]
    lines += _maintenance_lines(subs, map_data)
    lines += ["", "## Diagnostics — how the map measured this terrain", ""]
    by_topic = {}
    for sub in subs:
        by_topic.setdefault(sub["topic"], []).append(sub)
    for topic in sorted(by_topic):
        lines += [f"### {_topic_heading(topic)}", ""]
        for sub in sorted(by_topic[topic], key=_id_order):
            d = sub.get("density", {})
            lines.append(f"#### {sub['id']} — {_coverage_subject(sub)}")
            lines.append("")
            lines.append(f"- glance: {sub.get('glance', '')}")
            lines.append(f"- depth: {_depth_line(sub)}")
            lines.append(f"- consumed: {'yes' if sub.get('consumed') else 'no'}"
                         f" ({sub.get('consumed_items', 0)} of "
                         f"{d.get('items', 0)} item(s))")
            seeds = _lesson_seed_names(sub)
            lines.append(f"- lesson seeds ({len(seeds)}):")
            for line in _seed_lines(seeds):
                lines.append(f"    - {line}")
            pointers = d.get("pointers") or []
            lines.append(f"- evidence pointers ({len(pointers)}):")
            for line in _pointer_lines(pointers):
                lines.append(f"    - {line}")
            # An entry with no pointers has shown the owner counts and nothing
            # else — and the unclustered bucket is exactly the material nothing
            # else surfaces, so it always names its members (Story 18.70,
            # #616). The data is already on the record; this is a rendering.
            if not pointers or sub.get("clustered_by") == "unclustered":
                lines.append(f"- items ({d.get('items', 0)}):")
                for member in _member_lines(sub):
                    lines.append(f"    - {member}")
            lines.append("")
    # The render-boundary check (Story 18.82, #646): an internal term reaching
    # the reading path is REPORTED, never laundered. Rewriting the line here
    # would hide the derivation defect that produced it, and the surface would
    # go on looking clean while the adopted brief still carried the term.
    for line, term in lint_owner_lines(reading_path):
        sys.stderr.write(f"warning: internal vocabulary on the owner surface: "
                         f"{term!r} in {line!r}\n")
    # The budget applies to the composed surface, not to each call site: a
    # field added later is budgeted by construction rather than by remembering.
    # Clipping is the last step, so every list above has already been capped
    # and its remainder disclosed — this bounds a single long VALUE, it never
    # silently drops an item.
    return "\n".join(_clip_line(x) for x in lines).rstrip() + "\n"


def _topic_heading(topic):
    """A topic as a heading the owner can read. The placeholder track states
    say what the bucket CONTAINS; the declaration that would name it is a
    maintenance instruction and lives in that section (Story 18.82, #646)."""
    name = str(topic).strip()
    if name == "(untracked)" or name in PLACEHOLDER_PROSE:
        return "items not yet mapped to a topic"
    return name


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
    subs = _subtopics(map_data)
    by_depth = {}
    for sub in subs:
        by_depth.setdefault(sub.get("depth", {}).get("level") or "no estimate", 0)
        by_depth[sub.get("depth", {}).get("level") or "no estimate"] += 1
    terrain = ", ".join(f"{n} {level}" for level, n in sorted(by_depth.items()))
    consumed = sum(1 for s in subs if s.get("consumed"))

    choices = []
    for c in cands:
        choices.append({
            "label": c["direction"],
            "effect": _clip(
                f"starts a normal drafting run with this as your coverage brief; "
                f"{c['evidence_pointers']} evidence pointer(s) behind it"),
        })
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

    item = {
        "where": _clip(
            f"Topic map at {map_data.get('coverage', {}).get('pin')}: "
            f"{len(topics)} topic(s), {len(subs)} subtopic(s) ({terrain}); "
            f"{consumed} already consumed and still selectable.", BUDGETS["where"]),
        "why": _clip(
            "Depth is a signal for your judgment, never a gate: a seed-only "
            "subtopic is as pickable as a rich one. What you choose becomes the "
            "coverage brief, in your words.", BUDGETS["why"]),
        "choices": choices,
    }
    return {"items": [item]}


def _compose_summary_payload(map_data, view_path):
    """The >budget screen: a summary and the View's path. Still ONE item, still
    free-form every time, still `stop here` last — the size switch changes what
    the screen SHOWS, never the shape of the contract it is presented under."""
    topics = map_data.get("topics", [])
    subs = _subtopics(map_data)
    by_depth = {}
    for sub in subs:
        level = sub.get("depth", {}).get("level") or "no estimate"
        by_depth[level] = by_depth.get(level, 0) + 1
    terrain = ", ".join(f"{n} {level}" for level, n in sorted(by_depth.items()))
    consumed = sum(1 for s in subs if s.get("consumed"))

    choices = [
        {"label": "choose a direction by its index from the View",
         "effect": _clip("answer with the index (for example T1.2) and a short "
                         "note about the angle you want; your note is carried "
                         "into the brief word for word")},
        # Free-form is offered EVERY time, not only on rejection.
        {"label": "name your own direction or combination axis",
         "effect": _clip("starts the same run with your wording as the brief; "
                         "nothing in the View is adopted unless you say so")},
        {"label": "stop here",
         "effect": _clip("nothing is drafted and no brief is recorded; the map "
                         "and the View are regenerated fresh next time")},
    ]
    item = {
        "where": _fit_with_path(
            f"Topic map at {map_data.get('coverage', {}).get('pin')}: "
            f"{len(topics)} topic(s), {len(subs)} subtopic(s) ({terrain}); "
            f"{consumed} already consumed and still selectable. Too many to "
            f"fit on one screen.", view_path, BUDGETS["where"]),
        "why": _clip(
            "Depth is a signal for your judgment, never a gate: a seed-only "
            "subtopic is as pickable as a rich one. What you choose becomes the "
            "coverage brief, in your words.", BUDGETS["why"]),
        "choices": choices,
    }
    return {"items": [item]}


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
    out["stage"] = "topic-map-brief"
    out["next"] = ("draft-pipeline.py stage0 <framework> <sources...> --brief "
                   "<this brief> — the existing stage-0 path, unchanged")
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
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
            "view": cmd_view, "brief": cmd_brief}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
