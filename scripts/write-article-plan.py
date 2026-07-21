#!/usr/bin/env python3
"""write-article-plan.py — the article-plan writer (SPEC-article-plan CAP-1/CAP-2).

A completed run's editorial decisions — intent, audience, claim, evidence
clusters, open questions, visual plan — are stranded in a disposable run
workspace unless they are projected into a durable record. This writer emits
that record: an **article plan** at `plans/<slug>.md` in the articles
repository, beside the draft it plans.

The plan is a **deterministic projection** of artifacts the run already
produced (journal, editorial anchor, answers, visual decisions, unresolved
items): the SKILL assembles the plan text from run state, this writer validates
and places it. No owner interaction happens here, and writing the same plan
text twice is byte-identical.

Validation is **fail-closed with per-key diagnostics** — the same posture as
the sanctioned config writers: a plan that violates the schema is refused and
nothing is written.

Frontmatter contract (issue #310, owner-set 2026-07-17):

  REQUIRED  kind (constant `article-plan`), slug (== filename stem), intent,
            claim, status (outlined|drafted|superseded), run_id,
            pin (`<source-repo>@<commit>`)
  OPTIONAL  audience, audience_id, policy_seeded, seed (required iff policy_seeded), relates,
            policy_pin (`<name>@<sha>`, the consulted policy pin),
            policy_config_version (`[A-Za-z0-9._-]+`),
            policy_conformance (conformant|open|conflict|stale),
            arc (#440/#434: projected at completion from the run's argument-plan
                 intermediate; thesis projects into `claim`)
            — the CAP-4 trio; ALL THREE required when policy_seeded is true
            (a policy-seeded plan without conformance data is refused: run
            the `conformance --write` gate to record them)
  FORBIDDEN everything the canonical draft or its variants own (title, summary,
            topics, language, published, variants_emitted, canonical_url),
            machine-state content (checkpoint, journal, provenance-map data),
            draft-lifecycle statuses (review/published), and prose `evidence:`
            lists — the body carries commit-pinned pointers only.

Subcommands (each takes --root; default: the git top-level of cwd):

  validate --path plans/<slug>.md [PLAN|-]
      Validate a plan's text against the schema for the given destination path.
      Exit 0 = conforming; exit 4 = refused, with a per-key report.

  dest --slug <slug> [--root R]
      Print the resolved destination as JSON: the articles repo's
      `plans/<slug>.md` when the destination carries the articles-repo schema,
      else the user-scoped fallback (keyed by repo + slug). Read-only — it
      creates nothing.

  write --slug <slug> [PLAN|-] [--root R]
      Validate, then write the plan to the resolved destination. ONLY the plan
      file is emitted: no journal, checkpoint, or provenance-map data ever
      lands in the articles repository, and nothing is written to the host
      source repo. A non-conforming destination falls back to user-scoped
      state and NO `plans/` directory is created there. Prints the result JSON.

  consult [--root R]
      Read existing article plans for consultation at draft start (CAP-3,
      Story 13.57). READ-ONLY: it reads `plans/*.md` from the articles repo
      through the schema and creates/modifies NOTHING. Emits each plan's
      discovery surface (slug, intent, claim, status, pin, relates) as JSON so
      the run can surface plan-grounded proposals under the proposal contract.
      A repo with no plans, or a schema-less destination, degrades silently:
      it prints an empty plan list with a `degraded` reason — never a failure,
      never a prompt about missing plans.

  conformance --plan plans/<slug>.md --surface <policy-surface>
              [--config-json J | --root R] [--config-version V]
              [--staging <staging-candidates.md>] [--write]
      The CAP-4 policy-conformance gate (Story 13.76): validate every
      policy-seeded decision the plan records against the SAME pinned policy
      result the run consulted (the seam's served surface) and the
      authoritative user config, and compute status ∈
      conformant | open | conflict | stale. `--write` records the consulted
      pin, configVersion, and status into the plan's frontmatter through this
      writer's fail-closed validation. The gate writes NOTHING to any policy
      hub — with --write it touches exactly one file: the plan.
"""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys

PLAN_KIND = "article-plan"
PLAN_DIR = "plans"

REFUSED = 4  # schema violation — nothing is written

REQUIRED_KEYS = ("kind", "slug", "intent", "claim", "status", "run_id", "pin")
OPTIONAL_KEYS = ("audience", "audience_id", "policy_seeded", "seed", "relates",
                 "policy_pin", "policy_config_version", "policy_conformance",
                 # `arc` (#440/#434): projected at completion from the run's
                 # argument-plan intermediate ($WS/argument-plan.md) — the
                 # ordered movement the draft realizes. Thesis projects into the
                 # existing `claim` field. C2: the plan-record is the
                 # projection-of-record; the intermediate is not persisted here.
                 "arc",
                 # `consumed` (CAP-9/#430, Story 18.9): the story-element ids
                 # this article's draft consumed. This is the ONLY consumption
                 # record — no second store (C1). Lesson-based selection reads
                 # it across every plan (consult's `consumed_index`, a view
                 # regenerated from the plans on each call) and defaults to the
                 # unconsumed elements. Keyed by element id, so it survives
                 # re-harvest pointer drift (the id is identity, 18.8).
                 "consumed")
PLAN_STATUSES = ("outlined", "drafted", "superseded")

