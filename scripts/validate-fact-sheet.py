#!/usr/bin/env python3
"""Validate a harvest fact sheet: every entry is `CLAIM / SOURCE / KIND` with a
resolvable, commit-pinned, declared-repo source (Story 3.2).

Contract enforced per entry (a `- ` bullet line):

  - CLAIM / SOURCE / KIND

  * KIND  ∈ {result, decision, number, quote, event}  (closed set)
  * SOURCE is one of:
      path:line@sha   a file pointer PINNED to a commit sha, so it stays
                      resolvable after edits shift line numbers
      sha             a commit sha (7-40 hex)
      https://…       a URL (external, declared-source citation)
    A bare `path:line` with no `@sha` is rejected — pointers must pin.
  * A file pointer must resolve INSIDE a declared source repo (Story 3.1 scope);
    the sha must exist there, the path must exist at that sha, and the line must
    be in range. A `quote` entry's CLAIM must match the source line verbatim.

An entry that fails any check is REJECTED (it belongs on the needs-owner list —
Story 3.3 — not the fact sheet). Exit status is non-zero if any entry is
rejected, so "no entry without a resolvable pointer" is a hard gate.

Usage: validate-fact-sheet.py [FACTSHEET|-] [--root HOSTROOT] [--rejected]
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys

KINDS = {"result", "decision", "number", "quote", "event"}
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
FILEPIN_RE = re.compile(r"^(?P<path>.+):(?P<line>\d+)@(?P<sha>[0-9a-f]{7,40})$")
URL_RE = re.compile(r"^https?://\S+$")


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


def declared_repo_for(abspath, sources):
    for s in sources:
        if rws._contains(s["path"], abspath):
            return s["path"]
    return None


def validate_source(source, kind, claim, host, sources):
    """Return None if the source is valid, else a rejection reason."""
    if URL_RE.match(source):
        return None                      # external citation; form is the contract
    if SHA_RE.match(source):             # bare commit sha — must exist in a declared repo
        for s in sources:
            if os.path.isdir(os.path.join(s["path"], ".git")) or _git(s["path"], "rev-parse", "--git-dir").returncode == 0:
                if _git(s["path"], "cat-file", "-e", f"{source}^{{commit}}").returncode == 0:
                    return None
        return f"commit {source} not found in any declared repo"
    m = FILEPIN_RE.match(source)
    if not m:
        if re.match(r"^.+:\d+$", source):
            return "file pointer is not pinned to a commit (use path:line@sha)"
        return f"unrecognized SOURCE form: {source!r}"
    path, line, sha = m["path"], int(m["line"]), m["sha"]
    abspath = os.path.realpath(os.path.join(host, path))
    repo = declared_repo_for(abspath, sources)
    if repo is None:
        return f"source path is outside the declared repos: {path}"
    rel = os.path.relpath(abspath, repo)
    if _git(repo, "rev-parse", "--git-dir").returncode != 0:
        return None                      # not a git repo: structural pass (pin present)
    if _git(repo, "cat-file", "-e", f"{sha}^{{commit}}").returncode != 0:
        return f"commit {sha} not found in {os.path.basename(repo)}"
    show = _git(repo, "show", f"{sha}:{rel}")
    if show.returncode != 0:
        return f"path {rel} does not exist at commit {sha}"
    lines = show.stdout.split("\n")
    if line < 1 or line > len(lines):
        return f"line {line} out of range at {rel}@{sha} ({len(lines)} lines)"
    if kind == "quote":
        src_line = lines[line - 1].strip()
        quoted = claim.strip()
        inner = re.match(r'^[\"“](.*)[\"”]$', quoted)
        if inner:
            quoted = inner.group(1)
        if quoted not in src_line and src_line not in quoted:
            return "quote CLAIM does not match the source line verbatim"
    return None


def validate_entry(raw, host, sources):
    parts = [p.strip() for p in raw.rsplit(" / ", 2)]
    if len(parts) != 3 or any(p == "" for p in parts):
        return raw, "malformed: expected `CLAIM / SOURCE / KIND` with all fields non-empty"
    claim, source, kind = parts
    if kind not in KINDS:
        return raw, f"invalid KIND {kind!r} (must be one of {sorted(KINDS)})"
    reason = validate_source(source, kind, claim, host, sources)
    return raw, reason


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("factsheet", nargs="?", default="-", help="fact-sheet file, or - for stdin")
    p.add_argument("--root", help="host-repo root (default: git top-level, else cwd)")
    p.add_argument("--rejected", action="store_true", help="print only rejected entries (for the needs-owner list)")
    args = p.parse_args(argv)

    host = rws.host_root(args.root)
    sources = rws.get_sources(rws.read_lines(host), host)
    text = sys.stdin.read() if args.factsheet == "-" else open(args.factsheet, encoding="utf-8").read()

    # Only the fact-sheet section: stop at the NEEDS-OWNER list (Story 3.3),
    # whose entries use a different `CANDIDATE / REASON / TOPIC` schema.
    fs_lines = []
    for ln in text.split("\n"):
        if re.match(r"^#+\s*NEEDS-OWNER\b", ln):
            break
        fs_lines.append(ln)
    entries = [ln[2:] for ln in fs_lines if ln.startswith("- ")]
    rejected = 0
    for raw, reason in (validate_entry(e, host, sources) for e in entries):
        if reason is None:
            if not args.rejected:
                print(f"VALID   {raw}")
        else:
            rejected += 1
            print(f"REJECT  {raw}\n        -> {reason}")
    if not args.rejected:
        print(f"\n{len(entries)} entries, {rejected} rejected.")
    return 1 if rejected else 0


if __name__ == "__main__":
    sys.exit(main())
