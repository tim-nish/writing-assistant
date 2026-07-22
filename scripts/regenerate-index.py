#!/usr/bin/env python3
"""regenerate-index.py — the articles repo's INDEX.md as a deterministic view
(Story 18.43, #540).

The articles repo declares its own contract in INDEX.md's header and README —
"regenerated — one line per backlog/draft/newsletter item" — but nothing carried
it out: a repo holding 4 drafts + 1 backlog item read `_Empty._`, so a
just-persisted draft was invisible on the repo's browsing surface (#540). That
is the "built but never invoked" pattern: a declared regeneration duty with no
carrier.

INDEX.md is a **view, never an authority**: it is a pure projection over the
item frontmatter the pipeline already wrote, so on any mismatch the files win
and regeneration is idempotent (regenerating a current index rewrites the same
bytes). It is NOT a third declared product — the two completion-gated products
stay the canonical draft and the article plan; a failed index write is a
disclosed warning, never the hard error those two carry.

Usage:
  regenerate-index.py write [--repo R | --root HOST]   # rewrite INDEX.md, print what changed
  regenerate-index.py check [--repo R | --root HOST]   # exit 0 fresh, 1 stale (prints the drift)

`--repo` names the articles repo root directly; `--root` resolves it from the
host's declared `output.drafts` (the drafts dir's parent), so callers that only
know the host repo need no second config.
"""
import argparse
import json
import os
import subprocess
import sys

SECTIONS = ("backlog", "drafts", "newsletter")   # fixed order — determinism
HEADER = "# INDEX\n\nRegenerated — one line per backlog/draft/newsletter item.\n"
EMPTY = "_Empty._"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _frontmatter(path):
    """Parse the leading `---` YAML block into a flat {key: value} of its
    TOP-LEVEL scalar keys. Stdlib-only and deliberately shallow: a key whose
    value is a block scalar (`>`/`|`), a nested mapping, or a list is skipped —
    the index only ever projects scalars (slug/title/one_liner/status/date), so
    a partial parse is correct rather than lossy. Continuation lines (indented)
    are never mistaken for keys."""
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            first = f.readline()
            if first.strip() != "---":
                return out
            for line in f:
                s = line.rstrip("\n")
                if s.strip() == "---":
                    break
                if not s or s[0] in " \t#-":
                    continue                     # continuation / comment / list item
                if ":" not in s:
                    continue
                key, _, val = s.partition(":")
                key = key.strip()
                val = val.split("   #")[0].strip()   # trailing inline comment
                if not val or val in (">", "|", "{", "["):
                    continue                     # block scalar / nested opener
                if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                    val = val[1:-1]
                out[key] = val
    except OSError:
        return out
    return out


def _item(path):
    """Project one item file to (slug, title, detail). Filename stem is the
    fallback slug so an item without a `slug:` key still lists."""
    fm = _frontmatter(path)
    slug = fm.get("slug") or os.path.splitext(os.path.basename(path))[0]
    title = fm.get("title") or fm.get("one_liner") or slug
    # `status` (backlog) and `date` (drafts) are both optional; whichever the
    # item carries becomes its trailing detail, in a fixed order.
    bits = [b for b in (fm.get("status"), fm.get("date")) if b]
    return slug, title, " · ".join(bits)


def render(repo):
    """Render INDEX.md's full text from the repo's item frontmatter. Pure and
    deterministic: sections in fixed order, items sorted by slug."""
    blocks = []
    for section in SECTIONS:
        d = os.path.join(repo, section)
        if not os.path.isdir(d):
            continue
        items = []
        for name in sorted(os.listdir(d)):
            if not name.endswith(".md") or name.startswith("."):
                continue
            items.append(_item(os.path.join(d, name)))
        if not items:
            continue
        lines = [f"## {section}", ""]
        for slug, title, detail in sorted(items):
            lines.append(f"- `{slug}` — {title}" + (f" · {detail}" if detail else ""))
        blocks.append("\n".join(lines))
    body = "\n\n".join(blocks) if blocks else EMPTY
    return HEADER + "\n" + body + "\n"


def _repo_from_root(root):
    """The articles repo root = the parent of the declared `output.drafts` dir."""
    cmd = [sys.executable, os.path.join(SCRIPT_DIR, "resolve-writing-sources.py"),
           "draft-location"]
    if root:
        cmd += ["--root", root]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        return None
    drafts = r.stdout.strip()
    return os.path.dirname(os.path.abspath(drafts)) if drafts else None


def _resolve(args):
    repo = args.repo or _repo_from_root(args.root)
    if not repo or not os.path.isdir(repo):
        sys.stderr.write(
            f"error: cannot resolve the articles repo (repo={repo!r}) — pass "
            "--repo <articles-repo> or --root <host-repo> with output.drafts declared\n")
        return None
    return repo


def cmd_write(args):
    repo = _resolve(args)
    if repo is None:
        return 2
    path = os.path.join(repo, "INDEX.md")
    new = render(repo)
    old = ""
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as f:
                old = f.read()
        except OSError as e:
            sys.stderr.write(f"error: cannot read {path}: {e}\n")
            return 1
    if old == new:
        print(json.dumps({"index": path, "changed": False}))
        return 0            # idempotent: a current index is a no-op
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(new)
        os.replace(tmp, path)
    except OSError as e:
        sys.stderr.write(f"error: cannot write {path}: {e}\n")
        return 1
    print(json.dumps({"index": path, "changed": True}))
    return 0


def cmd_check(args):
    """Staleness detection for the disclosure path: exit 0 when INDEX.md already
    matches its projection, 1 when it drifted (naming the drift), so a run that
    does not regenerate can still DISCLOSE rather than silently widen the gap."""
    repo = _resolve(args)
    if repo is None:
        return 2
    path = os.path.join(repo, "INDEX.md")
    new = render(repo)
    old = ""
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as f:
                old = f.read()
        except OSError as e:
            sys.stderr.write(f"error: cannot read {path}: {e}\n")
            return 2
    if old == new:
        print(f"INDEX.md is current ({path})")
        return 0
    listed = sum(1 for ln in old.split("\n") if ln.startswith("- `"))
    actual = sum(1 for ln in new.split("\n") if ln.startswith("- `"))
    print(f"INDEX.md is stale ({path}): lists {listed} item(s), the repo holds "
          f"{actual} — regenerate with `regenerate-index.py write`")
    return 1


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, help_ in (("write", "rewrite INDEX.md from item frontmatter"),
                        ("check", "exit 1 if INDEX.md drifted from its projection")):
        sp = sub.add_parser(name, help=help_)
        sp.add_argument("--repo", help="articles repo root (contains backlog/ drafts/ newsletter/)")
        sp.add_argument("--root", help="host repo; resolves the articles repo from output.drafts")
    args = p.parse_args(argv)
    return {"write": cmd_write, "check": cmd_check}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
