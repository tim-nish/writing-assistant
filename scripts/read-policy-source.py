#!/usr/bin/env python3
"""read-policy-source.py — bounded, pinned, READ-ONLY policy reader (Story 14.2,
SPEC-policy-source-seam CAP-2).

Reads the recall surface of the policy repo named by `policy_source` in the
host repo's writing-sources.yaml, for Stage-2 question seeding. The read scope
is a code-level allowlist — the read function takes the whitelist and refuses
everything else, so no prompt can widen the seam:

  * `GLOSSARY.md` and `LESSONS.md`, always;
  * at most 2 `topics/*.md` files — the explicit `policy_source.topics` list
    when declared, else `topics/<track>*.md` matched by filename stem from
    `policy_source.track` (sorted, first 2). No track and no topics list means
    GLOSSARY + LESSONS only — still a valid seeded run.
  * `q_a/` and every other path are structurally unreadable; a symlink or `..`
    escaping the policy root is refused, not followed.

Every run is pinned: the reader records `product-lab@<commit>` from
`git rev-parse HEAD` at the policy path — one call per run, so every emitted
line shares one pin — and prints content line-numbered so the caller can quote
with `file:line@commit` pointers (the harvest convention; validate-fact-sheet's
FILEPIN grammar). The reader never creates or modifies any file under the
policy path.

Subcommands (each takes --root, the HOST repo root; default: git top-level):

  whitelist        Print the resolved allowlist, one path per line (relative to
                   the policy root). Absent whitelisted files are listed with an
                   `absent: ` prefix — a missing GLOSSARY is a note, not a failure.
  pin              Print `product-lab@<commit>`.
  read [--only NAME ...]
                   Print the pin, then each whitelisted file's content with
                   line numbers. --only restricts to the named whitelist
                   entries (relative path or basename); naming ANY path outside
                   the whitelist is refused with exit 5 — that refusal is the
                   enforcement test, not a convention.

Exit codes — the caller keys graceful degradation (CAP-6) off these:

  0   success
  2   usage / host-root resolution errors
  4   policy_source block malformed (resolver's report relayed verbatim;
      stage-0 validation should have caught this first)
  5   REFUSED: a requested path is outside the code whitelist
  10  unavailable: policy_source not declared        (degrade: generic mode, silent)
  11  unavailable: path missing or not a directory   (degrade: generic mode, log once)
  12  unavailable: path is not a git repository      (degrade: generic mode, log once)

For 10-12 a single `policy_source unavailable: <reason>` line goes to stderr —
the one line Stage 2 logs before degrading; the run never fails because of the
policy source.
"""

import argparse
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys

REFUSED = 5
MALFORMED = 4
UNAVAIL_UNSET = 10
UNAVAIL_PATH = 11
UNAVAIL_GIT = 12

MAX_TOPICS = 2  # CAP-2: at most 2 track-matched topic files
BASE_FILES = ("GLOSSARY.md", "LESSONS.md")


def _load_rws():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


RWS = _load_rws()


def resolve_policy_source(root):
    """The declared policy_source block via the one config parse path.

    Returns (block, None) or (None, (exit_code, reason))."""
    block, errors = RWS.get_policy_source(RWS.read_lines(root), root)
    if block is None:
        return None, (UNAVAIL_UNSET, "policy_source not declared in writing-sources.yaml")
    if errors:
        for key, msg in errors:
            sys.stderr.write(f"[{RWS.SOURCES_FILE}] {key}: {msg}\n")
        return None, (MALFORMED, "policy_source block is malformed (see stage-0 validation)")
    return block, None


def policy_repo(block):
    """Validate usability of the declared path. Returns (path, pin, None) or
    (None, None, (exit_code, reason))."""
    path = block["path"]
    if not os.path.isdir(path):
        return None, None, (UNAVAIL_PATH, f"path does not exist or is not a directory: {path}")
    try:
        p = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"],
                           capture_output=True, text=True)
    except FileNotFoundError:  # pragma: no cover - git always present in this env
        return None, None, (UNAVAIL_GIT, "git is not available")
    if p.returncode != 0:
        return None, None, (UNAVAIL_GIT, f"not a git repository (or no commits): {path}")
    return path, p.stdout.strip(), None


def _inside(parent, child):
    parent = os.path.realpath(parent)
    child = os.path.realpath(child)
    return child == parent or child.startswith(parent + os.sep)