# A story-element id (CAP-9/#428): identity for an evidence cluster. The
# persisted form a plan's `consumed` list carries — a stable token, never a
# pointer set (pointers are derived payload under the id, 18.8). Kept
# deliberately permissive on internal shape (`lesson:retry-storm`, a hash) but
# closed against whitespace/prose so a `consumed` list can never smuggle free
# text past the schema.
ELEMENT_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:._-]*$")


def parse_id_list(raw):
    """A `consumed:` frontmatter value → the list of element ids it names.
    Accepts an optionally-bracketed, comma-separated scalar (the flat
    frontmatter parser stores lists as strings): `[a, b]` or `a, b` or ``.
    Returns [] for an empty value."""
    s = str(raw).strip()
    if s.startswith("[") and s.endswith("]"):
        s = s[1:-1]
    return [t.strip().strip('"').strip("'") for t in s.split(",") if t.strip()]

# The CAP-4 conformance trio (Story 13.76): optional in general, required as a
# set when the plan is policy-seeded — recorded by `conformance --write`.
CONFORMANCE_KEYS = ("policy_pin", "policy_config_version", "policy_conformance")
CONFORMANCE_STATUSES = ("conformant", "open", "conflict", "stale")
CONFIG_VERSION_RE = re.compile(r"^[A-Za-z0-9._-]+$")

# Fields the canonical draft or its variants own — a plan restating one forks
# the source of truth.
DRAFT_OWNED = ("title", "summary", "topics", "language", "published",
               "variants_emitted", "canonical_url")
# Machine state belongs to the run workspace, never the articles repository.
MACHINE_STATE = ("checkpoint", "journal", "provenance_map", "provenance-map",
                 "rubric_verdicts", "presented_payloads")
# Draft-lifecycle statuses the plan may never claim (its own set is
# PLAN_STATUSES; `review`/`published` describe the draft, not the plan).
DRAFT_STATUSES = ("review", "published", "seed", "evidenced")

# `<source-repo>@<commit>` — the pin every body pointer resolves against.
PIN_RE = re.compile(r"^[^\s@]+@[0-9a-f]{7,40}$")
# A commit-pinned file pointer, a bare sha, a URL, a Den pointer (Story 13.51),
# or an interview-answer id (`q3`, `a12`) — the only evidence forms a plan body
# may carry. Mirrors the fact-sheet SOURCE grammar; prose evidence is refused.
PINNED_PTR_RE = re.compile(
    r"^(?:.+:\d+(?:-\d+)?@[0-9a-f]{7,40}"      # path:line@sha / path:l1-l2@sha
    r"|[0-9a-f]{7,40}"                          # bare commit sha
    r"|https?://\S+"                            # URL
    r"|den:[A-Za-z0-9._-]+@[A-Za-z0-9._-]+"     # den:<ledger-id>@<run>
    r"|[qa]\d+)$")                              # interview-answer id
# An UNPINNED file pointer anywhere in the body (`path:line` with no `@sha`).
# The trailing `(?![\d@-])` blocks the match from backtracking into a genuinely
# pinned pointer (`path:12@sha` must not match as `path:1`).
UNPINNED_PTR_RE = re.compile(r"(?<![\w@/:.-])([\w./-]+\.\w+:\d+(?:-\d+)?)(?![\d@-])")


def _load_mod(fname):
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        fname.replace("-", "_").replace(".py", ""), os.path.join(here, fname))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _load_paths():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rp", os.path.join(here, "resolve-paths.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _load_sources():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rp = _load_paths()


def split_frontmatter(text):
    """Return (fields, body, errors). Frontmatter is the flat `key: value`
    subset the plan contract uses — stdlib-only, like every other reader here.
    """
    errors = []
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text, [("(frontmatter)", "a plan must open with a `---` "
                           "frontmatter block")]
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, text, [("(frontmatter)", "unterminated frontmatter block "
                           "(no closing `---`)")]
    fields = {}
    for lineno, ln in enumerate(lines[1:end], 2):
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z][\w-]*)\s*:\s*(.*)$", ln)
        if not m:
            errors.append((f"line {lineno}", f"unparseable frontmatter line: "
                                             f"{ln.strip()!r}"))
            continue
        key, raw = m.group(1), m.group(2).strip()
        fields[key] = raw.strip('"').strip("'")
    return fields, "\n".join(lines[end + 1:]), errors


def _truthy(v):
    return str(v).strip().lower() in ("true", "yes", "1")


