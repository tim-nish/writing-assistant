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
#
# Invariant: every framework's list contains q2 (significance — the claim the
# article exists to communicate) and q5 (audience). They are the review skill's
# intent anchors: the cold-read pass compares its reader answers against the
# journal's q2/q5 entries, so a framework that never asks them would make that
# comparison unexecutable (issue #120).
FRAMEWORK_PRIORITY = {
    "F1": ["q2", "q4", "q3", "q5", "q1"],   # evidence GATE, decision cost, limits, audience, surprise
    "F2": ["q1", "q4", "q3", "q2", "q5"],   # what-happened, mechanism/cost, applicability, significance, audience
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


# Stage-3 sidecar provenance map (Story 11.1; `docs/harness-architecture.md` D1).
# Every draft sentence belongs to exactly one provenance class:
#   sourced   — asserts something traceable to ONE fact-sheet entry or interview
#               answer; carries that pointer;
#   derived   — a synthesis over >=2 named sourced claims (compress / combine /
#               restate); inherits ALL their pointers;
#   narration — asserts nothing checkable (falsifiability test, D2); no pointer;
#   verify    — an inferred claim beyond sources/derivation; carries an inline
#               [VERIFY] marker in the draft body (no pointer in the map).
# The map lives in the run workspace, never inline, so the draft body stays clean
# for variants and review. This command parses and STRUCTURALLY validates the map
# (pointer-count rules per class); the independent `verify-provenance` check
# (Story 11.2) adds the semantic layer (falsifiability + the six forbidden
# derivation categories).
PROV_CLASSES = ("sourced", "derived", "narration", "verify")
PROV_LINE = re.compile(
    r"^(?P<pos>\S+):\s*(?P<cls>sourced|derived|narration|verify)"
    r"(?:\s*<-\s*(?P<ptrs>.+?))?\s*$"
)


def parse_provenance_map(text):
    """Parse the sidecar map text into [(pos, cls, [pointers])], raising
    ValueError on a malformed line or a class name outside the closed set."""
    entries = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = PROV_LINE.match(line)
        if not m:
            raise ValueError(f"line {lineno}: malformed provenance entry: {raw!r}")
        ptrs = [p.strip() for p in (m.group("ptrs") or "").split(",") if p.strip()]
        entries.append((m.group("pos"), m.group("cls"), ptrs))
    return entries


def cmd_provenance(args):
    """Stage 3: parse and structurally validate the sidecar provenance map
    (Story 11.1). Enforces the per-class pointer contract:

      - sourced   → exactly-traceable: >=1 pointer;
      - derived   → synthesis over >=2 named sourced claims: >=2 pointers;
      - narration → asserts nothing: 0 pointers;
      - verify    → inferred, marked inline in the draft: 0 pointers here.

    --count prints the per-class tallies (dimension-4 quote-density reads these).
    A structural violation exits non-zero; the semantic checks live in
    `verify-provenance` (Story 11.2).
    """
    text = sys.stdin.read() if args.map == "-" else open(args.map, encoding="utf-8").read()
    try:
        entries = parse_provenance_map(text)
    except ValueError as e:
        sys.stderr.write(f"error: {e}\n")
        return 1

    tally = {c: 0 for c in PROV_CLASSES}
    problems = []
    for pos, cls, ptrs in entries:
        tally[cls] += 1
        if cls == "sourced" and len(ptrs) < 1:
            problems.append(f"{pos}: sourced claim carries no pointer")
        elif cls == "derived" and len(ptrs) < 2:
            problems.append(f"{pos}: derived claim must inherit >=2 pointers (got {len(ptrs)})")
        elif cls in ("narration", "verify") and ptrs:
            problems.append(f"{pos}: {cls} must carry no pointer (got {len(ptrs)})")

    if args.count:
        print(json.dumps(tally))
        return 0
    if problems:
        sys.stderr.write("provenance map INVALID:\n")
        for p in problems:
            sys.stderr.write(f"  {p}\n")
        return 1
    print(f"provenance map OK: {json.dumps(tally)}")
    return 0


# Stage-3→4 quality gate (Story 11.4; `docs/harness-architecture.md` D3–D5).
# Dimension 4 (readability mechanics) is checked here MECHANICALLY (zero tokens);
# dimensions 1–3 are judged by one single-pass cheap-tier rubric judge whose
# pass/fail verdicts this command consumes. The gate is a stage-progression
# PRECONDITION, not an advisory finding: any failing dimension blocks stage 4.
# Conservative v1 thresholds live in the rubric asset (skills/draft-article/
# quality-rubric.md); mirror them here.
QG_MEAN_SENTENCE_WORDS = 30
QG_LONG_SENTENCE_WORDS = 40
QG_LONG_SENTENCE_FRACTION = 0.25
QG_PARA_MAX_SENTENCES = 8
QG_PARA_MAX_WORDS = 160
QG_STITCH_SOURCED_FRACTION = 0.70
_SENT_SPLIT = re.compile(r"(?<=[.!?])\s+")


def _draft_body(text):
    """Strip YAML frontmatter and heading lines; return prose paragraphs."""
    if text.startswith("---"):
        parts = text.split("\n---", 1)
        if len(parts) == 2:
            text = parts[1]
    lines = [ln for ln in text.splitlines() if not ln.lstrip().startswith("#")]
    blocks, cur = [], []
    for ln in lines:
        if ln.strip() == "":
            if cur:
                blocks.append(" ".join(cur)); cur = []
        else:
            cur.append(ln.strip())
    if cur:
        blocks.append(" ".join(cur))
    return blocks


def _sentences(paragraph):
    return [s for s in _SENT_SPLIT.split(paragraph.strip()) if s.strip()]


def _dimension4(draft_text, prov_entries):
    """Mechanical readability-mechanics checks; returns a list of failing
    locations (empty = pass)."""
    fails = []
    paragraphs = _draft_body(draft_text)
    sentences = [s for p in paragraphs for s in _sentences(p)]
    if sentences:
        lens = [len(s.split()) for s in sentences]
        mean = sum(lens) / len(lens)
        if mean > QG_MEAN_SENTENCE_WORDS:
            fails.append(f"sentence length: mean {mean:.0f} words > {QG_MEAN_SENTENCE_WORDS}")
        long = sum(1 for n in lens if n > QG_LONG_SENTENCE_WORDS)
        if long / len(lens) > QG_LONG_SENTENCE_FRACTION:
            fails.append(f"sentence length: {long}/{len(lens)} sentences over {QG_LONG_SENTENCE_WORDS} words")
    for i, p in enumerate(paragraphs):
        ns, nw = len(_sentences(p)), len(p.split())
        if ns > QG_PARA_MAX_SENTENCES or nw > QG_PARA_MAX_WORDS:
            fails.append(f"paragraph {i + 1}: {ns} sentences / {nw} words (wall of text)")
    if "## " not in draft_text and "\n#" not in draft_text:
        fails.append("heading density: no section headings")
    # Stitched-fact-sheet signature: wall-to-wall sourced claims, no
    # derived/narration connective tissue (reads the provenance map).
    if prov_entries:
        classes = [c for _, c, _ in prov_entries]
        total = len(classes)
        sourced = classes.count("sourced")
        tissue = classes.count("derived") + classes.count("narration")
        if tissue == 0 and sourced > 0:
            fails.append("stitched fact sheet: all sourced claims, no derived/narration tissue")
        elif total and sourced / total > QG_STITCH_SOURCED_FRACTION and tissue == 0:
            fails.append(f"stitched fact sheet: {sourced}/{total} sourced, no connective tissue")
    return fails


def cmd_quality_gate(args):
    """Stage 3→4 quality gate (Story 11.4). Dimension 4 is mechanical here;
    dimensions 1–3 come from the single-pass judge's verdicts (--judge, a file of
    `dim1|dim2|dim3: pass|fail [locations]`). Emits a per-dimension verdict; a
    non-zero exit BLOCKS stage 4 (a precondition, not an advisory finding).
    """
    draft = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    prov_entries = []
    if args.map:
        try:
            prov_entries = parse_provenance_map(_read_text(args.map))
        except ValueError as e:
            sys.stderr.write(f"error: provenance map: {e}\n")
            return 2

    results = {}
    # Dimensions 1–3: judge verdicts.
    judged = {}
    if args.judge:
        for ln in _read_text(args.judge).splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            dim, _, rest = ln.partition(":")
            judged[dim.strip()] = rest.strip()
    for dim in ("dim1", "dim2", "dim3"):
        verdict = judged.get(dim, "")
        passed = verdict.lower().startswith("pass")
        results[dim] = ("pass" if passed else "fail",
                        "" if passed else (verdict[4:].strip(" :-") if verdict else "no judge verdict"))
    # Dimension 4: mechanical.
    d4 = _dimension4(draft, prov_entries)
    results["dim4"] = ("pass", "") if not d4 else ("fail", "; ".join(d4))

    failing = [d for d, (v, _) in results.items() if v == "fail"]
    out = {"gate": "quality", "pass": not failing,
           "dimensions": {d: {"verdict": v, "locations": loc} for d, (v, loc) in results.items()},
           "failing_dimensions": failing}
    print(json.dumps(out, indent=2))
    return 0 if not failing else 1


def _read_text(path):
    return sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()


def _load_json_state(path, label):
    """Read `path` (`-` == stdin) and parse it as JSON, raising SystemExit with a
    named, actionable message instead of an opaque traceback when the input is
    empty or malformed. An empty capture is the common case — a prior stage that
    produced no output piped into the next — so it gets its own clear diagnostic
    rather than a bare JSONDecodeError."""
    text = _read_text(path)
    if not text.strip():
        raise SystemExit(
            f"error: {label} produced no output (empty input from "
            f"{'stdin' if path == '-' else path}) — the prior stage wrote nothing"
        )
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise SystemExit(f"error: {label} is not valid JSON: {e}")


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
    state = _load_json_state(args.state, "stage-0 state capture")
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


# Stage-2 answer dispositions (Story 10.3; `docs/interview-architecture.md` D2).
# Each disposition maps deterministically to the provenance class the answer
# carries into stage 3, so the drafting stage never has to re-derive it:
#   - approved : the recommended answer is adopted VERBATIM and KEEPS its source
#                pointers → SOURCED provenance (grounds claims like a fact-sheet
#                entry);
#   - modified : the owner edited the recommendation → INTERVIEW provenance
#                (owner judgment on top of the grounding);
#   - replaced : the owner supplied their own bullet → INTERVIEW provenance;
#   - answered : an OPEN question answered with a free-text bullet → INTERVIEW;
#   - skipped  : unanswered — the engine records ONLY the disposition; the slot
#                effect is the framework's declared contract (Story 10.5),
#                resolved at stage 3, never by the interview engine.
DISPOSITION_PROVENANCE = {
    "approved": "sourced",
    "modified": "interview",
    "replaced": "interview",
    "answered": "interview",
    "skipped": None,
}


def _validate_answer(spec):
    """Validate one interview answer spec against the D2 disposition rules.

    Returns (record, None) when valid, or (None, reason) when not. `spec` is a
    dict with `id`, `disposition`, optional `text`, optional `pointers` — the
    same fields the single-answer flags carry. This is the shared core of both
    the single-answer and the batch paths so their rules can never diverge."""
    qid = spec.get("id")
    if not qid:
        return None, "missing `id` (the question this answer keys to)"
    disposition = spec.get("disposition")
    if disposition not in DISPOSITION_PROVENANCE:
        return None, (f"invalid disposition {disposition!r} "
                      f"(valid: {', '.join(DISPOSITION_PROVENANCE)})")
    provenance = DISPOSITION_PROVENANCE[disposition]
    text = (spec.get("text") or "").strip()
    pointers = list(spec.get("pointers") or [])

    if disposition == "skipped":
        if text or pointers:
            return None, ("a skipped answer records only the disposition (no text, no "
                          "pointers); its slot effect is the framework's (Story 10.5)")
    elif disposition == "approved":
        if not pointers:
            return None, ("an approved answer must inherit >=1 source pointer "
                          "(pass --pointer; it grounds sourced claims like a "
                          "fact-sheet entry)")
        if not text:
            return None, ("an approved answer must carry the adopted recommendation "
                          "text (pass --text)")
    else:  # modified / replaced / answered
        if not text:
            return None, f"a {disposition} answer must carry the owner's text (pass --text)"
        if pointers:
            return None, (f"a {disposition} answer is owner judgment (interview-sourced); "
                          "it carries no source pointers")

    return ({"id": qid, "disposition": disposition, "provenance": provenance,
             "answer": text or None, "pointers": pointers}, None)


def cmd_answer(args):
    """Stage 2: record interview answers with their disposition and the
    provenance class it implies (Story 10.3), enforcing the D2 rules so a
    malformed record cannot reach stage 3:

      - approved  → must carry >=1 inherited source pointer and the adopted text;
      - modified / replaced / answered → must carry owner text, no pointers
        (owner judgment is interview-sourced, not source-pointed);
      - skipped   → carries neither text nor pointers; only the disposition,
        its slot effect deferred to the framework (Story 10.5).

    Two forms share one validation core (`_validate_answer`):
      - single answer via the flags (--id/--disposition/--text/--pointer);
      - a batch via `--batch <file|->` (a JSON list of answer specs), validated
        in one pass that reports EVERY rejection at once rather than failing on
        the first — the round-trip cut of Story 13.6, so the interview does not
        pay one reject-and-retry cycle per bad answer.
    """
    if args.batch is not None:
        text = _read_text(args.batch)
        try:
            specs = json.loads(text)
        except json.JSONDecodeError as e:
            sys.stderr.write(f"error: --batch is not valid JSON: {e}\n")
            return 1
        if not isinstance(specs, list):
            sys.stderr.write("error: --batch must be a JSON list of answer specs\n")
            return 1
        records, rejects = [], []
        for i, spec in enumerate(specs):
            if not isinstance(spec, dict):
                rejects.append((i, "?", "answer spec must be a JSON object"))
                continue
            record, reason = _validate_answer(spec)
            if reason is None:
                records.append(record)
            else:
                rejects.append((i, spec.get("id", "?"), reason))
        if rejects:
            # One consolidated, actionable report — every problem, its id, and
            # the fix — instead of one reject per attempt.
            sys.stderr.write(f"{len(rejects)} of {len(specs)} answers rejected:\n")
            for i, qid, reason in rejects:
                sys.stderr.write(f"  [{i}] id={qid}: {reason}\n")
            return 1
        print(json.dumps(records, indent=2))
        return 0

    if not args.id or not args.disposition:
        sys.stderr.write("error: single-answer form needs --id and --disposition "
                         "(or use --batch for a list)\n")
        return 2
    record, reason = _validate_answer(
        {"id": args.id, "disposition": args.disposition,
         "text": args.text, "pointers": args.pointer})
    if reason is not None:
        sys.stderr.write(f"error: {reason}\n")
        return 1
    print(json.dumps(record, indent=2))
    return 0


def cmd_journal(args):
    """Stage 2: assemble the interview journal — one entry per candidate question —
    from the triage (Story 10.2) and the recorded answers (Story 10.3), so a
    mis-asked or mis-suppressed question is attributable from run state rather
    than discovered mid-interview (Story 10.4; `docs/interview-architecture.md` D3).

    Merges what each side already recorded:
      - every ASKED question (recommended/open) → its survival rationale
        (`topic-absent` | `needs-owner-reraise` | `owner-judgment`), the
        recommendation's grounding pointers (when recommended), and the owner's
        disposition;
      - every SUPPRESSED question → the covering fact-sheet entries.

    The journal is written to the run workspace by the SKILL; this command emits
    it. It fails closed if an asked question has no recorded disposition — an
    unattributable interview is a contract violation, not a silent gap.
    """
    interview = _load_json_state(args.interview, "interview journal")
    triage = interview.get("triage")
    if triage is None:
        sys.stderr.write("error: interview JSON has no `triage` array (run `interview` first)\n")
        return 1

    answers = {}
    if args.answers:
        parsed = _load_json_state(args.answers, "answers batch")
        for a in (parsed if isinstance(parsed, list) else [parsed]):
            answers[a.get("id")] = a.get("disposition")

    entries = []
    for t in triage:
        qid = t["id"]
        if t["outcome"] == "suppressed":
            entries.append({"id": qid, "status": "suppressed",
                            "covered_by": t.get("covered_by", [])})
            continue
        disposition = answers.get(qid)
        if disposition is None:
            sys.stderr.write(f"error: asked question {qid} has no recorded disposition — "
                             "the interview is not attributable (Story 10.4)\n")
            return 1
        entry = {"id": qid, "status": "asked", "outcome": t["outcome"],
                 "rationale": t.get("rationale"), "disposition": disposition}
        if "grounding" in t:
            entry["grounding"] = t["grounding"]
        entries.append(entry)

    print(json.dumps({"stage": "interview", "journal": entries}, indent=2))
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
        # Use the validator's shared SOURCE grammar so consume can never diverge
        # from it (Story 13.8): a multi-line `quote` range that validate-fact-sheet
        # accepts must not be rejected here.
        if not vfs.source_form_ok(source, kind):
            sys.stderr.write(f"error: fact-sheet SOURCE {source!r} is not a valid pointer form for KIND {kind!r}: {e}\n")
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
    state, code = _run_state(args.framework, args.sources, args.root)
    if state is None:
        return code
    print(json.dumps(state, indent=2))
    return 0


# --- Durability: per-stage checkpoint + resume (Story 13.5) ------------------
# The pipeline's turn/compute budget is a real ceiling even though wall-clock is
# unconstrained (SPEC constraints, 2026-07-12). Each stage's output state already
# carries `next_stage`; persisting that state to the run workspace after a stage
# completes makes a re-invocation resume from the last completed stage instead of
# restarting — a turn-ceiling casualty is recoverable, not a total loss. The
# checkpoint file IS the stage state, so writing it twice is idempotent and
# resuming never re-runs a completed stage (next_stage points past it).

CHECKPOINT_FILE = "checkpoint.json"


def _checkpoint_path(ws):
    return os.path.join(ws, CHECKPOINT_FILE)


def cmd_checkpoint(args):
    """Persist a completed stage's output state to `<ws>/checkpoint.json` so the
    run can resume from `next_stage`. Idempotent: re-writing the same stage's
    state yields an identical file. The write is atomic (temp + os.replace) so an
    interrupted write never leaves a half-written checkpoint to resume from."""
    if not os.path.isdir(args.ws):
        sys.stderr.write(f"error: run workspace does not exist: {args.ws}\n")
        return 1
    text = _read_text(args.state)
    try:
        state = json.loads(text)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: checkpoint state is not valid JSON: {e}\n")
        return 1
    if not isinstance(state, dict):
        sys.stderr.write("error: checkpoint state must be a JSON object\n")
        return 1
    if "next_stage" not in state:
        sys.stderr.write(
            "error: checkpoint state has no `next_stage` — pass a stage's output "
            "state (start/consume/interview/...), which records where to resume\n")
        return 1
    path = _checkpoint_path(args.ws)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, path)
    print(f"checkpoint: next_stage={state['next_stage']} -> {path}")
    return 0


