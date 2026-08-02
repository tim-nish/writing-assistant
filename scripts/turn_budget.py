"""The owner-surface information budget (Story 20.153, #1225).

WHAT THE OWNER ACTUALLY READ. On the 2026-08-02 run, after entering "share
engineering lessons", the owner read about FIVE lines out of the hundreds that
scrolled past. Everything else — anchor tables, coverage ledgers, pin
inventories, contract-mismatch narration, stage bookkeeping — was volume
between them and the next decision.

THE RULE IS A DEFAULT-DENY ON TURN CONTENT, deliberately not a list of
suppressed items. An enumerated list of banned relays would be the shape
`SPEC.md:80` clause (a) prohibits, and it would go stale the first time a new
table was invented. What binds instead: an owner-facing turn carries at most
ONE STATUS LINE plus the DECISION PAYLOAD if a gate is due. Everything else
goes to the run workspace behind one pointer line.

WHY THIS IS MEASURABLE WHERE VOCABULARY WAS NOT. `SPEC.md:80` records that
this repository cannot constrain the relay layer absolutely — the agent's
composition step is not ours. That argument is about WORDING. Volume is not
wording: a line count is mechanical, and story 20.151's Stop hook runs at the
layer where the turn actually ends. So the rule is stated here and MEASURED
there; the hook never defines it.

THE BUDGET IS DECLARED WITH ITS MEASUREMENT, never asserted. The story requires
the number to carry what it was set from, because a threshold with no evidence
behind it is re-argued at every sitting by whoever finds it inconvenient.
"""

# The budget, and the measurement it comes from.
#
# MEASURED, 2026-08-02 (run 20260802T090323-217675): the owner reported reading
# "about five lines" of the hundreds emitted, and the lines that mattered were
# a status line plus the decision itself. So the budget is set at the observed
# useful volume rather than at a round number: ONE status line, plus whatever
# the gate payload occupies, plus one pointer line to the workspace.
#
# The payload is EXCLUDED from the count on purpose. It is the decision, it is
# already budgeted field-by-field by `validate-proposal-payload.py`, and
# counting it here would make two mechanisms fight over the same text.
STATUS_LINES = 1
POINTER_LINES = 1

# What a turn may carry outside a gate payload. Exceeding it is a FINDING, not
# a crash: the hook reports, the owner sees the count, and the rule stays a
# rule rather than becoming a wall.
TURN_LINE_BUDGET = STATUS_LINES + POINTER_LINES

# Where the displaced material goes. One file, mentioned once at sitting end —
# not a second channel the owner has to remember to check.
FINDINGS_FILE = "findings.md"

# The debug channel is OPT-IN and OFF BY DEFAULT (the story's clause 2). An
# env var rather than a config key: verbosity is a property of one sitting, not
# a durable preference, and a durable preference is exactly what would silently
# re-flood the surface months later.
DEBUG_ENV = "WA_VERBOSE"


def debug_enabled(env=None):
    """True when the owner asked for the debug channel THIS SITTING."""
    import os
    src = os.environ if env is None else env
    return str(src.get(DEBUG_ENV, "")).strip().lower() in ("1", "true", "yes", "on")


def count_lines(text):
    """The owner-facing lines in a relay block.

    Blank lines do not count: they are layout, and counting them would make
    the budget punish readability, which is the opposite of the point.
    """
    if not text:
        return 0
    return len([ln for ln in str(text).splitlines() if ln.strip()])


def over_budget(text, budget=TURN_LINE_BUDGET):
    """`(over, count)` for a turn's non-payload text.

    Returns the count either way so a caller can report the actual number
    rather than only the verdict — "12 lines against a budget of 2" is
    actionable where "over budget" is not.
    """
    n = count_lines(text)
    return n > budget, n


def essential_with_reason(line, reason):
    """The story's clause 3, as a constructor rather than a checker.

    Any line shown outside a gate payload must be classifiable as "changes what
    the owner should decide next", WITH the reason stated. Making it a
    constructor is the constrain move: a caller that cannot supply a reason
    cannot build the line, so the unclassifiable case is unrepresentable rather
    than caught later.
    """
    line = " ".join(str(line or "").split())
    reason = " ".join(str(reason or "").split())
    if not line:
        raise ValueError("an owner-facing line is not empty")
    if not reason:
        raise ValueError(
            "an owner-facing line outside a gate payload carries the reason it "
            "changes what the owner decides next; if the reason cannot be "
            "stated, the line belongs in the workspace")
    return line


def pointer(path):
    """The ONE line that replaces everything displaced to the workspace."""
    return f"Detail for this run: {path}"
