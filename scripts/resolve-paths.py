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
  terrain-briefs-dir [--root R]
                             the Brief's durable home for this host repo
                             (Story 20.191) — a query, creating nothing
  terrain-brief --id ID [--root R]
                             the home path of ONE Brief, by its stable id
  list-briefs [--root R]     every Brief in the home, one path per line: the
                             listing IS the enumeration, and no index exists
  active-run-pointer [--cwd D]
                             <state-root>/<cwd-key>/active-run.json — the run
                             pointer the checkpoint write leaves for the Stop
                             hook, keyed on the SESSION's cwd (Story 20.156)
"""

import argparse
import datetime
import importlib.util
import json
import os
import re
import subprocess
import sys

PLUGIN = "writing-assistant"


# --------------------------------------------------------------------------
# Roots
# --------------------------------------------------------------------------
def _cwd_toplevel():
    """The git toplevel of cwd, realpath'd — or None when cwd is not in a repo.

    Separated from host_root so the --root branch can report a disagreement
    without changing precedence (#309).
    """
    try:
        top = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return os.path.realpath(top) if top else None
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def _toplevel_of(path):
    """The git toplevel containing `path`, realpath'd — or None when `path` is
    not inside a git repository (or git is unavailable).

    Exists because testing `os.path.isdir(<path>/.git)` is WRONG in a linked
    git worktree, where `.git` is a regular FILE holding a `gitdir:` pointer
    (#1005). Every resolver here that needs "is this a repo, and which one"
    asks git, exactly as `_cwd_toplevel` already did for cwd — the two differ
    only in which directory the question is asked from.

    The failure this fixes is silent and misattributed: a resolver that decides
    "not a repo" inside a worktree falls back to the state root, and the
    breakage surfaces several layers away as an unrelated assertion about
    where a workspace lives, never as "you are in a worktree".

    `path` need not exist; the nearest existing ancestor is probed instead, so
    a not-yet-created destination directory still resolves to its repo.
    """
    probe = os.path.abspath(path)
    while not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            return None
        probe = parent
    try:
        top = subprocess.run(
            ["git", "-C", probe, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return os.path.realpath(top) if top else None
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


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
    top = _cwd_toplevel()
    if top:
        return top
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


def plugin_root():
    """This plugin's own repository root — the directory holding `scripts/`."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def terrain_output_root():
    """Where this tool's outputs and debug artifacts live (D2, amended
    2026-07-28, #874 — owner ruling).

    Terrain is a writing-assistant feature, so its outputs and its debug
    artifacts belong in the writing-assistant repository: the repo the human
    works in for this feature. The resolver owns the choice, per D1 — no
    caller composes it and no literal appears anywhere else.

    **"The writing-assistant repo" is one place only when the plugin runs from
    a working tree.** Installed, it is a marketplace clone under
    `~/.claude/plugins/` that the owner does not work in and that is known to
    go stale; writing per-run data there puts it where no human will look. So
    an installed clone falls back to the machine state root, which is where
    these artifacts lived before the ruling and remains a correct place for
    them — the ruling moves them TOWARD the human, and a location no human
    opens does not satisfy it.

    "Runs from a working tree" is asked of git, never of `.git`'s file type: a
    LINKED WORKTREE's `.git` is a regular file, so an `isdir` test read every
    worktree as an installed clone and sent its artifacts to the state root
    (#1005). A worktree of this repo is a working tree the owner works in, and
    resolves here exactly like the main one.
    """
    here = plugin_root()
    installed = os.path.join(os.path.expanduser("~"), ".claude", "plugins")
    if os.path.commonpath([os.path.abspath(here), os.path.abspath(installed)]) \
            == os.path.abspath(installed):
        return state_root()
    if _toplevel_of(here) != os.path.realpath(here):
        return state_root()
    return os.path.join(here, TERRAIN_OUTPUT_DIR)


def repo_dir(root):
    return os.path.join(state_root(), repo_key(root))


def terrain_repo_dir(root):
    """Terrain's per-host directory under the terrain output root — the
    OWNER-FACING OUTPUT surface, which after 2026-07-30 means the View alone.

    SCOPED DELIBERATELY (#874), then NARROWED (#935). #874 moved Terrain's
    outputs and its debug artifacts here on the ground that they belong where
    the owner works. Half of that held and half did not: the View is opened by
    a human, so it belongs in a tree; run workspaces are per-invocation
    intermediates that nothing reopens, and roughly forty repo-key directories
    accumulated in the working tree with no mechanism owning their deletion —
    most of them `-tmp-tmp-*-host-repo` leftovers from test and dogfood runs.
    So the class split runs at this seam: output stays, intermediates go back
    to the machine state root (see `terrain_runs_dir`).

    The draft pipeline's harvest caches, plan fallbacks and stage checkpoints
    were never in scope and never moved — a wholesale move was tried first and
    four unrelated checks failed on it, which is the subsystems saying,
    correctly, that the ruling did not reach them.
    """
    return os.path.join(terrain_output_root(), repo_key(root))


def terrain_runs_dir(root):
    """Terrain's run workspaces — INTERMEDIATES, under the machine state root.

    RELOCATED 2026-07-30 (#935), reversing this half of #874. A run workspace
    holds the map, the payload and the recorded answer; nothing reopens it
    after the invocation, so "put it where the owner works" buys nothing and
    costs an unbounded pile of directories in a public working tree carrying
    verbatim hub renderings. #874's owed retention rule is discharged BY
    RELOCATION rather than by a GC mechanism — there is deliberately no
    collector here.

    Distinct from `runs_dir` so Terrain and the draft pipeline cannot collide
    on a run id, and named for its subsystem rather than nested under it.
    """
    return os.path.join(repo_dir(root), "terrain-runs")


# --------------------------------------------------------------------------
# The active-run pointer — the Stop hook's SUBJECT (Story 20.156, #1245/#1247)
#
# The Stop hook runs outside the model, in a process the pipeline never spawns,
# and its only documented handle on the session is the payload's `cwd`. Before
# this, it resolved its subject from `WA_RUN_WS` or `payload["cwd_run_ws"]` —
# an environment variable nothing set and a payload field the harness does not
# supply — so `ws` was always None and the hook exited 0 on every turn as "not
# a pipeline turn at all". Three cycles' worth of gates closed un-carried
# behind that silence.
#
# So the pointer gets a WRITER, at the one place run state already changes: the
# checkpoint write. It is keyed on the SESSION'S cwd rather than on the host
# repo, because cwd is the only key both sides can compute — the pipeline from
# its own process, the hook from the payload — without either guessing.
#
# THE PATH LIVES HERE, not in the hook, because D1 says every state path
# resolves through this file; and the READ lives here beside the WRITE so the
# two cannot drift into composing different paths, which is the failure that
# produced the dead input in the first place.
# --------------------------------------------------------------------------

ACTIVE_RUN_FILE = "active-run.json"


def cwd_key(cwd=None):
    """The state key for a session working directory.

    The git toplevel when `cwd` is inside a repository — so a turn taken in a
    subdirectory resolves to the same pointer the pipeline wrote from the repo
    root — and the realpath'd directory itself otherwise. `repo_key` does the
    slugging, so this scheme has exactly one implementation.
    """
    d = os.path.realpath(cwd or os.getcwd())
    return repo_key(_toplevel_of(d) or d)


def active_run_pointer(cwd=None):
    """`<state-root>/<cwd-key>/active-run.json` — where the pointer lives."""
    return os.path.join(state_root(), cwd_key(cwd), ACTIVE_RUN_FILE)


def write_active_run(ws, next_stage, cwd=None, now=None):
    """Record `{ws, next_stage, written_at}` for this working directory.

    `written_at` is the staleness instrument and the ONLY one: nothing here or
    downstream may answer "which run is this" by scanning for the newest
    workspace, because a wrong-run block is indistinguishable at the owner's
    screen from a real one.

    Atomic (temp + replace) for the same reason the checkpoint write is: a
    half-written pointer would be read as an unparseable one, and this must
    fail toward "no subject", never toward a corrupt one.
    """
    stamp = (now or datetime.datetime.now()).astimezone().isoformat(timespec="seconds")
    rec = {"ws": os.path.realpath(ws), "next_stage": next_stage,
           "written_at": stamp}
    path = active_run_pointer(cwd)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rec, f, indent=2)
    os.replace(tmp, path)
    return path


def read_active_run(cwd=None):
    """The pointer record, or None when there is none / it does not parse."""
    try:
        with open(active_run_pointer(cwd), encoding="utf-8") as f:
            rec = json.load(f)
    except (OSError, ValueError):
        return None
    return rec if isinstance(rec, dict) else None


def cmd_active_run_pointer(args):
    print(active_run_pointer(getattr(args, "cwd", None)))
    return 0


# --------------------------------------------------------------------------
# The destination repository (Story 18.72, #611)
#
# Everything above resolves MACHINE-STATE paths — where intermediates, caches
# and per-run workspaces live. The two functions below resolve a path in the
# repository the OWNER WORKS IN, which is a different class with a much
# narrower licence: `docs/storage-architecture.md` D1 bounds the destination
# write surface exhaustively, and a member is added by amending that list and
# the footprint check together. They live here because D1's seam says every
# storage path resolves through this one helper — a caller composing a
# destination path itself is the defect the seam exists to prevent.
# --------------------------------------------------------------------------

# The View's basename, in the OWNER'S vocabulary (Story 20.85, #1040;
# SPEC-terrain amendments, 2026-07-31 triage). It left #726's machine-key
# exemption because both grounds of that exemption are falsified: owner-facing
# is a type carried by the VALUE, not a property of which file it lives in — and
# the View is the one artifact this flow writes for the owner to open — while
# the published-artifact location #726 declined to rename no longer exists.
#
# `TOPIC_MAP_VIEW_DIR = "topic-map"` was deleted with it: dead since the #874
# relocation stopped composing that directory component, with zero references.
TOPIC_MAP_VIEW_BASENAME = "terrain-view.md"
# The in-repo directory holding this tool's outputs and debug artifacts
# (D2, amended 2026-07-28, #874). Ignored by the repo and guarded by a check:
# a run's intermediates carry hub renderings, and this repository is public.
TERRAIN_OUTPUT_DIR = ".writing-assistant"


def articles_repo_root(root):
    """The articles (destination) repository: the git top-level containing the
    declared `output.drafts` destination, or the destination itself when it is
    not inside a git repo. None when no destination is declared.

    Single source: `write-article-plan.py` delegates here rather than keeping
    its own copy, so "where is the destination repo" is answered in exactly one
    place, like every other path in this file.
    """
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    rws = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rws)
    val = rws.get_output_drafts(rws.read_lines(root))
    if not val:
        return None
    drafts = rws.resolve_drafts_dir(val, root)
    # Ask git rather than walking for a `.git` DIRECTORY: in a linked worktree
    # `.git` is a file, so the walk ran off the top and reported "not in a git
    # repo", silently answering with the destination itself (#1005).
    return _toplevel_of(drafts) or drafts


