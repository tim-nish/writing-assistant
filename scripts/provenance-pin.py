#!/usr/bin/env python3
"""provenance-pin — the two-tier grounding pin's private half (Story 18.120, #731).

A claim about what the served recall surface records binds only after consulting
it. The pin that proves the consult happened is **split at the publication
boundary** (`specs/spec-writing-assistant/SPEC.md`, Publication boundary):

  public  — a generic decision line in the artifact:
              owner decision record — YYYY-MM-DD (short title)
            enough for a reader to see THAT a consult grounds the claim and
            WHICH one. The mechanism is public.

  private — this store: the decision line mapped to the full pin (hub name,
            commit sha) and the file:line set consulted. Machine-local, outside
            every repository, because it is exactly the owner-specific
            provenance the boundary keeps out of a public tree.

WHY THIS EXISTS AT ALL
----------------------
Before #731 the instruction was to carry the full pin at the point of use, and
the boundary check rejected precisely that string — so grounding a claim was
the act that leaked. Writing the pin somewhere the check cannot see would be a
dodge; writing it nowhere would drop the verifiability the rule exists for.
This keeps the verification and moves only the address.

STORE LOCATION — machine-global, deliberately
---------------------------------------------
`<config-home>/provenance/decisions.json`, resolved through the path resolver
(`scripts/resolve-paths.py config-home`) like every other storage path, per the
single-seam rule in `docs/storage-architecture.md` D1. Machine-global rather
than per-repo because ONE decision grounds claims in several repositories — the
hub is shared — so a per-repo store would hold N copies of one fact and would
need its own reconciliation rule. There is one hub; there is one record of what
it said.

PRECEDENCE — the private record wins
------------------------------------
The store is a conformance copy of the hub's state, so it carries a declared
precedence rule rather than growing into a second authority: on any mismatch
the store's recorded pin is authoritative over a public decision line, and a
public line with **no** store entry is UNVERIFIED — never a grounded claim.
`check` is that mismatch check; a conformance copy without one is the failure
mode this repo already names for the harvest cache.

Stdlib-only. Subcommands:
  record   --decision LINE --pin PIN --cites CITES [--force]
  resolve  --decision LINE
  check    [paths...]        report public decision lines with no store entry
  list                       every recorded decision line (no pins printed)

Exit codes: 0 ok · 1 miss / unverified findings · 2 usage.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESOLVE_PATHS = os.path.join(HERE, "resolve-paths.py")

MISS = 1
USAGE = 2

# The public half's grammar, TOLERANT BY DESIGN.
#
# The canonical form the boundary check suggests is
# `owner decision record — YYYY-MM-DD (title)`, but the convention predates this
# script and already ships in four punctuation variants across ~30 sites:
# `record — DATE, title`, `record DATE (title)`, `record DATE` with no title,
# and `record: title`. A matcher that accepted only the canonical form found
# ZERO of them and reported a confident, useless `ok` — the exact false-zero
# shape this repo's own reporting rules reject.
#
# So identity is DATE plus an optional TITLE, and punctuation is noise. That is
# the same judgment `normalize()` already makes for the store key; making the
# matcher stricter than the key would manufacture `unverified` findings out of
# an em-dash.
DECISION_LINE = re.compile(
    r"owner decision records?\s*[—:,-]?\s*(?P<date>\d{4}-\d{2}-\d{2})"
    r"(?:\s*(?:\((?P<ptitle>[^)]{1,80})\)|,\s*(?P<ctitle>[^.;)\n]{1,80})))?"
)

# Where public decision lines are looked for by `check`. Kept narrow on purpose:
# scanning the whole tree would sweep in quoted examples inside this file and
# the spec text that defines the grammar.
DEFAULT_CHECK_PATHS = ("specs", "docs", "skills", "CLAUDE.md")


def die(msg, code=USAGE):
    sys.stderr.write("error: %s\n" % msg)
    raise SystemExit(code)


def store_path():
    """<config-home>/provenance/decisions.json, via the resolver — never a
    literal composed here (docs/storage-architecture.md D1)."""
    try:
        out = subprocess.run([sys.executable, RESOLVE_PATHS, "config-home"],
                             capture_output=True, text=True, check=True)
    except (subprocess.CalledProcessError, OSError) as exc:
        die("could not resolve the config home: %s" % exc)
    return os.path.join(out.stdout.strip(), "provenance", "decisions.json")


def load():
    path = store_path()
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except ValueError as exc:
        die("provenance store at %s is not readable JSON: %s" % (path, exc))


def save(data):
    path = store_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)
    return path


def normalize(line):
    """A decision line -> its store key.

    Matching is on date + title so the key survives an em-dash/hyphen swap and
    incidental whitespace — a public line that differs only in punctuation is
    the same decision, and treating it as a different one would manufacture
    spurious `unverified` findings.

    A line with no title keys on the date alone. That is lossy where two
    decisions share a date, and it is reported rather than silently merged:
    `check` names the untitled site so the fix is to add a title, not to guess
    which decision was meant.
    """
    m = DECISION_LINE.search(line)
    if not m:
        return None
    raw = m.group("ptitle") or m.group("ctitle") or ""
    title = " ".join(raw.split()).lower().rstrip(")]")
    return "%s|%s" % (m.group("date"), title)


def cmd_record(args):
    key = normalize(args.decision)
    if not key:
        die("--decision must match: owner decision record — YYYY-MM-DD (title)")
    data = load()
    if key in data and not args.force:
        prev = data[key]
        if prev.get("pin") != args.pin or prev.get("cites") != args.cites:
            die("decision already recorded with a different pin; re-run with "
                "--force to supersede it (existing pin recorded %s)"
                % prev.get("recorded", "at an unknown time"), MISS)
        print("already recorded (identical)")
        return 0
    data[key] = {"decision": " ".join(args.decision.split()),
                 "pin": args.pin, "cites": args.cites}
    path = save(data)
    print("recorded %s -> %s" % (key, path))
    return 0


def cmd_resolve(args):
    key = normalize(args.decision)
    if not key:
        die("--decision must match: owner decision record — YYYY-MM-DD (title)")
    entry = load().get(key)
    if not entry:
        # A miss is reported as a miss. Never an empty-looking success — that
        # is the shape that turns "not consulted" into a claim of absence.
        sys.stderr.write("miss: no store entry for %s\n" % key)
        return MISS
    print("pin:   %s" % entry.get("pin", "—"))
    print("cites: %s" % entry.get("cites", "—"))
    return 0


def iter_files(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
        for root, dirs, names in os.walk(p):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for n in names:
                if n.endswith((".md", ".py", ".sh", ".yaml", ".yml")):
                    yield os.path.join(root, n)


def cmd_check(args):
    data = load()
    paths = args.paths or [p for p in DEFAULT_CHECK_PATHS if os.path.exists(p)]
    findings, seen = [], 0
    for path in iter_files(paths):
        try:
            with open(path, encoding="utf-8") as fh:
                lines = fh.readlines()
        except (OSError, UnicodeDecodeError):
            continue
        for i, line in enumerate(lines, start=1):
            for m in DECISION_LINE.finditer(line):
                seen += 1
                key = normalize(m.group(0))
                if key not in data:
                    findings.append((path, i, m.group(0)))
    if not findings:
        print("ok: %d public decision line(s), all resolvable in the store" % seen)
        return 0
    print("unverified: %d of %d public decision line(s) have no store entry"
          % (len(findings), seen))
    for path, lineno, text in findings:
        print("  %s:%d  %s" % (path, lineno, text))
    print("\nEach must either be recorded (provenance-pin.py record) or carry an")
    print("explicit `unverified —` marker at the point of use. A public line with")
    print("no private counterpart is not a grounded claim.")
    return MISS


def cmd_list(args):
    data = load()
    if not data:
        print("(no decisions recorded)")
        return 0
    # Pins are deliberately NOT printed: this subcommand exists to answer
    # "what is recorded", and printing the private half into a terminal that
    # may be logged or pasted re-creates the leak the split exists to prevent.
    for key in sorted(data):
        print("%s  %s" % (key, data[key].get("decision", "")))
    return 0


def main():
    ap = argparse.ArgumentParser(
        description="The private half of the two-tier grounding pin (#731).")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("record", help="map a public decision line to its full pin")
    sp.add_argument("--decision", required=True)
    sp.add_argument("--pin", required=True, help="the full pin, e.g. <hub>@<sha>")
    sp.add_argument("--cites", required=True, help="the file:line set consulted")
    sp.add_argument("--force", action="store_true",
                    help="supersede an existing entry for the same decision")
    sp.set_defaults(func=cmd_record)

    sp = sub.add_parser("resolve", help="the full pin behind a public decision line")
    sp.add_argument("--decision", required=True)
    sp.set_defaults(func=cmd_resolve)

    sp = sub.add_parser("check", help="public decision lines with no store entry")
    sp.add_argument("paths", nargs="*")
    sp.set_defaults(func=cmd_check)

    sp = sub.add_parser("list", help="recorded decision lines (pins not printed)")
    sp.set_defaults(func=cmd_list)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
