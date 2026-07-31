#!/usr/bin/env python3
"""harvest-scope.py — the term-derived file-scope PROPOSAL for a harvest.

Story 20.43 (#906); SPEC-article-draft-pipeline, the harvest-scope amendment of
2026-07-29 (#896).

Under the thesis model the material worth searching is derived from the
thesis's Strands: their tags, slugs and gloss terms. This script greps those
terms over the host repo's **declared sources** and proposes the files a
harvest should read. It is a **proposal**, not a filter — the owner accepts,
widens or ignores it at the existing gate, and free text always wins.

**Deterministic by construction.** Same terms plus same declared sources give
byte-identical output: terms are de-duplicated and sorted, files come in the
enumerator's own order (`resolve-writing-sources.py files`, the single source
of truth for the read boundary), and matching is whole-word and
case-insensitive. Nothing is ranked and nothing is scored — ordering a
proposal by judged relevance is the second-proposer boundary, and a scope
proposal that narrows by machine judgment is the act that boundary bans.

**The terms are shown.** A scope the owner cannot explain is a scope they
cannot correct, so every proposed file names the terms that put it there, and
the derived term list is emitted whether or not it matched anything.

**The repo boundary is the enumerator's.** Only the declared sources of the
resolved root are searched. A file outside them enters solely by explicit
request (`--include`), and it is disclosed as owner-requested in the manifest
rather than folded silently into the proposal — the same rule that keeps an
out-of-scope repository from ever being searched automatically.

**No embedding index, deliberately.** The drafting model already does semantic
matching by reading CLAIM prose at the moment of need; a retrieval layer is
deferred behind an observed-miss trigger recorded in SPEC-writing-assistant.
This is the cheap deterministic half, and it is the whole of it.

Usage:
  harvest-scope.py [--root R] --terms a,b,c
  harvest-scope.py [--root R] --terms a,b,c --json
  harvest-scope.py [--root R] --terms a,b,c --include docs/notes.md
"""

import argparse
import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SRC_RES = os.path.join(SCRIPT_DIR, "resolve-writing-sources.py")


def host_root(arg_root):
    """--root or the git toplevel of cwd, realpath'd. Keep in sync with the
    identical helper in the sibling resolvers."""
    if arg_root:
        return os.path.realpath(arg_root)
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.stderr.write("error: not inside a git repository (pass --root)\n")
        raise SystemExit(2)
    return os.path.realpath(r.stdout.strip())


def declared_files(root):
    """The host repo's declared writing sources, in the enumerator's order.

    Read through the single enumerator rather than globbed here: the read
    boundary and its order are its contract, and a second enumeration would be
    a second boundary that drifts from it.
    """
    cmd = [sys.executable, SRC_RES]
    if root:
        cmd += ["--root", root]
    cmd += ["files"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        detail = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                  else f"the resolver exited {r.returncode}")
        return [], f"{detail} (resolve-writing-sources.py exit {r.returncode})"
    files = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    if not files:
        return [], "the host repo declares no writing sources"
    return files, None


def normalise_terms(raw):
    """The derived terms: split, trimmed, de-duplicated, SORTED.

    Sorted because the output must not depend on the order the caller happened
    to assemble a thesis's Strands in — two runs over the same material are
    the same proposal or the determinism claim is empty.
    """
    out = set()
    for chunk in raw or []:
        for t in str(chunk).split(","):
            t = t.strip()
            if t:
                out.add(t)
    return sorted(out)


def term_pattern(term):
    """Whole-word, case-insensitive. A slug's hyphens are literal, so a term
    like `carry-the-grade` matches the slug and not its individual words."""
    return re.compile(r"(?<![\w-])" + re.escape(term) + r"(?![\w-])",
                      re.IGNORECASE)


