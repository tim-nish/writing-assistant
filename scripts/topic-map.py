#!/usr/bin/env python3
"""topic-map.py — the topic map as a DERIVED, READ-ONLY view (Story 18.61, #585;
SPEC-topic-map CAP-1 + CAP-4).

The topic map is an overview of what the owner *could* write about, assembled
**at every invocation** from state that already exists. This script implements
exactly two capabilities:

  CAP-1  derived view, never stored state
  CAP-4  bounded assembly (index/frontmatter surfaces only, with disclosure)

CAP-2 (subtopic clusters, evidence-density and depth signals) and CAP-3
(in-conversation presentation, candidate directions, the brief hand-off) are
**not** implemented here — they belong to sibling stories. This script prints
JSON; it composes no owner-facing screen and no narrative structures (18.45's
single-proposer invariant).

CAP-1 — derived, never stored
-----------------------------
Every field of the output is recomputed from authoritative state on each run:

  * the **articles repo** — `backlog/`, `drafts/`, `newsletter/`, `graveyard/`
    item frontmatter and `INDEX.md`, reached through the declared
    `output.drafts` location (`resolve-writing-sources.py draft-location`), so
    no caller composes a storage path;
  * the **track↔topic mapping** — `policy_source.track_topics` in the host
    repo's `writing-sources.yaml`, read through
    `resolve-writing-sources.py policy-source` (#525). The articles repo owns
    track names, the hub owns topic names, the mapping is consumer config.
  * the **Lesson-consumption derived view** — READ, never re-implemented, from
    `write-article-plan.py consult` (`consumed_index` /
    `project_consumed_index`), which is the shipped instantiation of the
    SPEC-article-draft-pipeline CAP-9 predicate as amended by #556
    (consumed iff a live backlog/draft/published item cites it OR an
    ever-published item cites it — a selection-time derived view, never a
    stored flag). This script neither widens that join nor caches its answer.

**No map file is ever written for later reuse, and nothing this script writes
is ever read back as an input.** `--emit-debug PATH` exists only so a run's
output can be eyeballed after the fact; there is no subcommand, flag, or code
path that reads such a file (grep-asserted by `check-topic-map.sh`). Deleting a
run workspace loses nothing.

**OQ1 (subtopic clustering authority) — resolved as pure-derived.** Whatever
grouping this map shows is computed per invocation from item frontmatter that
already exists. No backlog frontmatter key is required, defined, or read for
clustering purposes, so the articles repo gains **no schema obligation** from
this story. Promotion to a recorded vocabulary stays available if clusters are
later observed to be unstable.

CAP-4 — bounded assembly
------------------------
Only **index and frontmatter surfaces** are read: `INDEX.md` and the leading
`---` frontmatter block of each item file. `read_frontmatter` stops at the
closing `---` and never touches the body, so assembly cost scales with index
size, not corpus body size — a repo of 50 huge articles costs the same as 50
stubs. There is an explicit read bound (`--max-surfaces`, default 400).

When the bound truncates, the map **names the surfaces it did not read** rather
than narrowing silently, in the coverage-disclosure shape harvest already uses
(`skills/harvest/SKILL.md` output contract, `validate-fact-sheet.py`
`validate_coverage`): a `pin`, a `matched` count, a `read` list with per-surface
entry counts, and a `skipped` list of `(surface, reason)` — with the same closed
accounting `#read + #skipped == matched`.

Stdlib-only (host repos guarantee no venv).

Subcommands (each takes --root / --repo and --max-surfaces):
  assemble    the whole map as one JSON object (topics, items, coverage,
              consumption view)
  surfaces    the surfaces this invocation would read, one path per line,
              in read order (the bound applied)
  coverage    the coverage manifest alone, as JSON

Exit codes: 0 ok · 2 not in a git repo · 3 no articles repo resolvable.
"""

import argparse
import importlib.util
import json
import os
import subprocess
import sys

NO_ARTICLES_REPO = 3

# Item directories, in a fixed read order (determinism). `graveyard/` is read
# because the never-delete convention makes it load-bearing for the consumption
# predicate (#556): a graveyarded item is not live, but an ever-published one
# keeps its citations consumed. Items there are reported with live=false.
SECTIONS = ("backlog", "drafts", "newsletter", "graveyard")
LIVE_SECTIONS = ("backlog", "drafts", "newsletter")

DEFAULT_MAX_SURFACES = 400


