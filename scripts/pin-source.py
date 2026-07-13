#!/usr/bin/env python3
"""Pin harvest SOURCE pointers: `path:line` -> `path:line@sha` (Story 13.15).

A harvest driver reads a source file at its CURRENT line numbers and wants the
already-required `path:line@sha` pointer form (validate-fact-sheet.py's contract)
without shelling out to `git blame`/`git rev-parse` once per cited line — that
per-line burn is a large share of the draft turn budget. This is a convenience
helper: it emits the existing pointer form, introduces NO new SOURCE grammar.

What it does, per pointer:
  * `path:line`      -> `path:origline@sha`  — blame reports the commit the line
                       came from AND its line number in that commit (`origline`),
                       so the emitted pointer resolves at `sha` by construction.
  * `path:l1-l2`     -> `path:o1-o2@sha`      — a quote range; emitted only when
                       every line l1..l2 shares one commit with contiguous origin
                       numbering. Otherwise it falls back to the current commit:
                       `path:l1-l2@HEAD` (current numbers are valid at HEAD).

Batching is the point (AC2): all lines requested for one file are resolved with a
SINGLE `git blame -L min,max` over that file, so pinning a fact sheet costs one
blame per file, not one process per line — bounded by file count, not line count.

A line with no commit (uncommitted working-tree change, all-zero blame sha) cannot
be pinned; it is reported to stderr and skipped rather than emitting a pointer that
would not resolve.

Input pointers come from positional args and/or stdin (one per line; blank lines
and `#` comments ignored), so a driver can pipe a column of `path:line` pointers.

Usage:
  pin-source.py [--root HOSTROOT] POINTER [POINTER ...]
  printf 'README.md:88\nbench/results.md:42\n' | pin-source.py --root .
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys

POINTER_RE = re.compile(r"^(?P<path>.+):(?P<l1>\d+)(?:-(?P<l2>\d+))?$")
ZERO_SHA = "0" * 40


def _load_rws():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rws = _load_rws()


def _git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def repo_for(abspath):
    """The git top-level containing `abspath` (handles sibling declared repos)."""
    r = _git(os.path.dirname(abspath), "rev-parse", "--show-toplevel")
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None


def blame_map(repo, rel, lo, hi):
    """One `git blame -L lo,hi --porcelain` over `rel`, parsed into
    {current_line: (sha, orig_line)}. Returns (map, None) or (None, reason)."""
    r = _git(repo, "blame", "-L", f"{lo},{hi}", "--porcelain", "--", rel)
    if r.returncode != 0:
        return None, r.stderr.strip() or f"cannot blame {rel} (lines {lo}-{hi})"
    out = {}
    sha = orig = None
    for ln in r.stdout.split("\n"):
        # Porcelain header: `<40-hex> <orig_line> <final_line> [<num_lines>]`
        m = re.match(r"^([0-9a-f]{40})\s+(\d+)\s+(\d+)(?:\s+\d+)?$", ln)
        if m:
            sha, orig, final = m.group(1), int(m.group(2)), int(m.group(3))
            out[final] = (sha, orig)
    return out, None


def pin_one(path, l1, l2, host, head_cache):
    """Resolve one pointer to its pinned form, or (None, reason)."""
    abspath = os.path.realpath(os.path.join(host, path))
    repo = repo_for(abspath)
    if repo is None:
        return None, f"{path}: not inside a git repository"
    rel = os.path.relpath(abspath, repo)
    lo, hi = (l1, l1) if l2 is None else (l1, l2)
    bmap, reason = blame_map(repo, rel, lo, hi)
    if reason:
        return None, f"{path}: {reason}"
    for cur in range(lo, hi + 1):
        if cur not in bmap:
            return None, f"{path}:{cur}: line not found (file shorter than {cur} lines?)"
        if bmap[cur][0] == ZERO_SHA:
            return None, f"{path}:{cur}: line is not committed yet — commit it before pinning"

    if l2 is None:                                   # single line
        sha, orig = bmap[l1]
        return f"{path}:{orig}@{sha}", None

    # Range (quote span): emit an origin-pinned range only when every line shares
    # one commit with contiguous origin numbering; else pin to HEAD (current
    # numbers are valid at the current commit).
    shas = {bmap[c][0] for c in range(lo, hi + 1)}
    o1, o2 = bmap[lo][1], bmap[hi][1]
    if len(shas) == 1 and (o2 - o1) == (hi - lo):
        return f"{path}:{o1}-{o2}@{shas.pop()}", None
    if repo not in head_cache:
        h = _git(repo, "rev-parse", "HEAD")
        head_cache[repo] = h.stdout.strip() if h.returncode == 0 else None
    head = head_cache[repo]
    if not head:
        return None, f"{path}: cannot resolve HEAD to pin the range {l1}-{l2}"
    return f"{path}:{l1}-{l2}@{head}", None


def parse_pointer(raw):
    m = POINTER_RE.match(raw.strip())
    if not m:
        return None
    l2 = int(m["l2"]) if m["l2"] is not None else None
    return m["path"], int(m["l1"]), l2


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("pointers", nargs="*", help="path:line or path:l1-l2 (quote range)")
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    args = p.parse_args(argv)

    host = rws.host_root(args.root)
    raw_ptrs = list(args.pointers)
    if not sys.stdin.isatty():
        raw_ptrs += [ln for ln in sys.stdin.read().split("\n")
                     if ln.strip() and not ln.lstrip().startswith("#")]
    if not raw_ptrs:
        print("error: no pointers given (pass path:line args or pipe them on stdin)", file=sys.stderr)
        return 2

    head_cache = {}
    failed = 0
    for raw in raw_ptrs:
        parsed = parse_pointer(raw)
        if parsed is None:
            print(f"skip: {raw.strip()!r} is not a path:line or path:l1-l2 pointer", file=sys.stderr)
            failed += 1
            continue
        path, l1, l2 = parsed
        pinned, reason = pin_one(path, l1, l2, host, head_cache)
        if pinned is None:
            print(f"skip: {reason}", file=sys.stderr)
            failed += 1
        else:
            print(pinned)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
