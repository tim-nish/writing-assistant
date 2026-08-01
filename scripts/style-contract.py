#!/usr/bin/env python3
"""The ONE versioned style contract — resolved and read AT GENERATION.

SPEC-writing-assistant, the 2026-08-01 (#1191) amendment; Story 20.139 (#1201),
umbrella #1191.

WHAT THIS IS. One owned, versioned contract that generation consumes, so the
styling decision is made once at ONBOARDING lifetime instead of being re-made
inside every article's production loop. A per-article style system is the
per-RUN choice SPEC-article-visuals already forbids; this is its opposite — a
contract that REMOVES the decision from the loop. There is exactly one such
artifact, and this file is its only reader.

WHERE IT LIVES, AND WHY THE PLUGIN NEVER WRITES IT. The artifact is authored
and edited BY THE OWNER, in the owner's articles repository — the `output.drafts`
destination, whose root is resolved here exactly as the other destination-aware
scripts resolve it (the parent of the declared drafts directory,
`resolve-writing-sources.py draft-location`, the single authority for that
value). Its clauses are prose a person writes, so it is a human-facing artifact
rather than machine state; and "one voice across every article" is a strategy
fact about the whole set, not a per-host-repo fact. Consequences, both binding:

  * the plugin's ONLY interaction with this artifact is a READ. There is no
    writer here, no setup-offers path, and no config-writer subcommand for it —
    `check-style-contract.sh` asserts the absence of a writer rather than
    trusting this paragraph;
  * when the artifact is ABSENT the reader SAYS SO and the run proceeds. It
    never creates one, and absence is exit 0, never an error.

THE SECTIONS SORT BY WHAT CAN CARRY THEM, AND THE SORT IS THE CONTENT:

  REGISTER          judgment  -> the Reviewer's ONE dimension (conformance to
                               the named clause, citing it) — never taste
  STRUCTURAL VOICE  judgment  -> the same one dimension
  LEXICON           mechanical-> the EXISTING coinage lint (the quality gate's
                               dim-3 first-use-gloss pass, #673). No new
                               instrument is introduced for it
  FIGURES           already ratified -> SPEC-article-visuals (visual identity +
                               the kind-typed fallback ladder). POINTER ONLY:
                               this contract never restates it
  SYNTAX PROFILE    NO INSTRUMENT, deliberately — see below

SYNTAX PROFILE CARRIES NO INSTRUMENT, AND THE REASON IS THE WHOLE POINT.
Sentence length, hedging density, person and voice are the only section a
machine can measure cheaply, which is exactly why the section will attract
enforcement. A distribution check is a PROXY FOR VOICE RATHER THAN VOICE: an
instrument that measures the measurable NEIGHBOUR of a property teaches
conformance to the neighbour. So this reader parses the section, carries its
clause to generation, and MEASURES NOTHING — it counts no sentence, computes no
density, and emits no score. A change that adds a syntax metric here, or
downstream of what this emits, has failed the contract, not implemented it.
The contract file's own `carrier:` line for that section must read `none`, and
a file declaring an instrument there is REFUSED (exit 4).

EXEMPLAR SLOTS ARE DECLARED AND EMPTY. The record format below declares the
slots and the KEY they are looked up by — the contract SECTION id, `register`
or `structural-voice`, the two judgment sections an accepted article can
demonstrate (the mechanical and already-ratified sections need no exemplar, and
the syntax profile gets none because its carrier is deliberately absent). They
ship EMPTY: zero accepted articles exist to pin, and the hub's own plain-register
renderings are the wrong register for this contract. An empty declared slot is
visible where an unstated intention is not — inventing an exemplar to fill one
is the failure this shape exists to prevent.

THE CORPUS-LEVEL DRIFT CHECK IS NOT BUILT — HELD, NOT DECLINED, AND RECORDED
HERE SO A FUTURE IMPLEMENTER FINDS IT AT THE ARTIFACT IT WOULD MEASURE.
"One author across 100 articles" is a corpus property INVISIBLE to per-article
review by construction, which is why the per-article Reviewer must not be asked
to carry it. It is held because the corpus is approximately zero published
articles, so the instrument could not run if it were built.
  ITS TRIGGER, NAMED NOW RATHER THAN INVENTED UNDER TIME PRESSURE LATER:
  THE OWNER READS TWO SHIPPED ARTICLES AS WRITTEN BY DIFFERENT PEOPLE.
Until that is observed, nothing corpus-level is built, and the absence is
declared rather than silent.

SUBCOMMANDS
  read [--root R | --repo P] [--json]
        Resolve, parse, and report the contract. Exit 0 present, 0 ABSENT
        (with the absence stated), 4 malformed (naming the defect), 2 when the
        destination itself cannot be resolved.
  path [--root R | --repo P]
        Print the resolved artifact path and exit.
  format
        Print the CANONICAL record format — the template an owner authors from.
        It is emitted here and restated nowhere: an enumeration restated in a
        second place goes stale silently (#1193), so skills point at this
        command instead of copying the shape.

Stdlib only, like every sibling script; host repos guarantee no venv.
"""

