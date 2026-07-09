#!/usr/bin/env python3
"""Validate the harvest NEEDS-OWNER list and its partition from the fact sheet
(Story 3.3).

A harvest output document has two sections:

    # Fact sheet: {subject}
    - CLAIM / SOURCE / KIND          # source-pointed (Story 3.2)
    ...
    # NEEDS-OWNER
    - CANDIDATE / REASON / TOPIC      # unsourceable, feeds the gap interview
    ...

This enforces:
  * the `# NEEDS-OWNER` section is ALWAYS present (a stable contract downstream
    stages can rely on) — even with zero entries;
  * every NEEDS-OWNER entry is `CANDIDATE / REASON / TOPIC` with all fields
    non-empty (context to seed the interview, not a bare string), and
    TOPIC ∈ {surprise, significance, opinion, warning, other} — the gap-
    interview categories so items are groupable/prioritizable;
  * the partition is strict — no candidate text appears both here and as a fact-
    sheet CLAIM (mutual exclusion; nothing double-counted).

With --group, prints the NEEDS-OWNER items grouped by TOPIC (how the ≤5-question
interview consumes them). Exit is non-zero on any violation.

Usage: validate-needs-owner.py [HARVEST_DOC|-] [--group]
"""

import argparse
import re
import sys

TOPICS = {"surprise", "significance", "opinion", "warning", "other"}


def split_sections(text):
    """Return (fact_sheet_lines, needs_owner_lines, has_needs_owner_heading)."""
    fs, no, in_no, seen = [], [], False, False
    for ln in text.split("\n"):
        if re.match(r"^#+\s*NEEDS-OWNER\b", ln):
            in_no, seen = True, True
            continue
        (no if in_no else fs).append(ln)
    return fs, no, seen


def entries(lines):
    return [ln[2:] for ln in lines if ln.startswith("- ")]


def norm(claim):
    return re.sub(r"\s+", " ", claim.strip().lower())


def validate(text):
    """Return a list of problems (empty = valid)."""
    problems = []
    fs_lines, no_lines, has_heading = split_sections(text)
    if not has_heading:
        problems.append("NEEDS-OWNER section missing — it must be emitted even when empty")
        return problems

    fs_claims = {norm(e.rsplit(" / ", 2)[0]) for e in entries(fs_lines) if e.rsplit(" / ", 2)[0]}

    seen = set()
    for raw in entries(no_lines):
        parts = [p.strip() for p in raw.rsplit(" / ", 2)]
        if len(parts) != 3 or any(p == "" for p in parts):
            problems.append(f"malformed (need `CANDIDATE / REASON / TOPIC`): {raw}")
            continue
        candidate, reason, topic = parts
        if topic not in TOPICS:
            problems.append(f"invalid TOPIC {topic!r} (must be one of {sorted(TOPICS)}): {raw}")
        key = norm(candidate)
        if key in fs_claims:
            problems.append(f"candidate is ALSO a fact-sheet claim (double-counted): {candidate}")
        if key in seen:
            problems.append(f"duplicate NEEDS-OWNER candidate: {candidate}")
        seen.add(key)
    return problems


def group_by_topic(text):
    _, no_lines, _ = split_sections(text)
    groups = {}
    for raw in entries(no_lines):
        parts = [p.strip() for p in raw.rsplit(" / ", 2)]
        if len(parts) != 3:
            continue
        groups.setdefault(parts[2], []).append(parts[0])
    return groups


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("doc", nargs="?", default="-", help="harvest output document, or - for stdin")
    p.add_argument("--group", action="store_true", help="group NEEDS-OWNER items by TOPIC (interview view)")
    args = p.parse_args(argv)
    text = sys.stdin.read() if args.doc == "-" else open(args.doc, encoding="utf-8").read()

    if args.group:
        for topic in sorted(group_by_topic(text)):
            print(f"[{topic}]")
            for c in group_by_topic(text)[topic]:
                print(f"  - {c}")
        return 0

    problems = validate(text)
    for prob in problems:
        print(f"REJECT  {prob}")
    if not problems:
        print("NEEDS-OWNER list valid (schema + partition OK).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
