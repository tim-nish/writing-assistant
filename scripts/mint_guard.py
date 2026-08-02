#!/usr/bin/env python3
"""mint_guard.py — the shared guard every mechanical issue mint passes through
(Story 20.167, #1260).

A mechanically minted issue carries its DENOMINATOR — what was searched to
reach the finding it asserts — and an EMPTY denominator refuses to mint. Five
issues (#1171-#1175) were filed by the now-retired journey join from a search
over zero bytes, each carrying `"checked": []` in its own brief: a
cannot-determine dressed as an established absence, five times. The remedy is
the served position of 2026-07-28 — constrain what the pipeline can PRODUCE,
not what it can detect — applied at the filing boundary:
`coverage-completeness-is-relative-to-enumeration`.

THIS IS THE SINGLE SHARED SITE (#1260 AC-1). The post-#1183 enumeration of
filing paths found exactly one remaining path in this repository that composes
and files a GitHub issue — the policy-divergence detector's owner-gated
tracker-issue emission (`skills/policy-divergence-detector/SKILL.md`, "report
upstream" / "fix here"). One path needs no dispatch table, but the guard is
shaped as the shared site deliberately: any future filing path calls
`compose` here rather than growing its own body assembly, and a filing path
that bypasses this module is the defect class returning.

THE DENOMINATOR IS MECHANICAL, NEVER PROSE (#1260 AC-2). `compose` renders the
denominator section from fields the minting code already holds — a `checked:`
list, source counts, bytes/records read — passed in as the RECORD. Prose
flavor ("a thorough search found nothing") is not a denominator and cannot be
supplied here: the section is generated from the record's values verbatim.

EMPTY REFUSES (#1260 AC-3). `checked == []`, zero bytes/records with no named
source, or an unreachable source is a search that did not search. The mint is
REFUSED: the reason goes to stderr, `cannot-determine` goes to the run record,
the exit is non-zero, and NOTHING is written to stdout — an absence-shaped
issue body is never composed from an empty enumeration.

Recognized record fields (all optional; at least one non-empty/positive one is
required to mint):

  checked        list — the enumeration actually searched (names/paths/points)
  searched       list — same standing as `checked` (examine.py's field name)
  sources        int  — count of sources consulted
  records_read   int  — count of records consulted
  bytes_read     int  — bytes actually read
  skipped        list — sources NOT consulted, with reasons (reported in the
                        body when present; never counts toward the denominator)
  unreachable    truthy — the source could not be reached at all; forces
                        refusal regardless of other fields

Usage:
  mint_guard.py compose --record R.json --body-file BODY.md \
      [--run-record RUN.json] [--detected YYYY-MM-DD]

  exit 0: stdout is the full issue body (the draft body + the generated
          `## Denominator` section). File THAT, never the bare draft.
  exit 4: refused; reason on stderr, cannot-determine appended to the run
          record (when given), stdout empty.
"""

import argparse
import datetime
import json
import sys

REFUSED = 4

# The list-shaped and count-shaped fields the guard reads, in render order.
LIST_FIELDS = ("checked", "searched")
COUNT_FIELDS = ("sources", "records_read", "bytes_read")


def denominator(record):
    """(lines, reason) — the rendered denominator lines, or the refusal reason.

    Exactly one of the two is non-None. The lines are composed from the
    record's own values; the reason names which emptiness refused the mint.
    """
    if record.get("unreachable"):
        detail = record["unreachable"]
        what = ", ".join(detail) if isinstance(detail, list) else "the source"
        return None, f"unreachable source: {what} could not be read"

    lines, nonempty = [], False
    for f in LIST_FIELDS:
        if f not in record:
            continue
        items = record[f]
        if not isinstance(items, list):
            return None, f"field {f!r} is not a list"
        names = [i.get("source", json.dumps(i, sort_keys=True))
                 if isinstance(i, dict) else str(i) for i in items]
        lines.append(f"- {f} ({len(names)}): " + (", ".join(names) or "—"))
        if names:
            nonempty = True
    for f in COUNT_FIELDS:
        if f not in record:
            continue
        n = record[f]
        if not isinstance(n, int) or isinstance(n, bool) or n < 0:
            return None, f"field {f!r} is not a non-negative integer"
        lines.append(f"- {f}: {n}")
        if n > 0:
            nonempty = True
    # `skipped` is disclosure, never denominator: a source that was not read
    # keeps an empty search empty (the journey join's exact defect, #1181).
    skipped = record.get("skipped")
    if isinstance(skipped, list) and skipped:
        names = [s.get("source", json.dumps(s, sort_keys=True))
                 if isinstance(s, dict) else str(s) for s in skipped]
        lines.append(f"- skipped ({len(names)}): " + ", ".join(names))

    if not lines:
        return None, ("the record carries no denominator field at all "
                      f"(expected one of: {', '.join(LIST_FIELDS + COUNT_FIELDS)})")
    if not nonempty:
        return None, ("empty enumeration: every checked/searched list is [] "
                      "and every count is 0 — a search over nothing "
                      "establishes nothing (#1171-#1175)")
    return lines, None


def _append_run_record(path, entry):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {"mints": []}
    data.setdefault("mints", []).append(entry)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")


def cmd_compose(args):
    with open(args.record, encoding="utf-8") as fh:
        record = json.load(fh)
    with open(args.body_file, encoding="utf-8") as fh:
        body = fh.read().rstrip("\n")
    when = args.detected or datetime.date.today().isoformat()

    lines, reason = denominator(record)
    if reason is not None:
        sys.stderr.write(f"REFUSED: mint would assert from an empty search — "
                         f"{reason}\n")
        sys.stderr.write("no issue body was composed; the finding is "
                         "cannot-determine, not absence (#1260 AC-3)\n")
        if args.run_record:
            _append_run_record(args.run_record, {
                "minted": False, "verdict": "cannot-determine",
                "reason": reason, "record": args.record, "at": when,
            })
        return REFUSED

    out = body + "\n\n## Denominator\n\nWhat this finding was searched " \
        "against (mechanical, from the minting run's own record):\n\n" \
        + "\n".join(lines) + "\n"
    sys.stdout.write(out)
    if args.run_record:
        _append_run_record(args.run_record, {
            "minted": True, "record": args.record, "at": when,
        })
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compose")
    c.add_argument("--record", required=True,
                   help="JSON record carrying the mechanical denominator fields")
    c.add_argument("--body-file", required=True,
                   help="the draft issue body (markdown)")
    c.add_argument("--run-record", help="run-record JSON to report the "
                   "mint/cannot-determine outcome into (appended)")
    c.add_argument("--detected", help="date YYYY-MM-DD (default: today)")
    c.set_defaults(fn=cmd_compose)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
