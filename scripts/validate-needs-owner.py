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
  * NO CONFABULATED PREMISE (#526): a NEEDS-OWNER item may pose an unsourceable
    QUESTION — that is why it is on the list — but it must never assert an
    unsourced factual PREMISE as established fact. Any factual ground an item
    carries is a declared OPTIONAL trailing `premise:` clause that is EITHER
    marked `premise: unverified` (an open question, not a claim) OR pointer-
    backed under the SAME resolvable `path:line@sha` grammar a fact-sheet SOURCE
    uses. A declared premise that is neither — prose asserted as fact, an
    unpinned `path:line`, a malformed pointer — is a NAMED rejection. This is the
    same lockstep the KIND set carries: this file and `skills/harvest/SKILL.md §4`
    are the two enforcement copies — a change to one without the other is a
    defect (SPEC-article-draft-pipeline, "No confabulated NEEDS-OWNER premise").

An item with NO `premise:` clause parses byte-identically to before — posing an
unsourceable question with no asserted factual premise still PASSES.

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

# The premise pointer is held to the fact-sheet SOURCE grammar, so the two
# cannot diverge: we reuse validate-fact-sheet.py's grammar + git-resolution
# machinery rather than re-deriving a second pointer parser (#526).
def _load_vfs():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "vfs", os.path.join(here, "validate-fact-sheet.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


vfs = _load_vfs()


def split_premise(raw):
    """Pull an OPTIONAL trailing `premise:` clause off a NEEDS-OWNER line (#526).

    Returns (core, premise_value): `core` is the line with any premise clause
    removed, to be parsed as `CANDIDATE / REASON / TOPIC` exactly as before;
    `premise_value` is the text after `premise:` (which may itself contain
    ` / `), or None when the item declares no premise. An item with no premise
    clause returns (raw, None) unchanged — it parses byte-identically to today."""
    segs = raw.split(" / ")
    for i, s in enumerate(segs):
        if s.strip().startswith("premise:"):
            core = " / ".join(segs[:i]).rstrip()
            clause = " / ".join(segs[i:]).strip()
            return core, clause[len("premise:"):].strip()
    return raw, None


def validate_premise(value, host=None, sources=None):
    """Validate a declared premise value. Returns None if it passes, else a
    NAMED rejection reason (#526).

      * `unverified` (literal)        -> PASS (an open question, not a claim);
      * a pinned fact-sheet pointer   -> PASS structurally; when host/sources
        context is present (--root), also RESOLVED at the commit;
      * anything else                 -> a named rejection (`confabulated-premise`
        for prose/malformed, `unpinned-premise-pointer` for a bare path:line)."""
    v = value.strip()
    if v == "unverified":
        return None
    # Grammar gate: the same atomic SOURCE forms a fact sheet accepts, single
    # line (kind 'event' is not span-eligible, so a premise pins one line).
    if vfs.source_form_ok(v, "event"):
        if host is not None and sources is not None:
            return vfs.validate_source(v, "event", v, host, sources)
        return None                      # structural pass — pin present
    if re.match(r"^\S.*:\d+(-\d+)?$", v):
        return ("unpinned-premise-pointer: premise pointer is not pinned to a "
                "commit (use path:line@sha, the fact-sheet SOURCE grammar) — or "
                "mark `premise: unverified` if the factual ground is an open question")
    return ("confabulated-premise: a NEEDS-OWNER premise asserted as fact must be "
            "a resolvable pointer (path:line@sha) or explicitly marked "
            "`premise: unverified` — undeclared/prose factual ground is not evidence")


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
        if premise is not None:
            preason = validate_premise(premise, host, sources)
            if preason:
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
