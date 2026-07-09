#!/usr/bin/env python3
"""Draft-article pipeline — stage 0 (invocation), Story 4.1.

`draft article <framework> from <sources>` starts the harvest-to-variant flow.
This helper does the mechanical part of stage 0: validate the framework against
the closed allowlist, classify each source token (path / glob / commit-range),
and emit a run-state record that stage 1 (harvest) consumes unmodified.

  start <FRAMEWORK> [SOURCE ...]

  * FRAMEWORK ∈ {F1, F2, F3, F4} (case-insensitive). Anything else is rejected
    with the valid set, a non-zero exit, and NO run-state emitted — no work
    begins, no partial state.
  * Each SOURCE is classified, with this precedence (disambiguation is explicit,
    not assumed):
      1. glob         — contains a glob metacharacter (* ? [ ])
      2. commit-range — `A..B` / `A...B` of ref-like parts, not a relative path
      3. path         — anything else (prefix a literal path with ./ to force it)
  * On success, prints the run-state JSON (framework, framework file, the raw
    sources verbatim, and their classification) and next_stage = harvest.

The recorded sources are a SELECTION for harvest, never a scope widener: stage 1
enumerates the writing-sources-declared files and INTERSECTS this selection, so
an undeclared path passed here cannot expand what gets read.
"""

import argparse
import json
import os
import re
import sys

FRAMEWORKS = {
    "f1": "F1-project-introduction.md",
    "f2": "F2-engineering-lessons.md",
    "f3": "F3-evaluation-methodology.md",
    "f4": "F4-research-survey.md",
}
GLOB_RE = re.compile(r"[*?\[\]{}]")
RANGE_RE = re.compile(r"^[A-Za-z0-9_.\-~^@]+\.\.\.?[A-Za-z0-9_.\-~^@/]+$")


def classify(token):
    if GLOB_RE.search(token):
        return "glob"
    # a relative/absolute path is never a commit-range, even with `..` in it
    if not token.startswith(("./", "../", "/")) and RANGE_RE.match(token) and ".." in token:
        return "commit-range"
    return "path"


def plugin_root():
    return os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def _load(name):
    import importlib.util
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(name.replace("-", "_").replace(".py", ""),
                                                  os.path.join(here, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def cmd_consume(args):
    """Stage 1: consume harvest's output document (fact sheet + NEEDS-OWNER) into
    pipeline state — WITHOUT re-reading any source. Source pointers are carried
    verbatim; the harvest contract (KINDS, pointer forms, TOPICS) is imported
    from the Epic 3 validators so a schema change surfaces here, not silently.
    """
    # Lazy import: stage 0 stays independent of these.
    vfs = _load("validate-fact-sheet.py")
    vno = _load("validate-needs-owner.py")

    text = sys.stdin.read() if args.doc == "-" else open(args.doc, encoding="utf-8").read()
    fs_lines, no_lines, has_no = vno.split_sections(text)
    if not has_no:
        sys.stderr.write("error: harvest output has no `# NEEDS-OWNER` section (contract violation)\n")
        return 1

    fact_sheet = []
    for e in vno.entries(fs_lines):
        parts = [p.strip() for p in e.rsplit(" / ", 2)]
        if len(parts) != 3 or any(p == "" for p in parts):
            sys.stderr.write(f"error: malformed fact-sheet entry (want `CLAIM / SOURCE / KIND`): {e}\n")
            return 1
        claim, source, kind = parts
        if kind not in vfs.KINDS:
            sys.stderr.write(f"error: fact-sheet KIND {kind!r} outside the harvest contract: {e}\n")
            return 1
        if not (vfs.URL_RE.match(source) or vfs.SHA_RE.match(source) or vfs.FILEPIN_RE.match(source)):
            sys.stderr.write(f"error: fact-sheet SOURCE {source!r} is not a valid pointer form: {e}\n")
            return 1
        fact_sheet.append({"claim": claim, "source": source, "kind": kind})   # source verbatim

    needs_owner = []
    for e in vno.entries(no_lines):
        parts = [p.strip() for p in e.rsplit(" / ", 2)]
        if len(parts) != 3 or any(p == "" for p in parts):
            sys.stderr.write(f"error: malformed NEEDS-OWNER entry (want `CANDIDATE / REASON / TOPIC`): {e}\n")
            return 1
        candidate, reason, topic = parts
        if topic not in vno.TOPICS:
            sys.stderr.write(f"error: NEEDS-OWNER TOPIC {topic!r} outside the harvest contract: {e}\n")
            return 1
        needs_owner.append({"candidate": candidate, "reason": reason, "topic": topic})

    state = {
        "stage": "consume",
        "next_stage": "interview",          # NEEDS-OWNER threads into the gap interview (Story 4.3)
        "fact_sheet": fact_sheet,
        "needs_owner": needs_owner,
    }
    print(json.dumps(state, indent=2))
    return 0


def cmd_start(args):
    key = args.framework.lower()
    if key not in FRAMEWORKS:
        sys.stderr.write(
            f"error: invalid framework {args.framework!r}. "
            f"Valid frameworks: F1, F2, F3, F4. Nothing started.\n"
        )
        return 2
    framework_file = os.path.join("skills", "draft-article", "frameworks", FRAMEWORKS[key])
    if not os.path.isfile(os.path.join(plugin_root(), framework_file)):
        sys.stderr.write(f"error: framework asset missing: {framework_file}\n")
        return 1
    state = {
        "next_stage": "harvest",
        "framework": key.upper(),
        "framework_file": framework_file,
        "sources_raw": list(args.sources),
        "sources": [{"value": t, "form": classify(t)} for t in args.sources],
    }
    print(json.dumps(state, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("start")
    sp.add_argument("framework")
    sp.add_argument("sources", nargs="*")
    sp = sub.add_parser("consume")
    sp.add_argument("doc", nargs="?", default="-", help="harvest output document, or - for stdin")
    args = p.parse_args(argv)
    return {"start": cmd_start, "consume": cmd_consume}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
