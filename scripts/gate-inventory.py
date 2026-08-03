#!/usr/bin/env python3
"""A run's gate inventory, audited against what it actually emitted
(Story 20.119, #1114/#1122).

WHY THIS EXISTS AFTER THE SITTING. Story 20.118 constrains what this repository
COMPOSES — a gate surface is composed only through the declared registry, so
every code-path gate leaves an ask row. What it cannot constrain is the agent's
own rendering step, which #1102 records as a layer this repository does not own.
So the residue is DETECTED: a gate the run reached with no matching row in
`presented-payloads.jsonl` becomes a defect anyone can find later, rather than
an obligation nobody can check.

WHY THE LEFT-HAND SIDE IS PASSED IN. `reached` is what the run actually got to,
which the log cannot supply — a log missing a row is precisely the case being
audited, so deriving "reached" from the log would make the check vacuous by
construction. The caller (the sitting, or a fixture) names what it reached; the
registry validates that those ids exist at all.

WHAT THIS AUDIT DOES NOT COVER — STATED, BECAUSE A CLEAN AUDIT OTHERWISE READS
AS A CLEAN CLASS (Story 20.136, #1176). This is coverage of DECLARED-ID
EMISSION. It compares the ids a caller says it reached against the ask rows the
run wrote, and both sides are keyed on `draft_gates.GATES` — so an owner-facing
ask that was never declared there is invisible to it, and a run that composed
one still audits clean. That is not a gap to be closed by a better predicate:
the sentence above is the reason. `reached` is supplied by the caller because
deriving it from the log would make the check vacuous, which means the actor
that failed to declare a gate is the actor that reports which gates it reached
— the self-assertion shape already declined upstream as "self-asserted by the
same actor class that made the original error". No mechanical carrier is
possible at the agent's composition step, so THE STATED LIMIT IS THE REMEDY
(`specs/spec-writing-assistant/amendments-2026-07-24--2026-08-01.md`,
2026-08-01 #1176/#1177, clause (a)). Reopen trigger: a harness-level signal
that fires when a turn ends awaiting a reply.

No spec, skill or check may cite this audit as evidence of gate coverage
without that bound.
"""

import argparse
import importlib.util
import json
import os
import sys


