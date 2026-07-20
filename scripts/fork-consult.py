#!/usr/bin/env python3
"""fork-consult.py — the fork-gate consult-first mechanical core
(SPEC-policy-fork-consultation, #480, Stories 18.11/18.12).

At any stop point that presents policy / architecture / prior-decision forks
(spec-run fork tables, triage spec-lane re-offers), a covered fork should be
resolved as a visible, overrideable FYI and only genuinely new positions should
reach the owner as gates. The *semantic* step — does a served line discriminate
between a fork's options? — is LLM-assisted upstream and reaches this script as
a per-fork `consult` result. This script is the mechanical remainder: enforce
strict coverage, format FYI vs gate, bound gate candidates, record misses, and
degrade safely. It never blocks a run and never writes the upstream hub.

Reuses the divergence detector's served-pointer grammar
(`validate-divergence-candidate.py`) so both §3.1 emitters share one authority.

Subcommands:

  present --input FORKS.json --pin PIN [--policy-source-available true|false]
      The CAP-1/2/3 pass. Classify each fork into an FYI (covered + the served
      line discriminates), a gate (uncovered, or covered-but-only-topical, or
      degraded), or skipped (out-of-scope mechanical fork). Uncovered in-scope
      forks are recorded as misses (CAP-4 distill-bug signal). Prints a stop
      report. NEVER exits non-zero for a degraded/empty run — the pass never
      blocks. Exit 4 only on a malformed payload (a gate with >3 candidates, a
      pre-selected default, or a non-served pointer).

  emit-miss --question Q --decision D --slug SLUG --source-repo REPO
      --created YYYY-MM-DD [--perishable] [--tag T ...]
      The CAP-4 emit side: a §3.1-conformant staging block for one dispositioned
      miss, proposal-only, in the seam staging-candidate format (a conformance
      copy of the hub §3.1 schema — no schema of its own). Prints the block to
      stdout for the owner to copy by hand; writes nothing to any hub.
"""

import argparse
import importlib.util
import json
import os
import re
import sys

REFUSED = 4
MAX_CANDIDATES = 3


