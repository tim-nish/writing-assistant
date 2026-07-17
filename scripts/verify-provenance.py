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
# `POS ~ "<quoted>": reason` — the judge echoing the sentence it graded.
JUDGE_ECHO = re.compile(r'^(?P<pos>[^~:]+)~\s*"(?P<quote>[^"]*)"\s*:\s*(?P<reason>.*)$')
# Positions may carry a line anchor — `P1.S1[L7]` (#304). This parser stays
# independent of the pipeline's (NFR13: the drafting context never grades its
# own map), so the grammar is mirrored here deliberately, not imported.
PROV_LINE = re.compile(
    r"^(?P<pos>[^\s:\[]+)(?:\[L(?P<anchor>\d+)\])?"
    r":\s*(?P<cls>sourced|derived|narration|verify)"
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
        anchor = int(m.group("anchor")) if m.group("anchor") else None
        entries.append((m.group("pos"), m.group("cls"), ptrs, anchor))
    return entries


def anchored_text(anchor, draft_lines):
    """The verbatim draft line an anchor names — what the judge MATCHES against.

    Returning the line (not a re-split sentence) is the point: any derivation
    the judge has to perform is a derivation it can get wrong, and three judges
    already proved they get it wrong differently.
    """
    if anchor is None or draft_lines is None:
        return None
    if not (1 <= anchor <= len(draft_lines)):
        return None
    return draft_lines[anchor - 1].strip()


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
    p.add_argument("--draft", help="the draft the map describes; makes the judge hand-off carry each\nposition's anchored line verbatim, and lets an echoed judge quote be checked (#304)")
    args = p.parse_args(argv)

    try:
        entries = parse_map(_read(args.map))
    except ValueError as e:
        sys.stderr.write(f"error: {e}\n")
        return 2

    draft_lines = _read(args.draft).splitlines() if args.draft else None

    # The judge hand-off. With --draft each position carries its anchored line
    # verbatim, so the judge MATCHES the sentence instead of re-deriving the
    # P{n}.S{n} numbering from skip rules (#304). Emission is a pure function of
    # (map, draft): every spawn receives byte-identical text, which is what makes
    # three judges agree on what P8.S3 is.
    if args.list_narration:
        for pos, cls, _, anchor in entries:
            if cls != "narration":
                continue
            text = anchored_text(anchor, draft_lines)
            print(f"{pos} [L{anchor}]: {text}" if text is not None else pos)
        return 0
    if args.list_derived:
        for pos, cls, ptrs, anchor in entries:
            if cls != "derived":
                continue
            text = anchored_text(anchor, draft_lines)
            head = f"{pos} [L{anchor}]" if text is not None else pos
            print(f"{head}: {', '.join(ptrs)}" + (f" | {text}" if text is not None else ""))
        return 0

    valid = _load_set(args.fact_sheet)
    findings = []

    # --- mechanical layer ---
    for pos, cls, ptrs, anchor in entries:
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
    # Grammar: `POS: reason`, or `POS ~ "<quoted sentence>": reason` when the
    # judge echoes the text it graded. The echo is what makes a MISLOCATED
    # verdict detectable from the record alone (#304): a judge that graded the
    # wrong sentence still returns a confident finding, and previously the only
    # way to notice was a human comparing quote to draft — which needs exactly
    # the drafting context NFR13 denies the judge. With the echo, the mismatch
    # is arithmetic.
    if args.judge_findings:
        anchors = {pos: anchor for pos, _, _, anchor in entries}
        known = set(anchors)
        for ln in _read(args.judge_findings).splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            m = JUDGE_ECHO.match(ln)
            if m:
                pos, quoted, reason = m.group("pos").strip(), m.group("quote"), m.group("reason").strip()
            else:
                pos, _, reason = ln.partition(":")
                pos, quoted, reason = pos.strip(), None, reason.strip()
            if pos not in known:
                findings.append((pos, f"judge graded position {pos!r}, which is not in the map "
                                      "— the verdict cannot be trusted"))
                continue
            if quoted is not None:
                actual = anchored_text(anchors[pos], draft_lines)
                if actual is None:
                    findings.append((pos, "judge echoed a sentence but the map gives no "
                                          "resolvable anchor to check it against"))
                    continue
                if quoted.strip() not in actual:
                    findings.append((pos, f"ANCHOR MISMATCH: judge graded {quoted.strip()!r} "
                                          f"but {pos} anchors to {actual!r} — the verdict is "
                                          "about a different sentence and is discarded"))
                    continue
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
