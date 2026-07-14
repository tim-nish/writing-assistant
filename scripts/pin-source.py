#!/usr/bin/env python3
"""Pin harvest SOURCE pointers: `path:line` -> `path:line@sha` (Story 13.15).

A harvest driver reads a source file at its CURRENT line numbers and wants the
already-required `path:line@sha` pointer form (validate-fact-sheet.py's contract)
without shelling out to `git blame`/`git rev-parse` once per cited line — that
per-line burn is a large share of the draft turn budget. This is a convenience
helper: it emits the existing pointer form, introduces NO new SOURCE grammar.

What it does, per pointer:
  * `path:line`      -> `path:line@HEAD`   — the SAME line number you passed,
                       pinned to the current commit (HEAD). Because HEAD is the
                       committed state, the pointer resolves to the exact line you
                       cited: a human opening the current file at that line sees
                       the quoted text (#159 — the earlier blame-origin form
                       emitted a DIFFERENT line number that only resolved at a
                       historical sha, so the label did not match the live file).
  * `path:l1-l2`     -> `path:l1-l2@HEAD`  — a quote range, same line numbers.

The pointer keeps the caller's line numbers, so it is verifiable by eye. It is
still `@sha`-pinned (to HEAD), so it survives later edits that shift line numbers.

A line that is not committed OR differs from the committed (HEAD) version — an
uncommitted edit, or an uncommitted insertion/deletion above it that shifted its
number relative to HEAD — cannot be pinned to HEAD verbatim; it is reported to
stderr and skipped rather than emitting a pointer that resolves to the wrong text.
Resolution costs one `git show HEAD:<file>` per file (cached), not one process per
line — bounded by file count, not line count.

Input pointers come from positional args and/or stdin (one per line; blank lines
and `#` comments ignored), so a driver can pipe a column of `path:line` pointers.

With `--emit-entry` (#207) the helper emits the complete fact-sheet entry line
instead of the bare pointer — `- CLAIM / SOURCE / KIND` — with the CLAIM filled
from the verbatim committed source text, so quote entries are copied from tool
output rather than re-typed (the validator pass becomes a confirmation, not a
search). KIND defaults to `quote`; pass `--kind` for the other kinds, where the
verbatim text is a placeholder CLAIM to replace with your claim wording (only a
`quote` CLAIM must stay verbatim). A line range is emitted only for `quote`,
matching validate-fact-sheet.py's grammar. Still no new SOURCE grammar.

Usage:
  pin-source.py [--root HOSTROOT] POINTER [POINTER ...]
  pin-source.py [--root HOSTROOT] --emit-entry [--kind KIND] POINTER [POINTER ...]
  printf 'README.md:88\nbench/results.md:42\n' | pin-source.py --root .
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys

POINTER_RE = re.compile(r"^(?P<path>.+):(?P<l1>\d+)(?:-(?P<l2>\d+))?$")

# validate-fact-sheet.py's closed KIND set — kept in lockstep by the round-trip
# check in check-harvest.sh (emitted entries must validate with zero rejects).
KINDS = ("result", "decision", "number", "quote", "event")


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


def _head_sha(repo, cache):
    """HEAD sha for `repo`, cached; None if it can't be resolved."""
    key = ("sha", repo)
    if key not in cache:
        h = _git(repo, "rev-parse", "HEAD")
        cache[key] = h.stdout.strip() if h.returncode == 0 else None
    return cache[key]


def _head_lines(repo, sha, rel, cache):
    """The lines of `rel` as of `sha` (HEAD), cached; (lines, None) or (None, reason)."""
    key = ("lines", repo, rel)
    if key not in cache:
        show = _git(repo, "show", f"{sha}:{rel}")
        cache[key] = show.stdout.split("\n") if show.returncode == 0 else None
    if cache[key] is None:
        return None, f"{rel} does not exist at HEAD ({sha[:9]})"
    return cache[key], None


