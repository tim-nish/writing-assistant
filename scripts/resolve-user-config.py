#!/usr/bin/env python3
"""Resolve the owner's identity config into one merged value (CAP-6).

Resolution order (the single documented order every skill must follow):

  1. machine-global : $WRITING_ASSISTANT_USER_CONFIG, else
                      ~/.config/writing-assistant/user-config.yaml
  2. repo-local     : <host-repo>/config/user-config.yaml   (override, if present)

The repo-local file is a DEEP PER-KEY MERGE over the machine-global one: maps are
merged recursively; scalars and lists are replaced wholesale. At least one of the
two must exist — if neither resolves, this errors (skills assume identity always
resolves; there is no baked-in default identity, which is what keeps the engine
generic).

Stdlib-only by design (host repos guarantee no venv / no PyYAML), so it parses
the documented YAML subset directly and emits JSON — downstream skills then read
identity with the stdlib `json` module. The subset: 2-space-nested maps, block
scalars (`key: |`), inline lists (`[a, b]`), lists of scalars (`- item`), and
quoted/bare/int/bool scalars. Lists of maps are intentionally unsupported here
(user-config has none) and raise rather than misparse.

Subcommands:
  resolved [--as json]   print the fully merged config as JSON (default)
  get KEYPATH            print the value at a dotted key path (e.g. owner.site_url);
                         scalars print raw, maps/lists print as JSON
"""

import argparse
import json
import os
import re
import subprocess
import sys


# --------------------------------------------------------------------------
# YAML-subset parser
# --------------------------------------------------------------------------
class YamlSubsetError(ValueError):
    pass


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def _parse_scalar(s):
    s = s.strip()
    if s == "" or s == "~" or s.lower() == "null":
        return None
    if s[0] in "\"'":
        q = s[0]
        end = s.find(q, 1)
        if end == -1:
            raise YamlSubsetError(f"unterminated quote: {s}")
        return s[1:end]
    if s[0] == "[":
        inner = s[s.find("[") + 1 : s.rfind("]")]
        if inner.strip() == "":
            return []
        return [_parse_scalar(x) for x in inner.split(",")]
    s = re.sub(r"\s+#.*$", "", s).strip()  # strip trailing inline comment
    if s.lower() in ("true", "false"):
        return s.lower() == "true"
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    return s


class _Parser:
    def __init__(self, text):
        self.lines = text.split("\n")
        self.i = 0

    def _cur(self):
        while self.i < len(self.lines):
            ln = self.lines[self.i]
            s = ln.strip()
            if s == "" or s.startswith("#"):
                self.i += 1
                continue
            return ln
        return None

    def parse(self):
        ln = self._cur()
        return {} if ln is None else self.parse_block(0)

    def parse_block(self, min_indent):
        ln = self._cur()
        if ln is None or _indent(ln) < min_indent:
            return None
        if ln.lstrip().startswith("- "):
            return self.parse_list(_indent(ln))
        return self.parse_map(_indent(ln))

    def parse_map(self, indent):
        out = {}
        while True:
            ln = self._cur()
            if ln is None or _indent(ln) != indent or ln.lstrip().startswith("- "):
                break
            body = ln.lstrip()
            m = re.match(r"^([^:]+):(?:\s+(.*))?\s*$", body)
            if not m:
                raise YamlSubsetError(f"cannot parse map line: {ln!r}")
            key = m.group(1).strip()
            rest = (m.group(2) or "").strip()
            self.i += 1
            if rest == "":
                child = self.parse_block(indent + 1)
                out[key] = child
            elif rest in ("|", "|-", ">", ">-"):
                out[key] = self.parse_block_scalar(indent, rest)
            else:
                out[key] = _parse_scalar(rest)
        return out

    def parse_list(self, indent):
        out = []
        while True:
            ln = self._cur()
            if ln is None or _indent(ln) != indent or not ln.lstrip().startswith("- "):
                break
            content = ln.lstrip()[2:].strip()
            if re.match(r"^[^:\s]+:(\s|$)", content):
                raise YamlSubsetError(
                    "lists of maps are unsupported in the user-config subset: "
                    f"{ln!r}"
                )
            self.i += 1
            out.append(_parse_scalar(content))
        return out

    def parse_block_scalar(self, key_indent, style):
        collected, base = [], None
        while self.i < len(self.lines):
            ln = self.lines[self.i]
            if ln.strip() == "":
                collected.append("")
                self.i += 1
                continue
            if _indent(ln) <= key_indent:
                break
            if base is None:
                base = _indent(ln)
            collected.append(ln[base:])
            self.i += 1
        while collected and collected[-1] == "":
            collected.pop()
        if style.startswith(">"):
            return " ".join(collected)  # crude fold; user-config uses only `|`
        text = "\n".join(collected)
        return text if style.endswith("-") else text + "\n"


def load_yaml(text):
    return _Parser(text).parse()


# --------------------------------------------------------------------------
# Resolution
# --------------------------------------------------------------------------
def deep_merge(base, over):
    """Deep per-key merge: maps recurse; scalars and lists are replaced."""
    if isinstance(base, dict) and isinstance(over, dict):
        out = dict(base)
        for k, v in over.items():
            out[k] = deep_merge(base[k], v) if k in base else v
        return out
    return over


def host_root(arg_root):
    """The host repo root: explicit --root, else git toplevel of cwd.

    Never falls back to a bare cwd — outside a git repo this exits 2 telling
    the caller to pass --root, instead of silently keying to whatever
    directory the script happened to run from. Mirrored in
    scripts/resolve-paths.py and scripts/resolve-writing-sources.py; keep the
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


def global_config_path(args):
    if args.global_config:
        return args.global_config
    env = os.environ.get("WRITING_ASSISTANT_USER_CONFIG")
    if env:
        return env
    return os.path.expanduser("~/.config/writing-assistant/user-config.yaml")


def repo_config_path(args):
    if args.repo_config:
        return args.repo_config
    return os.path.join(host_root(args.root), "config", "user-config.yaml")


def _load_file(path):
    if not path or not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return load_yaml(fh.read())


def resolve(args):
    g_path, r_path = global_config_path(args), repo_config_path(args)
    g, r = _load_file(g_path), _load_file(r_path)
    if g is None and r is None:
        raise SystemExit(
            "error: no user-config resolved.\n"
            f"  looked for machine-global: {g_path}\n"
            f"  and repo-local override:   {r_path}\n"
            "  copy config/user-config.example.yaml to the machine-global path "
            "and fill in your identity."
        )
    if g is None:
        return r
    if r is None:
        return g
    return deep_merge(g, r)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def cmd_resolved(args):
    print(json.dumps(resolve(args), indent=2, ensure_ascii=False))
    return 0


def cmd_get(args):
    cur = resolve(args)
    for part in args.keypath.split("."):
        if not isinstance(cur, dict) or part not in cur:
            sys.stderr.write(f"error: key path not found: {args.keypath}\n")
            return 1
        cur = cur[part]
    if isinstance(cur, (dict, list)):
        print(json.dumps(cur, ensure_ascii=False))
    elif isinstance(cur, bool):
        print("true" if cur else "false")
    elif cur is None:
        print("")
    else:
        print(cur)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    p.add_argument("--global-config", help="override the machine-global config path")
    p.add_argument("--repo-config", help="override the repo-local config path")
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("resolved")
    sp.add_argument("--as", dest="as_fmt", choices=["json"], default="json")
    sp = sub.add_parser("get")
    sp.add_argument("keypath")
    args = p.parse_args(argv)
    return {"resolved": cmd_resolved, "get": cmd_get}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
