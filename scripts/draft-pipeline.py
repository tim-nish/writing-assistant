#!/usr/bin/env python3
"""Draft-article pipeline — stage 0 (invocation), Story 4.1.

`draft article <framework> from <sources>` starts the harvest-to-variant flow.
This helper does the mechanical part of stage 0: validate the framework against
the closed allowlist, classify each source token (path / glob / commit-range),
and emit a run-state record that stage 1 (harvest) consumes unmodified.

  start <FRAMEWORK> [SOURCE ...]

  * FRAMEWORK ∈ {F1, F2, F3, F4} (case-insensitive). Anything else is rejected
    with the valid set, a non-zero exit, and NO run-state emitted — no work
    begins, no partial state.
  * Each SOURCE is classified, with this precedence (disambiguation is explicit,
    not assumed):
      1. glob         — contains a glob metacharacter (* ? [ ])
      2. commit-range — `A..B` / `A...B` of ref-like parts, not a relative path
      3. path         — anything else (prefix a literal path with ./ to force it)
  * On success, prints the run-state JSON (framework, framework file, the raw
    sources verbatim, and their classification) and next_stage = harvest.

The recorded sources are a SELECTION for harvest, never a scope widener: stage 1
enumerates the writing-sources-declared files and INTERSECTS this selection, so
an undeclared path passed here cannot expand what gets read.
"""

import argparse
import json
import os
import re
import subprocess
import sys

FRAMEWORKS = {
    "f1": "F1-project-introduction.md",
    "f2": "F2-engineering-lessons.md",
    "f3": "F3-evaluation-methodology.md",
    "f4": "F4-research-survey.md",
}
GLOB_RE = re.compile(r"[*?\[\]{}]")
RANGE_RE = re.compile(r"^[A-Za-z0-9_.\-~^@]+\.\.\.?[A-Za-z0-9_.\-~^@/]+$")


def classify(token):
    if GLOB_RE.search(token):
        return "glob"
    # a relative/absolute path is never a commit-range, even with `..` in it
    if not token.startswith(("./", "../", "/")) and RANGE_RE.match(token) and ".." in token:
        return "commit-range"
    return "path"