def cmd_resume(args):
    """Report where to resume a run from its workspace checkpoint. Prints a JSON
    object: `{"resumed": true, ...state}` when a checkpoint exists (resume from
    its `next_stage`), or `{"resumed": false, "next_stage": "harvest"}` when none
    exists yet (a fresh run starts at stage 1)."""
    if not os.path.isdir(args.ws):
        sys.stderr.write(f"error: run workspace does not exist: {args.ws}\n")
        return 1
    path = _checkpoint_path(args.ws)
    if not os.path.isfile(path):
        print(json.dumps({"resumed": False, "next_stage": "harvest"}, indent=2))
        return 0
    with open(path, encoding="utf-8") as f:
        state = json.load(f)
    out = {"resumed": True}
    out.update(state)
    print(json.dumps(out, indent=2))
    return 0


# A completed run's final checkpoint carries next_stage == DONE_STAGE so
# `autostart` never resumes it (Story 13.12).
DONE_STAGE = "done"


def _autostart(root):
    """Core of automatic resume (Story 13.12): return the workspace to use and
    where to start — resuming the newest in-progress run (checkpoint next_stage
    != done), or minting a fresh run when none is in progress. Shared by the
    `autostart` and `stage0` commands."""
    rp = _load("resolve-paths.py")
    base = rp.runs_dir(root)
    if os.path.isdir(base):
        # Run ids are timestamp-based, so reverse-lexicographic == newest-first.
        for run_id in sorted(os.listdir(base), reverse=True):
            cp = os.path.join(base, run_id, CHECKPOINT_FILE)
            if not os.path.isfile(cp):
                continue
            try:
                with open(cp, encoding="utf-8") as f:
                    state = json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
            if state.get("next_stage") and state["next_stage"] != DONE_STAGE:
                out = {"resumed": True, "ws": os.path.join(base, run_id), "run_id": run_id}
                out.update(state)
                return out
    # No in-progress run — start fresh (this is the AC4 no-false-resume path).
    ws = rp.new_run(root)
    return {"resumed": False, "ws": ws, "run_id": os.path.basename(ws), "next_stage": "harvest"}


