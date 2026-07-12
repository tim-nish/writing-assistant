#!/usr/bin/env python3
"""Resolve writing-sources.yaml: declared sources + draft output location.

Stdlib-only by design (host repos guarantee no venv / no PyYAML), so this reads
the small, flat writing-sources.yaml subset directly rather than through a YAML
library. Write-back is line surgery, so existing comments and ordering survive.

Subcommands (each takes --root; default: the git top-level of cwd — outside a
git repo the script errors rather than silently resolving against cwd):

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

  files                     Print the concrete allowlist of files harvest may
                            read: declared sources only, narrowed by `include`
                            globs, with `.git/` pruned and symlink/.. escapes
                            excluded. Fail-closed — no/malformed writing-sources
                            or a non-existent declared path yields nothing.
"""

import argparse
import glob
import os
import re
import subprocess
import sys

SOURCES_FILE = "writing-sources.yaml"

NEEDS_PROMPT = 3  # draft-location: no output.drafts declared


def host_root(arg_root):
    """Resolve the host-repo root: explicit --root, else git top-level of cwd.

    Never falls back to a bare cwd — outside a git repo this exits 2 telling
    the caller to pass --root, instead of silently keying to whatever
    directory the script happened to run from. Mirrored in
    scripts/resolve-paths.py and scripts/resolve-user-config.py; keep the
    three in sync.
    """
    if arg_root:
        real = os.path.realpath(arg_root)
        if not os.path.isdir(real):
            print(f"error: --root {arg_root!r} resolved to {real}, which is not a directory",
                  file=sys.stderr)
            sys.exit(2)
        return real
    try:
        top = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if top:
            return os.path.realpath(top)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    print(f"error: cannot resolve the host repo: {os.getcwd()} is not inside a git repository; "
          "pass --root <host-repo>", file=sys.stderr)
    sys.exit(2)


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


def enumerate_files(sources):
    """The concrete allowlist of files harvest may read: declared sources only,
    narrowed by any `include` globs, with `.git/` pruned and every path checked
    to stay inside its declared root (no symlink/.. escape). Fail-closed —
    undeclared or non-existent paths contribute nothing.
    """
    seen, out = set(), []
    for s in sources:
        root = s["path"]
        if os.path.isfile(root):        # a declared single-file source
            candidates = [root]
        elif os.path.isdir(root):
            if s["include"]:
                candidates = []
                for pat in s["include"]:
                    if ".." in pat.split("/"):
                        continue        # reject path-escaping include patterns
                    candidates += glob.glob(os.path.join(root, pat), recursive=True)
            else:
                candidates = []
                for dp, dn, fn in os.walk(root, followlinks=False):
                    dn[:] = [d for d in dn if d != ".git"]   # never descend VCS metadata
                    candidates += [os.path.join(dp, name) for name in fn]
        else:
            continue                    # non-existent declared path: read nothing

        for full in candidates:
            if not os.path.isfile(full):
                continue
            rel = os.path.relpath(full, root)
            if rel.split(os.sep)[0] == ".git":
                continue
            if not _contains(root, full):
                continue                # symlink / .. escaping the declared root
            real = os.path.realpath(full)
            if real in seen:
                continue
            seen.add(real)
            out.append(full)
    return sorted(out)


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


def cmd_files(args):
    root = host_root(args.root)
    for f in enumerate_files(get_sources(read_lines(root), root)):
        print(f)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ROOT_HELP = "host-repo root (default: git top-level of cwd; errors outside a git repo)"
    p.add_argument("--root", help=ROOT_HELP)
    # --root is accepted in BOTH positions — before OR after the subcommand — so
    # the invocation the SKILLs document (`… files --root <host>`) works (#138).
    # SUPPRESS default on the subparser copy avoids clobbering a --root given
    # before the subcommand.
    root_parent = argparse.ArgumentParser(add_help=False)
    root_parent.add_argument("--root", default=argparse.SUPPRESS, help=ROOT_HELP)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("draft-location", parents=[root_parent])
    sp = sub.add_parser("set-draft-location", parents=[root_parent])
    sp.add_argument("path")
    sub.add_parser("sources", parents=[root_parent])
    sp = sub.add_parser("is-declared", parents=[root_parent])
    sp.add_argument("path")
    sub.add_parser("files", parents=[root_parent])
    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    return {
        "draft-location": cmd_draft_location,
        "set-draft-location": cmd_set_draft_location,
        "sources": cmd_sources,
        "is-declared": cmd_is_declared,
        "files": cmd_files,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
