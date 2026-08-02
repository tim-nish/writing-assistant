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

The ANSWER half (`--answer <ask_id>`, added 2026-07-25, #694) is validated too:
the recorded answer is the other half of the interaction this gate protects, and
its shape is contract — "the owner's selection + free text" (SPEC-draft-article-ux
CAP-2). A non-empty `selection` string is required, `free_text` must be a string
when present, and a blocked answer is never captured. Which selection VALUES are
legal stays with the consuming gate (shape, not vocabulary), and the presented-text
rules above deliberately do NOT apply to an owner's own words.

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


# The host selection control admits 2-4 options. Mirrors
# `draft_gates.CONTROL_CAPACITY`, which is the builder's copy; this file is the
# enforcing one and the carrier check asserts the two agree.
CONTROL_CAPACITY = 4

# A choice set exceeding the capacity by at most this margin is still a
# selection, with the members past the capacity declared in `render.overflow`
# and named in the question text (amended 2026-08-02, #1206). Mirrors
# `draft_gates.OVERFLOW_MARGIN`; the carrier check asserts the two agree.
OVERFLOW_MARGIN = 2


def _render_errors(item, tag, choices):
    """Yield (path, reason) for a `render` directive's shape (Story 20.107).

    ABSENCE IS NOT CHECKED HERE. This function validates the directive when one
    is present; requiring it is `--require-render`'s job, because this
    validator gates every proposal surface in the repository and the terrain
    screens do not emit a directive until Story 20.108. Making it mandatory
    here would have turned one story's tightening into another story's
    breakage, which is how a carrier acquires a reputation for being in the
    way.
    """
    render = item.get("render")
    if render is None:
        return
    if not isinstance(render, dict):
        yield (f"{tag}.render", "render is not an object")
        return
    control = render.get("control")
    if control not in ("selection", "block"):
        yield (f"{tag}.render.control",
               f"is {control!r}; expected 'selection' or 'block'")
        return
    n = len(choices)
    expected = ("selection" if n <= CONTROL_CAPACITY + OVERFLOW_MARGIN
                else "block")
    if control != expected:
        yield (f"{tag}.render.control",
               f"is {control!r} but {n} choices against a capacity "
               f"of {CONTROL_CAPACITY} (margin {OVERFLOW_MARGIN}) make it "
               f"{expected!r} — control is "
               "computed from the choice count, never authored")
    # A small overflow is DISCLOSED, never hidden (#1206): declared only
    # within the margin, matching the tail of the ordered choice set, each
    # member named in the question text the owner reads.
    overflow = render.get("overflow")
    if overflow is not None:
        if control == "block" or n <= CONTROL_CAPACITY:
            yield (f"{tag}.render.overflow",
                   "is declared outside the margin — overflow belongs only "
                   "to a selection whose choices exceed the capacity by at "
                   f"most {OVERFLOW_MARGIN}")
        elif not isinstance(overflow, list):
            yield (f"{tag}.render.overflow", "is not a list of labels")
        else:
            tail = [str((c or {}).get("label", "")) if isinstance(c, dict)
                    else "" for c in choices[CONTROL_CAPACITY:]]
            if overflow != tail:
                yield (f"{tag}.render.overflow",
                       f"is {overflow!r} but the members past the capacity "
                       f"are {tail!r} — overflow is the ordered tail, never "
                       "authored")
            question = f"{item.get('where', '')} {item.get('why', '')}"
            for label in overflow:
                if label and label not in question:
                    yield (f"{tag}.render.overflow",
                           f"member {label!r} is not named in the question "
                           "text — an overflow is disclosed, never hidden")
    elif control == "selection" and n > CONTROL_CAPACITY:
        yield (f"{tag}.render.overflow",
               f"is missing — {n} choices against a capacity of "
               f"{CONTROL_CAPACITY} put the tail past the control, and an "
               "undeclared tail is hidden, not overflowed")
    rec = render.get("recommended")
    if rec is not None:
        if not isinstance(rec, int) or isinstance(rec, bool):
            yield (f"{tag}.render.recommended",
                   "is not an index — a label drifts when wording changes")
        elif rec != 0:
            yield (f"{tag}.render.recommended",
                   f"is {rec}; a recommended option leads, so it is index 0")
    for field in ("banner", "reply_line"):
        present = render.get(field)
        if control == "block" and not present:
            yield (f"{tag}.render.{field}",
                   "a block carries its own banner and reply line; without "
                   "them the renderer composes them itself")
        if control == "selection" and present:
            yield (f"{tag}.render.{field}",
                   "belongs to the block form; this payload fits the control")


# --- DECIDABILITY (Story 20.152, #1222) ----------------------------------
# The THIRD axis on a gate item. The owner-facing proposal contract binds an
# ask's FORM (`SPEC.md:76`), gate-item content grounding binds its PREMISES
# (`:79`), and the owner-surface register binds its REGISTER (`:80`). None of
# them tests whether the recipient can DECIDE. On 2026-08-02 a run was
# abandoned at Stage 3 after the owner answered several gates by picking the
# first option every time — "I selected the first option because the question
# was incomprehensible" — and every shipped check passed. The recorded answers
# were then consumed downstream as authoritative, which is why this is a
# correctness rule and not a politeness one.
#
# THE SPLIT IS THE DESIGN, and it comes from `SPEC.md:80`'s own discriminator:
# a check deciding a MECHANICAL FACT is an ordinary check; a check that must
# READ A PROPOSAL AND RULE ON IT is a judgment and "may not become an automated
# blocking member". So of #1222's five obligations, exactly the two that are
# mechanical are enforced here, and the three that are judgments are reported
# for a human-present gate — never silently dropped, and never quietly
# promoted to blockers.
#
#   DENIED here (mechanical):
#     3. a recommendation exists, or its absence is declared
#     5. a stage transition carries no stage name
#   REPORTED, not denied (judgment):
#     1. the ask names the concrete thing being decided
#     2. evidence precedes the options, or its absence is stated
#     4. no derivable parameter is asked as a blank
#
# WHAT OBLIGATION 5 DENIES IS THE NUMBERED FORM (Story 20.157, #1245/#1247).
# It used to derive the denied strings from `draft_gates.GATES`, back when the
# registry labelled gates `"stage 2"` / `"stage 3"`. The owner ruling of
# 2026-08-02 prohibits exactly that expression — *"By attaching a number, the
# system abandons its responsibility to explain which process the Human Gate
# belongs to"* — and the registry now names PROCESSES (`probe`, `interview`,
# `fill`). Keeping the derivation would therefore have inverted the rule: it
# would deny a gate the right to say which process it belongs to, which is the
# thing the ruling REQUIRES an ask to say, and the probe-entry gate's own
# shipped label ("run probe now") would have become a defect.
#
# So the denied family is the numbered one, and it is a PATTERN rather than a
# list — `stage 3`, `Stage 3`, `stage3` all match, and the observed defect
# ("Next is Stage 3 — fill.") still fails. There is nothing left to drift with
# a rename, because a process rename cannot change the shape `stage <digit>`.
# The lazy `draft_gates` loader this file kept for the old derivation is
# DELETED with it: an unread input left in place is what #1245 spent a
# thirteenth cycle on.

# The prohibited form, in one place: "stage" followed by a number, however
# spaced or cased. Nothing else is denied by obligation 5.
NUMBERED_STAGE = re.compile(r"stage\s*[-#]?\s*\d", re.I)


def numbered_stage_forms(text):
    """Every numbered-stage expression in `text`, as it was written.

    Returned rather than a boolean so the defect message can quote the owner's
    own words back at the author instead of naming a rule.
    """
    return [m.group(0) for m in NUMBERED_STAGE.finditer(str(text or ""))]


# A continuation ask is the shape obligation 5 governs: a two-option
# proceed/stop pair. Detected by SHAPE, never by gate id, so a new
# continuation gate inherits the rule instead of having to be added to a list.
_CONTINUE = ("continue", "proceed", "run ", "go on", "next")
_STOP = ("stop", "keep", "pause", "halt", "leave it")


def _is_continuation(choices):
    if len(choices) != 2:
        return False
    labels = [" ".join(str((c or {}).get("label") or "").split()).lower()
              for c in choices]
    has_go = any(any(t in l for t in _CONTINUE) for l in labels)
    has_stop = any(any(t in l for t in _STOP) for l in labels)
    return has_go and has_stop


def _decidability_errors(item, tag):
    """Yield (path, reason) for the MECHANICAL half of #1222 only."""
    choices = item.get("choices")
    if not isinstance(choices, list) or not choices:
        return

    # Obligation 3 — a recommendation, or a declared reason there is none.
    # `render.recommended` is the shipped field (Story 20.107); an item with
    # more than one option and no recommendation leaves the owner to weigh
    # the alternatives with nothing from the machine, which is the input the
    # fork-gate rule calls the hardest one.
    render = item.get("render")
    if len(choices) > 1 and isinstance(render, dict):
        if render.get("recommended") is None and not item.get("no_recommendation"):
            yield (f"{tag}.render.recommended",
                   "no recommendation and no declared reason for its absence "
                   "— an ask offering several options owes the machine's own "
                   "comparison, or an explicit `no_recommendation` saying why "
                   "it cannot make one")

    # Obligation 5 — a stage transition is Yes/No in plain terms, never a
    # NUMBER. "Next is Stage 3" is the observed shape: the owner's own finding
    # was that nobody, including the designer, knew what Stage 3 was. Naming
    # the PROCESS ("run probe now") is the remedy, not the defect — see the
    # note above the matcher.
    if _is_continuation(choices):
        for field in ("where", "why"):
            hits = numbered_stage_forms(" ".join(
                str(item.get(field) or "").split()))
            if hits:
                yield (f"{tag}.{field}",
                       f"a continuation ask says {hits[0]!r}; say plainly "
                       "what happens next and what it costs — a number tells "
                       "the owner nothing about which process this is")
        for j, ch in enumerate(choices):
            hits = numbered_stage_forms(" ".join(
                str((ch or {}).get("label") or "").split()))
            if hits:
                yield (f"{tag}.choices[{j}].label",
                       f"a continuation option says {hits[0]!r}; the label "
                       "states the effect, and names the process if it names "
                       "anything")


def decidability_reports(payload):
    """The JUDGMENT half of #1222 — surfaced for a gate where a human is
    present, never raised as a blocking defect.

    `SPEC.md:80` is explicit that a check which must read a proposal and rule
    on it "rides an existing gate rather than becoming a new blocking hook,
    otherwise the remedy for too many enumerated gates is a new enumerated
    gate". These three obligations cannot be decided without reading intent,
    so they are reported and the human arbitrates.
    """
    items = payload["items"] if isinstance(payload, dict) and "items" in payload \
        else payload if isinstance(payload, list) else [payload]
    out = []
    for i, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        tag = f"item[{i}]"
        why = " ".join(str(item.get("why") or "").split())
        # Obligation 2 — evidence, or an explicit statement that there is none.
        # The mechanical proxy is deliberately weak and labelled as such: a
        # `why` carrying no digit, no pointer and no lacks-marker is a
        # CANDIDATE for the judgment, never a verdict on it.
        if why and not any(ch.isdigit() for ch in why) \
                and "://" not in why and ":" not in why \
                and "no " not in why.lower() and "cannot" not in why.lower():
            out.append((f"{tag}.why", "obligation 2 (judgment): carries no "
                        "number, pointer, or explicit statement that the "
                        "system lacks the evidence — check it gives the owner "
                        "a basis to decide"))
        # Obligations 1 and 4 need intent, so they are named for the reader
        # rather than guessed at here.
        out.append((tag, "obligations 1 and 4 (judgment): confirm the ask "
                    "names the concrete thing being decided (which repository, "
                    "which file, which sentence) and asks for nothing the "
                    "system could derive"))
    return out


def validate(payload, require_render=False):
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
        if require_render and item.get("render") is None:
            yield (f"{tag}.render",
                   "no render directive — a gate declares how it renders, or "
                   "the rendering step is free to compose prose from it")
        yield from _render_errors(item, tag, choices)
        yield from _decidability_errors(item, tag)


CAPTURE_FILE = "presented-payloads.jsonl"


def validate_answer(payload):
    """Yield (path, reason) for every shape defect in an ANSWER envelope
    (Story 18.106, #694).

    The answer record is the other half of the owner interaction this gate
    exists to protect, and its shape is contract: the capture holds "the owner's
    selection + free text" (SPEC-draft-article-ux CAP-2). Recording an envelope
    with no usable selection deferred the error to whichever consumer happened to
    read it — so `{"choice": "approve"}` was captured with `ok: true` and only
    failed stages later at `adapt-canonical write`.

    Two boundaries, both deliberate:

    * SHAPE, never VOCABULARY. Which selection *values* are legal belongs to the
      gate that offered them (approve/modify/stop here, something else there), so
      any non-empty selection string passes.
    * The presented-payload checks do NOT apply. Budgets and the plain-text
      marker rules govern machine-authored text shown to the owner; free text is
      the owner's own words, and clipping or rejecting those would be this
      gate protecting the wrong party."""
    if not isinstance(payload, dict):
        yield "answer", (f"the answer envelope is {type(payload).__name__}, not an "
                         "object — record {\"selection\": \"...\", \"free_text\": \"...\"}")
        return
    # An ask payload piped into --answer by mistake: name it, rather than let a
    # missing `selection` describe the symptom instead of the cause.
    for ask_key in ("items", "choices", "where", "why"):
        if ask_key in payload:
            yield "answer", (f"this looks like an ASK payload (it carries {ask_key!r}), "
                             "not an answer envelope — record the owner's selection, "
                             "or drop --answer to validate it as a payload")
            return
    if "selection" not in payload:
        yield "answer.selection", ("missing — the recorded answer must name the option "
                                   "the owner chose (SPEC-draft-article-ux CAP-2)")
    else:
        sel = payload["selection"]
        if not isinstance(sel, str):
            yield "answer.selection", (f"is {type(sel).__name__}, not a string — the "
                                       "recorded selection is the option's label")
        elif not sel.strip():
            yield "answer.selection", ("is empty — an answer with no selection records "
                                       "no decision, and fails at whichever stage reads "
                                       "it next")
    if "free_text" in payload and not isinstance(payload["free_text"], str):
        yield "answer.free_text", (f"is {type(payload['free_text']).__name__}, not a "
                                   "string — free text is the owner's prose, or absent")


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
                   "requires --ws. The ANSWER envelope's shape is validated (a "
                   "non-empty `selection` string, optional string `free_text`) "
                   "and a blocked answer is never captured; which selection "
                   "VALUES are legal stays with the consuming gate")
    p.add_argument("--require-render", action="store_true",
                   help="reject a payload whose item carries no `render` "
                        "directive (Story 20.107, #1102). Off by default "
                        "because this validator gates every proposal surface "
                        "and the terrain screens do not emit one until Story "
                        "20.108; the carrier check passes it for the gates it "
                        "covers")
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
        answer_defects = list(validate_answer(payload))
        if answer_defects:
            # Blocked answers are never captured — the same posture a blocked ask
            # payload has, so the log never holds an unusable interaction record.
            sys.stderr.write("answer BLOCKED — not a usable answer record:\n")
            for path, reason in answer_defects:
                sys.stderr.write(f"  {path}: {reason}\n")
            return 1
        _capture_append(args.ws, {"kind": "answer", "ask_id": args.answer,
                                  "answer": payload})
        print(json.dumps({"ok": True, "kind": "answer", "ask_id": args.answer}))
        return 0

    defects = list(validate(payload, require_render=args.require_render))
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