def validate_plan(text, path):
    """Yield (key, reason) for every schema violation; empty = conforming."""
    fields, body, errors = split_frontmatter(text)
    for e in errors:
        yield e
    if not fields:
        return

    stem = os.path.splitext(os.path.basename(path))[0]
    parent = os.path.basename(os.path.dirname(os.path.normpath(path)))

    # Placement: `plans/<slug>.md` and nowhere else.
    if parent != PLAN_DIR:
        yield ("(path)", f"a plan lives at {PLAN_DIR}/<slug>.md; refused path: "
                         f"{path} (parent directory is {parent!r})")
    if not path.endswith(".md"):
        yield ("(path)", f"a plan is a markdown file: {path}")

    # Required keys.
    for key in REQUIRED_KEYS:
        if key not in fields or not str(fields[key]).strip():
            yield (key, "required key is missing or empty")

    if fields.get("kind") and fields["kind"] != PLAN_KIND:
        yield ("kind", f"must be the constant {PLAN_KIND!r} (got "
                       f"{fields['kind']!r}) — it is the machine marker that "
                       "keeps a plan out of the evidence stream")
    if fields.get("slug") and fields["slug"] != stem:
        yield ("slug", f"must equal the filename stem: slug={fields['slug']!r} "
                       f"but the file is {os.path.basename(path)!r} (stem "
                       f"{stem!r}) — the slug IS the 1:1 article association")
    status = fields.get("status")
    if status and status not in PLAN_STATUSES:
        if status in DRAFT_STATUSES:
            yield ("status", f"{status!r} is a DRAFT-lifecycle status owned by "
                             f"the draft, not the plan; valid plan statuses: "
                             + ", ".join(PLAN_STATUSES))
        else:
            yield ("status", f"unknown status {status!r}; valid: "
                             + ", ".join(PLAN_STATUSES))
    if fields.get("pin") and not PIN_RE.match(fields["pin"]):
        yield ("pin", f"must be <source-repo>@<commit> (got {fields['pin']!r}) "
                      "— every body pointer resolves against it")

    # policy_seeded / seed coupling: an audited seed or neither.
    if _truthy(fields.get("policy_seeded", "")) and not fields.get("seed", "").strip():
        yield ("seed", "required when policy_seeded is true — the seed's "
                       "file:line@commit pointer is what makes the influence "
                       "auditable")
    if fields.get("seed") and not re.match(r"^.+:\d+(?:-\d+)?@[0-9a-f]{7,40}$",
                                           fields["seed"]):
        yield ("seed", f"must be a commit-pinned file:line@commit pointer (got "
                       f"{fields['seed']!r})")

    # CAP-4 conformance trio (Story 13.76): each key validated fail-closed,
    # and a policy-seeded plan must carry all three — a policy-seeded plan
    # without conformance data is refused.
    if fields.get("policy_pin") and not PIN_RE.match(fields["policy_pin"]):
        yield ("policy_pin", f"must be the consulted policy pin <name>@<sha> "
                             f"(got {fields['policy_pin']!r}) — it is what the "
                             "conformance gate validated against")
    pcv = fields.get("policy_config_version")
    if pcv and not CONFIG_VERSION_RE.match(pcv):
        yield ("policy_config_version",
               f"must match [A-Za-z0-9._-]+ (got {pcv!r}) — the configVersion "
               "the conformance gate consulted")
    pc = fields.get("policy_conformance")
    if pc and pc not in CONFORMANCE_STATUSES:
        yield ("policy_conformance", f"unknown conformance status {pc!r}; "
                                     "valid: " + ", ".join(CONFORMANCE_STATUSES))
    if _truthy(fields.get("policy_seeded", "")):
        for key in CONFORMANCE_KEYS:
            if not str(fields.get(key, "")).strip():
                yield (key, "required when policy_seeded is true — a "
                            "policy-seeded plan without conformance data is "
                            "refused; run the `conformance --write` gate "
                            "(SPEC-article-plan CAP-4) to record the consulted "
                            "pin, configVersion, and status")

    # `consumed` (CAP-9/#430): a list of well-formed story-element ids. Each id
    # is identity (18.8); a malformed or prose-bearing entry is refused so the
    # single consumption record can never drift into free text.
    if "consumed" in fields:
        ids = parse_id_list(fields["consumed"])
        for tok in ids:
            if not ELEMENT_ID_RE.match(tok):
                yield ("consumed", f"malformed story-element id {tok!r} — each "
                                   "entry is a stable id token "
                                   "([A-Za-z0-9][A-Za-z0-9:._-]*), never a "
                                   "pointer set or prose (the id is identity, "
                                   "the pointers are derived payload)")
        if len(set(ids)) != len(ids):
            yield ("consumed", "duplicate story-element id — consumption is a "
                               "set keyed by id, list each element at most once")

    # Forbidden fields.
    for key in fields:
        if key in DRAFT_OWNED:
            yield (key, "forbidden: this field is owned by the canonical draft "
                        "or its variants — a plan that restates it forks the "
                        "source of truth")
        elif key in MACHINE_STATE:
            yield (key, "forbidden: machine state (journal, checkpoint, "
                        "provenance map) stays in the run workspace and never "
                        "lands in the articles repository")
        elif key == "evidence":
            yield (key, "forbidden: prose evidence lists are not evidence — "
                        "the body carries commit-pinned pointers (or "
                        "interview-answer ids) resolved against `pin`")
        elif key not in REQUIRED_KEYS and key not in OPTIONAL_KEYS:
            yield (key, "unknown field — the plan schema is closed (required: "
                        + ", ".join(REQUIRED_KEYS) + "; optional: "
                        + ", ".join(OPTIONAL_KEYS) + ")")

    # Body: every evidence reference is pinned. An unpinned `path:line` is the
    # exact defect the fact-sheet grammar refuses, refused here too.
    for lineno, ln in enumerate(body.split("\n"), 1):
        if ln.lstrip().startswith("#"):
            continue
        for m in UNPINNED_PTR_RE.finditer(ln):
            yield (f"body line {lineno}",
                   f"unpinned pointer {m.group(1)!r} — every evidence "
                   "reference is commit-pinned (path:line@sha), a bare sha, a "
                   "URL, a den: pointer, or an interview-answer id")
        m = re.match(r"^\s*evidence\s*:\s*(.+)$", ln, re.IGNORECASE)
        if m and not all(PINNED_PTR_RE.match(tok.strip())
                         for tok in m.group(1).split(",") if tok.strip()):
            yield (f"body line {lineno}",
                   "prose evidence — an `evidence:` line carries pinned "
                   "pointers or interview-answer ids only, never free text")


