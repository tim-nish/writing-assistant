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

CAP-1 — derived, never stored, enumerated PER SOURCE FAMILY
-----------------------------------------------------------
Every field of the output is recomputed from authoritative state on each run,
and every candidate surface carries the **source family** it came from
(Story 18.64, #604; CAP-1 as amended 2026-07-23). The families:

  * `articles-items` — the **articles repo**: `backlog/`, `drafts/`,
    `newsletter/`, `graveyard/` item frontmatter and `INDEX.md`, reached
    through the declared `output.drafts` location
    (`resolve-writing-sources.py draft-location`), so no caller composes a
    storage path;
  * `hub-lessons` — the hub's Lesson corpus as its **index lines**, one lesson
    seed per line, read through the shipped policy seam
    (`read-policy-source.py read --only LESSONS.md`, the gateway's
    `lessons_index`). There is no second reader and no per-Lesson file read:
    the seam's scope is code-bounded and lesson BODIES are out of reach
    (SPEC-topic-map OQ3). An unresolvable or degraded policy source makes the
    family **declared-but-not-enumerated with the reason** — the same disclosed
    refusal shape `consumption_view` uses — never a silent empty family.
  * `host-sources` — the host repo's **declared writing sources** (Story
    18.65, #605), enumerated through the SINGLE enumerator
    (`resolve-writing-sources.py files`) that already owns the read boundary
    and its order — the same one harvest's budgeting delegates to. Read at
    **frontmatter/heading level only**: the leading `---` block and the ATX
    heading lines, never the prose between them. Undeclared or unresolvable
    sources make the family declared-but-not-enumerated with the reason, as
    above.

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

A family is a *declared denominator*, which is the point: a coverage claim
that does not name the families it covers is exactly the defect CAP-4 exists
to prevent (a "coverage complete" line that was true over the wrong corpus).

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
Only **index, frontmatter and heading surfaces** are read: `INDEX.md`, the
leading `---` frontmatter block of each item file, LESSONS.md index lines, and
a declared source's frontmatter plus its ATX heading lines. `read_frontmatter`
stops at the closing `---` and never touches the body; `read_headings` skips
over the prose between headings and projects none of it. Assembly cost scales
with index and outline size, not corpus body size — a repo of 50 huge articles
costs the same as 50 stubs, and a 20k-line README contributes exactly its
headings. There is an explicit read bound (`--max-surfaces`, default 400).

When the bound truncates, the map **names the surfaces it did not read** rather
than narrowing silently, in the coverage-disclosure shape harvest already uses
(`skills/harvest/SKILL.md` output contract, `validate-fact-sheet.py`
`validate_coverage`): a `pin`, a `matched` count, a `read` list with per-surface
entry counts, and a `skipped` list of `(surface, reason)` — with the same closed
accounting `#read + #skipped == matched` — which holds **per family** as well
as overall, and the manifest names which declared families were enumerated and
which were not.

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
import re
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

# Source families (CAP-1 as amended 2026-07-23), in a fixed enumeration order.
# The order is the read order, so the bound truncates the later families first
# and says so per family rather than narrowing the denominator in silence.
FAMILY_ARTICLES_ITEMS = "articles-items"
FAMILY_HUB_LESSONS = "hub-lessons"
FAMILY_HUB_ELEMENTS = "hub-elements"

# CAP-4's element bound, restated where it binds: the seam serves at most 2
# `topics/*.md` per read (`scripts/read-policy-source.py:100`). Element coverage
# is therefore PARTIAL BY CONSTRUCTION whenever the repo maps more topics than
# this, and the surfaces beyond the bound are disclosed by name — never dropped
# quietly, and never worked around with extra reads.
ELEMENT_TOPIC_BOUND = 2

# What a topic line looks like on the served surface: `- <date> — <text>`,
# verified against product-lab@6b9a4882 rather than inferred.
ELEMENT_LINE = re.compile(r"^-\s+(\d{4}-\d{2}-\d{2})\s+—\s+(.*)$")

# The heading whose lines are rejections rather than decisions. Membership of
# this SECTION is the marker — not the word "declined", which appears inline in
# ordinary decision lines ("... declined as a conformance copy ...") and would
# misclassify most of a topic file as reversals.
DECLINED_HEADING = "declined"

# The other native reversal record: a struck-through clause inside a dated line
# marks the superseded position (topics/articles.md:17@6b9a4882 is one).
STRUCK = "~~"

ELEMENT_SUMMARY_CHARS = 200
FAMILY_HOST_SOURCES = "host-sources"
DECLARED_FAMILIES = (FAMILY_ARTICLES_ITEMS, FAMILY_HUB_LESSONS,
                     FAMILY_HOST_SOURCES, FAMILY_HUB_ELEMENTS)

# A lesson seed enters the topic derivation through the SAME track->topic path
# every item uses: it carries the family name as its track, so an owner who
# wants these under a hub topic name declares it in `policy_source.track_topics`
# like any other track. Nothing here invents a topic.
LESSON_TRACK = FAMILY_HUB_LESSONS
LESSON_SECTION = FAMILY_HUB_LESSONS

# A declared writing source enters the topic derivation the same way, for the
# same reason: its own `track:` when it happens to declare one, else the family
# name as a track the owner may map like any other.
SOURCE_TRACK = FAMILY_HOST_SOURCES
SOURCE_SECTION = FAMILY_HOST_SOURCES


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
POLICY_READER = os.path.join(SCRIPT_DIR, "read-policy-source.py")

_BUDGET = []


def _budget():
    """harvest-budget.py, loaded once, for its `harvestable_lines` measure
    ALONE (Story 18.65). This is the shipped non-blank-line size proxy, reused
    so the map and harvest measure a source the same way — NOT harvest's
    extraction pass, which the map never invokes (CAP-4's cost promise)."""
    if not _BUDGET:
        _BUDGET.append(_load("harvest-budget.py"))
    return _BUDGET[0]


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


def _lesson_seed(text, cite):
    """One LESSONS.md index line as a lesson seed: `(id, title, cite)`.

    The index-line shape is the hub's own (`- [Title](lessons/<id>.md) — hook`),
    and only that shape is understood: the link target's stem is the seed's
    identifier, the link text its title. A line without a link keeps its text
    as the title and slugifies it for an identifier. Nothing here follows the
    link — lesson BODIES are out of the seam's reach (OQ3), and the hook text
    beyond the title is not projected as prose.
    """
    s = text.strip()
    if not s.startswith("- "):
        return None                      # a heading, a blank, a prose line
    s = s[2:].strip()
    ident, title = None, s
    if s.startswith("["):
        close = s.find("](")
        if close != -1:
            end = s.find(")", close)
            if end != -1:
                title = s[1:close].strip()
                target = s[close + 2:end].strip()
                ident = os.path.splitext(os.path.basename(target))[0] or None
    if ident is None:
        head = title.split("—")[0].split(" - ")[0].strip()
        ident = "".join(c if c.isalnum() else "-" for c in head.lower())
        ident = "-".join(p for p in ident.split("-") if p)
    if not ident:
        return None
    return ident, (title or ident), cite


def lesson_seeds(root):
    """The `hub-lessons` family: one seed per LESSONS.md **index line**, read
    through the shipped seam and nothing else.

    Returns `(seeds, reason)`. A `reason` means the family is
    DECLARED-BUT-NOT-ENUMERATED and names why — an undeclared policy source
    (exit 10), an unreachable gateway (11), a too-old tool surface (13), a
    malformed block (4), or a served miss. The map still produces a result in
    every one of those cases; a family that cannot be enumerated is disclosed,
    never silently empty.
    """
    cmd = [sys.executable, POLICY_READER]
    if root:
        cmd += ["--root", root]
    cmd += ["read", "--only", "LESSONS.md"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        detail = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                  else f"the policy reader exited {r.returncode}")
        return [], f"{detail} (read-policy-source.py exit {r.returncode})"
    pin, commit, seeds = None, None, []
    in_section = False
    for line in r.stdout.splitlines():
        if line.startswith("pin: "):
            pin = line[5:].strip()
            continue
        if line.startswith("miss: "):
            return [], (f"the policy source served a miss for {line[6:].strip()} "
                        f"at {pin or 'an undisclosed pin'}")
        if line.startswith("=== "):
            in_section = True
            commit = line.rsplit(" @ ", 1)[-1].strip()
            continue
        if not in_section:
            continue
        number, _sep, text = line.partition(": ")
        if not number.strip().isdigit():
            continue
        seed = _lesson_seed(text, f"LESSONS.md:{number.strip()}@{commit}")
        if seed:
            seeds.append(seed)
    if not seeds:
        return [], (f"the served LESSONS.md index at {pin or 'an undisclosed pin'} "
                    "lists no index lines")
    return seeds, None


def declared_sources(root):
    """The `host-sources` family's read boundary, from the SINGLE enumerator.

    `resolve-writing-sources.py files` is the one source of truth for which
    files are in scope and in what order — the same enumeration harvest's
    budgeting delegates to, so the map and harvest can never disagree about
    what "the declared sources" means. Returns `(paths, reason)`; a `reason`
    is the family's declared-but-not-enumerated disclosure.
    """
    cmd = [sys.executable, SRC_RES]
    if root:
        cmd += ["--root", root]
    cmd += ["files"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        detail = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                  else f"the enumerator exited {r.returncode}")
        return [], f"{detail} (resolve-writing-sources.py exit {r.returncode})"
    paths = [ln for ln in r.stdout.splitlines() if ln.strip()]
    if not paths:
        return [], ("no writing sources are declared for this repo "
                    "(resolve-writing-sources.py files enumerated none)")
    return paths, None


def read_headings(path):
    """A declared source at **frontmatter/heading level**, in ONE pass.

    **This is CAP-4's bound for the host-sources family**, the counterpart of
    `read_frontmatter` for files that have no frontmatter at all. It returns
    `(frontmatter, headings)` where `headings` is `[(level, text, line_no)]`
    for ATX heading lines only.

    The prose between headings is skipped over and discarded: it is never
    projected into the map, which is the difference between reading a document
    at outline level and consuming it as prose. Fenced code blocks are tracked
    so a `# comment` inside one is not mistaken for a heading.
    """
    fm, headings = {}, []
    try:
        with open(path, encoding="utf-8", errors="strict") as fh:
            raw = fh.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return fm, headings
    start = 0
    if raw and raw[0].strip() == "---":
        for i in range(1, len(raw)):
            if raw[i].strip() == "---":
                start = i + 1
                break
    if start:
        fm = read_frontmatter(path)
    fence = False
    for n, line in enumerate(raw[start:], start=start + 1):
        if line.lstrip().startswith("```") or line.lstrip().startswith("~~~"):
            fence = not fence
            continue
        if fence or not line.startswith("#"):
            continue
        level = len(line) - len(line.lstrip("#"))
        text = line[level:].strip()
        if text and level <= 6:
            headings.append((level, text, n))
    return fm, headings


def source_surfaces(root):
    """The `host-sources` family as surfaces, in the enumerator's own order.

    Returns `(surfaces, reason)`. The payload is the absolute path; the
    surface name is the path relative to the host root, so the manifest names
    a source the way the repo does.
    """
    paths, reason = declared_sources(root)
    if reason:
        return [], reason
    out = []
    for path in paths:
        try:
            rel = os.path.relpath(path, root)
        except ValueError:                       # pragma: no cover - defensive
            rel = path
        out.append((FAMILY_HOST_SOURCES, SOURCE_SECTION, rel, path))
    return out, None


def source_item(rel, path, pin):
    """A declared source as an item, projected from its OUTLINE alone.

    The projection — the story's open design point, proposed here for review:

      * **title** — the frontmatter `title:`, else the first level-1 heading,
        else the path stem. A README has no frontmatter; its `# Title` is the
        nearest thing it has to one.
      * **evidence** — one `file:line@pin` pointer per heading, at the
        heading's true line. These are real, resolvable cites, and a document
        with a rich outline honestly carries more of them than a stub.
      * **size** — `harvest-budget.py`'s `harvestable_lines`, the SHIPPED
        non-blank-line proxy, called rather than reimplemented so the map and
        harvest measure a source the same way.
      * **subtopic** — NOT set here. The shipped clustering rule already
        resolves a source to its own path stem via the evidence-pointer
        subject, so nothing needs inventing; a source that declares
        `subtopic:`/`cluster:` keeps winning as it does for any item.
      * **body text** — never projected. `read_headings` counts it and drops
        it; CAP-4 forbids widening to prose, and no heading's following
        paragraph reaches the map.
    """
    fm, headings = read_headings(path)
    title = fm.get("title") or fm.get("one_liner") or ""
    if not title:
        h1 = next((h for h in headings if h[0] == 1), None)
        title = h1[1] if h1 else os.path.splitext(os.path.basename(rel))[0]
    item = {
        "slug": os.path.splitext(os.path.basename(rel))[0],
        "title": title if isinstance(title, str) else str(title),
        "family": FAMILY_HOST_SOURCES,
        "section": SOURCE_SECTION,
        "surface": rel,
        "status": fm.get("status") or "",
        "track": fm.get("track") or SOURCE_TRACK,
        "date": fm.get("date") or "",
        "evidence": ([f"{rel}:{n}@{pin}" for _lvl, _t, n in headings]
                     or [f"{rel}:1@{pin}"]),
        "live": False,
        # The shipped cheap size proxy, carried as a SIGNAL. It informs the
        # density readout and nothing else: no declared depth level takes a
        # minimum over it, so CAP-2's "signal, never a gate" is untouched.
        "source_lines": _budget().harvestable_lines(path),
    }
    for key in SUBTOPIC_KEYS:
        if key in fm and fm[key]:
            item[key] = fm[key]
    return item


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
    """The `articles-items` family: every index/frontmatter surface the
    articles repo offers, in a deterministic read order — INDEX files first,
    then item files by section and name.

    Unchanged by Story 18.64 beyond the family tag: what this family yields is
    exactly what it yielded before, so widening the corpus cannot quietly move
    the family that already worked. Each entry is
    `(family, section, rel, payload)`; here the payload is a filesystem path.
    """
    surfaces = []
    for name in ("INDEX.md",):
        p = os.path.join(repo, name)
        if os.path.isfile(p):
            surfaces.append((FAMILY_ARTICLES_ITEMS, "index", name, p))
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
            surfaces.append((FAMILY_ARTICLES_ITEMS, section,
                             f"{section}/{name}", os.path.join(d, name)))
    return surfaces


def lesson_surfaces(root):
    """The `hub-lessons` family as surfaces: one per served index line.

    Returns `(surfaces, reason)` — a `reason` is the family's
    declared-but-not-enumerated disclosure, passed through from
    `lesson_seeds`. The payload is the seed tuple itself, not a path: these
    surfaces are index lines the seam already served, and no file is opened
    for them.
    """
    seeds, reason = lesson_seeds(root)
    if reason:
        return [], reason
    return [(FAMILY_HUB_LESSONS, LESSON_SECTION, seed[2], seed)
            for seed in seeds], None


def _element_summary(text):
    """One line of a topic decision, as a person reads it.

    The served text is markdown with emphasis and a trailing `(q_a/... D1)`
    provenance pointer. The pointer is the hub's own bookkeeping, not the
    decision, so it is dropped from the summary — the cite carries provenance.
    """
    body = re.sub(r"\s*\(q_a/[^)]*\)\s*$", "", str(text).strip())
    body = body.replace(STRUCK, "").replace("**", "").replace("`", "")
    body = " ".join(body.split())
    if len(body) > ELEMENT_SUMMARY_CHARS:
        body = body[:ELEMENT_SUMMARY_CHARS - 1].rstrip() + "…"
    return body


def parse_topic_elements(topic, served, commit):
    """The typed elements in one served topic file (CAP-2's element projection).

    `served` is the seam's `N: text` lines for the file, in order. Two element
    kinds are recognised, and BOTH markers were verified against the served
    surface (product-lab@6b9a4882) rather than inferred from the spec prose:

    * `reversal` — a dated line under the `## Declined` heading (things
      considered and rejected), or a dated line carrying a struck-through
      clause (`~~...~~`), which is how a superseded position is recorded
      in place. These are "the recall surface's native reversal records".
    * `decision` — any other dated line: the standing record of what was
      decided, with its reasoning.

    Section membership is what types a Declined line — NOT the word "declined",
    which appears inline in many ordinary decision lines ("... declined as a
    conformance copy ...", topics/articles.md:12) and would type most of a
    topic file as a reversal.
    """
    elements, heading = [], ""
    for number, text in served:
        stripped = text.strip()
        if stripped.startswith("## "):
            heading = stripped[3:].strip().lower()
            continue
        m = ELEMENT_LINE.match(stripped)
        if not m:
            continue
        date, body = m.group(1), m.group(2)
        declined = heading.startswith(DECLINED_HEADING)
        kind = "reversal" if (declined or STRUCK in body) else "decision"
        cite = f"topics/{topic}.md:{number}@{commit}"
        elements.append({
            "kind": kind,
            "summary": _element_summary(body),
            "topic": topic,
            # The situation it was recorded in: when, and exactly where.
            "date": date,
            "situation": cite,
            "evidence": [cite],
            # Marked, never hidden — the same rule lesson seeds follow. There
            # is no join to compute it against yet: `consumed_index` is keyed
            # by lesson id (`write-article-plan.py consult`), and the articles
            # repo declares no element-citation key. Disclosed rather than
            # guessed, and it widens exactly when that key appears.
            "consumed": False,
            "consumption_join": ("none — the articles repo declares no "
                                 "element-citation key"),
        })
    return elements


def element_topics(mapping):
    """The topics this run may project elements from: the ones the repo already
    declared through `policy_source.track_topics`, deduplicated and ordered
    deterministically. A run never widens its own scope to reach more."""
    names = {t for topics in mapping.values() for t in topics if t}
    return sorted(names)


def read_topic_elements(root, topics):
    """Read up to `ELEMENT_TOPIC_BOUND` topic files through the shipped seam
    and parse their elements.

    Returns `(by_topic, reason)`. A `reason` is the family's
    declared-but-not-enumerated disclosure, exactly as `lesson_seeds` returns
    it — an undeclared policy source, an unreachable gateway, a too-old tool
    surface, or a served miss. ONE read covers the whole bounded set; a run
    never issues extra reads to widen coverage (CAP-4).
    """
    if not topics:
        return {}, None
    cmd = [sys.executable, POLICY_READER]
    if root:
        cmd += ["--root", root]
    cmd += ["read", "--topics"] + [f"{t}.md" for t in topics]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        detail = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                  else f"the policy reader exited {r.returncode}")
        return {}, f"{detail} (read-policy-source.py exit {r.returncode})"
    by_topic, pin, current, commit, served = {}, None, None, None, []
    misses = []

    def flush():
        if current and served:
            by_topic[current] = parse_topic_elements(current, served, commit)

    for line in r.stdout.splitlines():
        if line.startswith("pin: "):
            pin = line[5:].strip()
            continue
        if line.startswith("miss: "):
            misses.append(line[6:].strip())
            continue
        if line.startswith("=== "):
            flush()
            head = line[4:]
            path, _sep, sha = head.rpartition(" @ ")
            commit, served = sha.strip(), []
            name = os.path.basename(path.strip())
            current = (os.path.splitext(name)[0]
                       if path.strip().startswith("topics/") else None)
            continue
        if not current:
            continue
        number, _sep, text = line.partition(": ")
        if number.strip().isdigit():
            served.append((number.strip(), text))
    flush()
    if misses and not by_topic:
        return {}, (f"the policy source served a miss for {', '.join(misses)} "
                    f"at {pin or 'an undisclosed pin'}")
    return by_topic, None