def cmd_autostart(args):
    """Stage 0: automatic resume (Story 13.12). Resumption is the DEFAULT, not an
    agent choice — so instead of always minting a new run, find the newest
    in-progress run for this repo (a run workspace whose checkpoint records a
    `next_stage` other than `done`) and resume it; if none exists, mint a fresh
    run at stage 1. Prints the workspace to use and where to start:
      {"resumed": true,  "ws": …, "run_id": …, "next_stage": …}  # continue here
      {"resumed": false, "ws": …, "run_id": …, "next_stage": "harvest"}  # new run
    A large draft completing across several invocations is the normal model."""
    rp = _load("resolve-paths.py")
    print(json.dumps(_autostart(rp.host_root(args.root)), indent=2))
    return 0


def _entry_gate_ok(key, framework_file, root):
    """Evaluate the selected framework's ENTRY gate — the framework-selection
    precondition stated at the top of its framework file (F1: a tagged release,
    F1-project-introduction.md "GATE (entry)"). Returns (ok, message).

    Frameworks that declare no entry precondition pass. Enforcement is bound to
    the framework file's own text: it fires only while the file still states the
    gate, so this mirrors the spec rather than hardcoding a precondition the
    framework no longer claims. Checked here — before any framework file is read
    into the draft or a workspace is minted — so an unsatisfiable framework fails
    fast instead of forcing a wasted mid-pipeline switch (Story 13.19)."""
    try:
        with open(os.path.join(plugin_root(), framework_file), encoding="utf-8") as f:
            head = f.read(2000)
    except OSError:
        return True, ""
    # F1 is the only framework that currently declares a machine-checkable entry
    # precondition ("GATE (entry) — ... the project has a tagged release ...").
    if key == "f1" and "GATE (entry)" in head and "tagged release" in head:
        try:
            r = subprocess.run(["git", "tag"], cwd=(root or None),
                               capture_output=True, text=True)
            has_tag = r.returncode == 0 and r.stdout.strip() != ""
        except OSError:
            has_tag = False
        if not has_tag:
            return False, (
                "framework F1 (project introduction) has an entry GATE: the "
                "project must have a tagged release (or an equivalent shipped "
                "artifact), and this repository has no git tags — F1's "
                "precondition is unmet before any drafting begins.\n"
                "Choose a framework without a release precondition: "
                "F2 (engineering lessons), F3 (evaluation methodology), or "
                "F4 (research survey).")
    return True, ""