def propose(root, files, terms):
    """Which declared files carry which terms, in enumeration order.

    Returns `[{path, terms, hits}]` for the files that matched at least one
    term. A file is proposed because a term is IN it — never because it scored
    well against one, which is a distinction the second-proposer boundary
    turns on.
    """
    patterns = [(t, term_pattern(t)) for t in terms]
    proposed, binary = [], []
    for rel in files:
        path = os.path.join(root, rel)
        try:
            with open(path, "rb") as fh:
                raw = fh.read()
        except OSError:
            # A declared source that cannot be read is reported by the
            # enumerator's own consumers; scope proposal skips it rather than
            # claiming a match it could not test.
            continue
        if b"\x00" in raw:
            # A binary file has no terms to match — a "hit" in one is a byte
            # coincidence from decoding it as text. Skipped as a CORRECTNESS
            # matter and disclosed by name, never filtered silently: the read
            # boundary stays the enumerator's, and this narrows nothing a
            # reader could have wanted.
            binary.append(rel)
            continue
        body = raw.decode("utf-8", errors="replace")
        matched, hits = [], 0
        for term, pat in patterns:
            n = len(pat.findall(body))
            if n:
                matched.append(term)
                hits += n
        if matched:
            proposed.append({"path": rel, "terms": matched, "hits": hits})
    return proposed, binary


