#!/usr/bin/env python3
"""terrain_seam — the policy-seam I/O layer (Story 20.40, #903).

Extracted from `terrain_map.py` per the packaging invariant's scripts-family
clause (`specs/spec-writing-assistant/SPEC.md`, amended 2026-07-29, #900). Of
the four concerns that file interleaved, this is the one with an **external**
boundary: its contract is owned by another repository, reached only through
the shipped reader (`read-policy-source.py`). That is why it goes first.

**What lives here: invocation and the ENVELOPE. What does not: interpretation
of the lines inside it.** Every reader in the old file re-implemented the same
envelope — `pin:`, `miss:`, `=== <path> @ <sha>`, then `<n>: <text>` — and then
went on to interpret those lines its own way. The duplication was the seam
showing through in five places, so the envelope is parsed once here and each
caller keeps its own line interpretation.

**The degradation rules concentrate here, deliberately.** An undeclared policy
source, an unreachable gateway, a tool surface too old to register the call
(the named exit-13 gap), a served miss, and a served path that differs from the
requested one are all *seam* facts. Isolating them is what makes those paths
testable without the axis model around them — and a fallback that goes silent
is the failure this layer exists to make impossible, so every degraded return
carries a reason rather than an empty result.

There is exactly ONE path to the policy source, and it is `run_reader` below.
A second invocation anywhere is the defect this module exists to prevent.
"""

import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
POLICY_READER = os.path.join(SCRIPT_DIR, "read-policy-source.py")


def host_root(arg_root):
    """--root or the git toplevel of cwd, realpath'd. Keep in sync with the
    identical helper in resolve-paths.py / resolve-user-config.py /
    resolve-writing-sources.py / resolve-platform-profiles.py."""
    if arg_root:
        return os.path.realpath(arg_root)
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.stderr.write("error: not inside a git repository (pass --root)\n")
        raise SystemExit(2)
    return os.path.realpath(r.stdout.strip())


def run_reader(root, args):
    """Invoke the shipped seam reader. The ONLY path to the policy source.

    Returns the completed process; callers decide what a non-zero exit means
    for their family, because the disclosure wording is the family's own.
    """
    cmd = [sys.executable, POLICY_READER]
    if root:
        cmd += ["--root", root]
    return subprocess.run(cmd + list(args), capture_output=True, text=True)


def failure_reason(r):
    """Why a non-zero reader exit happened, in the wording every family uses.

    The reader's own last stderr line when it wrote one — it names the
    condition better than an exit code can — and the exit code otherwise, so
    a silent failure still produces a disclosable reason.
    """
    detail = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
              else f"the policy reader exited {r.returncode}")
    return f"{detail} (read-policy-source.py exit {r.returncode})"


def read_served(root, args):
    """One seam read, with its envelope parsed and nothing else interpreted.

    Returns a dict:
      `reason`   — set when the read could not happen at all (the family is
                   declared-but-not-enumerated and this names why); the other
                   fields are then empty.
      `pin`      — the served pin, or None when the seam reported none.
      `misses`   — served misses, verbatim. A miss is a served ANSWER under
                   the pin (an empty or ungranted surface), which is a
                   different fact from unavailability, so it is never folded
                   into `reason`.
      `sections` — `[{path, sha, lines: [(number, text)]}]` in served order.

    `path` is the path the seam ACTUALLY SERVED, never one recomposed from
    what was asked for. Recomposing it is what once let an archive be
    displayed as the live record with nothing reporting it.
    """
    r = run_reader(root, args)
    if r.returncode != 0:
        return {"reason": failure_reason(r), "pin": None,
                "misses": [], "sections": []}
    pin, misses, sections = None, [], []
    current = None
    for line in r.stdout.splitlines():
        if line.startswith("pin: "):
            pin = line[5:].strip()
            continue
        if line.startswith("miss: "):
            misses.append(line[6:].strip())
            continue
        if line.startswith("=== "):
            head = line[4:]
            path, _sep, sha = head.rpartition(" @ ")
            current = {"path": path.strip(), "sha": sha.strip(), "lines": []}
            sections.append(current)
            continue
        if current is None:
            continue
        number, _sep, text = line.partition(": ")
        if number.strip().isdigit():
            current["lines"].append((number.strip(), text))
    return {"reason": None, "pin": pin, "misses": misses, "sections": sections}


def substitution(requested, served_path):
    """A served path that differs from the one requested — or None.

    An abnormal condition, not a gap: nothing is missing, the wrong thing
    arrives and reads as the right one, so no absence is felt and no other
    check fires. Detection is the CONSUMER's own and is never conditional on
    an upstream fix having landed, because the failure this catches is
    precisely the one where the fix is believed to have landed and has not.
    """
    if served_path and requested and served_path != requested:
        return {"requested": requested, "served": served_path}
    return None


def hub_pin(root):
    """The hub state this run actually read, as a bare sha.

    The seam prints `<hub>@<sha>`; only the sha is kept. The hub's NAME is a
    publication-boundary value (`CLAUDE.md` §"Claims about the served
    surface"), so it is never carried into an artifact this tool writes, not
    even an untracked one — the cheapest place to not leak a name is to never
    store it.

    Returns `None` when the seam cannot report one: an unknown hub state is
    disclosed, never defaulted to the destination's sha, because a pin that
    silently means the other repository is the defect this whole capability
    exists to fix.
    """
    r = run_reader(root, ["pin"])
    if r.returncode != 0 or not r.stdout.strip():
        return None
    _name, _sep, sha = r.stdout.strip().partition("@")
    return (sha or None) if _sep else None


def elements_read(root):
    """The served element manifest as structured records (the seam's
    `elements` subcommand — the gateway's `element_survey`).

    Returns `(records, reason)`. Each record is the manifest's JSON object
    verbatim plus the served line's `cite` (`file:line@commit`). A `reason`
    means record acquisition is unavailable (the named exit-13 gap, a served
    miss, an unreachable gateway) and names why; the caller then falls back
    WITH the substitution disclosed, never silently.

    Decoding JSON here is not the interpretation this module excludes: the
    manifest is served AS data by the tool's own contract, so there is no
    markdown to re-derive — which is the whole reason this acquisition path
    exists.
    """
    served = read_served(root, ["elements"])
    if served["reason"]:
        return [], served["reason"]
    if served["misses"]:
        return [], "the policy source served a miss for the element manifest"
    records = []
    for section in served["sections"]:
        for number, text in section["lines"]:
            try:
                record = json.loads(text)
            except ValueError:
                # The manifest contract says every line is a record;
                # conformance is guarded at the hub's generation, never
                # re-derived here.
                continue
            if not isinstance(record, dict) or not record.get("slug"):
                continue
            record["cite"] = f"{section['path']}:{number}@{section['sha']}"
            records.append(record)
    if not records:
        return [], "the served element manifest carries no records"
    return records, None
