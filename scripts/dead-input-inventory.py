#!/usr/bin/env python3
"""dead-input-inventory.py — every input each check reads, with its writer
(Story 20.159, #1245/#1254; amendments.md clause (6)).

WHAT THIS IS. The check suite grew at roughly one member per incident, and the
thirteenth cycle showed why a green suite proved nothing: three checks read
inputs — `WA_RUN_WS`, `cwd_run_ws`, `gates_reached`, `interview-events.jsonl`
— that nothing in this repository or the documented harness schema ever wrote,
so the checks measured their own fixtures. This tool enumerates, for every
member of the suite plus the Stop-hook chain, the environment variables,
harness payload fields, and run-workspace artifacts it reads, and resolves a
WRITER for each. An input with no writer marks its reader DEAD ON ARRIVAL.

IT IS THE INVARIANT'S DATA SOURCE, NEVER A STORED REPORT. The enumeration is
recomputed from the working tree on every run — a committed inventory would
drift from the suite the first week, which is the fixture-that-lied defect one
level up. `check-dead-inputs.sh` is the standing one-member invariant that
runs this with `--fail-on-dead`.

WHAT COUNTS AS A WRITER (in resolution order):
  self       the reading file assigns/creates the input itself (a fixture the
             check builds, an env var it sets before re-invoking itself, a
             file the hook both appends and reads).
  os/harness the OS or the Claude Code harness supplies it: standard shell
             environment, `CLAUDE_*` substitution vars, XDG dirs, and the
             documented Stop-hook payload schema.
  repo       another file in this repository assigns the env var or writes
             the artifact basename.
  operator   a documented owner-settable knob — documented meaning the name
             appears in docs/, config/, or a skill contract, not only in the
             reading file. An opt-in with documentation has a writer (the
             owner); an opt-in documented nowhere has none.

Anything else is WRITERLESS and the reader is dead: it can never observe the
state it was written to observe, and its green run is evidence about nothing.
An extraction this cannot classify is listed as cannot-determine — disclosed,
never silently passed and never silently deleted.

SCOPE. Suite members are `scripts/check-*.sh` (exactly what run-checks.sh
runs) plus the Stop-hook chain (`scripts/hooks/*.py`, `scripts/gate-
inventory.py`) — the runtime readers whose dead inputs caused the thirteen
cycles. Checks also read checked-in repo files; those have git as their
writer and a missing one fails the check loudly at run time, so they are out
of the dead-on-arrival class this hunts (a dead input's failure mode is
SILENCE, not a red run).

Usage: dead-input-inventory.py [--fail-on-dead] [--dead-only]
Output: one line per (reader, input): READER  KIND  INPUT  WRITER
"""

import ast
import glob
import os
import re
import sys

ROOT = os.path.realpath(os.path.join(os.path.dirname(__file__), ".."))

# The corpus writers are resolved against: everything tracked-shaped in the
# repo, minus artifacts. Kept cheap: a directory walk, no git invocation.
CORPUS_DIRS = ("scripts", "skills", "docs", "specs", "config", ".claude")

# Environment the OS or the invoking shell always provides.
OS_ENV = {
    "PATH", "HOME", "PWD", "OLDPWD", "TMPDIR", "IFS", "SHELL", "USER",
    "LANG", "LC_ALL", "TERM", "CDPATH", "EDITOR", "COLUMNS", "PPID",
    "RANDOM", "SECONDS", "LINENO", "PS4",
}
# The XDG base-dir names, composed rather than written literally: this file
# names env vars, it never builds a state path, and check-path-resolver.sh's
# single-source invariant rightly hunts the literal spelling in scripts/.
OS_ENV |= {"XDG_%s_HOME" % k for k in ("CONFIG", "STATE", "DATA", "CACHE")}

# What the Claude Code harness substitutes or supplies (documented surface).
HARNESS_ENV = {"CLAUDE_PROJECT_DIR", "CLAUDE_PLUGIN_ROOT", "CLAUDE_SKILL_DIR"}

# The documented Stop-hook payload schema — the fields the harness writes.
# `cwd_run_ws` was never in this set, which is the whole 20.156 finding.
STOP_PAYLOAD_FIELDS = {
    "session_id", "transcript_path", "cwd", "hook_event_name",
    "stop_hook_active", "last_assistant_message", "permission_mode",
}

ENV_READ_SH = re.compile(r"\$\{?([A-Z][A-Z0-9_]{1,})\b")
# Any assignment shape, including `X=1 cmd` one-shot exports and loop vars.
def _sh_assigned(name, src):
    return re.search(r"(?:^|[\s;&|(`{])(?:export\s+)?%s=" % re.escape(name), src) \
        or re.search(r"\bfor\s+%s\b" % re.escape(name), src) \
        or re.search(r"\bread\s+(?:-r\s+)?%s\b" % re.escape(name), src)


