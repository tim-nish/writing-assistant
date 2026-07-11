#!/usr/bin/env python3
"""Validate an owner-facing proposal payload before it is presented (Story 10.1,
owner-facing proposal contract (e)).

Every proposal surface — gap interview, review arbitration, Stage-4
verification, visual proposals — assembles a payload and must pass it through
this gate before showing it to the owner. The gate is mechanical and blocks
presentation the way `verify-markers` blocks stage progression: a payload with a
missing Effect line, an empty field, or a field truncated mid-sentence is NOT
presentable, so the damaged prompt never ships.

Payload shape (JSON) — one proposal item, or a list under `items`:

    {
      "items": [
        {
          "where":  "Section 2 (Evidence) — currently: 'Throughput rose 2x ...'",
          "why":    "The single result that matters most is not stated",
          "choices": [
            {"label": "approve", "effect": "keep the section as drafted"},
            {"label": "modify",  "effect": "rewrite the section from your answer"}
          ]
        }
      ]
    }

Each item must carry Where and Why, and at least one choice, every choice
stating a non-empty Effect. Each field must be present, non-empty, and
untruncated. "Untruncated" is enforced two ways: a field ending in an ellipsis
(`…` or `...`) is a mid-sentence cut, and a field longer than its display budget
is a failure — content is made to fit by AUTHORSHIP (write shorter), never by
clipping. Budgets live here, with the implementation, not in the contract prose
(interview-architecture.md O2).

Exit 0 = presentable; non-zero = blocked, with a per-field report.
"""

import argparse
import json
import sys

# Display budgets (characters). Illustrative caps tied to the presentation
# mechanism, kept with the implementation per interview-architecture O2.
BUDGETS = {"where": 240, "why": 200, "effect": 140}
ELLIPSES = ("…", "...")


def _truncation_error(field, value, budget):
    """Return a reason string if `value` is missing/empty/truncated/over budget,
    else None."""
    if value is None or not str(value).strip():
        return "missing or empty"
    v = str(value).rstrip()
    if v.endswith(ELLIPSES):
        return "truncated (ends in an ellipsis — re-author, do not clip)"
    if len(v) > budget:
        return f"over the {budget}-char display budget ({len(v)}) — write it shorter"
    return None


def validate(payload):
    """Yield (path, reason) for every defect; empty iterator means presentable."""
    if isinstance(payload, dict) and "items" in payload:
        items = payload["items"]
    elif isinstance(payload, list):
        items = payload
    else:
        items = [payload]

    if not items:
        yield ("payload", "no proposal items to present")
        return

    for i, item in enumerate(items):
        tag = f"item[{i}]"
        if not isinstance(item, dict):
            yield (tag, "item is not an object")
            continue
        for field in ("where", "why"):
            reason = _truncation_error(field, item.get(field), BUDGETS[field])
            if reason:
                yield (f"{tag}.{field}", reason)
        choices = item.get("choices")
        if not isinstance(choices, list) or not choices:
            yield (f"{tag}.choices", "no choices — selective presentation requires effect-stating options")
            continue
        for j, ch in enumerate(choices):
            effect = ch.get("effect") if isinstance(ch, dict) else None
            reason = _truncation_error("effect", effect, BUDGETS["effect"])
            if reason:
                yield (f"{tag}.choices[{j}].effect", reason)


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("payload", nargs="?", default="-",
                   help="proposal payload JSON file, or - for stdin")
    args = p.parse_args(argv)

    raw = sys.stdin.read() if args.payload == "-" else open(args.payload, encoding="utf-8").read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: payload is not valid JSON: {e}\n")
        return 2

    defects = list(validate(payload))
    if not defects:
        print("payload OK: presentable (where/why/effect present, non-empty, within budget)")
        return 0
    sys.stderr.write("payload BLOCKED — not presentable:\n")
    for path, reason in defects:
        sys.stderr.write(f"  {path}: {reason}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
