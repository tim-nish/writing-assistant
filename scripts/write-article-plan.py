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
  OPTIONAL  audience, audience_id, policy_seeded, seed (required iff policy_seeded), relates
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
"""

import argparse
import importlib.util
import json
import os
import re
import sys

PLAN_KIND = "article-plan"
PLAN_DIR = "plans"

REFUSED = 4  # schema violation — nothing is written

REQUIRED_KEYS = ("kind", "slug", "intent", "claim", "status", "run_id", "pin")
OPTIONAL_KEYS = ("audience", "audience_id", "policy_seeded", "seed", "relates")
PLAN_STATUSES = ("outlined", "drafted", "superseded")

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
            "policy_seeded": fields.get("policy_seeded")}


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
    print(json.dumps({"plans": summaries, "articles_repo": repo,
                      "degraded": None}))
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

    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    return {"validate": cmd_validate, "dest": cmd_dest,
            "write": cmd_write, "consult": cmd_consult}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
