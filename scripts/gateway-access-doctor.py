#!/usr/bin/env python3
"""gateway-access-doctor.py — read-only verification of gateway-served policy
access against the canonical access log (Story 13.74, SPEC-policy-source-seam
CAP-2 success clause as amended 2026-07-18, #366). stdlib only, ZERO tokens.

The tsurezure-gateway's server-side access log is the canonical record of
every policy read (allow and deny alike); a consumer run's `consulted:` lines
are receipts. This doctor holds the two against each other:

  * the log path resolves exactly like the gateway's own `resolveLogPath`
    (tsurezure-gateway src/log.ts): operator config `statePath` from
    `~/.tsurezure/gateway.json`, else $TSUREZURE_STATE_DIR, else
    `~/.tsurezure` — then `access.jsonl` inside it. `--log PATH` overrides
    (the test seam); `--gateway-config PATH` overrides the operator-config
    location.
  * `--consumer NAME` (default: writing-assistant) and `--since ISO` window
    the entries; each surviving entry prints one summary line
    (ts, consumer, tool, decision, files/realms, pin, config_version) after
    a count.
  * `--receipts FILE` extracts `consulted:` lines from a run artifact (or a
    bare consulted file) and cross-checks BOTH directions at pin level:
      -> every receipt pin (`<policy-source>@<commit>`) appears in some
         windowed log entry for the consumer;
      <- every windowed log entry for the consumer carries a pin that some
         receipt names.
    Unmatched items are reported in both directions; with `--strict` any
    mismatch exits 1. `consulted: none (...)` lines are generic-mode
    receipts — they name no pin and expect no log entry.

READ-ONLY everywhere: this tool opens the gateway config, the log, and the
receipts file for reading and writes nothing anywhere. It runs no git, no
subprocess, no network.

Exit codes: 0 ok (or mismatch without --strict); 1 mismatch under --strict;
2 usage / unreadable inputs.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

DEFAULT_CONSUMER = "writing-assistant"
PIN_RE = re.compile(r"\b([A-Za-z0-9][A-Za-z0-9_.-]*@[0-9a-f]{7,40})\b")


def resolve_log_path(gateway_config, env=os.environ):
    """Mirror tsurezure-gateway resolveLogPath (src/log.ts): config statePath,
    else TSUREZURE_STATE_DIR, else ~/.tsurezure; the file is access.jsonl."""
    state_dir = None
    try:
        with open(gateway_config, encoding="utf-8") as fh:
            state_dir = json.load(fh).get("statePath") or None
    except (OSError, ValueError):
        state_dir = None  # absent/unreadable operator config: fall through
    if not state_dir:
        state_dir = env.get("TSUREZURE_STATE_DIR") or os.path.join(
            os.path.expanduser("~"), ".tsurezure")
    return os.path.join(state_dir, "access.jsonl")


def parse_ts(iso):
    """ISO-8601 -> aware datetime (Z accepted); None if unparsable."""
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def load_entries(log_path, consumer, since):
    entries = []
    try:
        fh = open(log_path, encoding="utf-8")
    except OSError as e:
        sys.stderr.write(f"error: cannot read access log {log_path}: {e}\n")
        sys.exit(2)
    with fh:
        for i, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                sys.stderr.write(f"warning: {log_path}:{i}: unparsable line skipped\n")
                continue
            if consumer and d.get("consumer") != consumer:
                continue
            if since is not None:
                ts = parse_ts(d.get("ts", ""))
                if ts is None or ts < since:
                    continue
            entries.append(d)
    return entries


def entry_summary(d):
    files = d.get("files_served") or []
    served = ", ".join(files) if files else "realms=" + ",".join(d.get("realms_granted") or [])
    return (f"{d.get('ts', '?')}  consumer={d.get('consumer')}  tool={d.get('tool')}  "
            f"decision={d.get('decision')}  [{served}]  pin={d.get('pin')}  "
            f"config_version={d.get('config_version')}")


def load_receipt_pins(path):
    """`consulted:` lines -> (pins, generic_count). A `consulted: none` line is
    a generic-mode receipt: no pin, no expected log entry."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as e:
        sys.stderr.write(f"error: cannot read receipts {path}: {e}\n")
        sys.exit(2)
    pins, generic = [], 0
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("consulted:"):
            continue
        rest = stripped[len("consulted:"):].strip()
        if rest.startswith("none"):
            generic += 1
            continue
        m = PIN_RE.search(rest)
        if m:
            pins.append(m.group(1))
    return pins, generic


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--log", help="access-log path override (default: resolved "
                   "like the gateway's resolveLogPath)")
    p.add_argument("--gateway-config",
                   default=os.path.join(os.path.expanduser("~"), ".tsurezure", "gateway.json"),
                   help="gateway operator config (default: ~/.tsurezure/gateway.json)")
    p.add_argument("--consumer", default=DEFAULT_CONSUMER,
                   help=f"consumer name to filter on (default: {DEFAULT_CONSUMER})")
    p.add_argument("--since", help="ISO-8601 lower bound on entry timestamps")
    p.add_argument("--receipts", help="run artifact (or consulted file) whose "
                   "`consulted:` lines are cross-checked against the log")
    p.add_argument("--strict", action="store_true",
                   help="exit 1 if the receipts/log cross-check finds any mismatch")
    args = p.parse_args(argv)

    since = None
    if args.since:
        since = parse_ts(args.since)
        if since is None:
            sys.stderr.write(f"error: --since {args.since!r} is not ISO-8601\n")
            return 2

    log_path = args.log or resolve_log_path(args.gateway_config)
    entries = load_entries(log_path, args.consumer, since)

    window = f" since {args.since}" if args.since else ""
    print(f"access log: {log_path}")
    print(f"{len(entries)} entr{'y' if len(entries) == 1 else 'ies'} "
          f"for consumer={args.consumer}{window}")
    for d in entries:
        print("  " + entry_summary(d))

    if not args.receipts:
        return 0

    pins, generic = load_receipt_pins(args.receipts)
    log_pins = {d.get("pin") for d in entries if d.get("pin")}
    receipt_pins = set(pins)
    print(f"receipts: {len(pins)} pinned consulted line(s), {generic} generic (none)")

    mismatch = False
    for pin in sorted(receipt_pins - log_pins):
        mismatch = True
        print(f"UNMATCHED RECEIPT: pin {pin} has no log entry for "
              f"consumer={args.consumer}{window}")
    for d in entries:
        if d.get("pin") and d["pin"] not in receipt_pins:
            mismatch = True
            print(f"UNMATCHED LOG ENTRY: {entry_summary(d)} — no receipt names its pin")
    if not mismatch:
        print("cross-check ok: every receipt pin is logged and every logged "
              "entry maps to a receipt")
        return 0
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
