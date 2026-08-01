#!/usr/bin/env python3
"""probe — the stage-1 feasibility check (Story 20.146, #1210; umbrella #1182).

HARVEST IS RETIRED AT STAGE 1, and this is what replaced it (amended
2026-08-02, #1182/#1097/#1185/#1209). Harvest ran at stage 1 while the
article's structure is fixed at stage 3, so the read had to anticipate every
question a not-yet-existing thesis would raise — retrieval against an unstated
query, 358 files opened on the 2026-08-01 run to serve a thesis about five
named mechanisms. Probe asks the one question stage 1 can actually answer:
CAN this repository ground anything for this brief at all? It returns a
feasibility verdict plus a handful of anchors, and writes NO fact sheet —
a doomed article still dies early, at a fraction of harvest's cost, and no
artifact of harvest's shape exists anywhere in the pipeline. Per-claim
examination is `examine` (stage 3+, story 20.147), not this.

THE MODEL JUDGES, THE TOOL NEVER DOES. The verdict and the anchors are the
agent's reading of the brief against the surface; what this tool owns is the
SURFACE (the declared read boundary through the typed time-axis source model,
`resolve-writing-sources.py` — never a second enumeration), the VALIDATION
(an anchor is a resolvable pointer into declared sources, coverage accounts
for every declared source), and the RECORD (probe.json plus the checkpoint).

EVERY PROBE REPORTS ITS COVERAGE: what it consulted, what it could not reach,
and why — an empty result from an unreachable source is a different finding
from an empty result from a read source. `record` refuses a result whose
coverage does not account for every declared source.

CHECKPOINT/RESUME CONTRACT (SPEC-writing-assistant SPEC.md, stage checkpoint
obligation). Probe is atomic at `record`: an interrupted probe leaves the
run's checkpoint at `next_stage: probe` (the stage-0 mint), so resumption
re-enters probe from the top with nothing partial to reconcile; a recorded
probe persists `$WS/probe.json` and the routed checkpoint in one invocation
(grounded -> `interview`, or `fill` on the slim profile; ungrounded ->
`done`, the run stopped with its verdict kept). Re-running `record` replaces
probe.json idempotently — the newest judgment wins, nothing is appended.

Subcommands:
  surface --root R          The declared read surface, typed: every entry from
                            the typed source model with its derived time_axis
                            and an `id` the coverage report must account for.
  record  --ws WS --root R [--framework F] [result.json|-]
                            Validate and persist the model's probe result,
                            then route the checkpoint. Non-zero with named
                            defects on an invalid result; nothing is written.
"""

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys

ANCHOR_CAP = 7   # a HANDFUL of anchors, not a sheet — pre-extraction is
                 # harvest's shape, and the cap is what keeps probe from
                 # growing back into it

_SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
_PTR_RE = re.compile(r"^(?P<path>[^:]+):(?P<a>\d+)(?:-(?P<b>\d+))?$")

SLIM_FRAMEWORKS = {"f5", "working-note"}


def _load_resolver():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _entry_id(rec, root):
    """One stable name per declared entry, for the coverage ledger."""
    if rec["type"] == "path":
        return f"path:{os.path.relpath(rec['path'], root)}"
    if rec["type"] == "github-issues":
        lab = ",".join(rec.get("labels") or [])
        return f"github-issues:{lab}" if lab else "github-issues"
    if rec["type"] == "commits":
        return "commits"
    return rec["type"]


def surface(root):
    """The declared, typed read surface — the coverage denominator.

    Read THROUGH the typed source model (#1184): the resolver derives each
    entry's time_axis and owns the file enumeration; a second glob walk here
    would be a second boundary that drifts from the declared one.
    """
    rws = _load_resolver()
    root = rws.host_root(root)
    lines = rws.read_lines(root)
    entries = []
    for rec in json.loads(_capture(rws.cmd_typed_sources, root)):
        rec["id"] = _entry_id(rec, root)
        entries.append(rec)
    files = sorted(rws.enumerate_files(rws.get_sources(lines, root)))
    return {"root": root, "entries": entries, "files": files}


def _capture(fn, root):
    import contextlib
    import io

    class A:
        pass

    a = A()
    a.root = root
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fn(a)
    return buf.getvalue()


def _anchor_errors(anchors, surf):
    """Every anchor RESOLVES into the declared surface, or the record is
    refused whole. `path:line[-line]` must name an enumerated file and a line
    it actually has; a bare sha must exist in the host repository; anything
    else is not an anchor form."""
    if not isinstance(anchors, list):
        yield "anchors is not a list"
        return
    if len(anchors) > ANCHOR_CAP:
        yield (f"{len(anchors)} anchors exceed the cap of {ANCHOR_CAP} — a "
               "handful, not a sheet; pre-extraction is harvest's shape")
    rel = {os.path.relpath(f, surf["root"]) for f in surf["files"]}
    for i, a in enumerate(anchors):
        ptr = (a or {}).get("pointer") if isinstance(a, dict) else None
        if not ptr or not isinstance(ptr, str):
            yield f"anchors[{i}] carries no pointer"
            continue
        m = _PTR_RE.match(ptr)
        if m:
            path = m.group("path")
            if path not in rel:
                yield (f"anchors[{i}] points outside the declared surface: "
                       f"{path} is not an enumerated source file")
                continue
            try:
                with open(os.path.join(surf["root"], path),
                          encoding="utf-8", errors="replace") as f:
                    n = sum(1 for _ in f)
            except OSError:
                yield f"anchors[{i}]: {path} could not be opened"
                continue
            hi = int(m.group("b") or m.group("a"))
            if not 1 <= int(m.group("a")) <= hi <= n:
                yield (f"anchors[{i}]: line {m.group('a')} is outside "
                       f"{path}'s {n} line(s)")
        elif _SHA_RE.match(ptr):
            r = subprocess.run(["git", "cat-file", "-e", ptr + "^{commit}"],
                               cwd=surf["root"], capture_output=True)
            if r.returncode != 0:
                yield (f"anchors[{i}]: commit {ptr} does not resolve in the "
                       "host repository")
        else:
            yield (f"anchors[{i}]: {ptr!r} is neither path:line[-line] nor a "
                   "commit sha — an anchor is a resolvable pointer into "
                   "declared sources")


