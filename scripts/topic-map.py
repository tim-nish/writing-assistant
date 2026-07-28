#!/usr/bin/env python3
"""topic-map.py — the topic map as a DERIVED, READ-ONLY view (Story 18.61, #585;
SPEC-terrain CAP-1 + CAP-4).

The topic map is an overview of what the owner *could* write about, assembled
**at every invocation** from state that already exists. This script implements:

  CAP-1  derived view, never stored state
  CAP-2  subtopic clusters, evidence density, depth estimate (Story 18.62)
  CAP-4  bounded assembly (index/frontmatter surfaces only, with disclosure)

CAP-3 (in-conversation presentation, candidate directions, the brief hand-off)
is **not** implemented here — it belongs to a sibling story. This script prints
JSON; it composes no owner-facing screen and no narrative structures (18.45's
single-proposer invariant).

CAP-2 — the STRAND is the unit
------------------------------
Every hub Lesson and every served Journey rendering is its own STRAND: an
individually selectable piece of article material, carrying its served
plain-register rendering, its date, its consumed mark and its three-valued
writability verdict.

Subtopic CLUSTERING and the DEPTH ESTIMATE were removed 2026-07-27 (Story 20.7,
#809) — abandoned, not tuned: one dogfood run spent its whole budget to produce
a single usable line. Both the emitters and the threshold declaration are gone,
so the assembly cost went with the output; a section deleted at render time is
still paid for. What survived the removal, deliberately, is the CROSS-TOPIC
COMBINATION move, re-based onto strands (see topic-map-directions.py) rather
than deleted with the clusters it happened to be built from.

Two invariants hold regardless:

  * a signal gates what is **surfaced**, never what the owner may pick;
  * already-consumed material is **marked consumed, not hidden**, so the owner
    can still name it at the free-form entry (SPEC-article-draft-pipeline CAP-9,
    Story 18.47). Consumption is READ from the shipped derived view, never
    re-implemented and never stored.

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
    (SPEC-terrain OQ3). An unresolvable or degraded policy source makes the
    family **declared-but-not-enumerated with the reason** — the same disclosed
    refusal shape `consumption_view` uses — never a silent empty family.
  * `host-sources` — **DECLARED BUT NO LONGER ENUMERATED** (Story 20.7,
    #809). The host repo's writing sources are not article material: this
    family emitted ~190 junk directions in the second dogfood ("cover
    check-topic-map" — repo check scripts are evidence, not material). The
    family stays declared so CAP-4's denominator still NAMES it — a family
    deliberately out of scope must say so rather than vanish — but its
    surfaces are not walked, so the assembly cost went with the emitter.
  * `hub-gloss` — the served **plain-register Gloss overview index** (the
    gateway's two-tier `gloss_index`, tsurezure-gateway#64), one bounded
    tier-1 read: the ratified `gloss:` / `journey_gloss:` renderings the
    PRIMARY element projection quotes (#799). A gateway that cannot serve it
    makes the family declared-but-not-enumerated with the reason — and the
    element slots disclose the absence rather than quoting the recall
    one-liner in a rendering's place.

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
# verified against product-lab@<private-pin> rather than inferred.
ELEMENT_LINE = re.compile(r"^-\s+(\d{4}-\d{2}-\d{2})\s+—\s+(.*)$")

# The heading whose lines are rejections rather than decisions. Membership of
# this SECTION is the marker — not the word "declined", which appears inline in
# ordinary decision lines ("... declined as a conformance copy ...") and would
# misclassify most of a topic file as reversals.
DECLINED_HEADING = "declined"

# The other native reversal record: a struck-through clause inside a dated line
# marks the superseded position (topics/articles.md:17@<private-pin> is one).
STRUCK = "~~"

ELEMENT_SUMMARY_CHARS = 200
FAMILY_HOST_SOURCES = "host-sources"
FAMILY_HUB_GLOSS = "hub-gloss"
DECLARED_FAMILIES = (FAMILY_ARTICLES_ITEMS, FAMILY_HUB_LESSONS,
                     FAMILY_HOST_SOURCES, FAMILY_HUB_ELEMENTS,
                     FAMILY_HUB_GLOSS)

# One tier-1 Gloss overview line (`gloss/INDEX.md`): `- **<slug>** — <headline>
# (<tags>)[ · journeys/<tag>]`. The headline is the FIRST SENTENCE of the
# lesson's ratified `gloss:` rendering, verbatim (hub `specs/gloss.md` —
# consumers quote the ratified field, never re-express it). The optional
# trailing marker is the hub's per-lesson Journey discovery (`specs/gloss.md`
# §5.1, product-lab#106): the address of the journey shard holding this
# lesson's arc. Verified against the hub's generated index rather than
# inferred.
GLOSS_LINE = re.compile(
    r"^-\s+\*\*(.+?)\*\*\s+—\s+(.*?)"
    r"(?:\s+\(([^()]*)\))?"
    r"(?:\s+·\s+(journeys/[\w-]+))?$"
)

# A lesson seed enters the topic derivation through the SAME track->topic path
# every item uses: it carries the family name as its track, so an owner who
# wants these under a hub topic name declares it in `policy_source.track_topics`
# like any other track. Nothing here invents a topic.
LESSON_TRACK = FAMILY_HUB_LESSONS
LESSON_SECTION = FAMILY_HUB_LESSONS

# A declared writing source enters the topic derivation the same way, for the
# same reason: its own `track:` when it happens to declare one, else the family
# name as a track the owner may map like any other.


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


SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SRC_RES = os.path.join(SCRIPT_DIR, "resolve-writing-sources.py")
PLAN_WRITER = os.path.join(SCRIPT_DIR, "write-article-plan.py")
POLICY_READER = os.path.join(SCRIPT_DIR, "read-policy-source.py")

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


def gloss_read(root):
    """The `hub-gloss` family: the served tier-1 Gloss overview index, ONE
    bounded read through the shipped seam (`read-policy-source.py gloss`,
    the gateway's two-tier `gloss_index` — tsurezure-gateway#64).

    Returns `(by_file, reason)`. `by_file` is `[(rel, entries)]` in served
    order; each entry is `{slug, gloss, tags, cite, journey}` — `gloss` is the
    headline text verbatim (the first sentence of the ratified `gloss:` /
    `journey_gloss:` rendering; the hub writes it at the distill gate and
    consumers QUOTE it, never re-express it). An entry is a journey rendering
    exactly when the hub serves it from a journey-named index file — the
    consumer never guesses a journey arc from a lesson headline.

    A `reason` means the family is DECLARED-BUT-NOT-ENUMERATED and names why:
    an undeclared policy source, an unreachable gateway, a gateway that does
    not register `gloss_index` (the named exit-13 gap — the live deployment
    predates the tool or its operator config declares no gloss surface), or a
    served miss. The map never substitutes any other text for a ratified
    rendering: no gloss served means the slot DISCLOSES that, it never quotes
    the recall one-liner in the rendering's place.
    """
    cmd = [sys.executable, POLICY_READER]
    if root:
        cmd += ["--root", root]
    cmd += ["gloss"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        detail = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                  else f"the policy reader exited {r.returncode}")
        return [], f"{detail} (read-policy-source.py exit {r.returncode})"
    by_file, order, pin, current, commit = {}, [], None, None, None
    for line in r.stdout.splitlines():
        if line.startswith("pin: "):
            pin = line[5:].strip()
            continue
        if line.startswith("miss: "):
            return [], (f"the policy source served a miss for the gloss index "
                        f"at {pin or 'an undisclosed pin'}")
        if line.startswith("=== "):
            head = line[4:]
            path, _sep, sha = head.rpartition(" @ ")
            current, commit = path.strip(), sha.strip()
            if current not in by_file:
                by_file[current] = []
                order.append(current)
            continue
        if not current:
            continue
        number, _sep, text = line.partition(": ")
        if not number.strip().isdigit():
            continue
        m = GLOSS_LINE.match(text.strip())
        if not m:
            continue
        slug, headline, tags = m.group(1), m.group(2), m.group(3) or ""
        headline = headline.replace("**", "").strip()
        if not slug.strip() or not headline:
            continue
        by_file[current].append({
            "slug": slug.strip(),
            "gloss": headline,
            "tags": [t.strip() for t in tags.split(",") if t.strip()],
            "cite": f"{current}:{number.strip()}@{commit}",
            # A journey rendering is what the hub serves from a journey-named
            # index path (`gloss/journeys/...`) — the path is the hub's own
            # naming, and the consumer never infers an arc from a headline.
            "journey": "journey" in current.lower(),
            # The tier-1 marker names the journey shard carrying this lesson's
            # arc — discovery data, kept verbatim; None when the line has none.
            "journey_shard": m.group(4),
        })
    entries = [(rel, by_file[rel]) for rel in order if by_file[rel]]
    if not entries:
        return [], (f"the served gloss index at {pin or 'an undisclosed pin'} "
                    "lists no renderings")
    return entries, None


def gloss_surfaces(root):
    """The `hub-gloss` family as surfaces: one per served tier-1 index file.
    Returns `(surfaces, reason)`; the payload is the file's parsed entries —
    these surfaces were already served in the one bounded read, no file is
    opened for them."""
    by_file, reason = gloss_read(root)
    if reason:
        return [], reason
    return [(FAMILY_HUB_GLOSS, "gloss", rel, parsed)
            for rel, parsed in by_file], None


# A topic decision line's trailing provenance pointer and a decisions-shard
# entry heading carry the same key: `q_a/<batch> D<n>` (Story 20.22, #851;
# shard shape read from the served surface, not inferred). Rally suffixes and
# the heading's `· <date>` tail are outside the captured key on both sides.
DECISION_POINTER = re.compile(r"\(q_a/([^\s)]+)\s+D(\d+)[^)]*\)\s*$")
DECISION_SHARD_HEAD = re.compile(r"^##\s*\(q_a/([^\s)]+)\s+D(\d+)[^)]*\)\s*$")


def parse_decision_shard(stdout_text):
    """Entries of one served `decisions/<topic>` shard, keyed by provenance
    pointer (`q_a/<batch> D<n>`).

    The shard is the reader's `gloss --tag decisions/<topic>` output: `=== path
    @ sha` then `N: text` lines, entry headings `## (q_a/<batch> D<n> ·
    <date>)`, entry bodies the ratified plain-register rendering, whole. The
    rendering is quoted verbatim downstream — a consumer never re-expresses it.
    Measured at the pin this join was built against: shard entries carry NO
    per-entry tags, so `tags` is empty until the hub serves them — which is
    why a joined decision Strand still lands in the untagged-disclosure line
    rather than under an axis member.
    """
    entries, key, headline_no, body = {}, None, None, []
    path = sha = None

    def flush():
        if key and body:
            entries[key] = {
                "gloss": " ".join(" ".join(body).split()),
                "cite": f"{path}:{headline_no}@{sha}",
                "tags": [],
            }

    for line in stdout_text.splitlines():
        if line.startswith("miss: "):
            return {}
        if line.startswith("=== "):
            head = line[4:]
            p, _sep, c = head.rpartition(" @ ")
            path, sha = p.strip(), c.strip()
            continue
        number, _sep, text = line.partition(": ")
        if not number.strip().isdigit():
            continue
        t = text.strip()
        m = DECISION_SHARD_HEAD.match(t)
        if m:
            flush()
            key = f"q_a/{m.group(1)} D{m.group(2)}"
            headline_no, body = number.strip(), []
            continue
        if key and t and not t.startswith("#") and t != "---":
            body.append(t)
    flush()
    return entries


# A journey shard's entries are headed by the lesson slug whose arc they
# carry (`## <slug>`), which is the join key back to the lesson element. Shape
# read from the served surface, not inferred from the spec prose.
JOURNEY_SHARD_HEAD = re.compile(r"^##\s+([a-z0-9][a-z0-9-]*)\s*$")