import argparse
import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SRC_RES = os.path.join(SCRIPT_DIR, "resolve-writing-sources.py")

ARTIFACT = "style-contract.md"
VERSION_KEY = "style_contract_version"

# The five contract sections, in their declared order, each with the carrier
# that may enforce it. This dict is the single declaration of the section set.
CARRIERS = {
    "REGISTER": "judgment",
    "STRUCTURAL VOICE": "judgment",
    "LEXICON": "mechanical",
    "FIGURES": "ratified-elsewhere",
    "SYNTAX PROFILE": "none",
}
# Exemplar slots are keyed by contract section id — the two JUDGMENT sections.
EXEMPLAR_KEY = "section-id"
EXEMPLAR_SLOTS = ("register", "structural-voice")

EXIT_OK = 0
EXIT_NO_DESTINATION = 2
EXIT_MALFORMED = 4

TEMPLATE = """---
{version_key}: 1
---

# Style contract

<!-- OWNER-AUTHORED, and read-only to the writing-assistant plugin: it reads
     this file at generation and never writes, creates, or migrates it.
     One artifact, one version field, onboarding lifetime. -->

## REGISTER

carrier: judgment — the Reviewer's one dimension (conformance to this clause,
citing it), never taste.

<!-- Owner-authored: the assumed reader background. -->

## STRUCTURAL VOICE

carrier: judgment — the Reviewer's one dimension (conformance to this clause,
citing it), never taste.

<!-- Owner-authored: e.g. claim-first paragraphs so skimming survives; the
     concrete-failure -> generalized-property -> validity-conditions pattern. -->

## LEXICON

carrier: mechanical — the existing coinage lint (the quality gate's dim-3
first-use-gloss pass). No new instrument.

<!-- Owner-authored: coin-with-definition. -->

## FIGURES

carrier: ratified-elsewhere — SPEC-article-visuals (the visual identity plus
the kind-typed fallback ladder). Pointer only; never restated here.

## SYNTAX PROFILE

carrier: none — deliberately. Sentence length, hedging density, person and
voice are the only section a machine can measure cheaply, which is exactly why
this section attracts enforcement; a distribution check is a proxy for voice
rather than voice, and an instrument that measures the measurable neighbour of
a property teaches conformance to the neighbour. Adding a metric here has
failed this contract, not implemented it.

<!-- Owner-authored: read at generation, measured by nothing. -->

## EXEMPLARS

lookup key: {exemplar_key} — one slot per judgment section.
record: <section-id>: <article path in this repo>#<heading or line span> — <one
line on what it exemplifies>

The slots are DECLARED AND EMPTY: no accepted articles exist to pin yet, and
renderings written in a plain register are the wrong register for this
contract. Leave a slot empty until a real accepted article can fill it —
inventing one defeats the point of declaring the slot.

{slot_lines}
"""


def render_template():
    slots = "\n".join(f"{s}:" for s in EXEMPLAR_SLOTS)
    return TEMPLATE.format(version_key=VERSION_KEY, exemplar_key=EXEMPLAR_KEY,
                           slot_lines=slots)


