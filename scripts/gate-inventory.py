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


def audit(ws, reached):
    """Assert `reached` ⊆ emitted, and that every emitted payload declares its
    render form.

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
    render_missing = sorted({
        r["gate"] for r in rows
        if not all((it or {}).get("render") for it in (r.get("items") or [{}]))})
    return {"ok": not missing and not render_missing,
            # The bound travels WITH the verdict, not beside it in a doc
            # somewhere: a caller that reads `ok` and nothing else is the
            # reader this clause exists for.
            "bound": BOUND,
            "reached": list(reached),
            "emitted": sorted(x for x in emitted if x),
            "missing": missing,
            "render_missing": render_missing}


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
    if not args.ws or not args.reached:
        p.error("--ws and --reached are required unless --list/--pending")
    res = audit(args.ws, [g.strip() for g in args.reached.split(",") if g.strip()])
    print(json.dumps(res, indent=2))
    # PRINTED ON EVERY AUDIT, INCLUDING A CLEAN ONE — especially a clean one.
    # A limit disclosed only on failure is disclosed exactly where nobody is
    # about to over-read the result.
    print(BOUND)
    if res["missing"]:
        print(f"error: reached but never emitted: {res['missing']} — a gate "
              f"surface that asked the owner something left no record of it",
              file=sys.stderr)
    if res["render_missing"]:
        print(f"error: emitted without a render: declaration: "
              f"{res['render_missing']}", file=sys.stderr)
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