def articles_repo_root(root):
    """The articles repository: the git top-level containing the declared
    `output.drafts` destination (or the destination itself when it is not in a
    git repo). Returns None when no destination is declared."""
    rws = _load_sources()
    lines = rws.read_lines(root)
    val = rws.get_output_drafts(lines)
    if not val:
        return None
    drafts = rws.resolve_drafts_dir(val, root)
    cur = drafts
    while True:
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return drafts        # not in a git repo: the destination itself
        cur = parent


def has_articles_schema(repo):
    """Does `repo` carry the articles-repo schema (the API this writer works
    through — SPEC-article-plan, "the repo's schema is the API")?

    The markers are the schema's own load-bearing surfaces: a `drafts/`
    directory (canonical drafts) plus its discovery/lifecycle surface —
    `INDEX.md` or `backlog/`. A destination without them is NOT an articles
    repo, so the plan falls back to user-scoped state instead of parking a
    tool-owned `plans/` tree in someone else's directory.
    """
    if not repo or not os.path.isdir(repo):
        return False
    if not os.path.isdir(os.path.join(repo, "drafts")):
        return False
    return (os.path.isfile(os.path.join(repo, "INDEX.md"))
            or os.path.isdir(os.path.join(repo, "backlog")))


def resolve_dest(root, slug):
    """(path, conforming, repo): where this plan lands.

    Conforming articles repo -> <repo>/plans/<slug>.md.
    Otherwise -> the machine-global user-scoped fallback, keyed by repo + slug,
    with the draft association intact (the slug) and NO plans/ directory
    created in the non-conforming destination.
    """
    repo = articles_repo_root(root)
    if has_articles_schema(repo):
        return os.path.join(repo, PLAN_DIR, f"{slug}.md"), True, repo
    fallback = os.path.join(rp.repo_dir(root), PLAN_DIR, f"{slug}.md")
    return fallback, False, repo


def _report(defects):
    sys.stderr.write("article plan REFUSED — schema violations:\n")
    for key, reason in defects:
        sys.stderr.write(f"  [{PLAN_DIR}/<slug>.md] {key}: {reason}\n")
    sys.stderr.write("\nNothing was written.\n")


def _read_plan(arg):
    return sys.stdin.read() if arg == "-" else open(arg, encoding="utf-8").read()


def cmd_validate(args):
    text = _read_plan(args.plan)
    defects = list(validate_plan(text, args.path))
    if defects:
        _report(defects)
        return REFUSED
    print(json.dumps({"ok": True, "path": args.path}))
    return 0


def cmd_dest(args):
    root = rp.host_root(args.root)
    path, conforming, repo = resolve_dest(root, args.slug)
    print(json.dumps({"path": path, "conforming": conforming,
                      "articles_repo": repo,
                      "fallback": None if conforming else "user-scoped state "
                                  "(keyed by repo + slug); the destination does "
                                  "not carry the articles-repo schema"}))
    return 0


def cmd_write(args):
    root = rp.host_root(args.root)
    text = _read_plan(args.plan)
    path, conforming, repo = resolve_dest(root, args.slug)

    # Validate against the CANONICAL plans/<slug>.md contract in both cases —
    # the fallback location changes where the plan lives, never its schema.
    defects = list(validate_plan(text, os.path.join(PLAN_DIR, f"{args.slug}.md")))
    if defects:
        _report(defects)
        return REFUSED

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(json.dumps({"ok": True, "path": path, "conforming": conforming,
                      "articles_repo": repo, "slug": args.slug,
                      "emitted": [os.path.basename(path)]}))
    return 0


def _read_plan_summary(path):
    """Parse one plan file into its discovery surface, or None if unreadable /
    not an article plan. Read-only."""
    try:
        with open(path, encoding="utf-8") as fh:
            fields, _, _ = split_frontmatter(fh.read())
    except OSError:
        return None
    if fields.get("kind") != PLAN_KIND:
        return None
    slug = fields.get("slug") or os.path.splitext(os.path.basename(path))[0]
    return {"slug": slug, "intent": fields.get("intent"),
            "claim": fields.get("claim"), "status": fields.get("status"),
            "pin": fields.get("pin"), "relates": fields.get("relates"),
            "policy_seeded": fields.get("policy_seeded"),
            # CAP-9/#430: the story-element ids this plan's draft consumed, so
            # consultation can exclude them from a new lesson-based selection.
            "consumed": parse_id_list(fields.get("consumed", ""))}


