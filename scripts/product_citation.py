#!/usr/bin/env python3
"""Reader-facing COMMIT citations for emitted products — constructed
repo-qualified from the examination record (Story 20.195, #1339;
SPEC-writing-assistant amendment 2026-08-03).

The shipped canonical cited `commit 556ab1b` beside GitHub references that
carried full URLs. For the declared audience — an external reader with no
portfolio context — a bare sha resolves to nothing: no repository is named,
and an article mentions several.

WHAT THIS MODULE IS. The CONSTRUCT side of the standing remedy shape (owner
decision record — 2026-07-28 (constrain generation, not post-hoc detection)).
An examination record already carries `pin: <repo>@<sha>` AT THE READ THAT
PRODUCED IT (`examine.py`), so the repository qualifier is IN HAND at the
point of writing: nothing here infers a repository, consults a remote, or
re-derives anything from git. A bare, repo-unqualified sha is therefore
UNCONSTRUCTIBLE — `citation()` refuses a pin that carries no qualifier rather
than emitting half a pointer.

THE SCAN IS THE BACKSTOP, NOT THE MECHANISM. `bare_commit_citations()` reads a
product's text so a HAND-AUTHORED product cannot re-open the hole at the
`complete` write layer. On pipeline output it is expected never to fire.

SCOPE, stated so it is not read wider (the amendment's own words): this
governs COMMIT references in emitted PRODUCTS. Issue and URL references
already resolve and are untouched. `path:line@sha` pins in THIS repository's
own body text stay with `check-citation-form.sh` — this module never becomes a
second authority over them, which is why ANY `<qualifier>@<sha>` reads as
qualified here. The publication boundary is unaffected: what is constructed is
a repo-qualified sha of a PUBLIC repository, and the prohibition on the policy
hub's name and shas is unchanged.

CLI:
  render   --pin <repo>@<sha> [--form token|prose]   one citation
  cite-map --ws <workspace> [--json]                 bare cite -> citation,
                                                     derived from the run's
                                                     examination records
  scan     <file> ...                                the backstop, over text
"""

import argparse
import json
import os
import re
import sys

# A short sha as this repository's tooling writes one: git's abbreviation, 7
# hex minimum, never longer than a full object name. Shape only — resolution
# is not this module's business (the record was written by the read).
_SHA = r"[0-9a-f]{7,40}"
# The qualifier is whatever stands left of `@` in the record's pin: a repo
# basename (`writing-assistant`) or this repo's own `path:line` pin head.
_PIN_RE = re.compile(r"^(?P<qual>[A-Za-z0-9][A-Za-z0-9._/:\-]*)@(?P<sha>" + _SHA + r")$")
_SHA_TOKEN_RE = re.compile(r"(?<![0-9a-zA-Z@/])(" + _SHA + r")(?![0-9a-zA-Z])")
_FENCE_RE = re.compile(r"^\s{0,3}(```|~~~)")


class UnqualifiedPin(ValueError):
    """A pin with no repository qualifier — the citation is unconstructible."""


def parse_pin(pin):
    """`<repo>@<sha>` -> (repo, sha). Anything else is unconstructible.

    A bare sha lands here as the empty-qualifier case and is REFUSED: the
    caller may not fall back to emitting it, because the fallback is the
    defect (`commit 556ab1b`).
    """
    text = (pin or "").strip().strip("`")
    m = _PIN_RE.match(text)
    if not m:
        raise UnqualifiedPin(
            f"cannot construct a reader-facing commit citation from {pin!r} — "
            "a product citation is rendered from the examination record's "
            "`pin` (<repo>@<sha>), and a bare repo-unqualified sha is not "
            "composable (SPEC-writing-assistant, amendment 2026-08-03, #1339)")
    return m.group("qual"), m.group("sha")


def citation(pin, form="token"):
    """The reader-facing citation for a commit-grounded claim.

    `token` — `repo@sha`, the pointer itself, for a Pointers-section line or a
    parenthetical. `prose` — "commit `repo@sha` in repo", for a sentence that
    already says the word commit. Both are repo-qualified; there is no third
    form that is not.
    """
    repo, sha = parse_pin(pin)
    if form == "prose":
        return f"commit `{repo}@{sha}` in `{repo}`"
    return f"{repo}@{sha}"