def topic_map_view(root):
    """The Terrain View's FIXED path (SPEC-terrain CAP-3, amended 2026-07-23;
    relocated 2026-07-28, #874): `<host-repo>/.writing-assistant/terrain/
    terrain-view.md` — inside THIS tool's own output directory in the
    writing-assistant working tree, which the repository ignores. None when no
    destination is declared.

    The basename is the OWNER'S word (Story 20.85, #1040). It read
    `topic-map-view.md` under #726's machine-key exemption, on two grounds the
    2026-07-31 amendment falsifies: owner-facing is a type carried by the value
    rather than a property of which file it lives in, and the View is the one
    artifact this flow writes for a human to open — so the value was
    owner-facing all along; and the published-artifact location whose migration
    cost #726 declined to pay no longer exists, so nothing is owed. The file is
    regenerated every invocation and never read back, so there is no old name to
    migrate from and no compatibility alias is written.

    Fixed, not per-run: the View is written for the owner to open, and a
    per-run path moves every invocation, so nothing opened during a sitting can
    be reopened later. Host-qualified by `repo_key`, because one articles repo
    serves many host repos and each has its own terrain.

    This changes only WHERE the file lands. CAP-1's properties are untouched
    and remain binding: fully regenerated every invocation, never read back by
    any code path, and deleting it loses nothing.
    """
    # RELOCATED 2026-07-28 (#874, owner ruling): the View is a
    # writing-assistant output, so it lands in the writing-assistant
    # repository — not in the `output.drafts` destination, whose permitted
    # surface shrinks back to INDEX.md alone (D1). It stays a FIXED path so a
    # file opened during a sitting can be reopened later, and stays
    # host-qualified because one tool serves many host repos.
    return os.path.join(terrain_repo_dir(root), TOPIC_MAP_VIEW_BASENAME)