def build_whitelist(policy_root, block):
    """The code-enforced allowlist: [(rel, full, exists)].

    GLOSSARY + LESSONS always; then <=2 topics — the explicit list when
    declared, else `topics/<track>*.md` by filename stem. A candidate whose
    realpath escapes the policy root (symlink/.. tricks) is dropped here, so
    it never becomes readable.
    """
    entries = []
    for rel in BASE_FILES:
        full = os.path.join(policy_root, rel)
        entries.append((rel, full, os.path.isfile(full) and _inside(policy_root, full)))
    topics = []
    if block["topics"]:
        for t in block["topics"][:MAX_TOPICS]:
            if "/" in t or ".." in t or t.startswith("."):
                continue  # defense in depth; the resolver already rejects these
            topics.append(os.path.join(policy_root, "topics", t))
    elif block["track"]:
        pattern = os.path.join(policy_root, "topics", glob.escape(block["track"]) + "*.md")
        topics = sorted(glob.glob(pattern))[:MAX_TOPICS]
    for full in topics:
        rel = os.path.relpath(full, policy_root)
        entries.append((rel, full, os.path.isfile(full) and _inside(policy_root, full)))
    return entries


def read_whitelisted(policy_root, rel, whitelist):
    """THE read function: takes the allowlist, refuses everything else.

    Returns (lines, None, rel) on success, (None, "refused", msg) for a path
    outside the whitelist, (None, "absent", rel) for a whitelisted file that is
    missing or escapes the policy root. Every byte the reader emits passes
    through here — there is no other file access path.
    """
    match = next((e for e in whitelist
                  if e[0] == rel or os.path.basename(e[0]) == rel), None)
    if match is None:
        return None, "refused", (
            f"refused: {rel!r} is not on the policy read whitelist "
            f"({', '.join(e[0] for e in whitelist)}); q_a/ and all other "
            "paths are structurally unreadable")
    rel, full, exists = match
    if not exists:
        return None, "absent", rel
    with open(full, encoding="utf-8") as fh:
        return fh.read().split("\n"), None, rel


def _unavailable(code_reason):
    code, reason = code_reason
    if code in (UNAVAIL_UNSET, UNAVAIL_PATH, UNAVAIL_GIT):
        sys.stderr.write(f"policy_source unavailable: {reason}\n")
    return code


def cmd_whitelist(args):
    root = RWS.host_root(args.root)
    block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    policy_root, _pin, err = policy_repo(block)
    if err:
        return _unavailable(err)
    for rel, _full, exists in build_whitelist(policy_root, block):
        print(rel if exists else f"absent: {rel}")
    return 0


def cmd_pin(args):
    root = RWS.host_root(args.root)
    block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    _policy_root, pin, err = policy_repo(block)
    if err:
        return _unavailable(err)
    print(f"product-lab@{pin}")
    return 0


def cmd_read(args):
    root = RWS.host_root(args.root)
    block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    policy_root, pin, err = policy_repo(block)
    if err:
        return _unavailable(err)
    whitelist = build_whitelist(policy_root, block)
    targets = args.only or [e[0] for e in whitelist]
    print(f"pin: product-lab@{pin}")
    for name in targets:
        lines, kind, detail = read_whitelisted(policy_root, name, whitelist)
        if kind == "refused":
            sys.stderr.write(detail + "\n")
            return REFUSED
        if kind == "absent":
            print(f"absent: {detail}")
            continue
        print(f"=== {detail} @ {pin}")
        for i, ln in enumerate(lines, 1):
            print(f"{i}: {ln}")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ROOT_HELP = "HOST-repo root (default: git top-level of cwd; errors outside a git repo)"
    p.add_argument("--root", help=ROOT_HELP)
    root_parent = argparse.ArgumentParser(add_help=False)
    root_parent.add_argument("--root", default=argparse.SUPPRESS, help=ROOT_HELP)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("whitelist", parents=[root_parent])
    sub.add_parser("pin", parents=[root_parent])
    sp = sub.add_parser("read", parents=[root_parent])
    sp.add_argument("--only", nargs="+",
                    help="restrict to these whitelist entries; anything else is refused (exit 5)")
    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    return {"whitelist": cmd_whitelist, "pin": cmd_pin, "read": cmd_read}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
