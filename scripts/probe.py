#!/usr/bin/env python3
"""probe — the stage-1 configuration and permission check (Story 20.154, #1224).

WHAT PROBE IS NOW, AND WHY IT SHRANK. Probe replaced harvest at stage 1 (Story
20.146, #1210) as a model-judged feasibility read: a `grounded`/`ungrounded`
verdict, up to seven anchors, and a coverage ledger accounting for every
declared source. That contract is retired by the 2026-08-02 amendment (#1224).

THE CONTRADICTION THAT KILLED IT, quoted from the stage's own text:
`stage1.md` said "Read against the brief only what feasibility needs — anchors,
never an extraction pass", and, forty lines later, that `record` refuses a
ledger not accounting for EVERY declared source. Those cannot both hold. The
second clause won in practice, and it is what read 168 files to certify an
empty result from a source that contributed nothing.

THE DECLARATION SPLITS IN TWO, AND ONLY ONE HALF SURVIVES HERE.
As a PERMISSION BOUNDARY — what may be read at all — `writing-sources.yaml` is
untouched, and two ratified invariants still rest on it: the filter-never-
widener rule (`stage0.md`) and "out-of-scope repos never searched
automatically". This module still verifies that boundary, which is the whole
of what stage 1 now does.
As a COVERAGE DENOMINATOR it is gone. Certifying coverage of a DECLARED
universe makes the cost scale with the declaration rather than with the claim,
and the claim is what the evidence is for.

FEASIBILITY MOVED TO WHERE IT BINDS. There is no verdict here because stage 1
cannot honestly reach one: the article's structure is fixed at stage 3, so a
verdict at stage 1 judges a thesis that does not yet exist. A claim that cannot
be grounded is now an ungrounded CLAIM, found at `examine` — a finding the
pipeline can act on, where an ungrounded RUN was a verdict about nothing.
Die-early folds into the first failed examine (story 20.155 moves the
anchor-finding that goes with it).

THE COST IS DISCLOSED, NOT ASSUMED AWAY. The #1104 amendment made a thin read
READ as thin by denominating it — "92% coverage of 11 declared files, with 340
files outside the declaration". Dropping the denominator risks reinstating the
unfalsifiable-success defect that fixed. The bet is that per-claim scoring is
the better instrument, because each claim is individually gradeable where
whole-corpus coverage never was. OVERTURN CONDITION, recorded so it can be
checked rather than argued: a sitting in which per-claim results are present
and the owner still cannot tell a well-grounded article from a thin one. The
answer then is to bound the ledger to term-matched sources with the remainder
counted-never-read — the alternative this decision rejected.

THE TIME BUDGET IS A CONTRACT, because #1224 correctly observed that none
existed anywhere and the only cost language was relative ("a fraction of
harvest's cost"). A relative bound against a retired stage bounds nothing.

CHECKPOINT/RESUME CONTRACT. Probe is atomic at `record`: an interrupted probe
leaves the checkpoint at `next_stage: probe` (the stage-0 mint), so resumption
re-enters from the top with nothing partial to reconcile. `record` persists
`$WS/probe.json` and the routed checkpoint in one invocation, idempotently.

Subcommands:
  check  --root R           The permission check: the declaration resolves and
                            every granted root is reachable. No enumeration,
                            no anchors, no verdict.
  record --ws WS --root R [--framework F]
                            Run the check, persist it, and route the
                            checkpoint (slim profile -> fill, all others ->
                            interview). Takes no model result: nothing at this
                            stage is a judgment.
"""

import argparse
import importlib.util
import json
import os
import sys
import time

# THE STAGE-1 TIME BUDGET (Story 20.154, #1224), in seconds. A permission check
# reads a declaration and stats a handful of roots; five seconds is generous
# for that and tight enough to fail loudly if enumeration ever creeps back in,
# which is the regression this number exists to catch. Asserted by
# `check-probe.sh`, never merely hoped for.
TIME_BUDGET_S = 5.0

# The frameworks whose runs skip the Stage-2 interview.
SLIM_FRAMEWORKS = {"f5", "working-note"}