# --------------------------------------------------------------------------
# THE BRIEF'S DURABLE HOME (Story 20.191, #1342; SPEC-terrain amendments, the
# 2026-08-03 block)
#
# A Brief used to live only in the per-run workspace that composed it — machine
# state, keyed by recency, which the pipeline already distrusted in its own
# words: the brief record writes `brief_source` PINS FIRST "because the path is
# a state-dir location that goes stale by relocation while still looking
# authoritative" (`skills/draft-article/stages/stage0.md`). The amendment stops
# working around that and moves the artifact.
#
# WHY BESIDE THE VIEW. The Brief is the owner's DECISION and is re-opened by
# design, which is exactly the property that put the View in a working tree
# (#874) and left run workspaces in the state root (#935). The class split runs
# at the same seam: the Brief is output, not an intermediate, so it lands under
# `terrain_repo_dir` — host-qualified, because one tool serves many host repos.
#
# THE DIRECTORY IS THE ENUMERATION. No index file is written here and none may
# be: an index over a directory is a derived second ledger holding what is
# recomputable from the directory itself, which is the shape the amendment
# declined by name. `list_home_briefs` below is a LISTING, not a store.
BRIEFS_DIR = "briefs"
BRIEF_SUFFIX = ".json"


def terrain_briefs_dir(root):
    """The Brief's durable home for one host repo: `<terrain-repo-dir>/briefs`.

    Only this function composes it (D1). A Brief is addressed by its stable id
    within the home, never by the run workspace that happened to compose it.
    """
    return os.path.join(terrain_repo_dir(root), BRIEFS_DIR)