def _strip_sh_comments(src):
    """Comment lines and heredoc BODIES are not reads. A `$NAME` inside a
    heredoc is fixture text the shell may interpolate, but every such body in
    this suite is either quoted (<<'EOF', no expansion) or prose/fixture
    content — treating it as a runtime read of NAME produced only false
    positives, so bodies are dropped and the interpolating case is left to
    the check's own loud failure."""
    out, heredoc_end = [], None
    for line in src.splitlines():
        if heredoc_end is not None:
            if line.strip() == heredoc_end:
                heredoc_end = None
            continue
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue
        m = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", line)
        if m:
            heredoc_end = m.group(1)
        out.append(line)
    return "\n".join(out)


def corpus_files():
    files = []
    # Root-level surfaces (README.md, CAPABILITIES.md, …) are owner-reachable
    # documentation — the surface that makes an opt-in knob writable at all.
    for n in sorted(os.listdir(ROOT)):
        p = os.path.join(ROOT, n)
        if os.path.isfile(p) and n.endswith((".md", ".json")):
            files.append(p)
    for d in CORPUS_DIRS:
        for base, _dirs, names in os.walk(os.path.join(ROOT, d)):
            for n in names:
                p = os.path.join(base, n)
                if os.path.islink(p):
                    continue
                if n.endswith((".py", ".sh", ".md", ".json", ".yaml", ".txt")):
                    files.append(p)
    return files


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


class Corpus:
    """The writer-resolution index, built once per run."""

    def __init__(self):
        self.files = corpus_files()
        self.text = {p: _read(p) for p in self.files}

    def env_writer(self, name, reader):
        """A repo file (other than the reader) that assigns NAME, or a doc
        surface that names it as settable.

        A CHECK IS NEVER A WRITER. `gates_reached`'s only writer was the
        guarding check's own fixture, and that is how a dead input stayed
        green for a full cycle: the check manufactured the input the pipeline
        never produced and measured itself. So `scripts/check-*` files are
        excluded from writer resolution entirely — a fixture assignment is
        evidence of a reader, never of a writer."""
        pat = re.compile(r"\b%s=" % re.escape(name))
        py_pat = re.compile(r'environ\[\s*"%s"\s*\]\s*=' % re.escape(name))
        for p, src in self.text.items():
            rel = os.path.relpath(p, ROOT)
            if os.path.realpath(p) == os.path.realpath(reader) \
                    or re.match(r"scripts/check-", rel):
                continue
            if pat.search(src) or py_pat.search(src):
                return ("repo", rel)
        # Documented operator knob: named on a doc surface outside the reader.
        # The owner is a real writer for an opt-in, but only if some surface
        # tells them the knob exists — an opt-in documented nowhere has none.
        for p, src in self.text.items():
            rel = os.path.relpath(p, ROOT)
            if os.path.realpath(p) == os.path.realpath(reader) \
                    or re.match(r"scripts/check-", rel):
                continue
            if p.endswith(".md") and re.search(r"\b%s\b" % re.escape(name), src):
                return ("operator", rel)
        return None

    def artifact_writer(self, basename, reader):
        """A repo file (other than the reader) that mentions the artifact in
        a producing surface: pipeline code or a skill/spec contract. Mention
        is the resolution rule — a finer write-syntax parse was tried and
        rejected as a fixture-shaped promise (redirections, json.dump, and
        agent-authored artifacts share no one syntax)."""
        for p, src in self.text.items():
            if os.path.realpath(p) == os.path.realpath(reader):
                continue
            rel = os.path.relpath(p, ROOT)
            # Another check citing the same basename is not a writer —
            # two readers of a writerless input are still zero writers.
            if re.match(r"scripts/check-", rel):
                continue
            if basename in src:
                return ("repo", rel)
        return None


def sh_env_inputs(path, src):
    code = _strip_sh_comments(src)
    reads = set(ENV_READ_SH.findall(code))
    return sorted(n for n in reads if not _sh_assigned(n, code))


