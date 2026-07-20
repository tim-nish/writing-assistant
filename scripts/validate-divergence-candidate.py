#!/usr/bin/env python3
"""validate-divergence-candidate.py — the consumer-side policy-divergence
detector's mechanical core (SPEC-policy-divergence-detector, #436).

The detector flags when THIS tool has moved past an upstream policy line it once
consulted — a *divergence candidate*, never a determination. This script is the
schema/guard core the CAPs build on; the LLM-assisted classification pass (CAP-1)
and the interactive owner gate (CAP-3) wire into it. Everything here is
mechanical, stdlib-only, and fail-closed with per-key diagnostics — the same
posture as the other `validate-*.py` gates.

Subcommands (each reads a JSON file path or - for stdin unless noted):

  record <FILE|->
      Validate one CAP-2 divergence-candidate record (detector-formats.md §1).
      The schema is CLOSED and carries NO verdict/severity/resolution field —
      it can only say "these two disagree and here is where". Exit 0 = valid;
      exit 4 = refused, per-key report on stderr.

  ledger <FILE|->
      Validate the CAP-4 disposition ledger (detector-formats.md §2):
      well-formed entries, the dedup key's shape, and `reason` required on a
      `dismissed` entry. Exit 0 / 4 as above.

  dedup-key <FILE|->
      Print the CAP-4 dedup key for a record — (policy.pointer sans commit,
      direction, decision.evidence) — the key CAP-4 dedups and the ledger is
      keyed by. Reads a candidate record.

  direction --original <LINE> --current <LINE>
      The CAP-5 direction guard. Given the served policy line as the decision
      ORIGINALLY consulted it and the line at the run's CURRENT pin, decide
      which side moved. Different -> the UPSTREAM moved: route to the seam's
      stale machinery (CAP-3 staleness / CAP-7 reconciliation), NOT a divergence
      candidate. Same -> the surface is current at the pin and THIS tool moved
      past it: a divergence candidate is admissible. Prints a JSON verdict.
"""

import argparse
import json
import re
import sys

REFUSED = 4  # schema violation — nothing downstream may use the record