def record_citations(record):
    """Every commit citation a single examination record can ground.

    Keyed by the record's own `cite` (the bare sha the derived pin ledger
    carries) so a drafter holding a ledger line can look up what to WRITE.
    Non-commit evidence is passed over untouched: issue and URL references
    already resolve.
    """
    out = {}
    for ev in (record or {}).get("evidence", []) or []:
        if ev.get("source_type") != "commit":
            continue
        pin = ev.get("pin")
        if not pin:
            continue
        try:
            text = citation(pin)
        except UnqualifiedPin:
            continue
        for key in (ev.get("cite"), ev.get("ref"), pin):
            if key:
                out[str(key)] = text
    return out


def cite_map(ws):
    """bare cite -> reader-facing citation, over a run's examination records.

    Reads `$WS/examinations/*.json` directly: the records are the authority
    the amendment names, and the derived ledger (`examination-pins.txt`) is
    exactly the surface that carries the bare form.
    """
    exdir = os.path.join(ws, "examinations")
    mapping = {}
    for name in sorted(os.listdir(exdir)) if os.path.isdir(exdir) else []:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(exdir, name), encoding="utf-8") as fh:
                mapping.update(record_citations(json.load(fh)))
        except (OSError, ValueError):
            continue
    return mapping


def bare_commit_citations(text):
    """THE BACKSTOP. Repo-unqualified commit references in a product's text.

    Returns [(line_no, line_text, token)]. Admitted, deliberately narrowly:

      * `<qualifier>@<sha>` — qualified (and the `path:line@sha` pin form, so
        this never becomes a second authority over it);
      * a sha inside a URL — a full commit URL already names its repository;
      * a fenced code block — a literal being SHOWN, the exemption
        `check-citation-form.sh` already carries for the same reason;
      * hex that is not sha-shaped — pure digits are a number, and an
        all-letter hex word ("effaced") is a word.
    """
    findings = []
    fenced = False
    for i, line in enumerate(text.splitlines(), start=1):
        if _FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        for m in _SHA_TOKEN_RE.finditer(line):
            tok = m.group(1)
            if not (any(c.isdigit() for c in tok) and any(c.isalpha() for c in tok)):
                continue
            run = _enclosing_run(line, m.start())
            if "://" in run:
                continue
            findings.append((i, line.strip(), tok))
    return findings


def _enclosing_run(line, pos):
    start = line.rfind(" ", 0, pos) + 1
    end = line.find(" ", pos)
    return line[start:] if end < 0 else line[start:end]


def refusal(findings):
    """The `complete` write layer's refusal text — it NAMES the citation."""
    named = "; ".join(f"line {n}: `{tok}`" for n, _, tok in findings)
    return ("the product carries repo-unqualified commit reference(s) — "
            + named
            + ". A reader-facing commit citation is constructed from the "
            "examination record's `pin` (<repo>@<sha>) — see "
            "`scripts/product_citation.py render --pin <repo>@<sha>`; a bare "
            "sha names no repository and resolves to nothing for an external "
            "reader (SPEC-writing-assistant, amendment 2026-08-03, #1339)")


def complete_refusal(text):
    """One call, one return value, for the `complete` gate's call site: the
    refusal reason, or None when the product is clean."""
    findings = bare_commit_citations(text)
    return refusal(findings) if findings else None


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("render", help="one reader-facing citation from a pin")
    r.add_argument("--pin", required=True, help="the examination record's pin, <repo>@<sha>")
    r.add_argument("--form", choices=["token", "prose"], default="token")

    c = sub.add_parser("cite-map", help="bare cite -> citation, from a run's records")
    c.add_argument("--ws", required=True, help="the run workspace holding examinations/")
    c.add_argument("--json", action="store_true")

    s = sub.add_parser("scan", help="the backstop: bare commit references in a product")
    s.add_argument("paths", nargs="+")

    args = p.parse_args(argv)

    if args.cmd == "render":
        try:
            print(citation(args.pin, args.form))
        except UnqualifiedPin as e:
            sys.stderr.write(f"error: {e}\n")
            return 2
        return 0

    if args.cmd == "cite-map":
        mapping = cite_map(args.ws)
        if args.json:
            print(json.dumps(mapping, indent=2, sort_keys=True))
        else:
            for k in sorted(mapping):
                print(f"{k}\t{mapping[k]}")
        return 0

    rc = 0
    for path in args.paths:
        with open(path, encoding="utf-8") as fh:
            found = bare_commit_citations(fh.read())
        if found:
            rc = 1
            for n, _, tok in found:
                sys.stderr.write(f"FAIL: {path}:{n} bare commit reference {tok}\n")
            sys.stderr.write(f"error: {path}: {refusal(found)}\n")
        else:
            print(f"ok:   {path} — no repo-unqualified commit reference")
    return rc


if __name__ == "__main__":
    sys.exit(main())
