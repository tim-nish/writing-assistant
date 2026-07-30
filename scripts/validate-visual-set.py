#!/usr/bin/env python3
"""validate-visual-set.py — validate a visual-set plan (SPEC-article-visuals
CAP-2a, Story 13.58).

Before any individual visual proposal, the pipeline proposes the article's
visual set as a whole. This validator enforces the plan's machine-checkable
rules so a malformed or over-budget plan never reaches the owner as a ratifiable
item:

  * the plan holds at most `slot_count + 2` members — the slots THIS ACCEPTED
    STRUCTURE declares plus the two opportunistic extras CAP-2 allows; the plan
    proposes WITHIN that cap, never raises it. The count comes from the plan
    record's `visual_slots` (Story 20.68, #983), never from framework identity:
    #911 demoted F1-F5 to candidates and records `bespoke` on every accepted
    structure, so a framework-anchored operand is undefined exactly on the case
    #911's own instrument expects to be common. A framework-matched structure
    may declare CAP-1's slots verbatim; a bespoke one declares its own; either
    way the cap is defined;
  * a ZERO-member plan is valid — an article may need no visual — and is never
    padded toward the cap;
  * every member enumerates role, required_elements, format, and placement;
  * every required element carries evidence — a commit-pinned pointer, an
    interview-answer id, or an explicit `[VERIFY]`/NEEDS-OWNER marker (CAP-3):
    an element with none would launder an unsourced structural claim into the
    draft, so it is refused.

Plan JSON:

    {
      "members": [
        {
          "role": "the harvest→draft→review pipeline flow",
          "required_elements": ["harvest", "draft", "review", "gate edge"],
          "format": "diagram",
          "placement": "Section 3 (Architecture) — declared slot",
          "evidence": {
            "harvest":    "skills/harvest/SKILL.md:11@a1b2c3d",
            "draft":      "q4",
            "review":     "skills/review-article/SKILL.md:1@a1b2c3d",
            "gate edge":  "[VERIFY: the ordering is argued in prose, unpinned]"
          }
        }
      ]
    }

Exit 0 = a ratifiable plan; exit 4 = refused, with a per-member report.
"""

import argparse
import json
import re
import sys

REFUSED = 4
OPPORTUNISTIC_EXTRAS = 2  # CAP-2: the declared slot plus at most two extras.

# The evidence forms an element may carry (mirrors the fact-sheet / plan-body
# grammar) OR an explicit unverified marker that routes to owner arbitration.
PINNED_PTR_RE = re.compile(
    r"^(?:.+:\d+(?:-\d+)?@[0-9a-f]{7,40}"
    r"|[0-9a-f]{7,40}"
    r"|https?://\S+"
    r"|den:[A-Za-z0-9._-]+@[A-Za-z0-9._-]+"
    r"|[qa]\d+)$")
VERIFY_RE = re.compile(r"\[VERIFY\b|NEEDS-OWNER", re.IGNORECASE)
# A fact-sheet id is a derived index into the fact sheet, not evidence: the
# fact's own SOURCE pointer is the pinned form ratification needs (F72).
FACT_SHEET_ID_RE = re.compile(r"^fs-\d+$")

MEMBER_KEYS = ("role", "required_elements", "format", "placement", "evidence")