def _gates():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "draft_gates", os.path.join(here, "draft_gates.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.declared_gates()


def read_asks(ws):
    """The ask rows a run wrote. A missing log is an EMPTY run, not an error —
    the audit's whole job is to report what is absent."""
    path = os.path.join(ws, "presented-payloads.jsonl")
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if row.get("kind") == "ask":
                rows.append(row)
    return rows


def read_tool_calls(transcript_path, settle_marker=None):
    """The `AskUserQuestion` tool-use events a transcript carries, plus whether
    the transcript has CAUGHT UP (Story 20.151, #1221).

    Returns `(gate_ids, settled)`. `settled` is the load-bearing half.

    WHY SETTLEDNESS IS A RETURN VALUE AND NOT AN ASSUMPTION. The harness writes
    the transcript asynchronously and its own docs say the file "may lag the
    in-memory conversation". This audit's finding BLOCKS a turn, so a read that
    raced the writer would block on evidence that exists and simply had not
    landed — the most expensive failure this check can have. Owner decision
    2026-08-02: assert only on settled turns, report the rest as
    cannot-determine, never block on incomplete evidence.

    `settle_marker` is the turn's final assistant text, supplied by the harness.
    It is used as an OPAQUE TOKEN — "has the file caught up to this turn yet" —
    and never classified, matched against patterns, or inspected for content.
    That distinction is the whole reason this stays inside the contract: the
    amendment forbids reading reply PROSE, and an identity test on a string the
    harness handed us reads no prose. Nothing here branches on what it says.
    """
    if not transcript_path or not os.path.isfile(transcript_path):
        return [], False
    gates, saw_marker = [], settle_marker is None
    try:
        with open(transcript_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                blob = json.dumps(row)
                if settle_marker and settle_marker in blob:
                    saw_marker = True
                for name, gate in _ask_tool_uses(row):
                    if name == "AskUserQuestion":
                        gates.append(gate)
    except OSError:
        return [], False
    return gates, saw_marker


def _ask_tool_uses(row):
    """Yield `(tool_name, gate_id_or_None)` for every tool-use event in a
    transcript row. Shape-tolerant on purpose: the transcript schema is the
    harness's, not this repository's, so a structure change must degrade to
    "found nothing" rather than raising inside a Stop hook."""
    msg = row.get("message") if isinstance(row, dict) else None
    content = (msg or {}).get("content") if isinstance(msg, dict) else None
    if not isinstance(content, list):
        return
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        inp = block.get("input") or {}
        gate = inp.get("gate") if isinstance(inp, dict) else None
        yield block.get("name"), gate


def reached_from_state(ws):
    """The gates a run reached, DERIVED FROM RUN STATE (Story 20.151, #1221).

    The caller used to supply this, and the docstring above still records why
    that was defensible: deriving `reached` from the PAYLOAD LOG would make the
    audit vacuous, since a log missing a row is exactly the case under audit.
    That argument is sound about the log and silent about run state, which is a
    third source — and it is the one #1221 names: "the run workspace already
    records `next_stage` ... so 'a gate was due here' is computable".

    So the left-hand side now comes from the checkpoint, and the actor that
    failed to declare a gate is no longer the actor reporting which gates it
    reached.

    `gates_reached` IS GONE (Story 20.157, #1245/#1247). Story 20.151 read a
    `checkpoint.json:gates_reached` list, and the amendment that orders this
    story states what triage found: its only writer in this repository was the
    guarding check's own fixture, so the input never existed on a real run and
    this function returned `[]` every time — an audit that cannot fail because
    it is never given anything to audit. The list is not given a writer; it is
    DROPPED, because the join it stood in for is computable from data both
    sides already carry. `draft_gates.GATES` declares which PROCESS each gate
    belongs to and the checkpoint names the process the run is entering, in
    the same vocabulary (`draft_gates` declares it once) — so due-ness is one
    equality, with no translation table anywhere in the path.

    Due, not historical: a gate is returned when the run is entering the
    process that gate belongs to. Gates on a pre-run process (`terrain`,
    `start`) never match, because no checkpoint exists while they are asked —
    stated in the registry rather than special-cased here.
    """
    path = os.path.join(ws, "checkpoint.json")
    if not os.path.isfile(path):
        return [], "no checkpoint — the run reached no declared stage"
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError) as e:
        return [], f"checkpoint unreadable: {type(e).__name__}"
    stage = state.get("next_stage")
    reached = [gid for gid, spec in _gates().items()
               if stage and spec.get("stage") == stage]
    return reached, None if reached else (
        f"no declared gate belongs to the process next_stage={stage!r}")



# THE BOUND, DECLARED ONCE (Story 20.136, #1176) and carried by every audit —
# in the result, in the CLI output, and in --help. One string, so a consumer
# quotes it rather than paraphrasing the limit into something weaker.
BOUND = (
    "BOUND: this is coverage of DECLARED-ID EMISSION — reached ids against the "
    "ask rows written for them, both keyed on draft_gates.GATES. It is NOT "
    "coverage of an ask that was never declared: a surface composed outside the "
    "registry is invisible here and this audit still reports ok. A clean audit "
    "is not a clean class."
)


def audit(ws, reached, transcript_path=None, settle_marker=None):
    """Assert `reached` ⊆ emitted, and that every emitted payload declares its
    render form. With `transcript_path`, additionally assert that each emitted
    gate has AskUserQuestion TOOL-CALL evidence (Story 20.151, #1221) — a gate
    is `presented` when the transcript carries the call, never when a payload
    file exists.

    Two findings, kept apart because they are different defects: a gate that
    never emitted (the thesis-gate shape) and a gate that emitted without a
    `render:` declaration (the intent-gate shape). Both were observed on the
    same 2026-08-01 run, and collapsing them would lose which one to fix.
    """
    declared = _gates()
    unknown = [g for g in reached if g not in declared]
    if unknown:
        raise ValueError(
            f"not declared in the gate registry: {unknown} — a gate the run "
            f"claims to have reached must exist in `draft_gates.GATES`")
    rows = read_asks(ws)
    emitted = {r.get("gate") for r in rows}
    missing = [g for g in reached if g not in emitted]
    # A row with no `gate` is not a gate emission and cannot be missing a
    # render directive: `validate-proposal-payload.py --ws --surface` captures
    # surface-keyed asks, and `--answer` captures answer rows, neither of which
    # carries a gate id. Indexing them raised KeyError, and because this audit
    # runs inside the Stop hook the crash presented as the hook's own
    # cannot-determine fallback on every turn of a run that captured any.
    render_missing = sorted({
        r["gate"] for r in rows
        if r.get("gate")
        and not all((it or {}).get("render") for it in (r.get("items") or [{}]))})
    tool_call_gaps, settled = [], None
    if transcript_path is not None:
        called, settled = read_tool_calls(transcript_path, settle_marker)
        if settled:
            called_set = {g for g in called if g}
            # A gap is a gate that EMITTED a payload but has no tool-call
            # evidence: the payload existed, so the pre-#1221 audit passed,
            # and the question UI was never actually invoked.
            tool_call_gaps = sorted(g for g in emitted
                                    if g and g not in called_set)
    return {"ok": (not missing and not render_missing
                   and not tool_call_gaps),
            # The bound travels WITH the verdict, not beside it in a doc
            # somewhere: a caller that reads `ok` and nothing else is the
            # reader this clause exists for.
            "bound": BOUND,
            "reached": list(reached),
            "emitted": sorted(x for x in emitted if x),
            "missing": missing,
            "render_missing": render_missing,
            # None = not asked for; False = asked for but the transcript had
            # not caught up, so NOTHING is asserted about tool calls. False is
            # never a pass: it is cannot-determine, and the caller must not
            # read `ok` as covering the tool-call half.
            "tool_call_settled": settled,
            "tool_call_gaps": tool_call_gaps}


def pending_decisions(answered=()):
    """The owner decisions still to come, DERIVED from the registry
    (Story 20.117, #1112).

    AC3 forbids a hand-listed map — *"a hardcoded list is a conformance copy
    with no precedence rule and drifts the first time a gate moves"* — so this
    reads `draft_gates.GATES` and nothing else. Add a gate there and it appears
    here; move it to another stage and this follows.

    A gate with `owner_decision: None` carries no decision the owner must make
    (the resume confirmation is asked only when a run predates the sitting), so
    it is omitted rather than rendered as an empty row.
    """
    declared = _gates()
    out = []
    for gid, spec in declared.items():
        if gid in answered or not spec.get("owner_decision"):
            continue
        out.append({"gate": gid, "stage": spec["stage"],
                    "decision": spec["owner_decision"]})
    # Stage order is the registry's insertion order, which is the order the
    # pipeline reaches them; sorting alphabetically would tell the owner that
    # sources comes before intent.
    return out


NEVER_ASKED = (
    ("paragraph structure",
     "frameworks bind section OBLIGATIONS, not literal headings — so this is "
     "never asked, of anyone, at any stage"),
)


def pending_decision_lines(answered=()):
    """The map as the owner reads it, with the never-asked decision stated.

    NON-MEMBER DISCLOSURE, applied to decisions rather than to content: the
    absence of a structure ask at the brief must read as *later*, and the one
    that is never asked must read as *never, and here is why*. An owner who
    expected a gate and saw none could otherwise only conclude the pipeline
    decided it silently, which is exactly what #1112 reports.
    """
    rows = pending_decisions(answered)
    lines = ["Decisions still yours, and where each is asked:"]
    lines += [f"  {r['decision']} — {r['stage']}" for r in rows]
    for what, why in NEVER_ASKED:
        lines.append(f"  {what} — never asked: {why}")
    return lines


def main(argv=None):
    # RawDescriptionHelpFormatter, deliberately: the default formatter reflows
    # the epilog into one block and the bound is the half a reader skims for.
    p = argparse.ArgumentParser(
        description="Audit a run's gates against the ask rows it wrote. " + BOUND,
        epilog=BOUND,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--ws", help="the run workspace to audit")
    p.add_argument("--reached",
                   help="comma-separated gate ids the run reached")
    p.add_argument("--transcript",
                   help="a Claude Code transcript to take AskUserQuestion "
                        "tool-call evidence from; a gate counts as PRESENTED "
                        "only when the call is in the transcript, never when "
                        "a payload file exists (Story 20.151, #1221)")
    p.add_argument("--settle-marker",
                   help="the turn's final assistant text, used ONLY as an "
                        "opaque has-the-file-caught-up token; an unsettled "
                        "transcript asserts nothing rather than blocking")
    p.add_argument("--reached-from-state", action="store_true",
                   help="derive the reached ids from the run checkpoint "
                        "instead of --reached (Story 20.151, #1221)")
    p.add_argument("--audit", action="store_true",
                   help="audit --reached against the ask rows in --ws (the "
                        "default mode; named so citations can say --audit). "
                        + BOUND)
    p.add_argument("--list", action="store_true",
                   help="print the declared registry and exit")
    p.add_argument("--pending", action="store_true",
                   help="print the owner decisions still pending, derived from "
                        "the registry (Story 20.117), and exit")
    p.add_argument("--answered", default="",
                   help="comma-separated gate ids already answered")
    args = p.parse_args(argv)
    if args.list:
        print(json.dumps(_gates(), indent=2))
        return 0
    if args.pending:
        answered = [g.strip() for g in args.answered.split(",") if g.strip()]
        print("\n".join(pending_decision_lines(answered)))
        return 0
    if not args.ws or not (args.reached or args.reached_from_state):
        p.error("--ws and --reached (or --reached-from-state) are required "
                "unless --list/--pending")
    if args.reached_from_state:
        reached, why = reached_from_state(args.ws)
        if why:
            print(f"cannot-determine: {why}")
    else:
        reached = [g.strip() for g in args.reached.split(",") if g.strip()]
    res = audit(args.ws, reached, transcript_path=args.transcript,
                settle_marker=args.settle_marker)
    print(json.dumps(res, indent=2))
    # PRINTED ON EVERY AUDIT, INCLUDING A CLEAN ONE — especially a clean one.
    # A limit disclosed only on failure is disclosed exactly where nobody is
    # about to over-read the result.
    print(BOUND)
    if res["missing"]:
        if res.get("tool_call_gaps"):
            print(f"error: emitted but never CALLED: {res['tool_call_gaps']} — "
                  "a payload exists and the question UI was never invoked, so "
                  "the ask reached the owner as prose", file=sys.stderr)
        if res.get("tool_call_settled") is False:
            print("cannot-determine: the transcript had not caught up to this "
                  "turn; nothing is asserted about tool calls (not a pass)")
        print(f"error: reached but never emitted: {res['missing']} — a gate "
              f"surface that asked the owner something left no record of it",
              file=sys.stderr)
    if res["render_missing"]:
        print(f"error: emitted without a render: declaration: "
              f"{res['render_missing']}", file=sys.stderr)
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