def terrain_brief_home(root, brief_id):
    """The home path of ONE Brief, addressed by its stable id.

    The id is the artifact's identity and is computed from what the Brief
    already carries (`terrain_brief.brief_id`) — never minted here, and never
    fresh per write, or the home would accumulate a copy per save.
    """
    return os.path.join(terrain_briefs_dir(root), str(brief_id) + BRIEF_SUFFIX)


def list_home_briefs(root):
    """Every Brief in the home, as absolute paths, sorted by id.

    THE LISTING IS THE ENUMERATION (Story 20.191 AC4): read from the directory
    every time, so a Brief added, replaced or removed by hand is reflected with
    nothing to repair. A missing home is an empty listing, not an error — a
    host repo with no terrain sitting yet simply has no Briefs.
    """
    d = terrain_briefs_dir(root)
    try:
        names = os.listdir(d)
    except OSError:
        return []
    return [os.path.join(d, n) for n in sorted(names)
            if n.endswith(BRIEF_SUFFIX)
            and os.path.isfile(os.path.join(d, n))]


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


def _update_latest(base, ws):
    """Point <runs_dir>/latest at the just-created run dir (F40).

    Run ids are microsecond timestamps, so a human who wants the most recent
    run's fact sheet otherwise has to eyeball the newest of a deep list of
    `runs/<ts>/` dirs. `latest` is a stable shorthand: `ls runs/latest/` or
    `cd runs/latest`. The target is RELATIVE (the run-id basename) so the link
    survives the tree being moved. Best-effort — a filesystem without symlink
    support, or a lost race with a concurrent run, is silently tolerated: the
    shorthand is a convenience, never a correctness requirement, and both run
    enumerators skip the symlink so a stale `latest` never corrupts a listing
    or a resume.
    """
    link = os.path.join(base, "latest")
    tmp = os.path.join(base, f".latest.{os.getpid()}.tmp")
    try:
        try:
            os.remove(tmp)
        except FileNotFoundError:
            pass
        os.symlink(os.path.basename(ws), tmp)
        os.replace(tmp, link)  # atomic swap over any existing `latest`
    except OSError:
        try:
            os.remove(tmp)
        except OSError:
            pass