def _load_core():
    here = os.path.dirname(os.path.realpath(__file__))
    path = os.path.join(here, "validate-divergence-candidate.py")
    spec = importlib.util.spec_from_file_location("divcore", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


core = _load_core()  # shared served-pointer / pin grammar

SLUG_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*$")


def _truthy(v):
    return str(v).strip().lower() in ("true", "yes", "1")


def _served_ok(pointer):
    return bool(core.POLICY_PTR_RE.match(str(pointer)))


def classify(forks, pin, policy_available):
    """Return (report, defects). report partitions every fork; defects is a list
    of (fork_id, reason) that make the payload malformed (fail-closed)."""
    report = {"pin": pin, "degraded": None, "fyis": [], "gates": [],
              "misses": [], "skipped": []}
    defects = []

    if not policy_available:
        # Degradation (CAP: gateway unavailable): every IN-SCOPE fork is a gate,
        # ONE logged line, the run never blocks. Out-of-scope forks still skip.
        report["degraded"] = ("policy_source unavailable: all in-scope forks "
                              "presented as gates (one logged line)")

    for f in forks:
        fid = f.get("id", "?")
        if not f.get("in_scope", True):
            report["skipped"].append({"id": fid, "reason":
                                      "out-of-scope (mechanical fork); not consulted"})
            continue

        gate = {"id": fid, "question": f.get("question"), "candidates": [],
                "reason": None}

        if not policy_available:
            gate["reason"] = "degraded — policy_source unavailable"
            gate["candidates"] = f.get("consult", {}).get("candidates", []) or []
            report["gates"].append(gate)
            report["misses"].append({"id": fid, "question": f.get("question"),
                                     "reason": "unconsulted (degraded)"})
            _check_gate(gate, defects)
            continue

        c = f.get("consult") or {}
        covered = bool(c.get("covered"))
        discriminates = bool(c.get("discriminates"))

        if covered and discriminates:
            # CAP-2: covered fork -> overrideable FYI with source receipts.
            ptr = c.get("pointer", "")
            if not _served_ok(ptr):
                defects.append((fid, f"FYI pointer {ptr!r} is not a served "
                                "file:line@commit pointer"))
            if not core.PIN_RE.match(str(c.get("pin", pin))):
                defects.append((fid, "FYI pin is not <policy-source>@<commit>"))
            if not str(c.get("quote", "")).strip():
                defects.append((fid, "a covered FYI must carry the verbatim served quote"))
            report["fyis"].append({
                "id": fid, "chosen_option": c.get("chosen_option"),
                "quote": c.get("quote"), "pointer": ptr,
                "pin": c.get("pin", pin), "overrideable": True})
            continue

        # Coverage is STRICT: covered-but-topical (does not discriminate) stays a
        # gate, exactly like an uncovered fork. Either way it is a miss.
        gate["reason"] = ("covered but only topical — the quote does not "
                          "discriminate the options"
                          if covered else "uncovered by any served line")
        gate["candidates"] = c.get("candidates", []) or []
        report["gates"].append(gate)
        report["misses"].append({"id": fid, "question": f.get("question"),
                                 "reason": gate["reason"]})
        _check_gate(gate, defects)

    report["counts"] = {"fyis": len(report["fyis"]), "gates": len(report["gates"]),
                        "misses": len(report["misses"]), "skipped": len(report["skipped"])}
    return report, defects


def _check_gate(gate, defects):
    cands = gate["candidates"]
    if len(cands) > MAX_CANDIDATES:
        defects.append((gate["id"], f"a gate carries ≤{MAX_CANDIDATES} candidates, "
                        f"got {len(cands)}"))
    for i, c in enumerate(cands):
        if isinstance(c, dict) and (c.get("default") or c.get("selected")):
            defects.append((gate["id"], f"candidate[{i}] is pre-selected as a "
                            "default — the gate never times out into a choice"))
        for g in (c.get("grounding") or []) if isinstance(c, dict) else []:
            p = g.get("pointer") if isinstance(g, dict) else None
            if p and not _served_ok(p):
                defects.append((gate["id"], f"candidate grounding pointer {p!r} "
                                "is not a served file:line@commit pointer"))


def cmd_present(args):
    text = sys.stdin.read() if args.input == "-" else open(args.input, encoding="utf-8").read()
    data = json.loads(text)
    forks = data.get("forks", data) if isinstance(data, (dict, list)) else []
    if isinstance(forks, dict):
        forks = forks.get("forks", [])
    if not core.PIN_RE.match(str(args.pin)):
        sys.stderr.write("error: --pin must be <policy-source>@<commit> "
                         "(fresh per run; no consultation cache)\n")
        return REFUSED
    report, defects = classify(forks, args.pin,
                               _truthy(args.policy_source_available))
    print(json.dumps(report, indent=2))
    if defects:
        sys.stderr.write(f"REFUSED: {len(defects)} malformed-payload defect(s):\n")
        for fid, r in defects:
            sys.stderr.write(f"  [{fid}] {r}\n")
        return REFUSED
    return 0


def cmd_emit_miss(args):
    if not SLUG_RE.match(args.slug):
        sys.stderr.write("error: --slug must be <YYYY-MM-DD>-<kebab-gist>\n")
        return REFUSED
    tags = ["fork-miss"] + list(args.tag or [])
    # A conformance copy of the hub §3.1 staging-file schema, in the seam's
    # staging-candidate shape (seam-formats.md §3). No schema of its own; the hub
    # §3.1 schema is the authority and wins on any mismatch. Proposal-only —
    # printed for the owner to copy by hand; the hub is never written.
    block = (
        "<!-- staging-candidate -->\n"
        "<!-- conforms to hub §3.1 (product-lab specs/knowledge-architecture.md);"
        " hub schema is the authority, wins on mismatch -->\n"
        "---\n"
        f"slug: {args.slug}\n"
        f"created: {args.created}\n"
        f"source_repo: {args.source_repo}\n"
        f"perishable: {'true' if args.perishable else 'false'}\n"
        f"tags: [{', '.join(tags)}]\n"
        "---\n"
        f"Q: {args.question}\n"
        f"Decision: {args.decision}\n"
    )
    sys.stdout.write(block)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    pr = sub.add_parser("present")
    pr.add_argument("--input", required=True, help="forks JSON, or - for stdin")
    pr.add_argument("--pin", required=True, help="<policy-source>@<commit>, fresh per run")
    pr.add_argument("--policy-source-available", default="true",
                    help="false => degraded: all in-scope forks are gates")
    pr.set_defaults(fn=cmd_present)
    em = sub.add_parser("emit-miss")
    em.add_argument("--question", required=True)
    em.add_argument("--decision", required=True)
    em.add_argument("--slug", required=True, help="<YYYY-MM-DD>-<kebab-gist>")
    em.add_argument("--source-repo", required=True)
    em.add_argument("--created", required=True, help="YYYY-MM-DD")
    em.add_argument("--perishable", action="store_true")
    em.add_argument("--tag", action="append")
    em.set_defaults(fn=cmd_emit_miss)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