def plugin_root():
    return os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def _load(name):
    import importlib.util
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(name.replace("-", "_").replace(".py", ""),
                                                  os.path.join(here, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Stage-2 gap-interview question bank (from pipeline-stages.md). Each question
# has a topic aligned with the NEEDS-OWNER topics and a synonym-rich `covers`
# set: if a fact-sheet claim already contains that content, the question is
# redundant (semantic de-dup, not literal-string match) and is suppressed unless
# a NEEDS-OWNER gap re-raises it.
QUESTION_BANK = {
    "q1": {"text": "What surprised you most while building this?", "topic": "surprise",
           "covers": ["surprise", "surprising", "unexpected", "caught us off guard", "to our shock"]},
    "q2": {"text": "Which single result or number matters most, and why that one?", "topic": "significance",
           "covers": ["most important result", "headline number", "key result", "matters most",
                      "flagship metric", "primary metric", "the result that counts"]},
    "q3": {"text": "What would you warn a reader about before they adopt this?", "topic": "warning",
           "covers": ["warning", "caveat", "caution", "pitfall", "limitation", "gotcha", "watch out", "do not use"]},
    "q4": {"text": "What did this decision cost you — what did you give up?", "topic": "tradeoff",
           "covers": ["tradeoff", "trade-off", "cost us", "gave up", "sacrificed", "at the expense of"]},
    "q5": {"text": "Who exactly is this article for, and what should they do after reading?", "topic": "audience",
           "covers": ["intended audience", "written for", "target reader", "this is for", "aimed at", "readers are"]},
    "q6": {"text": "What opinion in this piece are you willing to defend in comments?", "topic": "opinion",
           "covers": ["our opinion", "we argue", "we believe", "hot take", "controversial", "we contend"]},
    "q7": {"text": "What would you do differently if starting over?", "topic": "retrospective",
           "covers": ["in hindsight", "would do differently", "if starting over", "lessons for next time"]},
}

# Per-framework question priority, ORDERED by that framework's GATE slots (not
# question-bank order) — so the same fact sheet yields a stable, framework-
# tailored interview and the ordering is the deterministic tie-break under the
# ≤5 cap.
FRAMEWORK_PRIORITY = {
    "F1": ["q2", "q4", "q3", "q5", "q1"],   # evidence GATE, decision cost, limits, audience, surprise
    "F2": ["q1", "q4", "q3", "q2", "q7"],   # what-happened, mechanism/cost, applicability, significance, retro
    "F3": ["q2", "q3", "q4", "q5", "q6"],   # what-it-caught, cannot-tell, tradeoff, audience, opinion
    "F4": ["q6", "q2", "q3", "q5", "q1"],   # my-take opinion, significance, warning, audience, surprise
}
QUESTION_BUDGET = 5

# Stage-3 `[VERIFY]` marker contract. The canonical marker is exactly
# `[VERIFY: <reason>]` — an inferred claim carries one naming WHY it is
# unverified. Stage 4 (resolve markers) and the lint (5.1) match this exact
# form, so the format is machine-detectable and non-negotiable.
VERIFY_CANDIDATE = re.compile(r"\[VERIFY\b[^\]]*\]", re.IGNORECASE)
VERIFY_CANONICAL = re.compile(r"^\[VERIFY: [^\]]+\]$")

# Stage-4 rewrite budget (Story 4.5). The verification pass allows ONE rewrite
# per section; a section needing more than that routes back into a new interview
# question instead of open-ended editing (SPEC-article-draft-pipeline constraint:
# "A section needing more than one rewrite routes back to a new interview
# question, never into open-ended editing.").
REWRITE_BUDGET = 1


def cmd_verify_markers(args):
    """Stage 3/4: validate the `[VERIFY: reason]` markers in a draft. Every
    VERIFY-shaped bracket must match the canonical form exactly; anything else
    (bare `[VERIFY]`, empty reason, wrong case, missing colon) is malformed.
    --count prints the number of well-formed markers (Stage 4 drives it to zero).
    """
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    candidates = VERIFY_CANDIDATE.findall(text)
    well = [c for c in candidates if VERIFY_CANONICAL.match(c)]
    malformed = [c for c in candidates if not VERIFY_CANONICAL.match(c)]

    if args.count:
        print(len(well))
        return 0
    for c in well:
        print(f"VALID     {c}")
    for c in malformed:
        print(f"MALFORMED {c}   (must be exactly `[VERIFY: <reason>]`)")
    print(f"\n{len(well)} well-formed, {len(malformed)} malformed.")
    return 1 if malformed else 0


def cmd_verify(args):
    """Stage 4: build the owner's verification worklist — one entry per
    well-formed `[VERIFY: reason]` marker, carrying its line and the reason so
    the owner resolves each to a source, a confirmation, or deletion. The pass
    is complete (next_stage = variants) only when zero markers remain; any
    malformed marker blocks the pass (Stage 3 must have produced canonical ones).
    """
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    worklist = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for m in VERIFY_CANDIDATE.finditer(line):
            frag = m.group(0)
            if not VERIFY_CANONICAL.match(frag):
                sys.stderr.write(
                    f"error: malformed marker at line {lineno}: {frag}   "
                    "(must be exactly `[VERIFY: <reason>]`; resolve Stage 3 first)\n"
                )
                return 1
            worklist.append({"line": lineno, "marker": frag,
                             "reason": frag[len("[VERIFY: "):-1]})
    remaining = len(worklist)
    out = {
        "stage": "verify",
        # The pass exits to Stage 5 only when every marker is resolved.
        "next_stage": "variants" if remaining == 0 else "verify",
        "remaining": remaining,
        "worklist": worklist,
    }
    print(json.dumps(out, indent=2))
    return 0


def cmd_reroute(args):
    """Stage 4 constraint: a section needing more than one rewrite routes back to
    a NEW interview question rather than open-ended editing. Given the rewrites
    already applied to a section, decide `edit` (the one allowed pass-time
    rewrite) or `reroute` — the latter emits a bounded interview question that
    re-enters Stage 2's answer capture instead of continuing to edit.
    """
    if args.rewrites < 0:
        sys.stderr.write("error: --rewrites must be >= 0\n")
        return 2
    if args.rewrites < REWRITE_BUDGET:
        out = {
            "stage": "verify",
            "section": args.section,
            "rewrites": args.rewrites,
            "decision": "edit",
            "remaining_edits": REWRITE_BUDGET - args.rewrites,
        }
    else:
        out = {
            "stage": "verify",
            "section": args.section,
            "rewrites": args.rewrites,
            "decision": "reroute",
            "next_stage": "interview",
            "reason": ("past the one allowed rewrite; route to a new interview "
                       "question, not open-ended editing"),
            "question": {
                "id": f"reroute:{args.section}",
                "text": (f"Section {args.section!r} still needs change after one "
                         "rewrite. In a bullet: what exactly should it say, and "
                         "what source or fact supports that?"),
                "from_reroute": True,
            },
        }
    print(json.dumps(out, indent=2))
    return 0


def _read_frontmatter(text):
    """Parse the leading `---` article frontmatter into a dict. Stdlib-only
    line surgery (host repos have no PyYAML): top-level `key: value` pairs, with
    `[a, b]` lists split and a folded `key: >` block collapsing its indented
    continuation lines. Returns (fields, body) — body is everything after the
    closing fence, verbatim (the full article text).
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise SystemExit("error: draft has no `---` frontmatter block")
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        raise SystemExit("error: draft frontmatter is not closed with `---`")

    fields = {}
    i = 1
    while i < end:
        line = lines[i]
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).strip()
        if val in (">", "|"):                       # folded/literal block
            block = []
            i += 1
            while i < end and (lines[i].startswith((" ", "\t")) or lines[i].strip() == ""):
                if lines[i].strip():
                    block.append(lines[i].strip())
                i += 1
            fields[key] = " ".join(block)
            continue
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            fields[key] = [t.strip().strip('"\'') for t in inner.split(",") if t.strip()]
        else:
            fields[key] = val.strip().strip('"\'')
        i += 1

    body = "\n".join(lines[end + 1:]).lstrip("\n")
    return fields, body


def _devto_variant(fields, body, variant_cfg):
    """dev.to (Forem) copy: full text, `canonical_url` placeholder pointing back
    at the site page. Tags are sanitized to Forem's alphanumeric rule (≤4)."""
    slug = fields.get("slug", "{slug}")
    base = variant_cfg.get("canonical_url_base", "{site_url}/articles")
    tags = []
    for t in fields.get("topics", []) or []:
        clean = re.sub(r"[^a-z0-9]", "", t.lower())
        if clean and clean not in tags:
            tags.append(clean)
    fm = [
        "---",
        f"title: {fields.get('title', '{title}')}",
        "published: false",
        f"description: {fields.get('summary', '')}",
        f"tags: {', '.join(tags[:4])}",
        f"canonical_url: {base}/{slug}",   # placeholder — owner confirms/repoints
        "---",
    ]
    return "\n".join(fm) + "\n\n" + body.rstrip() + "\n"


def _zenn_variant(fields, body, variant_cfg):
    """Zenn repo-sync copy: Zenn frontmatter, full body (Zenn is canonical via
    repo-sync). `emoji` is a placeholder the owner may change."""
    topics = [re.sub(r"[^a-z0-9]", "", t.lower()) for t in (fields.get("topics", []) or [])]
    topics = [t for t in topics if t][:5]
    fm = [
        "---",
        f'title: "{fields.get("title", "{title}")}"',
        'emoji: "📝"',                     # placeholder — owner may change
        'type: "tech"',
        "topics: [" + ", ".join(f'"{t}"' for t in topics) + "]",
        "published: false",
        "---",
    ]
    return "\n".join(fm) + "\n\n" + body.rstrip() + "\n"


VARIANT_BUILDERS = {"devto": _devto_variant, "zenn": _zenn_variant}


def _resolve_drafts_dir(root):
    """Resolve output.drafts via resolve-writing-sources.py (Story 1.3). Exit 3
    there means the location is undeclared — surface that, no silent default."""
    here = os.path.dirname(os.path.realpath(__file__))
    cmd = [sys.executable, os.path.join(here, "resolve-writing-sources.py")]
    if root:
        cmd += ["--root", root]
    cmd.append("draft-location")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode == 3:
        raise SystemExit("error: output.drafts is undeclared in writing-sources.yaml; "
                         "declare it (resolve-writing-sources.py set-draft-location) "
                         "or pass --out")
    if r.returncode != 0:
        raise SystemExit(r.stderr.strip() or "error: could not resolve output.drafts")
    return r.stdout.strip()


def cmd_variants(args):
    """Stage 5: emit platform-ready variants of a VERIFIED draft, per the
    article's language and the config canonical policy (never a hardcoded
    mapping). EN/canonical → a dev.to copy (full text, canonical_url
    placeholder); JA/external → a Zenn repo-sync copy (Zenn frontmatter). Each is
    written to the resolved output.drafts location (or --out).
    """
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()

    # Precondition: a verified draft carries zero well-formed [VERIFY] markers.
    unresolved = [c for c in VERIFY_CANDIDATE.findall(text) if VERIFY_CANONICAL.match(c)]
    if unresolved:
        sys.stderr.write(f"error: draft still has {len(unresolved)} unresolved [VERIFY] "
                         "marker(s); complete Stage 4 before emitting variants\n")
        return 1

    fields, body = _read_frontmatter(text)
    lang = fields.get("language")
    if not lang:
        sys.stderr.write("error: draft frontmatter has no `language`; cannot pick a variant policy\n")
        return 1

    # Config drives the mapping: which platforms, and their canonical policy.
    rf = _load("render-frontmatter.py")
    cfg_args = argparse.Namespace(config_json=args.config_json, root=args.root,
                                  global_config=args.global_config, repo_config=args.repo_config)
    cfg = rf.load_config(cfg_args)
    policy = cfg.get("syndication", {}).get("policy", {}).get(lang)
    if not policy:
        sys.stderr.write(f"error: no syndication.policy for language {lang!r} in config\n")
        return 1
    variant_params = cfg.get("syndication", {}).get("variants", {})

    slug = fields.get("slug") or "draft"
    out_dir = args.out if args.out else _resolve_drafts_dir(args.root)

    emitted = []
    for name in policy.get("variants", []):
        builder = VARIANT_BUILDERS.get(name)
        if not builder:
            sys.stderr.write(f"error: no builder for configured variant {name!r}\n")
            return 1
        content = builder(fields, body, variant_params.get(name, {}))
        path = os.path.join(out_dir, f"{slug}.{name}.md")
        if not args.dry_run:
            os.makedirs(out_dir, exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content)
        emitted.append({"platform": name, "path": path})

    out = {
        "stage": "variants",
        "next_stage": "review",           # draft exits into SPEC-article-review
        "language": lang,
        "mode": policy.get("mode"),
        "emitted": emitted,
        "written": not args.dry_run,
    }
    print(json.dumps(out, indent=2))
    return 0


def cmd_interview(args):
    """Stage 2: triage every candidate question against the harvest output
    (fact sheet + NEEDS-OWNER) into exactly one of three outcomes, then present
    the surviving (non-suppressed) ones, at most 5, prioritized by the
    framework's GATE slots with confirmed NEEDS-OWNER gaps first.

    Three-outcome triage (Story 10.2; `docs/interview-architecture.md` D1),
    reading NOTHING beyond the harvest output carried in the state:

      - suppressed  : a fact-sheet entry already covers the question's
                      information need (semantic de-dup) and no NEEDS-OWNER
                      gap re-raises it — the owner never sees it;
      - recommended : a NEEDS-OWNER entry re-raises the topic — always
                      recommended (confirm/deny the claim), grounded on that
                      entry (D1: re-raises are never `open`);
      - open        : neither — genuinely owner-only knowledge, answered as a
                      bullet.

    The recommended/open split here is the deterministic baseline the script
    can compute from harvest output alone; the SKILL's recommendation pass may
    additionally ground an `open` question from a fact-sheet owner-judgment
    entry and present it as recommended (rationale `owner-judgment`). Zero
    questions are asked when everything is covered — never padded.
    """
    framework = args.framework.upper()
    if framework not in FRAMEWORK_PRIORITY:
        sys.stderr.write(f"error: invalid framework {args.framework!r}. Valid: F1, F2, F3, F4.\n")
        return 2
    text = sys.stdin.read() if args.state == "-" else open(args.state, encoding="utf-8").read()
    state = json.loads(text)
    fact_sheet = state.get("fact_sheet", [])
    needs_owner = state.get("needs_owner", [])
    gap_topics = {n.get("topic") for n in needs_owner}

    def covering_entries(qid):
        """Fact-sheet entries whose claim contains one of the question's synonym
        keywords — the semantic (not literal) de-dup evidence."""
        kws = QUESTION_BANK[qid]["covers"]
        return [e.get("claim", "") for e in fact_sheet
                if any(kw in e.get("claim", "").lower() for kw in kws)]

    def grounding_for(topic):
        """NEEDS-OWNER candidates re-raising this topic — the recommended
        answer's grounding (confirm/deny)."""
        return [n.get("candidate", n.get("reason", "")) for n in needs_owner
                if n.get("topic") == topic]

    # Triage EVERY bank question (the journal, Story 10.4, records all of them),
    # walking the framework's GATE-slot order so the classification is stable.
    triage = []
    for qid in FRAMEWORK_PRIORITY[framework]:
        topic = QUESTION_BANK[qid]["topic"]
        is_gap = topic in gap_topics
        covers = covering_entries(qid)
        rec = {"id": qid, "text": QUESTION_BANK[qid]["text"], "topic": topic}
        if is_gap:
            rec.update(outcome="recommended", rationale="needs-owner-reraise",
                       grounding=grounding_for(topic))
        elif covers:
            rec.update(outcome="suppressed", covered_by=covers)
        else:
            rec.update(outcome="open", rationale="topic-absent")
        triage.append(rec)

    # Survivors = the non-suppressed questions. Confirmed gaps first (stable →
    # framework order preserved within each group), then hard-cap at ≤5.
    survivors = [r for r in triage if r["outcome"] != "suppressed"]
    survivors.sort(key=lambda r: 0 if r["outcome"] == "recommended" else 1)
    survivors = survivors[:QUESTION_BUDGET]

    questions = [{"id": r["id"], "text": r["text"], "topic": r["topic"],
                  "from_gap": r["outcome"] == "recommended", "outcome": r["outcome"],
                  "rationale": r["rationale"],
                  **({"grounding": r["grounding"]} if "grounding" in r else {})}
                 for r in survivors]
    out = {
        "stage": "interview",
        "next_stage": "fill",
        "framework": framework,
        "budget": QUESTION_BUDGET,
        "asked": len(questions),
        "questions": questions,
        "triage": triage,
    }
    print(json.dumps(out, indent=2))
    return 0


def cmd_consume(args):
    """Stage 1: consume harvest's output document (fact sheet + NEEDS-OWNER) into
    pipeline state — WITHOUT re-reading any source. Source pointers are carried
    verbatim; the harvest contract (KINDS, pointer forms, TOPICS) is imported
    from the Epic 3 validators so a schema change surfaces here, not silently.
    """
    # Lazy import: stage 0 stays independent of these.
    vfs = _load("validate-fact-sheet.py")
    vno = _load("validate-needs-owner.py")

    text = sys.stdin.read() if args.doc == "-" else open(args.doc, encoding="utf-8").read()
    fs_lines, no_lines, has_no = vno.split_sections(text)
    if not has_no:
        sys.stderr.write("error: harvest output has no `# NEEDS-OWNER` section (contract violation)\n")
        return 1

    fact_sheet = []
    for e in vno.entries(fs_lines):
        parts = [p.strip() for p in e.rsplit(" / ", 2)]
        if len(parts) != 3 or any(p == "" for p in parts):
            sys.stderr.write(f"error: malformed fact-sheet entry (want `CLAIM / SOURCE / KIND`): {e}\n")
            return 1
        claim, source, kind = parts
        if kind not in vfs.KINDS:
            sys.stderr.write(f"error: fact-sheet KIND {kind!r} outside the harvest contract: {e}\n")
            return 1
        if not (vfs.URL_RE.match(source) or vfs.SHA_RE.match(source) or vfs.FILEPIN_RE.match(source)):
            sys.stderr.write(f"error: fact-sheet SOURCE {source!r} is not a valid pointer form: {e}\n")
            return 1
        fact_sheet.append({"claim": claim, "source": source, "kind": kind})   # source verbatim

    needs_owner = []
    for e in vno.entries(no_lines):
        parts = [p.strip() for p in e.rsplit(" / ", 2)]
        if len(parts) != 3 or any(p == "" for p in parts):
            sys.stderr.write(f"error: malformed NEEDS-OWNER entry (want `CANDIDATE / REASON / TOPIC`): {e}\n")
            return 1
        candidate, reason, topic = parts
        if topic not in vno.TOPICS:
            sys.stderr.write(f"error: NEEDS-OWNER TOPIC {topic!r} outside the harvest contract: {e}\n")
            return 1
        needs_owner.append({"candidate": candidate, "reason": reason, "topic": topic})

    state = {
        "stage": "consume",
        "next_stage": "interview",          # NEEDS-OWNER threads into the gap interview (Story 4.3)
        "fact_sheet": fact_sheet,
        "needs_owner": needs_owner,
    }
    print(json.dumps(state, indent=2))
    return 0


def cmd_start(args):
    key = args.framework.lower()
    if key not in FRAMEWORKS:
        sys.stderr.write(
            f"error: invalid framework {args.framework!r}. "
            f"Valid frameworks: F1, F2, F3, F4. Nothing started.\n"
        )
        return 2
    framework_file = os.path.join("skills", "draft-article", "frameworks", FRAMEWORKS[key])
    if not os.path.isfile(os.path.join(plugin_root(), framework_file)):
        sys.stderr.write(f"error: framework asset missing: {framework_file}\n")
        return 1
    state = {
        "next_stage": "harvest",
        "framework": key.upper(),
        "framework_file": framework_file,
        "sources_raw": list(args.sources),
        "sources": [{"value": t, "form": classify(t)} for t in args.sources],
    }
    print(json.dumps(state, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("start")
    sp.add_argument("framework")
    sp.add_argument("sources", nargs="*")
    sp = sub.add_parser("consume")
    sp.add_argument("doc", nargs="?", default="-", help="harvest output document, or - for stdin")
    sp = sub.add_parser("interview")
    sp.add_argument("--framework", required=True)
    sp.add_argument("state", nargs="?", default="-", help="stage-1 pipeline state JSON, or - for stdin")
    sp = sub.add_parser("verify-markers")
    sp.add_argument("draft", nargs="?", default="-", help="draft file, or - for stdin")
    sp.add_argument("--count", action="store_true", help="print the count of well-formed markers")
    sp = sub.add_parser("verify")
    sp.add_argument("draft", nargs="?", default="-", help="filled draft, or - for stdin")
    sp = sub.add_parser("reroute")
    sp.add_argument("--rewrites", type=int, required=True,
                    help="rewrites already applied to this section")
    sp.add_argument("--section", default="?", help="section identifier (for the routed question)")
    sp = sub.add_parser("variants")
    sp.add_argument("draft", nargs="?", default="-", help="verified draft, or - for stdin")
    sp.add_argument("--config-json", help="resolved config as JSON (FILE or - for stdin)")
    sp.add_argument("--root")
    sp.add_argument("--global-config")
    sp.add_argument("--repo-config")
    sp.add_argument("--out", help="output dir (default: resolved output.drafts)")
    sp.add_argument("--dry-run", action="store_true", help="do not write files; just report")
    args = p.parse_args(argv)
    return {
        "start": cmd_start, "consume": cmd_consume, "interview": cmd_interview,
        "verify-markers": cmd_verify_markers, "verify": cmd_verify, "reroute": cmd_reroute,
        "variants": cmd_variants,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
