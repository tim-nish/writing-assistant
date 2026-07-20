#!/usr/bin/env python3
"""detect-policy-divergence.py — the divergence detector's RUNTIME half
(SPEC-policy-divergence-detector, #436, Story 13.99): the CAP-1 detection pass
and the CAP-3/CAP-4 disposition emit side. This is what INVOKES the foundation
(`validate-divergence-candidate.py`): the record schema, the CAP-5 direction
guard, and the CAP-4 dedup key all have their invocation site here.

The classification itself (is this a contradiction or an outgrowing?) is the
LLM-assisted step upstream; it hands this driver *raw flags*. The driver is the
mechanical remainder — guard the direction, validate the record fail-closed,
dedup against the ledger, cap at ≤3 — so a flag only ever becomes a *candidate*
through checks, never a bare assertion. Emission stays proposal-only (CAP-3);
this driver never writes the upstream hub.

Subcommands:

  run --input FLAGS.json [--ledger LEDGER.json] [--detected YYYY-MM-DD]
      [--cap 3]
      The CAP-1 pass. Input is the run's raw flags (one per applied line the
      classification pass flagged): consult_point, direction, rationale,
      decision{statement,evidence}, policy{quote,pointer,pin}, and
      `current_line` (the served line at the run's CURRENT pin, for the CAP-5
      guard). For each flag:
        1. CAP-5 direction guard: policy.quote (as originally consulted) vs
           current_line. Different -> the UPSTREAM moved -> routed to the seam's
           stale/reconcile machinery, never a candidate.
        2. Build the CAP-2 record and validate it fail-closed.
        3. CAP-4 dedup against the ledger (key sans commit); an unexpired hit is
           deduped (occurrence bumped), not re-surfaced.
        4. Cap at --cap (default 3), highest-leverage first (input order);
           capped candidates are COUNTED, never silently dropped.
      Prints {candidates, routed_to_seam, deduped, capped, errors}. Exits 4 if
      any surviving flag fails record validation (fail-closed).

  disposition --ledger LEDGER.json --key KEY --disposition D --pin PIN
      [--reason R] [--ref REF] [--detected YYYY-MM-DD]
      The CAP-3 emit / CAP-4 persistence side. Records an owner disposition
      (reported | fix-here | dismissed) into the ledger: a new entry, or an
      occurrence bump + disposition update on an existing key. `dismissed`
      requires --reason. Validates the whole ledger fail-closed before writing.
      Writes ONLY the ledger file; never the upstream hub.
"""

import argparse
import datetime
import importlib.util
import json
import os
import sys

REFUSED = 4


