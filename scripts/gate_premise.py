#!/usr/bin/env python3
"""gate_premise.py — the shared gate-item premise checker.

ONE implementation of the engine-wide gate-item content-grounding constraint
(SPEC-writing-assistant Constraints, added 2026-07-22 from triage #567):

    A machine-authored gate item asserts no factual premise without a
    resolvable pointer, or an inline `unverified —` marker at the point of use.

Extracted from `validate-needs-owner.py` (where #526 first shipped it for the
NEEDS-OWNER path) so every gate producer — NEEDS-OWNER items, interview items,
fork-gate candidates and FYIs, proposal payloads, review-arbitration findings,
visual proposals — validates through the SAME rule rather than four
re-derivations that drift, above all on the marker spelling the hub
deliberately decided once across surfaces. Stdlib only.

Three properties are load-bearing, and each is enforced here:

  (a) The marker spelling is exactly `unverified —` (EM DASH), inline, AT THE
      POINT OF USE — never a footnote the reader may skip. A hyphen lookalike
      (`unverified -`) is a NAMED rejection rather than a silent miss: it is
      the likeliest way the spelling drifts back apart.
  (b) The rule attaches to PREMISE CLAUSES specifically, not to an item's
      overall honesty. #526's item disclosed correctly at the top level
      (`not in declared sources`) and still smuggled a fabrication into a
      subordinate clause, so top-level candour is NOT a defence — and an
      honest top-level disclosure can actively make the invention read as
      licensed. Enforcement is therefore per clause.
  (c) A pointer-carrying premise validates under the same resolvable
      `path:line@sha` grammar as an evidence entry — reusing the fact-sheet
      machinery, never a second pointer parser.

An item that asserts no factual premise passes untouched: this module adds a
rejection class, never an authoring burden on premise-free items.
"""

import importlib.util
import os
import re

# The literal marker. EM DASH (U+2014), not a hyphen — the same spelling
# adopted for unverified operational references, decided once across both
# surfaces rather than twice.
UNVERIFIED_MARKER = "unverified —"
# The lookalike we reject loudly instead of missing quietly.
_HYPHEN_LOOKALIKE = re.compile(r"unverified\s*[-–]\s", re.IGNORECASE)
_MARKER_RE = re.compile(re.escape(UNVERIFIED_MARKER), re.IGNORECASE)

# Premise-assertion cues — a CLOSED, documented list, the same discipline
# `validate-interview-items.py`'s R4 restatement rule uses ("mechanical rule,
# documented, not vibes"). Each names a construction that asserts factual
# ground ABOUT THE WORLD, as opposed to asking a question about it. This is
# deliberately narrow: it is a floor that catches the known failure shape, not
# a semantic judge of arbitrary prose. Widening it is a spec change, not a
# tweak — the list is the contract.
PREMISE_CUES = (
    re.compile(r"\bdescribed\s+(?:internally|externally|publicly)?\s*as\b", re.I),
    re.compile(r"\b(?:known|referred\s+to|marketed|positioned|branded)\s+as\b", re.I),
    re.compile(r"\bthe\s+(?:team|owner|company|org|maintainers?)\s+"
               r"(?:calls?|call|considers?|treats?|describes?)\b", re.I),
    re.compile(r"\b(?:originally|initially)\s+(?:built|designed|written|created)\b", re.I),
    re.compile(r"\bwas\s+(?:built|designed|written|created|introduced)\s+(?:to|for|as)\b", re.I),
    re.compile(r"\bis\s+(?:documented|recorded|specified)\s+as\b", re.I),
)

# A pinned pointer appearing inline (the same shape a SOURCE carries). Its
# presence in a clause grounds that clause's premise.
_INLINE_POINTER_RE = re.compile(r"\S+:\d+(?:-\d+)?@[0-9a-f]{7,40}\b")

# Clause boundaries. A premise must be grounded AT ITS POINT OF USE, so the
# marker or pointer has to sit in the SAME clause as the cue — a marker three
# clauses away is the footnote this rule exists to forbid.
#
# Brackets are deliberately NOT boundaries: a parenthetical immediately after
# an assertion is the most natural place to put the marker, and treating it as
# a separate clause would reject the correct authoring shape.
_CLAUSE_SPLIT_RE = re.compile(r"[,;]|\.\s|—|\n")

# The marker itself contains an em dash, which is also a clause boundary, so it
# is masked out before splitting or the marker would be cut in half.
_MARKER_MASK = "\x00UNVERIFIED_MARKER\x00"


