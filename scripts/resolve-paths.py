#!/usr/bin/env python3
"""THE path resolver — the single source of every plugin storage path (Story 9.1).

`docs/storage-architecture.md` D1 fixes one invariant: the plugin never writes
state or intermediate artifacts into a host repo's working tree, and *every*
storage path — config lookup, state root, per-run workspaces — resolves through
this one helper. No other script, skill, or prompt may compose a state or
workspace path itself; the directory scheme behind these commands is an
implementation detail with exactly one migration point (this file).

Layout (D3 — evolvable behind the commands, not contractual):

    $XDG_STATE_HOME/writing-assistant/     # state root; default ~/.local/state/writing-assistant
      <repo-key>/                          # path slug of the repo's git toplevel
        runs/<run-id>/                     # per-invocation workspace (Story 9.2)

Config lookup (machine-global identity, `~/.config/writing-assistant`) is exposed
here too so nothing else hardcodes it; the existing config resolvers keep their
current contract pending `docs/storage-architecture.md` O1.

Stdlib-only by design (host repos guarantee no venv), matching the no-JS
constraint. Every command prints one absolute path to stdout.

Subcommands:
  state-root                 the state root ($XDG_STATE_HOME/writing-assistant or default)
  config-home                the machine-global config dir (~/.config/writing-assistant)
  repo-key   [--root R]      path slug of the repo's git toplevel
  repo-dir   [--root R]      <state-root>/<repo-key> (the per-repo state directory)
"""

import argparse
import os
import re
import subprocess
import sys

PLUGIN = "writing-assistant"


# --------------------------------------------------------------------------
# Roots
# --------------------------------------------------------------------------
def host_root(arg_root):
    """The host repo root: explicit --root, else git toplevel, else cwd.

    Mirrors scripts/resolve-user-config.py so both resolvers agree on which
    repo they are keyed to.
    """
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


def state_root():
    """$XDG_STATE_HOME/writing-assistant, or ~/.local/state/writing-assistant.

    An empty/unset $XDG_STATE_HOME falls back to the default, per the XDG base
    directory spec.
    """
    xdg = os.environ.get("XDG_STATE_HOME")
    base = xdg if xdg else os.path.expanduser("~/.local/state")
    return os.path.join(base, PLUGIN)


def config_home():
    """~/.config/writing-assistant (machine-global identity config lives here).

    Honours $XDG_CONFIG_HOME for symmetry; the identity resolver's default is
    the same location.
    """
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = xdg if xdg else os.path.expanduser("~/.config")
    return os.path.join(base, PLUGIN)


def repo_key(root):
    """Path slug of the repo's git toplevel — the scheme Claude Code uses for
    its own project directories: every run of non-alphanumeric characters in
    the absolute path becomes a single '-'.

    e.g. /home/ada/work/blog -> -home-ada-work-blog
    Stdlib-trivial and debuggable by eye. Moving a repo orphans its old key
    (acceptable — run contents are disposable); if that ever matters the
    scheme evolves inside this function (D3).
    """
    return re.sub(r"[^A-Za-z0-9]+", "-", root)


def repo_dir(root):
    return os.path.join(state_root(), repo_key(root))


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def cmd_state_root(args):
    print(state_root())
    return 0


def cmd_config_home(args):
    print(config_home())
    return 0


def cmd_repo_key(args):
    print(repo_key(host_root(args.root)))
    return 0


def cmd_repo_dir(args):
    print(repo_dir(host_root(args.root)))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("state-root", help="print the state root")
    sub.add_parser("config-home", help="print the machine-global config dir")

    sp = sub.add_parser("repo-key", help="print the repo key (path slug of git toplevel)")
    sp.add_argument("--root", help="host-repo root (default: git top-level, else cwd)")

    sp = sub.add_parser("repo-dir", help="print <state-root>/<repo-key>")
    sp.add_argument("--root", help="host-repo root (default: git top-level, else cwd)")

    args = p.parse_args(argv)
    return {
        "state-root": cmd_state_root,
        "config-home": cmd_config_home,
        "repo-key": cmd_repo_key,
        "repo-dir": cmd_repo_dir,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