def _load_core():
    here = os.path.dirname(os.path.realpath(__file__))
    path = os.path.join(here, "validate-divergence-candidate.py")
    spec = importlib.util.spec_from_file_location("divcore", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


core = _load_core()


def _read_json(path):
    text = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    return json.loads(text)


def _today(args):
    # A repo script may read the clock; tests pin it with --detected.
    return args.detected or datetime.date.today().isoformat()


def _ledger_keys(ledger):
    """{dedup key: entry} for the active (non-tombstoned) entries."""
    return {e["key"]: e for e in ledger.get("entries", [])
            if not e.get("tombstoned")}


def cmd_run(args):
    flags = _read_json(args.input)
    if isinstance(flags, dict):
        flags = flags.get("flags", [])
    # An absent ledger is an empty one — a missing dedup file never blocks the
    # detection pass (the "never blocks a run" invariant).
    ledger = {"entries": []}
    if args.ledger and os.path.exists(args.ledger):
        ledger = _read_json(args.ledger)
    active = _ledger_keys(ledger)
    detected = _today(args)

    candidates, routed, deduped, errors = [], [], [], []
    seq = 0
    for f in flags:
        # 1. CAP-5 direction guard — which side moved.
        verdict, note = core.direction_verdict(
            f.get("policy", {}).get("quote", ""), f.get("current_line", ""))
        if verdict != "candidate":
            routed.append({"decision": f.get("decision"), "note": note})
            continue
        # 2. Build + validate the CAP-2 record fail-closed.
        seq += 1
        rec = {
            "id": f"div-{detected}-{seq:03d}",
            "detected": detected,
            "consult_point": f.get("consult_point"),
            "direction": f.get("direction"),
            "decision": f.get("decision"),
            "policy": f.get("policy"),
            "rationale": f.get("rationale"),
            "status": "candidate",
        }
        defects = list(core.validate_record(rec))
        if defects:
            errors.append({"id": rec["id"], "defects": defects})
            continue
        # 3. CAP-4 dedup against the ledger.
        try:
            key = core.dedup_key(rec)
        except ValueError as e:
            errors.append({"id": rec["id"], "defects": [["dedup", str(e)]]})
            continue
        if key in active:
            deduped.append({"key": key,
                            "occurrences": active[key].get("occurrences", 1) + 1})
            continue
        candidates.append(rec)

    # 4. CAP-4 cap — highest-leverage first (input order), count the overflow.
    capped = 0
    if len(candidates) > args.cap:
        capped = len(candidates) - args.cap
        candidates = candidates[:args.cap]

    out = {"candidates": candidates, "routed_to_seam": routed,
           "deduped": deduped, "capped": capped, "errors": errors}
    print(json.dumps(out, indent=2))
    # Fail-closed: a surviving flag that could not validate is a hard error.
    return REFUSED if errors else 0


def cmd_disposition(args):
    if args.disposition not in core.DISPOSITIONS:
        sys.stderr.write("error: disposition must be one of "
                         + ", ".join(core.DISPOSITIONS) + "\n")
        return REFUSED
    if args.disposition == "dismissed" and not (args.reason or "").strip():
        sys.stderr.write("error: --reason is required for a 'dismissed' "
                         "disposition\n")
        return REFUSED
    if len(args.key.split("|")) != 3:
        sys.stderr.write("error: --key must be pointer|direction|evidence\n")
        return REFUSED

    ledger = _read_json(args.ledger) if os.path.exists(args.ledger) \
        else {"entries": []}
    entries = ledger.setdefault("entries", [])
    existing = next((e for e in entries if e.get("key") == args.key), None)
    if existing:
        existing["occurrences"] = existing.get("occurrences", 1) + 1
        existing["disposition"] = args.disposition
        if args.reason:
            existing["reason"] = args.reason
        if args.ref is not None:
            existing["ref"] = args.ref
        existing["pin_at_disposition"] = args.pin
    else:
        entry = {
            "key": args.key,
            "first_seen": _today(args),
            "disposition": args.disposition,
            "ref": args.ref,
            "pin_at_disposition": args.pin,
            "occurrences": 1,
        }
        if args.reason:
            entry["reason"] = args.reason
        entries.append(entry)

    # Validate the whole ledger fail-closed BEFORE writing (never a bad ledger).
    defects = list(core.validate_ledger(ledger))
    if defects:
        sys.stderr.write("REFUSED: the resulting ledger is invalid; nothing "
                         "written:\n")
        for k, r in defects:
            sys.stderr.write(f"  [{k}] {r}\n")
        return REFUSED
    with open(args.ledger, "w", encoding="utf-8") as fh:
        json.dump(ledger, fh, indent=2)
        fh.write("\n")
    print(json.dumps({"ledger": args.ledger, "key": args.key,
                      "disposition": args.disposition,
                      "entries": len(entries)}))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--input", required=True, help="raw-flags JSON, or - for stdin")
    r.add_argument("--ledger", help="disposition ledger for dedup (optional)")
    r.add_argument("--detected", help="detection date YYYY-MM-DD (default: today)")
    r.add_argument("--cap", type=int, default=3, help="max candidates per run (CAP-4; default 3)")
    r.set_defaults(fn=cmd_run)
    d = sub.add_parser("disposition")
    d.add_argument("--ledger", required=True, help="ledger file (created if absent)")
    d.add_argument("--key", required=True, help="dedup key pointer|direction|evidence")
    d.add_argument("--disposition", required=True, help="reported | fix-here | dismissed")
    d.add_argument("--pin", required=True, help="<policy-source>@<commit> at disposition")
    d.add_argument("--reason", help="one line; required when dismissed")
    d.add_argument("--ref", help="#NNN | run-workspace path | (omit for null)")
    d.add_argument("--detected", help="first_seen date YYYY-MM-DD (default: today)")
    d.set_defaults(fn=cmd_disposition)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
