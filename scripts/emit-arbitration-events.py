#!/usr/bin/env python3
"""Emit review-arbitration outcomes as dogfood events (SPEC-article-review
CAP-5, Story 13.42).

One emit per finding disposition, RAW events only — nothing is judged or
classified at emit time; demotion analysis belongs to the dogfood tool's own
recurrence bar, never this workflow. Input is one JSON object per line (file or
`-` for stdin), one per arbitrated finding:

    {"pass": "structure", "criterion": "rubric-dim2", "severity": "should",
     "disposition": "accepted"}
    {"pass": "prose", "criterion": "hedging", "severity": "nit",
     "disposition": "rejected", "reason": "intentional hedge — claim is soft"}

Required fields: pass, criterion, severity, disposition; `reason` (one line) is
required when disposition is `rejected`. An optional `anchor` (the finding's
location, e.g. `L64:exploration-axes`) — or, failing that, `summary` — gives the
finding a STABLE identity that is folded into `detail`, so two distinct findings
never emit byte-identical events (#497). Malformed input is a per-line error and
exit 2 — the raw-event contract is enforced mechanically.

The events are ALWAYS persisted to the run workspace
(`$WS/arbitration-events.jsonl`) in the dogfood ledger's ingestible event shape
(type `review-arbitration`; the disposition fields both structured and folded
into `detail` for exact-dupe fingerprinting). Ledger ingestion is an OPTIONAL
hook — the plugin stays producer-generic: when user config declares
`dogfood.ingest_cmd`, that command is run with the events file appended; when
it is absent, or the command fails, the emitter logs ONE line and exits 0 —
the ledger is an enhancer, never a dependency (the events remain in `$WS` for
any later offline mining pass).

Stdlib-only. Prints a one-line JSON summary to stdout.
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys

REQUIRED = ("pass", "criterion", "severity", "disposition")
DISPOSITIONS = {"accepted", "rejected", "fix-article", "position-moved", "dismissed"}


def finding_identity(d):
    """A STABLE per-finding identifier folded into the event so two DISTINCT
    findings never emit byte-identical events (which would collapse under
    Tanuki's scenario|type|detail exact-dupe key and corrupt recurrence counts,
    #497), while a true cross-run recurrence — the same criterion at the same
    location — keeps the same identity and still collapses correctly.

    Prefer the finding's `anchor` (the location it is raised at, e.g.
    `L64:exploration-axes`) so the event can be joined back to its originating
    edit offline; fall back to a short slug of the finding's `summary`. Both are
    optional — a finding with neither yields `""` (unchanged legacy behaviour)."""
    anchor = str(d.get("anchor") or "").strip()
    if anchor:
        return anchor
    summary = str(d.get("summary") or "").strip()
    if summary:
        slug = re.sub(r"[^a-z0-9]+", "-", summary.lower()).strip("-")
        return slug[:48]
    return ""


def load_dispositions(path):
    text = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    out, errors = [], []
    for i, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError as e:
            errors.append(f"line {i}: not valid JSON: {e}")
            continue
        missing = [k for k in REQUIRED if not d.get(k)]
        if missing:
            errors.append(f"line {i}: missing required field(s): {', '.join(missing)}")
            continue
        if d["disposition"] not in DISPOSITIONS:
            errors.append(f"line {i}: unknown disposition {d['disposition']!r} "
                          f"(valid: {', '.join(sorted(DISPOSITIONS))})")
            continue
        if d["disposition"] == "rejected" and not d.get("reason"):
            errors.append(f"line {i}: disposition 'rejected' requires a one-line `reason`")
            continue
        out.append(d)
    return out, errors


def to_event(d, scenario, run_id):
    """Fold one disposition into the ledger's event shape. `detail` carries the
    full disposition for exact-dupe fingerprinting (scenario|type|detail); it
    ends with a STABLE finding identity (#497) so distinct findings stay
    distinct while true cross-run recurrence still collapses. The structured
    fields — including `finding`, the same identity for offline joins — ride
    alongside, unjudged."""
    identity = finding_identity(d)
    detail = "|".join([d["pass"], d["criterion"], d["severity"], d["disposition"],
                       d.get("reason", ""), identity])
    return {
        "type": "review-arbitration",
        "source": "review-arbitration",
        "scenario": scenario,
        "run": run_id,
        "detail": detail,
        "pass": d["pass"],
        "criterion": d["criterion"],
        "severity": d["severity"],
        "disposition": d["disposition"],
        **({"reason": d["reason"]} if d.get("reason") else {}),
        **({"finding": identity} if identity else {}),
    }


def resolve_ingest_cmd(args):
    """Optional `dogfood.ingest_cmd` from user config (resolved the standard
    way); --ingest-cmd overrides for tests. Absent -> None (graceful path)."""
    if args.ingest_cmd is not None:
        return args.ingest_cmd or None      # explicit "" disables
    here = os.path.dirname(os.path.realpath(__file__))
    cmd = [sys.executable, os.path.join(here, "resolve-user-config.py")]
    for flag, val in (("--root", args.root), ("--global-config", args.global_config),
                      ("--repo-config", args.repo_config)):
        if val:
            cmd += [flag, val]
    cmd += ["resolved"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        return None
    try:
        cfg = json.loads(p.stdout)
    except json.JSONDecodeError:
        return None
    return (cfg.get("dogfood") or {}).get("ingest_cmd") or None


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dispositions", nargs="?", default="-",
                   help="JSONL of finding dispositions, or - for stdin")
    p.add_argument("--ws", required=True,
                   help="run workspace — the events file always lands here")
    p.add_argument("--scenario", default="review",
                   help="scenario id for the events (e.g. the draft slug)")
    p.add_argument("--run-id", default=None,
                   help="run id recorded on each event (default: basename of --ws)")
    p.add_argument("--ingest-cmd", default=None,
                   help="override the optional dogfood.ingest_cmd from user config "
                        "(empty string disables ingestion)")
    p.add_argument("--root")
    p.add_argument("--global-config")
    p.add_argument("--repo-config")
    args = p.parse_args(argv)

    dispositions, errors = load_dispositions(args.dispositions)
    if errors:
        for e in errors:
            sys.stderr.write(f"error: {e}\n")
        return 2
    run_id = args.run_id or os.path.basename(os.path.normpath(args.ws))
    events = [to_event(d, args.scenario, run_id) for d in dispositions]

    events_path = os.path.join(args.ws, "arbitration-events.jsonl")
    with open(events_path, "a", encoding="utf-8") as fh:
        for e in events:
            fh.write(json.dumps(e, ensure_ascii=False) + "\n")

    ingested = False
    ingest_cmd = resolve_ingest_cmd(args)
    if ingest_cmd:
        try:
            r = subprocess.run(shlex.split(ingest_cmd) + [events_path],
                               capture_output=True, text=True)
            ingested = r.returncode == 0
            if not ingested:
                sys.stderr.write("notice: dogfood ledger ingest failed "
                                 f"({(r.stderr or r.stdout).strip().splitlines()[0] if (r.stderr or r.stdout).strip() else 'no output'}) "
                                 "— events kept in the run workspace\n")
        except OSError as exc:
            sys.stderr.write(f"notice: dogfood ledger ingest unavailable ({exc}) "
                             "— events kept in the run workspace\n")
    else:
        sys.stderr.write("notice: no dogfood.ingest_cmd configured — events kept "
                         "in the run workspace for offline mining\n")

    print(json.dumps({"emitted": len(events), "events_file": events_path,
                      "ingested": ingested}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