def _run_state(framework, sources, root=None):
    """Build the stage-0 run-state (framework + classified sources), or return
    (None, exit_code) on a framework error — shared by `start` and `stage0`."""
    key = framework.lower()
    if key not in FRAMEWORKS:
        sys.stderr.write(
            f"error: invalid framework {framework!r}. "
            f"Valid frameworks: F1, F2, F3, F4. Nothing started.\n")
        return None, 2
    framework_file = os.path.join("skills", "draft-article", "frameworks", FRAMEWORKS[key])
    if not os.path.isfile(os.path.join(plugin_root(), framework_file)):
        sys.stderr.write(f"error: framework asset missing: {framework_file}\n")
        return None, 1
    gate_ok, gate_msg = _entry_gate_ok(key, framework_file, root)
    if not gate_ok:
        sys.stderr.write(f"error: {gate_msg}\nNothing started.\n")
        return None, 2
    return {
        "next_stage": "harvest",
        "framework": key.upper(),
        "framework_file": framework_file,
        "sources_raw": list(sources),
        "sources": [{"value": t, "form": classify(t)} for t in sources],
    }, 0


def cmd_stage0(args):
    """Story 13.13: fold the whole of Stage 0 into ONE invocation instead of
    three — configuration validation (CAP-5), framework check, and workspace
    autostart (Story 13.12). The agent pays one round-trip, not three, so a run
    makes progress per turn instead of exhausting the budget on orchestration.

    Halts (non-zero) with `validate-config.py`'s exact per-key report on a bad
    config (delegated verbatim, so diagnostics never diverge); a bad framework
    halts before any workspace is minted. On success prints a combined JSON:
      {"config_ok": true, "run_state": {…}, "resumed": …, "ws": …, "next_stage": …}
    """
    here = os.path.dirname(os.path.realpath(__file__))
    # 1. Config validation — delegate verbatim (same report, same exit code).
    cmd = [sys.executable, os.path.join(here, "validate-config.py")]
    if args.root:
        cmd += ["--root", args.root]
    rc = subprocess.run(cmd).returncode
    if rc != 0:
        return rc
    # 2. Framework check + entry-gate precondition (before minting a workspace).
    run_state, code = _run_state(args.framework, args.sources, args.root)
    if run_state is None:
        return code
    # 3. Workspace autostart (mint or resume).
    rp = _load("resolve-paths.py")
    out = {"config_ok": True, "run_state": run_state}
    out.update(_autostart(rp.host_root(args.root)))
    print(json.dumps(out, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("start")
    sp.add_argument("framework")
    sp.add_argument("sources", nargs="*")
    sp.add_argument("--root", help="host-repo root, for the framework entry-gate check "
                                   "(default: cwd; e.g. F1 requires a tagged release)")
    sp = sub.add_parser("consume")
    sp.add_argument("doc", nargs="?", default="-", help="harvest output document, or - for stdin")
    sp = sub.add_parser("checkpoint", help="persist a completed stage's state to <ws>/checkpoint.json (Story 13.5)")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS) to checkpoint into")
    sp.add_argument("state", nargs="?", default="-", help="the stage's output state JSON, or - for stdin")
    sp = sub.add_parser("resume", help="report where to resume a run from its workspace checkpoint (Story 13.5)")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS) to resume")
    sp = sub.add_parser("autostart", help="auto-resume the newest in-progress run, else mint a fresh one (Story 13.12)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp = sub.add_parser("stage0", help="fold Stage 0 into one call: config validation + framework + autostart (Story 13.13)")
    sp.add_argument("framework")
    sp.add_argument("sources", nargs="*")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp = sub.add_parser("interview")
    sp.add_argument("--framework", required=True)
    sp.add_argument("state", nargs="?", default="-", help="stage-1 pipeline state JSON, or - for stdin")
    sp = sub.add_parser("answer")
    sp.add_argument("--id", help="the question id this answer keys to (single-answer form)")
    sp.add_argument("--disposition",
                    help="approved | modified | replaced | answered | skipped (single-answer form)")
    sp.add_argument("--text", help="the answer text (adopted recommendation, or owner's bullet)")
    sp.add_argument("--pointer", action="append",
                    help="inherited source pointer (approved answers only; repeatable)")
    sp.add_argument("--batch", help="validate a JSON list of answer specs in one pass "
                                    "(FILE or - for stdin); reports every rejection at once")
    sp = sub.add_parser("journal")
    sp.add_argument("--interview", required=True, help="the `interview` output JSON (carries triage), or - for stdin")
    sp.add_argument("--answers", help="recorded answer records (JSON list), or - for stdin")
    sp = sub.add_parser("provenance")
    sp.add_argument("--map", default="-", help="the sidecar provenance map, or - for stdin")
    sp.add_argument("--count", action="store_true", help="print per-class tallies as JSON")
    sp = sub.add_parser("quality-gate")
    sp.add_argument("--draft", default="-", help="the filled draft, or - for stdin")
    sp.add_argument("--map", help="the sidecar provenance map (for the stitched-fact-sheet check)")
    sp.add_argument("--judge", help="rubric judge verdicts for dims 1-3: `dimN: pass|fail [locations]` per line")
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
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--global-config")
    sp.add_argument("--repo-config")
    sp.add_argument("--out", help="output dir (default: resolved output.drafts)")
    sp.add_argument("--dry-run", action="store_true", help="do not write files; just report")
    args = p.parse_args(argv)
    return {
        "start": cmd_start, "consume": cmd_consume, "interview": cmd_interview,
        "checkpoint": cmd_checkpoint, "resume": cmd_resume, "autostart": cmd_autostart,
        "stage0": cmd_stage0,
        "answer": cmd_answer, "journal": cmd_journal, "provenance": cmd_provenance,
        "quality-gate": cmd_quality_gate,
        "verify-markers": cmd_verify_markers, "verify": cmd_verify, "reroute": cmd_reroute,
        "variants": cmd_variants,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
