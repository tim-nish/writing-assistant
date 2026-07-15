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

  policy-source             Print the optional `policy_source` block as JSON:
                            {"declared": false} when absent (exit 0 — absence
                            is not an error), else {"declared": true, "path":
                            <abs>, "track": <str|null>, "topics": [<basename>…]}.
                            A malformed block (missing/empty path, more than 2
                            topics, a topics entry that is not a plain basename)
                            exits 4 with per-key errors naming the fix — the
                            stage-0 validator relays them. Whether the path is
                            USABLE (exists, readable, a git repo) is
                            deliberately not checked here: an unusable path is
                            a read-time degradation, never a config error.
"""

import argparse
import glob
import importlib.util
import os
import re
import subprocess
import sys

SOURCES_FILE = "writing-sources.yaml"


def _load_paths():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rp", os.path.join(here, "resolve-paths.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rp = _load_paths()

# One notice per process — read_lines is called repeatedly by some consumers.
_NOTICED = set()


def _notice(key, msg):
    if key not in _NOTICED:
        _NOTICED.add(key)
        sys.stderr.write(msg)


def sources_path(root, notice=False):
    """The resolved writing-sources.yaml for `root` — (path, kind), kind in
    {'global','legacy','none'}. Resolution lives in resolve-paths.py (O1, #211).

    Library calls stay SILENT by default: several consumers own a structured
    stderr protocol (read-policy-source.py's relayed config errors, parsed by
    validate-config.py) that a free-text line would corrupt. CLI entry points —
    which own their stderr — pass notice=True to surface the migration notices:
      both exist   -> the machine-global file wins; one line names the ignored
                      in-repo file and the migration path
      legacy only  -> read it (compatibility), one deprecation line
    """
    path, kind = rp.sources_file(root)
    legacy = rp.legacy_sources_file(root)
    if notice:
        if kind == "global" and os.path.isfile(legacy):
            _notice(("both", root),
                    f"notice: ignoring legacy {legacy} — the machine-global config wins "
                    f"({path}); delete the in-repo file after migrating (#211)\n")
        elif kind == "legacy":
            _notice(("legacy", root),
                    f"deprecated: {path} lives in the host repo; move it to "
                    f"{os.path.join(rp.repo_config_dir(root), SOURCES_FILE)} (#211)\n")
    return path, kind

NEEDS_PROMPT = 3      # draft-location: no output.drafts declared
POLICY_MALFORMED = 4  # policy-source: block present but malformed
SOURCES_MALFORMED = 5 # sources: include: line not the inline-list form (#221)
POLICY_MAX_TOPICS = 2 # SPEC-policy-source-seam CAP-2: at most 2 topic files


class MalformedSources(ValueError):
    """A sources `include:` line the parser cannot read (#221).

    A malformed *narrowing* directive must never fall through to whole-tree
    scope — that silently inverts the fail-closed read boundary. Raised by
    get_sources(); CLI entry points catch it and exit SOURCES_MALFORMED.
    """


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
    """Return the raw lines (no trailing newlines) of the RESOLVED
    writing-sources.yaml (machine-global first, legacy in-repo second — O1,
    #211), or [] when neither exists."""
    path, kind = sources_path(root)
    if kind == "none":
        return []
    with open(path, encoding="utf-8") as fh:
        return fh.read().split("\n")


def write_lines(root, lines):
    """Write back to the SAME file read resolution chose — global stays global,
    a legacy in-repo file is updated in place during migration (never silently
    forked into a global copy that would shadow its sources). When neither file
    exists yet, create the machine-global one (#211) — never a host-repo file."""
    path, kind = sources_path(root)
    if kind == "none":
        os.makedirs(os.path.dirname(path), exist_ok=True)
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


def resolve_drafts_dir(value, root):
    """Resolve a declared output.drafts value to an absolute directory (#213).

    `~` and environment variables expand; an absolute result is taken as-is (an
    external articles repo is the recommended home for drafts — articles are
    private assets and a host repo may be public); a relative value keeps its
    legacy meaning, resolving against the HOST ROOT (never the process cwd).
    """
    expanded = os.path.expandvars(os.path.expanduser(value))
    if os.path.isabs(expanded):
        return os.path.normpath(expanded)
    return os.path.normpath(os.path.join(root, expanded))


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

    Absent `include` means the whole path is in scope. An `include:` line
    that is present but not the supported inline form raises
    MalformedSources (#221): degrading it to "no include" would silently
    widen scope to the whole tree — the opposite of fail-closed.
    """
    result = []
    in_sources = False
    current = None
    for lineno, ln in enumerate(lines, 1):
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
        m = re.match(r"^\s+include:\s*\[(.*)\]\s*(#.*)?$", ln)
        if m and current is not None:
            items = [x.strip().strip('"').strip("'") for x in m.group(1).split(",")]
            current["include"] = [x for x in items if x]
            continue
        if re.match(r"^\s+include\s*:", ln):
            raise MalformedSources(
                f"line {lineno}: unparseable include: {ln.strip()!r} — only the "
                f'inline form is supported (include: ["docs/**", "README.md"]); '
                f"a block-style YAML list is not read, and falling through would "
                f"silently widen scope to the whole tree (#221)")
    return result


def get_policy_source(lines, root):
    """Parse the optional `policy_source` block.

    Returns (None, []) when the block is absent, else (block, errors) where
    block = {"path": abs-or-None, "track": str-or-None, "topics": [str]} and
    errors is a list of (key, message) pairs for a malformed block. Usability
    of the path (exists / readable / git repo) is not checked here.
    """
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^policy_source:\s*(#.*)?$", ln):
            start = i
            break
    if start is None:
        return None, []

    def _val(raw):
        return re.sub(r"\s+#.*$", "", raw).strip().strip('"').strip("'")

    block = {"path": None, "track": None, "topics": []}
    errors = []
    j = start + 1
    while j < len(lines):
        ln = lines[j]
        j += 1
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            continue
        if _indent(ln) == 0:
            break  # left the block
        m = re.match(r"^\s+path:\s*(.*)$", ln)
        if m:
            raw = _val(m.group(1))
            block["path"] = os.path.realpath(os.path.join(root, raw)) if raw else None
            continue
        m = re.match(r"^\s+track:\s*(.*)$", ln)
        if m:
            block["track"] = _val(m.group(1)) or None
            continue
        m = re.match(r"^\s+topics:\s*\[(.*)\]\s*(#.*)?$", ln)
        if m:
            items = [x.strip().strip('"').strip("'") for x in m.group(1).split(",")]
            block["topics"] = [x for x in items if x]
            continue

    if block["path"] is None:
        errors.append(("policy_source.path",
                       "required when policy_source is declared. Fix: set it to "
                       "the local product-lab checkout (a plain path; no URL)."))
    if len(block["topics"]) > POLICY_MAX_TOPICS:
        errors.append(("policy_source.topics",
                       f"{len(block['topics'])} entries exceed the cap of "
                       f"{POLICY_MAX_TOPICS}. Fix: keep at most {POLICY_MAX_TOPICS} "
                       "topic files (the bounded-read invariant)."))
    for t in block["topics"]:
        if "/" in t or ".." in t or t.startswith("."):
            errors.append(("policy_source.topics",
                           f"entry {t!r} is not a plain basename. Fix: name files "
                           "directly under the policy repo's topics/ directory "
                           "(e.g. eval-engineering.md)."))
    return block, errors


def _contains(parent, child):
    """True iff realpath child is parent or inside it (no symlink/.. escape)."""
    parent = os.path.realpath(parent)
    child = os.path.realpath(child)
    if child == parent:
        return True
    return child.startswith(parent + os.sep)


# Well-known VCS / tool / editor / build directories that a whole-tree `path: .`
# scope sweeps into harvest as noise. This list drives an ADVISORY WARNING only —
# it never prunes. The read-scope invariant is unchanged (scope = declared paths
# minus `.git/`); owners narrow scope with an `include:` allowlist. Story 13.20 /
# issue #170 decided warn-only precisely to preserve that invariant.
NOISE_DIRS = {
    ".claude", ".obsidian", ".devcontainer", ".vscode", ".idea",
    "_bmad", "_bmad-output", "node_modules", "__pycache__",
    ".venv", "venv", ".mypy_cache", ".pytest_cache", ".ruff_cache",
}


def noise_report(sources, files):
    """For each whole-tree source (declared with no `include:`), count resolved
    files that fall under a well-known noise directory. Returns {dir_name: count},
    aggregated across whole-tree sources. Advisory only — nothing is pruned, so
    the file list this run returns is unaffected."""
    whole_tree_roots = [s["path"] for s in sources
                        if not s["include"] and os.path.isdir(s["path"])]
    counts = {}
    for full in files:
        base = next((r for r in whole_tree_roots if _contains(r, full)), None)
        if base is None:
            continue
        parts = os.path.relpath(full, base).split(os.sep)
        hit = next((p for p in parts if p in NOISE_DIRS), None)
        if hit:
            counts[hit] = counts.get(hit, 0) + 1
    return counts


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
            f"no output.drafts declared in {sources_path(root)[0]}; "
            f"ask the owner once — recommended: a directory in a PRIVATE articles "
            f"repo OUTSIDE the host repo (articles are private assets; a host repo "
            f"may be public, #213) — then run:\n"
            f"  resolve-writing-sources.py set-draft-location <path> --root {root}\n"
        )
        return NEEDS_PROMPT
    print(resolve_drafts_dir(val, root))
    return 0


def cmd_set_draft_location(args):
    root = host_root(args.root)
    lines = read_lines(root)
    new_lines, changed = set_output_drafts(lines, args.path)
    path, kind = sources_path(root)
    if kind == "legacy":
        # The key must land machine-global, never in the host repo (#211/#213) —
        # but a bare global file holding only `output:` would WIN resolution and
        # shadow the legacy sources. So migrate the whole (updated) content.
        gpath = os.path.join(rp.repo_config_dir(root), SOURCES_FILE)
        os.makedirs(os.path.dirname(gpath), exist_ok=True)
        with open(gpath, "w", encoding="utf-8") as fh:
            fh.write("\n".join(new_lines))
        sys.stderr.write(
            f"migrated: {path} copied to {gpath} (with output.drafts set) — the "
            f"machine-global file now wins; delete the in-repo copy (#211)\n")
    elif changed or kind == "none":
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
    sources = get_sources(read_lines(root), root)
    files = enumerate_files(sources)
    for f in files:
        print(f)
    report = noise_report(sources, files)
    if report:
        total = sum(report.values())
        listed = ", ".join(f"{d}/ ({n})" for d, n in
                           sorted(report.items(), key=lambda kv: (-kv[1], kv[0])))
        sys.stderr.write(
            f"warning: a whole-tree source (`path: .`, no `include:`) pulled "
            f"{total} file(s) from well-known tool/editor/build directories into "
            f"harvest scope: {listed}. These are usually noise, not article "
            f"material. Narrow scope with an `include:` allowlist in "
            f"{SOURCES_FILE} (e.g. `include: [\"specs/**\", \"docs/**\"]`); see "
            f"config/writing-sources.example.yaml. Default scope is unchanged — "
            f"this is advisory only.\n")
    return 0


def cmd_policy_source(args):
    import json
    root = host_root(args.root)
    block, errors = get_policy_source(read_lines(root), root)
    if block is None:
        print(json.dumps({"declared": False}))
        return 0
    if errors:
        for key, msg in errors:
            sys.stderr.write(f"[{SOURCES_FILE}] {key}: {msg}\n")
        return POLICY_MALFORMED
    print(json.dumps({"declared": True, "path": block["path"],
                      "track": block["track"], "topics": block["topics"]}))
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
    sub.add_parser("policy-source", parents=[root_parent])
    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    # The CLI owns its stderr: surface the O1 migration notices (legacy in-repo
    # file / ignored legacy) once per invocation. Library importers never see
    # them — see sources_path(). host_root() here exits identically to the
    # handler's own call, so this adds no new failure mode.
    sources_path(host_root(args.root), notice=True)
    try:
        return {
            "draft-location": cmd_draft_location,
            "set-draft-location": cmd_set_draft_location,
            "sources": cmd_sources,
            "is-declared": cmd_is_declared,
            "files": cmd_files,
            "policy-source": cmd_policy_source,
        }[args.cmd](args)
    except MalformedSources as e:
        # #221: never widen scope on a malformed narrowing directive — name the
        # offending line and read nothing.
        path, _ = sources_path(host_root(args.root))
        print(f"error: {path}: {e}", file=sys.stderr)
        return SOURCES_MALFORMED


if __name__ == "__main__":
    sys.exit(main())