def new_run(root, run_id=None, terrain=False):
    """Create <repo-dir>/runs/<run-id>/ and return it (Story 9.2).

    Every intermediate a pipeline run produces — fact sheet, NEEDS-OWNER list,
    interview journal, provenance map, quality-gate output, scratch — lives
    under this one directory: one run = one debuggable, disposable unit, and
    the host working tree stays clean by construction. There is no
    state-vs-cache split (D2): all per-run artifacts share the workspace.

    An explicit --run-id must be fresh; without one, a unique id is minted, and
    on the astronomically unlikely microsecond collision a random suffix is
    appended until the directory does not already exist. A `latest` symlink is
    repointed at the new run for easy re-finding (F40).
    """
    # `terrain=True` mints under Terrain's own state-root subdirectory (#935,
    # narrowing #874): every run workspace is machine state regardless of
    # subsystem, and only the View is owner-facing output. The flag now buys
    # collision isolation between subsystems, not a different storage class.
    base = terrain_runs_dir(root) if terrain else runs_dir(root)
    if run_id is not None:
        ws = os.path.join(base, run_id)
        os.makedirs(ws)  # exist_ok=False: an explicit id must be new
        _update_latest(base, ws)
        _init_ws_git(ws)
        return ws
    while True:
        ws = os.path.join(base, _timestamp_run_id())
        try:
            os.makedirs(ws)
            _update_latest(base, ws)
            _init_ws_git(ws)
            return ws
        except FileExistsError:
            ws = os.path.join(base, _timestamp_run_id() + "-" + os.urandom(3).hex())
            os.makedirs(ws, exist_ok=False)
            _update_latest(base, ws)
            _init_ws_git(ws)
            return ws


def _init_ws_git(ws):
    """Initialise the run workspace's own git repository (Story 20.209, #1390).

    The workspace git is the WRITE CARRIER for the canonical draft: every
    mutation of `draft.md` after `fill` creates it is recorded as a commit
    with its reason, and a write that reaches the file without one is
    detectable (`run_loop.py draft-inspect`). Initialised at mint because the
    carrier's detection is relative to a repository that must predate the
    first write — a repo created lazily at the first carrier call could not
    tell fill's creation from an out-of-band rewrite of it.

    The repository lives in the STATE ROOT, never the host tree (the
    footprint invariant, verified before this shipped: the state root is
    outside the host repo and `check-footprint-invariant.sh` passes with a
    workspace repo present). Identity is set locally so recording never
    depends on the operator's global git config.

    Degrades, never fails: a machine without git mints a workspace exactly as
    before, with the degradation on stderr — the same discipline as
    `run_loop.preserve`, because instrumentation must never fail the run it
    observes."""
    try:
        for cmd in (["git", "init", "-q"],
                    ["git", "config", "user.name", "writing-assistant-carrier"],
                    ["git", "config", "user.email",
                     "carrier@writing-assistant.invalid"]):
            r = subprocess.run(cmd, cwd=ws, capture_output=True, text=True)
            if r.returncode != 0:
                raise OSError(r.stderr.strip() or "exit %d" % r.returncode)
    except (OSError, FileNotFoundError) as e:
        sys.stderr.write("resolve-paths: workspace git unavailable — draft "
                         "writes will not be recorded (%s)\n" % e)


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


def root_disagreement(arg_root, resolved):
    """The one-line --root/cwd disagreement notice, or None (#309).

    Deliberately NOT inside host_root: that runs on every path resolution, many
    times per run, where a notice would be pure noise (and would break flows
    contracted to stay silent on stderr). The disagreement is an ENTRY-surface
    signal — it belongs where the run announces its target, once.
    """
    if not arg_root:
        return None
    cwd_top = _cwd_toplevel()
    if cwd_top and cwd_top != resolved:
        return (f"note: --root resolves to {resolved}; cwd is inside {cwd_top} "
                "— using --root")
    return None