def cmd_consult(args):
    """Read existing plans for draft-start consultation (CAP-3). Read-only and
    silent-degrading: no articles-repo schema, or no plans/ directory, yields
    an empty list with a reason — never a failure, never a side effect."""
    root = rp.host_root(args.root)
    repo = articles_repo_root(root)
    if not has_articles_schema(repo):
        print(json.dumps({"plans": [], "degraded":
                          "destination has no articles-repo schema; "
                          "consultation is skipped (today's behavior)"}))
        return 0
    plans_dir = os.path.join(repo, PLAN_DIR)
    if not os.path.isdir(plans_dir):
        print(json.dumps({"plans": [], "degraded":
                          "no plans/ directory in the articles repo"}))
        return 0
    summaries = []
    for name in sorted(os.listdir(plans_dir)):
        if not name.endswith(".md"):
            continue
        s = _read_plan_summary(os.path.join(plans_dir, name))
        if s is not None:
            summaries.append(s)
    # CAP-9/#430: the consumption-exclusion view — every story-element id any
    # plan records as consumed, mapped to the plans that consumed it. This is a
    # MECHANICALLY REGENERATED VIEW over `plans/*.md`, rebuilt on each call from
    # the plans alone; it is never a stored second ledger (C1). Lesson-based
    # selection defaults to elements NOT in this index; the owner may override
    # to re-cover one.
    consumed_index = {}
    for s in summaries:
        for eid in s.get("consumed", []):
            consumed_index.setdefault(eid, []).append(s["slug"])
    print(json.dumps({"plans": summaries, "articles_repo": repo,
                      "consumed_index": consumed_index, "degraded": None}))
    return 0


# --- Differential context: prior-coverage digest (Story 18.23, #504) ----------
# When prior published/drafted articles share the project, the argument plan
# should not re-explain what those articles already carry. This computes a
# READ-ONLY prior-coverage digest — built on the SAME carriers as plan
# consultation (plans/*.md) and continuation mode (the canonical's frontmatter +
# framing spans) — so Stage 3 can compress-and-link repeated context instead of
# re-introducing it. The prior body NEVER enters the harvest evidence stream
# (Story 13.56's fences hold): this is framing context, exactly like
# continuation mode, computed automatically rather than only on an explicit
# `continuing <slug>`. No new store, no schema change (C1) — the project a plan
# belongs to is the repo component of its already-recorded `pin`.

def _plan_project(pin):
    """The project a plan belongs to: the source-repo component of its `pin`
    (`<source-repo>@<commit>`). This is the `related.projects` proxy already
    carried by every plan — no new field."""
    if not pin:
        return None
    return pin.split("@", 1)[0].strip() or None


def _canonical_dir(root):
    """The declared `output.drafts` directory (where continuation mode reads a
    named prior canonical), or None when none is declared."""
    rws = _load_sources()
    val = rws.get_output_drafts(rws.read_lines(root))
    if not val:
        return None
    return rws.resolve_drafts_dir(val, root)


