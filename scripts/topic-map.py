#!/usr/bin/env python3
"""topic-map.py — the topic map as a DERIVED, READ-ONLY view (Story 18.61, #585;
SPEC-topic-map CAP-1 + CAP-4).

The topic map is an overview of what the owner *could* write about, assembled
**at every invocation** from state that already exists. This script implements:

  CAP-1  derived view, never stored state
  CAP-2  subtopic clusters, evidence density, depth estimate (Story 18.62)
  CAP-4  bounded assembly (index/frontmatter surfaces only, with disclosure)

CAP-3 (in-conversation presentation, candidate directions, the brief hand-off)
is **not** implemented here — it belongs to a sibling story. This script prints
JSON; it composes no owner-facing screen and no narrative structures (18.45's
single-proposer invariant).

CAP-2 — depth signals
---------------------
Each topic's items are grouped into SUBTOPICS and annotated with an
evidence-density signal (distinct evidence pointers, unconsumed cited story
elements, backlog items with their status, live item count) and a DEPTH
ESTIMATE naming what the material supports today. The estimate is computed from
that density by minimums declared in ONE place
(`config/topic-depth-thresholds.yaml`, overridable per repo) — never by taste —
and every estimate carries the counts it was derived from, so "why this depth?"
is answered from the same numbers rather than an opaque score.

Two invariants hold here regardless of the numbers:

  * a threshold gates what is **surfaced**, never what the owner may pick —
    every subtopic is emitted `selectable: true`, whatever level it lands in;
  * already-consumed material is **marked consumed, not hidden**, so the owner
    can still name it at the free-form entry (SPEC-article-draft-pipeline CAP-9,
    Story 18.47). Consumption is READ from the shipped derived view, never
    re-implemented and never stored.

The shipped thresholds are PROPOSED, not ratified: the spec does not choose the
boundaries, so the declaration carries `ratified: false` and the map reports it
alongside every estimate.

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
        # Optional cluster/citation keys, projected only when an item happens to
        # declare one (Story 18.62). Reading a key that may be absent imposes no
        # schema obligation, and no clustering depends on any of them existing.
        for key in SUBTOPIC_KEYS + ELEMENT_KEYS:
            if key in fm:
                item[key] = fm[key] if key in SUBTOPIC_KEYS else _as_list(fm[key])
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


# --------------------------------------------------------------------------
# Subtopic clusters, evidence density and the depth estimate (CAP-2)
#
# A rich subtopic and a lone seed must look different at a glance. Everything
# below is DERIVED per invocation from the same bounded surfaces CAP-4 already
# reads — no new frontmatter key is required of the articles repo (OQ1 stays
# resolved as pure-derived), and nothing is stored.
#
# A THRESHOLD GATES WHAT IS SURFACED, NEVER WHAT THE OWNER MAY PICK. Every
# subtopic is emitted with `selectable: true`, and already-consumed material is
# MARKED consumed rather than hidden — the owner may still name it at the
# free-form entry (SPEC-article-draft-pipeline CAP-9, Story 18.47).

THRESHOLDS_FILE = "topic-depth-thresholds.yaml"

# Optional item keys, read only when an item happens to declare them. None is
# required, so the articles repo gains no schema obligation from this story.
SUBTOPIC_KEYS = ("subtopic", "cluster")
ELEMENT_KEYS = ("elements", "lessons")

UNCLUSTERED = "(unclustered)"


def thresholds_path(root, override):
    """The depth-threshold declaration: an explicit override, else a per-repo
    file beneath the RESOLVED repo-config directory, else the shipped default.
    One place, so the boundaries can move without touching stage code."""
    if override:
        return os.path.realpath(override)
    rp = _load("resolve-paths.py")
    repo_local = os.path.join(rp.repo_config_dir(root), THRESHOLDS_FILE)
    if os.path.isfile(repo_local):
        return repo_local
    return os.path.realpath(os.path.join(SCRIPT_DIR, "..", "config", THRESHOLDS_FILE))


def load_thresholds(root, override=None):
    """Read the declared levels. A missing or unreadable declaration is
    DISCLOSED, never silently replaced by numbers invented here."""
    path = thresholds_path(root, override)
    uc = _load("resolve-user-config.py")
    try:
        data = uc.load_yaml(open(path, encoding="utf-8").read())
    except (OSError, uc.YamlSubsetError) as exc:
        return {"available": False, "source": path, "reason": str(exc), "levels": []}
    declared = (data or {}).get("levels") or {}
    order = (data or {}).get("order") or sorted(declared)
    levels = []
    for key in order:
        entry = declared.get(key)
        if not isinstance(entry, dict):
            continue
        levels.append({
            "key": key,
            "name": str(entry.get("name") or key),
            "description": str(entry.get("description") or ""),
            "min_evidence_pointers": int(entry.get("min_evidence_pointers") or 0),
            "min_unconsumed_lessons": int(entry.get("min_unconsumed_lessons") or 0),
            "min_live_items": int(entry.get("min_live_items") or 0),
        })
    if not levels:
        return {"available": False, "source": path,
                "reason": "the declaration names no levels", "levels": []}
    return {"available": True, "source": path,
            # Proposed values are visibly proposed: a run can never mistake an
            # unratified calibration input for a settled rule.
            "ratified": bool((data or {}).get("ratified")),
            "levels": levels}


def _pointer_subject(pointer):
    """The subject a bare evidence pointer names: its path stem, with any line
    anchor and extension dropped (`docs/retro.md:41` -> `retro`). Two items
    citing the same source are talking about the same thing — that is the whole
    of the derivation, and it needs no declared key."""
    head = str(pointer).split("#")[0].split(":")[0].strip()
    stem = os.path.splitext(os.path.basename(head))[0]
    return stem or None


def subtopic_key(item):
    """Which cluster an item belongs to, derived in a fixed, explainable order:
    a declared subtopic when the item happens to carry one, else the subject its
    evidence pointers agree on, else `(unclustered)`. Never invented from prose.
    """
    for key in SUBTOPIC_KEYS:
        declared = item.get(key)
        if isinstance(declared, list) and declared:
            declared = declared[0]
        if isinstance(declared, str) and declared.strip():
            return declared.strip(), "declared"
    subjects = [s for s in (_pointer_subject(p) for p in item.get("evidence", [])) if s]
    if subjects:
        # The most-cited subject, ties broken alphabetically (determinism).
        best = sorted(set(subjects), key=lambda s: (-subjects.count(s), s))[0]
        return best, "evidence-subject"
    return UNCLUSTERED, "unclustered"


def estimate_depth(density, thresholds):
    """The strongest declared level whose every minimum the density meets, plus
    the reason it landed there — the estimate is EXPLAINABLE from the same
    numbers it was derived from, never an opaque score."""
    if not thresholds.get("available"):
        return {"level": None, "ratified": None,
                "why": ("no depth-threshold declaration is readable, so no estimate "
                        f"is offered ({thresholds.get('reason')})"),
                "thresholds_source": thresholds.get("source")}
    counted = {"evidence_pointers": density["evidence_pointers"],
               "unconsumed_lessons": density["unconsumed_lessons"],
               "live_items": density["live_items"]}
    chosen, unmet = thresholds["levels"][0], []
    for level in thresholds["levels"]:
        missing = [f"{k} {counted[k]} < {level['min_' + k]}"
                   for k in counted if counted[k] < level["min_" + k]]
        if missing:
            unmet = missing
            break
        chosen = level
    why = (f"{chosen['name']}: {counted['evidence_pointers']} evidence pointer(s), "
           f"{counted['unconsumed_lessons']} unconsumed lesson(s), "
           f"{counted['live_items']} live item(s)")
    if unmet:
        why += f"; the next level needs {', '.join(unmet)}"
    return {"level": chosen["name"], "description": chosen["description"],
            "ratified": thresholds.get("ratified"),
            "counted": counted, "why": why,
            "thresholds_source": thresholds.get("source"),
            # Stated in the artifact so no consumer can read the estimate as
            # permission: thresholds gate SURFACING, never what the owner picks.
            "gates": "surfacing only — never what the owner may pick"}


def _glance(depth, density):
    """A one-line, fixed-width density rendering so a rich subtopic and a lone
    seed are visibly different AT A GLANCE. Data, not a screen — composing the
    screen is CAP-3's job."""
    filled = min(4, sum(1 for n in (density["evidence_pointers"] // 3,
                                    density["unconsumed_lessons"],
                                    density["live_items"] // 2,
                                    density["items"] // 3) if n))
    bar = "#" * filled + "." * (4 - filled)
    return (f"[{bar}] {depth.get('level') or 'no estimate'} - "
            f"{density['evidence_pointers']} ptr, "
            f"{density['unconsumed_lessons']} unconsumed, "
            f"{density['live_items']} live")


def cluster_subtopics(items, consumption, thresholds):
    """Group a topic's items into subtopics and annotate each with its
    evidence-density signal and depth estimate."""
    consumed_index = (consumption or {}).get("consumed_index") or {}
    groups = {}
    for item in items:
        name, basis = subtopic_key(item)
        g = groups.setdefault(name, {"subtopic": name, "basis": basis, "items": []})
        g["items"].append(item)

    out = []
    for name in sorted(groups):
        g = groups[name]
        pointers, elements, unconsumed = set(), set(), set()
        backlog, consumed_items = [], 0
        for item in g["items"]:
            pointers.update(item.get("evidence") or [])
            cited = []
            for key in ELEMENT_KEYS:
                cited.extend(_as_list(item.get(key)))
            elements.update(cited)
            item_consumed = bool(cited) and all(e in consumed_index for e in cited)
            for eid in cited:
                if eid not in consumed_index:
                    unconsumed.add(eid)
            if item_consumed:
                consumed_items += 1
            if item["section"] == "backlog":
                backlog.append({"slug": item["slug"], "status": item["status"]})
        live_items = [i for i in g["items"] if i["live"]]
        density = {
            "evidence_pointers": len(pointers),
            "pointers": sorted(pointers),
            "lessons_cited": len(elements),
            "unconsumed_lessons": len(unconsumed),
            "unconsumed": sorted(unconsumed),
            "backlog_items": backlog,
            "items": len(g["items"]),
            "live_items": len(live_items),
        }
        depth = estimate_depth(density, thresholds)
        out.append({
            "subtopic": name,
            "clustered_by": g["basis"],
            "density": density,
            "depth": depth,
            "glance": _glance(depth, density),
            # Consumed material is MARKED, never hidden — and stays pickable.
            "consumed_items": consumed_items,
            "consumed": consumed_items > 0 and consumed_items == len(g["items"]),
            "selectable": True,
            "items": [dict(i, consumed=bool(
                [e for k in ELEMENT_KEYS for e in _as_list(i.get(k))])
                and all(e in consumed_index
                        for k in ELEMENT_KEYS for e in _as_list(i.get(k))))
                for i in g["items"]],
        })
    return out


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
    consumption = consumption_view(root)
    thresholds = load_thresholds(root, getattr(args, "thresholds", None))
    for topic in topics:
        topic["subtopics"] = cluster_subtopics(topic["items"], consumption, thresholds)
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
        "consumption": consumption,
        "depth_thresholds": thresholds,
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
        sp.add_argument("--thresholds", metavar="PATH",
                        help="depth-threshold declaration override (default: the "
                             "per-repo file, else the shipped "
                             f"config/{THRESHOLDS_FILE})")
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