def parse_journey_shard(stdout_text):
    """Entries of one served `journeys/<tag>` shard, keyed by lesson slug.

    Same reader shape as the decisions shard: `=== path @ sha` then `N: text`
    lines, entry headings `## <lesson-slug>`, entry bodies the ratified
    `journey_gloss:` rendering, whole. The rendering is quoted verbatim
    downstream — a consumer never re-expresses it and never synthesises an arc
    from a lesson headline.
    """
    entries, slug, headline_no, body = {}, None, None, []
    path = sha = None

    def flush():
        if slug and body:
            entries[slug] = {
                "gloss": " ".join(" ".join(body).split()),
                "cite": f"{path}:{headline_no}@{sha}",
            }

    for line in stdout_text.splitlines():
        if line.startswith("miss: "):
            return {}
        if line.startswith("=== "):
            head = line[4:]
            p, _sep, c = head.rpartition(" @ ")
            path, sha = p.strip(), c.strip()
            continue
        number, _sep, text = line.partition(": ")
        if not number.strip().isdigit():
            continue
        t = text.strip()
        m = JOURNEY_SHARD_HEAD.match(t)
        if m:
            flush()
            slug, headline_no, body = m.group(1), number.strip(), []
            continue
        if slug and t and not t.startswith("#") and t != "---":
            body.append(t)
    flush()
    return entries


