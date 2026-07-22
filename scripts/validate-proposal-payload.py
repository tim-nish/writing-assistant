#!/usr/bin/env python3
"""Validate an owner-facing proposal payload before it is presented (Story 10.1,
owner-facing proposal contract (e)).

Every proposal surface — gap interview, review arbitration, Stage-4
verification, visual proposals — assembles a payload and must pass it through
this gate before showing it to the owner. The gate is mechanical and blocks
presentation the way `verify-markers` blocks stage progression: a payload with a
missing Effect line, an empty field, a field truncated mid-sentence, or an
UNGROUNDED FACTUAL PREMISE in its owner-facing prose (#567) is NOT presentable,
so the damaged prompt never ships.

Premise grounding (added 2026-07-22, #567) is the engine-wide gate-item
content-grounding rule, implemented once in `gate_premise.py`: a machine-authored
gate item asserts no factual premise without a resolvable pointer or an inline
`unverified —` marker at the point of use. Because all four surfaces above
present through THIS gate, wiring it here covers them all.

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
stating a non-empty Effect. Every presented string field must also be plain
text (contract (g), #300): Markdown markers the selection surface cannot
render — `**`/`__` emphasis, backticks, `#` headings, `[text](url)` links —
block presentation with a per-field diagnostic naming the marker and its
location. Each field must be present, non-empty, and
untruncated. "Untruncated" is enforced two ways: a field ending in an ellipsis
(`…` or `...`) is a mid-sentence cut, and a field longer than its display budget
is a failure — content is made to fit by AUTHORSHIP (write shorter), never by
clipping. Budgets live here, with the implementation, not in the contract prose
(interview-architecture.md O2).

Exit 0 = presentable; non-zero = blocked, with a per-field report.
"""

import argparse
import importlib.util
import json
import os
import re
import sys

# Display budgets (characters). Illustrative caps tied to the presentation
# mechanism, kept with the implementation per interview-architecture O2.
BUDGETS = {"where": 240, "why": 200, "effect": 140}
ELLIPSES = ("…", "...")

# Plain-text payload contract (g), #300: the selection surface renders no
# Markdown, so these markers are a blocking defect in ANY presented field —
# same posture as a missing Effect line. Allowed conventions (indentation,
# `-` dashes, CAPITALIZATION, blank-line separation) match none of these.
FORBIDDEN_MARKERS = (
    ("bold emphasis", re.compile(r"\*\*")),
    ("underline emphasis", re.compile(r"__")),
    ("backtick markup", re.compile(r"`")),
    ("heading marker", re.compile(r"^\s{0,3}#{1,6}\s", re.MULTILINE)),
    ("markdown link", re.compile(r"\[[^\]]+\]\([^)\s]+\)")),
)


