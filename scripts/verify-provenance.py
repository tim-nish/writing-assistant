#!/usr/bin/env python3
"""verify-provenance — the independent provenance-map check (Story 11.2).

Validates the sidecar provenance map WITHOUT sharing the drafting context
(NFR13; `docs/harness-architecture.md` D2): the agent that wrote the text never
grades its own claim/narration boundary. This is a standalone script — not a
draft-pipeline subcommand — so it carries none of the drafting state; it reads
only the map, the declared fact-sheet pointer set, and the independent judge's
verdicts.

It splits cleanly into a MECHANICAL layer and a SEMANTIC layer:

  Mechanical (this script decides):
    - every `derived` claim's inherited pointers must RESOLVE to declared
      fact-sheet entries; an unresolvable pointer is a gate failure;
    - a `sourced` claim's pointer must resolve too;
    - `narration` / `verify` carry no pointer.

  Semantic (an independent cheap-tier judge decides; this script consumes its
  findings — the drafting agent never self-grades):
    - a `narration` sentence that asserts a checkable proposition fails the
      falsifiability test → gate failure;
    - a `derived` claim that adds one of the six forbidden categories
      (causality, significance, evaluation, comparison, intent, scope) →
      gate failure.
  The judge's verdicts arrive via --judge-findings (one `POS: reason` per line);
  --list-narration / --list-derived emit the sentences the judge must grade.

Exit 0 with no findings = the map passes. Any finding = a gate failure, printed
as `POS: reason`, and a non-zero exit — the Stage 3→4 gate (Story 11.4) blocks
on it.
"""

import argparse
import re
import sys

PROV_CLASSES = ("sourced", "derived", "narration", "verify")
PROV_LINE = re.compile(
    r"^(?P<pos>\S+):\s*(?P<cls>sourced|derived|narration|verify)"
    r"(?:\s*<-\s*(?P<ptrs>.+?))?\s*$"
)


def parse_map(text):
    entries = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = PROV_LINE.match(line)
        if not m:
            raise ValueError(f"line {lineno}: malformed provenance entry: {raw!r}")
        ptrs = [p.strip() for p in (m.group("ptrs") or "").split(",") if p.strip()]
        entries.append((m.group("pos"), m.group("cls"), ptrs))
    return entries


def _read(path):
    return sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()


def _load_set(path):
    if not path:
        return None
    return {ln.strip() for ln in _read(path).splitlines() if ln.strip() and not ln.startswith("#")}


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--map", default="-", help="the sidecar provenance map, or - for stdin")
    p.add_argument("--fact-sheet", help="file of valid fact-sheet pointer ids (one per line)")
    p.add_argument("--judge-findings", help="independent judge's verdicts: `POS: reason` per line")
    p.add_argument("--list-narration", action="store_true", help="list narration positions for the judge")
    p.add_argument("--list-derived", action="store_true", help="list derived positions + pointers for the judge")
    args = p.parse_args(argv)

    try:
        entries = parse_map(_read(args.map))
    except ValueError as e:
        sys.stderr.write(f"error: {e}\n")
        return 2

    if args.list_narration:
        for pos, cls, _ in entries:
            if cls == "narration":
                print(pos)
        return 0
    if args.list_derived:
        for pos, cls, ptrs in entries:
            if cls == "derived":
                print(f"{pos}: {', '.join(ptrs)}")
        return 0

    valid = _load_set(args.fact_sheet)
    findings = []

    # --- mechanical layer ---
    for pos, cls, ptrs in entries:
        if cls in ("narration", "verify") and ptrs:
            findings.append((pos, f"{cls} must carry no pointer"))
        if cls == "sourced" and not ptrs:
            findings.append((pos, "sourced claim carries no pointer"))
        if cls == "derived" and len(ptrs) < 2:
            findings.append((pos, f"derived claim must inherit >=2 pointers (got {len(ptrs)})"))
        if valid is not None and cls in ("sourced", "derived"):
            for ptr in ptrs:
                if ptr not in valid:
                    findings.append((pos, f"pointer {ptr!r} does not resolve to a fact-sheet entry"))

    # --- semantic layer (independent judge's verdicts) ---
    if args.judge_findings:
        positions = {pos for pos, _, _ in entries}
        for ln in _read(args.judge_findings).splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            pos, _, reason = ln.partition(":")
            pos, reason = pos.strip(), reason.strip()
            findings.append((pos, reason or "judge flagged a provenance violation"))

    if not findings:
        print("verify-provenance: PASS (no findings)")
        return 0
    sys.stderr.write("verify-provenance: FAIL\n")
    for pos, reason in findings:
        sys.stderr.write(f"  {pos}: {reason}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