def element_surfaces(mapping):
    """The `hub-elements` family as surfaces: one per DECLARED topic file.

    Every declared topic is `matched` here, including the ones the seam bound
    will not reach — that is what lets the per-family accounting close over the
    real denominator and name which topics went unread, instead of quietly
    redefining "all topics" as "the two we read".
    """
    return [(FAMILY_HUB_ELEMENTS, "topic", f"topics/{t}.md", t)
            for t in element_topics(mapping)]


def all_surfaces(repo, root, mapping=None):
    """Every candidate surface across every DECLARED family, in family order,
    plus the family registry the coverage manifest discloses.

    The registry names each declared family and whether it was enumerated —
    with the reason when it was not — so "complete" is always complete over a
    named denominator (CAP-4 as amended 2026-07-23).
    """
    families = {name: {"family": name, "declared": True, "enumerated": True,
                       "reason": None}
                for name in DECLARED_FAMILIES}
    matched = list(candidate_surfaces(repo))
    lessons, reason = lesson_surfaces(root)
    if reason:
        families[FAMILY_HUB_LESSONS].update(enumerated=False, reason=reason)
    matched += lessons
    sources, reason = source_surfaces(root)
    if reason:
        families[FAMILY_HOST_SOURCES].update(enumerated=False, reason=reason)
    matched += sources
    # The element family's surfaces are the DECLARED topic files. An
    # undeclared mapping yields none, which is not an error: a repo that maps
    # no topics simply has no elements to project, and the family reports that
    # rather than inventing topics to read.
    elements = element_surfaces(mapping or {})
    if not elements:
        families[FAMILY_HUB_ELEMENTS].update(
            enumerated=False,
            reason=("no hub topic is declared for this repo "
                    "(`policy_source.track_topics`), so no topic file may be read"))
    matched += elements
    return matched, families