def cmd_target(args):
    """Print the resolved target repository path (#309).

    One call, made by every entry flow before it reads scope, mints a workspace,
    or spends a token — so operating on the wrong repository is detectable while
    it is still free. Resolution goes through host_root, so the precedence
    (explicit --root > git toplevel of cwd > fail closed) is the same one the
    rest of the run obeys: this surfaces the decision, it never makes a second
    one. A --root/cwd disagreement is reported here, informational and
    fail-open — explicit --root still wins.
    """
    root = host_root(args.root)
    note = root_disagreement(args.root, root)
    if note:
        print(note, file=sys.stderr)
    print(root)
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


def cmd_terrain_output_root(args):
    print(terrain_output_root())
    return 0


def cmd_terrain_runs_root(args):
    """Terrain's RUN-WORKSPACE root, under the machine state root.

    Exposed as a verb (Story 20.92, #1042) because a consumer needed to find
    the newest terrain workspace and the layout is the resolver's to know: the
    alternative was `topic-map-directions.py` composing
    `<repo-dir>/terrain-runs` itself, which is exactly the storage-path
    composition D1 bars. Distinct from `terrain-output-root`, which is the
    OWNER-FACING output root in the working tree — the two were relocated apart
    on purpose (#935) and a caller that confuses them writes intermediates
    where the owner works.
    """
    print(terrain_runs_dir(host_root(args.root)))
    return 0


def cmd_new_run(args):
    print(new_run(host_root(args.root), args.run_id,
                  terrain=getattr(args, "terrain", False)))
    return 0


def cmd_run_workspace(args):
    print(run_workspace(host_root(args.root), args.run_id))
    return 0


def cmd_terrain_briefs_dir(args):
    """The Brief's durable home for this host repo (Story 20.191, #1342).

    A QUERY, exactly like `terrain-view`: it creates nothing. The directory is
    created by the sanctioned writer when a Brief is written there, for the
    reason #935 recorded — a resolver that mkdirs leaves a repo-key directory
    behind for every host whose path was merely asked for.
    """
    print(terrain_briefs_dir(host_root(args.root)))
    return 0


def cmd_terrain_brief(args):
    """The home path of one Brief, addressed by its stable id."""
    print(terrain_brief_home(host_root(args.root), args.id))
    return 0


def cmd_list_briefs(args):
    """Enumerate the home — the LISTING IS the enumeration, and there is no
    index file to read or repair (Story 20.191 AC4). One path per line; an
    empty home prints nothing and exits 0, because "no Briefs yet" is a fact
    about this host repo rather than a failure."""
    for p in list_home_briefs(host_root(args.root)):
        print(p)
    return 0


def cmd_topic_map_view(args):
    path = topic_map_view(host_root(args.root))
    if not path:
        sys.stderr.write(
            "error: no output.drafts destination is declared, so the topic-map "
            "View has nowhere to land\n"
            "  resolve-writing-sources.py set-draft-location <path> "
            f"--root {host_root(args.root)}\n")
        return 3
    # RESOLVING IS A QUERY — it creates nothing (#935). The directory and its
    # self-ignoring `.gitignore` are created by the writer
    # (`topic-map-directions.py write_view`), because a resolver that mkdirs
    # left a repo-key directory behind for every host repo whose View path was
    # merely asked for, including the suite's temporary ones. That was the
    # accumulation's second source, invisible beside the run workspaces.
    print(path)
    return 0


# Owner-facing article-type labels (canonical map: draft-pipeline.py
# INTENT_LABELS — check-path-resolver.sh asserts the two stay in sync).
# The picker shows these, never the internal F-ids (SPEC-review-ux CAP-1).
_INTENT_LABELS = {
    "F1": "introduce the project",
    "F2": "share engineering lessons",
    "F3": "explain the evaluation methodology",
    "F4": "survey a research area",
    "F5": "write a working note",
}


def _draft_title(path):
    """The frontmatter `title:` of a draft, best-effort (metadata display only)."""
    try:
        with open(path, encoding="utf-8") as f:
            head = f.read(4000)
    except OSError:
        return None
    m = re.search(r'^title:\s*"?(.*?)"?\s*$', head, re.MULTILINE)
    return m.group(1) if m else None