def _iter_strings(obj, path):
    """Yield (path, value) for every string field under obj."""
    if isinstance(obj, str):
        yield path, obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield from _iter_strings(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _iter_strings(v, f"{path}[{i}]")


def _markup_errors(item, tag):
    """Yield (path, reason) for every forbidden formatting marker in any
    presented string field of `item` (contract (g))."""
    for path, value in _iter_strings(item, tag):
        for name, rx in FORBIDDEN_MARKERS:
            m = rx.search(value)
            if m:
                line = value.count("\n", 0, m.start()) + 1
                col = m.start() - value.rfind("\n", 0, m.start())
                yield (path, f"forbidden marker {m.group(0)!r} ({name}) at "
                             f"line {line} col {col} — the surface renders "
                             "plain text only (contract (g)); use indentation, "
                             "dashes, or CAPITALIZATION instead")


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


def _load_gp():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "gate_premise", os.path.join(here, "gate_premise.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_gp = None


def gp():
    global _gp
    if _gp is None:
        _gp = _load_gp()
    return _gp


# The owner-facing strings of a proposal item — every field the owner READS and
# ratifies. The premise rule binds gate-item CONTENT, so it runs over exactly
# these (SPEC-writing-assistant, "Gate-item content grounding", #567).
PREMISE_FIELDS = ("where", "why")


def _premise_errors(item, tag):
    """Every ungrounded factual premise in an item's owner-facing prose.

    This one call site covers FOUR proposal surfaces — gap interview, review
    arbitration, Stage-4 verification, and visual proposals — because they all
    assemble their payload through this gate before presenting.
    """
    for field in PREMISE_FIELDS:
        value = item.get(field)
        if not isinstance(value, str):
            continue
        for reason in gp().scan_inline(value):
            yield (f"{tag}.{field}", reason)
    for j, ch in enumerate(item.get("choices") or []):
        effect = ch.get("effect") if isinstance(ch, dict) else None
        if not isinstance(effect, str):
            continue
        for reason in gp().scan_inline(effect):
            yield (f"{tag}.choices[{j}].effect", reason)


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
        yield from _markup_errors(item, tag)
        yield from _premise_errors(item, tag)
        choices = item.get("choices")
        if not isinstance(choices, list) or not choices:
            yield (f"{tag}.choices", "no choices — selective presentation requires effect-stating options")
            continue
        for j, ch in enumerate(choices):
            effect = ch.get("effect") if isinstance(ch, dict) else None
            reason = _truncation_error("effect", effect, BUDGETS["effect"])
            if reason:
                yield (f"{tag}.choices[{j}].effect", reason)


CAPTURE_FILE = "presented-payloads.jsonl"


def _capture_append(ws, record):
    """Append one record to the run's presented-payload log (append-only,
    verbatim — SPEC-draft-article-ux CAP-2, Story 13.28) and return its
    1-based ask_id (the line number). The log lives in the run workspace,
    never the host tree."""
    path = os.path.join(ws, CAPTURE_FILE)
    try:
        with open(path, encoding="utf-8") as f:
            n = sum(1 for _ in f)
    except OSError:
        n = 0
    record = dict(record, ask_id=record.get("ask_id", n + 1))
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
    return record["ask_id"]


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("payload", nargs="?", default="-",
                   help="proposal payload JSON file, or - for stdin")
    p.add_argument("--ws", help="run workspace: on a presentable payload, append "
                   "it verbatim to <ws>/presented-payloads.jsonl and print its "
                   "ask_id (Story 13.28); a blocked payload is never captured")
    p.add_argument("--surface", default="unspecified",
                   help="which owner-facing surface is asking (interview, "
                   "visual-proposal, verification, arbitration)")
    p.add_argument("--answer", type=int, metavar="ASK_ID",
                   help="record-answer mode: append the owner's selection + free "
                   "text (JSON on stdin or in PAYLOAD) for the given ask_id; "
                   "requires --ws, skips payload validation")
    args = p.parse_args(argv)

    raw = sys.stdin.read() if args.payload == "-" else open(args.payload, encoding="utf-8").read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: payload is not valid JSON: {e}\n")
        return 2

    if args.answer is not None:
        if not args.ws:
            sys.stderr.write("error: --answer requires --ws\n")
            return 2
        _capture_append(args.ws, {"kind": "answer", "ask_id": args.answer,
                                  "answer": payload})
        print(json.dumps({"ok": True, "kind": "answer", "ask_id": args.answer}))
        return 0

    defects = list(validate(payload))
    if not defects:
        if args.ws:
            ask_id = _capture_append(args.ws, {"kind": "ask",
                                               "surface": args.surface,
                                               "payload": payload})
            print(json.dumps({"ok": True, "kind": "ask", "ask_id": ask_id}))
        else:
            print("payload OK: presentable (where/why/effect present, non-empty, within budget)")
        return 0
    sys.stderr.write("payload BLOCKED — not presentable:\n")
    for path, reason in defects:
        sys.stderr.write(f"  {path}: {reason}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
