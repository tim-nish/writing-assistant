"""The owner-surface seam — the one composition point an owner-facing PATH
passes through (Story 20.115, #1117).

WHAT THIS IS AN INSTANCE OF. `SPEC-writing-assistant` §Owner-surface register
fixed this seam's LOCATION and MECHANISM and left exactly one thing open:

    "What remains genuinely open is only the implementation shape — function,
     type wrapper, or render stage — which is this repository's call and is an
     open question here rather than an invented contract; reopen trigger: a
     surface being built that needs the seam to exist."

#1117 is that trigger. The clause also fixes what may not be done instead:
CONSTRAIN over DETECT, and an enumerated denial list is *prohibited* as the
remedy for a register leak, because "a denial list's non-member fallback is
ADMIT, so the defect is in the shape rather than in any list's contents."

WHY A TYPE AND NOT A LINT. What shipped for #1073 was a code comment plus one
check scoped to the View pointer — the per-surface shape — and a second surface
leaked with nothing failing. The failure mode is not that someone typed a bad
path; it is that a path is a `str`, and a `str` can be interpolated into a
sentence, where line-wrapping and elision then happen to it. `ArtifactPath`
makes that the thing you cannot do by accident: it renders as a BLOCK, and the
one method that returns a bare string is named so nobody reaches for it without
meaning to.

SCOPE, STATED SO IT IS NOT OVER-READ. This governs ARTIFACT paths — locations
the owner is expected to open. It does not govern evidence pointers such as
`LESSONS.md:25`, which `_short_path` deliberately abbreviates for a trailing
annotation; that helper's justification ("the full path stays in `map.json`")
is sound for an annotation and unsound for an instruction, which is the
distinction #1073 already drew and this module keeps.

HONEST LIMIT. This constrains what this repository COMPOSES. It cannot
constrain a terminal's own column wrap — but a path alone on its line is the
form that survives wrapping, which is the whole reason the rule is "on its own
line" rather than merely "whole".
"""

__all__ = ["ArtifactPath", "artifact_block", "is_elided"]

# The visible cut used everywhere in this codebase for a deliberate truncation.
# An artifact path may never carry it: a path with a cut in it is unopenable,
# and "unopenable" is the defect, not the cosmetics.
ELLIPSIS = "…"


class ArtifactPath(str):
    """A path the owner is expected to OPEN.

    It is a `str` subclass so it can be passed, joined and compared like any
    path — what it adds is that every owner surface in this repository asks it
    how to render, and the answer is always a block, never a fragment of a
    sentence.
    """

    __slots__ = ()

    def block(self, label, note=None):
        """The sanctioned rendering: label, then the path ALONE on its line.

        `note` is the sentence that would otherwise have swallowed the path —
        it goes after, never around, so no composition can put text on the
        path's line.
        """
        lines = [f"{label}:", str(self)]
        if note:
            lines.append(note)
        return "\n".join(lines)

    def bare(self):
        """The raw string, for machine consumers (JSON payloads, os.path).

        Named to be conspicuous at a call site: reaching for `.bare()` on an
        owner surface is the thing review should catch, and it reads as a
        decision rather than as an accident.
        """
        return str(self)


def artifact_block(label, path, note=None):
    """Render any path as an artifact block, wrapping if needed.

    Callers that already hold a plain `str` get the same guarantee without
    having to construct the type first — the seam admits, it does not gate.
    """
    p = path if isinstance(path, ArtifactPath) else ArtifactPath(str(path))
    return p.block(label, note)


def is_elided(text):
    """True when an owner surface put a visible cut next to a path.

    The DETECT fast path beneath the constraint, per §Owner-surface register(b)
    — the enumerated form is demoted, never deleted. Deliberately mechanical:
    it decides a shape, reads no intent, and so is an ordinary check rather
    than a judgment riding a gate.
    """
    if ELLIPSIS not in str(text):
        return False
    for line in str(text).split("\n"):
        if ELLIPSIS not in line:
            continue
        # A cut is a path-cut when it sits directly against a separator — the
        # `…/foo` and `/foo…` shapes the 2026-08-01 run emitted. Prose that
        # merely ends in an ellipsis is not a path and is not this rule's
        # business.
        for i, ch in enumerate(line):
            if ch != ELLIPSIS:
                continue
            before = line[i - 1] if i else ""
            after = line[i + 1] if i + 1 < len(line) else ""
            if before == "/" or after == "/":
                return True
    return False
