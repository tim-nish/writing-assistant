#!/usr/bin/env python3
"""read-policy-source.py — bounded, pinned, READ-ONLY policy reader (Story 14.2,
SPEC-policy-source-seam CAP-2).

Reads the recall surface of the policy repo named by `policy_source` in the
host repo's writing-sources.yaml, for Stage-2 question seeding. The read scope
is a code-level allowlist — the read function takes the whitelist and refuses
everything else, so no prompt can widen the seam:

  * `GLOSSARY.md` and `LESSONS.md`, always;
  * at most 2 `topics/*.md` files — the per-run `read --topics` selection the
    owner approved in draft-article Stage 2 (Story 13.35). No selection means
    GLOSSARY + LESSONS only — still a valid seeded run. (The per-repo
    `track`/`topics` config keys were removed — Story 13.36.)
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
  list-topics      Print the available topics/*.md basenames, one per line —
                   names only, never content (Story 13.35 step 1: the listing
                   the per-run selection question is built from).
  read [--only NAME ...] [--topics NAME.md ...]
                   Print the pin, then each whitelisted file's content with
                   line numbers. --only restricts to the named whitelist
                   entries (relative path or basename); naming ANY path outside
                   the whitelist is refused with exit 5 — that refusal is the
                   enforcement test, not a convention. --topics (Story 13.35,
                   SPEC-policy-topic-at-draft CAP-2) BUILDS the whitelist from
                   the given <=2 basenames under topics/ — distinct from
                   --only, which filters within an already-built whitelist;
                   >2 names or a non-basename is refused (exit 5).

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

MAX_TOPICS = 2  # CAP-2: at most 2 topic files per read
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


def build_whitelist(policy_root, block, override_topics=None):
    """The code-enforced allowlist: [(rel, full, exists)].

    GLOSSARY + LESSONS always; then <=2 topics — the per-run `--topics`
    selection when given (Story 13.35, SPEC-policy-topic-at-draft CAP-2),
    else none. A candidate whose realpath escapes the policy root
    (symlink/.. tricks) is dropped here, so it never becomes readable.
    """
    entries = []
    for rel in BASE_FILES:
        full = os.path.join(policy_root, rel)
        entries.append((rel, full, os.path.isfile(full) and _inside(policy_root, full)))
    topics = []
    if override_topics is not None:
        for t in override_topics[:MAX_TOPICS]:
            topics.append(os.path.join(policy_root, "topics", t))
    # No per-run selection -> GLOSSARY + LESSONS only. The config
    # `track`/`topics` keys were removed (Story 13.36, SPEC-policy-topic-at-
    # draft CAP-3): which topics an article reads is chosen per-article in
    # Stage 2 and arrives here as --topics; there is no per-repo topic config.
    for full in topics:
        rel = os.path.relpath(full, policy_root)
        entries.append((rel, full, os.path.isfile(full) and _inside(policy_root, full)))
    return entries


def validate_run_topics(names):
    """Validate a per-run --topics selection BEFORE it can build a whitelist
    (Story 13.35): basenames only, at most MAX_TOPICS. Returns an error string
    or None. Widening 'which two files' is the feature; widening 'how many' or
    'what else is readable' is refused in code."""
    if len(names) > MAX_TOPICS:
        return (f"refused: --topics takes at most {MAX_TOPICS} files "
                f"(got {len(names)}) — the ≤{MAX_TOPICS} cap is code-enforced")
    for t in names:
        if "/" in t or os.sep in t or ".." in t or t.startswith("."):
            return (f"refused: --topics entries are basenames under topics/ "
                    f"({t!r} is not) — no other path is readable")
    return None


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


def cmd_list_topics(args):
    """Names only — a whitelist listing, never a content read (Story 13.35
    step 1): the owner picks from these; nothing is opened here."""
    root = RWS.host_root(args.root)
    block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    policy_root, _pin, err = policy_repo(block)
    if err:
        return _unavailable(err)
    tdir = os.path.join(policy_root, "topics")
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(glob.escape(tdir), "*.md"))
                   if _inside(policy_root, p))
    for n in names:
        print(n)
    return 0


def cmd_read(args):
    root = RWS.host_root(args.root)
    block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    policy_root, pin, err = policy_repo(block)
    if err:
        return _unavailable(err)
    override = getattr(args, "topics", None)
    if override is not None:
        bad = validate_run_topics(override)
        if bad:
            sys.stderr.write(bad + "\n")
            return REFUSED
    whitelist = build_whitelist(policy_root, block, override_topics=override)
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
    sub.add_parser("list-topics", parents=[root_parent])
    sp = sub.add_parser("read", parents=[root_parent])
    sp.add_argument("--only", nargs="+",
                    help="restrict to these whitelist entries; anything else is refused (exit 5)")
    sp.add_argument("--topics", nargs="+", metavar="NAME.md",
                    help="per-run topic selection (Story 13.35): BUILD the "
                    "whitelist from these <=2 basenames under topics/ instead "
                    "of the config track/topics (distinct from --only, which "
                    "filters within an already-built whitelist); >2 or a "
                    "non-basename is refused (exit 5)")
    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    return {"whitelist": cmd_whitelist, "pin": cmd_pin,
            "list-topics": cmd_list_topics, "read": cmd_read}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
