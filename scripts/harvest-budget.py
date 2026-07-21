#!/usr/bin/env python3
"""harvest-budget.py — the per-source extraction budget, as a contract in code.

CAP-10 (#516) restructures harvest from one attention-bounded pass over the whole
corpus into **per-source budgeted extraction**: the model extracts one declared
source file at a time, each under an explicit **relative** entry budget, so
corpus growth scales cost rather than silently shrinking per-file coverage (the
#514 collapse). The budget is a **contract** — floors and caps live here in code,
never in a prompt instruction (boundedness-is-a-contract-not-curation) — and a
source that reaches its budget is surfaced by a **diagnostic naming that source**,
never truncated in the dark.

The scheme is *relative* to each source's own size (the product-lab corpus-intake
precedent): a budget derived from the file's harvestable-line count, clamped
between a floor and a cap. It is a soft guide for the extractor and a diagnostic
threshold — not a hard reject; the fact-sheet validator remains the correctness
gate. Enumeration order comes from `resolve-writing-sources.py files` (the single
source of truth for the read boundary and its order), so the budget report and
the deterministic merge share one enumeration.

Usage:
  harvest-budget.py [--root R]            # one `budget: <file> <n>` line per source, in enumeration order
  harvest-budget.py [--root R] --json     # {"floor":..,"cap":..,"per_line":..,"files":[{path,lines,budget}],"total":N}
  harvest-budget.py [--root R] <file> …   # budgets for the named files only (still relative to each file's size)

Output paths are the same absolute paths `resolve-writing-sources.py files`
emits, so they line up with the enumerator's list.
"""
import argparse
import json
import os
import subprocess
import sys

# --- The budget contract (floors/caps in code, never in a prompt) -----------
# One candidate fact per ~PER_LINE_DIVISOR harvestable (non-blank) lines, clamped
# to [FLOOR, CAP]. FLOOR keeps a tiny-but-real source (a short README, a config
# note) from being budgeted to zero; CAP keeps a single huge file from consuming
# the whole run. These three constants ARE the contract — change them here, in
# code, under review; never restate them as a number in a prompt.
FLOOR = 3
CAP = 40
PER_LINE_DIVISOR = 8

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENUMERATOR = os.path.join(SCRIPT_DIR, "resolve-writing-sources.py")


def enumerate_sources(root):
    """The declared read boundary, in enumeration order — delegated to
    resolve-writing-sources.py so there is exactly one enumerator."""
    cmd = [sys.executable, ENUMERATOR]
    if root:
        cmd += ["--root", root]
    cmd += ["files"]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        raise SystemExit(out.returncode)
    return [ln for ln in out.stdout.splitlines() if ln.strip()]


def harvestable_lines(path):
    """A cheap, deterministic proxy for how much extractable material a source
    carries: its non-blank line count. Unreadable/binary files count as 0 (they
    contribute no facts) and fall to the FLOOR budget."""
    try:
        with open(path, encoding="utf-8", errors="strict") as f:
            return sum(1 for ln in f if ln.strip())
    except (OSError, UnicodeDecodeError):
        return 0


def budget_for(path):
    n = harvestable_lines(path)
    raw = -(-n // PER_LINE_DIVISOR)  # ceil(n / divisor)
    return max(FLOOR, min(CAP, raw))


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd)")
    p.add_argument("--json", action="store_true", help="emit the whole budget report as JSON")
    p.add_argument("files", nargs="*", help="score only these files (default: the enumerated sources)")
    args = p.parse_args(argv)

    if args.files:
        paths = [os.path.abspath(f) for f in args.files]
    else:
        paths = enumerate_sources(args.root)

    rows = [{"path": pth, "lines": harvestable_lines(pth), "budget": budget_for(pth)} for pth in paths]
    total = sum(r["budget"] for r in rows)

    if args.json:
        print(json.dumps({
            "floor": FLOOR, "cap": CAP, "per_line": PER_LINE_DIVISOR,
            "files": rows, "total": total,
        }, indent=2))
    else:
        for r in rows:
            print(f"budget: {r['path']} {r['budget']}")
        print(f"total-budget: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
