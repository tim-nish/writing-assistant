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
                            {"declared": false} when absent or `enabled: false`
                            (exit 0 — absence is not an error), else
                            {"declared": true}. NO path is ever reported
                            (Story 13.73, #366): the block is a presence
                            toggle — the consumer holds no hub filesystem
                            location; the gateway's operator config owns it.
                            A malformed block — an unreadable `enabled` value,
                            the RETIRED `path` key (13.73), or a leftover
                            `track:`/`topics:` key (removed by Story 13.36,
                            SPEC-policy-topic-at-draft CAP-3) — exits 4 with
                            per-key errors naming the fix (migration notice
                            included) — the stage-0 validator relays them.
                            Whether the GATEWAY is usable is deliberately not
                            checked here: an unreachable gateway is a
                            read-time degradation, never a config error.
                            An optional nested `track_topics:` mapping (#525,
                            articles-track → hub-topic name[s]) is parsed and,
                            when present, echoed in the JSON as `track_topics`;
                            a malformed mapping is a per-key stage-0 error too.

  set-policy-source [--disable]
                            Write the presence toggle (`policy_source:` +
                            `enabled: true`) into writing-sources.yaml
                            (SPEC-repo-onboarding CAP-2; re-shaped by Story
                            13.73 — the PATH argument was retired with the
                            config key). Declarative block replace: a legacy
                            block (`path:` / `track:` / `topics:`) is REPLACED
                            whole by the toggle — this is the sanctioned
                            migration path (#366). Comments outside the block
                            survive; idempotent; machine-global destination;
                            legacy-file migration. The result is validated
                            BEFORE writing. `--disable` removes the block
                            entirely (same semantics as never declaring it).
                            `--track-topics` additionally records the optional
                            track→topic mapping (#525) fed as JSON on stdin
                            (owner-approved, agent-fed; an empty {} = declined,
                            bare toggle written); it replaces — never revives —
                            the removed `--track/--topics` value flags.
                            Prints {"declared": true|false}.

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
JOURNEY_MALFORMED = 6 # journey: block present but malformed / unreadable (#671)


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


def set_policy_source(lines, enabled=True, track_topics=None):
    """Return (new_lines, changed). Declarative replace of the whole
    `policy_source` block with the presence toggle (Story 13.73, #366:
    `enabled: true` — the consumer holds no hub filesystem path; the
    gateway's operator config owns the hub location). An optional
    `track_topics` mapping (#525) is rendered as a nested sub-block under the
    toggle. Like set_sources, comments INSIDE the old block do not survive the
    replace (declarative semantics — deliberately so: this is also the
    sanctioned migration path for a legacy `path:` / `track:` / `topics:`
    block); comments outside it do. With enabled=False the block is removed
    entirely (same semantics as never declaring it)."""
    if enabled:
        block = ["policy_source:", "  enabled: true"]
        if track_topics:
            block += render_track_topics(track_topics)
    else:
        block = []
    start, end = _block_span(lines, r"^policy_source:\s*(#.*)?$")
    if start is None:
        if not enabled:
            return lines, False
        tail = []
        if lines and lines[-1].strip() != "":
            tail.append("")
        return lines + tail + block, True
    # keep trailing blank separation as-is: replace header..last content
    last = end
    while last > start + 1 and lines[last - 1].strip() == "":
        last -= 1
    new = lines[:start] + block + lines[last:]
    return new, new != lines


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


def get_journey(lines, root):
    """Parse the optional top-level `journey:` block (Story 18.95, #671) into
    (paths, errors): the declared episode-record file(s), each resolved to an
    absolute path against `root`. `journey:` is a list — a block of `- path`
    items, or an inline `[a, b]`. An absent block → ([], []); a declared-but-
    empty or path-escaping block → an error. Resolution/validation follows the
    source-set rules: a path never escapes the root."""
    start, end = _block_span(lines, r"^journey:\s*(#.*)?$")
    if start is None:
        return [], []
    errors = []
    raws = []
    m = re.match(r"^journey:\s*\[(.*)\]\s*(#.*)?$", lines[start])
    if m:                                   # inline list form
        raws = [x.strip().strip('"').strip("'") for x in m.group(1).split(",")
                if x.strip()]
    else:                                   # block list of `- path` items
        for ln in lines[start + 1:end]:
            if ln.strip() == "" or ln.lstrip().startswith("#"):
                continue
            lm = re.match(r"^\s*-\s*(.*?)\s*$", ln)
            if not lm:
                errors.append(("journey", f"unreadable list line {ln.strip()!r} — "
                               "journey is a list of episode-record file paths "
                               "(e.g. `- docs/journey.md`)"))
                continue
            item = re.sub(r"\s+#.*$", "", lm.group(1)).strip().strip('"').strip("'")
            if item:
                raws.append(item)
    if not raws and not errors:
        errors.append(("journey", "declared but empty — remove the key or name at "
                       "least one episode-record file"))
    paths = []
    for r in raws:
        if ".." in r.split("/"):
            errors.append(("journey", f"path {r!r} escapes the repository with "
                           "`..` — an episode record lives inside the declared "
                           "source set"))
            continue
        paths.append(os.path.normpath(r) if os.path.isabs(r)
                     else os.path.normpath(os.path.join(root, r)))
    return paths, errors


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


def _parse_track_topics(lines, hdr_idx, hdr_indent):
    """Parse a nested `track_topics:` sub-block (#525, SPEC-policy-topic-at-draft
    CAP-5). Returns (mapping, errors, next_idx) where mapping maps an
    articles-repo track name to a list of hub topic name(s). A value may be a
    bare string (→ a single-element list), an inline list (`[a, b]`), or a
    block list of `- item` lines. A malformed entry — a non-`key: value` line
    where a mapping was expected, or a value that is neither a string nor a
    non-empty list of strings — appends a (key, message) stage-0 config error
    (same shape as the other `policy_source.*` errors → the resolver exits 4).
    next_idx is the first index at or below the header indent (the line after
    the sub-block)."""
    mapping = {}
    errors = []
    n = len(lines)
    j = hdr_idx + 1
    while j < n:
        ln = lines[j]
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            j += 1
            continue
        if _indent(ln) <= hdr_indent:
            break  # left the track_topics sub-block
        m = re.match(r"^(\s+)([^:#]+?)\s*:\s*(.*)$", ln)
        if not m:
            errors.append(("policy_source.track_topics",
                           f"unreadable mapping line {ln.strip()!r} — track_topics "
                           "is a mapping of articles-repo track name to hub topic "
                           "name(s). Fix: `<track>: <topic>` or "
                           "`<track>: [<t1>, <t2>]`."))
            j += 1
            continue
        entry_indent = len(m.group(1))
        key = m.group(2).strip().strip('"').strip("'")
        raw = re.sub(r"\s+#.*$", "", m.group(3)).strip()
        j += 1
        if raw.startswith("[") and raw.endswith("]"):
            items = [x.strip().strip('"').strip("'") for x in raw[1:-1].split(",")]
            items = [x for x in items if x]
            if items:
                mapping[key] = items
            else:
                errors.append((f"policy_source.track_topics.{key}",
                               "value is an empty list — a track must map to at "
                               "least one hub topic. Fix: `<track>: <topic>` or a "
                               "non-empty `[<t1>, <t2>]` list."))
            continue
        if raw:
            mapping[key] = [raw.strip('"').strip("'")]
            continue
        # empty inline value → look ahead for a block list of `- item` lines
        items = []
        while j < n:
            sub = lines[j]
            if sub.strip() == "" or sub.lstrip().startswith("#"):
                j += 1
                continue
            if _indent(sub) <= entry_indent:
                break
            lm = re.match(r"^\s*-\s*(.*?)\s*$", sub)
            if not lm:
                break
            item = re.sub(r"\s+#.*$", "", lm.group(1)).strip().strip('"').strip("'")
            if item:
                items.append(item)
            j += 1
        if items:
            mapping[key] = items
        else:
            errors.append((f"policy_source.track_topics.{key}",
                           "value is neither a topic name nor a list of topic "
                           "names. Fix: `<track>: <topic>`, `<track>: [<t1>, <t2>]`, "
                           "or a `- <topic>` block list."))
    return mapping, errors, j


def validate_track_topics(mapping):
    """Fail-closed write-time validation for a `track_topics` mapping fed to
    `set-policy-source --track-topics` (JSON on stdin, like set-sources).
    Returns a list of error strings; empty means writable. An empty mapping is
    valid (a declined offer — the caller writes the bare toggle)."""
    errors = []
    if not isinstance(mapping, dict):
        return ['track_topics must be a JSON object mapping "<track>": '
                '"<topic>" | ["<t1>", "<t2>"]']
    for track, val in mapping.items():
        if not isinstance(track, str) or not track.strip():
            errors.append(f"track_topics: a non-empty string track name is "
                          f"required (got {track!r})")
            continue
        if isinstance(val, str):
            if not val.strip():
                errors.append(f"track_topics.{track}: the topic name must be a "
                              "non-empty string")
        elif isinstance(val, list):
            if not val or any(not isinstance(t, str) or not t.strip() for t in val):
                errors.append(f"track_topics.{track}: must be a non-empty list of "
                              "non-empty topic-name strings")
        else:
            errors.append(f"track_topics.{track}: value must be a topic name or a "
                          "list of topic names")
    return errors


def render_track_topics(mapping):
    """The nested `track_topics:` lines for a policy_source block (#525) — a
    single topic renders inline (`track: topic`), multiple render as the inline
    list form (`track: [a, b]`), byte-consistent with the reader."""
    out = ["  track_topics:"]
    for track, topics in mapping.items():
        if len(topics) == 1:
            out.append(f"    {track}: {topics[0]}")
        else:
            out.append(f"    {track}: [{', '.join(topics)}]")
    return out


def get_policy_source(lines, root):
    """Parse the optional `policy_source` block (presence toggle — Story
    13.73, #366).

    Returns (None, []) when the block is absent, else (block, errors) where
    block = {"enabled": bool-or-None} and errors is a list of (key, message)
    pairs for a malformed block. An optional nested `track_topics:` mapping
    (#525, SPEC-policy-topic-at-draft CAP-5) is parsed into
    block["track_topics"] = {track: [topic, ...]} WHEN PRESENT (absent =
    byte-identical to before — the key is simply not added). The RETIRED
    `path` key (13.73) and the removed `track`/`topics` keys (13.36) are named
    configuration errors carrying a migration notice — NEVER silently honored.
    Whether the gateway is usable is deliberately not checked here: an
    unreachable gateway is a read-time degradation, never a config error."""
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^policy_source:\s*(#.*)?$", ln):
            start = i
            break
    if start is None:
        return None, []

    def _val(raw):
        return re.sub(r"\s+#.*$", "", raw).strip().strip('"').strip("'")

    block = {"enabled": None}
    errors = []
    j = start + 1
    while j < len(lines):
        ln = lines[j]
        j += 1
        if ln.strip() == "" or ln.lstrip().startswith("#"):
            continue
        if _indent(ln) == 0:
            break  # left the block
        m = re.match(r"^\s+enabled:\s*(.*)$", ln)
        if m:
            raw = _val(m.group(1)).lower()
            if raw in ("true", "yes", "on"):
                block["enabled"] = True
            elif raw in ("false", "no", "off"):
                block["enabled"] = False
            else:
                errors.append(("policy_source.enabled",
                               f"unreadable value {raw!r} — the presence toggle "
                               "takes `true` or `false` (#366)."))
            continue
        # Optional `track_topics:` mapping (#525): parse the nested sub-block and
        # skip past it. Absent = the key is never added (byte-identical to today).
        mt = re.match(r"^\s+track_topics:\s*(.*)$", ln)
        if mt:
            rest = re.sub(r"\s+#.*$", "", mt.group(1)).strip()
            hdr_indent = _indent(ln)
            if rest:
                errors.append(("policy_source.track_topics",
                               "track_topics is a nested mapping — put entries on "
                               "the following indented lines. Fix: `track_topics:` "
                               "then `  <track>: <topic>`."))
            mapping, terrs, nxt = _parse_track_topics(lines, j - 1, hdr_indent)
            if mapping:
                block["track_topics"] = mapping
            errors.extend(terrs)
            j = nxt
            continue
        # `path:` is RETIRED (Story 13.73, #366): the consumer holds no hub
        # filesystem location — the gateway's operator config owns it. A
        # leftover key is a named configuration error with a migration
        # notice — never silently honored.
        if re.match(r"^\s+path:", ln):
            errors.append(("policy_source.path",
                           "retired (#366): the consumer holds no hub path — "
                           "replace the block with `policy_source:` + "
                           "`enabled: true` (the gateway owns the hub "
                           "location). Fix: run `resolve-writing-sources.py "
                           "set-policy-source --root <host-repo>` (no path "
                           "argument) to migrate, or delete this line."))
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

    if block["enabled"] is None and not errors:
        errors.append(("policy_source.enabled",
                       "required when policy_source is declared (presence "
                       "toggle, #366). Fix: set `enabled: true` — the gateway "
                       "owns the hub location."))
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
    enabled = not args.disable
    # Optional track_topics mapping (#525), fed as JSON on stdin (like
    # set-sources) — opt-in via --track-topics so a plain toggle write never
    # blocks on stdin. An empty object is a DECLINED offer: write the bare
    # toggle, nothing extra.
    mapping = None
    if getattr(args, "track_topics", False):
        if not enabled:
            sys.stderr.write("set-policy-source: --track-topics cannot combine with "
                             "--disable\nrefused: nothing was written\n")
            return POLICY_MALFORMED
        try:
            raw = json.loads(sys.stdin.read())
        except json.JSONDecodeError as e:
            sys.stderr.write(f"set-policy-source: --track-topics stdin is not valid "
                             f"JSON: {e}\nrefused: nothing was written\n")
            return POLICY_MALFORMED
        errors = validate_track_topics(raw)
        if errors:
            for msg in errors:
                sys.stderr.write(f"[{SOURCES_FILE}] {msg}\n")
            sys.stderr.write("refused: nothing was written\n")
            return POLICY_MALFORMED
        if raw:  # non-empty; empty {} = declined → bare toggle
            mapping = {k: ([v] if isinstance(v, str) else list(v))
                       for k, v in raw.items()}
    new_lines, changed = set_policy_source(lines, enabled=enabled, track_topics=mapping)
    # Validate the RESULT before any write — a malformed block never lands.
    block, errors = get_policy_source(new_lines, root)
    if enabled and (block is None or errors or not block["enabled"]):
        for key, msg in errors or [("policy_source", "block failed to parse after surgery")]:
            sys.stderr.write(f"[{SOURCES_FILE}] {key}: {msg}\n")
        sys.stderr.write("refused: nothing was written\n")
        return POLICY_MALFORMED
    if mapping is not None and block.get("track_topics") != mapping:
        sys.stderr.write(f"[{SOURCES_FILE}] policy_source.track_topics: the written "
                         "mapping did not round-trip through the parser\n"
                         "refused: nothing was written\n")
        return POLICY_MALFORMED
    if not enabled and (block is not None or errors):
        sys.stderr.write(f"[{SOURCES_FILE}] policy_source: block survived removal surgery\n"
                         "refused: nothing was written\n")
        return POLICY_MALFORMED
    # --disable with no config file at all: nothing to remove, create nothing.
    if not (args.disable and not changed and sources_path(root)[1] == "none"):
        _write_back(root, new_lines, changed, "policy_source")
    out = {"declared": enabled}
    if mapping is not None:
        out["track_topics"] = mapping
    print(json.dumps(out))
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
    lines = read_lines(root)
    sources = get_sources(lines, root)
    files = enumerate_files(sources)
    # Declared journey files (#671) are read as ordinary declared prose — no new
    # read path — so they join the harvest read set, deduplicated against the
    # source enumeration. A non-existent journey file contributes nothing here
    # (its absence is surfaced by the `journey` validation subcommand instead).
    jpaths, _ = get_journey(lines, root)
    seen = {os.path.realpath(f) for f in files}
    for jp in jpaths:
        if os.path.isfile(jp) and os.path.realpath(jp) not in seen:
            seen.add(os.path.realpath(jp))
            files.append(jp)
    files = sorted(files)
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


def cmd_journey(args):
    """Resolve the declared `journey:` episode-record file(s) (#671). Prints
    `{"journey": [<abs path>, ...]}` when the block is absent (empty list) or
    every declared file resolves to a readable file. A malformed block or a
    declared file that does not exist is a stage-0 configuration DEFECT — the
    same lint shape used for source `include:` paths and variant-profile target
    directories — surfaced on stderr, exiting JOURNEY_MALFORMED so the stage-0
    aggregate (validate-config.py) relays it."""
    import json
    root = host_root(args.root)
    paths, errors = get_journey(read_lines(root), root)
    for key, msg in errors:
        sys.stderr.write(f"[{SOURCES_FILE}] {key}: {msg}\n")
    missing = [p for p in paths if not os.path.isfile(p)]
    for p in missing:
        sys.stderr.write(
            f"[{SOURCES_FILE}] journey: declared episode-record file does not "
            f"exist or is not a readable file: {p}. Fix: create it, or correct "
            "the `journey:` path.\n")
    if errors or missing:
        return JOURNEY_MALFORMED
    print(json.dumps({"journey": paths}))
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
    out = {"declared": bool(block["enabled"])}
    if block.get("track_topics"):  # #525: expose the mapping when present
        out["track_topics"] = block["track_topics"]
    print(json.dumps(out))
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
    sub.add_parser("journey", parents=[root_parent])
    sub.add_parser("policy-source", parents=[root_parent])
    sp = sub.add_parser("set-policy-source", parents=[root_parent])
    # No positional PATH (Story 13.73, #366): the block is a presence toggle;
    # the consumer never holds the hub's filesystem location.
    sp.add_argument("--disable", action="store_true",
                    help="remove the policy_source block entirely "
                         "(same semantics as never declaring it)")
    sp.add_argument("--track-topics", action="store_true", dest="track_topics",
                    help="also record a track_topics mapping (#525): read a JSON "
                         'object {"<track>": "<topic>" | ["<t1>", "<t2>"]} from '
                         "stdin (like set-sources). An empty {} is a declined "
                         "offer — the bare toggle is written. Owner-approved, "
                         "agent-fed; replaces the removed --track/--topics flags.")
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
            "journey": cmd_journey,
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