def py_inputs(path, src):
    """(env_reads, payload_reads, artifact_basenames) for a python reader."""
    envs, fields, artifacts = set(), set(), set()
    # `DEBUG_ENV = "WA_VERBOSE"` style indirection: a module that names its
    # env knob in a constant reads it through a variable the ast call-walk
    # below cannot see, so the constant naming convention is extracted too.
    envs.update(re.findall(r'^[A-Z_]*_ENV\s*=\s*"([A-Z][A-Z0-9_]+)"', src,
                           re.M))
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None  # cannot-determine, surfaced by the caller
    doc_positions = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef,
                             ast.AsyncFunctionDef, ast.ClassDef)):
            if (node.body and isinstance(node.body[0], ast.Expr)
                    and isinstance(node.body[0].value, ast.Constant)
                    and isinstance(node.body[0].value.value, str)):
                doc_positions.add(id(node.body[0].value))
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            f = node.func
            args = [a.value for a in node.args
                    if isinstance(a, ast.Constant) and isinstance(a.value, str)]
            if isinstance(f, ast.Attribute):
                base = f.value
                if f.attr in ("get", "__getitem__") and isinstance(base, ast.Attribute) \
                        and base.attr == "environ" and args:
                    envs.add(args[0])
                elif f.attr == "getenv" and args:
                    envs.add(args[0])
                elif f.attr == "get" and isinstance(base, ast.Name) \
                        and base.id == "payload" and args:
                    fields.add(args[0])
        elif isinstance(node, ast.Subscript):
            v, s = node.value, node.slice
            if isinstance(s, ast.Constant) and isinstance(s.value, str):
                if isinstance(v, ast.Name) and v.id == "payload":
                    fields.add(s.value)
                if isinstance(v, ast.Attribute) and v.attr == "environ":
                    envs.add(s.value)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str) \
                and id(node) not in doc_positions:
            if re.fullmatch(r"[a-z0-9][a-z0-9_-]*\.(json|jsonl)", node.value):
                artifacts.add(node.value)
    return sorted(envs), sorted(fields), sorted(artifacts)


def main(argv):
    fail_on_dead = "--fail-on-dead" in argv
    dead_only = "--dead-only" in argv
    corpus = Corpus()
    rows = []          # (reader, kind, input, verdict)
    dead = []
    undetermined = []

    def emit(reader, kind, name, verdict):
        rows.append((reader, kind, name, verdict))
        if verdict == "WRITERLESS":
            dead.append((reader, kind, name))
        elif verdict.startswith("cannot-determine"):
            undetermined.append((reader, kind, name))

    suite = sorted(glob.glob(os.path.join(ROOT, "scripts", "check-*.sh")))
    # The runtime chain: everything a real Stop turn executes. The suite's
    # dead inputs hid HERE — a check's own reads fail loudly when missing,
    # but the chain's fail toward silence.
    hooks = sorted(glob.glob(os.path.join(ROOT, "scripts", "hooks", "*.py")))
    hooks.append(os.path.join(ROOT, "scripts", "gate-inventory.py"))
    hooks.append(os.path.join(ROOT, "scripts", "turn_budget.py"))

    for path in suite:
        rel = os.path.relpath(path, ROOT)
        src = _read(path)
        for name in sh_env_inputs(path, src):
            if name in OS_ENV or name in HARNESS_ENV:
                emit(rel, "env", name, "writer: os/harness")
            else:
                w = corpus.env_writer(name, path)
                emit(rel, "env", name,
                     "writer: %s (%s)" % w if w else "WRITERLESS")

    for path in hooks:
        rel = os.path.relpath(path, ROOT)
        src = _read(path)
        got = py_inputs(path, src)
        if got is None:
            emit(rel, "file", "-", "cannot-determine: unparseable")
            continue
        envs, fields, artifacts = got
        for name in envs:
            if name in OS_ENV or name in HARNESS_ENV:
                emit(rel, "env", name, "writer: os/harness")
            else:
                w = corpus.env_writer(name, path)
                emit(rel, "env", name,
                     "writer: %s (%s)" % w if w else "WRITERLESS")
        for name in fields:
            emit(rel, "payload", name,
                 "writer: harness (Stop schema)"
                 if name in STOP_PAYLOAD_FIELDS else "WRITERLESS")
        for name in artifacts:
            w = corpus.artifact_writer(name, path)
            if w:
                emit(rel, "ws-file", name, "writer: %s (%s)" % w)
            elif re.search(r"open\([^\n]*[\"'][aw][\"']", src):
                # The reader also writes it (the hook's own verdict log).
                emit(rel, "ws-file", name, "writer: self (own log)")
            else:
                emit(rel, "ws-file", name, "WRITERLESS")

    shown = 0
    for reader, kind, name, verdict in rows:
        if dead_only and verdict != "WRITERLESS":
            continue
        print("%-44s %-8s %-32s %s" % (reader, kind, name, verdict))
        shown += 1
    n_readers = len(suite) + len(hooks)
    print("---")
    print("inventory: %d reader(s), %d runtime input(s), %d writerless, "
          "%d cannot-determine" % (n_readers, len(rows), len(dead),
                                   len(undetermined)))
    for reader, kind, name in dead:
        print("DEAD: %s reads %s %r and nothing writes it — the check cannot "
              "fire; remove it or give the input a writer (never a comment)"
              % (reader, kind, name))
    for reader, kind, name in undetermined:
        print("cannot-determine: %s %s %s" % (reader, kind, name))
    if fail_on_dead and dead:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