def cmd_list_drafts(args):
    """Enumerate candidate drafts for review (Story 13.31, SPEC-review-ux
    CAP-1): run workspaces holding a draft.md, with picker metadata — title,
    owner-facing article type, updated time, and pipeline status from the
    checkpoint (in-progress / complete / reviewed). Layout knowledge stays
    here: callers never compose runs/ paths themselves. JSON list on stdout;
    an empty list is data, not an error (the caller reports where a draft
    would have been and points at draft-article)."""
    root = host_root(args.root)
    base = runs_dir(root)
    out = []
    for rid in (sorted(os.listdir(base)) if os.path.isdir(base) else []):
        ws = os.path.join(base, rid)
        if os.path.islink(ws):
            continue  # the `latest` shorthand (F40) is not a distinct run
        draft = os.path.join(ws, "draft.md")
        if not os.path.isfile(draft):
            continue
        status, framework = "in-progress", None
        cp = os.path.join(ws, "checkpoint.json")
        try:
            with open(cp, encoding="utf-8") as f:
                state = json.load(f)
            framework = state.get("framework")
            if state.get("reviewed"):
                status = "reviewed"
            elif state.get("next_stage") == "done":
                status = "complete"
        except (OSError, json.JSONDecodeError):
            pass
        out.append({
            "run_id": rid,
            "ws": ws,
            "draft": draft,
            "title": _draft_title(draft),
            "article_type": _INTENT_LABELS.get(framework),
            "updated": int(os.path.getmtime(draft)),
            "status": status,
        })
    print(json.dumps(out, indent=2))
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
    sp.add_argument("--terrain", action="store_true",
                    help="mint under the terrain output root (#874) — Terrain "
                         "outputs and debug artifacts live where the owner works")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--run-id", help="explicit run id (must not already exist; default: fresh timestamp id)")

    sp = sub.add_parser("run-workspace", help="print an existing run workspace path (no create)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--run-id", required=True, help="the run id whose workspace to print")

    sub.add_parser("terrain-output-root",
                   help="print the root this tool's outputs and debug "
                        "artifacts live under (D2, #874)")
    sp = sub.add_parser("terrain-runs-root",
                        help="print the root Terrain's run workspaces live "
                             "under, in the machine state root (#935) — NOT "
                             "the owner-facing output root above")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    # THE VERB TRAVELS WITH THE FILENAME (Story 20.85, #1040). It is typed into
    # an owner-facing procedure document, and a resolver whose verb and answer
    # disagree manufactures exactly the drift #1039 records.
    sp = sub.add_parser("terrain-view", help="print the Terrain View's fixed path under this "
                        "tool's own output root (#874); creates its directory")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("terrain-briefs-dir",
                        help="print the Brief's durable home for this host "
                             "repo (Story 20.191, #1342); creates nothing")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("terrain-brief",
                        help="print the home path of ONE Brief, addressed by "
                             "its stable id")
    sp.add_argument("--id", required=True,
                    help="the Brief's stable id (`terrain_brief.brief_id`) — "
                         "computed from the Brief's pin and composition, never "
                         "minted fresh per write")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("list-briefs",
                        help="enumerate the Briefs in the home, one path per "
                             "line — the listing IS the enumeration, and no "
                             "index file exists (Story 20.191)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("list-drafts", help="enumerate run workspaces holding a draft.md, "
                        "with picker metadata (Story 13.31)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

    sp = sub.add_parser("active-run-pointer",
                        help="print <state-root>/<cwd-key>/active-run.json — the "
                             "Stop hook's subject pointer (Story 20.156, #1245)")
    sp.add_argument("--cwd", help="the session working directory (default: cwd)")

    sp = sub.add_parser("target", help="print the resolved target repository path (#309): the one "
                                       "call every entry flow makes before any scope read, "
                                       "workspace mint, or LLM spend")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")

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
        "terrain-output-root": cmd_terrain_output_root,
        "terrain-runs-root": cmd_terrain_runs_root,
        "terrain-view": cmd_topic_map_view,
        "terrain-briefs-dir": cmd_terrain_briefs_dir,
        "terrain-brief": cmd_terrain_brief,
        "list-briefs": cmd_list_briefs,
        "list-drafts": cmd_list_drafts,
        "active-run-pointer": cmd_active_run_pointer,
        "target": cmd_target,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