def journey_shard_read(root, shards):
    """The served Journey renderings for the given `journeys/<tag>` shards.

    Journeys are REQUESTED, not awaited (CAP-4 as amended 2026-07-28, #871):
    the tier-1 index publishes a per-lesson `journeys/<tag>` marker and this
    issues the tagged read for the shards those markers name. Before this, the
    only gloss call was the untagged tier-1 one, so no journey shard was ever
    asked for and `journey_renderings` was 0 on every real run — an omission
    the screen reported as the hub not serving them.

    Returns `(by_slug, misses)`. A miss names its reason per shard and is
    NEVER folded into an empty dict: a shard that was requested and did not
    arrive is disclosed as such, which is a different fact from a shard that
    was never requested.
    """
    out, misses = {}, {}
    for shard in shards:
        cmd = [sys.executable, POLICY_READER]
        if root:
            cmd += ["--root", root]
        cmd += ["gloss", "--tag", shard]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            misses[shard] = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                             else f"the policy reader exited {r.returncode}")
            continue
        entries = parse_journey_shard(r.stdout)
        if entries:
            # Later shards never clobber an earlier arc: a lesson's arc is
            # 1:0..1, so a slug seen twice is the same arc served from two
            # tag shards, not two arcs.
            for slug, entry in entries.items():
                out.setdefault(slug, entry)
        else:
            misses[shard] = ("the served surface lists no journey renderings "
                             "for this shard")
    return out, misses