# --- Grammars (mirror the fact-sheet / seam SOURCE grammar already in repo) ---
ID_RE = re.compile(r"^div-\d{4}-\d{2}-\d{2}-\d{3}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# A commit-pinned policy pointer: file:line[-line]@sha (the served-seam grammar).
POLICY_PTR_RE = re.compile(r"^.+:\d+(?:-\d+)?@[0-9a-f]{7,40}$")
# The run's pin: <policy-source>@<commit>.
PIN_RE = re.compile(r"^[^\s@]+@[0-9a-f]{7,40}$")
# Decision evidence: a repo path:line[-line], or a run-artifact pointer
# (ws:<path> / a workspace-relative path:line). Non-empty, no whitespace.
EVIDENCE_RE = re.compile(r"^(?:ws:)?\S+:\d+(?:-\d+)?$")
# A pin sans commit — the ledger dedups on the pointer without its sha.
PTR_SANS_COMMIT_RE = re.compile(r"^(.+):(\d+(?:-\d+)?)@[0-9a-f]{7,40}$")

CONSULT_POINTS = ("review:policy-consistency", "interview:seeding",
                  "session:consult-first")
DIRECTIONS = ("contradiction", "outgrown")
DISPOSITIONS = ("reported", "fix-here", "dismissed")

# Fields that would turn a "here is a disagreement" record into a verdict — the
# schema is closed anyway, but naming these gives a pointed refusal.
VERDICT_FIELDS = ("verdict", "severity", "resolution", "proposed_resolution",
                  "proposed-resolution", "recommendation", "fix")

RECORD_KEYS = ("id", "detected", "consult_point", "direction", "decision",
               "policy", "rationale", "status")
DECISION_KEYS = ("statement", "evidence")
POLICY_KEYS = ("quote", "pointer", "pin")
LEDGER_ENTRY_KEYS = ("key", "first_seen", "disposition", "ref", "reason",
                     "pin_at_disposition", "occurrences")

# Two or more sentence boundaries -> the field is not "one sentence".
MULTI_SENTENCE_RE = re.compile(r"[.!?]\s+[A-Z]")


def _one_sentence(text):
    return len(MULTI_SENTENCE_RE.findall(text)) == 0


def _closed(obj, allowed, where):
    """Yield (key, reason) for any key outside `allowed` — the closed-schema
    check, with a pointed message for verdict-shaped keys."""
    for k in obj:
        if k in allowed:
            continue
        if k in VERDICT_FIELDS:
            yield (f"{where}.{k}", "forbidden verdict-shaped field — the record "
                   "states a disagreement and where, never a resolution "
                   "(the schema has no verdict/severity/resolution field)")
        else:
            yield (f"{where}.{k}", "unknown field — the record schema is closed")


def validate_record(obj):
    """Yield (key, reason) for every CAP-2 violation; empty = a valid record."""
    if not isinstance(obj, dict):
        yield ("(root)", "a divergence-candidate record is a JSON object")
        return

    for key in RECORD_KEYS:
        if key not in obj:
            yield (key, "required key is missing")
    yield from _closed(obj, RECORD_KEYS, "(record)")

    if "id" in obj and not ID_RE.match(str(obj["id"])):
        yield ("id", "must be div-YYYY-MM-DD-NNN")
    if "detected" in obj and not DATE_RE.match(str(obj["detected"])):
        yield ("detected", "must be an ISO date YYYY-MM-DD")
    if "consult_point" in obj and obj["consult_point"] not in CONSULT_POINTS:
        yield ("consult_point", "must be one of " + ", ".join(CONSULT_POINTS))
    if "direction" in obj and obj["direction"] not in DIRECTIONS:
        yield ("direction", "must be 'contradiction' or 'outgrown' — the only "
               "two flaggable directions")
    if "status" in obj and obj["status"] != "candidate":
        yield ("status", "must be the constant 'candidate' — the detector never "
               "emits anything but a candidate")

    dec = obj.get("decision")
    if not isinstance(dec, dict):
        yield ("decision", "required object {statement, evidence}")
    else:
        for k in DECISION_KEYS:
            if not str(dec.get(k, "")).strip():
                yield (f"decision.{k}", "required and non-empty")
        yield from _closed(dec, DECISION_KEYS, "decision")
        if dec.get("evidence") and not EVIDENCE_RE.match(str(dec["evidence"])):
            yield ("decision.evidence", "must be a repo path:line or a "
                   "run-artifact pointer (e.g. specs/foo.md:38), never prose")
        if dec.get("statement") and not _one_sentence(str(dec["statement"])):
            yield ("decision.statement", "must be a single sentence stating the "
                   "decision taken — not a paragraph")

    pol = obj.get("policy")
    if not isinstance(pol, dict):
        yield ("policy", "required object {quote, pointer, pin}")
    else:
        for k in POLICY_KEYS:
            if not str(pol.get(k, "")).strip():
                yield (f"policy.{k}", "required and non-empty — a record missing "
                       "either quote, the pointer, or the pin is rejected")
        yield from _closed(pol, POLICY_KEYS, "policy")
        if pol.get("pointer") and not POLICY_PTR_RE.match(str(pol["pointer"])):
            yield ("policy.pointer", "must be a commit-pinned file:line@sha "
                   "(the served-seam grammar)")
        if pol.get("pin") and not PIN_RE.match(str(pol["pin"])):
            yield ("policy.pin", "must be <policy-source>@<commit>")

    if "rationale" in obj:
        if not str(obj["rationale"]).strip():
            yield ("rationale", "required and non-empty")
        elif not _one_sentence(str(obj["rationale"])):
            yield ("rationale", "must be a single sentence on why the two "
                   "disagree — it describes the disagreement, never resolves it")


def dedup_key(obj):
    """CAP-4 dedup key: policy.pointer sans commit | direction |
    decision.evidence. Raises ValueError if the record can't yield one."""
    pol = obj.get("policy") or {}
    m = PTR_SANS_COMMIT_RE.match(str(pol.get("pointer", "")))
    if not m:
        raise ValueError("policy.pointer is not a commit-pinned file:line@sha")
    ptr = f"{m.group(1)}:{m.group(2)}"
    direction = obj.get("direction")
    if direction not in DIRECTIONS:
        raise ValueError("direction is missing or invalid")
    evidence = str((obj.get("decision") or {}).get("evidence", "")).strip()
    if not evidence:
        raise ValueError("decision.evidence is missing")
    return f"{ptr}|{direction}|{evidence}"


def validate_ledger(obj):
    """Yield (key, reason) for every CAP-4 ledger violation."""
    if not isinstance(obj, dict) or not isinstance(obj.get("entries"), list):
        yield ("(root)", "the ledger is {\"entries\": [ ... ]}")
        return
    seen = {}
    for i, e in enumerate(obj["entries"]):
        at = f"entries[{i}]"
        if not isinstance(e, dict):
            yield (at, "each entry is a JSON object")
            continue
        for k in ("key", "first_seen", "disposition", "pin_at_disposition",
                  "occurrences"):
            if k not in e or (k != "occurrences" and not str(e.get(k, "")).strip()):
                yield (f"{at}.{k}", "required")
        yield from _closed(e, LEDGER_ENTRY_KEYS, at)
        if e.get("disposition") and e["disposition"] not in DISPOSITIONS:
            yield (f"{at}.disposition", "must be one of " + ", ".join(DISPOSITIONS))
        if e.get("disposition") == "dismissed" and not str(e.get("reason", "")).strip():
            yield (f"{at}.reason", "required when disposition is 'dismissed' — a "
                   "dismissal is remembered with its one-line reason")
        if e.get("first_seen") and not DATE_RE.match(str(e["first_seen"])):
            yield (f"{at}.first_seen", "must be an ISO date YYYY-MM-DD")
        if e.get("pin_at_disposition") and not PIN_RE.match(str(e["pin_at_disposition"])):
            yield (f"{at}.pin_at_disposition", "must be <policy-source>@<commit>")
        occ = e.get("occurrences")
        if not isinstance(occ, int) or isinstance(occ, bool) or occ < 1:
            yield (f"{at}.occurrences", "must be an integer >= 1")
        key = e.get("key")
        if key is not None:
            if len(str(key).split("|")) != 3:
                yield (f"{at}.key", "dedup key is pointer|direction|evidence")
            if key in seen:
                yield (f"{at}.key", f"duplicate dedup key (also entries[{seen[key]}]) "
                       "— the ledger holds each divergence once, incrementing "
                       "occurrences, never a second row")
            else:
                seen[key] = i


def direction_verdict(original, current):
    """CAP-5 direction guard. Returns (verdict, note).

    original: the served line as the decision originally consulted it.
    current:  the served line at the run's current pin.
    """
    if original.strip() == current.strip():
        return ("candidate", "surface is current at the pin; this tool moved "
                "past it — a divergence candidate is admissible")
    return ("upstream-moved", "the served line changed since the decision's "
            "consult; the UPSTREAM moved — route to the seam's stale/reconcile "
            "machinery (CAP-3/CAP-7), never a divergence candidate")


# --- CLI --------------------------------------------------------------------

def _load(path):
    text = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: not valid JSON: {e}\n")
        raise SystemExit(REFUSED)


def _report(defects, label):
    if not defects:
        print(f"ok: {label} is valid")
        return 0
    sys.stderr.write(f"REFUSED: {label} has {len(defects)} defect(s):\n")
    for key, reason in defects:
        sys.stderr.write(f"  [{key}] {reason}\n")
    return REFUSED


def cmd_record(args):
    return _report(list(validate_record(_load(args.path))),
                   "divergence-candidate record")


def cmd_ledger(args):
    return _report(list(validate_ledger(_load(args.path))), "disposition ledger")


def cmd_dedup_key(args):
    obj = _load(args.path)
    defects = list(validate_record(obj))
    if defects:
        return _report(defects, "divergence-candidate record")
    print(dedup_key(obj))
    return 0


def cmd_direction(args):
    verdict, note = direction_verdict(args.original, args.current)
    print(json.dumps({"verdict": verdict, "note": note,
                      "is_candidate": verdict == "candidate"}))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("record", cmd_record), ("ledger", cmd_ledger),
                     ("dedup-key", cmd_dedup_key)):
        sp = sub.add_parser(name)
        sp.add_argument("path", nargs="?", default="-", help="JSON file, or - for stdin")
        sp.set_defaults(fn=fn)
    sp = sub.add_parser("direction")
    sp.add_argument("--original", required=True, help="served line at the decision's consult")
    sp.add_argument("--current", required=True, help="served line at the run's current pin")
    sp.set_defaults(fn=cmd_direction)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
