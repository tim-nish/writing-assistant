#!/usr/bin/env python3
"""Resolve writing-sources.yaml: declared sources + draft output location.

Stdlib-only by design (host repos guarantee no venv / no PyYAML), so this reads
the small, flat writing-sources.yaml subset directly rather than through a YAML
library. Write-back is line surgery, so existing comments and ordering survive.

Subcommands (each takes --root; default: the git top-level, else cwd):

  draft-location            Print the declared output.drafts value and exit 0.
                            If it is undeclared, exit 3 (the draft skill then
                            asks the owner once and, on consent, calls
                            set-draft-location). There is deliberately NO
                            hardcoded default: an undeclared location is a
                            prompt, never a silent fallback.

  set-draft-location PATH   Write output.drafts = PATH back into
                            writing-sources.yaml, preserving comments and
                            ordering. Idempotent: re-running with the same PATH
                            changes nothing. Prints the resolved value.

  sources                   List declared source paths, each resolved against
                            the host-repo root (CAP-2: only these may be read).

  is-declared PATH          Exit 0 iff PATH lies inside a declared source root;
                            non-zero otherwise. This is the harvest read
                            boundary — an undeclared sibling repo is rejected
                            even when adjacent on disk.
"""

import argparse
import os
import re
import subprocess
import sys

SOURCES_FILE = "writing-sources.yaml"

NEEDS_PROMPT = 3  # draft-location: no output.drafts declared


def host_root(arg_root):
    """Resolve the host-repo root: explicit --root, else git top-level, else cwd."""
    if arg_root:
        return os.path.realpath(arg_root)
    try:
        top = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if top:
            return os.path.realpath(top)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return os.path.realpath(os.getcwd())


def read_lines(root):
    """Return the raw lines (no trailing newlines) of writing-sources.yaml, or []."""
    path = os.path.join(root, SOURCES_FILE)
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as fh:
        return fh.read().split("\n")


def write_lines(root, lines):
    path = os.path.join(root, SOURCES_FILE)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


def _indent(line):
    return len(line) - len(line.lstrip())


def _find_output_block(lines):
    """Index of a top-level `output:` line, or None."""
    for i, ln in enumerate(lines):
        if re.match(r"^output:\s*(#.*)?$", ln):
            return i
    return None


def get_output_drafts(lines):
    """Return the declared output.drafts value (str) or None."""
    out = _find_output_block(lines)
    if out is None:
        return None
    j = out + 1
    while j < len(lines):
        ln = lines[j]
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            j += 1
            continue
        if _indent(ln) == 0:  # left the output block
            break
        m = re.match(r"^\s+drafts:\s*(.*?)\s*$", ln)
        if m:
            val = m.group(1)
            # strip a trailing inline comment and surrounding quotes
            val = re.sub(r"\s+#.*$", "", val).strip().strip('"').strip("'")
            return val or None
        j += 1
    return None


def set_output_drafts(lines, value):
    """Return (new_lines, changed). Line surgery preserves comments/ordering."""
    out = _find_output_block(lines)
    if out is not None:
        j = out + 1
        while j < len(lines):
            ln = lines[j]
            if ln.strip() == "" or ln.lstrip().startswith("#"):
                j += 1
                continue
            if _indent(ln) == 0:
                break
            if re.match(r"^\s+drafts:\s*.*$", ln):
                indent = ln[: _indent(ln)]
                new = f"{indent}drafts: {value}"
                if new == ln:
                    return lines, False
                return lines[:j] + [new] + lines[j + 1 :], True
            j += 1
        # output block present but no drafts key: insert right under it
        return lines[: out + 1] + [f"  drafts: {value}"] + lines[out + 1 :], True
    # no output block at all: append one
    tail = []
    if lines and lines[-1].strip() != "":
        tail.append("")
    tail += ["output:", f"  drafts: {value}"]
    return lines + tail, True


def get_sources(lines, root):
    """Parse the sources list into [{'path': abs, 'include': [...]}].

    Absent `include` means the whole path is in scope.
    """
    result = []
    in_sources = False
    current = None
    for ln in lines:
        if re.match(r"^sources:\s*(#.*)?$", ln):
            in_sources = True
            continue
        if in_sources and _indent(ln) == 0 and ln.strip():
            break  # left the sources block
        if not in_sources or ln.strip() == "" or ln.lstrip().startswith("#"):
            continue
        m = re.match(r"^\s*-\s*path:\s*(.*?)\s*$", ln)
        if m:
            raw = re.sub(r"\s+#.*$", "", m.group(1)).strip().strip('"').strip("'")
            current = {"path": os.path.realpath(os.path.join(root, raw)), "include": []}
            result.append(current)
            continue
        m = re.match(r"^\s+include:\s*\[(.*)\]\s*$", ln)
        if m and current is not None:
            items = [x.strip().strip('"').strip("'") for x in m.group(1).split(",")]
            current["include"] = [x for x in items if x]
    return result


def _contains(parent, child):
    """True iff realpath child is parent or inside it (no symlink/.. escape)."""
    parent = os.path.realpath(parent)
    child = os.path.realpath(child)
    if child == parent:
        return True
    return child.startswith(parent + os.sep)


def cmd_draft_location(args):
    root = host_root(args.root)
    val = get_output_drafts(read_lines(root))
    if val is None:
        sys.stderr.write(
            f"no output.drafts declared in {os.path.join(root, SOURCES_FILE)}; "
            f"ask the owner for a location, then run:\n"
            f"  resolve-writing-sources.py set-draft-location <path> --root {root}\n"
        )
        return NEEDS_PROMPT
    print(val)
    return 0


def cmd_set_draft_location(args):
    root = host_root(args.root)
    lines = read_lines(root)
    new_lines, changed = set_output_drafts(lines, args.path)
    if changed:
        write_lines(root, new_lines)
    print(get_output_drafts(new_lines))
    return 0


def cmd_sources(args):
    root = host_root(args.root)
    for s in get_sources(read_lines(root), root):
        print(s["path"])
    return 0


def cmd_is_declared(args):
    root = host_root(args.root)
    target = os.path.join(root, args.path) if not os.path.isabs(args.path) else args.path
    for s in get_sources(read_lines(root), root):
        if _contains(s["path"], target):
            return 0
    sys.stderr.write(f"not a declared source: {args.path}\n")
    return 1


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", help="host-repo root (default: git top-level, else cwd)")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("draft-location")
    sp = sub.add_parser("set-draft-location")
    sp.add_argument("path")
    sub.add_parser("sources")
    sp = sub.add_parser("is-declared")
    sp.add_argument("path")
    args = p.parse_args(argv)
    return {
        "draft-location": cmd_draft_location,
        "set-draft-location": cmd_set_draft_location,
        "sources": cmd_sources,
        "is-declared": cmd_is_declared,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
