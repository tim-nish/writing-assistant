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
                            `type: path` entries only — non-file typed entries
                            (Story 13.49) never widen the file read scope.

  typed-sources             All declared entries with their `type` as JSON
                            (Story 13.49). Entries carry an optional `type`
                            key — `path` (default), `github-issues`
                            (optional inline `labels:` filter), `tanuki-den`.
                            Unknown types and keys that only apply to another
                            type (e.g. `include` on `github-issues`) are
                            refused fail-closed with per-key diagnostics
                            (exit 5, same posture as #221).

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
                            <abs>}. A malformed block (missing/empty path, or a
                            leftover `track:`/`topics:` key — removed by Story
                            13.36, SPEC-policy-topic-at-draft CAP-3: topics are
                            chosen per-article at draft time) exits 4 with
                            per-key errors naming the fix — the stage-0
                            validator relays them. Whether the path is
                            USABLE (exists, readable, a git repo) is
                            deliberately not checked here: an unusable path is
                            a read-time degradation, never a config error.

  set-policy-source PATH    Write the `policy_source` block back into
                            writing-sources.yaml (SPEC-repo-onboarding CAP-2),
                            with the same contract as set-draft-location:
                            comment-preserving line surgery, idempotent,
                            machine-global destination, legacy-file migration.
                            Path-only (Story 13.36): the `--track`/`--topics`
                            flags were removed with the config keys. The result
                            is validated BEFORE writing — a write that would
                            leave a malformed block (e.g. a leftover removed
                            key) exits 4 and touches nothing. Usability of
                            PATH is deliberately not checked (read-time
                            degradation, never a config error). Prints the new
                            block as JSON (the policy-source format).

  set-sources               Declaratively REPLACE the `sources:` block from a
                            JSON array on stdin (SPEC-repo-onboarding CAP-2):
                            [{"path": ".", "include": ["docs/**"]}, ...].
                            Typed entries round-trip (Story 13.49): an
                            optional "type" key ("path" default,
                            "github-issues" with optional "labels",
                            "tanuki-den") is accepted and written back.
                            Emits the inline include form (#221). Comments
                            inside the old sources block do not survive the
                            replace (declarative semantics); comments outside
                            it do. An empty list, a missing path, or an
                            include pattern containing `..` exits 5 and
                            touches nothing — the writer is fail-closed like
                            the reader. Prints the resolved source paths.
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


def _block_span(lines, header_re):
    """(start, end) of a top-level block: `start` is the header line index,
    `end` the first index after it holding a top-level non-blank line (the
    line AFTER the block). (None, None) when the header is absent. Matches
    the block-walking rule the readers use: any indent-0 non-blank line —
    comment included — ends the block."""
    start = None
    for i, ln in enumerate(lines):
        if re.match(header_re, ln):
            start = i
            break
    if start is None:
        return None, None
    end = start + 1
    while end < len(lines):
        ln = lines[end]
        if ln.strip() and _indent(ln) == 0:
            break
        end += 1
    return start, end


def set_policy_source(lines, path):
    """Return (new_lines, changed). Per-key line surgery like
    set_output_drafts: `path` is set, other lines keep their existing form
    (comments and ordering survive); an absent block is appended whole —
    path-only since Story 13.36 (topic selection moved to draft time; the
    `--track`/`--topics` flags were removed with the config keys). Callers
    validate the RESULT via get_policy_source before writing — a leftover
    `track:`/`topics:` line therefore refuses the write with the removed-key
    error until the owner deletes it."""
    start, end = _block_span(lines, r"^policy_source:\s*(#.*)?$")
    if start is None:
        tail = []
        if lines and lines[-1].strip() != "":
            tail.append("")
        tail.append("policy_source:")
        tail.append(f"  path: {path}")
        return lines + tail, True

    new = list(lines)
    changed = False

    def _set_key(key, value_line):
        """Replace the block's `key:` line, or insert one at the block end."""
        nonlocal new, changed, end
        for j in range(start + 1, end):
            m = re.match(rf"^(\s+){key}:\s*.*$", new[j])
            if m:
                candidate = f"{m.group(1)}{key}: {value_line}"
                if new[j] != candidate:
                    new[j] = candidate
                    changed = True
                return
        # key absent: insert at the end of the block, before trailing blanks
        k = end
        while k > start + 1 and new[k - 1].strip() == "":
            k -= 1
        new.insert(k, f"  {key}: {value_line}")
        end += 1
        changed = True

    _set_key("path", path)
    return new, changed


def render_sources_block(specs):
    """The canonical `sources:` block for typed specs (Story 13.49) — always
    the inline list form (#221). The default `type: path` is not emitted
    (untyped entries stay byte-identical); non-path types are emitted as
    `- type: …` entries."""
    out = ["sources:"]
    for s in specs:
        t = s.get("type", "path")
        if t == "path":
            out.append(f"  - path: {s['path']}")
            if s.get("include"):
                quoted = ", ".join(f'"{g}"' for g in s["include"])
                out.append(f"    include: [{quoted}]")
        else:
            out.append(f"  - type: {t}")
            if s.get("labels"):
                quoted = ", ".join(f'"{g}"' for g in s["labels"])
                out.append(f"    labels: [{quoted}]")
    return out


def validate_source_specs(specs):
    """Fail-closed write-time validation for set-sources input (typed —
    Story 13.49). Returns a list of error strings; empty means writable."""
    errors = []
    if not isinstance(specs, list) or not specs:
        return ["sources must be a non-empty JSON array of "
                '{"type"?: "path"|"github-issues"|"tanuki-den", '
                '"path": str, "include": [str, ...]?, "labels": [str, ...]?} '
                "objects"]
    for i, s in enumerate(specs):
        if not isinstance(s, dict):
            errors.append(f"sources[{i}]: not an object")
            continue
        t = s.get("type", "path")
        if t not in VALID_SOURCE_TYPES:
            errors.append(f"sources[{i}].type: unknown type {t!r} — valid "
                          "types: " + ", ".join(VALID_SOURCE_TYPES))
            continue
        if t != "path":
            for key in ("path", "include"):
                if key in s:
                    errors.append(f"sources[{i}].{key}: only applies to "
                                  f"`type: path` entries")
            if t == "tanuki-den" and "labels" in s:
                errors.append(f"sources[{i}].labels: only applies to "
                              "`type: github-issues` entries")
            labels = s.get("labels", [])
            if not isinstance(labels, list) or any(
                    not isinstance(g, str) or not g.strip() for g in labels):
                errors.append(f"sources[{i}].labels: must be a list of "
                              "non-empty strings")
            continue
        if "labels" in s:
            errors.append(f"sources[{i}].labels: only applies to "
                          "`type: github-issues` entries")
        if not isinstance(s.get("path"), str) or not s["path"].strip():
            errors.append(f"sources[{i}]: a non-empty string `path` is required")
            continue
        inc = s.get("include", [])
        if not isinstance(inc, list) or any(not isinstance(g, str) or not g.strip()
                                            for g in inc):
            errors.append(f"sources[{i}].include: must be a list of non-empty strings")
            continue
        for g in inc:
            if ".." in g.split("/"):
                errors.append(
                    f"sources[{i}].include: pattern {g!r} contains a `..` "
                    "segment — path-escaping patterns are refused at write "
                    "time (the reader would silently drop them)")
    return errors


def set_sources(lines, specs):
    """Return (new_lines, changed). Declarative replace of the whole
    `sources:` block (comments inside it are NOT preserved — this is the
    documented tradeoff of declarative semantics; comments elsewhere
    survive). An absent block is inserted after the leading comment header,
    so the conventional order (sources, output, policy_source) holds for
    files this tool creates from scratch."""
    block = render_sources_block(specs)
    start, end = _block_span(lines, r"^sources:\s*(#.*)?$")
    if start is not None:
        # keep trailing blank separation as-is: replace header..last content
        last = end
        while last > start + 1 and lines[last - 1].strip() == "":
            last -= 1
        new = lines[:start] + block + lines[last:]
        return new, new != lines
    # absent: insert after the leading run of comment/blank lines
    k = 0
    while k < len(lines) and (lines[k].strip() == "" or lines[k].lstrip().startswith("#")):
        k += 1
    lead = lines[:k]
    rest = lines[k:]
    sep_before = [""] if lead and lead[-1].strip() != "" else []
    sep_after = [""] if rest and rest[0].strip() != "" else []
    return lead + sep_before + block + sep_after + rest, True


# Typed source entries (Story 13.49, SPEC-writing-assistant CAP-2 amendment):
# `type: path` is the default — an untyped {path, include} entry behaves
# byte-identically to before. Non-file evidence is an explicit opt-in.
VALID_SOURCE_TYPES = ("path", "github-issues", "tanuki-den")


def _entry_key(cur, key, raw, lineno, errors):
    """Record one `key: value` line of a sources entry. Inline-list keys
    (`include`, `labels`) share the #221 rule: a non-inline form is an error,
    never a silent fall-through."""
    cur["keys"].add(key)
    val = re.sub(r"\s+#.*$", "", raw).strip()
    if key in ("path", "type"):
        cur[key] = val.strip('"').strip("'")
    elif key in ("include", "labels"):
        m = re.match(r"^\[(.*)\]$", val)
        if not m:
            errors.append(
                f"line {lineno}: unparseable {key}: {raw.strip()!r} — only the "
                f'inline form is supported ({key}: ["a", "b"]); a block-style '
                f"YAML list is not read, and falling through would silently "
                f"widen scope (#221)")
            return
        items = [x.strip().strip('"').strip("'") for x in m.group(1).split(",")]
        cur[key] = [x for x in items if x]
    elif cur.get("type") not in (None, "path"):
        # Typed non-path entries are fail-closed on unknown keys; untyped/path
        # entries keep today's ignore-unknown-lines behavior (byte-identical).
        errors.append(f"line {lineno}: unknown key {key!r} in a "
                      f"`type: {cur['type']}` sources entry")


def get_typed_sources(lines, root):
    """Parse the sources list into typed entries (Story 13.49):

      {'type': 'path', 'path': abs, 'include': [...]}
      {'type': 'github-issues', 'labels': [...]}
      {'type': 'tanuki-den'}

    Fail-closed: an unknown `type`, a key that only applies to another type
    (e.g. `include` on a `github-issues` entry), or a non-inline list form
    (#221) raises MalformedSources with per-key diagnostics — same posture as
    the block-style `include` hard error.
    """
    entries = []
    errors = []
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
        m = re.match(r"^\s*-\s+([A-Za-z][\w-]*):\s*(.*?)\s*$", ln)
        if m:
            current = {"type": None, "path": None, "include": [], "labels": [],
                       "keys": set(), "line": lineno}
            entries.append(current)
            _entry_key(current, m.group(1), m.group(2), lineno, errors)
            continue
        m = re.match(r"^\s+([A-Za-z][\w-]*)\s*:\s*(.*?)\s*$", ln)
        if m and current is not None:
            _entry_key(current, m.group(1), m.group(2), lineno, errors)
            continue

    for i, e in enumerate(entries):
        t = e["type"] or "path"
        tag = f"sources[{i}] (line {e['line']})"
        if t not in VALID_SOURCE_TYPES:
            errors.append(
                f"{tag}: unknown type {t!r} — valid types: "
                + ", ".join(VALID_SOURCE_TYPES))
            continue
        e["type"] = t
        if t == "path":
            if not e["path"]:
                errors.append(f"{tag}: a `type: path` entry requires a `path:` key")
                continue
            if "labels" in e["keys"]:
                errors.append(f"{tag}: `labels` only applies to "
                              f"`type: github-issues` entries")
            e["path"] = os.path.realpath(os.path.join(root, e["path"]))
        else:
            for key in ("path", "include"):
                if key in e["keys"]:
                    errors.append(
                        f"{tag}: `{key}` only applies to `type: path` entries "
                        f"— a `type: {t}` source reads no files")
            if t == "tanuki-den" and "labels" in e["keys"]:
                errors.append(f"{tag}: `labels` only applies to "
                              f"`type: github-issues` entries")

    if errors:
        raise MalformedSources("\n".join(errors))
    return entries


def get_sources(lines, root):
    """Parse the sources list into [{'path': abs, 'include': [...]}] —
    the file-scope view: `type: path` entries only (the default type), so
    every existing consumer (files / is-declared / harvest read boundary)
    sees exactly the declared file scope. Typed non-file entries are
    surfaced by get_typed_sources / the `typed-sources` subcommand.
    Malformed configs raise MalformedSources (#221 / Story 13.49) — never a
    silent fall-through.
    """
    return [{"path": e["path"], "include": e["include"]}
            for e in get_typed_sources(lines, root) if e["type"] == "path"]


def get_policy_source(lines, root):
    """Parse the optional `policy_source` block.

    Returns (None, []) when the block is absent, else (block, errors) where
    block = {"path": abs-or-None} and
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

    block = {"path": None}
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
        # `track:` / `topics:` were REMOVED (Story 13.36, SPEC-policy-topic-at-
        # draft CAP-3): topic context is a per-article decision made in
        # draft-article Stage 2, never per-repo config. A leftover key is an
        # explicit, actionable error — never a silent ignore.
        m = re.match(r"^\s+(track|topics):", ln)
        if m:
            errors.append((f"policy_source.{m.group(1)}",
                           "removed (SPEC-policy-topic-at-draft CAP-3): which "
                           "policy topics an article reads is chosen per-article "
                           "in draft-article Stage 2. Fix: delete this line from "
                           "writing-sources.yaml."))
            continue

    if block["path"] is None:
        errors.append(("policy_source.path",
                       "required when policy_source is declared. Fix: set it to "
                       "the local product-lab checkout (a plain path; no URL)."))
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


def _write_back(root, new_lines, changed, what):
    """The one write-back path every setter shares (SPEC-repo-onboarding
    CAP-2): a legacy in-repo file migrates whole to the machine-global
    location (#211 — a bare global file holding only the new key would WIN
    resolution and shadow the legacy content), otherwise write when changed
    or when no file existed yet."""
    path, kind = sources_path(root)
    if kind == "legacy":
        gpath = os.path.join(rp.repo_config_dir(root), SOURCES_FILE)
        os.makedirs(os.path.dirname(gpath), exist_ok=True)
        with open(gpath, "w", encoding="utf-8") as fh:
            fh.write("\n".join(new_lines))
        sys.stderr.write(
            f"migrated: {path} copied to {gpath} (with {what} set) — the "
            f"machine-global file now wins; delete the in-repo copy (#211)\n")
    elif changed or kind == "none":
        write_lines(root, new_lines)


def cmd_set_draft_location(args):
    root = host_root(args.root)
    lines = read_lines(root)
    new_lines, changed = set_output_drafts(lines, args.path)
    _write_back(root, new_lines, changed, "output.drafts")
    print(get_output_drafts(new_lines))
    return 0


def cmd_set_policy_source(args):
    import json
    root = host_root(args.root)
    lines = read_lines(root)
    new_lines, changed = set_policy_source(lines, args.path)
    # Validate the RESULT before any write — a malformed block never lands.
    block, errors = get_policy_source(new_lines, root)
    if block is None or errors:
        for key, msg in errors or [("policy_source", "block failed to parse after surgery")]:
            sys.stderr.write(f"[{SOURCES_FILE}] {key}: {msg}\n")
        sys.stderr.write("refused: nothing was written\n")
        return POLICY_MALFORMED
    _write_back(root, new_lines, changed, "policy_source")
    print(json.dumps({"declared": True, "path": block["path"]}))
    return 0


def cmd_set_sources(args):
    import json
    root = host_root(args.root)
    try:
        specs = json.loads(sys.stdin.read())
    except json.JSONDecodeError as e:
        sys.stderr.write(f"set-sources: stdin is not valid JSON: {e}\n"
                         "refused: nothing was written\n")
        return SOURCES_MALFORMED
    errors = validate_source_specs(specs)
    if errors:
        for msg in errors:
            sys.stderr.write(f"[{SOURCES_FILE}] {msg}\n")
        sys.stderr.write("refused: nothing was written\n")
        return SOURCES_MALFORMED
    lines = read_lines(root)
    new_lines, changed = set_sources(lines, specs)
    _write_back(root, new_lines, changed, "sources")
    for s in get_sources(new_lines, root):
        print(s["path"])
    return 0


def cmd_sources(args):
    root = host_root(args.root)
    for s in get_sources(read_lines(root), root):
        print(s["path"])
    return 0


def cmd_typed_sources(args):
    """All declared entries with their type, as JSON (Story 13.49) — the
    reader for typed non-file sources (github-issues / tanuki-den harvest)."""
    import json
    root = host_root(args.root)
    out = []
    for e in get_typed_sources(read_lines(root), root):
        if e["type"] == "path":
            out.append({"type": "path", "path": e["path"],
                        "include": e["include"]})
        elif e["type"] == "github-issues":
            out.append({"type": "github-issues", "labels": e["labels"]})
        else:
            out.append({"type": e["type"]})
    print(json.dumps(out))
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
    # Emit the whole-tree noise warning only after the file list is fully
    # flushed. stdout is block-buffered under a pipe while stderr is unbuffered,
    # so without this flush the advisory lands *before* the buffered enumeration
    # in a merged capture — interleaved mid-list and easy to miss (#F63).
    sys.stdout.flush()
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
    print(json.dumps({"declared": True, "path": block["path"]}))
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
    sub.add_parser("typed-sources", parents=[root_parent])
    sp = sub.add_parser("is-declared", parents=[root_parent])
    sp.add_argument("path")
    sub.add_parser("files", parents=[root_parent])
    sub.add_parser("policy-source", parents=[root_parent])
    sp = sub.add_parser("set-policy-source", parents=[root_parent])
    sp.add_argument("path")
    sub.add_parser("set-sources", parents=[root_parent])
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
            "typed-sources": cmd_typed_sources,
            "is-declared": cmd_is_declared,
            "files": cmd_files,
            "policy-source": cmd_policy_source,
            "set-policy-source": cmd_set_policy_source,
            "set-sources": cmd_set_sources,
        }[args.cmd](args)
    except MalformedSources as e:
        # #221: never widen scope on a malformed narrowing directive — name the
        # offending line and read nothing.
        path, _ = sources_path(host_root(args.root))
        print(f"error: {path}: {e}", file=sys.stderr)
        return SOURCES_MALFORMED


if __name__ == "__main__":
    sys.exit(main())
