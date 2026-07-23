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

# The View's fixed filename. "Fixed path" is the CAP-3 property that makes the
# View safe: one name per run workspace, fully regenerated every invocation,
# never read back. The caller passes the directory-qualified path (the run
# workspace), exactly as it does for topic-map.py's --emit-debug.
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
        out.append({
            "kind": "single",
            "id": sub["id"],
            "direction": f"cover {sub['subtopic']}",
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
                "direction": (f"connect {a['subtopic']} and {b['subtopic']} along "
                              f"{shared[0]}"),
                "topics": sorted({a["topic"], b["topic"]}),
                "subtopics": [a["subtopic"], b["subtopic"]],
                "axis": shared[0],
                "shared_evidence": shared,
                "why": (f"{a['subtopic']} ({a['topic']}) and {b['subtopic']} "
                        f"({b['topic']}) both cite {', '.join(shared)}"),
                "evidence_pointers": (a.get("density", {}).get("evidence_pointers", 0)
                                      + b.get("density", {}).get("evidence_pointers", 0)),
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


def compose_view(map_data):
    """The View: one invocation's terrain, rendered so 20+ directions are
    legible and CAP-2's 'why this depth?' is answerable from the same counts
    the estimate used.

    A RENDERING, at the same status as topic-map.py's --emit-debug: fully
    regenerated every invocation and NEVER read back by any code path. Deleting
    it loses nothing — the map is recomputed, and this is recomposed from it.
    """
    subs = _subtopics(map_data)
    pin = map_data.get("coverage", {}).get("pin")
    lines = [
        "# Topic map — the terrain",
        "",
        f"Pin: {pin}",
        f"Subtopics: {len(subs)} across {len(map_data.get('topics', []))} topic(s)",
        "",
        "Answer with a subtopic's index (for example T1.2) and a short note",
        "about the angle you want. Free text always wins. Depth is a signal for",
        "your judgment, never a gate: a seed-only subtopic is as pickable as a",
        "rich one, and consumed material stays selectable.",
        "",
    ]
    by_topic = {}
    for sub in subs:
        by_topic.setdefault(sub["topic"], []).append(sub)
    for topic in sorted(by_topic):
        lines += [f"## {topic}", ""]
        for sub in sorted(by_topic[topic], key=lambda s: s["id"]):
            d = sub.get("density", {})
            lines.append(f"### {sub['id']} — {sub['subtopic']}")
            lines.append("")
            lines.append(f"- glance: {sub.get('glance', '')}")
            lines.append(f"- depth: {sub.get('depth', {}).get('why', '')}")
            lines.append(f"- consumed: {'yes' if sub.get('consumed') else 'no'}"
                         f" ({sub.get('consumed_items', 0)} of "
                         f"{d.get('items', 0)} item(s))")
            seeds = _lesson_seed_names(sub)
            lines.append("- lesson seeds: "
                         + (", ".join(seeds) if seeds else "none"))
            pointers = d.get("pointers") or []
            lines.append(f"- evidence pointers ({len(pointers)}):")
            for p in pointers:
                lines.append(f"    - {p}")
            if not pointers:
                lines.append("    - none")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


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


def brief_from_answer(answer, cands):
    """The owner's outcome as the brief string for stage-0 `--brief`.

    Free text ALWAYS wins: machine-proposed wording becomes the brief only when
    the owner adopted it by selecting it, and then it is owner-adopted wording,
    not a tool-invented scope."""
    free = str(answer.get("free_text") or "").strip()
    if free:
        return {"brief": free, "provenance": "owner-authored", "origin": "free-form"}
    selection = str(answer.get("selection") or "").strip()
    if selection in ("stop here", "stop"):
        raise SystemExit(_err(
            "the owner chose to stop at the map: no brief exists and no run "
            "follows. Stopping is a first-class outcome, not a failure."))
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
    if view_path and large:
        write_view(view_path, compose_view(data))
    print(json.dumps(compose_payload(data, candidates(data), view_path),
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
    write_view(args.out, compose_view(load_map(args.map)))
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
    cands = candidates(load_map(args.map)) if args.map else []
    out = brief_from_answer(answer, cands)
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
