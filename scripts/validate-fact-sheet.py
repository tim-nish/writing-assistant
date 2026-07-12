#!/usr/bin/env python3
"""Validate a harvest fact sheet: every entry is `CLAIM / SOURCE / KIND` with a
resolvable, commit-pinned, declared-repo source (Story 3.2).

Contract enforced per entry (a `- ` bullet line):

  - CLAIM / SOURCE / KIND

  * KIND  ∈ {result, decision, number, quote, event}  (closed set)
  * SOURCE is one of:
      path:line@sha   a file pointer PINNED to a commit sha, so it stays
                      resolvable after edits shift line numbers
      path:l1-l2@sha  a line-range pointer, accepted ONLY for a `quote` whose
                      verbatim text spans consecutive physical lines (#119)
      sha             a commit sha (7-40 hex)
      https://…       a URL (external, declared-source citation)
    A bare `path:line` with no `@sha` is rejected — pointers must pin. A line
    range on any KIND except `quote` is rejected: single-line-only for facts,
    with the REJECT naming the fix (split the range into per-line pointers).
  * A file pointer must resolve INSIDE a declared source repo (Story 3.1 scope);
    the sha must exist there, the path must exist at that sha, and the line(s)
    must be in range. A `quote` entry's CLAIM must match the source line(s)
    verbatim (the joined physical lines, for a multi-line span).

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
# A line-range pointer `path:line1-line2@sha` — accepted ONLY for a `quote`
# whose verbatim text genuinely spans consecutive physical lines (#119).
FILEPINRANGE_RE = re.compile(
    r"^(?P<path>.+):(?P<l1>\d+)-(?P<l2>\d+)@(?P<sha>[0-9a-f]{7,40})$")
URL_RE = re.compile(r"^https?://\S+$")


def source_form_ok(source, kind):
    """Grammar-only check (no repo resolution): is `source` a syntactically valid
    SOURCE pointer FORM for `kind`? This is the single SOURCE grammar shared by
    the validator and the pipeline's `consume` step, so the two cannot diverge
    (Story 13.8). A multi-line range `path:l1-l2@sha` is valid ONLY for `quote`;
    every other KIND is single-line. Resolution (sha exists, line in range,
    verbatim match) is a separate, deeper check the validator does and consume
    deliberately does not (it never re-reads sources)."""
    if URL_RE.match(source) or SHA_RE.match(source) or FILEPIN_RE.match(source):
        return True
    if kind == "quote" and FILEPINRANGE_RE.match(source):
        return True
    return False


def _quote_matches(claim, src_text):
    """Verbatim test, lenient about surrounding quote marks and whitespace, as
    the single-line check has always been. `src_text` is the source line(s)
    with each physical line stripped and joined by a single space."""
    quoted = claim.strip()
    inner = re.match(r'^["“](.*)["”]$', quoted)
    if inner:
        quoted = inner.group(1)
    return quoted in src_text or src_text in quoted


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


def _resolve_lines(path, sha, host, sources):
    """Resolve a pinned file pointer to its source lines at the commit.

    Returns (lines, rel, None) on success, (None, None, reason) on rejection,
    or (None, rel, None) for the not-a-git-repo structural pass."""
    abspath = os.path.realpath(os.path.join(host, path))
    repo = declared_repo_for(abspath, sources)
    if repo is None:
        return None, None, f"source path is outside the declared repos: {path}"
    rel = os.path.relpath(abspath, repo)
    if _git(repo, "rev-parse", "--git-dir").returncode != 0:
        return None, rel, None           # not a git repo: structural pass (pin present)
    if _git(repo, "cat-file", "-e", f"{sha}^{{commit}}").returncode != 0:
        return None, None, f"commit {sha} not found in {os.path.basename(repo)}"
    show = _git(repo, "show", f"{sha}:{rel}")
    if show.returncode != 0:
        return None, None, f"path {rel} does not exist at commit {sha}"
    return show.stdout.split("\n"), rel, None


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

    # Line-range pointer `path:line1-line2@sha` — only a `quote` may span
    # consecutive physical lines; every other KIND is single-line (#119).
    rng = FILEPINRANGE_RE.match(source)
    if rng:
        l1, l2, sha, path = int(rng["l1"]), int(rng["l2"]), rng["sha"], rng["path"]
        if kind != "quote":
            return (f"SOURCE must be a single line for KIND '{kind}'; a line range is "
                    f"only allowed for a 'quote' that spans consecutive physical lines "
                    f"— split {l1}-{l2} into per-line pointers")
        if l2 < l1:
            return f"quote range {l1}-{l2} is backwards (line1 must be <= line2)"
        if l1 == l2:
            return (f"quote range {l1}-{l2} spans a single line; use a single-line "
                    f"pointer path:{l1}@{sha}")
        lines, rel, reason = _resolve_lines(path, sha, host, sources)
        if reason:
            return reason
        if lines is None:
            return None                  # not a git repo: structural pass
        if l2 > len(lines):
            return f"line {l2} out of range at {rel}@{sha} ({len(lines)} lines)"
        span = " ".join(lines[i].strip() for i in range(l1 - 1, l2))
        if not _quote_matches(claim, span):
            return "quote CLAIM does not match the source lines verbatim (check the span boundary)"
        return None

    m = FILEPIN_RE.match(source)
    if not m:
        if re.match(r"^.+:\d+-\d+$", source):
            return ("file pointer is not pinned to a commit (use path:line1-line2@sha; "
                    "a line range is valid only for a multi-line 'quote')")
        if re.match(r"^.+:\d+$", source):
            return "file pointer is not pinned to a commit (use path:line@sha)"
        return f"unrecognized SOURCE form: {source!r}"
    path, line, sha = m["path"], int(m["line"]), m["sha"]
    lines, rel, reason = _resolve_lines(path, sha, host, sources)
    if reason:
        return reason
    if lines is None:
        return None                      # not a git repo: structural pass
    if line < 1 or line > len(lines):
        return f"line {line} out of range at {rel}@{sha} ({len(lines)} lines)"
    if kind == "quote":
        if not _quote_matches(claim, lines[line - 1].strip()):
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
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    p.add_argument("--rejected", action="store_true", help="print only rejected entries (for the needs-owner list)")
    args = p.parse_args(argv)

    host = rws.host_root(args.root)
    # Validating against a host with no writing-sources.yaml would reject every
    # file pointer as "outside the declared repos" — a misleading mass-REJECT
    # when the real problem is a wrong root. Fail loudly instead.
    if not os.path.isfile(os.path.join(host, rws.SOURCES_FILE)):
        print(f"error: no {rws.SOURCES_FILE} in host root {host} — "
              "wrong --root, or run from inside the host repo", file=sys.stderr)
        return 2
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