def repo_files(root):
    """The host repository's tracked files, WITHOUT READING ANY OF THEM.

    THE REMAINDER IS COUNTED, NEVER READ (Story 20.110, #1104). The
    declared-sources boundary is not widened by this: widening was considered
    at the #1104 gate and declined against three ratified texts. What the count
    buys is the one thing every disclosure lacked — the denominator's
    provenance.

    Returns (absolute paths, reason) and never raises: a repository that cannot
    be enumerated yields a stated cannot-determine, which is a THIRD VALUE and
    never a zero — "not observed" without consulting the source is not
    "absent".
    """
    base = os.path.abspath(root or ".")
    r = subprocess.run(["git", "-C", base, "ls-files"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        detail = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                  else f"git ls-files exited {r.returncode}")
        return None, detail
    return {os.path.join(base, ln.strip())
            for ln in r.stdout.splitlines() if ln.strip()}, None


def substrate(root, files, terms, proposed):
    """What this harvest was computed OVER, stated before any coverage figure.

    THE ISSUE'S CLAIM SURVIVED EVERYTHING ALREADY BUILT. The coverage
    disclosure is closed and refuses to sample, and the term list is emitted
    whether or not it matched — yet the universe is `declared_files(root)`, so
    every disclosure is denominated against a SUPPLIED enumeration and the
    phase cannot discover the enumeration was wrong. Coverage of a
    predetermined subset is indistinguishable from coverage.

    So the denominator gets its own provenance: admitted, the unexamined
    remainder, and the terms that found nothing. "92% coverage" was not
    actionable; "92% of 11 declared files, with 340 outside the declaration"
    is.
    """
    tracked, unavailable = repo_files(root)
    admitted = len(files)
    matched_terms = {t for p in proposed for t in p.get("terms", [])}
    # A SET DIFFERENCE, NEVER A SUBTRACTION OF COUNTS. Measured on this
    # repository while building this story: 404 declared against 356 tracked —
    # the declaration is not a SUBSET of the tracked tree (globs reach
    # untracked and generated files), so `total - admitted` would have gone
    # negative and clamped to a confident, unfounded zero. That is the exact
    # class this story exists to fix, committed inside the fix.
    declared_abs = {os.path.abspath(f) for f in files}
    outside = None if tracked is None else sorted(tracked - declared_abs)
    return {
        "declared_admitted": admitted,
        # Counted, never read — and cannot-determine stays distinct from zero.
        "repo_files": None if tracked is None else len(tracked),
        "outside_declaration": (None if outside is None else len(outside)),
        "outside_unavailable": unavailable,
        "examined": len(proposed),
        # NEGATIVE EVIDENCE. A term that matched nothing is a reportable
        # result: "searched for X, found nowhere" is what makes a thin harvest
        # visible as thin instead of simply quiet.
        "terms_without_match": sorted(t for t in terms if t not in matched_terms),
        "remainder_read": False,
    }


def build(root, terms, include):
    """The whole proposal plus its coverage-manifest disclosure."""
    files, reason = declared_files(root)
    proposed, binary = propose(root, files, terms) if files else ([], [])
    proposed_paths = {p["path"] for p in proposed}
    # Owner-requested files enter regardless of match and are MARKED as such:
    # free text wins over any proposal, and the manifest says which files the
    # terms chose and which the owner did.
    requested = [{"path": p, "terms": [], "hits": 0, "owner_requested": True}
                 for p in sorted(set(include or [])) if p not in proposed_paths]
    return {
        "kind": "harvest-scope",
        "root": root,
        "terms": terms,
        "declared_sources": len(files),
        "unavailable": reason,
        "proposed": proposed + requested,
        # STATED BEFORE ANY COVERAGE FIGURE (Story 20.110, #1104).
        "substrate": substrate(root, files, terms, proposed),
        # The manifest half: which repository contributed, and the standing
        # fact that nothing outside it was searched. An added repository would
        # appear here as an explicit entry, never as a silent widening.
        "manifest": {
            "repositories": [{"root": root, "declared_sources": len(files),
                              "searched": bool(files)}],
            "owner_requested": sorted(set(include or [])),
            "out_of_scope_searched": False,
            "binary_skipped": binary,
            "method": ("deterministic whole-word term match over the declared "
                       "sources; no ranking, no scoring, no retrieval index"),
        },
    }


def render(payload):
    lines = []
    # THE SUBSTRATE LEADS. A coverage number read without its denominator's
    # provenance is the defect #1104 reports, so the provenance is not
    # something the reader must go looking for further down.
    sub = payload.get("substrate")
    if sub:
        if sub["outside_declaration"] is None:
            outside = f"outside: cannot-determine ({sub['outside_unavailable']})"
        else:
            outside = (f"outside: {sub['outside_declaration']} file(s) in this "
                       f"repo are not declared — counted, never read")
        lines.append(f"substrate: {sub['declared_admitted']} declared file(s) "
                     f"admitted; {outside}")
        if sub["terms_without_match"]:
            lines.append(f"found-nowhere: {', '.join(sub['terms_without_match'])}")
        else:
            lines.append("found-nowhere: none — every derived term matched "
                         "at least one declared file")
    for t in payload["terms"]:
        lines.append(f"term: {t}")
    if payload["unavailable"]:
        lines.append(f"unavailable: {payload['unavailable']}")
    for p in payload["proposed"]:
        if p.get("owner_requested"):
            lines.append(f"scope: {p['path']} owner-requested")
        else:
            lines.append(f"scope: {p['path']} {p['hits']} "
                         f"{','.join(p['terms'])}")
    m = payload["manifest"]
    if m["binary_skipped"]:
        lines.append(f"skipped: {len(m['binary_skipped'])} binary declared "
                     f"source(s) — no terms to match: "
                     f"{', '.join(m['binary_skipped'][:3])}"
                     f"{' …' if len(m['binary_skipped']) > 3 else ''}")
    # A COVERAGE FIGURE CANNOT BE READ WITHOUT ITS DENOMINATOR: the examined
    # count and the unexamined remainder travel in the same statement.
    if sub:
        rem = ("unknown" if sub["outside_declaration"] is None
               else str(sub["outside_declaration"]))
        lines.append(f"manifest: {len(m['repositories'])} repository(ies), "
                     f"{sub['examined']} of {payload['declared_sources']} "
                     f"declared source(s) examined, {rem} outside the "
                     f"declaration unexamined, out-of-scope searched: "
                     f"{str(m['out_of_scope_searched']).lower()}")
    else:
        lines.append(f"manifest: {len(m['repositories'])} repository(ies), "
                     f"{payload['declared_sources']} declared source(s), "
                     f"out-of-scope searched: {str(m['out_of_scope_searched']).lower()}")
    return "\n".join(lines)


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Propose a harvest's file scope from a thesis's terms.")
    p.add_argument("--root", help="host-repo root (default: git top-level)")
    p.add_argument("--terms", action="append", required=True,
                   help="comma-separated terms (repeatable): a thesis's "
                        "Strand tags, slugs and gloss terms")
    p.add_argument("--include", action="append", default=[],
                   help="a file the owner names directly (repeatable). It "
                        "enters scope regardless of match and is disclosed "
                        "as owner-requested — free text wins.")
    p.add_argument("--json", action="store_true")
    args = p.parse_args(argv)
    root = host_root(args.root)
    terms = normalise_terms(args.terms)
    if not terms:
        sys.stderr.write("error: --terms resolved to no terms\n")
        return 2
    payload = build(root, terms, args.include)
    print(json.dumps(payload, indent=2, sort_keys=True) if args.json
          else render(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