def _load_vfs():
    """Load `validate-fact-sheet.py` as a module (the shared-script idiom).

    The premise pointer is held to the fact-sheet SOURCE grammar so the two
    cannot diverge: reuse that grammar + git-resolution machinery rather than
    re-deriving a second pointer parser (#526)."""
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "vfs", os.path.join(here, "validate-fact-sheet.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_vfs = None


def vfs():
    """The fact-sheet module, loaded once on first use (keeps import cheap for
    callers that only need the inline scan)."""
    global _vfs
    if _vfs is None:
        _vfs = _load_vfs()
    return _vfs


# --------------------------------------------------------------------------
# The declared-clause form (moved from validate-needs-owner.py, #526)


def split_premise(raw, separator=" / "):
    """Pull an OPTIONAL trailing `premise:` clause off a slash-delimited item
    line. Returns (core, premise_value); `premise_value` is None when the item
    declares no premise, and `core` is then `raw` unchanged — so an item with
    no premise clause parses byte-identically to before."""
    segs = raw.split(separator)
    for i, s in enumerate(segs):
        if s.strip().startswith("premise:"):
            core = separator.join(segs[:i]).rstrip()
            clause = separator.join(segs[i:]).strip()
            return core, clause[len("premise:"):].strip()
    return raw, None


def validate_premise(value, host=None, sources=None):
    """Validate a DECLARED premise value. Returns None if it passes, else a
    NAMED rejection reason (#526).

      * `unverified` (literal) or the inline `unverified —` marker
                                      -> PASS (an open question, not a claim);
      * a pinned fact-sheet pointer   -> PASS structurally; when host/sources
        context is present, also RESOLVED at the commit;
      * anything else                 -> a named rejection (`confabulated-premise`
        for prose/malformed, `unpinned-premise-pointer` for a bare path:line).
    """
    v = value.strip()
    if v == "unverified" or _MARKER_RE.match(v):
        return None
    if _HYPHEN_LOOKALIKE.match(v):
        return ("marker-spelling: the unverified marker is spelled "
                f"`{UNVERIFIED_MARKER}` with an EM DASH — a hyphen variant is "
                "rejected so the spelling stays identical across surfaces")
    # Grammar gate: the same atomic SOURCE forms a fact sheet accepts, single
    # line (kind 'event' is not span-eligible, so a premise pins one line).
    if vfs().source_form_ok(v, "event"):
        if host is not None and sources is not None:
            return vfs().validate_source(v, "event", v, host, sources)
        return None                      # structural pass — pin present
    if re.match(r"^\S.*:\d+(-\d+)?$", v):
        return ("unpinned-premise-pointer: premise pointer is not pinned to a "
                "commit (use path:line@sha, the fact-sheet SOURCE grammar) — or "
                f"mark `{UNVERIFIED_MARKER}` if the factual ground is an open question")
    return ("confabulated-premise: a premise asserted as fact must be "
            "a resolvable pointer (path:line@sha) or explicitly marked "
            f"`{UNVERIFIED_MARKER}` — undeclared/prose factual ground is not evidence")


# --------------------------------------------------------------------------
# The inline form (#567): a premise smuggled into the item's own prose


def clauses(text):
    """Split `text` into clauses for point-of-use checking, with the marker
    masked so its own em dash never splits it."""
    masked = _MARKER_RE.sub(_MARKER_MASK, str(text))
    return [c.replace(_MARKER_MASK, UNVERIFIED_MARKER)
            for c in _CLAUSE_SPLIT_RE.split(masked)]


def grounded(clause):
    """Is this clause's factual ground declared AT ITS POINT OF USE — either an
    inline `unverified —` marker or a pinned pointer inside the same clause?"""
    return bool(_MARKER_RE.search(clause) or _INLINE_POINTER_RE.search(clause))


def scan_inline(text):
    """Every ungrounded premise assertion in `text`, as a list of named
    rejection reasons (empty = clean).

    Checked PER CLAUSE, so a correct top-level disclosure elsewhere in the item
    is no defence — that is exactly the #526 shape, where an item disclosed
    `not in declared sources` at the top level and still asserted an invented
    premise in a subordinate clause.
    """
    reasons = []
    for clause in clauses(text):
        if _HYPHEN_LOOKALIKE.search(clause):
            reasons.append(
                "marker-spelling: the unverified marker is spelled "
                f"`{UNVERIFIED_MARKER}` with an EM DASH — a hyphen variant is "
                f"rejected so the spelling stays identical across surfaces: {clause.strip()!r}")
            continue
        if grounded(clause):
            continue
        for cue in PREMISE_CUES:
            m = cue.search(clause)
            if m:
                reasons.append(
                    f"confabulated-premise: the clause asserts a factual premise "
                    f"({m.group(0).strip()!r}) with no resolvable pointer and no "
                    f"inline `{UNVERIFIED_MARKER}` marker at the point of use — "
                    f"a gate item's premise is evidence, not license to invent "
                    f"the ground an owner might ratify while skimming: {clause.strip()!r}")
                break
    return reasons


def check(text, declared_premise=None, host=None, sources=None):
    """The whole rule for one gate item: the inline scan over its owner-facing
    text, plus the declared `premise:` clause when the item carries one.
    Returns a list of named rejection reasons (empty = the item passes)."""
    reasons = list(scan_inline(text))
    if declared_premise is not None:
        reason = validate_premise(declared_premise, host, sources)
        if reason:
            reasons.append(reason)
    return reasons
