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

Config lookup (machine-global, `~/.config/writing-assistant`) is exposed here so
nothing else hardcodes it. Per-repo configuration (O1 resolved 2026-07-15, #211)
lives under the config home too:

    $XDG_CONFIG_HOME/writing-assistant/    # config home; default ~/.config/writing-assistant
      repos/<repo-key>/
        writing-sources.yaml               # per-repo declared sources — NEVER in the host repo

`sources_file()` is the single resolution point for that file: the machine-global
path wins; a legacy in-repo `writing-sources.yaml` is still honoured during
migration (with the caller expected to surface a deprecation notice — see
resolve-writing-sources.py). No other script may compose either location.

Stdlib-only by design (host repos guarantee no venv), matching the no-JS
constraint. Every command prints one absolute path to stdout.

Subcommands:
  state-root                 the state root ($XDG_STATE_HOME/writing-assistant or default)
  config-home                the machine-global config dir (~/.config/writing-assistant)
  repo-key   [--root R]      path slug of the repo's git toplevel
  repo-dir   [--root R]      <state-root>/<repo-key> (the per-repo state directory)
  repo-config-dir [--root R] <config-home>/repos/<repo-key> (per-repo config, O1/#211)
  sources-file [--root R]    the resolved writing-sources.yaml path for the repo:
                             machine-global if present, else a legacy in-repo file
                             (deprecation notice on stderr), else the machine-global
                             path where the file should be created (exit 3)
  new-run    [--root R] [--run-id ID]
                             create and print a fresh per-run workspace (Story 9.2)
  run-workspace --run-id ID [--root R]
                             print an existing run workspace path (no create)
"""

import argparse
import datetime
import os
import re
import subprocess
import sys

PLUGIN = "writing-assistant"


# --------------------------------------------------------------------------
# Roots
# --------------------------------------------------------------------------
def host_root(arg_root):
    """The host repo root: explicit --root, else git toplevel of cwd.

    Never falls back to a bare cwd — outside a git repo this exits 2 telling
    the caller to pass --root, instead of silently keying to whatever
    directory the script happened to run from. Mirrors
    scripts/resolve-user-config.py and scripts/resolve-writing-sources.py so
    all resolvers agree on which repo they are keyed to; keep the three in
    sync.
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


SOURCES_BASENAME = "writing-sources.yaml"


def repo_config_dir(root):
    """<config-home>/repos/<repo-key> — the per-repo configuration directory
    (O1 resolved 2026-07-15, #211). Same key scheme as the state root, so config
    and state for one repo always agree."""
    return os.path.join(config_home(), "repos", repo_key(root))


def sources_file(root):
    """Resolve the writing-sources.yaml for a host repo (O1, #211).

    Returns (path, kind):
      kind = 'global'  — machine-global file exists (wins even if a legacy
                         in-repo file also exists; callers surface the notice)
      kind = 'legacy'  — only the in-repo file exists (migration compatibility;
                         callers surface a deprecation notice)
      kind = 'none'    — neither exists; path is the machine-global location
                         where the file SHOULD be created (never the host root)
    The publication boundary behind this: a host repo may be public, and this
    file can carry private pointers — it must never need to live in the repo.
    """
    global_path = os.path.join(repo_config_dir(root), SOURCES_BASENAME)
    legacy_path = os.path.join(root, SOURCES_BASENAME)
    if os.path.isfile(global_path):
        return global_path, "global"
    if os.path.isfile(legacy_path):
        return legacy_path, "legacy"
    return global_path, "none"


def legacy_sources_file(root):
    """The legacy in-repo path (for callers composing the 'both exist' notice)."""
    return os.path.join(root, SOURCES_BASENAME)


def runs_dir(root):
    return os.path.join(repo_dir(root), "runs")


def _timestamp_run_id():
    """A timestamp-based, per-invocation-unique run id (D3): local time down to
    the microsecond, so two runs never collide on the same id."""
    now = datetime.datetime.now()
    return now.strftime("%Y%m%dT%H%M%S-") + f"{now.microsecond:06d}"


def new_run(root, run_id=None):
    """Create <repo-dir>/runs/<run-id>/ and return it (Story 9.2).

    Every intermediate a pipeline run produces — fact sheet, NEEDS-OWNER list,
    interview journal, provenance map, quality-gate output, scratch — lives
    under this one directory: one run = one debuggable, disposable unit, and
    the host working tree stays clean by construction. There is no
    state-vs-cache split (D2): all per-run artifacts share the workspace.

    An explicit --run-id must be fresh; without one, a unique id is minted, and
    on the astronomically unlikely microsecond collision a random suffix is
    appended until the directory does not already exist.
    """
    base = runs_dir(root)
    if run_id is not None:
        ws = os.path.join(base, run_id)
        os.makedirs(ws)  # exist_ok=False: an explicit id must be new
        return ws
    while True:
        ws = os.path.join(base, _timestamp_run_id())
        try:
            os.makedirs(ws)
            return ws
        except FileExistsError:
            ws = os.path.join(base, _timestamp_run_id() + "-" + os.urandom(3).hex())
            os.makedirs(ws, exist_ok=False)
            return ws


def run_workspace(root, run_id):
    return os.path.join(runs_dir(root), run_id)


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


def cmd_repo_config_dir(args):
    print(repo_config_dir(host_root(args.root)))
    return 0


def cmd_sources_file(args):
    root = host_root(args.root)
    path, kind = sources_file(root)
    if kind == "none":
        sys.stderr.write(
            f"no {SOURCES_BASENAME} for this repo; create it at {path} "
            f"(see config/writing-sources.example.yaml) — never in the host repo (#211)\n")
        print(path)
        return 3
    if kind == "legacy":
        sys.stderr.write(
            f"deprecated: {path} lives in the host repo; move it to "
            f"{os.path.join(repo_config_dir(root), SOURCES_BASENAME)} (#211)\n")
    print(path)
    return 0


def cmd_new_run(args):
    print(new_run(host_root(args.root), args.run_id))
    return 0


def cmd_run_workspace(args):
    print(run_workspace(host_root(args.root), args.run_id))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("state-root", help="print the state root")
    sub.add_parser("config-home", help="print the machine-global config dir")

    sp = sub.add_parser("repo-key", help="print the repo key (path slug of git toplevel)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("repo-dir", help="print <state-root>/<repo-key>")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("repo-config-dir", help="print <config-home>/repos/<repo-key>")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("sources-file", help="print the resolved writing-sources.yaml path")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("new-run", help="create and print a fresh per-run workspace")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--run-id", help="explicit run id (must not already exist; default: fresh timestamp id)")

    sp = sub.add_parser("run-workspace", help="print an existing run workspace path (no create)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--run-id", required=True, help="the run id whose workspace to print")

    args = p.parse_args(argv)
    return {
        "state-root": cmd_state_root,
        "config-home": cmd_config_home,
        "repo-key": cmd_repo_key,
        "repo-dir": cmd_repo_dir,
        "repo-config-dir": cmd_repo_config_dir,
        "sources-file": cmd_sources_file,
        "new-run": cmd_new_run,
        "run-workspace": cmd_run_workspace,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