def _coverage_errors(coverage, surf):
    """Coverage accounts for EVERY declared source, by id: consulted, or
    unreached with a why. What was not consulted and not explained is the
    silent gap this report exists to make impossible."""
    if not isinstance(coverage, dict):
        yield "coverage is not an object"
        return
    consulted = coverage.get("consulted")
    unreached = coverage.get("unreached")
    if not isinstance(consulted, list) or not isinstance(unreached, list):
        yield "coverage carries consulted and unreached lists, always"
        return
    seen = set(consulted)
    for i, u in enumerate(unreached):
        if not isinstance(u, dict) or not u.get("source") or not u.get("why"):
            yield (f"coverage.unreached[{i}] needs a source and a WHY — an "
                   "unreachable source is a finding, not an omission")
            continue
        seen.add(u["source"])
    declared = {e["id"] for e in surf["entries"]}
    for missing in sorted(declared - seen):
        yield (f"coverage does not account for declared source {missing!r} — "
               "consulted or unreached-with-why, nothing third")
    for extra in sorted(seen - declared):
        yield (f"coverage names {extra!r}, which the declaration does not "
               "carry — the denominator is the declared surface")


def validate(result, surf):
    """Yield every defect in the model's probe result; empty means recordable."""
    verdict = result.get("verdict")
    if verdict not in ("grounded", "ungrounded"):
        yield ("verdict is %r; a probe concludes 'grounded' or 'ungrounded', "
               "nothing third" % (verdict,))
        return
    reasons = result.get("reasons") or []
    anchors = result.get("anchors") or []
    if verdict == "ungrounded" and not reasons:
        yield ("an ungrounded verdict carries its reasons — the run stops on "
               "them, and a bare stop is unactionable")
    if verdict == "grounded" and not anchors:
        yield ("a grounded verdict carries at least one anchor — feasibility "
               "with nothing to point at is an assertion, not a finding")
    yield from _anchor_errors(anchors, surf)
    yield from _coverage_errors(result.get("coverage"), surf)


def record(ws, root, result, framework=None):
    """Persist a valid probe result and route the checkpoint. Returns the
    written record; raises ValueError with every defect on an invalid one."""
    surf = surface(root)
    errs = list(validate(result, surf))
    if errs:
        raise ValueError("\n".join(errs))
    fact_sheet = os.path.join(ws, "fact-sheet.md")
    if os.path.exists(fact_sheet):
        raise ValueError(
            "the run workspace carries fact-sheet.md — harvest's shape, which "
            "this pipeline no longer produces (#1182); remove it before "
            "recording a probe")
    out = {
        "stage": "probe",
        "verdict": result["verdict"],
        "reasons": list(result.get("reasons") or []),
        "anchors": list(result.get("anchors") or []),
        "coverage": result["coverage"],
    }
    if out["verdict"] == "ungrounded":
        out["next_stage"] = "done"
        out["stopped"] = ("the brief cannot be grounded in this repository; "
                          "the run stops before any interview or structure "
                          "work, with the verdict and its reasons kept")
    else:
        slim = str(framework or "").strip().lower() in SLIM_FRAMEWORKS
        out["next_stage"] = "fill" if slim else "interview"
    tmp = os.path.join(ws, "probe.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    os.replace(tmp, os.path.join(ws, "probe.json"))
    cp = os.path.join(ws, "checkpoint.json")
    state = {}
    try:
        with open(cp, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass
    state["stage"] = "probe"
    state["next_stage"] = out["next_stage"]
    state["probe_verdict"] = out["verdict"]
    tmp = cp + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, cp)
    return out


def cmd_surface(args):
    print(json.dumps(surface(args.root), indent=2))
    return 0


def cmd_record(args):
    if args.result == "-":
        raw = sys.stdin.read()
    else:
        with open(args.result, encoding="utf-8") as f:
            raw = f.read()
    try:
        result = json.loads(raw)
    except ValueError as e:
        sys.stderr.write(f"error: result is not JSON: {e}\n")
        return 2
    try:
        out = record(args.ws, args.root, result, framework=args.framework)
    except ValueError as e:
        sys.stderr.write(f"probe result REFUSED — nothing written:\n{e}\n")
        return 3
    print(json.dumps(out, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("surface", help="the declared, typed read surface — "
                                        "the coverage denominator")
    sp.add_argument("--root", help="host-repo root (default: cwd's toplevel)")
    sp = sub.add_parser("record", help="validate and persist the model's "
                                       "probe result, then route the checkpoint")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS)")
    sp.add_argument("--root", help="host-repo root (default: cwd's toplevel)")
    sp.add_argument("--framework", help="the run's article type; the slim "
                                        "profile routes to fill, all others "
                                        "to interview")
    sp.add_argument("result", nargs="?", default="-",
                    help="probe result JSON, or - for stdin")
    args = p.parse_args(argv)
    return {"surface": cmd_surface, "record": cmd_record}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