def _as_list(val):
    if val is None or val == "":
        return []
    if isinstance(val, list):
        return [v for v in val if v]
    return [str(val)]


def lesson_item(seed):
    """A lesson seed as an item, so it participates in the SAME clustering and
    density derivation every other item does (CAP-2, Story 18.62).

    Its identifier is declared as a `lessons:` element, which is the shipped
    signal for "unconsumed material worth writing about" — so a seed a plan
    already consumed is MARKED consumed by the existing lookup rather than
    hidden, and no second consumption rule appears here. Its own index line is
    its evidence pointer: a resolvable `file:line@commit` cite the seam served.
    """
    ident, title, cite = seed
    return {
        "slug": ident,
        "title": title,
        "family": FAMILY_HUB_LESSONS,
        "section": LESSON_SECTION,
        "surface": cite,
        "status": "",
        "track": LESSON_TRACK,
        "date": "",
        "evidence": [cite],
        "live": False,
        # NO tool-declared `subtopic` (Story 18.73, #614). One seed was one
        # cluster, which at corpus scale turned 65 index lines into 65
        # full subtopic blocks and buried the rest of the terrain. Seeds now
        # fall to the path-family derivation — they all cite the same index
        # surface, so they land in one cluster and the View lists them by name
        # as LESSON SEEDS under their topic, which is where they belong.
        #
        # It was also the tool naming a cluster. Under OQ1 as closed, subtopic
        # names belong to the articles repo's declared key; the tool derives,
        # it does not declare.
        "lessons": [ident],
    }


