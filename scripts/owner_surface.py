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

import json

__all__ = ["ArtifactPath", "artifact_block", "is_elided",
           "completion_summary", "product_handover", "BUCKETS",
           "HANDOVER_PRODUCTS"]

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

# --- The composed block (Story 20.123, #1137) --------------------------------
#
# THE TYPED VALUE WAS NECESSARY AND NOT SUFFICIENT. `ArtifactPath` guarantees
# how a path renders; it cannot stop a relay composing a sentence AROUND it,
# and on 2026-08-01 exactly that happened — the brief path reached the owner
# elided *after* #1117 merged, "all declared sources" was relayed as "all of
# it", and a completion summary was headed "Three things you should know", a
# phrase that exists nowhere in this repository.
#
# THE REMEDY IS THE ONE THE SERVED POSITION NAMES: shrink the free-form surface
# rather than lint it. A surface composed as ONE BLOCK leaves no string for a
# relay to rewrite, and the skill's instruction becomes *print this block*.
# Screen 2 has worked this way since #976/#977, for this exact failure; this
# is that shape made available to the surfaces still assembled in prose.
#
# HONEST LIMIT, restated because it bounds the claim: a block can still be
# paraphrased. What this removes is the EXCUSE, not the ability — the
# measurable property is that every owner surface has a composed block behind
# it, not that no leak can occur.

# The three labelled buckets `skills/completion-summary.md` mandates. Declared
# here so the composer cannot be called with a fourth, and so the headings are
# one string rather than N paraphrases.
BUCKETS = ("informational notes", "publish blockers", "optional cleanup")


# --- The handover block (Story 20.194, #1335) --------------------------------
#
# THE PATHS WERE EMITTED AND THE HANDOVER STILL FAILED. On run
# 20260803T105759-992700 both products persisted, zero blockers, and the owner
# reported *"No file path was shown, so I cannot see the generated artifact."*
# The paths were line 2 of the informational bucket inside 17 owner-facing
# lines. Whether a person finds a signal is a property of its FIXED POSITION,
# not of its presence — so this is a position rule, not another sentence in a
# bucket (amended 2026-08-03, `specs/spec-article-draft-pipeline/amendments.md`).
#
# RENDERED, NEVER COMPOSED. The input is `complete`'s own JSON: a path a run
# types is a path a run can mistype. There is no second store — `cmd_complete`
# already returns both persisted absolute paths and this reads them.

# The two declared products of a draft run, in handover order, with the label
# the owner reads. Declared here so the block cannot name one and forget the
# other.
HANDOVER_PRODUCTS = (("canonical", "draft"), ("plan", "plan"))


def product_handover(complete_json, blockers=()):
    """The completion summary's FIRST BLOCK: both persisted product paths.

    `complete_json` is what `draft-pipeline.py complete` printed — the parsed
    dict or its raw stdout. Returns None when it carries no completed run:
    unparseable output, a missing `products` key, or a product with no path.
    A `complete` that FAILED prints no JSON at all, so there is nothing to
    hand over and no path line is emitted; the gate's hard error is what the
    owner is owed instead.

    THE ORDERING AGAINST THE BLOCKER BUCKET IS DECLARED, NOT INCIDENTAL. This
    block precedes every bucket, publish blockers included — and because a
    blocker is the one thing that outranks the handover, the block's last line
    NAMES the blocker count when there is one. That is the tie-break the
    amendment asks for: fixed position for the handover, and no run where the
    first thing read hides the fact that the draft must not be published yet.
    """
    data = complete_json
    if isinstance(data, (str, bytes)):
        try:
            data = json.loads(data)
        except (ValueError, TypeError):
            return None
    if not isinstance(data, dict):
        return None
    products = data.get("products")
    if not isinstance(products, dict):
        return None
    lines = []
    for key, label in HANDOVER_PRODUCTS:
        entry = products.get(key)
        path = entry.get("path") if isinstance(entry, dict) else None
        if not path:
            return None
        lines.append(artifact_block(label, path))
    n = len([b for b in blockers if str(b).strip()])
    if n:
        lines.append(f"{n} publish blocker(s) below — do not publish yet.")
    return "\n".join(lines)


def completion_summary(stage, notes=(), blockers=(), cleanup=(), next_step=None,
                       complete_json=None):
    """The completion summary, composed — never assembled in chat.

    Every bucket renders, including an empty one: "publish blockers: none" is a
    fact the owner needs, and a bucket that disappears when empty is
    indistinguishable from a bucket nobody filled. That is the same
    non-member-disclosure rule the rest of this surface follows.

    `next_step` is the in-conversation choice the interaction contract requires
    (CAP-6, #226). It is rendered as a line here and asked through the gate
    carrier; this composer states it, it does not ask it.

    `complete_json` is `complete`'s output; given it, the handover block heads
    the summary ahead of every bucket. Passing something this composer cannot
    read both paths out of RAISES rather than silently dropping the block — a
    handover that vanished is the defect #1335 reports, and a summary printed
    over a failed `complete` would report a completion that did not happen.
    """
    lines = []
    if complete_json is not None:
        head = product_handover(complete_json, blockers=blockers)
        if head is None:
            raise ValueError(
                "complete_json carries no completed run — both product paths "
                "must be readable from `complete`'s JSON. A failed `complete` "
                "has no completion to summarize: surface its hard error")
        lines += [head, ""]
    lines += [f"{stage} — complete.", ""]
    for label, items in zip(BUCKETS, (notes, blockers, cleanup)):
        items = [str(i).strip() for i in items if str(i).strip()]
        if items:
            lines.append(f"{label}:")
            lines += [f"  - {i}" for i in items]
        else:
            lines.append(f"{label}: none")
        lines.append("")
    if next_step:
        lines.append(str(next_step).strip())
    return "\n".join(lines).rstrip() + "\n"