# --------------------------------------------------------------------------
# Resolution — the destination comes from the resolver, never composed here.


def destination_repo(root, repo_override=None):
    """The owner's articles repo: an explicit --repo (tests, non-default
    locations) else the parent of the declared `output.drafts` directory, which
    resolve-writing-sources.py owns. None when undeclared or unreachable — a
    disclosed refusal, never a silent fallback."""
    if repo_override:
        return os.path.realpath(repo_override)
    cmd = [sys.executable, SRC_RES]
    if root:
        cmd += ["--root", root]
    cmd += ["draft-location"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return os.path.dirname(os.path.realpath(r.stdout.strip()))


def artifact_path(root, repo_override=None):
    repo = destination_repo(root, repo_override)
    return os.path.join(repo, ARTIFACT) if repo else None


# --------------------------------------------------------------------------
# Parsing — read-only, and it measures nothing.


def _version(text):
    m = re.match(r"^---\s*\n(.*?)\n---\s*$", text, re.S | re.M)
    if not m:
        return None
    v = re.search(rf"^{VERSION_KEY}:\s*(\S+)\s*$", m.group(1), re.M)
    return v.group(1) if v else None


def _sections(text):
    """{HEADING: body} for every `## ` heading, in file order."""
    out = {}
    heading, body = None, []
    for ln in text.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", ln)
        if m:
            if heading is not None:
                out[heading] = "\n".join(body).strip()
            heading, body = m.group(1).strip(), []
        elif heading is not None:
            body.append(ln)
    if heading is not None:
        out[heading] = "\n".join(body).strip()
    return out


def _split_carrier(body):
    """(carrier, clause). The carrier is the `carrier:` PARAGRAPH — it may wrap
    over several lines, and ends at the first blank line. The clause is
    everything else, comments removed: the owner's authored text, carried to
    generation verbatim and never scored."""
    para, rest, seen = [], [], False
    for block in re.split(r"\n\s*\n", body):
        if not seen and block.lstrip().startswith("carrier:"):
            para = [block.strip()]
            seen = True
        else:
            rest.append(block)
    carrier = None
    if para:
        carrier = " ".join(para[0][len("carrier:"):].split())
    clause = re.sub(r"<!--.*?-->", "", "\n\n".join(rest), flags=re.S)
    return (carrier or None), clause.strip()


def _exemplars(body):
    """The declared slots and the key they are looked up by. A slot with no
    value is EMPTY — which is the shipped state, and is not a defect."""
    key = None
    m = re.search(r"^lookup key:\s*(\S+)", body or "", re.M)
    if m:
        key = m.group(1)
    slots = {}
    for slot in EXEMPLAR_SLOTS:
        entries = []
        for ln in (body or "").splitlines():
            sm = re.match(rf"^{re.escape(slot)}:\s*(.*?)\s*$", ln)
            if sm and sm.group(1):
                entries.append(sm.group(1))
        slots[slot] = entries
    return {"lookup_key": key, "slots": slots}


def parse(text, path):
    """(payload, defects). A defect list is a refusal, not a warning: a
    malformed contract is fixed by its owner, never silently half-applied."""
    defects = []
    version = _version(text)
    if not version:
        defects.append(
            f"no `{VERSION_KEY}:` field in the frontmatter — the contract is "
            "versioned, and an unversioned file cannot be one")
    found = _sections(text)
    sections = {}
    for name, expected in CARRIERS.items():
        if name not in found:
            defects.append(f"section `## {name}` is missing")
            continue
        body = found[name]
        carrier, clause = _split_carrier(body)
        if not carrier:
            defects.append(
                f"section `## {name}` declares no `carrier:` line — every "
                "section names what can carry it")
        elif not carrier.lower().startswith(expected):
            defects.append(
                f"section `## {name}` declares carrier `{carrier}` — this "
                f"section's carrier is `{expected}`")
        sections[name] = {
            "carrier": carrier,
            "carrier_kind": expected,
            "clause": clause,
            "authored": bool(clause),
        }
    if "EXEMPLARS" not in found:
        defects.append("section `## EXEMPLARS` is missing — the slots are "
                       "declared even while empty")
    exemplars = _exemplars(found.get("EXEMPLARS"))
    if "EXEMPLARS" in found and not exemplars["lookup_key"]:
        defects.append("`## EXEMPLARS` declares no `lookup key:` — a slot with "
                       "no stated key cannot be looked up")
    return {
        "status": "present",
        "path": path,
        "version": version,
        "sections": sections,
        "exemplars": exemplars,
        # Stated in the payload so a consumer never has to infer it: this
        # reader emits no measurement of any section, and the syntax profile
        # has no instrument by contract.
        "measured": [],
        "uninstrumented_by_contract": ["SYNTAX PROFILE"],
    }, defects


def absent_payload(path):
    return {"status": "absent", "path": path, "version": None,
            "sections": {}, "exemplars": {"lookup_key": EXEMPLAR_KEY,
                                          "slots": {s: [] for s in EXEMPLAR_SLOTS}},
            "measured": [], "uninstrumented_by_contract": ["SYNTAX PROFILE"]}


ABSENT_LINE = (
    "no style contract at {path} — generation proceeds WITHOUT one, and the "
    "plugin does not create it: the contract is owner-authored and read-only "
    "here. To adopt one, author that file (`style-contract.py format` prints "
    "the record format).")


# --------------------------------------------------------------------------


def _render(payload):
    lines = [f"style contract: {payload['path']}",
             f"version: {payload['version']}"]
    for name in CARRIERS:
        sec = payload["sections"].get(name, {})
        state = "authored" if sec.get("authored") else "NOT YET AUTHORED (owner's work)"
        lines.append(f"\n## {name} — carrier: {sec.get('carrier')} [{state}]")
        if sec.get("clause"):
            lines.append(sec["clause"])
    ex = payload["exemplars"]
    lines.append(f"\n## EXEMPLARS — looked up by {ex['lookup_key']}")
    for slot, entries in ex["slots"].items():
        lines.append(f"  {slot}: " + (", ".join(entries) if entries else "(empty)"))
    lines.append("\nMeasured by this reader: nothing. The syntax profile carries "
                 "no instrument by contract.")
    return "\n".join(lines)


def cmd_read(args):
    path = artifact_path(args.root, args.repo)
    if not path:
        sys.stderr.write(
            "error: cannot resolve the drafts destination — pass --repo "
            "<articles-repo>, or declare output.drafts for the host repo "
            "(resolve-writing-sources.py set-draft-location)\n")
        return EXIT_NO_DESTINATION
    if not os.path.isfile(path):
        line = ABSENT_LINE.format(path=path)
        if args.json:
            print(json.dumps(absent_payload(path), indent=2))
        else:
            print(line)
        sys.stderr.write(line + "\n")
        return EXIT_OK
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    payload, defects = parse(text, path)
    if defects:
        payload["status"] = "malformed"
        payload["defects"] = defects
        if args.json:
            print(json.dumps(payload, indent=2))
        for d in defects:
            sys.stderr.write(f"style contract at {path}: {d}\n")
        sys.stderr.write("the contract is not applied until its owner fixes "
                         "the above; `style-contract.py format` prints the "
                         "record format\n")
        return EXIT_MALFORMED
    print(json.dumps(payload, indent=2) if args.json else _render(payload))
    return EXIT_OK


def cmd_path(args):
    path = artifact_path(args.root, args.repo)
    if not path:
        sys.stderr.write("error: cannot resolve the drafts destination\n")
        return EXIT_NO_DESTINATION
    print(path)
    return EXIT_OK


def cmd_format(_args):
    sys.stdout.write(render_template())
    return EXIT_OK


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="style-contract.py",
        description="Read the owner's ONE versioned style contract at generation.")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("read", "path"):
        sp = sub.add_parser(name)
        sp.add_argument("--root", help="host repo root (default: cwd's git top-level)")
        sp.add_argument("--repo", help="articles repo root (bypasses resolution)")
        if name == "read":
            sp.add_argument("--json", action="store_true")
    sub.add_parser("format")
    args = p.parse_args(argv)
    return {"read": cmd_read, "path": cmd_path, "format": cmd_format}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