def pin_one(path, l1, l2, host, cache):
    """Resolve one pointer to `path:line@HEAD` (same line numbers), or (None, reason).

    The pointer keeps the caller's line numbers and pins to HEAD, and every cited
    line is verified to match its committed (HEAD) version, so the emitted pointer
    resolves to exactly the text the caller sees at that line (#159)."""
    abspath = os.path.realpath(os.path.join(host, path))
    repo = repo_for(abspath)
    if repo is None:
        return None, f"{path}: not inside a git repository"
    rel = os.path.relpath(abspath, repo)
    head = _head_sha(repo, cache)
    if not head:
        return None, f"{path}: cannot resolve HEAD"
    head_lines, reason = _head_lines(repo, head, rel, cache)
    if reason:
        return None, f"{path}: {reason}"
    try:
        with open(abspath, encoding="utf-8") as fh:
            wt_lines = fh.read().split("\n")
    except OSError as exc:
        return None, f"{path}: {exc}"

    lo, hi = (l1, l1) if l2 is None else (l1, l2)
    for cur in range(lo, hi + 1):
        if cur > len(wt_lines):
            return None, f"{path}:{cur}: line past end of file ({len(wt_lines)} lines)"
        # The line must be committed AND unchanged at HEAD — otherwise `path:cur@HEAD`
        # would resolve to different text than the caller is citing.
        if cur > len(head_lines) or head_lines[cur - 1] != wt_lines[cur - 1]:
            return None, (f"{path}:{cur}: line differs from HEAD (uncommitted edit, or an "
                          "uncommitted change above it shifted its number) — commit before pinning")

    span = str(l1) if l2 is None else f"{l1}-{l2}"
    # The verbatim cited text: physical lines stripped and joined by a single
    # space — the same shape validate-fact-sheet.py matches a quote CLAIM against.
    text = " ".join(wt_lines[cur - 1].strip() for cur in range(lo, hi + 1))
    return (f"{path}:{span}@{head}", text), None


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
    p.add_argument("--emit-entry", action="store_true",
                   help="emit the full fact-sheet entry line `- CLAIM / SOURCE / KIND` "
                        "with the CLAIM filled from the verbatim committed text")
    p.add_argument("--kind", choices=KINDS, default="quote",
                   help="KIND for --emit-entry entries (default: quote)")
    args = p.parse_args(argv)

    host = rws.host_root(args.root)
    raw_ptrs = list(args.pointers)
    if not sys.stdin.isatty():
        raw_ptrs += [ln for ln in sys.stdin.read().split("\n")
                     if ln.strip() and not ln.lstrip().startswith("#")]
    if not raw_ptrs:
        print("error: no pointers given (pass path:line args or pipe them on stdin)", file=sys.stderr)
        return 2

    cache = {}
    failed = 0
    for raw in raw_ptrs:
        parsed = parse_pointer(raw)
        if parsed is None:
            print(f"skip: {raw.strip()!r} is not a path:line or path:l1-l2 pointer", file=sys.stderr)
            failed += 1
            continue
        path, l1, l2 = parsed
        if args.emit_entry and l2 is not None and args.kind != "quote":
            # validate-fact-sheet.py accepts a line range only for a quote —
            # refuse here rather than emit a would-be-rejected entry.
            print(f"skip: {path}:{l1}-{l2}: a line range is only valid for KIND 'quote' "
                  f"(got '{args.kind}') — split into per-line pointers", file=sys.stderr)
            failed += 1
            continue
        resolved, reason = pin_one(path, l1, l2, host, cache)
        if resolved is None:
            print(f"skip: {reason}", file=sys.stderr)
            failed += 1
            continue
        pinned, text = resolved
        if not args.emit_entry:
            print(pinned)
            continue
        if not text.strip():
            print(f"skip: {pinned}: cited line(s) are blank — nothing to quote", file=sys.stderr)
            failed += 1
            continue
        print(f"- {text} / {pinned} / {args.kind}")
        if args.kind != "quote":
            print(f"note: {pinned}: CLAIM is the verbatim source text as a placeholder — "
                  f"replace it with your claim wording (only a 'quote' CLAIM must stay verbatim)",
                  file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