def _load_resolver():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _source_fields(src):
    """`(name, path)` for a declared source, tolerant of the resolver's own
    representation. Shape-tolerant on purpose: this module must not become a
    second reader of the source model's internals, which is the coupling
    `surface()` had and the reason it grew."""
    if isinstance(src, dict):
        return (src.get("name") or src.get("path") or str(src),
                src.get("path"))
    return (getattr(src, "name", None) or getattr(src, "path", None) or str(src),
            getattr(src, "path", None))


def check(root):
    """The permission check: can this run read what it was granted?

    THREE QUESTIONS AND NO FOURTH. Does the declaration resolve; is every
    granted root present and readable; how many sources were declared. It does
    NOT enumerate files, hunt anchors, or judge feasibility — each of those is
    what made the old probe cost minutes, and each now belongs to `examine`,
    per claim.
    """
    started = time.monotonic()
    rws = _load_resolver()
    root = rws.host_root(root)

    try:
        lines = rws.read_lines(root)
        sources = rws.get_sources(lines, root)
    except Exception as e:                    # noqa: BLE001 — reported, not raised
        return {"stage": "probe", "ok": False,
                "error": (f"the source declaration does not resolve: "
                          f"{type(e).__name__}: {e}"),
                "root": root, "declared": [], "unreadable": [],
                "elapsed_s": round(time.monotonic() - started, 3),
                "budget_s": TIME_BUDGET_S, "over_budget": False}

    declared, unreadable = [], []
    for src in sources:
        name, path = _source_fields(src)
        declared.append(name)
        # A GRANT THAT CANNOT BE READ IS A CONFIGURATION ERROR, and it is the
        # one thing stage 1 is now for. Reported per source with its path: an
        # aggregate "something is unreachable" is unactionable, which is the
        # complaint #1222 makes about asks generally.
        if path and not os.access(str(path), os.R_OK):
            unreadable.append({"source": name, "path": str(path)})

    elapsed = round(time.monotonic() - started, 3)
    return {"stage": "probe",
            "ok": not unreadable,
            "root": root,
            "declared": declared,
            "unreadable": unreadable,
            "elapsed_s": elapsed,
            "budget_s": TIME_BUDGET_S,
            # Disclosed rather than enforced in-process: a run that exceeds the
            # budget still completes and says so, because failing a draft on a
            # slow filesystem is a worse outcome than a slow probe. The CHECK
            # is what holds the number to account.
            "over_budget": elapsed > TIME_BUDGET_S}


def record(ws, root, framework=None):
    """Persist the check and route the checkpoint.

    Raises on an unreadable grant; everything else routes onward, because
    there is no verdict left to stop on.
    """
    result = check(root)
    if not result["ok"]:
        detail = "\n".join(f"  {u['source']}: {u['path']}"
                           for u in result["unreadable"]) or result.get("error", "")
        raise ValueError(
            "the run was granted sources it cannot read; fix the declaration "
            "or the permissions before drafting:\n" + detail)

    slim = str(framework or "").strip().lower() in SLIM_FRAMEWORKS
    result["next_stage"] = "fill" if slim else "interview"

    tmp = os.path.join(ws, "probe.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    os.replace(tmp, os.path.join(ws, "probe.json"))

    cp = os.path.join(ws, "checkpoint.json")
    state = {}
    try:
        with open(cp, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass
    state["stage"] = "probe"
    state["next_stage"] = result["next_stage"]
    # `probe_verdict` IS NO LONGER WRITTEN (Story 20.154, #1224), and the key
    # is REMOVED rather than set to a placeholder: a key carrying "no verdict"
    # reads as a verdict to every consumer that tests for its presence.
    state.pop("probe_verdict", None)
    tmp = cp + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, cp)
    return result


def cmd_check(args):
    print(json.dumps(check(args.root), indent=2))
    return 0


def cmd_record(args):
    try:
        out = record(args.ws, args.root, args.framework)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("check", help="the permission check: the declaration "
                                      "resolves and every granted root is "
                                      "readable")
    sp.add_argument("--root", help="host-repo root (default: cwd's toplevel)")
    sp = sub.add_parser("record", help="run the check, persist it, and route "
                                       "the checkpoint")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS)")
    sp.add_argument("--root", help="host-repo root (default: cwd's toplevel)")
    sp.add_argument("--framework", help="the run's article type; the slim "
                                        "profile routes to fill, all others "
                                        "to interview")
    args = p.parse_args(argv)
    return {"check": cmd_check, "record": cmd_record}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