def decision_gloss_read(root, topics):
    """The served decision-line renderings: one tier-2 `decisions/<topic>`
    shard per topic in the ALREADY-BOUNDED element-topic set — the run never
    widens its own scope to reach more (CAP-4's rule, applied to the shard
    reads the same way `read_topic_elements` applies it to the topic reads).

    Returns `(by_topic, misses)`. A miss names its reason per topic; it is
    NEVER folded into an empty dict, because downstream the absence must be
    disclosed as the abnormal condition it is (owner ruling, #850 D4)."""
    out, misses = {}, {}
    for topic in topics:
        cmd = [sys.executable, POLICY_READER]
        if root:
            cmd += ["--root", root]
        cmd += ["gloss", "--tag", f"decisions/{topic}"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            misses[topic] = (r.stderr.strip().split("\n")[-1] if r.stderr.strip()
                             else f"the policy reader exited {r.returncode}")
            continue
        entries = parse_decision_shard(r.stdout)
        if entries:
            out[topic] = entries
        else:
            misses[topic] = ("the served surface lists no decision renderings "
                             "for this record")
    return out, misses


def join_decision_gloss(elements, shards, misses):
    """Attach each decision/reversal Strand's served rendering (Story 20.22,
    #851 — the join #850 D1 found missing).

    A joined Strand carries `gloss`/`gloss_cite`/`tags` exactly as
    lesson/journey Strands do, so the renderer's served branch fires with no
    renderer change. A Strand whose rendering is absent carries the
    ABNORMAL-CONDITION disclosure (owner ruling, #850 D4): a fault to fix now,
    stated at the point of substitution — never a tolerated gap, and never the
    raw topic line dressed as a rendering."""
    for el in elements:
        if el.get("kind") not in ("decision", "reversal"):
            continue
        key = el.get("decision_pointer")
        entry = (shards.get(el.get("topic") or "") or {}).get(key) if key else None
        if entry:
            el["gloss"] = entry["gloss"]
            el["gloss_cite"] = entry["cite"]
            el["tags"] = list(entry["tags"])
            el["gloss_unavailable"] = None
            continue
        el["gloss"] = None
        el["gloss_cite"] = None
        el.setdefault("tags", [])
        reason = misses.get(el.get("topic") or "")
        el["gloss_unavailable"] = (
            (f"the decision renderings for this record are not being served "
             f"({reason}) — an abnormal condition to fix now, not a gap to "
             f"tolerate") if reason else
            ("no rendering is served for this decision line — an abnormal "
             "condition to fix now, not a gap to tolerate"))


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
    surface (product-lab@<private-pin>) rather than inferred from the spec prose:

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
        # The line's trailing provenance pointer, captured BEFORE the summary
        # strips it (Story 20.22, #851): it is the JOIN KEY into the served
        # `decisions/<topic>` shard, whose entries are headed by the same
        # `(q_a/<batch> D<n> · <date>)` pointer. A line with no D-numbered
        # pointer has no served rendering to join and stays pointerless.
        pm = DECISION_POINTER.search(body)
        pointer = f"q_a/{pm.group(1)} D{pm.group(2)}" if pm else None
        elements.append({
            "kind": kind,
            "decision_pointer": pointer,
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
    # NOT ENUMERATED (Story 20.7, #809). The family stays DECLARED so CAP-4's
    # denominator still names it — "complete over a named denominator" means a
    # family that is deliberately out of scope must say so, not vanish — but
    # its surfaces are no longer walked. Enumerating and then discarding would
    # keep paying the assembly cost this removal exists to stop.
    families[FAMILY_HOST_SOURCES].update(
        enumerated=False,
        reason=("host source files are not article material (Story 20.7, "
                "#809): Strands are Lessons and Journeys"))
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
    gloss, reason = gloss_surfaces(root)
    if reason:
        families[FAMILY_HUB_GLOSS].update(enumerated=False, reason=reason)
    matched += gloss
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
        # enumerated with its reason and contributes no denominator — the same
        # shape `host-sources` now reports permanently. Counting its
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
    gloss_lessons, gloss_journeys, gloss_served = {}, {}, False
    for family, section, rel, payload in read_now:
        if family == FAMILY_HUB_GLOSS:
            # The served plain-register renderings, keyed by lesson slug. The
            # map QUOTES these — the ratified `gloss:` / `journey_gloss:`
            # fields, written at the hub's distill gate — and never composes
            # a rendering of its own (hub `specs/gloss.md` §1).
            gloss_served = True
            for entry in payload:
                target = gloss_journeys if entry["journey"] else gloss_lessons
                target.setdefault(entry["slug"], entry)
            read_disclosure.append({"family": family, "surface": rel,
                                    "entries": len(payload)})
            continue
        if family == FAMILY_HUB_ELEMENTS:
            # Strands are the PRIMARY units since the cluster removal
            # (Story 20.7, #809); they were always a separate projection from
            # items, and now they are the only one that reaches candidates.
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
        # Optional citation keys, projected only when an item declares one
        # (Story 18.62). The cluster keys are no longer read at all: clustering
        # is gone (Story 20.7, #809), and reading a key nothing consumes is the
        # assembly cost that removal exists to stop. The articles repo may keep
        # declaring them; they are simply unread here.
        for key in ELEMENT_KEYS:
            if key in fm:
                item[key] = _as_list(fm[key])
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
    # The tagged journey read (Story 20.30, #871). The tier-1 marker names the
    # shard carrying each lesson's arc; those markers are the request set, so
    # a run asks for exactly the shards its own material points at and never
    # enumerates the hub's shard directory. No marker anywhere means nothing
    # was requested — which the disclosure reports as such, never as the hub
    # failing to serve.
    journey_shards = sorted({e.get("journey_shard") for e in gloss_lessons.values()
                             if e.get("journey_shard")})
    journey_misses = {}
    if journey_shards:
        served_journeys, journey_misses = journey_shard_read(root, journey_shards)
        for slug, entry in served_journeys.items():
            gloss_journeys.setdefault(slug, entry)
    gloss_info = {
        "served": gloss_served,
        "reason": (None if gloss_served else
                   families[FAMILY_HUB_GLOSS].get("reason")
                   or "the gloss family was not enumerated"),
        "lessons": gloss_lessons,
        "journeys": gloss_journeys,
        # The three states CAP-4 requires a disclosure to distinguish:
        # requested-and-served, requested-and-missing, not-requested.
        "journeys_requested": journey_shards,
        "journey_misses": journey_misses,
    }
    return out_topics, coverage, tracks_seen, elements, gloss_info


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


# Optional item keys, read only when an item happens to declare them. None is
# required, so the articles repo gains no schema obligation from this story.
ELEMENT_KEYS = ("elements", "lessons")



def _journey_absence(slug, entry, journeys, gloss_info):
    """Why this lesson shows no arc — three-valued, never collapsed to one
    (CAP-4 as amended 2026-07-28/29).

    A corpus that was not REQUESTED is never reported as not SERVED: they are
    different facts about different parties, and reporting the first as the
    second attributes a consumer's omission to the source. That mistake, made
    on exactly this surface, sent a real triage after a stale hub pin that did
    not exist.
    """
    if slug in journeys:
        return None
    if not gloss_info.get("served"):
        # The gloss disclosure already names this larger outage; a second line
        # for one outage is the volume-not-legibility defect CAP-4 retired.
        return None
    shard = (entry or {}).get("journey_shard")
    if not shard:
        return ("no journey shard is named for this lesson on the served "
                "index — not requested, so not judged absent")
    miss = (gloss_info.get("journey_misses") or {}).get(shard)
    if miss:
        return (f"requested {shard} and it did not arrive: {miss}")
    return (f"requested {shard}, which carries no rendering for this lesson")


def lesson_elements(topics, gloss_info, consumption):
    """Every hub Lesson as a first-class ELEMENT — the primary selectable
    article-idea unit (SPEC-terrain, stance-3 pivot 2026-07-27, #799): N
    lessons are N distinct selectable ideas, and no cluster gates them.

    The slot QUOTES the served `gloss:` rendering (the plain-register text the
    hub ratifies at its distill gate), NEVER the recall one-liner — that is the
    ratified amendment this projection exists to carry. Where the gloss surface
    is not served, the slot states so with the reason; no other text is
    substituted for a ratified rendering.
    """
    consumed_index = (consumption or {}).get("consumed_index") or {}
    journeys = gloss_info.get("journeys") or {}
    seen = {}
    for topic in topics:
        for item in topic["items"]:
            if item.get("family") != FAMILY_HUB_LESSONS:
                continue
            slug = item.get("slug") or ""
            if not slug or slug in seen:
                continue
            entry = gloss_info["lessons"].get(slug)
            seen[slug] = {
                "kind": "lesson",
                "slug": slug,
                "title": item.get("title") or slug,
                "topic": topic["topic"],
                # The ratified rendering, verbatim — or an honest absence with
                # its reason. The recall one-liner is identification (`title`),
                # never the quoted rendering.
                "gloss": entry["gloss"] if entry else None,
                "gloss_cite": entry["cite"] if entry else None,
                "gloss_unavailable": (
                    None if entry else
                    (gloss_info["reason"] if not gloss_info["served"] else
                     "the served gloss index carries no rendering for this lesson")),
                "tags": entry["tags"] if entry else [],
                "journey_shard": entry.get("journey_shard") if entry else None,
                # The lesson's ARC, on the lesson's own row (CAP-2 as amended
                # 2026-07-28, #871). A Journey is not a Strand of its own:
                # correspondence is 1:0..1 and the hub's discovery marker is
                # per-lesson, so the arc is displayed with the rule it belongs
                # to and the lesson is what the owner selects.
                "journey": (journeys.get(slug) or {}).get("gloss"),
                "journey_cite": (journeys.get(slug) or {}).get("cite"),
                "journey_unavailable": _journey_absence(slug, entry, journeys,
                                                        gloss_info),
                "date": "",
                "situation": item.get("surface") or "",
                "evidence": list(item.get("evidence") or []),
                "consumed": slug in consumed_index,
                "consumption_join": ("consumed_index "
                                     "(write-article-plan.py consult), "
                                     "keyed by lesson id"),
            }
    return [seen[slug] for slug in sorted(seen)]


# `journey_elements()` was REMOVED (Story 20.30, #871). A Journey stopped
# being a Strand of its own: correspondence is 1:0..1, the hub's tier-1
# discovery marker is per-lesson by ratified design, and an independently
# selectable Journey would assert a reachability the served shape does not
# carry. The arc now attaches to its lesson in `lesson_elements()`, and the
# `J<n>` namespace is retired — it was never populated in production, because
# nothing ever requested a journey shard.


def journey_join(root, topics, elements=None):
    """Resolve each candidate's usability against the target repo's declared
    sources — the mechanical topic↔evidence join (Story 18.96, #669). Returns
    `(needs_recording, recording_target)` and annotates every item AND every
    element in place with `usability` — the pivot (#799) makes the verdict a
    visible property of every element: it SURFACES at selection, it never
    filters what appears, and an unmatched element stays selectable (picking
    one yields the gap disclosure and its NEEDS-RECORDING tracking artifact,
    never a refusal to draft).

    A hub-lesson candidate is `matched` when a declared **journey** entry carries
    its slug (the #671 join key resolves into declared sources); otherwise it is
    `episodic-unrecorded` and emits a NEEDS-RECORDING task naming the slug, the
    episode label, and the target journey file. **Never a silent drop** — the
    unusable candidate IS the map's product, a named backfill worklist
    (constrained-excludes-visibly, the flywheel that grows the usable set). A
    source-derived or articles item is `matched` by construction: its evidence is
    the declared source it came from. Every verdict carries the pointers checked
    (audited), and the join only LOCATES evidence — it never supplies it, and no
    hub line becomes a SOURCE pointer.

    Boundary — `no-episode` is cannot-determine here: distinguishing a lesson the
    hub records with no episode at all from one whose episode is merely unrecorded
    needs the Lesson BODY, which the seam does not serve (only index lines, OQ3).
    So an unmatched hub lesson defaults to `episodic-unrecorded` — the expected
    day-one majority — and `no-episode` is the owner's attribution at offer
    (Story 17.1 tier), stated as such."""
    jpaths = []
    r = subprocess.run([sys.executable, SRC_RES, "--root", root, "journey"],
                       capture_output=True, text=True)
    if r.returncode == 0:
        try:
            jpaths = json.loads(r.stdout).get("journey", [])
        except json.JSONDecodeError:
            jpaths = []
    haystack = ""
    for p in jpaths:
        try:
            with open(p, encoding="utf-8") as fh:
                haystack += fh.read() + "\n"
        except OSError:
            continue
    checked = list(jpaths)
    target_file = jpaths[0] if jpaths else os.path.join(root, "docs", "journey.md")
    target_repo = os.path.basename(root)
    needs_recording = []
    for topic in topics:
        for item in topic["items"]:
            if item.get("family") != FAMILY_HUB_LESSONS:
                item["usability"] = {"verdict": "matched", "checked": []}
                continue
            slug = item.get("slug") or ""
            if slug and slug in haystack:
                item["usability"] = {"verdict": "matched", "checked": checked}
            else:
                item["usability"] = {"verdict": "episodic-unrecorded",
                                     "checked": checked}
                needs_recording.append({
                    "slug": slug,
                    "episode": item.get("title") or slug,
                    "target_repo": target_repo,
                    "target_file": target_file,
                })
    for el in elements or []:
        if el.get("kind") in ("lesson", "journey"):
            slug = el.get("slug") or ""
            if slug and slug in haystack:
                el["usability"] = {"verdict": "matched", "checked": checked}
            else:
                # The expected day-one majority. `no-episode` stays the
                # owner's attribution at offer (Story 17.1 tier) — the seam
                # serves index lines and renderings, not lesson bodies, so
                # the map cannot mechanically tell the two apart (OQ3), and
                # collapsing them would queue work that can never complete.
                el["usability"] = {"verdict": "episodic-unrecorded",
                                   "checked": checked}
        else:
            # A decision/reversal element carries no lesson slug a `journey:`
            # entry could name — the LOOKUP has no key, and the honest outcome
            # is `cannot-determine` (the contracted fourth outcome of the
            # lookup, 2026-07-26 correction), never a merge into the three
            # verdicts and never rendered as "none".
            el["usability"] = {"verdict": "cannot-determine",
                               "checked": checked,
                               "reason": ("no join key — a decision/reversal "
                                          "element names no lesson slug a "
                                          "journey entry could carry")}
    return (sorted(needs_recording, key=lambda t: t["slug"]),
            {"repo": target_repo, "file": target_file})


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
    topics, coverage, tracks_seen, elements, gloss_info = assemble(
        repo, mapping, args.max_surfaces, root=root)
    stale = sorted(t for t in mapping if t not in tracks_seen)
    consumption = consumption_view(root)
    # The declared-subtopic defect disclosure (Story 18.74, #614) went with
    # clustering (Story 20.7, #809): it reported malformed `subtopic:`/
    # `cluster:` declarations so a typo could not degrade into a silent
    # derivation. Nothing derives from those keys now, so there is no
    # degradation left to guard — and a lint on a key this tool no longer
    # reads would be reporting a defect with no consequence. The articles repo
    # may keep declaring them; that is its own schema's business.
    subtopic_defects = []
    # The PRIMARY selection units (stance-3 pivot, 2026-07-27, #799): every hub
    # Lesson and every served Journey rendering is its own element beside the
    # decision/reversal projection. Built before the join so every element
    # carries its usability verdict.
    # The decisions-shard join (Story 20.22, #851 — the join #850 D1 found
    # missing): fetch the served renderings for exactly the topics that
    # produced decision/reversal Strands, then attach them. A missing
    # rendering is disclosed as the abnormal condition it is, in the join.
    decision_topics = sorted({e.get("topic") or "" for e in elements
                              if e.get("kind") in ("decision", "reversal")})
    decision_topics = [t for t in decision_topics if t]
    decision_gloss, decision_gloss_misses = decision_gloss_read(
        root, decision_topics)
    join_decision_gloss(elements, decision_gloss, decision_gloss_misses)
    elements = (elements
                + lesson_elements(topics, gloss_info, consumption))
    # Topic↔evidence usability join (Story 18.96, #669) — annotate every item
    # AND every element with its usability verdict and collect the
    # NEEDS-RECORDING worklist.
    needs_recording, recording_target = journey_join(root, topics, elements)
    # NO CLUSTERING (Story 20.7, #809). The subtopic cluster is abandoned, not
    # tuned: one dogfood run spent its whole budget to produce a single usable
    # line. Strands — Lessons and Journeys — are the selection unit, and they
    # are already built above.
    for topic in topics:
        topic["subtopics"] = []
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
        # Retained as an always-empty key so a consumer reading `map.json`
        # does not KeyError across the removal; nothing populates it since
        # clustering went (Story 20.7, #809).
        "subtopic_defects": subtopic_defects,
        "topics": topics,
        # The topic↔evidence join's product (Story 18.96, #669): the
        # NEEDS-RECORDING worklist for hub-lesson candidates whose episode no
        # declared source carries. Never a silent drop — the unusable candidate
        # is surfaced as named backfill work (constrained-excludes-visibly).
        "needs_recording": needs_recording,
        # Where a NEEDS-RECORDING gap is discharged: the target repo's declared
        # journey file. Selecting an unmatched element yields the gap
        # disclosure plus a tracking artifact HERE — never a refusal to draft.
        "recording_target": recording_target,
        # The gloss surface's own disclosure: whether the ratified renderings
        # were served, and the reason when they were not. A slot without a
        # served rendering states this — it never quotes the recall one-liner
        # in the rendering's place.
        "gloss": {"served": gloss_info["served"],
                  "reason": gloss_info["reason"],
                  "lesson_renderings": len(gloss_info["lessons"]),
                  "journey_renderings": len(gloss_info["journeys"]),
                  # The journey read's own disclosure (Story 20.30, #871):
                  # which shards were REQUESTED, and which of those did not
                  # arrive. Without these the screen cannot tell a corpus
                  # nobody asked for from one the hub failed to serve — the
                  # conflation CAP-4 now forbids.
                  "journeys_requested": gloss_info.get("journeys_requested") or [],
                  "journey_misses": gloss_info.get("journey_misses") or {},
                  # The decisions-shard join's own disclosure (Story 20.22,
                  # #851): how many renderings joined, and per-topic misses
                  # with their reasons — an absence is named, never folded
                  # into a zero.
                  "decision_renderings": sum(
                      len(v) for v in decision_gloss.values()),
                  "decision_misses": decision_gloss_misses},
        "coverage": coverage,
        "consumption": consumption,
        # The PRIMARY selection units (stance-3 pivot, 2026-07-27, #799):
        # typed strands — hub Lessons and Journeys first-class, plus the
        # decision/reversal projection — each individually
        # selectable, each carrying its visible usability verdict. Since the
        # cluster removal (Story 20.7, #809) they are the ONLY units. Derived
        # per invocation and stored nowhere.
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