def _load(mod_filename):
    """Load a sibling script as a module (the resolve-*.py idiom)."""
    here = os.path.dirname(os.path.realpath(__file__))
    name = mod_filename.replace(".py", "").replace("-", "_")
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(here, mod_filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SRC_RES = os.path.join(SCRIPT_DIR, "resolve-writing-sources.py")
PLAN_WRITER = os.path.join(SCRIPT_DIR, "write-article-plan.py")


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


# --------------------------------------------------------------------------
# Resolution — every location comes from a resolver, never composed here.


def articles_repo(root, repo_override=None):
    """The articles repo root: an explicit --repo (tests / non-default
    locations) else the parent of the declared `output.drafts` directory, which
    resolve-writing-sources.py owns. Returns None when undeclared/unreachable —
    an undeclared location is a disclosed refusal, never a silent fallback."""
    if repo_override:
        return os.path.realpath(repo_override)
    cmd = [sys.executable, SRC_RES]
    if root:
        cmd += ["--root", root]
    cmd += ["draft-location"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    drafts = os.path.realpath(r.stdout.strip())
    return os.path.dirname(drafts)


def track_topics(root):
    """The `policy_source.track_topics` mapping (#525) as {track: [topic,...]},
    or {} when undeclared/unreadable. Absence is not an error — an unmapped
    repo still has tracks, and the map says so rather than inventing topics."""
    cmd = [sys.executable, SRC_RES]
    if root:
        cmd += ["--root", root]
    cmd += ["policy-source"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return {}
    try:
        data = json.loads(r.stdout)
    except ValueError:
        return {}
    mapping = data.get("track_topics") or {}
    return {k: (v if isinstance(v, list) else [v]) for k, v in mapping.items()}


def consumption_view(root):
    """The Lesson-consumption derived view, READ from its one shipped
    implementation — `write-article-plan.py consult` — never re-derived and
    never cached here.

    That command regenerates `consumed_index` / `project_consumed_index` over
    `plans/*.md` on every call; per SPEC-article-draft-pipeline CAP-9 as amended
    by #556 it is the current instantiation of the consumption predicate (only
    its join widens when the articles repo gains a Lesson-citation key). If it
    cannot answer, that is disclosed as `available: false` with the reason —
    the map never substitutes a second copy of the rule.
    """
    # `consult` takes --root after the subcommand (see write-article-plan.py).
    cmd = [sys.executable, PLAN_WRITER, "consult"]
    if root:
        cmd += ["--root", root]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return {"available": False,
                "source": "write-article-plan.py consult",
                "reason": (r.stderr.strip().split("\n")[-1]
                           if r.stderr.strip() else
                           "consult produced no output")}
    try:
        data = json.loads(r.stdout)
    except ValueError:
        return {"available": False,
                "source": "write-article-plan.py consult",
                "reason": "consult output was not JSON"}
    return {"available": True,
            "source": "write-article-plan.py consult",
            "derived_not_stored": True,
            "project": data.get("project"),
            "scanned": data.get("scanned"),
            "consumed_index": data.get("consumed_index") or {},
            "project_consumed_index": data.get("project_consumed_index") or {},
            "degraded": data.get("degraded")}


def repo_pin(repo):
    """The articles repo's HEAD sha, or "unpinned" outside git — the coverage
    manifest's `pin`, exactly as harvest discloses one."""
    r = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"],
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    return "unpinned"


# --------------------------------------------------------------------------
# Bounded reading (CAP-4)


def read_frontmatter(path):
    """The leading `---` frontmatter block of an item file as {key: value}.

    **This is the CAP-4 read bound in the small.** The reader stops at the
    closing `---` and returns; the body is never consumed, so a 40k-word
    article and a one-line stub cost the same. Scalars, inline lists
    (`[a, b]`), and `- item` block lists are understood — everything the map
    projects; anything else is skipped rather than half-parsed.
    """
    out = {}
    try:
        with open(path, encoding="utf-8") as fh:
            first = fh.readline()
            if first.strip() != "---":
                return out
            key = None
            for line in fh:
                s = line.rstrip("\n")
                if s.strip() == "---":
                    break                       # <- frontmatter ends here
                if not s.strip() or s.lstrip().startswith("#"):
                    continue
                stripped = s.lstrip()
                if stripped.startswith("- "):
                    if key is not None:         # a block-list continuation
                        item = stripped[2:].strip().strip('"').strip("'")
                        if item:
                            out.setdefault(key, [])
                            if isinstance(out[key], list):
                                out[key].append(item)
                    continue
                if s[0] in " \t":
                    continue                    # nested map / continuation
                if ":" not in s:
                    continue
                k, _, val = s.partition(":")
                key = k.strip()
                val = val.split("   #")[0].strip()
                if val in (">", "|"):
                    out[key] = ""               # block scalar: not projected
                    key = None
                    continue
                if val.startswith("[") and val.endswith("]"):
                    items = [x.strip().strip('"').strip("'")
                             for x in val[1:-1].split(",")]
                    out[key] = [x for x in items if x]
                    key = None
                    continue
                if val:
                    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                        val = val[1:-1]
                    out[key] = val
                    key = None
                else:
                    out[key] = []               # awaits a `- item` block list
    except OSError:
        return out
    return out


def index_entry_count(path):
    """How many item lines an INDEX file lists. Index surfaces are read as
    indexes — line shapes only, never followed into the items they name."""
    n = 0
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("- "):
                    n += 1
    except OSError:
        return 0
    return n


def candidate_surfaces(repo):
    """Every index/frontmatter surface this map may read, in a deterministic
    read order: INDEX files first, then item files by section and name. This is
    the `matched` set of the coverage manifest — the bound is applied to it,
    never to a silently pre-narrowed list."""
    surfaces = []
    for name in ("INDEX.md",):
        p = os.path.join(repo, name)
        if os.path.isfile(p):
            surfaces.append(("index", name, p))
    for section in SECTIONS:
        d = os.path.join(repo, section)
        if not os.path.isdir(d):
            continue
        try:
            names = sorted(os.listdir(d))
        except OSError:                          # pragma: no cover - defensive
            continue
        for name in names:
            if not name.endswith(".md") or name.startswith("."):
                continue
            surfaces.append((section, f"{section}/{name}",
                             os.path.join(d, name)))
    return surfaces


def _as_list(val):
    if val is None or val == "":
        return []
    if isinstance(val, list):
        return [v for v in val if v]
    return [str(val)]


def assemble(repo, mapping, max_surfaces):
    """Assemble the map. Returns (topics, coverage, tracks_seen).

    Reads ONLY the surfaces `candidate_surfaces` enumerates, at most
    `max_surfaces` of them; everything beyond the bound is disclosed by name in
    `coverage.skipped`, never dropped quietly.
    """
    matched = candidate_surfaces(repo)
    read_now = matched[:max_surfaces] if max_surfaces is not None else matched
    skipped = matched[len(read_now):]

    items, read_disclosure = [], []
    for section, rel, path in read_now:
        if section == "index":
            read_disclosure.append({"surface": rel,
                                    "entries": index_entry_count(path)})
            continue
        fm = read_frontmatter(path)
        slug = fm.get("slug") or os.path.splitext(os.path.basename(path))[0]
        evidence = _as_list(fm.get("evidence"))
        item = {
            "slug": slug if isinstance(slug, str) else str(slug),
            "title": fm.get("title") or fm.get("one_liner") or "",
            "section": section,
            "surface": rel,
            "status": fm.get("status") or "",
            "track": fm.get("track") or "",
            "date": fm.get("date") or "",
            # The evidence pointers as the item DECLARES them. They are counted
            # and listed, never resolved or followed — following one would be
            # the body fan-out CAP-4 forbids (and density/depth signals are
            # CAP-2's job, not this story's).
            "evidence": [e for e in evidence if isinstance(e, str)],
            "live": section in LIVE_SECTIONS,
        }
        items.append(item)
        read_disclosure.append({"surface": rel,
                                "entries": len(fm)})

    coverage = {
        "pin": repo_pin(repo),
        "bound": max_surfaces,
        "matched": len(matched),
        "read": read_disclosure,
        "skipped": [{"surface": rel,
                     "reason": f"over the read bound (--max-surfaces={max_surfaces})"}
                    for _s, rel, _p in skipped],
        "complete": not skipped,
        # Same closed accounting harvest's manifest carries: every matched
        # surface is disclosed as read or skipped, never silently omitted.
        "accounting_closes": len(read_disclosure) + len(skipped) == len(matched),
        "surfaces_read": "index and frontmatter only — item bodies are never read",
    }

    # --- topics: a pure per-invocation derivation (OQ1) ---------------------
    # A track maps to its declared hub topic(s); an unmapped track is shown
    # under its own name with mapped=false rather than being hidden or given an
    # invented topic. Nothing here asks the articles repo for a new key.
    topics = {}
    tracks_seen = set()
    for item in items:
        track = item["track"]
        if track:
            tracks_seen.add(track)
        names = mapping.get(track) or []
        mapped = bool(names)
        if not names:
            names = [track] if track else ["(untracked)"]
        for name in names:
            t = topics.setdefault(name, {"topic": name, "mapped": mapped,
                                         "tracks": set(), "items": []})
            t["mapped"] = t["mapped"] or mapped
            if track:
                t["tracks"].add(track)
            t["items"].append(item)
    out_topics = []
    for name in sorted(topics):
        t = topics[name]
        out_topics.append({
            "topic": name,
            "mapped": t["mapped"],
            "tracks": sorted(t["tracks"]),
            "item_count": len(t["items"]),
            "items": sorted(t["items"], key=lambda i: (i["section"], i["slug"])),
        })
    return out_topics, coverage, tracks_seen


def build_map(args):
    """The whole map, recomputed from scratch. No input to this function is a
    previously emitted map — there is no such input anywhere in this script."""
    root = host_root(args.root)
    repo = articles_repo(root, getattr(args, "repo", None))
    if not repo or not os.path.isdir(repo):
        sys.stderr.write(
            "error: no articles repo resolvable — declare `output.drafts` in "
            "writing-sources.yaml (resolve-writing-sources.py "
            "set-draft-location) or pass --repo\n")
        raise SystemExit(NO_ARTICLES_REPO)
    mapping = track_topics(root)
    topics, coverage, tracks_seen = assemble(repo, mapping, args.max_surfaces)
    stale = sorted(t for t in mapping if t not in tracks_seen)
    return {
        "kind": "topic-map",
        # CAP-1, stated in the artifact itself: this object is a view of the
        # repo at `coverage.pin`, valid for this invocation only. Nothing reads
        # it back — re-run the script instead of persisting it.
        "derived": True,
        "stored": False,
        "articles_repo": repo,
        "host_root": root,
        "track_topics": mapping,
        "unmapped_tracks": sorted(t for t in tracks_seen if t not in mapping),
        "stale_mapping_tracks": stale,
        "topics": topics,
        "coverage": coverage,
        "consumption": consumption_view(root),
    }


# --------------------------------------------------------------------------
# Subcommands


def _emit_debug(args, payload):
    """Optional debug dump. WRITE-ONLY BY CONTRACT (CAP-1): no code path in
    this script — or any flag it accepts — ever reads this file back, so it can
    never become a stored index. Deleting it loses nothing."""
    if not getattr(args, "emit_debug", None):
        return
    with open(args.emit_debug, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def cmd_assemble(args):
    payload = build_map(args)
    _emit_debug(args, payload)
    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


def cmd_surfaces(args):
    root = host_root(args.root)
    repo = articles_repo(root, getattr(args, "repo", None))
    if not repo or not os.path.isdir(repo):
        sys.stderr.write("error: no articles repo resolvable (pass --repo)\n")
        return NO_ARTICLES_REPO
    matched = candidate_surfaces(repo)
    for _section, rel, _p in matched[:args.max_surfaces]:
        print(rel)
    return 0


def cmd_coverage(args):
    payload = build_map(args)
    print(json.dumps(payload["coverage"], indent=2, ensure_ascii=False))
    return 0


def build_parser():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("--root", help="host-repo root (default: git toplevel of cwd)")
        sp.add_argument("--repo", help="articles repo root (default: the parent "
                                       "of the declared output.drafts dir)")
        sp.add_argument("--max-surfaces", type=int, default=DEFAULT_MAX_SURFACES,
                        help="CAP-4 read bound: how many index/frontmatter "
                             "surfaces this invocation may read (default "
                             f"{DEFAULT_MAX_SURFACES}). Surfaces beyond it are "
                             "NAMED in the coverage disclosure, never dropped.")
        return sp

    a = common(sub.add_parser("assemble", help="the whole map as JSON"))
    a.add_argument("--emit-debug", metavar="PATH",
                   help="also write this run's JSON to PATH — a debug artifact, "
                        "never an input (nothing reads it back)")
    common(sub.add_parser("surfaces", help="surfaces this run would read, in read order"))
    common(sub.add_parser("coverage", help="the coverage manifest alone, as JSON"))
    return p


DISPATCH = {"assemble": cmd_assemble, "surfaces": cmd_surfaces,
            "coverage": cmd_coverage}


def main(argv=None):
    args = build_parser().parse_args(argv)
    return DISPATCH[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
