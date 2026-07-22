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
    TOPIC ∈ {surprise, significance, opinion, warning, tradeoff, audience, other} — the gap-
    interview categories so items are groupable/prioritizable;
  * the partition is strict — no candidate text appears both here and as a fact-
    sheet CLAIM (mutual exclusion; nothing double-counted);
  * NO CONFABULATED PREMISE (#526, generalized #567): a NEEDS-OWNER item may
    pose an unsourceable QUESTION — that is why it is on the list — but it must
    never assert an unsourced factual PREMISE as established fact. Any factual
    ground an item carries is EITHER a declared OPTIONAL trailing `premise:`
    clause (this path's item grammar) OR grounded inline at its point of use,
    and in both cases it is marked `unverified —` (an open question, not a
    claim) or pointer-backed under the SAME resolvable `path:line@sha` grammar
    a fact-sheet SOURCE uses. Anything else is a NAMED rejection.

    The rule itself is the ENGINE-WIDE one and lives in `gate_premise.py`
    (SPEC-writing-assistant, "Gate-item content grounding"): it binds every
    machine-authored gate item, and this file is one call site of it, never its
    owner. It attaches to PREMISE CLAUSES specifically, so a correct top-level
    disclosure (`not in declared sources`) is no defence for an invention in a
    subordinate clause — the #526 shape. This file and `skills/harvest/SKILL.md
    §4` remain the two enforcement copies for THIS path — a change to one
    without the other is a defect (the same lockstep the KIND set carries).

An item with NO factual premise parses byte-identically to before — posing an
unsourceable question with no asserted premise still PASSES.

With --group, prints the NEEDS-OWNER items grouped by TOPIC (how the ≤5-question
interview consumes them). Exit is non-zero on any violation. With --root, a
declared premise pointer is also resolved at its commit in the host's declared
sources (the fact-sheet resolvability rule); without --root the structural pin
grammar is enforced alone (the primary gate — the check harness runs no hub).

Usage: validate-needs-owner.py [HARVEST_DOC|-] [--group] [--root HOSTROOT]
"""

import argparse
import importlib.util
import os
import re
import sys

TOPICS = {"surprise", "significance", "opinion", "warning", "tradeoff", "audience", "other"}

# The premise rule is the SHARED one (#567): this file is now one CALL SITE of
# `gate_premise.py`, not its owner. The rule binds every machine-authored gate
# item; the NEEDS-OWNER path is its first instance, and its declared
# `premise:` clause is that instance's item grammar. `split_premise` /
# `validate_premise` are re-exported so existing importers keep working.
def _load_gp():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "gate_premise", os.path.join(here, "gate_premise.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gp = _load_gp()

split_premise = gp.split_premise
validate_premise = gp.validate_premise


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


def validate(text, host=None, sources=None):
    """Return a list of problems (empty = valid)."""
    problems = []
    fs_lines, no_lines, has_heading = split_sections(text)
    if not has_heading:
        problems.append("NEEDS-OWNER section missing — it must be emitted even when empty")
        return problems

    fs_claims = {norm(e.rsplit(" / ", 2)[0]) for e in entries(fs_lines) if e.rsplit(" / ", 2)[0]}

    seen = set()
    for raw in entries(no_lines):
        # Pull the optional trailing `premise:` clause off FIRST, then validate
        # the remaining CANDIDATE / REASON / TOPIC triple exactly as before (#526).
        core, premise = split_premise(raw)
        parts = [p.strip() for p in core.rsplit(" / ", 2)]
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
        # The declared clause AND the item's own prose (#567): a premise
        # smuggled into the CANDIDATE/REASON text is checked per clause, so a
        # correct top-level disclosure is no defence — the #526 shape.
        for preason in gp.check(core, premise, host, sources):
            problems.append(f"{preason} — {raw}")
    return problems


def group_by_topic(text):
    _, no_lines, _ = split_sections(text)
    groups = {}
    for raw in entries(no_lines):
        core, _ = split_premise(raw)
        parts = [p.strip() for p in core.rsplit(" / ", 2)]
        if len(parts) != 3:
            continue
        groups.setdefault(parts[2], []).append(parts[0])
    return groups


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("doc", nargs="?", default="-", help="harvest output document, or - for stdin")
    p.add_argument("--group", action="store_true", help="group NEEDS-OWNER items by TOPIC (interview view)")
    p.add_argument("--root", help="host-repo root: also RESOLVE each declared premise pointer at "
                                  "its commit in the host's declared sources (fact-sheet rule). "
                                  "Without --root the structural pin grammar is enforced alone.")
    args = p.parse_args(argv)
    text = sys.stdin.read() if args.doc == "-" else open(args.doc, encoding="utf-8").read()

    if args.group:
        for topic in sorted(group_by_topic(text)):
            print(f"[{topic}]")
            for c in group_by_topic(text)[topic]:
                print(f"  - {c}")
        return 0

    # Premise-pointer resolution is opt-in: only when --root supplies a host with
    # declared sources do we resolve pins at their commit. The grammar gate runs
    # regardless — it is the primary enforcement (the check harness has no hub).
    host = sources = None
    if args.root is not None:
        vfs = gp.vfs()
        host = vfs.rws.host_root(args.root)
        ws_path, ws_kind = vfs.rws.sources_path(host, notice=False)
        if ws_kind == "none":
            print(f"error: no {vfs.rws.SOURCES_FILE} for host {host} — drop --root "
                  f"for structural-only premise checking, or check --root", file=sys.stderr)
            return 2
        try:
            sources = vfs.rws.get_sources(vfs.rws.read_lines(host), host)
        except vfs.rws.MalformedSources as e:
            print(f"error: {ws_path}: {e}", file=sys.stderr)
            return 2

    problems = validate(text, host, sources)
    for prob in problems:
        print(f"REJECT  {prob}")
    if not problems:
        print("NEEDS-OWNER list valid (schema + partition OK).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
