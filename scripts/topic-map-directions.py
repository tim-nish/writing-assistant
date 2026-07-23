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
  payload     --map PATH        the one screen, as a proposal payload
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

# How many machine-proposed directions the screen carries. A screen is a screen:
# the map's job is to make the terrain legible, not to enumerate it.
MAX_SINGLE = 3
MAX_COMBINATION = 2

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
    """Every subtopic in the map, each carrying its topic — flat, in a
    deterministic order, with nothing filtered out. Consumed subtopics are
    included: they are MARKED, never hidden, and the owner may still pick one."""
    rows = []
    for topic in map_data.get("topics", []):
        for sub in topic.get("subtopics", []):
            rows.append(dict(sub, topic=topic["topic"]))
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


def candidates(map_data):
    """Machine-proposed candidate DIRECTIONS, derived from the map's own depth
    signals. Never a narrative shape — what to cover, not how to tell it."""
    subs = sorted(_subtopics(map_data), key=_rank)
    out = []
    for sub in subs[:MAX_SINGLE]:
        d = sub.get("density", {})
        depth = sub.get("depth", {})
        out.append({
            "kind": "single",
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
    out.extend(combos[:MAX_COMBINATION])
    return out


def _clip(text, budget=BUDGETS["effect"]):
    text = " ".join(str(text).split())
    return text if len(text) <= budget else text[:budget - 1].rstrip() + "."


def compose_payload(map_data, cands):
    """The ONE screen: the terrain, the candidate directions, a free-form
    response, and stopping. Plain text only — the payload the validator accepts
    is the payload the owner sees."""
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
    print(json.dumps(compose_payload(data, candidates(data)),
                     indent=2, ensure_ascii=False))
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
    b = sub.add_parser("brief", help="the owner's outcome as the stage-0 brief")
    b.add_argument("--answer", required=True,
                   help="the recorded answer JSON, or - for stdin")
    b.add_argument("--map", help="the same map, so an adopted candidate resolves")
    args = p.parse_args(argv)
    return {"candidates": cmd_candidates, "payload": cmd_payload,
            "brief": cmd_brief}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