def assemble(repo, mapping, max_surfaces, root=None):
    """Assemble the map. Returns (topics, coverage, tracks_seen).

    Reads ONLY the surfaces `all_surfaces` enumerates across the declared
    families, at most `max_surfaces` of them; everything beyond the bound is
    disclosed by name in `coverage.skipped`, never dropped quietly, and the
    closed accounting is reported per family as well as overall.
    """
    matched, families = all_surfaces(repo, root, mapping)
    read_now = matched[:max_surfaces] if max_surfaces is not None else matched
    skipped = matched[len(read_now):]
    host_pin = repo_pin(root) if root else "unpinned"

    # --- the element family's own bound, applied BEFORE the loop ------------
    # The seam serves at most ELEMENT_TOPIC_BOUND topic files per read, which
    # is a different bound from `--max-surfaces` and is not negotiable here.
    # One read covers the whole reachable set; the topics past it are skipped
    # by NAME with the seam as the stated reason.
    elem_surfaces = [s for s in read_now if s[0] == FAMILY_HUB_ELEMENTS]
    elem_read = elem_surfaces[:ELEMENT_TOPIC_BOUND]
    elem_over = elem_surfaces[ELEMENT_TOPIC_BOUND:]
    elements_by_topic, element_reason = read_topic_elements(
        root, [payload for _f, _s, _r, payload in elem_read])
    if element_reason:
        families[FAMILY_HUB_ELEMENTS].update(enumerated=False,
                                             reason=element_reason)
        # A family that could not be enumerated AT ALL is declared-but-not-
        # enumerated with its reason and contributes no denominator — exactly
        # how `host-sources` behaves when nothing is declared. Counting its
        # surfaces as read-with-zero-entries would instead report a successful
        # empty projection, the "silently empty family" shape CAP-4 forbids.
        # This is distinct from the bounded case below: reading 2 of 9 topics
        # IS an incomplete run and says so; reading none is a family that did
        # not report.
        matched = [s for s in matched if s[0] != FAMILY_HUB_ELEMENTS]
        read_now = [s for s in read_now if s[0] != FAMILY_HUB_ELEMENTS]
        skipped = [s for s in skipped if s[0] != FAMILY_HUB_ELEMENTS]
        elem_read, elem_over = [], []
    read_now = [s for s in read_now if s not in elem_over]

    items, read_disclosure = [], []
    elements = []
    for family, section, rel, payload in read_now:
        if family == FAMILY_HUB_ELEMENTS:
            # Elements are a SECOND PROJECTION, not items: they never enter
            # the clustering that produces subtopics (CAP-2 — the cluster
            # stays the primary unit and elements sit beside it).
            found = elements_by_topic.get(payload) or []
            elements.extend(found)
            read_disclosure.append({"family": family, "surface": rel,
                                    "entries": len(found)})
            continue
        if family == FAMILY_HUB_LESSONS:
            items.append(lesson_item(payload))
            read_disclosure.append({"family": family, "surface": rel,
                                    "entries": 1})
            continue
        if family == FAMILY_HOST_SOURCES:
            item = source_item(rel, payload, host_pin)
            items.append(item)
            read_disclosure.append({"family": family, "surface": rel,
                                    "entries": len(item["evidence"])})
            continue
        path = payload
        if section == "index":
            read_disclosure.append({"family": family, "surface": rel,
                                    "entries": index_entry_count(path)})
            continue
        fm = read_frontmatter(path)
        slug = fm.get("slug") or os.path.splitext(os.path.basename(path))[0]
        evidence = _as_list(fm.get("evidence"))
        item = {
            "slug": slug if isinstance(slug, str) else str(slug),
            "title": fm.get("title") or fm.get("one_liner") or "",
            "family": family,
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
        read_disclosure.append({"family": family, "surface": rel,
                                "entries": len(fm)})

    skipped_disclosure = [
        {"family": family, "surface": rel,
         "reason": f"over the read bound (--max-surfaces={max_surfaces})"}
        for family, _s, rel, _p in skipped]
    # Named, not counted: the owner can see exactly which topics this run's
    # elements do NOT cover, which is what keeps a partial projection from
    # reading as the whole record.
    skipped_disclosure += [
        {"family": family, "surface": rel,
         "reason": (element_reason if element_reason else
                    f"over the seam's element bound (at most "
                    f"{ELEMENT_TOPIC_BOUND} topics/*.md per read); widening it "
                    f"is a hub-side ratification, never a map-side workaround")}
        for family, _s, rel, _p in elem_over]

    # Per-family accounting: the same closed read+skipped==matched rule the
    # overall manifest carries, computed within each family so a "complete"
    # claim can never be true over a denominator it never names.
    for name in DECLARED_FAMILIES:
        entry = families[name]
        f_matched = sum(1 for f, _s, _r, _p in matched if f == name)
        f_read = sum(1 for d in read_disclosure if d["family"] == name)
        f_skipped = sum(1 for d in skipped_disclosure if d["family"] == name)
        entry.update(matched=f_matched, read=f_read, skipped=f_skipped,
                     complete=f_skipped == 0,
                     accounting_closes=f_read + f_skipped == f_matched)

    coverage = {
        "pin": repo_pin(repo),
        "bound": max_surfaces,
        "matched": len(matched),
        "read": read_disclosure,
        "skipped": skipped_disclosure,
        "complete": not skipped_disclosure,
        # Same closed accounting harvest's manifest carries: every matched
        # surface is disclosed as read or skipped, never silently omitted.
        "accounting_closes": (len(read_disclosure) + len(skipped_disclosure)
                              == len(matched)),
        # CAP-4's named denominator: which declared families this run actually
        # enumerated, and which it did not — with the reason.
        "families": [families[name] for name in DECLARED_FAMILIES],
        "families_enumerated": [name for name in DECLARED_FAMILIES
                                if families[name]["enumerated"]],
        "families_not_enumerated": [
            {"family": name, "reason": families[name]["reason"]}
            for name in DECLARED_FAMILIES if not families[name]["enumerated"]],
        "surfaces_read": ("index and frontmatter only — item bodies are never "
                          "read; a declared source is read at heading level, "
                          "never as prose"),
        # Which topics this run's elements actually cover, stated positively so
        # the owner never reads a bounded projection as the whole record.
        "element_topics_read": [payload for _f, _s, _r, payload in elem_read],
        "element_topics_skipped": [payload for _f, _s, _r, payload in elem_over],
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
    # Ranked by RECENCY, then by cite (Story 18.79's open ranking choice,
    # answered): "what did I decide lately, and what changed my mind" is the
    # question elements exist to answer, and a date is the one ordering key
    # every element carries. Ties break on the cite so the order is
    # deterministic within a pin — the property the E<topic>.<n> indexes
    # assigned downstream depend on.
    elements.sort(key=lambda e: (e["date"], e["situation"]), reverse=True)
    return out_topics, coverage, tracks_seen, elements


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
    """The subject a bare evidence pointer names, at PATH-FAMILY granularity
    (Story 18.73, #614). Two items citing the same *family* of sources are
    talking about the same thing.

    The rule, and why it is shaped this way: use the pointer's **parent
    directory** when that directory is at least two segments deep, else the
    file stem.

        docs/stories/18-54-x.md:3   -> docs/stories      (one cluster, not ~60)
        specs/spec-tanuki-loop/SPEC.md:178 -> specs/spec-tanuki-loop  (per spec)
        tools/tanuki-ledger:1403    -> tanuki-ledger     (per tool, as before)
        README.md:1                 -> README

    The old rule was the file stem alone, which at corpus scale made "cluster"
    a synonym for "file": host-source items cite only themselves, so a
    147-subtopic map was a directory listing wearing a map's clothes. The
    depth-two condition is what keeps `tools/*` and `specs/*` per-item while
    collapsing a deep directory of siblings — both behaviours the map needs.

    A pointer containing whitespace is PROSE, not a path: `evidence:` in the
    articles repo holds free-text strings with embedded paths, so a last `/`
    can fall mid-sentence. Prose names no subject and is refused here rather
    than becoming a cluster name (the `" (first shipped consumer, Epic 14)"`
    case, Story 18.70/#616).

    Pure derivation: recomputed every invocation, recorded nowhere.
    """
    head = str(pointer).split("#")[0].split(":")[0].strip()
    if not head or re.search(r"\s", head):
        return None
    head = head.rstrip("/")
    parent = os.path.dirname(head)
    if parent.count("/") >= 1:
        return parent
    stem = os.path.splitext(os.path.basename(head))[0].strip()
    return stem or None


def subtopic_defect(item):
    """A declared subtopic key that is PRESENT but unusable, as
    `(key, reason)` — else None (Story 18.74, #614).

    The existence lint's counterpart for this vocabulary. A malformed
    declaration must be a config defect SURFACED BY NAME, never a silent
    fallback to derivation: today a non-string value simply fails the type test
    and the item quietly clusters by evidence instead, so a typo in the
    articles repo is indistinguishable from no declaration at all. Same shape
    as the ratified track->topic existence lint — the articles repo is
    authoritative, so a declaration the map cannot honour is the repo's defect
    to fix, and it says so rather than degrading.
    """
    for key in SUBTOPIC_KEYS:
        if key not in item:
            continue
        declared = item[key]
        if isinstance(declared, list):
            if not declared:
                return key, "declares an empty list; name one subtopic or remove the key"
            if len(declared) > 1:
                return key, (f"declares {len(declared)} values "
                             f"({', '.join(map(str, declared[:3]))}...); an item belongs "
                             "to ONE subtopic — only the first would be used")
            declared = declared[0]
        if not isinstance(declared, str):
            return key, (f"declares a value of type {type(declared).__name__}, "
                         "not a name; subtopic names are strings")
        if not declared.strip():
            return key, "declares an empty name; remove the key instead"
    return None


def subtopic_key(item):
    """Which cluster an item belongs to, in a fixed, explainable order of
    DECLARED PRECEDENCE (OQ1, closed 2026-07-23):

      1. a declared `subtopic:`/`cluster:` from the articles repo — the repo's
         frontmatter schema is the API, and it names its own subjects;
      2. else the PATH FAMILY its evidence pointers agree on (Story 18.73);
      3. else `(unclustered)`.

    The articles repo is authoritative: a cluster disagreeing with a declared
    name is this tool's defect, never the repo's. Nothing is cached — the
    declaration is read at assembly time on every invocation, so the mismatch
    check is RECOMPUTATION, never reconciliation, and no vocabulary is
    mirrored into plugin state. Never invented from prose.
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
        # Same guard the declared branch above already holds: a name that is
        # empty once stripped is NOT a name. Falling through to `(unclustered)`
        # is honest; rendering an unnamed heading is not.
        if best.strip():
            return best.strip(), "evidence-subject"
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


# The bar's width when there is no readable level declaration to take it from.
# Only reachable on the no-estimate path, where every bar is empty anyway.
GLANCE_FALLBACK_WIDTH = 4


def _glance(depth, density, thresholds=None):
    """A one-line density rendering so a rich subtopic and a lone seed are
    visibly different AT A GLANCE. Data, not a screen — composing the screen is
    CAP-3's job.

    THE BAR IS THE ESTIMATE, RENDERED (Story 18.69, #613): one segment per
    declared level, filled up to and including the level this subtopic landed
    in. Two subtopics at the same level render the same bar, and a stronger
    level never renders fewer segments than a weaker one.

    It previously filled one segment per NON-ZERO density dimension, which
    measured dimension DIVERSITY rather than accumulated depth — so a
    seed-only subtopic with 7 live items and no evidence rendered `[##..]`
    while an 85-pointer article series rendered `[#...]`. The bar and the depth
    word beside it moved independently and sometimes in opposite directions,
    which inverts exactly the comparison CAP-2's success criterion promises.

    The rendering stays explainable from the counts printed on the same line,
    because those counts are precisely what `estimate_depth` used to choose the
    level (see its `why`). And it stays a SIGNAL: the bar reports where the
    material landed, never what the owner may pick.
    """
    names = [lv["name"] for lv in (thresholds or {}).get("levels") or []]
    level = depth.get("level")
    if names and level in names:
        width, filled = len(names), names.index(level) + 1
    else:
        # No readable declaration, so there is no ladder to place this subtopic
        # on. An empty bar beside `no estimate` is the honest render — a bar
        # invented here would be the "opaque score" the estimate refuses to be.
        width, filled = len(names) or GLANCE_FALLBACK_WIDTH, 0
    bar = "#" * filled + "." * (width - filled)
    return (f"[{bar}] {level or 'no estimate'} - "
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
            # The declared sources' shipped size proxy, summed. A SIGNAL only:
            # no declared level takes a minimum over it (CAP-2 — depth remains
            # a signal, never a gate), it just lets a thin doc and a thick one
            # look different in the readout.
            "source_lines": sum(i.get("source_lines") or 0 for i in g["items"]),
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
            "glance": _glance(depth, density, thresholds),
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
    topics, coverage, tracks_seen, elements = assemble(
        repo, mapping, args.max_surfaces, root=root)
    stale = sorted(t for t in mapping if t not in tracks_seen)
    consumption = consumption_view(root)
    thresholds = load_thresholds(root, getattr(args, "thresholds", None))
    # Declared-subtopic defects, surfaced BY NAME rather than degrading into a
    # silent derivation (Story 18.74, #614). Collected before clustering so the
    # disclosure covers every item, including ones whose declaration was
    # unusable and which therefore clustered by evidence instead.
    subtopic_defects = []
    for topic in topics:
        for item in topic["items"]:
            found = subtopic_defect(item)
            if found:
                key, reason = found
                subtopic_defects.append({
                    "item": item.get("slug") or item.get("surface") or "",
                    "surface": item.get("surface") or "",
                    "key": key,
                    "reason": reason,
                })
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
        # The articles repo is authoritative for subtopic names; a declaration
        # this map cannot honour is the repo's defect, named here rather than
        # silently replaced by a derived cluster.
        "subtopic_defects": sorted(subtopic_defects,
                                   key=lambda d: (d["item"], d["key"])),
        "topics": topics,
        "coverage": coverage,
        "consumption": consumption,
        "depth_thresholds": thresholds,
        # CAP-2's SECOND PROJECTION, beside the subtopic clusters and never
        # merged into them: what was decided, and what changed. Derived per
        # invocation and stored nowhere, exactly like everything else here.
        "elements": elements,
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
    matched, _families = all_surfaces(repo, root)
    for _family, _section, rel, _p in matched[:args.max_surfaces]:
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