_CONTEXT_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s*\{?\s*context\b", re.IGNORECASE)
_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s")
# Warning-callout / admonition spans a prior article carries — the tissue the
# owner does not want repeated verbatim. GitHub-style callouts plus a small set
# of plain-prose warning cues, matched deterministically in document order.
_WARN_CALLOUT_RE = re.compile(r"^\s{0,3}>?\s*\[!(?:WARNING|CAUTION|IMPORTANT)\]", re.IGNORECASE)
_WARN_PROSE_RE = re.compile(r"\b(warning|caveat|gotcha|do not|don't|limitation|pitfall)\b",
                            re.IGNORECASE)
_SPAN_CAP = 500


def _split_frontmatter_body(text):
    fields, body, _ = split_frontmatter(text)
    return fields, body


def _blocks(body):
    """Body split into blank-line-delimited blocks, each a (list-of-lines)."""
    out, cur = [], []
    for ln in body.split("\n"):
        if ln.strip() == "":
            if cur:
                out.append(cur); cur = []
        else:
            cur.append(ln)
    if cur:
        out.append(cur)
    return out


def _context_span(body):
    """The text of the first section whose heading names Context — the shared
    setup a second article should recap-and-link rather than re-explain. None
    when the article has no such section."""
    lines = body.split("\n")
    start = None
    for i, ln in enumerate(lines):
        if _CONTEXT_HEADING_RE.match(ln):
            start = i + 1
            break
    if start is None:
        return None
    span = []
    for ln in lines[start:]:
        if _HEADING_RE.match(ln):
            break
        span.append(ln)
    text = re.sub(r"\s+", " ", "\n".join(span)).strip()
    return text[:_SPAN_CAP] or None if text else None


def _warning_spans(body):
    """Every warning/caveat span in the article body, in document order, deduped
    — the warnings a second article repeats only when load-bearing for its own
    claim (the SKILL owns that judgment; here we surface them)."""
    spans, seen = [], set()
    for block in _blocks(body):
        head = block[0]
        if _WARN_CALLOUT_RE.match(head) or _WARN_PROSE_RE.search(" ".join(block)):
            # strip leading blockquote/callout markers for a clean recap unit
            cleaned = []
            for ln in block:
                ln = re.sub(r"^\s{0,3}>\s?", "", ln)
                ln = re.sub(r"^\s*\[!(?:WARNING|CAUTION|IMPORTANT)\]\s*", "", ln,
                            flags=re.IGNORECASE)
                if ln.strip():
                    cleaned.append(ln.strip())
            text = re.sub(r"\s+", " ", " ".join(cleaned)).strip()[:_SPAN_CAP]
            if text and text not in seen:
                seen.add(text)
                spans.append(text)
    return spans


def cmd_differential_context(args):
    """Emit the prior-coverage digest for the run's project (Story 18.23). READ-
    ONLY, silent-degrading exactly like `consult`: no articles-repo schema, or no
    plans/ directory, yields an empty digest with a reason — never a failure.

    Membership: every prior plan whose project (the repo component of its `pin`)
    equals `--project`. For each, the digest carries the plan's slug/claim/status
    plus — read from the canonical at `output.drafts/<slug>.md`, framing context
    like continuation mode — the article's `summary` and its Context / warning
    spans. The prior body is used ONLY to build this framing digest; it never
    enters the harvest evidence stream. No prior article sharing the project ->
    an empty `prior_coverage` (unchanged behavior; no digest)."""
    root = rp.host_root(args.root)
    project = (args.project or "").strip() or _plan_project(
        f"{os.path.basename(os.path.realpath(root))}@")
    repo = articles_repo_root(root)
    if not has_articles_schema(repo):
        print(json.dumps({"project": project, "prior_coverage": [], "degraded":
                          "destination has no articles-repo schema; "
                          "differential context is skipped (today's behavior)"}))
        return 0
    plans_dir = os.path.join(repo, PLAN_DIR)
    if not os.path.isdir(plans_dir):
        print(json.dumps({"project": project, "prior_coverage": [], "degraded":
                          "no plans/ directory in the articles repo"}))
        return 0
    drafts_dir = _canonical_dir(root)
    coverage = []
    for name in sorted(os.listdir(plans_dir)):
        if not name.endswith(".md"):
            continue
        s = _read_plan_summary(os.path.join(plans_dir, name))
        if s is None:
            continue
        if _plan_project(s.get("pin")) != project:
            continue
        entry = {"slug": s["slug"], "claim": s.get("claim"),
                 "intent": s.get("intent"), "status": s.get("status"),
                 "pin": s.get("pin"), "summary": None,
                 "context_span": None, "warnings": []}
        # Framing context (continuation-mode read): the canonical's frontmatter
        # summary + its Context/warning spans. Read-only; body-fenced from harvest.
        if drafts_dir:
            canon = os.path.join(drafts_dir, f"{s['slug']}.md")
            if os.path.isfile(canon):
                try:
                    fields, body = _split_frontmatter_body(
                        open(canon, encoding="utf-8").read())
                    entry["summary"] = fields.get("summary")
                    entry["context_span"] = _context_span(body)
                    entry["warnings"] = _warning_spans(body)
                except OSError:
                    pass
        if entry["summary"] is None:      # canonical absent: the plan's claim is
            entry["summary"] = entry["claim"]   # the only framing available
        coverage.append(entry)
    print(json.dumps({"project": project, "articles_repo": repo,
                      "prior_coverage": coverage, "degraded": None}, indent=2))
    return 0


# --- CAP-4 policy-conformance gate (Story 13.76, #365) ------------------------

# A commit-pinned policy pointer in the seam whitelist grammar
# (`file:line[-line]@sha`) — the form a plan body carries for policy-consulted
# decisions.
POLICY_PTR_RE = re.compile(r"([\w./-]+):(\d+)(?:-\d+)?@([0-9a-f]{7,40})")
# An optional recorded quote on the same body line as a pointer: the first
# double-quoted span is treated as the plan's record of the consulted line.
QUOTE_RE = re.compile(r'"([^"]+)"')


def _plan_policy_refs(fields, body, surface_files):
    """Every policy pointer the plan records that references the served
    surface: the `seed:` frontmatter pointer plus each body pointer whose file
    is one the surface serves. Each ref: {file, line, sha, quote, at} — quote
    is the first double-quoted span on the same body line (None when the plan
    recorded no quote; the seed pointer never carries one)."""
    refs = []
    seed = fields.get("seed", "")
    m = POLICY_PTR_RE.fullmatch(seed)
    if m and m.group(1) in surface_files:
        refs.append({"file": m.group(1), "line": int(m.group(2)),
                     "sha": m.group(3), "quote": None, "at": "seed"})
    for lineno, ln in enumerate(body.split("\n"), 1):
        for m in POLICY_PTR_RE.finditer(ln):
            if m.group(1) not in surface_files:
                continue
            qm = QUOTE_RE.search(ln)
            refs.append({"file": m.group(1), "line": int(m.group(2)),
                         "sha": m.group(3),
                         "quote": qm.group(1) if qm else None,
                         "at": f"body line {lineno}"})
    # One ref per referenced file:line — a quoted body pointer wins over a
    # quoteless one (e.g. the seed) for the same line, so a recorded quote is
    # always the one compared in the stale check.
    merged, order = {}, []
    for r in refs:
        k = (r["file"], r["line"])
        if k not in merged:
            merged[k] = r
            order.append(k)
        elif merged[k]["quote"] is None and r["quote"] is not None:
            merged[k] = {**r}
    return [merged[k] for k in order]


def _staging_blocks(path):
    """Split a staging-candidates file into its `<!-- staging-candidate -->`
    blocks (each block's full text, marker excluded)."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        raise SystemExit(f"error: cannot read staging candidates {path!r}: {e}")
    parts = text.split("<!-- staging-candidate -->")
    return [p.strip() for p in parts[1:] if p.strip()]


def _staging_covers(blocks, subject):
    """Does a staging-candidate block record the reversal for this subject as
    a proposed policy change? Match by subject/tag: the block carries the
    `config-policy-reconciliation` tag (the CAP-7 reconciliation emitter's
    framing) and names the subject's config key."""
    for b in blocks:
        if "config-policy-reconciliation" in b and subject["config_key"] in b:
            return True
    return False


def cmd_conformance(args):
    """The CAP-4 policy-conformance gate (Story 13.76): validate every
    policy-seeded decision the plan records against the SAME pinned policy
    result the run consulted (--surface: the reader's `read` output) and the
    authoritative user config, and compute the plan's conformance status.

    Status rules (mechanical; precedence conflict > stale > conformant/open):

      conflict    — the shared comparable-subjects detector
                    (policy_subjects.detect_conflicts, the SAME table and rule
                    as `draft-pipeline.py classify-policy`) fires between the
                    served surface and the resolved config, and no staging
                    candidate covers it. Both positions are named with
                    pointers in the findings.
      conformant (reversal_as_proposal) — the detector fires but the run's
                    staging candidates (--staging) carry a
                    `config-policy-reconciliation` block naming the subject's
                    config key: the reversal is conformant ONLY as a proposed
                    policy change, never treated as current policy.
      stale       — THE EXACT RULE: the pin has moved (the plan's recorded
                    `policy_pin` differs from the surface's current pin, OR a
                    referenced pointer's own @sha differs from the sha the
                    surface currently serves for that file) AND at least one
                    plan-referenced consulted line changed — mechanically, for
                    each referenced `file:line`: when the plan records a quote
                    on the pointer's line, the line is changed iff that quote
                    no longer appears in the surface's current text at
                    `file:line`; when no quote is recorded, the pin mismatch
                    alone counts that referenced file as changed; a referenced
                    `file:line` the current surface no longer serves counts as
                    changed. A moved pin whose every referenced line is
                    unchanged (recorded quotes still present) is NOT stale.
      conformant  — checked and clean: at least one referenced consulted line
                    is classifiable by the comparable-subjects table, no
                    conflict fired, and the pin/lines are current.
      open        — policy-seeded decisions exist but the comparable table
                    cannot classify their subjects (nothing to check) — or the
                    plan records no policy-seeded decision at all.

    Output JSON: {status, pin, config_version, reversal_as_proposal,
    findings: [...]} with per-finding positions/pointers. With --write the
    gate records `policy_pin`, `policy_config_version`, `policy_conformance`
    into the plan's frontmatter THROUGH the writer's fail-closed validation
    (a plan the schema refuses is left untouched). The gate writes NOTHING to
    any policy hub — with --write it touches exactly one file: the plan.
    """
    try:
        plan_text = open(args.plan, encoding="utf-8").read()
    except OSError as e:
        sys.stderr.write(f"error: cannot read plan {args.plan!r}: {e}\n")
        return 2
    fields, body, fm_errors = split_frontmatter(plan_text)
    if fm_errors or not fields:
        _report(fm_errors or [("(frontmatter)", "no frontmatter fields")])
        return REFUSED
    try:
        surface_text = open(args.surface, encoding="utf-8").read()
    except OSError as e:
        sys.stderr.write(f"error: cannot read policy surface {args.surface!r}: {e}\n")
        return 2

    ps = _load_mod("policy_subjects.py")
    pin, surface_lines = ps.parse_policy_surface(surface_text)
    if not pin:
        sys.stderr.write(f"error: policy surface {args.surface!r} carries no "
                         "`pin:` line — the gate validates against a pinned "
                         "result only\n")
        return 2

    rf = _load_mod("render-frontmatter.py")
    cfg_args = argparse.Namespace(config_json=args.config_json, root=args.root,
                                  global_config=None, repo_config=None)
    try:
        cfg = rf.load_config(cfg_args)
    except Exception as e:
        sys.stderr.write(f"error: cannot resolve user config: {e}\n")
        return 2
    config_version = args.config_version or hashlib.sha256(
        json.dumps(cfg, sort_keys=True).encode("utf-8")).hexdigest()[:12]

    surface_files = {sl["file"] for sl in surface_lines}
    by_file_line = {(sl["file"], sl["line"]): sl["text"] for sl in surface_lines}
    file_shas = {sl["file"]: sl["sha"] for sl in surface_lines}
    refs = _plan_policy_refs(fields, body, surface_files)
    policy_seeded = _truthy(fields.get("policy_seeded", ""))

    findings = []
    status = None
    reversal = False

    # 1. Conflict: the shared detector, surface vs authoritative config.
    conflicts = ps.detect_conflicts(surface_lines, cfg, config_version)
    if conflicts:
        blocks = _staging_blocks(args.staging) if args.staging else []
        unresolved = []
        for c in conflicts:
            if _staging_covers(blocks, c["subject"]):
                findings.append({
                    "kind": "reversal-as-proposal", "subject": c["subject"]["id"],
                    "positions": [c["policy"], c["config"]],
                    "note": "the reversing decision has its staging-candidate "
                            "block — conformant only as a proposed policy "
                            "change, never as current policy",
                })
            else:
                unresolved.append(c)
                findings.append({
                    "kind": "conflict", "subject": c["subject"]["id"],
                    "positions": [c["policy"], c["config"]],
                    "note": f"served policy and the authoritative config "
                            f"disagree on {c['subject']['label']}",
                })
        if unresolved:
            status = "conflict"
        else:
            status = "conformant"
            reversal = True

    # 2. Stale: pin moved AND a referenced consulted line changed.
    recorded_pin = fields.get("policy_pin", "")
    pin_moved = bool(recorded_pin and recorded_pin != pin) or any(
        r["sha"] != file_shas.get(r["file"]) for r in refs)
    if status is None and pin_moved:
        for r in refs:
            ptr = f"{r['file']}:{r['line']}@{r['sha']}"
            cur = by_file_line.get((r["file"], r["line"]))
            if cur is None:
                findings.append({"kind": "stale", "pointer": ptr, "at": r["at"],
                                 "note": "the current surface no longer serves "
                                         "this line"})
            elif r["quote"] is not None:
                if r["quote"].strip() and r["quote"].strip() not in cur:
                    findings.append({"kind": "stale", "pointer": ptr,
                                     "at": r["at"], "current": cur.strip(),
                                     "recorded": r["quote"].strip(),
                                     "note": "the consulted line changed since "
                                             "the recorded quote"})
            else:
                findings.append({"kind": "stale", "pointer": ptr, "at": r["at"],
                                 "note": "pin moved and no quote is recorded "
                                         "for this referenced line — the "
                                         "mismatch counts"})
        if any(f["kind"] == "stale" for f in findings):
            status = "stale"

    # 3. Conformant (checked and clean) vs open (nothing the table can check).
    if status is None:
        checkable = []
        for r in refs:
            cur = by_file_line.get((r["file"], r["line"]), "")
            probe = r["quote"] if r["quote"] is not None else cur
            for subject in ps.COMPARABLE_SUBJECTS:
                if probe and subject["policy_line"].search(probe):
                    checkable.append((r, subject))
                    break
        if not policy_seeded and not refs:
            status = "open"
            findings.append({"kind": "no-policy-decisions",
                             "note": "the plan records no policy-seeded "
                                     "decision — nothing to check"})
        elif checkable:
            status = "conformant"
            for r, subject in checkable:
                findings.append({
                    "kind": "checked-clean", "subject": subject["id"],
                    "pointer": f"{r['file']}:{r['line']}@{r['sha']}",
                    "at": r["at"]})
        else:
            status = "open"
            for r in refs:
                findings.append({
                    "kind": "unclassifiable",
                    "pointer": f"{r['file']}:{r['line']}@{r['sha']}",
                    "at": r["at"],
                    "note": "no comparable subject classifies this consulted "
                            "line — recorded open, not checked"})
            if not refs:
                findings.append({"kind": "unclassifiable",
                                 "note": "policy_seeded is set but the plan "
                                         "references no served policy line "
                                         "the comparable table can classify"})

    out = {"status": status, "pin": pin, "config_version": config_version,
           "reversal_as_proposal": reversal, "findings": findings}

    if args.write:
        # Record the trio in place, THROUGH the writer's fail-closed schema:
        # strip any prior conformance keys, insert the fresh ones before the
        # closing `---` (deterministic), validate, and only then write. The
        # plan file is the ONLY thing the gate ever writes.
        lines = plan_text.split("\n")
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
        head = [ln for ln in lines[1:end]
                if not re.match(r"^(policy_pin|policy_config_version|"
                                r"policy_conformance)\s*:", ln)]
        head += [f"policy_pin: {pin}",
                 f"policy_config_version: {config_version}",
                 f"policy_conformance: {status}"]
        new_text = "\n".join(["---"] + head + lines[end:])
        slug = fields.get("slug") or os.path.splitext(
            os.path.basename(args.plan))[0]
        defects = list(validate_plan(new_text,
                                     os.path.join(PLAN_DIR, f"{slug}.md")))
        if defects:
            _report(defects)
            return REFUSED
        with open(args.plan, "w", encoding="utf-8") as fh:
            fh.write(new_text)
        out["written"] = args.plan

    print(json.dumps(out, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ROOT_HELP = ("host-repo root (default: git top-level of cwd; errors outside "
                 "a git repo)")
    p.add_argument("--root", help=ROOT_HELP)
    root_parent = argparse.ArgumentParser(add_help=False)
    root_parent.add_argument("--root", default=argparse.SUPPRESS, help=ROOT_HELP)
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("validate", parents=[root_parent])
    sp.add_argument("plan", nargs="?", default="-")
    sp.add_argument("--path", required=True,
                    help="the destination path the plan is validated for")

    sp = sub.add_parser("dest", parents=[root_parent])
    sp.add_argument("--slug", required=True)

    sp = sub.add_parser("write", parents=[root_parent])
    sp.add_argument("plan", nargs="?", default="-")
    sp.add_argument("--slug", required=True)

    sub.add_parser("consult", parents=[root_parent])

    sp = sub.add_parser("differential-context", parents=[root_parent])
    sp.add_argument("--project", help="the run's project (related.projects); "
                    "prior plans whose pin names this source repo share it. "
                    "Default: the host repo's basename.")

    sp = sub.add_parser("conformance", parents=[root_parent])
    sp.add_argument("--plan", required=True, help="the plan file to validate")
    sp.add_argument("--surface", required=True,
                    help="the policy reader's `read` output (pin line + "
                         "line-numbered files) the run consulted")
    sp.add_argument("--config-json",
                    help="resolved config as JSON (FILE or - for stdin); "
                         "default: resolve from --root")
    sp.add_argument("--config-version",
                    help="the cited configVersion (default: a sha256 prefix "
                         "of the resolved config)")
    sp.add_argument("--staging",
                    help="the run's staging-candidates.md — a reversal with "
                         "its staging block is conformant as a proposed "
                         "policy change")
    sp.add_argument("--write", action="store_true",
                    help="record policy_pin/policy_config_version/"
                         "policy_conformance into the plan (fail-closed)")

    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    return {"validate": cmd_validate, "dest": cmd_dest,
            "write": cmd_write, "consult": cmd_consult,
            "differential-context": cmd_differential_context,
            "conformance": cmd_conformance}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
