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

Fail-closed judge attestation (Story 13.67, #364): the verdicts file must open
with a structured attestation the judge echoes from the --list-* hand-off —

    attestation: draft-sha256=<hex64>
    graded: P1.S1,P1.S4,...        (repeatable; lines are unioned)

followed by the failure verdicts (none, when the judge found nothing). The
attestation binds the verdicts to the draft (content hash) and to the expected
worklist (every narration + derived position in the map). A comment-only file,
a graded set that does not cover the worklist, an unknown graded position, or
a draft-hash mismatch is an ATTESTATION FAILURE (exit 3), reported before any
grading result — absence of verdicts is never PASS, and "never judged" is
mechanically distinguishable from "judged clean".

Exit 0 with no findings = the map passes. Any finding = a gate failure, printed
as `POS: reason`, and a non-zero exit — the Stage 3→4 gate (Story 11.4) blocks
on it. Exit 2 = malformed map; exit 3 = attestation failure.
"""

import argparse
import hashlib
import re
import sys

PROV_CLASSES = ("sourced", "derived", "narration", "verify")
ATTEST_LINE = re.compile(r"^attestation:\s*draft-sha256=(?P<hash>[0-9a-fA-F]{64})\s*$")
GRADED_LINE = re.compile(r"^graded:\s*(?P<positions>\S.*)$")
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


def draft_sha256(draft_text):
    return hashlib.sha256(draft_text.encode("utf-8")).hexdigest()


def parse_attestation(text):
    """Split the verdicts file into (draft_hash, graded_set, verdict_lines).

    Returns (None, set(), lines) when no attestation header is present — the
    caller fails closed on that. `graded:` lines are unioned so the judge can
    echo the narration and derived listings' headers separately.
    """
    draft_hash, graded, verdicts = None, set(), []
    for raw in text.splitlines():
        ln = raw.strip()
        if not ln or ln.startswith("#"):
            continue
        m = ATTEST_LINE.match(ln)
        if m:
            draft_hash = m.group("hash").lower()
            continue
        m = GRADED_LINE.match(ln)
        if m:
            graded.update(p.strip() for p in m.group("positions").split(",") if p.strip())
            continue
        verdicts.append(ln)
    return draft_hash, graded, verdicts


def check_attestation(draft_hash, graded, entries, draft_text):
    """The fail-closed attestation checks (Story 13.67). Returns error strings."""
    errors = []
    if draft_hash is None:
        return ["no judge attestation found (`attestation: draft-sha256=<hex>` header) "
                "— absence of verdicts is never PASS; a comment-only or free-form file "
                "does not demonstrate that a judge ran"]
    worklist = {pos for pos, cls, _, _ in entries if cls in ("narration", "derived")}
    missing = sorted(worklist - graded)
    if missing:
        errors.append("attestation does not cover the expected worklist — ungraded "
                      f"position(s): {', '.join(missing)} (a partially-graded artifact "
                      "is not judged)")
    unknown = sorted(graded - {pos for pos, _, _, _ in entries})
    if unknown:
        errors.append(f"attestation grades position(s) not in the map: {', '.join(unknown)}")
    if draft_text is None:
        errors.append("attestation carries a draft hash but no --draft was given to "
                      "verify it against — pass --draft (fail closed)")
    elif draft_sha256(draft_text) != draft_hash:
        errors.append("draft-sha256 mismatch: the attestation was made over a different "
                      "draft version — verdicts for a prior draft never validate the "
                      "current one")
    return errors


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
    if args.list_narration or args.list_derived:
        cls_wanted = "narration" if args.list_narration else "derived"
        listed = [e for e in entries if e[1] == cls_wanted]
        # Attestation header the judge must echo verbatim at the top of its
        # verdicts file (Story 13.67): the draft hash binds the verdicts to
        # this draft version, the graded line to this worklist. Emitted only
        # with --draft — the hash does not exist without the draft.
        if args.draft:
            print(f"attestation: draft-sha256={draft_sha256(_read(args.draft))}")
            if listed:
                print(f"graded: {','.join(pos for pos, _, _, _ in listed)}")
        for pos, cls, ptrs, anchor in listed:
            text = anchored_text(anchor, draft_lines)
            if cls_wanted == "narration":
                print(f"{pos} [L{anchor}]: {text}" if text is not None else pos)
            else:
                head = f"{pos} [L{anchor}]" if text is not None else pos
                print(f"{head}: {', '.join(ptrs)}" + (f" | {text}" if text is not None else ""))
        return 0

    # --- attestation layer (Story 13.67, #364) — before any grading report ---
    # A verdicts file with no structured attestation, incomplete worklist
    # coverage, or the wrong draft hash fails closed here: "never judged" must
    # be mechanically distinguishable from "judged clean".
    verdict_lines = None
    if args.judge_findings:
        draft_text = _read(args.draft) if args.draft else None
        att_hash, graded, verdict_lines = parse_attestation(_read(args.judge_findings))
        att_errors = check_attestation(att_hash, graded, entries, draft_text)
        if att_errors:
            sys.stderr.write("verify-provenance: ATTESTATION FAILURE (not judged)\n")
            for e in att_errors:
                sys.stderr.write(f"  {e}\n")
            return 3

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
    if verdict_lines is not None:
        anchors = {pos: anchor for pos, _, _, anchor in entries}
        known = set(anchors)
        for ln in verdict_lines:
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