def validate(plan, slot_count):
    """Yield (where, reason) for each violation; empty = ratifiable."""
    if not isinstance(plan, dict) or not isinstance(plan.get("members"), list):
        yield ("plan", "must be an object with a `members` list (a zero-member "
                       "list is a valid zero-visual plan)")
        return

    members = plan["members"]
    cap = slot_count + OPPORTUNISTIC_EXTRAS
    if len(members) > cap:
        yield ("plan", f"{len(members)} members exceed the cap of {cap} "
                       f"(declared slots {slot_count} + {OPPORTUNISTIC_EXTRAS} "
                       "opportunistic extras) — the plan proposes within the "
                       "cap, never raises it")

    # A zero-member plan is valid and must not be padded. There is nothing to
    # pad here (the list IS the plan), so zero members simply passes — the
    # no-padding rule is a property the SKILL upholds and this validator never
    # violates by inventing members.
    for i, m in enumerate(members):
        tag = f"members[{i}]"
        if not isinstance(m, dict):
            yield (tag, "member is not an object")
            continue
        fixes = {
            "role": "state the communicative role — the part of the "
                    "argument this visual carries",
            "format": 'set "table", "diagram", or "chart" for a '
                      "QUANTITATIVE role — measured results, a trend — which "
                      "takes the CAP-4 Vega-Lite rung, since Mermaid is "
                      "topological and cannot carry magnitude (#983)",
            "placement": "name the framework slot or the section the "
                         "visual sits in",
        }
        for key in ("role", "format", "placement"):
            if not str(m.get(key, "")).strip():
                yield (f"{tag}.{key}",
                       f"required and non-empty — fix: {fixes[key]}")
        elements = m.get("required_elements")
        if not isinstance(elements, list) or not elements:
            yield (f"{tag}.required_elements",
                   "a member must enumerate at least one required element — "
                   "fix: list the nodes/relationships/rows the role demands, "
                   "then map each one in `evidence`")
            continue
        evidence = m.get("evidence")
        if not isinstance(evidence, dict):
            yield (f"{tag}.evidence",
                   "a member must map each required element to its evidence "
                   "(a pinned pointer, an interview-answer id, or a "
                   "[VERIFY]/NEEDS-OWNER marker) — fix: add an `evidence` "
                   "object with one entry per required element, e.g. "
                   '{"<element>": "path:line@sha" | "q4" | '
                   '"[VERIFY: reason]"}')
            continue
        for el in elements:
            val = str(evidence.get(el, "")).strip()
            if not val:
                yield (f"{tag}.evidence[{el!r}]",
                       "element has no evidence — a source pointer, an "
                       "interview-answer id, or an explicit [VERIFY]/NEEDS-OWNER "
                       "marker is required (CAP-3); an unsourced element is "
                       "never laundered into the set — fix: set "
                       f'evidence[{el!r}] to "path:line@sha", an answer id '
                       'like "q4", or "[VERIFY: <why it is unpinned>]"')
            elif FACT_SHEET_ID_RE.match(val):
                yield (f"{tag}.evidence[{el!r}]",
                       f"evidence {val!r} is a fact-sheet id — a derived "
                       "index, not evidence — fix: copy that fact's own "
                       'SOURCE pointer ("path:line@sha") from the fact '
                       "sheet; a fact with no pinned SOURCE routes to "
                       '"[VERIFY: reason]" instead')
            elif not (PINNED_PTR_RE.match(val) or VERIFY_RE.search(val)):
                yield (f"{tag}.evidence[{el!r}]",
                       f"evidence {val!r} is neither a pinned pointer / "
                       "interview-answer id nor a [VERIFY]/NEEDS-OWNER marker "
                       '— fix: use "path:line@sha", a bare commit sha, a URL, '
                       '"den:pkg@ver", an answer id like "q4", or '
                       '"[VERIFY: reason]"')


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("plan", nargs="?", default="-",
                   help="visual-set plan JSON file, or - for stdin")
    p.add_argument("--slot-count", type=int, default=None,
                   help="the ACCEPTED STRUCTURE's declared visual-slot count — "
                        "len(visual_slots) from the plan record (#983), not a "
                        "framework's. The cap is this + 2 opportunistic "
                        "extras. Required unless --plan-record supplies it.")
    p.add_argument("--plan-record", metavar="PATH",
                   help="the article plan JSON, to read `visual_slots` from "
                        "directly instead of passing --slot-count")
    args = p.parse_args(argv)

    slot_count = args.slot_count
    if args.plan_record:
        try:
            rec = json.loads(open(args.plan_record, encoding="utf-8").read())
        except (OSError, json.JSONDecodeError) as e:
            sys.stderr.write(f"error: plan record unreadable: {e}\n")
            return 2
        slots = rec.get("visual_slots")
        if not isinstance(slots, list):
            sys.stderr.write(
                "error: the plan record declares no `visual_slots` — an "
                "accepted structure must declare its slots (`[]` when it has "
                "none) or the cap has no operand (#983)\n")
            return 2
        slot_count = len(slots)
    if slot_count is None:
        sys.stderr.write(
            "error: no declared slot count — pass --slot-count (the accepted "
            "structure's len(visual_slots)) or --plan-record. It is not "
            "defaulted: a guessed operand is how the framework-anchored cap "
            "silently mis-sized a bespoke structure's plan (#983)\n")
        return 2

    raw = sys.stdin.read() if args.plan == "-" else open(args.plan, encoding="utf-8").read()
    try:
        plan = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: plan is not valid JSON: {e}\n")
        return 2

    defects = list(validate(plan, slot_count))
    if not defects:
        n = len(plan.get("members", []))
        print(json.dumps({"ok": True, "members": n,
                          "cap": slot_count + OPPORTUNISTIC_EXTRAS,
                          "zero_plan": n == 0}))
        return 0
    sys.stderr.write("visual-set plan REFUSED — not ratifiable:\n")
    for where, reason in defects:
        sys.stderr.write(f"  {where}: {reason}\n")
    sys.stderr.write(
        "resolve exactly the fields named above and resubmit — a plan "
        "authored from the scaffold shape (SKILL.md, Visual-set plan) is "
        "ratifiable first-try\n")
    return REFUSED


if __name__ == "__main__":
    sys.exit(main())
