#!/usr/bin/env python3
"""pin-denial-lists.py — emit the pinned inventory of every enumerated denial
list on the owner surface (Story 20.27, #862).

The inventory is what `check-denial-list-growth.sh` compares against, so it is
GENERATED rather than hand-maintained: a hand-edited pin is a second authority
on what the lists contain, and it would drift silently — which is the failure
shape this whole register contract exists to leave behind.

    python3 scripts/pin-denial-lists.py > scripts/denial-list-inventory.txt

Re-pinning is a deliberate act with a visible diff. That is the point: growing
a denial list is prohibited as the response to a register leak
(`specs/spec-writing-assistant/SPEC.md`, owner-surface register, property (a)),
so the re-pin is where a reviewer sees the prohibition being invoked.

Stdlib-only. Exit codes: 0 ok · 1 a list could not be read.
"""

import importlib.util
import sys

# The enumerated denial lists, by the module that owns each. Adding a THIRD
# list here is itself worth a second look: the contract demotes these to a
# cheap first pass, so a new one is a new instance of the remedy shape rather
# than a new tool.
SOURCES = (
    ("scripts/topic-map-directions.py", "INTERNAL_VOCAB", lambda v: list(v)),
    ("scripts/validate-proposal-payload.py", "FORBIDDEN_MARKERS",
     lambda v: [name for name, _rx in v]),
)

HEADER = """\
# The PINNED INVENTORY of every enumerated denial list on the owner
# surface, as of Story 20.27 (#862). Generated, never hand-edited:
#   python3 scripts/pin-denial-lists.py > scripts/denial-list-inventory.txt
#
# Growing a list here is PROHIBITED as the response to a register leak
# (SPEC-writing-assistant, owner-surface register, property (a)). The
# lists are demoted, not deleted: they remain the cheap deterministic
# first pass for the sub-class they were built for — coined identifiers.
# To admit a genuinely correct addition, put an adjacent
#   # register-exemption: <which leak, and why it is a coined identifier>
# comment on the entry's own line, then re-pin."""


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    lines = [HEADER]
    for path, attr, extract in SOURCES:
        try:
            module = _load(path, attr.lower())
            values = extract(getattr(module, attr))
        except (OSError, AttributeError, ValueError) as exc:
            sys.stderr.write(f"error: cannot read {attr} from {path}: {exc}\n")
            return 1
        for value in values:
            lines.append(f"{attr}\t{value}")
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
